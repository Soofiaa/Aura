import 'package:flutter_test/flutter_test.dart';
import 'package:aura/domain/contraceptive.dart';

ContraceptiveReminder _r(ContraceptiveMethod m, [String start = '2026-04-01']) =>
    ContraceptiveReminder(method: m, startDate: start, hour: 21, minute: 0);

void main() {
  group('contraceptiveEvents', () {
    test('parche: nuevo, cambio, cambio, quitar, y otro ciclo', () {
      expect(contraceptiveEvents(_r(ContraceptiveMethod.patch), '2026-04-01', 5),
          [
            ('2026-04-01', ContraceptiveAction.applyPatch),
            ('2026-04-08', ContraceptiveAction.changePatch),
            ('2026-04-15', ContraceptiveAction.changePatch),
            ('2026-04-22', ContraceptiveAction.removePatch),
            ('2026-04-29', ContraceptiveAction.applyPatch),
          ]);
    });

    test('anillo desde la mitad del ciclo', () {
      expect(contraceptiveEvents(_r(ContraceptiveMethod.ring), '2026-04-10', 3),
          [
            ('2026-04-22', ContraceptiveAction.removeRing),
            ('2026-04-29', ContraceptiveAction.insertRing),
            ('2026-05-20', ContraceptiveAction.removeRing),
          ]);
    });

    test('inyecciones: cada 30 y 91 dias, sin incluir el dia ya pasado', () {
      expect(
          contraceptiveEvents(
                  _r(ContraceptiveMethod.monthlyInjection), '2026-04-02', 2)
              .map((e) => e.$1),
          ['2026-05-01', '2026-05-31']);
      expect(
          contraceptiveEvents(
                  _r(ContraceptiveMethod.quarterlyInjection), '2026-04-02', 1)
              .single,
          ('2026-07-01', ContraceptiveAction.injection));
    });

    test('inicio en el futuro: empieza ese dia', () {
      expect(
          contraceptiveEvents(_r(ContraceptiveMethod.ring, '2026-04-05'),
                  '2026-04-01', 1)
              .single,
          ('2026-04-05', ContraceptiveAction.insertRing));
    });
  });

  group('JSON', () {
    test('ida y vuelta', () {
      for (final r in [
        _r(ContraceptiveMethod.patch),
        const ContraceptiveReminder(
            method: ContraceptiveMethod.pill, hour: 7, minute: 30),
      ]) {
        expect(ContraceptiveReminder.fromJson(r.toJson()), r);
      }
    });

    test('invalido: null', () {
      for (final raw in [
        null,
        {'metodo': 'chip', 'hora': 9, 'minuto': 0},
        {'metodo': 'ring', 'hora': 9, 'minuto': 0}, // sin inicio
        {'metodo': 'ring', 'inicio': '2026-02-30', 'hora': 9, 'minuto': 0},
        {'metodo': 'pill', 'hora': 24, 'minuto': 0},
      ]) {
        expect(ContraceptiveReminder.fromJson(raw), isNull, reason: '$raw');
      }
    });
  });
}
