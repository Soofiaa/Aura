import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/device_settings_store.dart';
import 'package:aura/data/notifications/notification_reconciler.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/domain/notification_planner.dart';
import 'package:aura/utils/notifications.dart' show idsToCancel;

import '../../support/fake_notification_scheduler.dart';

void main() {
  test(
      'arranca sin datos: no reconcilia hasta tener ciclos y ajustes, '
      'y el plan queda vacio con notificaciones apagadas (default)',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    final repo = CycleRepository(db);
    final scheduler = FakeNotificationScheduler();
    final reconciler = NotificationReconciler(
      repo,
      scheduler,
      clock: () => DateTime(2026, 4, 1, 8),
    );

    reconciler.start();
    await Future<void>.delayed(Duration.zero);

    expect(scheduler.reconcileCallCount, greaterThan(0));
    expect(scheduler.lastReconciledPlan, isEmpty); // notificationsEnabled=false por defecto

    await reconciler.dispose();
    await db.close();
  });

  test('activar el interruptor general y marcar un periodo dispara un plan no vacio',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    final repo = CycleRepository(db);
    final scheduler = FakeNotificationScheduler();
    final reconciler = NotificationReconciler(
      repo,
      scheduler,
      clock: () => DateTime(2026, 4, 1, 8),
    );

    reconciler.start();
    await Future<void>.delayed(Duration.zero);

    await repo.setNotificationsEnabled(true);
    await repo.markPeriodDay('2026-03-26');
    await Future<void>.delayed(Duration.zero);

    expect(
      scheduler.lastReconciledPlan
          .any((n) => n.kind == NotificationKind.periodReminder),
      isTrue,
    );

    await reconciler.dispose();
    await db.close();
  });

  test('onAppResumed con cambio de zona fuerza un reconcile', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    final repo = CycleRepository(db);
    final scheduler = FakeNotificationScheduler();
    final reconciler = NotificationReconciler(
      repo,
      scheduler,
      clock: () => DateTime(2026, 4, 1, 8),
    );

    reconciler.start();
    await Future<void>.delayed(Duration.zero);
    final callsBefore = scheduler.reconcileCallCount;

    scheduler.simulateTimeZoneChange = true;
    await reconciler.onAppResumed();

    expect(scheduler.reconcileCallCount, greaterThan(callsBefore));

    await reconciler.dispose();
    await db.close();
  });

  test('onAppResumed sin cambio de zona no fuerza un reconcile extra',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    final repo = CycleRepository(db);
    final scheduler = FakeNotificationScheduler();
    final reconciler = NotificationReconciler(
      repo,
      scheduler,
      clock: () => DateTime(2026, 4, 1, 8),
    );

    reconciler.start();
    await Future<void>.delayed(Duration.zero);
    final callsBefore = scheduler.reconcileCallCount;

    scheduler.simulateTimeZoneChange = false;
    await reconciler.onAppResumed();

    expect(scheduler.reconcileCallCount, callsBefore);

    await reconciler.dispose();
    await db.close();
  });

  // HU-05, CP5b: apagar "Mostrar ovulacion y ventana fertil" cancela el
  // aviso fertil pendiente (id 101) sin tocar el de periodo ni el valor
  // guardado de "Ventana fertil".
  test('apagar showFertileWindow cancela el aviso fertil pendiente (101)',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    final repo = CycleRepository(db);
    final scheduler = FakeNotificationScheduler();
    final reconciler = NotificationReconciler(
      repo,
      scheduler,
      clock: () => DateTime(2026, 4, 1, 8),
    );

    // Periodos cada 28 dias (3 ciclos completos, confianza media):
    // ultimo inicio 30/03, ventana fertil desde el 08/04.
    await repo.markPeriodDays(
        ['2026-01-05', '2026-02-02', '2026-03-02', '2026-03-30']);
    await repo.setNotificationsEnabled(true);
    await repo.setFertileWindowRemindersEnabled(true);
    reconciler.start();
    await Future<void>.delayed(Duration.zero);
    expect(scheduler.pendingIds, {100, 101});

    await repo.setShowFertileWindow(false);
    await Future<void>.delayed(Duration.zero);
    expect(scheduler.pendingIds, {100});
    expect(scheduler.cancelledIds, [101]);
    expect(
        (await repo.getNotificationSettings()).fertileWindowRemindersEnabled,
        isTrue);

    // Al volver a encenderlo, se agenda de nuevo.
    await repo.setShowFertileWindow(true);
    await Future<void>.delayed(Duration.zero);
    expect(scheduler.pendingIds, {100, 101});

    await reconciler.dispose();
    await db.close();
  });

  group('una corrida a la vez', () {
    test('con el scheduler lento, prender y apagar rapido deja el ultimo '
        'plan (sin aviso programado con el interruptor apagado)', () async {
      final db = AppDatabase.forTesting(
          NativeDatabase.memory(setup: enableForeignKeys));
      final repo = CycleRepository(db);
      final scheduler = FakeNotificationScheduler();
      final reconciler = NotificationReconciler(repo, scheduler,
          clock: () => DateTime(2026, 4, 1, 8));
      await repo.markPeriodDays(
          ['2026-01-05', '2026-02-02', '2026-03-02', '2026-03-30']);
      reconciler.start();
      await reconciler.idle;
      await Future<void>.delayed(Duration.zero);
      await reconciler.idle;

      final gate = Completer<void>();
      scheduler.delay = gate.future;
      await repo.setNotificationsEnabled(true);
      await Future<void>.delayed(Duration.zero);
      await repo.setNotificationsEnabled(false);
      await Future<void>.delayed(Duration.zero);
      final callsWhileBlocked = scheduler.reconcileCallCount;
      gate.complete();
      scheduler.delay = null;
      await reconciler.idle;

      // Lo que llego mientras corria se junto en una sola corrida mas.
      expect(scheduler.reconcileCallCount, callsWhileBlocked + 1);
      expect(scheduler.pendingIds, isEmpty);

      await reconciler.dispose();
      await db.close();
    });

    test('si el scheduler falla, el siguiente cambio vuelve a reconciliar',
        () async {
      final db = AppDatabase.forTesting(
          NativeDatabase.memory(setup: enableForeignKeys));
      final repo = CycleRepository(db);
      final scheduler = FakeNotificationScheduler()..throwOnReconcile = true;
      final reconciler = NotificationReconciler(repo, scheduler,
          clock: () => DateTime(2026, 4, 1, 8));
      await repo.markPeriodDays(
          ['2026-01-05', '2026-02-02', '2026-03-02', '2026-03-30']);
      reconciler.start();
      await Future<void>.delayed(Duration.zero);
      await reconciler.idle;

      scheduler.throwOnReconcile = false;
      await repo.setNotificationsEnabled(true);
      await Future<void>.delayed(Duration.zero);
      await reconciler.idle;

      expect(scheduler.pendingIds, contains(100));
      await reconciler.dispose();
      await db.close();
    });
  });

  test('no reconcilia hasta tener tambien los ciclos (no cancela todo al '
      'abrir la app)', () async {
    final db = AppDatabase.forTesting(
        NativeDatabase.memory(setup: enableForeignKeys));
    final repo = CycleRepository(db);
    await repo.markPeriodDays(
        ['2026-01-05', '2026-02-02', '2026-03-02', '2026-03-30']);
    await repo.setNotificationsEnabled(true);
    final scheduler = FakeNotificationScheduler()..pendingIds = {100};
    final reconciler = NotificationReconciler(repo, scheduler,
        clock: () => DateTime(2026, 4, 1, 8));

    reconciler.start();
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await reconciler.idle;

    expect(scheduler.lastReconciledPlan.map((p) => p.id), contains(100));
    expect(scheduler.cancelledIds, isEmpty);
    await reconciler.dispose();
    await db.close();
  });

  test('aviso de atraso: con el ajuste del telefono activado se planifica '
      'el dia siguiente al extremo tardio', () async {
    final db = AppDatabase.forTesting(
        NativeDatabase.memory(setup: enableForeignKeys));
    final repo = CycleRepository(db);
    final scheduler = FakeNotificationScheduler();
    final ajustes = StreamController<DeviceSettings>();
    final reconciler = NotificationReconciler(repo, scheduler,
        clock: () => DateTime(2026, 4, 1, 8), deviceSettings: ajustes.stream);
    // Ciclos de 28: ultimo inicio 30/03, extremo tardio 29/04.
    await repo.markPeriodDays(
        ['2026-01-05', '2026-02-02', '2026-03-02', '2026-03-30']);
    await repo.setNotificationsEnabled(true);

    reconciler.start();
    await Future<void>.delayed(Duration.zero);
    await reconciler.idle;
    expect(scheduler.reconcileCallCount, 0,
        reason: 'espera la primera lectura del ajuste del telefono');

    ajustes.add(const DeviceSettings(avisoAtraso: true));
    await Future<void>.delayed(Duration.zero);
    await reconciler.idle;
    final atraso = scheduler.lastReconciledPlan
        .where((p) => p.kind == NotificationKind.latePeriodReminder)
        .single;
    expect(atraso.date, '2026-04-30');
    expect(atraso.id, 102);

    ajustes.add(const DeviceSettings(avisoAtraso: false));
    await Future<void>.delayed(Duration.zero);
    await reconciler.idle;
    expect(scheduler.pendingIds, isNot(contains(102)));

    await reconciler.dispose();
    await ajustes.close();
    await db.close();
  });

  test('onAppResumed otro dia vuelve a planificar aunque no cambie la zona',
      () async {
    final db = AppDatabase.forTesting(
        NativeDatabase.memory(setup: enableForeignKeys));
    final repo = CycleRepository(db);
    final scheduler = FakeNotificationScheduler();
    var now = DateTime(2026, 4, 1, 8);
    final reconciler =
        NotificationReconciler(repo, scheduler, clock: () => now);
    reconciler.start();
    await Future<void>.delayed(Duration.zero);
    await reconciler.idle;
    final callsBefore = scheduler.reconcileCallCount;

    now = DateTime(2026, 4, 2, 8);
    await reconciler.onAppResumed();
    await reconciler.idle;

    expect(scheduler.reconcileCallCount, callsBefore + 1);
    await reconciler.dispose();
    await db.close();
  });

  group('idsToCancel (regla del scheduler real)', () {
    PlannedNotification item(int id, {bool due = false}) => PlannedNotification(
          kind: NotificationKind.values
              .firstWhere((k) => k.notificationId == id),
          id: id,
          date: '2026-04-01',
          hour: 9,
          minute: 0,
          title: 't',
          body: 'b',
          due: due,
        );

    test('cancela los propios que no estan en el plan; no toca ajenos', () {
      expect(
        idsToCancel(
            pendingIds: [100, 101, 7], ownedIds: [100, 101, 102],
            plan: [item(100)]),
        {101},
      );
    });

    test('uno vencido hoy (due) no se cancela', () {
      expect(
        idsToCancel(
            pendingIds: [100], ownedIds: [100, 101, 102],
            plan: [item(100, due: true)]),
        isEmpty,
      );
    });
  });
}
