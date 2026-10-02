import 'package:flutter_test/flutter_test.dart';
import 'package:aura/domain/cycle_deriver.dart';
import 'package:aura/domain/cycle_predictor.dart';
import 'package:aura/utils/day_key.dart';

/// Verifica las invariantes que deben cumplirse SIEMPRE en una
/// ActivePrediction, sin importar el escenario.
void _expectCoreInvariants(ActivePrediction p) {
  expect(
    DayKey.diffInDays(p.fertileWindowStartDate, p.estimatedOvulationDate),
    5,
    reason: 'inicio de ventana fertil = ovulacion - 5',
  );
  expect(p.fertileWindowEndDate, p.estimatedOvulationDate,
      reason: 'fin de ventana fertil = ovulacion');
  expect(
    DayKey.diffInDays(p.estimatedOvulationDate, p.nextPeriodExpectedDate),
    14,
    reason: 'ovulacion = proximo periodo esperado - 14',
  );
  expect(
    DayKey.compare(p.nextPeriodEarliestDate, p.nextPeriodExpectedDate) <= 0,
    isTrue,
    reason: 'extremo temprano <= esperado',
  );
  expect(
    DayKey.compare(p.nextPeriodExpectedDate, p.nextPeriodLatestDate) <= 0,
    isTrue,
    reason: 'esperado <= extremo tardio',
  );
}

CycleSummary _cycle(String start, int periodLength, int? cycleLength) =>
    CycleSummary(
      startDate: start,
      periodLengthDays: periodLength,
      cycleLengthDays: cycleLength,
    );

