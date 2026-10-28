import 'dart:async';

import '../../domain/cycle_predictor.dart';
import '../../domain/notification_planner.dart';
import '../../utils/day_key.dart';
import '../../utils/notifications.dart';
import '../device_settings_store.dart';
import '../repositories/cycle_repository.dart';

/// Unica suscripcion, viva mientras la app esta abierta, que combina los
/// datos del ciclo con los ajustes de notificaciones y mantiene lo
/// programado al dia. No vive atada al ciclo de vida de ninguna
/// pantalla en particular (ni siquiera home_screen): las notificaciones
/// deben seguir correctas aunque la usuaria este viendo otra pestana.
class NotificationReconciler {
  /// [deviceSettings]: el aviso "Te llego?" (ajuste de este telefono). Sin
  /// el, ese aviso queda apagado.
  NotificationReconciler(
    this._repository,
    this._scheduler, {
    DateTime Function()? clock,
    Stream<DeviceSettings>? deviceSettings,
  })  : _clock = clock ?? DateTime.now,
        _deviceSettingsStream = deviceSettings;

  final CycleRepository _repository;
  final NotificationScheduler _scheduler;
  final DateTime Function() _clock;
  final Stream<DeviceSettings>? _deviceSettingsStream;

  // Null hasta la primera emision de cada stream: con un plan armado sin
  // los ciclos se cancelaria todo lo programado al abrir la app.
  PredictionInputs? _inputs;
  NotificationSettings? _settings;
  DeviceSettings? _deviceSettings;

  StreamSubscription<PredictionInputs>? _cyclesSub;
  StreamSubscription<NotificationSettings>? _settingsSub;
  StreamSubscription<DeviceSettings>? _deviceSettingsSub;

  // Un reconcile a la vez: dos corridas solapadas podian programar un
  // aviso despues de que la otra lo cancelara (interruptor apagado y aviso
  // programado igual). Lo que llega mientras corre se junta en una sola
  // corrida mas, con los ultimos datos.
  Future<void>? _running;
  bool _pending = false;

  /// Dia del ultimo plan: al volver a la app otro dia se planifica de nuevo
  /// aunque no haya cambiado nada (el plan depende de "hoy").
  String? _lastPlannedDay;

  void start() {
    _cyclesSub = _repository.watchPredictionInputs().listen((inputs) {
      _inputs = inputs;
      _reconcile();
    }, onError: (Object _) {});
    _settingsSub = _repository.watchNotificationSettings().listen((settings) {
      _settings = settings;
      _reconcile();
    }, onError: (Object _) {});
    _deviceSettingsSub = _deviceSettingsStream?.listen((settings) {
      _deviceSettings = settings;
      _reconcile();
    }, onError: (Object _) {
      // Sin leer el ajuste: el aviso de atraso queda apagado.
      _deviceSettings ??= const DeviceSettings();
      _reconcile();
    });
  }

  Future<void> dispose() async {
    await _cyclesSub?.cancel();
    await _settingsSub?.cancel();
    await _deviceSettingsSub?.cancel();
  }

  /// Termina cuando no queda ningun reconcile corriendo ni pendiente.
  Future<void> get idle async {
    while (_running != null) {
      await _running;
    }
  }

  /// Llamar desde AppLifecycleState.resumed. Si la zona horaria del
  /// dispositivo cambio mientras la app estaba en segundo plano (viaje),
  /// resincroniza tz.local y fuerza un reconcile completo: las fechas ya
  /// calculadas deben reinterpretarse en la zona nueva. Tambien si cambio
  /// el dia desde el ultimo plan. No lanza.
  Future<void> onAppResumed() async {
    var changed = false;
    try {
      changed = await _scheduler.resyncTimeZone();
    } catch (_) {
      // Se mantiene la zona anterior.
    }
    if (changed || _lastPlannedDay != DayKey.fromDate(_clock())) {
      _reconcile();
    }
  }

  void _reconcile() {
    if (_inputs == null || _settings == null) return;
    if (_deviceSettingsStream != null && _deviceSettings == null) return;
    if (_running != null) {
      _pending = true;
      return;
    }
    _running = _drain().whenComplete(() => _running = null);
  }

  Future<void> _drain() async {
    do {
      _pending = false;
      try {
        // Solo se lee la base con el recordatorio diario activado.
        final loggedToday = (_deviceSettings?.recordatorioDiario ?? false) &&
            await _repository.getDay(DayKey.fromDate(_clock())) != null;
        await _scheduler.reconcile(_plan(loggedToday));
      } catch (_) {
        // Se reintenta con el proximo cambio de datos o al volver a la app.
        _lastPlannedDay = null;
      }
    } while (_pending);
  }

  List<PlannedNotification> _plan(bool loggedToday) {
    final inputs = _inputs!;
    final today = DayKey.fromDate(_clock());
    _lastPlannedDay = today;
    final prediction = inputs.predictionsPaused
        ? null
        : predictCycle(
            cycles: inputs.cycles,
            today: today,
            config: inputs.config,
          );
    return planNotifications(
      prediction: prediction,
      settings: _settings!.copyWith(
          latePeriodReminderEnabled: _deviceSettings?.avisoAtraso ?? false,
          dailyLogReminderEnabled:
              _deviceSettings?.recordatorioDiario ?? false,
          contraceptive: _deviceSettings?.anticonceptivo),
      today: today,
      nowMinutesOfDay: _nowMinutesOfDay(),
      keepDueToday: true,
      loggedToday: loggedToday,
    );
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
    _notificationReconcilerInstance ??= NotificationReconciler(
      cycleRepository,
      notificationScheduler,
      deviceSettings: deviceSettingsStore.watch(),
    );

/// Solo para tests.
set notificationReconciler(NotificationReconciler value) =>
    _notificationReconcilerInstance = value;
