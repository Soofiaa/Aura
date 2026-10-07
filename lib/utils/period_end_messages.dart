import 'package:intl/intl.dart';

import '../domain/current_period.dart';

/// "12 de julio" (requiere initializeDateFormatting, que main.dart llama
/// al arrancar).
String dayMonthLabel(String dayKey) =>
    DateFormat("d 'de' MMMM", 'es_ES').format(DateTime.parse(dayKey));

/// Mensaje para la usuaria cuando no se puede terminar el periodo que
/// empezo en [periodStart] en el dia elegido (ver checkPeriodEnd). Lo
/// usan Inicio y, mas adelante, el Calendario.
String periodEndProblemMessage(PeriodEndCheck check, String periodStart) {
  return switch (check.problem!) {
    PeriodEndProblem.beforeStart =>
      'Ese día es anterior al inicio de tu período. Elige un día desde el '
          '${dayMonthLabel(periodStart)}.',
    PeriodEndProblem.future => 'No puedes elegir un día que todavía no llegó.',
    PeriodEndProblem.markedDaysAfter => check.markedDaysAfter == 1
        ? 'Después de ese día hay 1 día marcado. Quítalo primero o elige '
            'otro día.'
        : 'Después de ese día hay ${check.markedDaysAfter} días marcados. '
            'Quítalos primero o elige otro día.',
    PeriodEndProblem.noBleedingThatDay =>
      'Ese día lo registraste sin sangrado, así que no puede ser el último '
          'día de tu período. Elige otro día.',
  };
}

/// "Periodo terminado hoy." / "Periodo terminado el 12 de julio."
String periodEndedMessage(String endDate, String today) => endDate == today
    ? 'Período terminado hoy.'
    : 'Período terminado el ${dayMonthLabel(endDate)}.';