void main() {
  group('predictCycle - casos sin datos / datos minimos', () {
    test('sin datos devuelve null', () {
      expect(predictCycle(cycles: [], today: '2026-01-01'), isNull);
    });

    test('un solo periodo (abierto): confianza baja, default 28 dias', () {
      final result = predictCycle(
        cycles: [_cycle('2026-01-01', 5, null)],
        today: '2026-01-10',
      );

      final p = result as ActivePrediction;
      expect(p.completeCyclesConsidered, 0);
      expect(p.averageCycleLengthDays, 28.0);
      expect(p.averagePeriodLengthDays, 5.0);
      expect(p.confidence, PredictionConfidence.low);
      expect(p.nextPeriodExpectedDate, '2026-01-29');
      expect(p.nextPeriodEarliestDate, '2026-01-26'); // 28-3
      expect(p.nextPeriodLatestDate, DayKey.addDays('2026-01-29', 3));
      _expectCoreInvariants(p);
    });
  });

  group('predictCycle - ciclos regulares', () {
    test('tres ciclos identicos de 28 dias NO dan rango de ancho cero', () {
      final result = predictCycle(
        cycles: [
          _cycle('2026-01-01', 5, 28),
          _cycle('2026-01-29', 5, 28),
          _cycle('2026-02-26', 5, 28),
          _cycle('2026-03-26', 5, null), // abierto
        ],
        today: '2026-03-28',
      );

      final p = result as ActivePrediction;
      expect(p.completeCyclesConsidered, 3);
      expect(p.averageCycleLengthDays, 28.0);
      expect(p.cycleLengthStdDevDays, 0.0);
      // piso de semiancho = 2 dias, aun con desviacion 0.
      expect(p.nextPeriodEarliestDate, isNot(p.nextPeriodLatestDate));
      expect(
        DayKey.diffInDays(p.nextPeriodEarliestDate, p.nextPeriodLatestDate),
        4, // 2*2
      );
      expect(p.confidence, PredictionConfidence.medium); // 3 ciclos, <4
      _expectCoreInvariants(p);
    });

    test('6+ ciclos completos: solo se consideran los ultimos 6 (ventana)',
        () {
      // El ciclo mas viejo (50 dias) debe quedar fuera de la ventana; si
      // entrara, el promedio ponderado se alejaria notoriamente de 28.
      final result = predictCycle(
        cycles: [
          _cycle('2026-01-01', 5, 50),
          _cycle('2026-02-20', 5, 28),
          _cycle('2026-03-20', 5, 28),
          _cycle('2026-04-17', 5, 28),
          _cycle('2026-05-15', 5, 28),
          _cycle('2026-06-12', 5, 28),
          _cycle('2026-07-10', 5, 28),
          _cycle('2026-08-07', 5, null), // abierto, octavo registro
        ],
        today: '2026-08-10',
      );

      final p = result as ActivePrediction;
      expect(p.completeCyclesConsidered, 6);
      expect(p.averageCycleLengthDays, closeTo(28.0, 0.001));
      expect(p.confidence, PredictionConfidence.high); // 6 ciclos, variab. 0
      _expectCoreInvariants(p);
    });
  });

  group('predictCycle - ciclos invalidos y variabilidad', () {
    test('excluye ciclos < 15 o > 60 dias y lo reporta en confidenceReasons',
        () {
      final result = predictCycle(
        cycles: [
          _cycle('2026-01-01', 5, 10), // invalido: < 15
          _cycle('2026-01-11', 5, 28),
          _cycle('2026-02-08', 5, 70), // invalido: > 60
          _cycle('2026-03-10', 5, 28),
          _cycle('2026-04-07', 5, null),
        ],
        today: '2026-04-10',
      );

      final p = result as ActivePrediction;
      expect(p.excludedCyclesCount, 2);
      expect(p.completeCyclesConsidered, 2); // los dos de 28
      expect(p.averageCycleLengthDays, 28.0);
      expect(
        p.confidenceReasons.any((r) => r.contains('Se excluyeron 2')),
        isTrue,
      );
      _expectCoreInvariants(p);
    });

    test('un ciclo de exactamente 60 dias SI es valido (limite inclusive)',
        () {
      final result = predictCycle(
        cycles: [
          _cycle('2026-01-01', 5, 60),
          _cycle('2026-03-02', 5, 28),
          _cycle('2026-03-30', 5, null),
        ],
        today: '2026-04-02',
      );
      final p = result as ActivePrediction;
      expect(p.excludedCyclesCount, 0);
      expect(p.completeCyclesConsidered, 2);
    });

    test('un ciclo de 61 dias SI se excluye', () {
      final result = predictCycle(
        cycles: [
          _cycle('2026-01-01', 5, 61),
          _cycle('2026-03-03', 5, 28),
          _cycle('2026-03-31', 5, null),
        ],
        today: '2026-04-02',
      );
      final p = result as ActivePrediction;
      expect(p.excludedCyclesCount, 1);
      expect(p.completeCyclesConsidered, 1);
    });

    test('ciclos muy irregulares: confianza baja por variabilidad alta', () {
      final result = predictCycle(
        cycles: [
          _cycle('2026-01-01', 5, 18),
          _cycle('2026-01-19', 5, 55),
          _cycle('2026-03-15', 5, 20),
          _cycle('2026-04-04', 5, null),
        ],
        today: '2026-04-06',
      );

      final p = result as ActivePrediction;
      expect(p.completeCyclesConsidered, 3);
      expect(p.confidence, PredictionConfidence.low);
      expect(
        p.confidenceReasons.any((r) => r.contains('Variabilidad alta')),
        isTrue,
      );
      // La variabilidad no debe angostar artificialmente el rango.
      expect(
        DayKey.diffInDays(p.nextPeriodEarliestDate, p.nextPeriodLatestDate) > 4,
        isTrue,
      );
      _expectCoreInvariants(p);
    });
  });

  group('predictCycle - fases del ciclo', () {
    test('fase menstrual se extiende si el sangrado actual supera el '
        'promedio historico', () {
      // Promedio historico de menstruacion: 5 dias. El ciclo actual
      // (abierto) ya lleva 8 dias de sangrado registrados.
      final result = predictCycle(
        cycles: [
          _cycle('2026-01-01', 5, 28),
          _cycle('2026-01-29', 5, 28),
          _cycle('2026-02-26', 8, null), // sangrado mas largo de lo usual
        ],
        today: '2026-03-05', // dia de ciclo 8 (2026-02-26 + 7 = 03-05)
      );

      final p = result as ActivePrediction;
      expect(p.currentPhase, CyclePhase.menstrual);
    });

    test(
        'periodConfirmedEnded anula la extension por el promedio: la fase '
        'deja de ser menstrual aunque el heuristico sin confirmar seguiria '
        'ahi', () {
      // Promedio historico de menstruacion: 5 dias. Este periodo solo
      // tuvo 3 dias observados, pero la usuaria confirmo explicitamente
      // que ya termino (p.ej. respondio "No" en la pregunta de Inicio).
      final cycles = [
        _cycle('2026-01-01', 5, 28),
        _cycle('2026-01-29', 5, 28),
        CycleSummary(
          startDate: '2026-02-26',
          periodLengthDays: 3,
          cycleLengthDays: null,
          periodConfirmedEnded: true,
        ),
      ];

      final result =
          predictCycle(cycles: cycles, today: '2026-03-01'); // dia de ciclo 4
      final p = result as ActivePrediction;
      expect(p.currentPhase, CyclePhase.folicular);

      // Control: el mismo dia 4, SIN la confirmacion, el heuristico
      // max(3,5)=5 si seguiria mostrando fase menstrual.
      final sinConfirmar = predictCycle(
        cycles: [
          _cycle('2026-01-01', 5, 28),
          _cycle('2026-01-29', 5, 28),
          _cycle('2026-02-26', 3, null),
        ],
        today: '2026-03-01',
      ) as ActivePrediction;
      expect(sinConfirmar.currentPhase, CyclePhase.menstrual);
    });

    test('fase folicular entre el fin de la menstruacion y la ovulacion',
        () {
      final result = predictCycle(
        cycles: [
          _cycle('2026-01-01', 5, 28),
          _cycle('2026-01-29', 5, 28),
          _cycle('2026-02-26', 5, null),
        ],
        today: '2026-03-03', // dia de ciclo 6, justo tras la menstruacion (dias 1-5)
      );
      final p = result as ActivePrediction;
      expect(p.currentPhase, CyclePhase.folicular);
    });

    test('fase ovulatoria alrededor del dia estimado de ovulacion', () {
      final result = predictCycle(
        cycles: [
          _cycle('2026-01-01', 5, 28),
          _cycle('2026-01-29', 5, 28),
          _cycle('2026-02-26', 5, null),
        ],
        // ovulacion esperada: 2026-02-26 + 28 - 14 = 2026-03-12 (dia 15)
        today: '2026-03-12',
      );
      final p = result as ActivePrediction;
      expect(p.currentPhase, CyclePhase.ovulatoria);
    });

    test('fase lutea despues de la ventana ovulatoria', () {
      final result = predictCycle(
        cycles: [
          _cycle('2026-01-01', 5, 28),
          _cycle('2026-01-29', 5, 28),
          _cycle('2026-02-26', 5, null),
        ],
        today: '2026-03-20', // bien despues de la ovulacion, antes del limite
      );
      final p = result as ActivePrediction;
      expect(p.currentPhase, CyclePhase.lutea);
    });
  });

  group('predictCycle - periodo atrasado vs datos desactualizados', () {
    test('periodo atrasado: hoy supera el extremo tardio del rango', () {
      final result = predictCycle(
        cycles: [
          _cycle('2026-01-01', 5, 28),
          _cycle('2026-01-29', 5, 28),
          _cycle('2026-02-26', 5, 28),
          _cycle('2026-03-26', 5, null),
        ],
        today: '2026-04-28', // esperado 04-23, tardio 04-25
      );
      final p = result as ActivePrediction;
      expect(p.nextPeriodExpectedDate, '2026-04-23');
      expect(p.nextPeriodLatestDate, '2026-04-25');
      expect(p.isPeriodLate, isTrue);
      expect(p.daysLate, 3);
    });

    test('exactamente en el extremo tardio: NO esta atrasado todavia', () {
      final result = predictCycle(
        cycles: [
          _cycle('2026-01-01', 5, 28),
          _cycle('2026-01-29', 5, 28),
          _cycle('2026-02-26', 5, 28),
          _cycle('2026-03-26', 5, null),
        ],
        today: '2026-04-25', // == nextPeriodLatestDate
      );
      final p = result as ActivePrediction;
      expect(p.isPeriodLate, isFalse);
      expect(p.daysLate, 0);
    });

    test('datos desactualizados: mas de maxValidCycleLengthDays (60) dias '
        'desde el ultimo registro, sin prediccion numerica', () {
      final result = predictCycle(
        cycles: [_cycle('2026-01-01', 5, null)],
        today: '2026-03-15', // 73 dias despues
      );
      expect(result, isA<StaleDataPrediction>());
      final stale = result as StaleDataPrediction;
      expect(stale.lastPeriodStartDate, '2026-01-01');
      expect(stale.daysSinceLastPeriodStart, 73);
    });

    test('exactamente 60 dias: todavia NO es datos desactualizados', () {
      final result = predictCycle(
        cycles: [_cycle('2026-01-01', 5, null)],
        today: DayKey.addDays('2026-01-01', 60),
      );
      expect(result, isA<ActivePrediction>());
    });

    test('61 dias: SI es datos desactualizados', () {
      final result = predictCycle(
        cycles: [_cycle('2026-01-01', 5, null)],
        today: DayKey.addDays('2026-01-01', 61),
      );
      expect(result, isA<StaleDataPrediction>());
    });
  });

  group('predictCycle - casos defensivos', () {
    test('hoy antes del unico registro: no explota, confidenceReason '
        'explicito, fase se clampea a menstrual', () {
      final result = predictCycle(
        cycles: [_cycle('2026-05-10', 5, null)],
        today: '2026-05-01',
      );
      final p = result as ActivePrediction;
      expect(p.currentPhase, CyclePhase.menstrual);
      expect(
        p.confidenceReasons
            .any((r) => r.contains('anterior al último período')),
        isTrue,
      );
    });
  });

  group('predictCycle - determinismo', () {
    test('mismos inputs producen mismos outputs', () {
      final cycles = [
        _cycle('2026-01-01', 5, 28),
        _cycle('2026-01-29', 5, 30),
        _cycle('2026-02-28', 5, null),
      ];
      final a = predictCycle(cycles: cycles, today: '2026-03-10');
      final b = predictCycle(cycles: cycles, today: '2026-03-10');
      expect(a, equals(b));
    });
  });

  group('predictCycle - cambios de hora de Chile', () {
    test('ciclos y hoy alrededor del cambio de otono 2026-04-04/05 cumplen '
        'las invariantes', () {
      final start1 = '2026-03-07';
      final start2 = DayKey.addDays(start1, 28); // 2026-04-04
      final start3 = DayKey.addDays(start2, 28); // 2026-05-02
      final result = predictCycle(
        cycles: [
          _cycle(start1, 5, 28),
          _cycle(start2, 5, 28),
          _cycle(start3, 5, null),
        ],
        today: DayKey.addDays(start3, 5),
      );
      _expectCoreInvariants(result as ActivePrediction);
      expect(result.averageCycleLengthDays, 28.0);
    });

    test('ciclos y hoy alrededor del cambio de primavera 2026-09-05/06/07 '
        'cumplen las invariantes', () {
      final start1 = '2026-08-09';
      final start2 = DayKey.addDays(start1, 28); // 2026-09-06
      final start3 = DayKey.addDays(start2, 28); // 2026-10-04
      final result = predictCycle(
        cycles: [
          _cycle(start1, 5, 28),
          _cycle(start2, 5, 28),
          _cycle(start3, 5, null),
        ],
        today: DayKey.addDays(start3, 3),
      );
      _expectCoreInvariants(result as ActivePrediction);
      expect(result.averageCycleLengthDays, 28.0);
    });
  });
}
