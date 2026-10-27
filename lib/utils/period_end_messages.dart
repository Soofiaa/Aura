import 'package:intl/intl.dart';

import '../domain/current_period.dart';
import 'aura_localizations.dart';

/// "12 de julio" (requiere initializeDateFormatting, que main.dart llama
/// al arrancar).
String dayMonthLabel(String dayKey) =>
    DateFormat(auraIsEnglish ? 'MMMM d' : "d 'de' MMMM", auraLanguage)
        .format(DateTime.parse(dayKey));

/// Mensaje para la usuaria cuando no se puede terminar el periodo que
/// empezo en [periodStart] en el dia elegido (ver checkPeriodEnd). Lo
/// usan Inicio y, mas adelante, el Calendario.
String periodEndProblemMessage(PeriodEndCheck check, String periodStart) {
  return switch (check.problem!) {
    PeriodEndProblem.beforeStart => tr(
        'Ese día es anterior al inicio de tu período. Elige un día desde el '
            '${dayMonthLabel(periodStart)}.',
        'That day is before your period started. Choose a day from '
            '${dayMonthLabel(periodStart)} on.'),
    PeriodEndProblem.future => tr(
        'No puedes elegir un día que todavía no llegó.',
        "You can't choose a day that hasn't happened yet."),
    PeriodEndProblem.markedDaysAfter => check.markedDaysAfter == 1
        ? tr(
            'Después de ese día hay 1 día marcado. Quítalo primero o elige '
                'otro día.',
            'There is 1 logged day after that day. Remove it first or '
                'choose another day.')
        : tr(
            'Después de ese día hay ${check.markedDaysAfter} días marcados. '
                'Quítalos primero o elige otro día.',
            'There are ${check.markedDaysAfter} logged days after that day. '
                'Remove them first or choose another day.'),
    PeriodEndProblem.noBleedingThatDay => tr(
        'Ese día lo registraste sin sangrado, así que no puede ser el último '
            'día de tu período. Elige otro día.',
        "You logged that day with no bleeding, so it can't be the last day "
            'of your period. Choose another day.'),
  };
}

/// "Periodo terminado hoy." / "Periodo terminado el 12 de julio."
String periodEndedMessage(String endDate, String today) => endDate == today
    ? tr('Período terminado hoy.', 'Period ended today.')
    : tr('Período terminado el ${dayMonthLabel(endDate)}.',
        'Period ended on ${dayMonthLabel(endDate)}.');
