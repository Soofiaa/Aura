import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aura/data/backup/backup_reminder_store.dart';
import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/main.dart';
import 'package:aura/screens/settings_screen.dart';

import '../support/fake_backup.dart';
import '../support/fake_notification_scheduler.dart';

/// CP4: fecha del ultimo respaldo e interruptor "Recordarme crear un
/// respaldo" en Ajustes > Tus datos. Datos inventados; "hoy" es el
/// 10/10/2026 segun el reloj del almacen.
void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  late AppDatabase db;
  late CycleRepository repo;
  late FakeBackupService backup;
  late FakeBackupFileGateway gateway;

  const primeraLinea = 'Guarda tus registros en un archivo';
  const sinRespaldo = 'Todavía no has creado un respaldo en este teléfono';
  const interruptor = 'Recordarme crear un respaldo';
  const subtitulo = 'Un aviso en Inicio si pasan 30 días sin respaldo';
  final hoy = DateTime(2026, 10, 10, 18, 5);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CycleRepository(db);
    backup = FakeBackupService(repo);
    gateway = FakeBackupFileGateway();
  });

  FakeBackupReminderStore almacen({String? ultimo, bool activado = true}) =>
      FakeBackupReminderStore(
        clock: () => hoy,
        initial: BackupReminderState(
          primerUso: '2026-08-01',
          ultimoRespaldo: ultimo,
          activado: activado,
        ),
      );

  Future<void> pumpAjustes(WidgetTester tester, BackupReminderStore store,
      {Size tamano = const Size(900, 2600), double escala = 1.0}) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = escala;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MaterialApp(
      theme: auraTheme(),
      home: SettingsScreen(
        repository: repo,
        scheduler: FakeNotificationScheduler(),
        backupService: backup,
        fileGateway: gateway,
        reminderStore: store,
      ),
    ));
    await tester.pumpAndSettle();
  }

  SwitchListTile switchRecordatorio(WidgetTester tester) =>
      tester.widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, interruptor));

  group('segunda linea de "Crear respaldo"', () {
    testWidgets('sin respaldo previo', (tester) async {
      await pumpAjustes(tester, almacen());
      expect(find.text(primeraLinea), findsOneWidget);
      expect(find.text(sinRespaldo), findsOneWidget);
      expect(find.textContaining('Último respaldo'), findsNothing);
      await db.close();
    });

    testWidgets('con respaldo de este ano: sin el ano', (tester) async {
      await pumpAjustes(tester, almacen(ultimo: '2026-09-06'));
      expect(find.text(primeraLinea), findsOneWidget);
      expect(find.text('Último respaldo: 6 de septiembre'), findsOneWidget);
      expect(find.text(sinRespaldo), findsNothing);
      await db.close();
    });

    testWidgets('con respaldo de otro ano: con el ano', (tester) async {
      await pumpAjustes(tester, almacen(ultimo: '2025-12-28'));
      expect(find.text('Último respaldo: 28 de diciembre de 2025'),
          findsOneWidget);
      await db.close();
    });

    testWidgets('al guardar un respaldo, la fecha cambia sola a hoy',
        (tester) async {
      await pumpAjustes(tester, almacen(ultimo: '2026-09-06'));
      await tester.tap(find.text('Crear respaldo'));
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
      expect(find.text('Último respaldo: 10 de octubre'), findsOneWidget);
      await db.close();
    });

    testWidgets('si no se puede leer el estado: solo la primera linea y el '
        'interruptor sin poder cambiarse', (tester) async {
      final store = almacen()..readError = StateError('sin acceso');
      await pumpAjustes(tester, store);
      expect(find.text(primeraLinea), findsOneWidget);
      expect(find.text(sinRespaldo), findsNothing);
      expect(find.textContaining('Último respaldo'), findsNothing);
      expect(switchRecordatorio(tester).value, isTrue);
      expect(switchRecordatorio(tester).onChanged, isNull);
      expect(tester.takeException(), isNull);
      await db.close();
    });
  });

  group('interruptor "Recordarme crear un respaldo"', () {
    testWidgets('encendido por defecto, con su subtitulo', (tester) async {
      await pumpAjustes(tester, almacen());
      expect(find.text(subtitulo), findsOneWidget);
      expect(switchRecordatorio(tester).value, isTrue);
      expect(switchRecordatorio(tester).onChanged, isNotNull);
      // Mismo estilo que los otros interruptores (el del tema).
      expect(switchRecordatorio(tester).activeThumbColor, isNull);
      expect(switchRecordatorio(tester).activeTrackColor, isNull);
      await db.close();
    });

    testWidgets('se guarda al tocarlo y se mantiene al volver a Ajustes',
        (tester) async {
      final store = almacen();
      await pumpAjustes(tester, store);

      await tester.tap(find.text(interruptor));
      await tester.pumpAndSettle();
      expect(store.current!.activado, isFalse);
      expect(switchRecordatorio(tester).value, isFalse);

      // Otra pantalla de Ajustes con el mismo almacen.
      await tester.pumpWidget(const SizedBox());
      await pumpAjustes(tester, store);
      expect(switchRecordatorio(tester).value, isFalse);

      await tester.tap(find.text(interruptor));
      await tester.pumpAndSettle();
      expect(store.current!.activado, isTrue);
      expect(switchRecordatorio(tester).value, isTrue);
      await db.close();
    });

    testWidgets('apagado guardado: se muestra apagado', (tester) async {
      await pumpAjustes(tester, almacen(activado: false));
      expect(switchRecordatorio(tester).value, isFalse);
      await db.close();
    });

    testWidgets('si no se puede guardar: avisa y queda como estaba',
        (tester) async {
      final store = almacen()..writeError = StateError('detalle interno');
      await pumpAjustes(tester, store);
      await tester.tap(find.text(interruptor));
      await tester.pumpAndSettle();

      expect(find.text('No se pudo guardar el cambio. Inténtalo de nuevo.'),
          findsOneWidget);
      expect(find.textContaining('detalle interno'), findsNothing);
      expect(switchRecordatorio(tester).value, isTrue);
      expect(store.current!.activado, isTrue);
      await db.close();
    });
  });

  group('accesibilidad', () {
    testWidgets('"Crear respaldo" se lee con sus dos lineas, como boton',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpAjustes(tester, almacen(ultimo: '2026-09-06'));
      final datos = tester.getSemantics(find.text('Crear respaldo'))
          .getSemanticsData();
      expect(datos.label, contains('Crear respaldo'));
      expect(datos.label, contains(primeraLinea));
      expect(datos.label, contains('Último respaldo: 6 de septiembre'));
      expect(datos.hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
      await db.close();
    });

    testWidgets('el interruptor tiene nombre, subtitulo y estado',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpAjustes(tester, almacen());
      final nodo = tester.getSemantics(find.text(interruptor));
      expect(
        nodo,
        isSemantics(
          label: '$interruptor\n$subtitulo',
          hasToggledState: true,
          isToggled: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );

      await tester.tap(find.text(interruptor));
      await tester.pumpAndSettle();
      expect(tester.getSemantics(find.text(interruptor)),
          isSemantics(hasToggledState: true, isToggled: false));
      handle.dispose();
      await db.close();
    });
  });

  group('360 x 640 sin desbordes', () {
    for (final escala in [1.0, 1.3, 1.5, 2.0]) {
      for (final ultimo in [null, '2025-12-28']) {
        testWidgets(
            'texto $escala, ${ultimo == null ? 'sin' : 'con'} respaldo previo',
            (tester) async {
          await pumpAjustes(tester, almacen(ultimo: ultimo),
              tamano: const Size(360, 640), escala: escala);
          for (final texto in [
            'Crear respaldo',
            ultimo == null
                ? sinRespaldo
                : 'Último respaldo: 28 de diciembre de 2025',
            interruptor,
            subtitulo,
            'Restaurar un respaldo',
          ]) {
            await tester.scrollUntilVisible(find.text(texto), 150);
            await tester.ensureVisible(find.text(texto));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: texto);
          }
          // Todo el texto de la seccion queda dentro de la pantalla de ancho.
          for (final texto in ['Crear respaldo', interruptor]) {
            final rect = tester.getRect(find.text(texto));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(360));
          }
          await db.close();
        });
      }
    }
  });
}
