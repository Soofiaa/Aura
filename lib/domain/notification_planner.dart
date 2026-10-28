import '../utils/aura_localizations.dart';
import '../utils/day_key.dart';
import 'contraceptive.dart';
import 'cycle_predictor.dart';
import 'fertile_marks.dart';

enum NotificationKind {
  periodReminder,
  fertileWindowReminder,

  /// "Te llego?": el primer dia de atraso del periodo.
  latePeriodReminder,

  /// Registrar el dia: se repite cada dia a la misma hora.
  dailyLogReminder,

  /// La pastilla: se repite cada dia a su hora.
  pillReminder,

  /// Parche, anillo o inyeccion: usa [contraceptiveSlots] ids seguidos.
  contraceptiveReminder,
}

/// Los avisos de parche, anillo e inyeccion programan los proximos varios
/// eventos, por si la app no se abre en semanas: uno por id, desde el de
/// [NotificationKind.contraceptiveReminder].
const contraceptiveSlots = 3;

extension NotificationKindId on NotificationKind {
  /// Id estable por tipo: reprogramar reemplaza la notificacion anterior
  /// del mismo tipo en vez de acumular una nueva cada vez.
  int get notificationId => switch (this) {
        NotificationKind.periodReminder => 100,
        NotificationKind.fertileWindowReminder => 101,
        NotificationKind.latePeriodReminder => 102,
        NotificationKind.dailyLogReminder => 103,
        NotificationKind.pillReminder => 104,
        NotificationKind.contraceptiveReminder => 105, // y 106, 107
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

  /// Aviso "Te llego?" (ajuste de este telefono, ver DeviceSettings): un
  /// aviso el dia siguiente al extremo tardio del rango del proximo
  /// periodo, si para entonces no se registro.
  final bool latePeriodReminderEnabled;

  /// Recordatorio diario de registro (ajuste de este telefono).
  final bool dailyLogReminderEnabled;

  /// Recordatorio de anticonceptivo (ajuste de este telefono), con su hora.
  final ContraceptiveReminder? contraceptive;

  const NotificationSettings({
    required this.notificationsEnabled,
    required this.periodReminderEnabled,
    required this.fertileWindowRemindersEnabled,
    required this.showDetailsEnabled,
    required this.reminderHour,
    required this.reminderMinute,
    this.showFertileWindow = true,
    this.latePeriodReminderEnabled = false,
    this.dailyLogReminderEnabled = false,
    this.contraceptive,
  });

  NotificationSettings copyWith(
          {bool? latePeriodReminderEnabled,
          bool? dailyLogReminderEnabled,
          ContraceptiveReminder? contraceptive}) =>
      NotificationSettings(
        notificationsEnabled: notificationsEnabled,
        periodReminderEnabled: periodReminderEnabled,
        fertileWindowRemindersEnabled: fertileWindowRemindersEnabled,
        showDetailsEnabled: showDetailsEnabled,
        reminderHour: reminderHour,
        reminderMinute: reminderMinute,
        showFertileWindow: showFertileWindow,
        latePeriodReminderEnabled:
            latePeriodReminderEnabled ?? this.latePeriodReminderEnabled,
        dailyLogReminderEnabled:
            dailyLogReminderEnabled ?? this.dailyLogReminderEnabled,
        contraceptive: contraceptive ?? this.contraceptive,
      );
}

class PlannedNotification {
  final NotificationKind kind;
  final int id;
  final String date; // 'yyyy-MM-dd'
  final int hour;
  final int minute;
  final String title;
  final String body;

  /// Su instante ya paso hoy (solo con `keepDueToday`): no se vuelve a
  /// programar (el plugin rechaza un instante pasado), pero tampoco se
  /// cancela si sigue pendiente. Con avisos inexactos Android puede
  /// entregarlo unos minutos despues de la hora; abrir la app en ese rato
  /// no debe perderlo.
  final bool due;

