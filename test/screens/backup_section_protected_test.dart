import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aura/data/backup/backup_reminder_store.dart';
import 'package:aura/data/backup/backup_service.dart';
import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/screens/settings_screen.dart';

import '../support/fake_backup.dart';
import '../support/fake_notification_scheduler.dart';

/// HU-06b CP3: crear un respaldo protegido desde Ajustes. Los archivos se
/// simulan en FakeBackupService; datos y contrasenas inventados.
void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  late AppDatabase db;
  late CycleRepository repo;
  late FakeBackupService backup;
  late FakeBackupFileGateway gateway;

  const secreto = 'mi casa es muy azul';
  const nombreProtegido = 'aura_respaldo_protegido_2026-10-04.json';
  const progreso = 'Protegiendo tu respaldo…';
  const progresoDetalle = 'Esto puede tardar unos segundos.';

  setUp(() {
    db = AppDatabase.forTesting(
      NativeDatabase.memory(setup: enableForeignKeys),
    );
    repo = CycleRepository(db);
    backup = FakeBackupService(repo);
    gateway = FakeBackupFileGateway();
    // Respaldo exitoso: anota la fecha en memoria (la E/S real no
    // avanza dentro de testWidgets).
    backupReminderStore = FakeBackupReminderStore();
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

  /// "Crear respaldo" -> [accion] -> "Proteger tu respaldo".
  Future<void> abrirProteger(WidgetTester tester, String accion) async {
    await tester.tap(find.text('Crear respaldo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(accion));
    await tester.pumpAndSettle();
    expect(find.text('Proteger tu respaldo'), findsOneWidget);
  }

  /// Escribe [p] en los dos campos y toca "Proteger y continuar" (sin
  /// esperar a que termine: puede haber un dialogo de progreso animado).
  Future<void> proteger(WidgetTester tester, String p) async {
    await tester.enterText(find.byKey(const ValueKey('protect-password')), p);
    await tester.enterText(find.byKey(const ValueKey('protect-repeat')), p);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Proteger y continuar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
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

  testWidgets('Compartir con contrasena: una sola exportacion con la '
      'contrasena escrita y progreso bloqueante mientras dura', (tester) async {
    backup.exportGate = Completer<void>();
    await pumpSettings(tester);
    await abrirProteger(tester, 'Compartir');
    await proteger(tester, secreto);

    expect(find.text(progreso), findsOneWidget);
    expect(find.text(progresoDetalle), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Proteger tu respaldo'), findsNothing);

    // "Atras" no cierra el progreso.
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(progreso), findsOneWidget);
    // Sigue animandose.
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(gateway.sharedFiles, isEmpty);

    backup.exportGate!.complete();
    await tester.pumpAndSettle();

    expect(find.text(progreso), findsNothing);
    expect(backup.exportPasswords, [secreto]);
    expect(gateway.sharedFiles.single.path, endsWith(nombreProtegido));
    expect(
      find.text(
        'Respaldo protegido listo. Recuerda tu contraseña: Aura no '
        'puede recuperarla.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Respaldo listo. Guárdalo en un lugar seguro.'),
      findsNothing,
    );
    expect(backup.preMigrationCopyDeleteCount, 0);
    await db.close();
  });

  testWidgets('Guardar en el teléfono con contrasena: guarda los bytes del '
      'archivo verificado, con el nombre protegido, y borra el temporal', (
    tester,
  ) async {
    await pumpSettings(tester);
    await abrirProteger(tester, 'Guardar en el teléfono');
    await proteger(tester, secreto);
    await tester.pumpAndSettle();

    expect(backup.exportPasswords, [secreto]);
    expect(gateway.savedFileName, nombreProtegido);
    expect(gateway.savedBytes, FakeBackupService.encryptedFileBytes);
    expect(backup.readExportPaths.single, endsWith(nombreProtegido));
    expect(backup.deletedExportPaths.single, endsWith(nombreProtegido));
    expect(
      find.text(
        'Respaldo protegido guardado. Recuerda tu contraseña: Aura '
        'no puede recuperarla.',
      ),
      findsOneWidget,
    );
    expect(find.text('Respaldo guardado.'), findsNothing);
    expect(backup.preMigrationCopyDeleteCount, 1);
    await db.close();
  });

  testWidgets('Guardar con contrasena: el temporal se borra aunque guardar '
      'falle', (tester) async {
    gateway.saveError = const FileSystemException('detalle interno');
    await pumpSettings(tester);
    await abrirProteger(tester, 'Guardar en el teléfono');
    await proteger(tester, secreto);
    await tester.pumpAndSettle();

    expect(backup.deletedExportPaths.single, endsWith(nombreProtegido));
    expect(find.text('No se pudo guardar el respaldo.'), findsOneWidget);
    expect(find.textContaining('detalle interno'), findsNothing);
    expect(backup.preMigrationCopyDeleteCount, 0);
    await db.close();
  });

  for (final accion in ['Compartir', 'Guardar en el teléfono']) {
    testWidgets('$accion: un error del cifrado muestra su mensaje, cierra el '
        'progreso y no comparte ni guarda nada', (tester) async {
      backup.encryptionError = BackupEncryptionException(
        BackupEncryptionFailure.verificationFailed,
        'detalle interno',
      );
      await pumpSettings(tester);
      await abrirProteger(tester, accion);
      await proteger(tester, secreto);
      await tester.pumpAndSettle();

      expect(find.text(progreso), findsNothing);
      expect(
        find.text(
          'No se pudo crear el respaldo protegido: la comprobación '
          'del archivo falló. No se guardó ningún archivo.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('detalle interno'), findsNothing);
      expect(gateway.sharedFiles, isEmpty);
      expect(gateway.savedBytes, isNull);
      expect(backup.readExportPaths, isEmpty);
      await db.close();
    });
  }

  testWidgets('sin contrasena, confirmado: exporta sin cifrar como antes', (
    tester,
  ) async {
    await pumpSettings(tester);
    await abrirProteger(tester, 'Compartir');
    await sinContrasena(tester);

    expect(backup.exportPasswords, [null]);
    expect(
      gateway.sharedFiles.single.path,
      endsWith('aura_respaldo_2026-10-04.json'),
    );
    // Sin contrasena, el mensaje de siempre.
    expect(
      find.text('Respaldo listo. Guárdalo en un lugar seguro.'),
      findsOneWidget,
    );
    expect(find.text(progreso), findsNothing);
    await db.close();
  });

  testWidgets('"Volver" y despues "Cancelar": no exporta nada', (tester) async {
    await pumpSettings(tester);
    await abrirProteger(tester, 'Compartir');
    await tester.tap(find.text('Continuar sin contraseña'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();
    expect(find.text('Proteger tu respaldo'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(backup.exportPasswords, isEmpty);
    expect(gateway.sharedFiles, isEmpty);
    expect(gateway.savedBytes, isNull);
    expect(find.byType(SnackBar), findsNothing);
    await db.close();
  });

  testWidgets('la contrasena no aparece en el progreso ni en los mensajes', (
    tester,
  ) async {
    backup.exportGate = Completer<void>();
    await pumpSettings(tester);
    await abrirProteger(tester, 'Compartir');
    await proteger(tester, secreto);
    void sinSecreto() {
      for (final e in find.byType(Text).evaluate()) {
        expect((e.widget as Text).data ?? '', isNot(contains(secreto)));
      }
    }

    sinSecreto();
    backup.exportGate!.complete();
    await tester.pumpAndSettle();
    sinSecreto();
    await db.close();
  });
}
