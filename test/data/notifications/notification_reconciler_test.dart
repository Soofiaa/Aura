import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/notifications/notification_reconciler.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/domain/notification_planner.dart';

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
}
