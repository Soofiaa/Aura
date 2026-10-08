import 'package:flutter_test/flutter_test.dart';
import 'package:aura/domain/cycle_deriver.dart';
import 'package:aura/domain/cycle_predictor.dart';
import 'package:aura/domain/fertile_marks.dart';

/// Prediccion inventada con fechas distintas en cada campo, para que un
/// cruce de campos se note.
ActivePrediction _prediction({
  PredictionConfidence confidence = PredictionConfidence.high,
  bool isPeriodLate = false,
}) {
  return ActivePrediction(
    lastPeriodStartDate: '2026-03-26',
    daysSinceLastPeriodStart: 10,
    averageCycleLengthDays: 28,
    cycleLengthStdDevDays: 0,
    averagePeriodLengthDays: 5,
    completeCyclesConsidered: 4,
    excludedCyclesCount: 0,
    nextPeriodEarliestDate: '2026-04-21',
    nextPeriodExpectedDate: '2026-04-23',
    nextPeriodLatestDate: '2026-04-25',
    estimatedOvulationDate: '2026-04-09',
    fertileWindowStartDate: '2026-04-04',
    fertileWindowEndDate: '2026-04-10',
    currentPhase: CyclePhase.lutea,
    isPeriodLate: isPeriodLate,
    daysLate: isPeriodLate ? 1 : 0,
    confidence: confidence,
    confidenceReasons: const [],
  );
}

const _marks = FertileMarks(
  ovulationDate: '2026-04-09',
  windowStartDate: '2026-04-04',
  windowEndDate: '2026-04-10',
);

CycleSummary _cycle(String start, int? cycleLength) => CycleSummary(
  startDate: start,
  periodLengthDays: 5,
  cycleLengthDays: cycleLength,
);

void main() {
  group('visibleFertileMarks - tabla completa', () {
    test('sin prediccion: null (con el interruptor encendido o apagado)', () {
      for (final mostrar in [true, false]) {
        expect(
          visibleFertileMarks(null, showFertileWindow: mostrar),
          isNull,
          reason: 'mostrar: $mostrar',
        );
      }
    });

    test('datos viejos (StaleDataPrediction): null', () {
      const stale = StaleDataPrediction(
        lastPeriodStartDate: '2026-01-01',
        daysSinceLastPeriodStart: 61,
      );
      for (final mostrar in [true, false]) {
        expect(
          visibleFertileMarks(stale, showFertileWindow: mostrar),
          isNull,
          reason: 'mostrar: $mostrar',
        );
      }
    });

    // 3 confianzas x atrasado si/no x interruptor si/no = 12 casos; solo
    // media o alta, no atrasado y encendido devuelven fechas.
    for (final confianza in PredictionConfidence.values) {
      for (final atrasado in [false, true]) {
        for (final mostrar in [true, false]) {
          final visible =
              confianza != PredictionConfidence.low && !atrasado && mostrar;
          test('activa, confianza ${confianza.name}, atrasado: $atrasado, '
              'interruptor: $mostrar -> ${visible ? 'fechas' : 'null'}', () {
            final result = visibleFertileMarks(
              _prediction(confidence: confianza, isPeriodLate: atrasado),
              showFertileWindow: mostrar,
            );
            expect(result, visible ? _marks : isNull);
          });
        }
      }
    }
  });

  group('visibleFertileMarks - fechas', () {
    test('cada campo sale del campo correspondiente de la prediccion', () {
      final result = visibleFertileMarks(
        _prediction(),
        showFertileWindow: true,
      )!;
      expect(result.ovulationDate, '2026-04-09');
      expect(result.windowStartDate, '2026-04-04');
      expect(result.windowEndDate, '2026-04-10');
    });

    test('con una prediccion real son las del predictor', () {
      // 4 ciclos de 28 (confianza alta). Ultimo inicio 26/03; esperado
      // 23/04; ovulacion 09/04; ventana 04/04 - 09/04.
      final prediction =
          predictCycle(
                cycles: [
                  _cycle('2025-12-04', 28),
                  _cycle('2026-01-01', 28),
                  _cycle('2026-01-29', 28),
                  _cycle('2026-02-26', 28),
                  _cycle('2026-03-26', null),
                ],
                today: '2026-03-28',
              )
              as ActivePrediction;
      expect(prediction.confidence, PredictionConfidence.high);
      expect(prediction.isPeriodLate, isFalse);

      final result = visibleFertileMarks(prediction, showFertileWindow: true)!;
      expect(result.ovulationDate, prediction.estimatedOvulationDate);
      expect(result.windowStartDate, prediction.fertileWindowStartDate);
      expect(result.windowEndDate, prediction.fertileWindowEndDate);
      expect(
        result,
        const FertileMarks(
          ovulationDate: '2026-04-09',
          windowStartDate: '2026-04-04',
          windowEndDate: '2026-04-09',
        ),
      );
    });

    test('la misma prediccion real, con el periodo atrasado: null', () {
      // Extremo tardio 25/04; el 26/04 es 1 dia de atraso.
      final prediction =
          predictCycle(
                cycles: [
                  _cycle('2025-12-04', 28),
                  _cycle('2026-01-01', 28),
                  _cycle('2026-01-29', 28),
                  _cycle('2026-02-26', 28),
                  _cycle('2026-03-26', null),
                ],
                today: '2026-04-26',
              )
              as ActivePrediction;
      expect(prediction.isPeriodLate, isTrue);
      expect(prediction.confidence, PredictionConfidence.high);
      expect(visibleFertileMarks(prediction, showFertileWindow: true), isNull);
    });
  });
}
