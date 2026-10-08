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
  /// FlutterLocalNotificationsScheduler.reconcile: se cancela todo id
  /// pendiente que no este en el plan nuevo.
  Set<int> pendingIds = {};
  final List<int> cancelledIds = [];

  @override
  Future<void> reconcile(List<PlannedNotification> plan) async {
    reconcileCallCount++;
    lastReconciledPlan = plan;
    final planned = {for (final p in plan) p.id};
    cancelledIds.addAll(pendingIds.difference(planned));
    pendingIds = planned;
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCallCount++;
    lastReconciledPlan = const [];
  }

  @override
  Future<void> scheduleTestNotification({
    Duration delay = const Duration(seconds: 10),
  }) async {}

  @override
  Future<bool> resyncTimeZone() async {
    final changed = simulateTimeZoneChange;
    simulateTimeZoneChange = false;
    return changed;
  }
}
