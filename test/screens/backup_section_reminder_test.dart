import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aura/data/backup/backup_file_gateway.dart';
import 'package:aura/data/backup/backup_reminder_store.dart';
import 'package:aura/data/backup/backup_service.dart';
import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/screens/settings_screen.dart';

import '../support/fake_backup.dart';
import '../support/fake_notification_scheduler.dart';

/// Recordatorio de respaldo (CP3): la fecha del ultimo respaldo se anota
/// solo tras guardar en el telefono con exito o compartir con "success".
/// Archivos simulados en FakeBackupService; datos y contrasenas inventados.
void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  late AppDatabase db;
  late CycleRepository repo;
  late FakeBackupService backup;
  late FakeBackupFileGateway gateway;
  late FakeBackupReminderStore recordatorio;

  const secreto = 'mi casa es muy azul';

  setUp(() {
    db = AppDatabase.forTesting(
      NativeDatabase.memory(setup: enableForeignKeys),
    );
    repo = CycleRepository(db);
    backup = FakeBackupService(repo);
    gateway = FakeBackupFileGateway();
    // Reloj del FakeBackupService (2026-10-04) y otro dia para el
    // recordatorio: la fecha anotada sale de su propio reloj.
    recordatorio =
        FakeBackupReminderStore(clock: () => DateTime(2026, 10, 9, 21, 40));
    backupReminderStore = recordatorio;
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await repo.markPeriodDays(['2026-05-01', '2026-05-02']);
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

  Future<void> elegir(WidgetTester tester, String accion) async {
    await tester.tap(find.text('Crear respaldo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(accion));
    await tester.pumpAndSettle();
  }

  Future<void> sinContrasena(WidgetTester tester) async {
    await tester.tap(find.text('Continuar sin contraseña'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog).last,
        matching: find.text('Continuar sin contraseña'),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> conContrasena(WidgetTester tester) async {
    await tester.enterText(
        find.byKey(const ValueKey('protect-password')), secreto);
    await tester.enterText(
        find.byKey(const ValueKey('protect-repeat')), secreto);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Proteger y continuar'));
    await tester.pumpAndSettle();
  }

  Future<String?> ultimoRespaldo() async =>
      (await recordatorio.read()).ultimoRespaldo;

  Future<void> sinAnotar() async {
    expect(recordatorio.recordCount, 0);
    expect(await ultimoRespaldo(), isNull);
  }

  group('guardar en el telefono', () {
    testWidgets('sin contrasena, con exito: anota hoy', (tester) async {
      await pumpSettings(tester);
      await elegir(tester, 'Guardar en el teléfono');
      await sinContrasena(tester);

      expect(find.text('Respaldo guardado.'), findsOneWidget);
      expect(recordatorio.recordCount, 1);
      expect(await ultimoRespaldo(), '2026-10-09');
      await db.close();
    });

    testWidgets('con contrasena, con exito: anota hoy', (tester) async {
      await pumpSettings(tester);
      await elegir(tester, 'Guardar en el teléfono');
      await conContrasena(tester);

      expect(gateway.savedFileName, 'aura_respaldo_protegido_2026-10-04.json');
      expect(recordatorio.recordCount, 1);
      expect(await ultimoRespaldo(), '2026-10-09');
      await db.close();
    });

    for (final protegido in [false, true]) {
      final caso = protegido ? 'con contrasena' : 'sin contrasena';

      testWidgets('$caso, cancelar el "Guardar como": no anota',
          (tester) async {
        gateway.saveResult = false;
        await pumpSettings(tester);
        await elegir(tester, 'Guardar en el teléfono');
        protegido ? await conContrasena(tester) : await sinContrasena(tester);

        expect(find.byType(SnackBar), findsNothing);
        await sinAnotar();
        await db.close();
      });

      testWidgets('$caso, si la escritura falla: no anota', (tester) async {
        gateway.saveError = const FileSystemException('detalle interno');
        await pumpSettings(tester);
        await elegir(tester, 'Guardar en el teléfono');
        protegido ? await conContrasena(tester) : await sinContrasena(tester);

        expect(find.text('No se pudo guardar el respaldo.'), findsOneWidget);
        await sinAnotar();
        await db.close();
      });
    }

    testWidgets('si no se puede crear el respaldo: no anota', (tester) async {
      backup.writeError = BackupWriteException(
          BackupWriteCause.fileSystem, 'detalle interno');
      await pumpSettings(tester);
      await elegir(tester, 'Guardar en el teléfono');
      await sinContrasena(tester);

      expect(find.text('No se pudo crear el respaldo.'), findsOneWidget);
      expect(gateway.savedBytes, isNull);
      await sinAnotar();
      await db.close();
    });
  });

  group('compartir', () {
    testWidgets('success: anota hoy', (tester) async {
      gateway.shareResult = BackupShareResult.success;
      await pumpSettings(tester);
      await elegir(tester, 'Compartir');
      await sinContrasena(tester);

      expect(find.text('Respaldo listo. Guárdalo en un lugar seguro.'),
          findsOneWidget);
      expect(recordatorio.recordCount, 1);
      expect(await ultimoRespaldo(), '2026-10-09');
      await db.close();
    });

    testWidgets('con contrasena y success: anota hoy', (tester) async {
      gateway.shareResult = BackupShareResult.success;
      await pumpSettings(tester);
      await elegir(tester, 'Compartir');
      await conContrasena(tester);

      expect(gateway.sharedFiles, hasLength(1));
      expect(recordatorio.recordCount, 1);
      await db.close();
    });

    testWidgets('dismissed: no anota ni muestra mensaje', (tester) async {
      gateway.shareResult = BackupShareResult.dismissed;
      await pumpSettings(tester);
      await elegir(tester, 'Compartir');
      await sinContrasena(tester);

      expect(gateway.sharedFiles, hasLength(1));
      expect(find.byType(SnackBar), findsNothing);
      await sinAnotar();
      await db.close();
    });

    testWidgets('unavailable: muestra el mensaje pero no anota',
        (tester) async {
      gateway.shareResult = BackupShareResult.unavailable;
      await pumpSettings(tester);
      await elegir(tester, 'Compartir');
      await sinContrasena(tester);

      expect(find.text('Respaldo listo. Guárdalo en un lugar seguro.'),
          findsOneWidget);
      await sinAnotar();
      await db.close();
    });

    testWidgets('si compartir falla: no anota', (tester) async {
      gateway.shareError = const FileSystemException('detalle interno');
      await pumpSettings(tester);
      await elegir(tester, 'Compartir');
      await sinContrasena(tester);

      expect(find.text('No se pudo compartir el respaldo.'), findsOneWidget);
      await sinAnotar();
      await db.close();
    });
  });

  for (final accion in ['Compartir', 'Guardar en el teléfono']) {
    testWidgets('$accion: un error del cifrado no anota', (tester) async {
      backup.encryptionError = BackupEncryptionException(
        BackupEncryptionFailure.verificationFailed,
        'detalle interno',
      );
      await pumpSettings(tester);
      await elegir(tester, accion);
      await conContrasena(tester);

      expect(gateway.sharedFiles, isEmpty);
      expect(gateway.savedBytes, isNull);
      await sinAnotar();
      await db.close();
    });

    testWidgets('$accion: cancelar en "Proteger tu respaldo" no anota',
        (tester) async {
      await pumpSettings(tester);
      await elegir(tester, accion);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(gateway.sharedFiles, isEmpty);
      expect(gateway.savedBytes, isNull);
      await sinAnotar();
      await db.close();
    });
  }

  testWidgets('cancelar el aviso de datos de salud no anota', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('Crear respaldo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    await sinAnotar();
    await db.close();
  });

  testWidgets('si no se puede anotar, el respaldo igual se informa como '
      'hecho', (tester) async {
    recordatorio.recordError =
        const FileSystemException('sin acceso al recordatorio');
    await pumpSettings(tester);
    await elegir(tester, 'Guardar en el teléfono');
    await sinContrasena(tester);

    expect(find.text('Respaldo guardado.'), findsOneWidget);
    expect(find.textContaining('sin acceso'), findsNothing);
    expect(backup.preMigrationCopyDeleteCount, 1);
    await db.close();
  });
}
