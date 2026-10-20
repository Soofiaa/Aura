import 'package:aura/domain/notification_planner.dart';
import 'package:aura/utils/notifications.dart';

/// Scheduler falso para tests: no toca ningun canal de plataforma, solo
/// registra que se le pidio hacer.
class FakeNotificationScheduler implements NotificationScheduler {
  bool permissionGranted = true;
  int initCallCount = 0;
  int requestPermissionCallCount = 0;
  int cancelAllCallCount = 0;
  int reconcileCallCount = 0;
  List<PlannedNotification> lastReconciledPlan = const [];

  /// Si es true, la proxima llamada a resyncTimeZone() informa un
  /// cambio de zona (y se resetea a false).
  bool simulateTimeZoneChange = false;

  @override
  Future<void> init() async {
    initCallCount++;
  }

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<bool> requestPermission() async {
    requestPermissionCallCount++;
    return permissionGranted;
  }

  /// Ids agendados ahora y los cancelados, con la misma regla que
  /// FlutterLocalNotificationsScheduler.reconcile (idsToCancel): se cancela
  /// todo id pendiente que no este en el plan nuevo; uno `due` no se
  /// programa, pero si seguia pendiente se queda.
  Set<int> pendingIds = {};
  final List<int> cancelledIds = [];

  /// Si no es null, reconcile espera este Future antes de aplicar el plan
  /// (para simular un scheduler lento).
  Future<void>? delay;

  /// Si es true, reconcile lanza (despues de contar la llamada).
  bool throwOnReconcile = false;

  @override
  Future<void> reconcile(List<PlannedNotification> plan) async {
    reconcileCallCount++;
    if (delay != null) await delay;
    if (throwOnReconcile) throw StateError('falla simulada');
    lastReconciledPlan = plan;
    final toCancel = idsToCancel(
      pendingIds: pendingIds,
      ownedIds: NotificationKind.values.map((k) => k.notificationId),
      plan: plan,
    );
    cancelledIds.addAll(toCancel);
    pendingIds = {
      for (final p in plan)
        if (!p.due || pendingIds.contains(p.id)) p.id,
    };
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCallCount++;
    lastReconciledPlan = const [];
  }

  @override
  Future<bool> resyncTimeZone() async {
    final changed = simulateTimeZoneChange;
    simulateTimeZoneChange = false;
    return changed;
  }
}
