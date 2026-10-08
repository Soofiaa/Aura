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
}