  const PlannedNotification({
    required this.kind,
    required this.id,
    required this.date,
    required this.hour,
    required this.minute,
    required this.title,
    required this.body,
    this.due = false,
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
      other.body == body &&
      other.due == due;

  @override
  int get hashCode =>
      Object.hash(kind, id, date, hour, minute, title, body, due);

  @override
  String toString() =>
      'PlannedNotification(kind: $kind, date: $date, hour: $hour, '
      'minute: $minute, title: $title${due ? ', due' : ''})';
}

/// Funcion pura: sin reloj propio, sin plataforma. [today] y
/// [nowMinutesOfDay] son el "ahora" inyectado (igual filosofia que
/// predictCycle con `today`), para poder testear con fechas y horas
/// fijas y para poder omitir avisos cuyo instante ya paso hoy -
/// programar un instante pasado tira una excepcion en el plugin.
///
/// [keepDueToday]: un aviso de hoy cuya hora ya paso vuelve con
/// [PlannedNotification.due] en vez de omitirse (ver ese campo). Lo usa el
/// reconciliador; sin el, el plan es solo lo que falta programar.
///
/// [loggedToday]: hoy ya tiene registro, asi que el recordatorio diario
/// empieza manana.
List<PlannedNotification> planNotifications({
  required CyclePrediction? prediction,
  required NotificationSettings settings,
  required String today,
  required int nowMinutesOfDay,
  bool keepDueToday = false,
  bool loggedToday = false,
}) {
  if (!settings.notificationsEnabled) return const [];
  final planned = <PlannedNotification>[];

  // Sin prediccion tambien (sin datos o en embarazo). Se repite solo cada
  // dia; la fecha es solo la primera vez: hoy si aun no se registro ni
  // paso la hora, si no manana. Nunca "due": a la hora ya pasada se
  // programa el de manana, que sigue repitiendose.
  if (settings.dailyLogReminderEnabled) {
    final passed = settings.reminderHour * 60 + settings.reminderMinute <=
        nowMinutesOfDay;
    planned.add(_dailyLogReminder(
        loggedToday || passed ? DayKey.addDays(today, 1) : today, settings));
  }

  // Tambien sin prediccion, a su propia hora. La pastilla se repite sola
  // como el recordatorio diario; los demas metodos, en sus fechas.
  final c = settings.contraceptive;
  if (c != null) {
    final passed = c.hour * 60 + c.minute <= nowMinutesOfDay;
    if (c.method == ContraceptiveMethod.pill) {
      planned.add(_contraceptiveReminder(
          NotificationKind.pillReminder.notificationId,
          passed ? DayKey.addDays(today, 1) : today,
          ContraceptiveAction.takePill,
          c,
          settings,
          false));
    } else {
      // Nunca "due": un due no se cancela ni se reprograma, y en su id podia
      // quedar el aviso de otro metodo. El de hoy ya pasado se salta.
      var slot = 0;
      for (final (date, action)
          in contraceptiveEvents(c, today, contraceptiveSlots + 1)) {
        if (slot == contraceptiveSlots) break;
        if (date == today && passed) continue;
        planned.add(_contraceptiveReminder(
            NotificationKind.contraceptiveReminder.notificationId + slot++,
            date,
            action,
            c,
            settings,
            false));
      }
    }
  }

  if (prediction is! ActivePrediction) return planned;

  void add(String date,
      PlannedNotification Function(String date, bool due) build) {
    final cmp = DayKey.compare(date, today);
    if (cmp < 0) return; // fecha pasada
    // Mismo dia: solo si el instante exacto todavia no paso.
    final due = cmp == 0 &&
        settings.reminderHour * 60 + settings.reminderMinute <=
            nowMinutesOfDay;
    if (due && !keepDueToday) return;
    planned.add(build(date, due));
  }

  if (settings.periodReminderEnabled) {
    add(DayKey.addDays(prediction.nextPeriodEarliestDate, -1),
        (date, due) => _periodReminder(date, settings, due));
  }

  // Confianza baja => no se manda: la estimacion de ovulacion ya depende
  // de la del proximo periodo (se le resta la fase lutea), asi que es
  // menos confiable todavia. Mandar un aviso de "ventana fertil" ahi
  // seria falsa precision: Inicio tampoco muestra la ovulacion ni la
  // ventana con confianza baja (HU-05, H5-1 A). Tampoco si la usuaria
  // eligio no ver la ovulacion ni la ventana (H5-3).
  // La regla es la de Inicio y el Calendario (visibleFertileMarks): con el
  // periodo atrasado o una ovulacion que caeria en el periodo tampoco.
  final marks = visibleFertileMarks(prediction,
      showFertileWindow: settings.showFertileWindow);
  if (settings.fertileWindowRemindersEnabled && marks != null) {
    add(marks.windowStartDate,
        (date, due) => _fertileWindowReminder(date, settings, due));
  }

  // "Te llego?": el primer dia de atraso (isPeriodLate empieza el dia
  // siguiente al extremo tardio). Registrar el periodo cambia la
  // prediccion y lo deja fuera del plan; si ya paso ese dia, no se repite.
  if (settings.latePeriodReminderEnabled) {
    add(DayKey.addDays(prediction.nextPeriodLatestDate, 1),
        (date, due) => _latePeriodReminder(date, settings, due));
  }

  planned.sort((a, b) => DayKey.compare(a.date, b.date));
  return planned;
}

PlannedNotification _periodReminder(
    String date, NotificationSettings s, bool due) {
  final detailed = s.showDetailsEnabled;
  return PlannedNotification(
    kind: NotificationKind.periodReminder,
    id: NotificationKind.periodReminder.notificationId,
    date: date,
    hour: s.reminderHour,
    minute: s.reminderMinute,
    title: detailed
        ? tr('Tu período podría estar por comenzar',
            'Your period may be about to start')
        : tr('Aura: recordatorio', 'Aura: reminder'),
    body: detailed
        ? tr('Según la estimación de tu ciclo, tu período podría empezar pronto.',
            'Based on your cycle estimate, your period may start soon.')
        : tr('Abre la app para ver el detalle.', 'Open the app to see the details.'),
    due: due,
  );
}

PlannedNotification _fertileWindowReminder(
    String date, NotificationSettings s, bool due) {
  final detailed = s.showDetailsEnabled;
  return PlannedNotification(
    kind: NotificationKind.fertileWindowReminder,
    id: NotificationKind.fertileWindowReminder.notificationId,
    date: date,
    hour: s.reminderHour,
    minute: s.reminderMinute,
    title: detailed
        ? tr('Ventana de mayor fertilidad (estimación)',
            'Fertile window (estimate)')
        : tr('Aura: recordatorio', 'Aura: reminder'),
    body: detailed
        ? tr(
            'Según la estimación de tu ciclo, hoy comienza tu ventana de mayor '
                'probabilidad de fertilidad. No es un método anticonceptivo.',
            'Based on your cycle estimate, your fertile window starts today. '
                'This is not a method of birth control.')
        : tr('Abre la app para ver el detalle.', 'Open the app to see the details.'),
    due: due,
  );
}

PlannedNotification _dailyLogReminder(String date, NotificationSettings s) =>
    PlannedNotification(
      kind: NotificationKind.dailyLogReminder,
      id: NotificationKind.dailyLogReminder.notificationId,
      date: date,
      hour: s.reminderHour,
      minute: s.reminderMinute,
      title: s.showDetailsEnabled
          ? tr('¿Cómo estuvo tu día?', 'How was your day?')
          : tr('Aura: recordatorio', 'Aura: reminder'),
      body: s.showDetailsEnabled
          ? tr('Registra cómo te sientes en Aura.',
              'Log how you feel in Aura.')
          : tr('Abre la app para ver el detalle.',
              'Open the app to see the details.'),
    );

PlannedNotification _contraceptiveReminder(
    int id,
    String date,
    ContraceptiveAction action,
    ContraceptiveReminder c,
    NotificationSettings s,
    bool due) {
  final (title, body) = switch (action) {
    ContraceptiveAction.takePill => (
        tr('Hora de tu pastilla', 'Time for your pill'),
        tr('Recuerda tomar tu anticonceptivo.',
            'Remember to take your birth control.'),
      ),
    ContraceptiveAction.applyPatch => (
        tr('Hoy toca parche nuevo', 'New patch today'),
        tr('Empieza un ciclo: ponte un parche nuevo.',
            'A new cycle starts: put on a new patch.'),
      ),
    ContraceptiveAction.changePatch => (
        tr('Hoy toca cambiar el parche', 'Change your patch today'),
        tr('Quítate el parche y ponte uno nuevo.',
            'Take off your patch and put on a new one.'),
      ),
    ContraceptiveAction.removePatch => (
        tr('Hoy toca quitarte el parche', 'Take off your patch today'),
        tr('Empieza tu semana sin parche.', 'Your patch-free week starts.'),
      ),
    ContraceptiveAction.insertRing => (
        tr('Hoy toca anillo nuevo', 'New ring today'),
        tr('Ponte un anillo nuevo.', 'Insert a new ring.'),
      ),
    ContraceptiveAction.removeRing => (
        tr('Hoy toca quitarte el anillo', 'Remove your ring today'),
        tr('Empieza tu semana sin anillo.', 'Your ring-free week starts.'),
      ),
    ContraceptiveAction.injection => (
        tr('Hoy toca tu inyección', 'Injection due today'),
        tr('Recuerda tu inyección anticonceptiva.',
            'Remember your birth control injection.'),
      ),
  };
  final detailed = s.showDetailsEnabled;
  return PlannedNotification(
    kind: action == ContraceptiveAction.takePill
        ? NotificationKind.pillReminder
        : NotificationKind.contraceptiveReminder,
    id: id,
    date: date,
    hour: c.hour,
    minute: c.minute,
    title: detailed ? title : tr('Aura: recordatorio', 'Aura: reminder'),
    body: detailed
        ? body
        : tr('Abre la app para ver el detalle.',
            'Open the app to see the details.'),
    due: due,
  );
}

PlannedNotification _latePeriodReminder(
    String date, NotificationSettings s, bool due) {
  final detailed = s.showDetailsEnabled;
  return PlannedNotification(
    kind: NotificationKind.latePeriodReminder,
    id: NotificationKind.latePeriodReminder.notificationId,
    date: date,
    hour: s.reminderHour,
    minute: s.reminderMinute,
    title: detailed
        ? tr('¿Te llegó el período?', 'Did your period start?')
        : tr('Aura: recordatorio', 'Aura: reminder'),
    body: detailed
        ? tr(
            'Según la estimación de tu ciclo, tu período podría estar '
                'atrasado. Si ya empezó, puedes registrarlo en Aura.',
            'Based on your cycle estimate, your period may be late. '
                'If it already started, you can log it in Aura.')
        : tr('Abre la app para ver el detalle.', 'Open the app to see the details.'),
    due: due,
  );
}
