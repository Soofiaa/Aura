import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/screens/settings_screen.dart';

import '../support/fake_notification_scheduler.dart';

void main() {
  late AppDatabase db;
  late CycleRepository repo;
  late FakeNotificationScheduler scheduler;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CycleRepository(db);
    scheduler = FakeNotificationScheduler();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(repository: repo, scheduler: scheduler),
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

  testWidgets('el boton de prueba de debug programa una notificacion de prueba',
      (tester) async {
    await pumpScreen(tester);

    final testButton = find.text('Probar notificación en 10 segundos');
    expect(testButton, findsOneWidget); // kDebugMode esta activo en tests

    await tester.tap(testButton);
    await tester.pumpAndSettle();

    // No hay contador dedicado en el falso, pero no debe explotar y el
    // mensaje de confirmacion debe aparecer.
    expect(find.text('Notificación de prueba programada en 10 segundos.'),
        findsOneWidget);

    await db.close();
  });
}
