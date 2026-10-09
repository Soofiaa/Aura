import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

import '../domain/notification_planner.dart';

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

  /// Para el boton de debug: programa un aviso generico sin pasar por
  /// planNotifications, solo para validar permiso/zona horaria en el
  /// telefono sin esperar dias.
  Future<void> scheduleTestNotification({Duration delay});

  /// Vuelve a consultar la zona horaria del dispositivo y reconfigura
  /// tz.local si cambio. Devuelve true si cambio (quien llama debe
  /// reconciliar de nuevo con las fechas ya reinterpretadas en la zona
  /// correcta).
  Future<bool> resyncTimeZone();
}

const _periodChannelId = 'aura_period_reminder';
const _periodChannelName = 'Recordatorio de período';
const _periodChannelDescription =
    'Aviso antes del inicio estimado de tu período.';

const _fertileChannelId = 'aura_fertile_window_reminder';
const _fertileChannelName = 'Ventana fértil';
const _fertileChannelDescription =
    'Aviso al comenzar tu ventana de mayor fertilidad estimada.';

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
    final name = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(name));
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
    final plannedIds = plan.map((p) => p.id).toSet();
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      if (_ownedIds.contains(request.id) && !plannedIds.contains(request.id)) {
        await _plugin.cancel(request.id);
      }
    }
    for (final item in plan) {
      await _scheduleOne(item);
    }
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
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
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
    };

    // NOTA: flutter_local_notifications 17.1.2 no expone `publicVersion`
    // en AndroidNotificationDetails (a diferencia de la API nativa de
    // Android, que si lo tiene). Sin esto, en pantalla de bloqueo
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

  @override
  Future<void> scheduleTestNotification({
    Duration delay = const Duration(seconds: 10),
  }) async {
    final when = tz.TZDateTime.now(tz.local).add(delay);
    await _plugin.zonedSchedule(
      999,
      'Aura: prueba',
      'Si ves este aviso, Aura puede enviarte notificaciones en tu teléfono.',
      when,
      _detailsFor(NotificationKind.periodReminder),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}
