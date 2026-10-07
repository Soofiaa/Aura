import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/domain/backup_codec.dart';
import 'package:aura/screens/settings_screen.dart';
import 'package:aura/utils/app_version.dart';

import '../support/fake_backup.dart';
import '../support/fake_notification_scheduler.dart';

void main() {
  late AppDatabase db;
  late CycleRepository repo;
  late FakeNotificationScheduler scheduler;
  late FakeBackupService backup;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CycleRepository(db);
    scheduler = FakeNotificationScheduler();
    backup = FakeBackupService(repo);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        repository: repo,
        scheduler: scheduler,
        backupService: backup,
        fileGateway: FakeBackupFileGateway(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('no pide permiso solo por abrir la pantalla', (tester) async {
    await pumpScreen(tester);
    expect(scheduler.requestPermissionCallCount, 0);
    await db.close();
  });

  testWidgets('pide permiso exactamente al activar el interruptor general',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Notificaciones'));
    await tester.pumpAndSettle();

    expect(scheduler.requestPermissionCallCount, 1);
    expect(await repo.getNotificationsEnabled(), isTrue);

    await db.close();
  });

  testWidgets(
      'si el permiso es denegado, el interruptor vuelve a apagado y queda '
      'persistido en false', (tester) async {
    scheduler.permissionGranted = false;
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Notificaciones'));
    await tester.pumpAndSettle();

    final switchWidget = tester
        .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Notificaciones'));
    expect(switchWidget.value, isFalse);
    expect(await repo.getNotificationsEnabled(), isFalse);

    await db.close();
  });

  testWidgets(
      'los sub-interruptores estan deshabilitados mientras el general esta '
      'apagado', (tester) async {
    await pumpScreen(tester);

    final periodoSwitch = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Recordatorio de período'));
    expect(periodoSwitch.onChanged, isNull);

    await db.close();
  });

  testWidgets('activar el recordatorio de ventana fertil lo persiste',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Notificaciones'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SwitchListTile, 'Ventana fértil'));
    await tester.pumpAndSettle();

    final settings = await repo.getNotificationSettings();
    expect(settings.fertileWindowRemindersEnabled, isTrue);

    await db.close();
  });

  testWidgets('el subtitulo de ventana fertil menciona el disclaimer',
      (tester) async {
    await pumpScreen(tester);
    expect(
      find.textContaining('estimación, no método anticonceptivo'),
      findsOneWidget,
    );
    await db.close();
  });

  testWidgets(
      'el subtitulo de mostrar detalles advierte sobre dispositivos '
      'conectados', (tester) async {
    await pumpScreen(tester);
    expect(
      find.textContaining('relojes u otros dispositivos'),
      findsOneWidget,
    );
    await db.close();
  });

  testWidgets(
      'el boton de notificacion de prueba esta siempre visible y programa una',
      (tester) async {
    await pumpScreen(tester);

    final testButton = find.text('Enviar notificación de prueba');
    expect(testButton, findsOneWidget); // visible siempre, no solo en debug

    await tester.tap(testButton);
    await tester.pumpAndSettle();

    // No hay contador dedicado en el falso, pero no debe explotar y el
    // mensaje de confirmacion debe aparecer.
    expect(find.text('Notificación de prueba programada en 10 segundos.'),
        findsOneWidget);

    await db.close();
  });

  testWidgets('muestra la version de la constante unica', (tester) async {
    await pumpScreen(tester);
    await tester.scrollUntilVisible(
        find.text('Versión $appVersionName • Aura 🌸'), 200);
    expect(find.text('Versión $appVersionName • Aura 🌸'), findsOneWidget);
    expect(find.textContaining('1.0.0'), findsNothing);
    await db.close();
  });

  testWidgets(
      'los interruptores se actualizan solos cuando los ajustes cambian por '
      'fuera de la pantalla (importar un respaldo)', (tester) async {
    await repo.setNotificationsEnabled(true);
    await pumpScreen(tester);
    SwitchListTile switchDe(String titulo) => tester
        .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, titulo));
    expect(switchDe('Recordatorio de período').value, isTrue);
    expect(switchDe('Ventana fértil').value, isFalse);

    await repo.replaceAllWithBackup(const BackupData(
      schemaVersion: currentBackupSchemaVersion,
      appVersion: '1.0.1',
      exportedAt: '2026-10-04T10:15:00-03:00',
      days: [],
      settings: BackupSettings(
        onboardingSeen: true,
        notificationsEnabled: false,
        periodReminderEnabled: false,
        fertileWindowRemindersEnabled: true,
        showDetailsEnabled: true,
        reminderHour: 21,
        reminderMinute: 30,
      ),
    ));
    await tester.pumpAndSettle();

    expect(switchDe('Notificaciones').value, isTrue,
        reason: 'el interruptor general no se importa');
    expect(switchDe('Recordatorio de período').value, isFalse);
    expect(switchDe('Ventana fértil').value, isTrue);
    expect(switchDe('Mostrar detalles en la notificación').value, isTrue);
    expect(find.text('21:30'), findsOneWidget);

    await db.close();
  });

  testWidgets(
      'Borrar todos los datos pasa por BackupService (que tambien borra la '
      'copia previa y los temporales) y reinicia los interruptores',
      (tester) async {
    await repo.setNotificationsEnabled(true);
    await repo.setReminderTime(hour: 21, minute: 30);
    await repo.markPeriodDay('2026-01-01');
    await pumpScreen(tester);

    await tester.scrollUntilVisible(find.text('Borrar todos los datos'), 200);
    await tester.tap(find.text('Borrar todos los datos'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('la copia guardada antes de la última importación'),
        findsOneWidget);
    await tester.tap(find.text('Borrar todo'));
    await tester.pumpAndSettle();

    expect(backup.deleteAllDataCallCount, 1);
    expect(await repo.countDays(), 0);
    expect(find.text('Datos borrados correctamente 💧'), findsOneWidget);

    await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Notificaciones'), -200);
    expect(
        tester
            .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, 'Notificaciones'))
            .value,
        isFalse);
    expect(find.text('09:00'), findsOneWidget);

    await db.close();
  });

  testWidgets('si borrar falla, el mensaje no muestra el detalle del error',
      (tester) async {
    backup.failOnDelete = true;
    await pumpScreen(tester);

    await tester.scrollUntilVisible(find.text('Borrar todos los datos'), 200);
    await tester.tap(find.text('Borrar todos los datos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrar todo'));
    await tester.pumpAndSettle();

    expect(
        find.text('No se pudieron borrar todos los datos. Inténtalo de nuevo.'),
        findsOneWidget);
    expect(find.textContaining('detalle interno'), findsNothing);
    expect(find.text('Datos borrados correctamente 💧'), findsNothing);

    await db.close();
  });
}
