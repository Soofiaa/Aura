import 'dart:async';

import '../../domain/cycle_deriver.dart';
import '../../domain/cycle_predictor.dart';
import '../../domain/notification_planner.dart';
import '../../utils/day_key.dart';
import '../../utils/notifications.dart';
import '../repositories/cycle_repository.dart';

/// Unica suscripcion, viva mientras la app esta abierta, que combina los
/// datos del ciclo con los ajustes de notificaciones y mantiene lo
/// programado al dia. No vive atada al ciclo de vida de ninguna
/// pantalla en particular (ni siquiera home_screen): las notificaciones
/// deben seguir correctas aunque la usuaria este viendo otra pestana.
class NotificationReconciler {
  NotificationReconciler(
    this._repository,
    this._scheduler, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final CycleRepository _repository;
  final NotificationScheduler _scheduler;
  final DateTime Function() _clock;

  List<CycleSummary> _cycles = const [];
  NotificationSettings? _settings;

  StreamSubscription<List<CycleSummary>>? _cyclesSub;
  StreamSubscription<NotificationSettings>? _settingsSub;

  void start() {
    _cyclesSub = _repository.watchDerivedCycles().listen((cycles) {
      _cycles = cycles;
      _reconcile();
    });
    _settingsSub = _repository.watchNotificationSettings().listen((settings) {
      _settings = settings;
      _reconcile();
    });
  }

  Future<void> dispose() async {
    await _cyclesSub?.cancel();
    await _settingsSub?.cancel();
  }

  /// Llamar desde AppLifecycleState.resumed. Si la zona horaria del
  /// dispositivo cambio mientras la app estaba en segundo plano (viaje),
  /// resincroniza tz.local y fuerza un reconcile completo: las fechas ya
  /// calculadas deben reinterpretarse en la zona nueva.
  Future<void> onAppResumed() async {
    final changed = await _scheduler.resyncTimeZone();
    if (changed) {
      _reconcile();
    }
  }

  void _reconcile() {
    final settings = _settings;
    if (settings == null) return; // todavia no llego la primera emision

    final today = DayKey.fromDate(_clock());
    final prediction = predictCycle(cycles: _cycles, today: today);
    final plan = planNotifications(
      prediction: prediction,
      settings: settings,
      today: today,
      nowMinutesOfDay: _nowMinutesOfDay(),
    );
    _scheduler.reconcile(plan);
  }

  int _nowMinutesOfDay() {
    final now = _clock();
    return now.hour * 60 + now.minute;
  }
}

NotificationScheduler? _notificationSchedulerInstance;

NotificationScheduler get notificationScheduler =>
    _notificationSchedulerInstance ??= FlutterLocalNotificationsScheduler();

/// Solo para tests: reemplaza el scheduler global (ej. por un
/// FakeNotificationScheduler) antes de montar la UI.
set notificationScheduler(NotificationScheduler value) =>
    _notificationSchedulerInstance = value;

NotificationReconciler? _notificationReconcilerInstance;

NotificationReconciler get notificationReconciler =>
    _notificationReconcilerInstance ??=
        NotificationReconciler(cycleRepository, notificationScheduler);

/// Solo para tests.
set notificationReconciler(NotificationReconciler value) =>
    _notificationReconcilerInstance = value;
