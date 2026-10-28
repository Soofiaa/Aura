import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
// latest_all, no latest: latest deja fuera los alias y nombres antiguos
// (America/Buenos_Aires, Asia/Calcutta, Etc/UTC...) que algunos telefonos
// todavia informan.
import 'package:timezone/data/latest_all.dart' as tzdata;

import '../domain/notification_planner.dart';
import 'aura_localizations.dart';

/// Unica capa que toca el plugin de notificaciones y el reloj de
/// plataforma. planNotifications (dominio, puro) decide QUE avisos
/// corresponden; esto solo los programa.
abstract class NotificationScheduler {
  Future<void> init();

  Future<bool> hasPermission();

  /// Pide el permiso POST_NOTIFICATIONS (Android 13+). Debe llamarse
  /// solo cuando la usuaria activa el interruptor general, no al abrir
  /// la app.
  Future<bool> requestPermission();

  /// Programa exactamente lo que hay en [plan] y cancela cualquier aviso
  /// propio que haya quedado agendado de antes y ya no corresponda
  /// (toggle apagado, prediccion que dejo de justificarlo, etc).
  Future<void> reconcile(List<PlannedNotification> plan);

  Future<void> cancelAll();

  /// Vuelve a consultar la zona horaria del dispositivo y reconfigura
  /// tz.local si cambio. Devuelve true si cambio (quien llama debe
  /// reconciliar de nuevo con las fechas ya reinterpretadas en la zona
  /// correcta).
  Future<bool> resyncTimeZone();
}

const _periodChannelId = 'aura_period_reminder';
String get _periodChannelName => tr('Recordatorio de período', 'Period reminder');
String get _periodChannelDescription =>
    tr('Aviso antes del inicio estimado de tu período.',
        'A heads-up before your period is estimated to start.');

const _fertileChannelId = 'aura_fertile_window_reminder';
String get _fertileChannelName => tr('Ventana fértil', 'Fertile window');
String get _fertileChannelDescription =>
    tr('Aviso al comenzar tu ventana de mayor fertilidad estimada.',
        'A heads-up when your estimated fertile window begins.');

const _lateChannelId = 'aura_late_period_reminder';
String get _lateChannelName => tr('Período atrasado', 'Late period');
String get _lateChannelDescription =>
    tr('Aviso el primer día de atraso de tu período estimado.',
        'A heads-up on the first day your estimated period is late.');

const _dailyChannelId = 'aura_daily_log_reminder';
String get _dailyChannelName => tr('Recordatorio diario', 'Daily reminder');
String get _dailyChannelDescription =>
    tr('Aviso diario para registrar cómo estuvo tu día.',
        'A daily reminder to log how your day went.');

/// Avisos propios pendientes que ya no corresponden: todo id de
/// [ownedIds] que no este en [plan]. Uno [PlannedNotification.due] del plan
/// no se cancela (ni se vuelve a programar): Android puede no haberlo
/// entregado todavia.
Set<int> idsToCancel({
  required Iterable<int> pendingIds,
  required Iterable<int> ownedIds,
  required List<PlannedNotification> plan,
}) {
  final owned = ownedIds.toSet();
  final planned = {for (final p in plan) p.id};
  return {
    for (final id in pendingIds)
      if (owned.contains(id) && !planned.contains(id)) id,
  };
}

/// Zona de tz para el nombre que informa el telefono. Un nombre que la
/// base de timezone no conoce (zona nueva, o "GMT+03:00" de algunas ROMs)
/// no debe impedir abrir la app: se usa Etc/GMT con el desfase actual en
/// horas enteras, o UTC. Requiere tzdata.initializeTimeZones().
tz.Location resolveTimeZoneLocation(String? name, Duration offset) {
  if (name != null) {
    try {
      return tz.getLocation(name);
    } on tz.LocationNotFoundException {
      // Sigue con el desfase.
    }
  }
  if (offset.inMinutes % 60 == 0 && offset.inHours != 0) {
    // Etc/GMT invierte el signo: Etc/GMT+3 es UTC-3.
    final hours = -offset.inHours;
    try {
      return tz.getLocation('Etc/GMT${hours > 0 ? '+' : ''}$hours');
    } on tz.LocationNotFoundException {
      // Desfase fuera de -14..+12: UTC.
    }
  }
  return tz.UTC;
}

