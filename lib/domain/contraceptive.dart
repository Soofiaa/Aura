import '../utils/aura_localizations.dart';
import '../utils/day_key.dart';

enum ContraceptiveMethod {
  /// Todos los dias, sin pausa.
  pill,

  /// Ciclos de 28 dias: un parche nuevo los dias 0, 7 y 14; el 21 se quita.
  patch,

  /// Ciclos de 28 dias: se pone el dia 0 y se quita el 21.
  ring,

  /// Cada 30 dias.
  monthlyInjection,

  /// Cada 13 semanas (91 dias).
  quarterlyInjection,
}

extension ContraceptiveMethodLabel on ContraceptiveMethod {
  String get label => switch (this) {
        ContraceptiveMethod.pill =>
          tr("Pastilla (todos los días)", "Pill (every day)"),
        ContraceptiveMethod.patch => tr(
            "Parche (semanal, con semana de descanso)",
            "Patch (weekly, with a patch-free week)"),
        ContraceptiveMethod.ring => tr(
            "Anillo (3 semanas y 1 de descanso)", "Ring (3 weeks in, 1 out)"),
        ContraceptiveMethod.monthlyInjection => tr(
            "Inyección mensual (cada 30 días)",
            "Monthly injection (every 30 days)"),
        ContraceptiveMethod.quarterlyInjection => tr(
            "Inyección trimestral (cada 13 semanas)",
            "3-month injection (every 13 weeks)"),
      };

  /// Dias entre un inicio de ciclo y el siguiente (1 para la pastilla).
  int get cycleDays => switch (this) {
        ContraceptiveMethod.pill => 1,
        ContraceptiveMethod.patch || ContraceptiveMethod.ring => 28,
        ContraceptiveMethod.monthlyInjection => 30,
        ContraceptiveMethod.quarterlyInjection => 91,
      };
}

enum ContraceptiveAction {
  takePill,
  applyPatch,
  changePatch,
  removePatch,
  insertRing,
  removeRing,
  injection,
}

/// Recordatorio de anticonceptivo de este telefono.
class ContraceptiveReminder {
  const ContraceptiveReminder({
    required this.method,
    this.startDate,
    required this.hour,
    required this.minute,
  }) : assert(method == ContraceptiveMethod.pill || startDate != null);

  final ContraceptiveMethod method;

  /// Dia en que se puso el parche o el anillo de este ciclo, o el de la
  /// ultima inyeccion. La pastilla no lo usa.
  final String? startDate;
  final int hour;
  final int minute;

  Map<String, Object?> toJson() => {
        'metodo': method.name,
        'inicio': startDate,
        'hora': hour,
        'minuto': minute,
      };

  /// null si [raw] no es valido.
  static ContraceptiveReminder? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final method = ContraceptiveMethod.values
        .where((m) => m.name == raw['metodo'])
        .firstOrNull;
    final start = raw['inicio'];
    final hour = raw['hora'];
    final minute = raw['minuto'];
    if (method == null ||
        hour is! int ||
        minute is! int ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }
    if (start is String) {
      try {
        DayKey.toUtcAnchor(start);
      } on FormatException {
        return null;
      }
    } else if (start != null || method != ContraceptiveMethod.pill) {
      return null;
    }
    return ContraceptiveReminder(
        method: method, startDate: start as String?, hour: hour, minute: minute);
  }

  @override
  bool operator ==(Object other) =>
      other is ContraceptiveReminder &&
      other.method == method &&
      other.startDate == startDate &&
      other.hour == hour &&
      other.minute == minute;

  @override
  int get hashCode => Object.hash(method, startDate, hour, minute);

  @override
  String toString() =>
      'ContraceptiveReminder($method, $startDate, $hour:$minute)';
}

/// Los proximos [count] eventos desde [from] (incluido) de un metodo que no
/// es la pastilla, en orden.
List<(String, ContraceptiveAction)> contraceptiveEvents(
    ContraceptiveReminder r, String from, int count) {
  final cycle = r.method.cycleDays;
  final Map<int, ContraceptiveAction> byDay = switch (r.method) {
    ContraceptiveMethod.pill => throw ArgumentError('la pastilla es diaria'),
    ContraceptiveMethod.patch => {
        0: ContraceptiveAction.applyPatch,
        7: ContraceptiveAction.changePatch,
        14: ContraceptiveAction.changePatch,
        21: ContraceptiveAction.removePatch,
      },
    ContraceptiveMethod.ring => {
        0: ContraceptiveAction.insertRing,
        21: ContraceptiveAction.removeRing,
      },
    ContraceptiveMethod.monthlyInjection ||
    ContraceptiveMethod.quarterlyInjection =>
      {0: ContraceptiveAction.injection},
  };
  final start = r.startDate!;
  final events = <(String, ContraceptiveAction)>[];
  var day = DayKey.isBefore(from, start) ? start : from;
  while (events.length < count) {
    final action = byDay[DayKey.diffInDays(start, day) % cycle];
    if (action != null) events.add((day, action));
    day = DayKey.addDays(day, 1);
  }
  return events;
}
