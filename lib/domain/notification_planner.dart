import '../utils/day_key.dart';
import 'cycle_predictor.dart';

enum NotificationKind { periodReminder, fertileWindowReminder }

extension NotificationKindId on NotificationKind {
  /// Id estable por tipo: reprogramar reemplaza la notificacion anterior
  /// del mismo tipo en vez de acumular una nueva cada vez.
  int get notificationId => switch (this) {
        NotificationKind.periodReminder => 100,
        NotificationKind.fertileWindowReminder => 101,
      };
}

class NotificationSettings {
  /// Interruptor GENERAL: controla el permiso de Android y si se
  /// programa cualquier aviso. Si esta apagado, planNotifications no
  /// devuelve nada sin importar los demas toggles.
  final bool notificationsEnabled;
  final bool periodReminderEnabled;
  final bool fertileWindowRemindersEnabled;
  final bool showDetailsEnabled;
  final int reminderHour;
  final int reminderMinute;

  /// "Mostrar ovulacion y ventana fertil" (HU-05, H5-3). Apagado, no se
  /// planifica el aviso fertil aunque [fertileWindowRemindersEnabled]
  /// siga activado (se conserva su valor).
  final bool showFertileWindow;

  const NotificationSettings({
    required this.notificationsEnabled,
    required this.periodReminderEnabled,
    required this.fertileWindowRemindersEnabled,
    required this.showDetailsEnabled,
    required this.reminderHour,
    required this.reminderMinute,
    this.showFertileWindow = true,
  });
}

class PlannedNotification {
  final NotificationKind kind;
  final int id;
  final String date; // 'yyyy-MM-dd'
  final int hour;
  final int minute;
  final String title;
  final String body;

  const PlannedNotification({
    required this.kind,
    required this.id,
    required this.date,
    required this.hour,
    required this.minute,
    required this.title,
    required this.body,
  });

  @override
  bool operator ==(Object other) =>
      other is PlannedNotification &&
      other.kind == kind &&
      other.id == id &&
      other.date == date &&
      other.hour == hour &&
      other.minute == minute &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode => Object.hash(kind, id, date, hour, minute, title, body);

  @override
  String toString() =>
      'PlannedNotification(kind: $kind, date: $date, hour: $hour, minute: $minute, title: $title)';
}

/// Funcion pura: sin reloj propio, sin plataforma. [today] y
/// [nowMinutesOfDay] son el "ahora" inyectado (igual filosofia que
/// predictCycle con `today`), para poder testear con fechas y horas
/// fijas y para poder omitir avisos cuyo instante ya paso hoy -
/// programar un instante pasado tira una excepcion en el plugin.
List<PlannedNotification> planNotifications({
  required CyclePrediction? prediction,
  required NotificationSettings settings,
  required String today,
  required int nowMinutesOfDay,
}) {
  if (!settings.notificationsEnabled) return const [];
  if (prediction is! ActivePrediction) return const [];

  final planned = <PlannedNotification>[];

  if (settings.periodReminderEnabled) {
    final date = DayKey.addDays(prediction.nextPeriodEarliestDate, -1);
    if (_isStillPending(date, settings, today, nowMinutesOfDay)) {
      planned.add(_periodReminder(date, settings));
    }
  }

  // Confianza baja => no se manda: la estimacion de ovulacion ya depende
  // de la del proximo periodo (se le resta la fase lutea), asi que es
  // menos confiable todavia. Mandar un aviso de "ventana fertil" ahi
  // seria falsa precision: Inicio tampoco muestra la ovulacion ni la
  // ventana con confianza baja (HU-05, H5-1 A). Tampoco si la usuaria
  // eligio no ver la ovulacion ni la ventana (H5-3).
  if (settings.fertileWindowRemindersEnabled &&
      settings.showFertileWindow &&
      prediction.confidence != PredictionConfidence.low) {
    final date = prediction.fertileWindowStartDate;
    if (_isStillPending(date, settings, today, nowMinutesOfDay)) {
      planned.add(_fertileWindowReminder(date, settings));
    }
  }

  planned.sort((a, b) => DayKey.compare(a.date, b.date));
  return planned;
}

bool _isStillPending(
  String date,
  NotificationSettings settings,
  String today,
  int nowMinutesOfDay,
) {
  final cmp = DayKey.compare(date, today);
  if (cmp < 0) return false; // fecha pasada
  if (cmp > 0) return true; // fecha futura: siempre vale
  // mismo dia: solo si el instante exacto todavia no paso.
  final reminderMinutesOfDay = settings.reminderHour * 60 + settings.reminderMinute;
  return reminderMinutesOfDay > nowMinutesOfDay;
}

PlannedNotification _periodReminder(String date, NotificationSettings s) {
  final detailed = s.showDetailsEnabled;
  return PlannedNotification(
    kind: NotificationKind.periodReminder,
    id: NotificationKind.periodReminder.notificationId,
    date: date,
    hour: s.reminderHour,
    minute: s.reminderMinute,
    title: detailed ? 'Tu período podría estar por comenzar' : 'Aura: recordatorio',
    body: detailed
        ? 'Según la estimación de tu ciclo, tu período podría empezar pronto.'
        : 'Abre la app para ver el detalle.',
  );
}

PlannedNotification _fertileWindowReminder(String date, NotificationSettings s) {
  final detailed = s.showDetailsEnabled;
  return PlannedNotification(
    kind: NotificationKind.fertileWindowReminder,
    id: NotificationKind.fertileWindowReminder.notificationId,
    date: date,
    hour: s.reminderHour,
    minute: s.reminderMinute,
    title: detailed ? 'Ventana de mayor fertilidad (estimación)' : 'Aura: recordatorio',
    body: detailed
        ? 'Según la estimación de tu ciclo, hoy comienza tu ventana de mayor '
            'probabilidad de fertilidad. No es un método anticonceptivo.'
        : 'Abre la app para ver el detalle.',
  );
}
