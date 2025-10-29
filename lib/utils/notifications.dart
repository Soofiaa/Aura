import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    tzdata.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettings = InitializationSettings(
      android: androidSettings,
    );

    await _notificationsPlugin.initialize(initializationSettings);
  }

  static Future<void> mostrarNotificacion({
    required String titulo,
    required String cuerpo,
    int id = 0,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'aura_channel',
      'Aura Notificaciones',
      channelDescription: 'Recordatorios del ciclo menstrual',
      importance: Importance.high,
      priority: Priority.high,
    );

    const notificationDetails = NotificationDetails(android: androidDetails);
    await _notificationsPlugin.show(id, titulo, cuerpo, notificationDetails);
  }

  static Future<void> programarNotificacion({
    required int id,
    required String titulo,
    required String cuerpo,
    required DateTime fechaHora,
  }) async {
    await _notificationsPlugin.zonedSchedule(
      id,
      titulo,
      cuerpo,
      tz.TZDateTime.from(fechaHora, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'aura_channel',
          'Aura Notificaciones',
          channelDescription: 'Recordatorios de predicciones',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
    );
  }

  static Future<void> cancelarNotificacion(int id) async {
    await _notificationsPlugin.cancel(id);
  }

  static Future<void> cancelarTodas() async {
    await _notificationsPlugin.cancelAll();
  }
}
