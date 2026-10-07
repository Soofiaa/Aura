import 'package:flutter_test/flutter_test.dart';

import 'package:aura/domain/range_selection.dart';

/// Dias 'yyyy-MM-dd' de julio de 2026 (fechas inventadas).
String _jul(int day) => '2026-07-${day.toString().padLeft(2, '0')}';

RangeSelection _taps(List<String> days) {
  var selection = RangeSelection.empty;
  for (final day in days) {
    selection = selection.tap(day);
  }
  return selection;
}

void _expectRange(RangeSelection s, String start, String? end) {
  expect(s.start, start, reason: 'inicio');
  expect(s.end, end, reason: 'final');
}

void main() {
  group('RangeSelection.tap: tabla de U-1 (opciones A + B)', () {
    test('vacio + toque X: inicio X, sin final', () {
      final s = RangeSelection.empty.tap(_jul(10));
      _expectRange(s, _jul(10), null);
      expect(s.hasOnlyStart, isTrue);
      expect(s.dayCount, 1);
    });

    test('solo inicio X + dia posterior Y: rango X-Y', () {
      _expectRange(_taps([_jul(10), _jul(12)]), _jul(10), _jul(12));
    });

    test('solo inicio X + dia anterior Y: rango Y-X', () {
      _expectRange(_taps([_jul(12), _jul(10)]), _jul(10), _jul(12));
    });

    test('solo inicio X + el mismo X: rango de 1 dia X-X', () {
      final s = _taps([_jul(10), _jul(10)]);
      _expectRange(s, _jul(10), _jul(10));
      expect(s.isComplete, isTrue);
      expect(s.dayCount, 1);
    });

    test('completo X-Z + dia posterior a Z: alarga', () {
      _expectRange(_taps([_jul(10), _jul(12), _jul(14)]), _jul(10), _jul(14));
    });

    test('completo X-Z + dia anterior a X: mueve el inicio', () {
      _expectRange(_taps([_jul(10), _jul(12), _jul(8)]), _jul(8), _jul(12));
    });

    test('completo X-Z + dia de adentro: acorta el final', () {
      _expectRange(_taps([_jul(10), _jul(13), _jul(11)]), _jul(10), _jul(11));
    });

    test('completo X-Z + X (el inicio): rango de 1 dia X-X (crit. 17)', () {
      final s = _taps([_jul(10), _jul(12), _jul(10)]);
      _expectRange(s, _jul(10), _jul(10));
      expect(s.dayCount, 1);
    });

    test('completo X-Z + Z (el final): sin cambios (crit. 17)', () {
      _expectRange(_taps([_jul(10), _jul(12), _jul(12)]), _jul(10), _jul(12));
    });

    test('rango de 1 dia X-X + X: sigue igual', () {
      _expectRange(_taps([_jul(10), _jul(10), _jul(10)]), _jul(10), _jul(10));
    });

    test('ningun toque reinicia un rango completo (crit. 16)', () {
      // Varios toques seguidos sobre un rango completo siempre lo
      // ajustan, nunca vuelven a "solo inicio".
      var s = _taps([_jul(10), _jul(12)]);
      for (final day in [_jul(15), _jul(5), _jul(7), _jul(20), _jul(5)]) {
        s = s.tap(day);
        expect(s.isComplete, isTrue, reason: 'tras tocar $day');
      }
    });
  });

  group('criterios de U-1 en la especificacion', () {
    test('8: tocar 10, 11 y 12 -> rango 10-12, 3 dias', () {
      final s = _taps([_jul(10), _jul(11), _jul(12)]);
      _expectRange(s, _jul(10), _jul(12));
      expect(s.dayCount, 3);
    });

    test('9: tocar 10 y 12 -> rango 10-12, 3 dias', () {
      expect(_taps([_jul(10), _jul(12)]).dayCount, 3);
    });

    test('10: con 10-12 listo, tocar el 8 -> rango 8-12', () {
      _expectRange(_taps([_jul(10), _jul(12), _jul(8)]), _jul(8), _jul(12));
    });

    test('11: con 10-12 listo, tocar el 11 -> el final pasa a 11', () {
      _expectRange(_taps([_jul(10), _jul(12), _jul(11)]), _jul(10), _jul(11));
    });

    test('13: los dias del rango son exactamente los de inicio a final', () {
      expect(_taps([_jul(10), _jul(12)]).days, [_jul(10), _jul(11), _jul(12)]);
      expect(_taps([_jul(10)]).days, [_jul(10)]);
      expect(RangeSelection.empty.days, isEmpty);
    });

    test('14: "Cancelar seleccion" vuelve a cero', () {
      final s = _taps([_jul(10), _jul(12)]).cleared();
      expect(s.isEmpty, isTrue);
      expect(s.dayCount, 0);
    });

    test('15 y 18: alcanzar mas de 10 dias por extension lo marca como largo',
        () {
      final ten = _taps([_jul(1), _jul(10)]);
      expect(ten.dayCount, 10);
      expect(ten.isLong, isFalse);
      final eleven = ten.tap(_jul(11));
      expect(eleven.dayCount, 11);
      expect(eleven.isLong, isTrue);
    });

    test('18: un rango puede cruzar de mes', () {
      final s = _taps(['2026-06-28', '2026-07-03']);
      expect(s.dayCount, 6);
      expect(s.days.first, '2026-06-28');
      expect(s.days.last, '2026-07-03');
    });

    test('el valor del umbral de rango largo sigue siendo 10', () {
      expect(longRangeConfirmationThreshold, 10);
    });
  });

  group('rangeEndAction (R-1, con la condicion de la decision 5)', () {
    const today = '2026-07-15';

    RangeEndAction action(List<String> range, List<String> existing) =>
        rangeEndAction(
          rangeDays: range,
          existingPeriodDays: existing,
          today: today,
        );

    test('termina hace 2 dias o mas y es el ultimo dia: se cierra', () {
      expect(action([_jul(11), _jul(12), _jul(13)], const []),
          RangeEndAction.close);
    });

    test('caso 19: termina ayer: se pregunta', () {
      expect(action([_jul(13), _jul(14)], const []), RangeEndAction.ask);
    });

    test('termina hoy: se pregunta', () {
      expect(action([_jul(14), _jul(15)], const []), RangeEndAction.ask);
    });

    test(
        'el ultimo dia del rango no es el ultimo del periodo resultante: solo '
        'se marca (el cierre existente sigue valiendo)', () {
      expect(action([_jul(11), _jul(12)], [_jul(10), _jul(13), _jul(14)]),
          RangeEndAction.markOnly);
    });

    test(
        'rango justo despues de un periodo cerrado (lo reabre, R-4) y termina '
        'hace 2 dias o mas: se cierra en el ultimo dia del rango', () {
      expect(action([_jul(11), _jul(12)], [_jul(8), _jul(9), _jul(10)]),
          RangeEndAction.close);
    });

    test('un dia marcado mas de 7 dias despues es otro periodo: no impide', () {
      expect(
          action([_jul(1), _jul(2)], [_jul(11)]), RangeEndAction.close);
    });

    test('rango sobre dias ya marcados: se decide igual por su ultimo dia', () {
      expect(action([_jul(10), _jul(11)], [_jul(10), _jul(11)]),
          RangeEndAction.close);
    });

    test('rango que termina en el futuro (no deberia ocurrir): solo se marca',
        () {
      expect(action([_jul(16)], const []), RangeEndAction.markOnly);
    });

    test('rango vacio: solo se marca (nada)', () {
      expect(action(const [], const []), RangeEndAction.markOnly);
    });
  });
}
