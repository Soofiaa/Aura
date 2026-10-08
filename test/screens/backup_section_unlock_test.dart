import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aura/data/backup/backup_service.dart';
import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/domain/backup_codec.dart';
import 'package:aura/domain/backup_crypto.dart';
import 'package:aura/screens/settings_screen.dart';

import '../support/fake_backup.dart';
import '../support/fake_notification_scheduler.dart';

/// HU-06b CP4: importar un respaldo protegido desde Ajustes. Archivos en
/// memoria (FakeBackupService, descifrado en el mismo isolate); datos y
/// contrasenas inventados. test/fixtures/backup_v5_cifrado.json es
/// backup_v5.json (8 dias) cifrado con parametros reducidos.
void main() {
  const fixturePassword = 'Fixture CP1: ñandú 🌸 árbol';
  const wrong = 'una clave equivocada';
  const titulo = 'Respaldo protegido';
  const errorClave =
      'La contraseña no es correcta o el archivo está dañado. No se cambió '
      'nada.';
  const progreso = 'Abriendo tu respaldo…';
  const progresoDetalle = 'Esto puede tardar unos segundos.';
  const exito =
      'Listo: se importaron 8 días.\nSi te equivocaste, toca '
      'Deshacer.';

  late List<int> cifrado;
  late List<int> cifradoSchemaNuevo;

  // Resultados REALES de BackupService.unlockBackup (criptografia real, en
  // el mismo isolate), calculados fuera de testWidgets: Argon2id no avanza
  // dentro del reloj falso. El FakeBackupService los devuelve.
  late BackupUnlockResult desbloqueado;
  late BackupUnlockResult schemaNuevo;

  setUpAll(() async {
    await initializeDateFormatting();
    cifrado = File('test/fixtures/backup_v5_cifrado.json').readAsBytesSync();
    // Contenido de un schema posterior, cifrado con la misma contrasena.
    final v5 =
        jsonDecode(File('test/fixtures/backup_v5.json').readAsStringSync())
            as Map<String, dynamic>;
    v5['schemaVersion'] = currentBackupSchemaVersion + 1;
    cifradoSchemaNuevo = utf8.encode(
      await encryptBackup(
        jsonEncode(v5),
        fixturePassword,
        params: const Argon2idParams(
          memoryKiB: 8192,
          iterations: 1,
          parallelism: 1,
        ),
      ),
    );

    final tmpDb = AppDatabase.forTesting(
      NativeDatabase.memory(setup: enableForeignKeys),
    );
    final real = BackupService(
      CycleRepository(tmpDb),
      supportDirectory: () => throw UnimplementedError(),
      temporaryDirectory: () => throw UnimplementedError(),
      runTask: runInSameIsolate,
    );
    BackupNeedsPassword pendiente(List<int> b) =>
        decodeBackup(b) as BackupNeedsPassword;
    desbloqueado = await real.unlockBackup(pendiente(cifrado), fixturePassword);
    expect(desbloqueado, isA<BackupUnlocked>());
    expect(
      await real.unlockBackup(pendiente(cifrado), wrong),
      isA<BackupUnlockWrongPasswordOrDamaged>(),
    );
    schemaNuevo = await real.unlockBackup(
      pendiente(cifradoSchemaNuevo),
      fixturePassword,
    );
    expect(schemaNuevo, isA<BackupUnlockInvalid>());
    await tmpDb.close();
  });

  late AppDatabase db;
  late CycleRepository repo;
  late FakeBackupService backup;
  late FakeBackupFileGateway gateway;

  setUp(() {
    db = AppDatabase.forTesting(
      NativeDatabase.memory(setup: enableForeignKeys),
    );
    repo = CycleRepository(db);
    backup = FakeBackupService(repo);
    backup.unlockResults[fixturePassword] = desbloqueado;
    gateway = FakeBackupFileGateway();
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await repo.markPeriodDays(['2026-05-01', '2026-05-02', '2026-05-03']);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          repository: repo,
          scheduler: FakeNotificationScheduler(),
          backupService: backup,
          fileGateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> elegir(WidgetTester tester, List<int> bytes) async {
    backup.files['respaldo.json'] = bytes;
    gateway.pickResult = 'respaldo.json';
    await tester.tap(find.text('Restaurar un respaldo'));
    await tester.pumpAndSettle();
  }

  Finder campo() => find.byKey(const ValueKey('unlock-password'));

  Future<void> escribirYAbrir(WidgetTester tester, String p) async {
    await tester.enterText(campo(), p);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Abrir respaldo'));
    await tester.pumpAndSettle();
  }

  Future<void> nadaCambio() async {
    expect(backup.importCount, 0);
    expect(await backup.hasPreImportCopy(), isFalse);
    expect(await repo.countDays(), 3);
  }

  testWidgets('flujo completo: contrasena, vista previa, confirmar, aviso y '
      'Deshacer', (tester) async {
    await pumpSettings(tester);
    await elegir(tester, cifrado);
    expect(find.text(titulo), findsOneWidget);

    await escribirYAbrir(tester, fixturePassword);
    expect(find.text('¿Reemplazar tus datos?'), findsOneWidget);
    await nadaCambio();

    await tester.tap(find.text('Reemplazar'));
    await tester.pumpAndSettle();
    expect(backup.importCount, 1);
    expect(await repo.countDays(), 8);
    expect(find.text(exito), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Deshacer'));
    await tester.pumpAndSettle();
    expect(backup.undoCount, 1);
    expect(await repo.countDays(), 3);
    await db.close();
  });

  testWidgets('contrasena incorrecta: mensaje exacto, el dialogo vuelve con lo '
      'escrito, sin volver a elegir el archivo; despues la correcta funciona', (
    tester,
  ) async {
    await pumpSettings(tester);
    await elegir(tester, cifrado);
    await escribirYAbrir(tester, wrong);

    expect(find.text(titulo), findsOneWidget);
    expect(find.text(errorClave), findsOneWidget);
    expect(errorClave, wrongPasswordOrDamagedMessage);
    final c = tester.widget<TextField>(campo()).controller!;
    expect(c.text, wrong);
    expect(
      c.selection,
      TextSelection(baseOffset: 0, extentOffset: wrong.length),
    );
    expect(gateway.pickCount, 1);
    expect(backup.readCount, 1);
    expect(backup.unlockCount, 1);
    await nadaCambio();

    // Otro intento equivocado: sin limite.
    await escribirYAbrir(tester, '$wrong 2');
    expect(find.text(errorClave), findsOneWidget);
    await nadaCambio();

    await escribirYAbrir(tester, fixturePassword);
    expect(find.text('¿Reemplazar tus datos?'), findsOneWidget);
    await nadaCambio();
    await tester.tap(find.text('Reemplazar'));
    await tester.pumpAndSettle();
    expect(await repo.countDays(), 8);
    expect(gateway.pickCount, 1);
    expect(backup.readCount, 1);
    expect(backup.unlockCount, 3);
    await db.close();
  });

  testWidgets('Cancelar en el dialogo de contrasena: nada cambia', (
    tester,
  ) async {
    await pumpSettings(tester);
    await elegir(tester, cifrado);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text(titulo), findsNothing);
    expect(backup.unlockCount, 0);
    expect(find.byType(SnackBar), findsNothing);
    await nadaCambio();
    await db.close();
  });

  testWidgets('Cancelar en la vista previa: nada cambia', (tester) async {
    await pumpSettings(tester);
    await elegir(tester, cifrado);
    await escribirYAbrir(tester, fixturePassword);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    await nadaCambio();
    await db.close();
  });

  testWidgets('contenido no importable (schema posterior): mensaje de siempre, '
      'sin reintento ni detalle', (tester) async {
    backup.unlockResults[fixturePassword] = schemaNuevo;
    await pumpSettings(tester);
    await elegir(tester, cifradoSchemaNuevo);
    await escribirYAbrir(tester, fixturePassword);

    expect(find.text(titulo), findsNothing);
    expect(
      find.text(
        'Este respaldo es de una versión más nueva de Aura. '
        'Actualiza la app y vuelve a intentarlo. No se cambió nada.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('schemaVersion'), findsNothing);
    expect(backup.unlockCount, 1);
    await nadaCambio();
    await db.close();
  });

  testWidgets('progreso visible y bloqueante mientras se abre', (tester) async {
    backup.unlockGate = Completer<void>();
    await pumpSettings(tester);
    await elegir(tester, cifrado);
    await tester.enterText(campo(), fixturePassword);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Abrir respaldo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(progreso), findsOneWidget);
    expect(find.text(progresoDetalle), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(progreso), findsOneWidget);

    backup.unlockGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text(progreso), findsNothing);
    expect(find.text('¿Reemplazar tus datos?'), findsOneWidget);
    await db.close();
  });

  testWidgets('la contrasena no aparece en ningun texto ni nodo de semantica, '
      'tampoco en el aviso final', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpSettings(tester);
    await elegir(tester, cifrado);

    void sinClave() {
      for (final e in find.byType(Text).evaluate()) {
        final data = (e.widget as Text).data ?? '';
        expect(data, isNot(contains('Fixture CP1')));
        expect(data, isNot(contains(wrong)));
      }
      bool tiene(SemanticsNode node) {
        final d = node.getSemanticsData();
        return [
          d.label,
          d.value,
          d.hint,
          d.tooltip,
        ].any((t) => t.contains('Fixture CP1') || t.contains(wrong));
      }

      expect(find.semantics.byPredicate(tiene), findsNothing);
    }

    await escribirYAbrir(tester, wrong);
    sinClave();
    await escribirYAbrir(tester, fixturePassword);
    sinClave();
    await tester.tap(find.text('Reemplazar'));
    await tester.pumpAndSettle();
    expect(find.text(exito), findsOneWidget);
    sinClave();
    semantics.dispose();
    await db.close();
  });
}
