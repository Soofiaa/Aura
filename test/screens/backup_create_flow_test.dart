import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/screens/backup_create_flow.dart';
import 'package:aura/screens/backup_section.dart';

import '../support/fake_backup.dart';

/// CP5a: el flujo "Crear respaldo" extraido de BackupSection y su
/// proteccion contra doble toque, compartida si hay un BackupBusyScope
/// (MainNavigationScreen) e independiente si no. Datos y contrasenas
/// inventados.
void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  late AppDatabase db;
  late CycleRepository repo;
  late FakeBackupService backup;
  late FakeBackupFileGateway gateway;
  late FakeBackupReminderStore store;

  const secreto = 'mi casa es muy azul';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CycleRepository(db);
    backup = FakeBackupService(repo);
    gateway = FakeBackupFileGateway();
    store = FakeBackupReminderStore();
  });

  Widget seccion(Key key) => BackupSection(
        key: key,
        service: backup,
        gateway: gateway,
        reminderStore: store,
      );

  /// Dos secciones de respaldo, como Ajustes e Inicio en la app.
  Future<void> pumpDos(WidgetTester tester, {ValueNotifier<bool>? busy}) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await repo.markPeriodDays(['2026-05-01', '2026-05-02']);
    final cuerpo = Column(children: [
      seccion(const Key('a')),
      seccion(const Key('b')),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: busy == null
            ? cuerpo
            : BackupBusyScope(busy: busy, child: cuerpo),
      ),
    ));
    await tester.pumpAndSettle();
  }

  ListTile crearDe(WidgetTester tester, String key) =>
      tester.widget<ListTile>(find.descendant(
        of: find.byKey(Key(key)),
        matching: find.widgetWithText(ListTile, 'Crear respaldo'),
      ));

  /// Desde la seccion [key]: Compartir con contrasena, que queda esperando
  /// en exportGate (pantalla bloqueada por el progreso).
  Future<void> empezarCompartirProtegido(
      WidgetTester tester, String key) async {
    backup.exportGate = Completer<void>();
    await tester.tap(find.descendant(
      of: find.byKey(Key(key)),
      matching: find.text('Crear respaldo'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compartir'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('protect-password')), secreto);
    await tester.enterText(
        find.byKey(const ValueKey('protect-repeat')), secreto);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Proteger y continuar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Protegiendo tu respaldo…'), findsOneWidget);
  }

  testWidgets('con BackupBusyScope: mientras una crea, la otra queda '
      'deshabilitada; al terminar, las dos se habilitan', (tester) async {
    final busy = ValueNotifier<bool>(false);
    await pumpDos(tester, busy: busy);
    await empezarCompartirProtegido(tester, 'a');

    expect(busy.value, isTrue);
    expect(crearDe(tester, 'a').enabled, isFalse);
    expect(crearDe(tester, 'b').enabled, isFalse);

    backup.exportGate!.complete();
    await tester.pumpAndSettle();
    expect(busy.value, isFalse);
    expect(crearDe(tester, 'a').enabled, isTrue);
    expect(crearDe(tester, 'b').enabled, isTrue);
    expect(gateway.sharedFiles, hasLength(1));
    expect(store.recordCount, 1);
    await db.close();
  });

  testWidgets('sin BackupBusyScope: cada seccion tiene su propia proteccion',
      (tester) async {
    await pumpDos(tester);
    await empezarCompartirProtegido(tester, 'a');

    expect(crearDe(tester, 'a').enabled, isFalse);
    expect(crearDe(tester, 'b').enabled, isTrue);

    backup.exportGate!.complete();
    await tester.pumpAndSettle();
    expect(crearDe(tester, 'a').enabled, isTrue);
    await db.close();
  });

  testWidgets('tambien restaurar ocupa la proteccion compartida',
      (tester) async {
    final busy = ValueNotifier<bool>(false);
    final seleccion = Completer<void>();
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // El selector de archivos queda abierto (la usuaria aun no elige).
    final pick = FakeBackupFileGatewayConEspera(seleccion);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BackupBusyScope(
          busy: busy,
          child: Column(children: [
            BackupSection(
                key: const Key('a'),
                service: backup,
                gateway: pick,
                reminderStore: store),
            seccion(const Key('b')),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byKey(const Key('a')),
      matching: find.text('Restaurar un respaldo'),
    ));
    await tester.pump();
    expect(busy.value, isTrue);
    expect(crearDe(tester, 'b').enabled, isFalse);

    seleccion.complete();
    await tester.pumpAndSettle();
    expect(busy.value, isFalse);
    expect(crearDe(tester, 'b').enabled, isTrue);
    await db.close();
  });

  testWidgets('CreateBackupFlow.run no abre nada si ya hay una operacion',
      (tester) async {
    final busy = ValueNotifier<bool>(true);
    late BuildContext contexto;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        contexto = context;
        return const SizedBox();
      }),
    ));
    unawaited(CreateBackupFlow(
      service: backup,
      busy: busy,
      gateway: gateway,
      reminderStore: store,
    ).run(contexto));
    await tester.pumpAndSettle();
    expect(find.text('Tu respaldo tiene datos de salud'), findsNothing);
    expect(busy.value, isTrue);
    await db.close();
  });

  testWidgets('CreateBackupFlow.run: guardar sin contrasena anota y avisa '
      'sobre el contexto que recibe', (tester) async {
    final busy = ValueNotifier<bool>(false);
    late BuildContext contexto;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          contexto = context;
          return const SizedBox();
        }),
      ),
    ));
    unawaited(CreateBackupFlow(
      service: backup,
      busy: busy,
      gateway: gateway,
      reminderStore: store,
    ).run(contexto));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar en el teléfono'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar sin contraseña'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog).last,
      matching: find.text('Continuar sin contraseña'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Respaldo guardado.'), findsOneWidget);
    expect(gateway.savedFileName, 'aura_respaldo_2026-10-04.json');
    expect(store.recordCount, 1);
    expect(backup.preMigrationCopyDeleteCount, 1);
    expect(busy.value, isFalse);
    await db.close();
  });
}

/// Gateway cuyo selector de archivos no responde hasta [espera] (y
/// entonces "cancela").
class FakeBackupFileGatewayConEspera extends FakeBackupFileGateway {
  FakeBackupFileGatewayConEspera(this.espera);

  final Completer<void> espera;

  @override
  Future<String?> pickBackupFile() async {
    await espera.future;
    return null;
  }
}