class FlutterLocalNotificationsScheduler implements NotificationScheduler {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static final List<int> _ownedIds =
      NotificationKind.values.map((k) => k.notificationId).toList();

  @override
  Future<void> init() async {
    tzdata.initializeTimeZones();
    await _syncTimeZoneLocation();

    // Icono pequeno de notificacion: silueta blanca sobre transparente
    // (Android solo usa su transparencia). Se busca por nombre, asi que
    // res/raw/keep.xml evita que shrinkResources lo elimine en release.
    const androidSettings = AndroidInitializationSettings('ic_stat_aura');
    const initializationSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(initializationSettings);
  }

  Future<void> _syncTimeZoneLocation() async {
    String? name;
    try {
      name = await FlutterTimezone.getLocalTimezone();
    } catch (_) {
      // Sin nombre se usa el desfase actual (ver resolveTimeZoneLocation).
    }
    tz.setLocalLocation(
        resolveTimeZoneLocation(name, DateTime.now().timeZoneOffset));
  }

  @override
  Future<bool> resyncTimeZone() async {
    final previous = tz.local.name;
    await _syncTimeZoneLocation();
    return tz.local.name != previous;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> hasPermission() async =>
      await _android?.areNotificationsEnabled() ?? false;

  @override
  Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? false;

  @override
  Future<void> reconcile(List<PlannedNotification> plan) async {
    final pending = await _plugin.pendingNotificationRequests();
    final toCancel = idsToCancel(
      pendingIds: pending.map((r) => r.id),
      ownedIds: _ownedIds,
      plan: plan,
    );
    // Un fallo en un aviso no impide cancelar ni programar los demas; el
    // primero se relanza al final (el reconciliador lo absorbe).
    Object? firstError;
    for (final id in toCancel) {
      try {
        await _plugin.cancel(id);
      } catch (e) {
        firstError ??= e;
      }
    }
    for (final item in plan.where((p) => !p.due)) {
      try {
        await _scheduleOne(item);
      } catch (e) {
        firstError ??= e;
      }
    }
    if (firstError != null) throw firstError;
  }

  Future<void> _scheduleOne(PlannedNotification item) async {
    final parts = item.date.split('-');
    final scheduled = tz.TZDateTime(
      tz.local,
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
      item.hour,
      item.minute,
    );

    await _plugin.zonedSchedule(
      item.id,
      item.title,
      item.body,
      scheduled,
      _detailsFor(item.kind),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: item.kind == NotificationKind.dailyLogReminder
          ? DateTimeComponents.time
          : null,
    );
  }

  NotificationDetails _detailsFor(NotificationKind kind) {
    final (channelId, channelName, channelDescription) = switch (kind) {
      NotificationKind.periodReminder => (
          _periodChannelId,
          _periodChannelName,
          _periodChannelDescription,
        ),
      NotificationKind.fertileWindowReminder => (
          _fertileChannelId,
          _fertileChannelName,
          _fertileChannelDescription,
        ),
      NotificationKind.latePeriodReminder => (
          _lateChannelId,
          _lateChannelName,
          _lateChannelDescription,
        ),
      NotificationKind.dailyLogReminder => (
          _dailyChannelId,
          _dailyChannelName,
          _dailyChannelDescription,
        ),
    };

    // NOTA: flutter_local_notifications 19.5.0 tampoco expone
    // `publicVersion` en AndroidNotificationDetails (la API nativa de
    // Android si lo tiene). Sin esto, en pantalla de bloqueo
    // segura Android muestra su propio placeholder generico del
    // sistema (icono + nombre de la app) en vez de un publicVersion
    // redactado por la app - igual de discreto en la practica, pero no
    // es texto nuestro. Si se actualiza el plugin y agrega soporte,
    // vale la pena agregarlo aca.
    final android = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      visibility: NotificationVisibility.private,
    );

    return NotificationDetails(android: android);
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();
}
