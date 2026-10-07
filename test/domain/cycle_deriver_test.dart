import 'package:flutter_test/flutter_test.dart';
import 'package:aura/data/models/day_enums.dart';
import 'package:aura/domain/cycle_deriver.dart';

void main() {
  group('deriveCycles', () {
    test('sin datos devuelve lista vacia', () {
      expect(deriveCycles([]), isEmpty);
    });

    test('un solo periodo: un ciclo abierto (cycleLengthDays null)', () {
      final result = deriveCycles([
        '2026-03-01',
        '2026-03-02',
        '2026-03-03',
        '2026-03-04',
        '2026-03-05',
      ]);

      expect(result, hasLength(1));
      expect(result.single.startDate, '2026-03-01');
      expect(result.single.periodLengthDays, 5);
      expect(result.single.cycleLengthDays, isNull);
    });

    test('ciclos regulares de 28 dias con periodos de 5 dias', () {
      final periodDays = <String>[];
      // 3 periodos de 5 dias cada 28 dias, empezando el 2026-01-01.
      for (var cycle = 0; cycle < 3; cycle++) {
        final start = DateTime(2026, 1, 1).add(Duration(days: cycle * 28));
        for (var d = 0; d < 5; d++) {
          final day = start.add(Duration(days: d));
          periodDays.add(
            '${day.year.toString().padLeft(4, '0')}-'
            '${day.month.toString().padLeft(2, '0')}-'
            '${day.day.toString().padLeft(2, '0')}',
          );
        }
      }

      final result = deriveCycles(periodDays);

      expect(result, hasLength(3));
      expect(result[0].startDate, '2026-01-01');
      expect(result[0].periodLengthDays, 5);
      expect(result[0].cycleLengthDays, 28);
      expect(result[1].cycleLengthDays, 28);
      expect(result[2].cycleLengthDays, isNull); // ultimo ciclo, abierto
    });

    test('un dia olvidado dentro del periodo no parte el ciclo en dos', () {
      // Dia 3 nunca se registro, pero el hueco (2 dias) esta dentro de
      // maxGapWithinPeriod (7), asi que sigue siendo un solo periodo.
      final result = deriveCycles([
        '2026-05-01',
        '2026-05-02',
        '2026-05-04',
        '2026-05-05',
      ]);

      expect(result, hasLength(1));
      expect(result.single.startDate, '2026-05-01');
      expect(result.single.periodLengthDays, 5); // 05-01 a 05-05 inclusive
    });

    test('borrar un dia en medio del periodo no lo parte en dos', () {
      const original = [
        '2026-06-10',
        '2026-06-11',
        '2026-06-12',
        '2026-06-13',
        '2026-06-14',
      ];
      final sinMedio = [...original]..remove('2026-06-12');

      final result = deriveCycles(sinMedio);

      expect(result, hasLength(1));
      expect(result.single.startDate, '2026-06-10');
      expect(result.single.periodLengthDays, 5); // 06-10 a 06-14 inclusive
    });

    test('un hueco mayor a maxGapWithinPeriod si parte el ciclo en dos', () {
      final result = deriveCycles([
        '2026-07-01',
        '2026-07-02',
        // hueco de 9 dias > maxGapWithinPeriod (7)
        '2026-07-11',
        '2026-07-12',
      ]);

      expect(result, hasLength(2));
      expect(result[0].startDate, '2026-07-01');
      expect(result[0].cycleLengthDays, 10);
      expect(result[1].startDate, '2026-07-11');
      expect(result[1].cycleLengthDays, isNull);
    });

    test('cruce de anio: periodo que empieza en diciembre y sigue en enero', () {
      final result = deriveCycles([
        '2026-12-30',
        '2026-12-31',
        '2027-01-01',
        '2027-01-02',
      ]);

      expect(result, hasLength(1));
      expect(result.single.startDate, '2026-12-30');
      expect(result.single.periodLengthDays, 4);
    });

    test(
        'fechas alrededor del cambio de hora de otono chileno 2026-04-04/05 '
        'dan duraciones exactas', () {
      final result = deriveCycles([
        '2026-04-03',
        '2026-04-04',
        '2026-04-05',
        '2026-04-06',
      ]);

      expect(result, hasLength(1));
      expect(result.single.periodLengthDays, 4);
    });

    test(
        'fechas alrededor del cambio de hora de primavera chileno '
        '2026-09-05/06/07 dan duraciones y ciclos exactos', () {
      final result = deriveCycles([
        '2026-09-05',
        '2026-09-06',
        '2026-09-07',
      ]);

      expect(result, hasLength(1));
      expect(result.single.startDate, '2026-09-05');
      expect(result.single.periodLengthDays, 3);

      // Dos ciclos cuyo inicio cae justo a cada lado del cambio de hora:
      // la duracion del ciclo debe seguir siendo exactamente 28 dias.
      final conSiguienteCiclo = deriveCycles([
        '2026-09-05',
        '2026-09-06',
        '2026-09-07',
        '2026-10-03', // 2026-09-05 + 28 dias
        '2026-10-04',
      ]);
      expect(conSiguienteCiclo, hasLength(2));
      expect(conSiguienteCiclo[0].cycleLengthDays, 28);
    });
  });

  group('deriveCycles - periodConfirmedEnded', () {
    test('sin explicitNonPeriodDays: false por defecto (retrocompatible)',
        () {
      final result = deriveCycles(['2026-01-01', '2026-01-02']);
      expect(result.single.periodConfirmedEnded, isFalse);
    });

    test('un "no" explicito el dia siguiente al ultimo sangrado confirma el '
        'fin del periodo', () {
      final result = deriveCycles(
        ['2026-01-01', '2026-01-02', '2026-01-03'],
        explicitNonPeriodDays: ['2026-01-04'],
      );
      expect(result.single.periodConfirmedEnded, isTrue);
    });

    test('un "no" explicito dentro de maxGapWithinPeriod (7) confirma, pero '
        'no cambia el agrupamiento ni periodLengthDays', () {
      final result = deriveCycles(
        ['2026-01-01', '2026-01-02', '2026-01-03'],
        explicitNonPeriodDays: ['2026-01-08'], // +5 dias, dentro de 7
      );
      expect(result.single.periodConfirmedEnded, isTrue);
      expect(result.single.periodLengthDays, 3);
    });

    test('un "no" explicito mas alla de maxGapWithinPeriod no confirma nada '
        '(esta demasiado lejos para decir algo sobre ESTE periodo)', () {
      final result = deriveCycles(
        ['2026-01-01', '2026-01-02', '2026-01-03'],
        explicitNonPeriodDays: ['2026-01-20'],
      );
      expect(result.single.periodConfirmedEnded, isFalse);
    });

    test('un "no" explicito ANTES del ultimo dia de sangrado no confirma '
        'nada (dato contradictorio, se ignora)', () {
      final result = deriveCycles(
        ['2026-01-05', '2026-01-06', '2026-01-07'],
        explicitNonPeriodDays: ['2026-01-04'],
      );
      expect(result.single.periodConfirmedEnded, isFalse);
    });

    test('cada periodo evalua su propio "no" explicito por separado', () {
      final result = deriveCycles(
        [
          '2026-01-01', '2026-01-02', '2026-01-03', // periodo 1
          '2026-02-01', '2026-02-02', '2026-02-03', // periodo 2 (abierto)
        ],
        explicitNonPeriodDays: ['2026-01-04'], // solo confirma el periodo 1
      );
      expect(result, hasLength(2));
      expect(result[0].periodConfirmedEnded, isTrue);
      expect(result[1].periodConfirmedEnded, isFalse);
    });
  });
  group('deriveCycles - periodEnd e isClosed (D-1)', () {
    test('sin periodEnds: periodEnd null e isClosed false por defecto', () {
      final result = deriveCycles(['2026-01-01', '2026-01-02']);
      expect(result.single.periodEnd, isNull);
      expect(result.single.isClosed, isFalse);
    });

    test(
        'period_end en el ultimo dia cierra el periodo sin cambiar '
        'periodConfirmedEnded', () {
      final result = deriveCycles(
        ['2026-01-01', '2026-01-02', '2026-01-03'],
        periodEnds: {'2026-01-03': PeriodEndSource.inferred},
      );
      expect(result.single.periodEnd, PeriodEndSource.inferred);
      expect(result.single.isClosed, isTrue);
      expect(result.single.periodConfirmedEnded, isFalse,
          reason: 'periodConfirmedEnded sigue siendo solo la regla del "no"');
    });

    test('un "no" explicito solo tambien deja el periodo cerrado', () {
      final result = deriveCycles(
        ['2026-01-01', '2026-01-02'],
        explicitNonPeriodDays: ['2026-01-03'],
      );
      expect(result.single.periodEnd, isNull);
      expect(result.single.isClosed, isTrue);
    });

    test('"no" explicito y period_end juntos: cerrado', () {
      final result = deriveCycles(
        ['2026-01-01', '2026-01-02'],
        explicitNonPeriodDays: ['2026-01-03'],
        periodEnds: {'2026-01-02': PeriodEndSource.declared},
      );
      expect(result.single.periodConfirmedEnded, isTrue);
      expect(result.single.periodEnd, PeriodEndSource.declared);
      expect(result.single.isClosed, isTrue);
    });

    test(
        'period_end en un dia interior no cuenta (R-4): marcar el dia '
        'siguiente reabre el periodo', () {
      final result = deriveCycles(
        ['2026-01-01', '2026-01-02', '2026-01-03', '2026-01-04'],
        periodEnds: {'2026-01-03': PeriodEndSource.declared},
      );
      expect(result.single.periodLengthDays, 4);
      expect(result.single.periodEnd, isNull);
      expect(result.single.isClosed, isFalse);
    });

    test(
        'quitar el dia que seguia al fin declarado: el fin vuelve a valer '
        '(R-4)', () {
      const ends = {'2026-01-03': PeriodEndSource.declared};
      final reabierto = deriveCycles(
        ['2026-01-01', '2026-01-02', '2026-01-03', '2026-01-04'],
        periodEnds: ends,
      );
      final sinElDiaNuevo = deriveCycles(
        ['2026-01-01', '2026-01-02', '2026-01-03'],
        periodEnds: ends,
      );
      expect(reabierto.single.isClosed, isFalse);
      expect(sinElDiaNuevo.single.periodEnd, PeriodEndSource.declared);
      expect(sinElDiaNuevo.single.isClosed, isTrue);
    });

    test('cada periodo toma solo el period_end de su propio ultimo dia', () {
      final result = deriveCycles(
        [
          '2026-01-01', '2026-01-02', // periodo 1
          '2026-02-01', '2026-02-02', // periodo 2
        ],
        periodEnds: {'2026-01-02': PeriodEndSource.inferred},
      );
      expect(result[0].periodEnd, PeriodEndSource.inferred);
      expect(result[0].isClosed, isTrue);
      expect(result[1].periodEnd, isNull);
      expect(result[1].isClosed, isFalse);
    });

    test(
        'un period_end en una fecha que no es dia marcado se ignora (el '
        'CHECK de la base no lo permite)', () {
      final result = deriveCycles(
        ['2026-01-01', '2026-01-02'],
        periodEnds: {'2026-01-05': PeriodEndSource.declared},
      );
      expect(result.single.periodEnd, isNull);
      expect(result.single.isClosed, isFalse);
    });

    test('la igualdad de CycleSummary considera periodEnd', () {
      const a = CycleSummary(
        startDate: '2026-01-01',
        periodLengthDays: 3,
        cycleLengthDays: null,
      );
      const b = CycleSummary(
        startDate: '2026-01-01',
        periodLengthDays: 3,
        cycleLengthDays: null,
        periodEnd: PeriodEndSource.inferred,
      );
      expect(a == b, isFalse);
      expect(
        b,
        const CycleSummary(
          startDate: '2026-01-01',
          periodLengthDays: 3,
          cycleLengthDays: null,
          periodEnd: PeriodEndSource.inferred,
        ),
      );
    });
  });
}
