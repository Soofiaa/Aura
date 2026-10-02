import 'package:flutter_test/flutter_test.dart';
import 'package:aura/utils/day_key.dart';

void main() {
  group('DayKey.fromDate', () {
    test('formatea year/month/day con ceros a la izquierda', () {
      expect(DayKey.fromDate(DateTime(2026, 1, 5)), '2026-01-05');
      expect(DayKey.fromDate(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });

  group('DayKey.diffInDays', () {
    test('dias consecutivos normales', () {
      expect(DayKey.diffInDays('2026-01-01', '2026-01-02'), 1);
      expect(DayKey.diffInDays('2026-01-02', '2026-01-01'), -1);
    });

    test('cruce de mes y de anio', () {
      expect(DayKey.diffInDays('2025-12-31', '2026-01-01'), 1);
      expect(DayKey.diffInDays('2025-01-01', '2026-01-01'), 365);
    });

    // Chile retrasa el reloj (fin de horario de verano) la madrugada del
    // 2026-04-04/05: ese dia local tiene 25 horas. Con DateTime local,
    // difference().inDays podria truncar mal. Con anclas DateTime.utc
    // (que ignoran la hora real) el resultado debe ser exactamente 1.
    test('cambio de hora de otono 2026-04-04/05 (dia de 25 horas)', () {
      expect(DayKey.diffInDays('2026-04-04', '2026-04-05'), 1);
      expect(DayKey.diffInDays('2026-04-03', '2026-04-06'), 3);
    });

    // Chile adelanta el reloj (inicio de horario de verano) la madrugada
    // del 2026-09-05/06 (ano electoral/calendario sujeto a decreto, se
    // prueban los 3 dias de la ventana 09-05/06/07 igual): ese dia local
    // tiene 23 horas.
    test('cambio de hora de primavera 2026-09-05/06/07 (dia de 23 horas)', () {
      expect(DayKey.diffInDays('2026-09-05', '2026-09-06'), 1);
      expect(DayKey.diffInDays('2026-09-06', '2026-09-07'), 1);
      expect(DayKey.diffInDays('2026-09-05', '2026-09-07'), 2);
    });
  });

  group('DayKey.addDays', () {
    test('suma simple', () {
      expect(DayKey.addDays('2026-01-01', 1), '2026-01-02');
    });

    test('suma que cruza el cambio de hora de abril sin perder un dia', () {
      expect(DayKey.addDays('2026-04-04', 1), '2026-04-05');
      expect(DayKey.addDays('2026-04-04', 3), '2026-04-07');
    });

    test('suma que cruza el cambio de hora de septiembre sin perder un dia', () {
      expect(DayKey.addDays('2026-09-05', 1), '2026-09-06');
      expect(DayKey.addDays('2026-09-05', 2), '2026-09-07');
    });

    test('suma que cruza fin de anio', () {
      expect(DayKey.addDays('2026-12-31', 1), '2027-01-01');
    });
  });

  group('DayKey.compare / isBefore', () {
    test('orden lexicografico coincide con orden cronologico', () {
      expect(DayKey.compare('2026-01-01', '2026-01-02') < 0, isTrue);
      expect(DayKey.isBefore('2026-01-01', '2026-01-02'), isTrue);
      expect(DayKey.isBefore('2026-01-02', '2026-01-01'), isFalse);
    });
  });
}
