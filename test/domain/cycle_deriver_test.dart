import 'package:flutter_test/flutter_test.dart';
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
}
