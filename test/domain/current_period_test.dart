import 'package:flutter_test/flutter_test.dart';

import 'package:aura/data/models/day_enums.dart';
import 'package:aura/domain/current_period.dart';
import 'package:aura/domain/cycle_deriver.dart';

/// "Hoy" de los ejemplos (fechas inventadas).
const _today = '2026-07-15';

/// Dias 'yyyy-MM-dd' de julio de 2026.
String _jul(int day) => '2026-07-${day.toString().padLeft(2, '0')}';
List<String> _julRange(int from, int to) =>
    [for (var d = from; d <= to; d++) _jul(d)];

List<CycleSummary> _cycles(
  List<String> periodDays, {
  List<String> explicitNo = const [],
  Map<String, PeriodEndSource> ends = const {},
}) =>
    deriveCycles(periodDays,
        explicitNonPeriodDays: explicitNo, periodEnds: ends);

void main() {
  group('findCurrentPeriod (periodo mas reciente)', () {
    test('sin periodos: null', () {
      expect(findCurrentPeriod(cycles: const [], today: _today), isNull);
    });

    test('periodo abierto en curso: inicio, ultimo dia marcado y dia N', () {
      final p = findCurrentPeriod(
          cycles: _cycles(_julRange(12, 14)), today: _today)!;
      expect(p.startDate, _jul(12));
      expect(p.lastMarkedDate, _jul(14));
      expect(p.isOpen, isTrue);
      expect(p.dayNumber, 4);
    });

    test('el dia del inicio es el dia 1', () {
      final p = findCurrentPeriod(cycles: _cycles([_today]), today: _today)!;
      expect(p.dayNumber, 1);
    });

    test('periodo mas reciente cerrado: se devuelve cerrado', () {
      final p = findCurrentPeriod(
        cycles: _cycles(_julRange(10, 13),
            ends: {_jul(13): PeriodEndSource.declared}),
        today: _today,
      )!;
      expect(p.isClosed, isTrue);
      expect(p.isOpen, isFalse);
    });

    test('solo cuenta el mas reciente, aunque uno anterior siga abierto', () {
      final p = findCurrentPeriod(
        cycles: _cycles([
          '2026-06-01', '2026-06-02', // abierto, mas antiguo
          ..._julRange(10, 12),
        ]),
        today: _today,
      )!;
      expect(p.startDate, _jul(10));
    });

    test('ultimo dia marcado hace exactamente 7 dias: sigue siendo el actual',
        () {
      final p = findCurrentPeriod(
          cycles: _cycles(_julRange(6, 8)), today: _today);
      expect(p, isNotNull);
    });

    test(
        'ultimo dia marcado hace mas de 7 dias: ya no hay periodo actual (un '
        'dia marcado hoy empezaria otro periodo)', () {
      expect(
          findCurrentPeriod(cycles: _cycles(_julRange(5, 7)), today: _today),
          isNull);
    });

    test('hoy anterior al inicio (reloj atrasado): null', () {
      expect(
          findCurrentPeriod(cycles: _cycles(_julRange(16, 17)), today: _today),
          isNull);
    });
  });

  group('estimatedPeriodDays (E-1)', () {
    List<String> estimate(List<String> periodDays,
            {int typical = 5,
            String today = _today,
            Map<String, PeriodEndSource> ends = const {},
            List<String> explicitNo = const []}) =>
        estimatedPeriodDays(
          cycles: _cycles(periodDays, explicitNo: explicitNo, ends: ends),
          typicalPeriodLengthDays: typical,
          today: today,
        );

    test(
        'caso 1: abierto 12-14, duracion habitual 5, hoy 15 -> estimados 15 '
        'y 16', () {
      expect(estimate(_julRange(12, 14)), [_jul(15), _jul(16)]);
    });

    test('caso 2: tras "Sigue" (15 marcado) -> estimado solo el 16', () {
      expect(estimate(_julRange(12, 15)), [_jul(16)]);
    });

    test('periodo cerrado (fin guardado o "No"): sin estimados', () {
      expect(
          estimate(_julRange(12, 14),
              ends: {_jul(14): PeriodEndSource.declared}),
          isEmpty);
      expect(estimate(_julRange(12, 14), explicitNo: [_jul(15)]), isEmpty);
    });

    test('periodo igual o mas largo que la duracion habitual: sin estimados',
        () {
      expect(estimate(_julRange(11, 15)), isEmpty);
      expect(estimate(_julRange(9, 15)), isEmpty);
    });

    test('duracion habitual 1: sin estimados', () {
      expect(estimate([_today], typical: 1), isEmpty);
    });

    test('duracion habitual 15 con solo el inicio marcado: 14 estimados', () {
      final days = estimate([_jul(10)], typical: 15);
      expect(days.first, _jul(11));
      expect(days.last, _jul(24));
      expect(days, hasLength(14));
    });

    test('estimados que ya pasaron (dias olvidados) tambien se muestran', () {
      expect(estimate([_jul(5), _jul(6)], today: '2026-07-12'),
          [_jul(7), _jul(8), _jul(9)]);
    });

    test('solo el periodo mas reciente: uno antiguo abierto no tiene', () {
      expect(
        estimate([
          '2026-06-01', // abierto, antiguo
          ..._julRange(10, 12),
        ], ends: {
          _jul(12): PeriodEndSource.declared,
        }),
        isEmpty,
      );
    });

    test('si pasaron mas de 7 dias desde el ultimo dia marcado: sin estimados',
        () {
      expect(estimate([_jul(5)], typical: 15), isEmpty);
    });

    test('sin datos: sin estimados', () {
      expect(estimate(const []), isEmpty);
    });
  });

  group('canConfirmEstimates (decision 4: sin dias futuros)', () {
    test('el ultimo estimado es futuro: no se puede confirmar', () {
      expect(canConfirmEstimates(estimatedDays: [_jul(15), _jul(16)],
              today: _today),
          isFalse);
    });

    test('el ultimo estimado es hoy o ya paso: se puede confirmar', () {
      expect(canConfirmEstimates(estimatedDays: [_jul(14), _jul(15)],
              today: _today),
          isTrue);
      expect(canConfirmEstimates(estimatedDays: [_jul(13)], today: _today),
          isTrue);
    });

    test('sin estimados: no hay nada que confirmar', () {
      expect(canConfirmEstimates(estimatedDays: const [], today: _today),
          isFalse);
    });
  });

  group('checkPeriodEnd (decision 5: "Termino otro dia" / "Termino este dia")',
      () {
    PeriodEndCheck check(String end, List<String> periodDays,
            {String start = '2026-07-10',
            List<String> explicitNo = const []}) =>
        checkPeriodEnd(
          periodStart: start,
          endDate: end,
          today: _today,
          periodDays: periodDays,
          explicitNonPeriodDays: explicitNo,
        );

    test('terminar en el ultimo dia marcado: valido', () {
      expect(check(_jul(13), _julRange(10, 13)).isValid, isTrue);
    });

    test('terminar en un dia sin marcar despues del ultimo (hasta hoy): valido',
        () {
      expect(check(_jul(15), _julRange(10, 13)).isValid, isTrue);
    });

    test('terminar el mismo dia del inicio: valido', () {
      expect(check(_jul(10), [_jul(10)]).isValid, isTrue);
    });

    test('antes del inicio: bloqueado', () {
      final result = check(_jul(9), _julRange(10, 13));
      expect(result.problem, PeriodEndProblem.beforeStart);
    });

    test('dia futuro: bloqueado', () {
      final result = check(_jul(16), _julRange(10, 13));
      expect(result.problem, PeriodEndProblem.future);
    });

    test(
        'caso 5: hay dias marcados despues dentro del mismo periodo: '
        'bloqueado, con cuantos son', () {
      final result = check(_jul(12), _julRange(10, 14));
      expect(result.problem, PeriodEndProblem.markedDaysAfter);
      expect(result.markedDaysAfter, 2);
    });

    test(
        'dia elegido con un "No" explicito: bloqueado (no se puede guardar '
        'el fin en un dia sin sangrado)', () {
      final result =
          check(_jul(14), _julRange(10, 13), explicitNo: [_jul(14)]);
      expect(result.problem, PeriodEndProblem.noBleedingThatDay);
      expect(result.isValid, isFalse);
    });

    test(
        'dia elegido sin registro: sigue siendo valido y se completa al '
        'cerrar', () {
      expect(check(_jul(14), _julRange(10, 13)).isValid, isTrue);
      expect(
        daysToMarkWhenClosing(
          periodStart: _jul(10),
          endDate: _jul(14),
          periodDays: _julRange(10, 13),
          explicitNonPeriodDays: const [],
        ),
        [_jul(14)],
      );
    });

    test('un "No" en otro dia del periodo no bloquea terminar en un dia marcado',
        () {
      expect(
          check(_jul(13), [_jul(10), _jul(11), _jul(13)],
                  explicitNo: [_jul(12)])
              .isValid,
          isTrue);
    });

    test('un periodo posterior (mas de 7 dias despues) no cuenta', () {
      final result = check(
        _jul(3),
        ['2026-07-01', '2026-07-02', '2026-07-03', '2026-07-12'],
        start: '2026-07-01',
      );
      expect(result.isValid, isTrue);
      expect(result.markedDaysAfter, 0);
    });
  });

  group('daysToMarkWhenClosing (decision 3: completar sin pisar un "No")', () {
    test('caso 4: abierto 10-13, terminar el 15 -> se completan 14 y 15', () {
      expect(
        daysToMarkWhenClosing(
          periodStart: _jul(10),
          endDate: _jul(15),
          periodDays: _julRange(10, 13),
          explicitNonPeriodDays: const [],
        ),
        [_jul(14), _jul(15)],
      );
    });

    test('un hueco sin registro se completa', () {
      expect(
        daysToMarkWhenClosing(
          periodStart: _jul(10),
          endDate: _jul(13),
          periodDays: [_jul(10), _jul(11), _jul(13)],
          explicitNonPeriodDays: const [],
        ),
        [_jul(12)],
      );
    });

    test('un "No" explicito en el medio se respeta', () {
      expect(
        daysToMarkWhenClosing(
          periodStart: _jul(10),
          endDate: _jul(13),
          periodDays: [_jul(10), _jul(11), _jul(13)],
          explicitNonPeriodDays: [_jul(12)],
        ),
        isEmpty,
      );
    });

    test('periodo de un dia: no hay nada que completar', () {
      expect(
        daysToMarkWhenClosing(
          periodStart: _today,
          endDate: _today,
          periodDays: [_today],
          explicitNonPeriodDays: const [],
        ),
        isEmpty,
      );
    });

    test('el ultimo dia se completa aunque no estuviera marcado', () {
      expect(
        daysToMarkWhenClosing(
          periodStart: _jul(10),
          endDate: _jul(11),
          periodDays: [_jul(10)],
          explicitNonPeriodDays: const [],
        ),
        [_jul(11)],
      );
    });
  });

  group('needsSingleDayConfirmation (decision 14)', () {
    test('caso 3: inicio y fin el mismo dia: pide confirmacion', () {
      expect(
          needsSingleDayConfirmation(periodStart: _today, endDate: _today),
          isTrue);
    });

    test('mas de un dia: sin confirmacion', () {
      expect(
          needsSingleDayConfirmation(periodStart: _jul(14), endDate: _today),
          isFalse);
    });
  });

  group('periodThatDayWouldJoin (decision 7)', () {
    test('sin periodos: no se suma a nada', () {
      expect(periodThatDayWouldJoin(day: _today, periodDays: const []),
          isNull);
    });

    test('a 7 dias del ultimo dia de un periodo anterior: se suma', () {
      expect(
          periodThatDayWouldJoin(
              day: _jul(15), periodDays: _julRange(6, 8)),
          _jul(8));
    });

    test('a 8 dias: empieza un periodo nuevo', () {
      expect(
          periodThatDayWouldJoin(
              day: _jul(15), periodDays: _julRange(5, 7)),
          isNull);
    });

    test('dia ya marcado: null (no hay nada que avisar)', () {
      expect(
          periodThatDayWouldJoin(
              day: _jul(12), periodDays: _julRange(10, 13)),
          isNull);
    });

    test('un periodo posterior al dia no cuenta', () {
      expect(
          periodThatDayWouldJoin(
              day: _jul(10), periodDays: [_jul(12), _jul(13)]),
          isNull);
    });

    test('usa el dia marcado mas cercano anterior', () {
      expect(
          periodThatDayWouldJoin(
              day: _jul(15), periodDays: [_jul(1), _jul(2), _jul(11)]),
          _jul(11));
    });
  });
}
