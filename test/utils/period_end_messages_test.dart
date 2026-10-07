import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aura/domain/current_period.dart';
import 'package:aura/utils/period_end_messages.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  const start = '2026-07-10';

  String message(PeriodEndProblem problem, [int after = 0]) =>
      periodEndProblemMessage(
          PeriodEndCheck(problem: problem, markedDaysAfter: after), start);

  test('cada problema tiene su propio mensaje', () {
    final messages = {
      message(PeriodEndProblem.beforeStart),
      message(PeriodEndProblem.future),
      message(PeriodEndProblem.markedDaysAfter, 2),
      message(PeriodEndProblem.noBleedingThatDay),
    };
    expect(messages, hasLength(4));
  });

  test('beforeStart nombra el inicio del periodo', () {
    expect(message(PeriodEndProblem.beforeStart),
        'Ese día es anterior al inicio de tu período. Elige un día desde el '
        '10 de julio.');
  });

  test('future', () {
    expect(message(PeriodEndProblem.future),
        'No puedes elegir un día que todavía no llegó.');
  });

  test('markedDaysAfter en singular y plural', () {
    expect(message(PeriodEndProblem.markedDaysAfter, 1),
        'Después de ese día hay 1 día marcado. Quítalo primero o elige otro '
        'día.');
    expect(message(PeriodEndProblem.markedDaysAfter, 3),
        'Después de ese día hay 3 días marcados. Quítalos primero o elige '
        'otro día.');
  });

  test('noBleedingThatDay', () {
    expect(message(PeriodEndProblem.noBleedingThatDay),
        'Ese día lo registraste sin sangrado, así que no puede ser el último '
        'día de tu período. Elige otro día.');
  });

  test('periodEndedMessage: hoy u otro dia', () {
    expect(periodEndedMessage('2026-07-15', '2026-07-15'),
        'Período terminado hoy.');
    expect(periodEndedMessage('2026-07-12', '2026-07-15'),
        'Período terminado el 12 de julio.');
  });
}
