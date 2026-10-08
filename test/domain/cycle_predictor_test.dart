import 'package:flutter_test/flutter_test.dart';
import 'package:aura/data/models/day_enums.dart';
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

/// Igual que [_cycle], pero con el periodo cerrado (period_end en su
/// ultimo dia, D-1).
CycleSummary _closed(String start, int periodLength, int? cycleLength) =>
    CycleSummary(
      startDate: start,
      periodLengthDays: periodLength,
      cycleLengthDays: cycleLength,
      periodEnd: PeriodEndSource.inferred,
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
      // 5 sale de typicalPeriodLengthDays por defecto, no de los datos:
      // el periodo es abierto y no entra al promedio (P-1).
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
      // Promedio de menstruacion: 5 dias, que sale de
      // typicalPeriodLengthDays por defecto y no de los datos (_cycle arma
      // periodos abiertos, que no entran al promedio, P-1). El ciclo
      // actual (abierto) ya lleva 8 dias de sangrado registrados.
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
      // Promedio de menstruacion: 5 dias en el control sin confirmar, que
      // sale de typicalPeriodLengthDays por defecto y no de los datos
      // (_cycle arma periodos abiertos, que no entran al promedio, P-1).
      // Este periodo solo tuvo 3 dias observados, pero la usuaria
      // confirmo explicitamente que ya termino (p.ej. respondio "No" en
      // la pregunta de Inicio).
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
      // max(3,5)=5 (5 = typicalPeriodLengthDays por defecto) si seguiria
      // mostrando fase menstrual.
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
        // Dia de ciclo 6, justo tras la menstruacion (dias 1-5). Esos 5 dias
        // salen de typicalPeriodLengthDays por defecto, no de los datos:
        // _cycle arma periodos abiertos, que no entran al promedio (P-1).
        today: '2026-03-03',
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
  group('predictCycle - duracion del periodo solo con periodos cerrados (P-1)',
      () {
    test(
        'regresion HU-03: un ciclo abierto de 1 dia y otro cerrado de 5 dias '
        'dan duracion promedio 5, no 3,67', () {
      final p = predictCycle(
        cycles: [
          _cycle('2026-01-01', 1, 28), // solo se marco el primer dia
          _closed('2026-01-29', 5, 28),
          _cycle('2026-02-26', 2, null), // actual, abierto
        ],
        today: '2026-02-27',
      ) as ActivePrediction;
      expect(p.averagePeriodLengthDays, 5.0);
    });

    test(
        'pocos ciclos completos con el periodo abierto: usa la duracion '
        'habitual (ya no la del periodo mas reciente)', () {
      final p = predictCycle(
        cycles: [
          _cycle('2026-01-01', 1, 28),
          _cycle('2026-01-29', 1, null),
        ],
        today: '2026-01-30',
        config: const PredictionConfig(typicalPeriodLengthDays: 6),
      ) as ActivePrediction;
      expect(p.completeCyclesConsidered, 1);
      expect(p.averagePeriodLengthDays, 6.0);
      // Dia de ciclo 2 con duracion habitual 6: sigue en fase menstrual
      // (antes, con la duracion 1 del periodo mas reciente, no).
      expect(p.currentPhase, CyclePhase.menstrual);
    });

    test(
        'el periodo actual cerrado entra al promedio aunque su ciclo no este '
        'completo (R-3), como el mas reciente', () {
      final p = predictCycle(
        cycles: [
          _closed('2026-01-01', 4, 28),
          _closed('2026-01-29', 4, 28),
          _closed('2026-02-26', 6, null), // actual, cerrado
        ],
        today: '2026-03-10',
      ) as ActivePrediction;
      // Ponderado 1, 2, 3: (4 + 8 + 18) / 6 = 5.
      expect(p.averagePeriodLengthDays, 5.0);
    });

    test('solo el periodo actual cerrado, sin ciclos completos: su duracion',
        () {
      final p = predictCycle(
        cycles: [_closed('2026-01-01', 3, null)],
        today: '2026-01-10',
      ) as ActivePrediction;
      expect(p.averagePeriodLengthDays, 3.0);
    });

    test('sin ningun periodo cerrado: typicalPeriodLengthDays', () {
      final p = predictCycle(
        cycles: [
          _cycle('2026-01-01', 2, 28),
          _cycle('2026-01-29', 2, 28),
          _cycle('2026-02-26', 2, 28),
          _cycle('2026-03-26', 2, null),
        ],
        today: '2026-03-28',
        config: const PredictionConfig(typicalPeriodLengthDays: 7),
      ) as ActivePrediction;
      expect(p.averagePeriodLengthDays, 7.0);
    });

    test('typicalPeriodLengthDays vale 5 por defecto', () {
      expect(const PredictionConfig().typicalPeriodLengthDays, 5);
      final p = predictCycle(
        cycles: [_cycle('2026-01-01', 1, null)],
        today: '2026-01-02',
      ) as ActivePrediction;
      expect(p.averagePeriodLengthDays, 5.0);
    });

    test(
        'un periodo cerrado de un ciclo fuera del rango valido no entra '
        '(solo cuenta la ventana)', () {
      final p = predictCycle(
        cycles: [
          _closed('2026-01-01', 9, 10), // ciclo invalido (< 15)
          _closed('2026-01-11', 4, 28),
          _closed('2026-02-08', 4, 28),
          _cycle('2026-03-08', 1, null),
        ],
        today: '2026-03-09',
      ) as ActivePrediction;
      expect(p.excludedCyclesCount, 1);
      expect(p.averagePeriodLengthDays, 4.0);
    });

    test('un periodo cerrado por el "no" explicito tambien cuenta', () {
      final p = predictCycle(
        cycles: [
          _cycle('2026-01-01', 1, 28),
          const CycleSummary(
            startDate: '2026-01-29',
            periodLengthDays: 4,
            cycleLengthDays: 28,
            periodConfirmedEnded: true,
          ),
          _cycle('2026-02-26', 1, null),
        ],
        today: '2026-02-27',
      ) as ActivePrediction;
      expect(p.averagePeriodLengthDays, 4.0);
    });

    test(
        'menstrualEndDay usa isClosed: un periodo actual con period_end '
        '(sin "no") termina la fase menstrual en lo observado', () {
      final cerrado = predictCycle(
        cycles: [
          _cycle('2026-01-01', 5, 28),
          _cycle('2026-01-29', 5, 28),
          _closed('2026-02-26', 3, null),
        ],
        today: '2026-03-01', // dia de ciclo 4
      ) as ActivePrediction;
      expect(cerrado.currentPhase, CyclePhase.folicular);

      final abierto = predictCycle(
        cycles: [
          _cycle('2026-01-01', 5, 28),
          _cycle('2026-01-29', 5, 28),
          _cycle('2026-02-26', 3, null),
        ],
        today: '2026-03-01',
      ) as ActivePrediction;
      expect(abierto.currentPhase, CyclePhase.menstrual); // max(3, 5)
    });

    test(
        'forma de datos reales (fechas inventadas): 4 periodos de 3 dias cada '
        '28 dias, los 3 primeros cerrados y el ultimo en curso', () {
      final p = predictCycle(
        cycles: [
          _closed('2025-11-03', 3, 28),
          _closed('2025-12-01', 3, 28),
          _closed('2025-12-29', 3, 28),
          _cycle('2026-01-26', 2, null), // en curso: lleva 2 dias
        ],
        today: '2026-01-27',
      ) as ActivePrediction;

      expect(p.averagePeriodLengthDays, 3.0);
      expect(p.currentPhase, CyclePhase.menstrual); // dia 2 de max(2, 3)

      // Fechas, rango y confianza iguales a los de antes de P-1: la
      // duracion del ciclo no cambia (28, desviacion 0, semiancho 2).
      expect(p.completeCyclesConsidered, 3);
      expect(p.averageCycleLengthDays, 28.0);
      expect(p.cycleLengthStdDevDays, 0.0);
      expect(p.nextPeriodExpectedDate, '2026-02-23');
      expect(p.nextPeriodEarliestDate, '2026-02-21');
      expect(p.nextPeriodLatestDate, '2026-02-25');
      expect(p.estimatedOvulationDate, '2026-02-09');
      expect(p.fertileWindowStartDate, '2026-02-04');
      expect(p.fertileWindowEndDate, '2026-02-09');
      expect(p.confidence, PredictionConfidence.medium);
      expect(p.isPeriodLate, isFalse);
      _expectCoreInvariants(p);

      // Mismas fechas con los periodos abiertos: la duracion del periodo
      // no interviene en fechas, rango ni confianza.
      final abiertos = predictCycle(
        cycles: [
          _cycle('2025-11-03', 3, 28),
          _cycle('2025-12-01', 3, 28),
          _cycle('2025-12-29', 3, 28),
          _cycle('2026-01-26', 2, null),
        ],
        today: '2026-01-27',
      ) as ActivePrediction;
      expect(abiertos.nextPeriodExpectedDate, p.nextPeriodExpectedDate);
      expect(abiertos.nextPeriodEarliestDate, p.nextPeriodEarliestDate);
      expect(abiertos.nextPeriodLatestDate, p.nextPeriodLatestDate);
      expect(abiertos.confidence, p.confidence);
    });
  });

  group('estimatePeriodLength - duracion estimada unica (P-1)', () {
    test('sin ciclos: el ajuste, con origen setting', () {
      final e = estimatePeriodLength(
        cycles: const [],
        config: const PredictionConfig(typicalPeriodLengthDays: 6),
      );
      expect(e.averageDays, 6.0);
      expect(e.days, 6);
      expect(e.source, PeriodLengthSource.setting);
    });

    test('solo periodos abiertos: el ajuste', () {
      final e = estimatePeriodLength(
        cycles: [_cycle('2026-01-01', 2, 28), _cycle('2026-01-29', 1, null)],
        config: const PredictionConfig(typicalPeriodLengthDays: 7),
      );
      expect(e.days, 7);
      expect(e.source, PeriodLengthSource.setting);
    });

    test('con periodos cerrados: su promedio ponderado, redondeado en days',
        () {
      final e = estimatePeriodLength(
        cycles: [
          _closed('2026-01-01', 3, 28),
          _closed('2026-01-29', 4, 28),
          _cycle('2026-02-26', 1, null),
        ],
        config: const PredictionConfig(typicalPeriodLengthDays: 7),
      );
      // Ponderado 1, 2: (3 + 8) / 3 = 3,67.
      expect(e.averageDays, closeTo(11 / 3, 1e-9));
      expect(e.days, 4);
      expect(e.source, PeriodLengthSource.ownPeriods);
    });

    test('un cerrado solo en un ciclo invalido no cuenta: el ajuste', () {
      final e = estimatePeriodLength(
        cycles: [_closed('2026-01-01', 9, 10), _cycle('2026-01-11', 1, null)],
        config: const PredictionConfig(typicalPeriodLengthDays: 5),
      );
      expect(e.days, 5);
      expect(e.source, PeriodLengthSource.setting);
    });

    test('es el mismo numero que averagePeriodLengthDays de predictCycle', () {
      final cycles = [
        _closed('2025-11-03', 3, 28),
        _closed('2025-12-01', 5, 28),
        _cycle('2025-12-29', 2, 28),
        _closed('2026-01-26', 4, null),
      ];
      const config = PredictionConfig(typicalPeriodLengthDays: 9);
      final p = predictCycle(cycles: cycles, today: '2026-02-01', config: config)
          as ActivePrediction;
      expect(estimatePeriodLength(cycles: cycles, config: config).averageDays,
          p.averagePeriodLengthDays);
    });
  });

  // HU-05, CP1: tests de caracterizacion. Fijan lo que el predictor hace
  // HOY (no lo que deberia hacer). Datos inventados.
  group('HU-05 CP1 - caracterizacion del comportamiento actual', () {
    /// Ciclos completos con las duraciones [lengths] (de mas viejo a mas
    /// nuevo) desde [start], mas un periodo actual abierto al final.
    /// Todos los periodos duran [periodLength] dias y estan abiertos, asi
    /// que la duracion de periodo del predictor es la habitual (5).
    List<CycleSummary> cyclesFrom(String start, List<int> lengths,
        {int periodLength = 5}) {
      final result = <CycleSummary>[];
      var day = start;
      for (final length in lengths) {
        result.add(_cycle(day, periodLength, length));
        day = DayKey.addDays(day, length);
      }
      result.add(_cycle(day, periodLength, null));
      return result;
    }

    String lastStart(List<CycleSummary> cycles) => cycles.last.startDate;

    ActivePrediction twoDaysAfterLastStart(List<CycleSummary> cycles) =>
        predictCycle(
            cycles: cycles,
            today: DayKey.addDays(lastStart(cycles), 2)) as ActivePrediction;

    double ratio(ActivePrediction p) =>
        p.cycleLengthStdDevDays / p.averageCycleLengthDays;

    group('a) umbral de confianza 0,18 (desviacion / promedio)', () {
      // Calculo (pesos 1..n, igual que _weightedMeanAndStdDev), hecho con
      // un script que recorrio todas las combinaciones de 20 a 45 dias:
      // - [20, 23, 23, 32]: media 26,3; desviacion 4,7339; razon
      //   0,179997 (la mas cercana a 0,18 por debajo con 4 ciclos).
      // - [32, 37, 25]: media 30,1667; desviacion 5,4288; razon 0,179961
      //   (la mas cercana por debajo con 3 ciclos).
      // - [20, 31, 23, 20]: media 23,1; desviacion 4,1581; razon
      //   0,180005 (la mas cercana por encima con 4 ciclos).
      // - [22, 34, 22, 34, 22, 34]: media 28,857; desviacion 5,9385;
      //   razon 0,2058.
      test('4 ciclos justo por debajo de 0,18: confianza alta', () {
        final p = twoDaysAfterLastStart(
            cyclesFrom('2026-01-01', [20, 23, 23, 32]));
        expect(p.completeCyclesConsidered, 4);
        expect(ratio(p), lessThan(0.18));
        expect(ratio(p), greaterThan(0.1799));
        expect(p.confidence, PredictionConfidence.high);
        expect(p.confidenceReasons, isEmpty);
      });

      test('3 ciclos justo por debajo de 0,18: confianza media', () {
        final p =
            twoDaysAfterLastStart(cyclesFrom('2026-01-01', [32, 37, 25]));
        expect(p.completeCyclesConsidered, 3);
        expect(ratio(p), lessThan(0.18));
        expect(ratio(p), greaterThan(0.1799));
        expect(p.confidence, PredictionConfidence.medium);
        expect(p.confidenceReasons, isEmpty);
      });

      test('4 ciclos justo por encima de 0,18: confianza baja con el motivo '
          '(el porcentaje se redondea: dice 18)', () {
        final p = twoDaysAfterLastStart(
            cyclesFrom('2026-01-01', [20, 31, 23, 20]));
        expect(p.completeCyclesConsidered, 4);
        expect(ratio(p), greaterThan(0.18));
        expect(ratio(p), lessThan(0.1801));
        expect(p.confidence, PredictionConfidence.low);
        expect(p.confidenceReasons,
            ['Variabilidad alta entre ciclos (±18% del promedio).']);
      });

      test('6 ciclos con variabilidad alta: baja aunque la cantidad '
          'alcance para alta', () {
        final p = twoDaysAfterLastStart(
            cyclesFrom('2026-01-01', [22, 34, 22, 34, 22, 34]));
        expect(p.completeCyclesConsidered, 6);
        expect(p.confidence, PredictionConfidence.low);
        expect(p.confidenceReasons,
            ['Variabilidad alta entre ciclos (±21% del promedio).']);
      });
    });

    group('b) limites de ciclo valido (15 a 60, ambos incluidos)', () {
      // Cada caso: el ciclo en el limite primero y dos ciclos de 28.
      ActivePrediction withFirst(int length) =>
          twoDaysAfterLastStart(cyclesFrom('2026-01-01', [length, 28, 28]));

      const motivo =
          'Se excluyeron 1 ciclo(s) fuera del rango válido (15-60 días).';

      Iterable<String> exclusionReasons(ActivePrediction p) =>
          p.confidenceReasons.where((r) => r.startsWith('Se excluyeron'));

      test('14 dias: excluido, con el motivo', () {
        final p = withFirst(14);
        expect(p.excludedCyclesCount, 1);
        expect(p.completeCyclesConsidered, 2);
        expect(p.confidenceReasons, contains(motivo));
      });

      test('15 dias: valido, sin motivo', () {
        final p = withFirst(15);
        expect(p.excludedCyclesCount, 0);
        expect(p.completeCyclesConsidered, 3);
        expect(exclusionReasons(p), isEmpty);
      });

      test('60 dias: valido, sin motivo', () {
        final p = withFirst(60);
        expect(p.excludedCyclesCount, 0);
        expect(p.completeCyclesConsidered, 3);
        expect(exclusionReasons(p), isEmpty);
      });

      test('61 dias: excluido, con el motivo', () {
        final p = withFirst(61);
        expect(p.excludedCyclesCount, 1);
        expect(p.completeCyclesConsidered, 2);
        expect(p.confidenceReasons, contains(motivo));
      });
    });

    test('c) exactamente 1 ciclo completo valido: promedio 28 (no el del '
        'ciclo), semiancho 3, confianza baja y el motivo', () {
      // Un ciclo completo de 32 dias y el periodo actual: el 32 se ignora
      // porque hacen falta 2 ciclos (minCompleteCyclesForMedium).
      final cycles = cyclesFrom('2026-01-01', [32]);
      final start = lastStart(cycles);
      final p = twoDaysAfterLastStart(cycles);
      expect(p.completeCyclesConsidered, 1);
      expect(p.averageCycleLengthDays, 28.0);
      expect(p.cycleLengthStdDevDays, 0.0);
      expect(p.nextPeriodExpectedDate, DayKey.addDays(start, 28));
      expect(p.nextPeriodEarliestDate, DayKey.addDays(start, 25));
      expect(p.nextPeriodLatestDate, DayKey.addDays(start, 31));
      expect(p.confidence, PredictionConfidence.low);
      expect(p.confidenceReasons, [
        'Menos de 2 ciclos completos registrados; se usa un promedio por '
            'defecto de 28 días.'
      ]);
    });

    group('d) fases con promedios de 15, 20, 28 y 45 dias (periodo de 5)',
        () {
      // Tres ciclos identicos de A dias (desviacion 0, promedio A) y el
      // periodo actual abierto de 5 dias: fin menstrual = max(5, 5) = 5.
      // Ovulacion = inicio + A - 14, asi que el dia de ovulacion del
      // ciclo es A - 13; la ovulatoria va de A - 14 a A - 12. El orden de
      // las reglas es menstrual, ovulatoria, folicular, lutea.
      List<CycleSummary> identical(int average) =>
          cyclesFrom('2026-01-01', [average, average, average]);

      List<CyclePhase> phases(int average) {
        final cycles = identical(average);
        final start = lastStart(cycles);
        return [
          for (var day = 1; day <= average; day++)
            (predictCycle(
                    cycles: cycles, today: DayKey.addDays(start, day - 1))
                as ActivePrediction)
                .currentPhase,
        ];
      }

      int ovulationDay(int average) {
        final cycles = identical(average);
        final start = lastStart(cycles);
        final p =
            predictCycle(cycles: cycles, today: start) as ActivePrediction;
        return DayKey.diffInDays(start, p.estimatedOvulationDate) + 1;
      }

      const m = CyclePhase.menstrual;
      const f = CyclePhase.folicular;
      const o = CyclePhase.ovulatoria;
      const l = CyclePhase.lutea;

      test('15: ovulacion el dia 2, la ovulatoria queda tapada por la '
          'menstrual y despues del dia 5 pasa directo a lutea', () {
        expect(ovulationDay(15), 2);
        expect(phases(15), [...List.filled(5, m), ...List.filled(10, l)]);
      });

      test('20: sin fase folicular (la ovulatoria empieza el dia 6)', () {
        expect(ovulationDay(20), 7);
        expect(phases(20), [...List.filled(5, m), o, o, o, ...List.filled(12, l)]);
        expect(phases(20), isNot(contains(f)));
      });

      test('28: referencia (folicular 6-13, ovulatoria 14-16, lutea 17-28)',
          () {
        expect(ovulationDay(28), 15);
        expect(phases(28), [
          ...List.filled(5, m),
          ...List.filled(8, f),
          o, o, o,
          ...List.filled(12, l),
        ]);
      });

      test('45: ovulacion el dia 32, folicular del 6 al 30, ovulatoria 31-33 '
          'y lutea desde el 34', () {
        expect(ovulationDay(45), 32);
        expect(phases(45), [
          ...List.filled(5, m),
          ...List.filled(25, f),
          o, o, o,
          ...List.filled(12, l),
        ]);
      });
    });
  });
}
