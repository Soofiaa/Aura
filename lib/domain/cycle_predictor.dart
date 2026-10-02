import 'dart:math' as math;

import '../utils/day_key.dart';
import 'cycle_deriver.dart';

/// Todas las constantes del motor de prediccion, nombradas y ajustables.
class PredictionConfig {
  /// Cuantos ciclos completos recientes entran en el promedio ponderado.
  final int maxCyclesConsidered;

  /// Ciclos completos de menos de esta duracion se excluyen del promedio
  /// (probable manchado o error de registro, no un ciclo real).
  final int minValidCycleLengthDays;

  /// Ciclos completos de mas de esta duracion se excluyen del promedio.
  /// Tambien se reusa como umbral de "datos desactualizados": si hoy esta
  /// a mas de esta cantidad de dias del ultimo periodo registrado, ya no
  /// se arriesga una prediccion numerica.
  final int maxValidCycleLengthDays;

  /// Dias entre la ovulacion y el inicio del siguiente periodo. La fase
  /// lutea es mucho mas estable entre personas y ciclos que la folicular,
  /// por eso la ovulacion se ancla restando desde el proximo periodo
  /// esperado en vez de sumar desde el ultimo.
  final int lutealPhaseDays;

  /// Dias fertiles antes de la ovulacion (mas el dia de ovulacion).
  final int fertileWindowDaysBeforeOvulation;

  /// Medio ancho de la fase ovulatoria alrededor del dia de ovulacion
  /// estimado ("ovulacion +-1").
  final int ovulationPhaseHalfWidthDays;

  /// Duracion de ciclo asumida cuando hay menos de
  /// [minCompleteCyclesForMedium] ciclos completos.
  final int defaultCycleLengthDays;

  /// Multiplicador de la desviacion estandar para el semiancho del rango
  /// del proximo periodo.
  final double rangeStdDevMultiplier;

  /// Piso del semiancho del rango, incluso si la desviacion es 0 (ciclos
  /// identicos no deberian dar un rango de ancho cero).
  final int minRangeHalfWidthDays;

  /// Semiancho fijo del rango cuando no hay suficientes ciclos completos
  /// para calcular una desviacion estandar significativa.
  final int defaultRangeHalfWidthDays;

  /// Minimo de ciclos completos para confianza media (por debajo: baja).
  final int minCompleteCyclesForMedium;

  /// Minimo de ciclos completos para confianza alta.
  final int minCompleteCyclesForHigh;

  /// Si la desviacion estandar supera esta fraccion del promedio, la
  /// variabilidad se considera alta y la confianza baja
  /// independientemente de cuantos ciclos haya.
  final double highStdDevRelativeRatio;

  const PredictionConfig({
    this.maxCyclesConsidered = 6,
    this.minValidCycleLengthDays = 15,
    this.maxValidCycleLengthDays = 60,
    this.lutealPhaseDays = 14,
    this.fertileWindowDaysBeforeOvulation = 5,
    this.ovulationPhaseHalfWidthDays = 1,
    this.defaultCycleLengthDays = 28,
    this.rangeStdDevMultiplier = 1.5,
    this.minRangeHalfWidthDays = 2,
    this.defaultRangeHalfWidthDays = 3,
    this.minCompleteCyclesForMedium = 2,
    this.minCompleteCyclesForHigh = 4,
    this.highStdDevRelativeRatio = 0.18,
  });
}

enum CyclePhase { menstrual, folicular, ovulatoria, lutea }

extension CyclePhaseLabel on CyclePhase {
  String get label => switch (this) {
        CyclePhase.menstrual => 'Fase menstrual',
        CyclePhase.folicular => 'Fase folicular',
        CyclePhase.ovulatoria => 'Fase ovulatoria',
        CyclePhase.lutea => 'Fase lútea',
      };
}

enum PredictionConfidence { low, medium, high }

extension PredictionConfidenceLabel on PredictionConfidence {
  String get label => switch (this) {
        PredictionConfidence.low => 'Baja',
        PredictionConfidence.medium => 'Media',
        PredictionConfidence.high => 'Alta',
      };
}

/// Resultado de [predictCycle]. Null solo si no hay ningun dia de
/// sangrado registrado jamas; en cualquier otro caso devuelve
/// [StaleDataPrediction] o [ActivePrediction].
sealed class CyclePrediction {
  /// Fecha de inicio del ciclo mas reciente (completo o abierto).
  final String lastPeriodStartDate;

  /// Dias transcurridos entre [lastPeriodStartDate] y el "hoy" recibido.
  final int daysSinceLastPeriodStart;

  const CyclePrediction({
    required this.lastPeriodStartDate,
    required this.daysSinceLastPeriodStart,
  });
}

/// Hoy esta a mas de [PredictionConfig.maxValidCycleLengthDays] dias del
/// ultimo periodo registrado: no se arriesga una prediccion numerica.
final class StaleDataPrediction extends CyclePrediction {
  const StaleDataPrediction({
    required super.lastPeriodStartDate,
    required super.daysSinceLastPeriodStart,
  });

  @override
  bool operator ==(Object other) =>
      other is StaleDataPrediction &&
      other.lastPeriodStartDate == lastPeriodStartDate &&
      other.daysSinceLastPeriodStart == daysSinceLastPeriodStart;

  @override
  int get hashCode => Object.hash(lastPeriodStartDate, daysSinceLastPeriodStart);

  @override
  String toString() =>
      'StaleDataPrediction(lastPeriodStartDate: $lastPeriodStartDate, '
      'daysSinceLastPeriodStart: $daysSinceLastPeriodStart)';
}

final class ActivePrediction extends CyclePrediction {
  final double averageCycleLengthDays;
  final double cycleLengthStdDevDays;
  final double averagePeriodLengthDays;

  /// Ciclos completos y validos realmente usados en el promedio (tras
  /// excluir fuera de rango y acotar a los ultimos
  /// [PredictionConfig.maxCyclesConsidered]).
  final int completeCyclesConsidered;

  /// Ciclos completos excluidos del promedio por estar fuera del rango
  /// valido (ver [PredictionConfig.minValidCycleLengthDays] /
  /// [PredictionConfig.maxValidCycleLengthDays]).
  final int excludedCyclesCount;

  final String nextPeriodEarliestDate;
  final String nextPeriodExpectedDate;
  final String nextPeriodLatestDate;
  final String estimatedOvulationDate;
  final String fertileWindowStartDate;
  final String fertileWindowEndDate;
  final CyclePhase currentPhase;
  final bool isPeriodLate;
  final int daysLate;
  final PredictionConfidence confidence;

  /// Explicaciones legibles de por que la confianza es la que es (o de
  /// anomalias detectadas en los datos de entrada). Pensado para mostrar
  /// en la UI y para debuggear tests, no es texto fijo de producto.
  final List<String> confidenceReasons;

  const ActivePrediction({
    required super.lastPeriodStartDate,
    required super.daysSinceLastPeriodStart,
    required this.averageCycleLengthDays,
    required this.cycleLengthStdDevDays,
    required this.averagePeriodLengthDays,
    required this.completeCyclesConsidered,
    required this.excludedCyclesCount,
    required this.nextPeriodEarliestDate,
    required this.nextPeriodExpectedDate,
    required this.nextPeriodLatestDate,
    required this.estimatedOvulationDate,
    required this.fertileWindowStartDate,
    required this.fertileWindowEndDate,
    required this.currentPhase,
    required this.isPeriodLate,
    required this.daysLate,
    required this.confidence,
    required this.confidenceReasons,
  });

  @override
  bool operator ==(Object other) =>
      other is ActivePrediction &&
      other.lastPeriodStartDate == lastPeriodStartDate &&
      other.daysSinceLastPeriodStart == daysSinceLastPeriodStart &&
      other.averageCycleLengthDays == averageCycleLengthDays &&
      other.cycleLengthStdDevDays == cycleLengthStdDevDays &&
      other.averagePeriodLengthDays == averagePeriodLengthDays &&
      other.completeCyclesConsidered == completeCyclesConsidered &&
      other.excludedCyclesCount == excludedCyclesCount &&
      other.nextPeriodEarliestDate == nextPeriodEarliestDate &&
      other.nextPeriodExpectedDate == nextPeriodExpectedDate &&
      other.nextPeriodLatestDate == nextPeriodLatestDate &&
      other.estimatedOvulationDate == estimatedOvulationDate &&
      other.fertileWindowStartDate == fertileWindowStartDate &&
      other.fertileWindowEndDate == fertileWindowEndDate &&
      other.currentPhase == currentPhase &&
      other.isPeriodLate == isPeriodLate &&
      other.daysLate == daysLate &&
      other.confidence == confidence &&
      _listEquals(other.confidenceReasons, confidenceReasons);

  @override
  int get hashCode => Object.hash(
        lastPeriodStartDate,
        daysSinceLastPeriodStart,
        averageCycleLengthDays,
        cycleLengthStdDevDays,
        averagePeriodLengthDays,
        completeCyclesConsidered,
        excludedCyclesCount,
        nextPeriodEarliestDate,
        nextPeriodExpectedDate,
        nextPeriodLatestDate,
        Object.hash(estimatedOvulationDate, fertileWindowStartDate,
            fertileWindowEndDate, currentPhase, isPeriodLate, daysLate, confidence),
      );

  @override
  String toString() =>
      'ActivePrediction(lastPeriodStartDate: $lastPeriodStartDate, '
      'nextPeriod: $nextPeriodEarliestDate..$nextPeriodExpectedDate..$nextPeriodLatestDate, '
      'ovulation: $estimatedOvulationDate, phase: $currentPhase, '
      'confidence: $confidence, reasons: $confidenceReasons)';
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class _WeightedStats {
  final double mean;
  final double stdDev;
  const _WeightedStats(this.mean, this.stdDev);
}

/// Media y desviacion estandar ponderadas: [values] ordenados de mas
/// viejo a mas nuevo, peso lineal 1..n (el mas reciente pesa mas).
_WeightedStats _weightedMeanAndStdDev(List<int> values) {
  final n = values.length;
  final weights = List<int>.generate(n, (i) => i + 1);
  final weightSum = weights.reduce((a, b) => a + b);

  var weightedSum = 0.0;
  for (var i = 0; i < n; i++) {
    weightedSum += values[i] * weights[i];
  }
  final mean = weightedSum / weightSum;

  var weightedSquaredDiff = 0.0;
  for (var i = 0; i < n; i++) {
    final diff = values[i] - mean;
    weightedSquaredDiff += weights[i] * diff * diff;
  }
  final variance = weightedSquaredDiff / weightSum;

  return _WeightedStats(mean, math.sqrt(variance));
}

/// Motor de prediccion puro: sin DateTime.now(), sin base de datos.
/// [today] es una clave 'yyyy-MM-dd' (igual que [CycleSummary.startDate])
/// para reusar la aritmetica de [DayKey], que ya es segura ante los
/// cambios de hora de Chile. Devuelve null solo si [cycles] esta vacia.
CyclePrediction? predictCycle({
  required List<CycleSummary> cycles,
  required String today,
  PredictionConfig config = const PredictionConfig(),
}) {
  if (cycles.isEmpty) return null;

  final sorted = [...cycles]..sort((a, b) => DayKey.compare(a.startDate, b.startDate));
  final mostRecent = sorted.last;

  final confidenceReasons = <String>[];
  if (DayKey.isBefore(today, mostRecent.startDate)) {
    confidenceReasons.add(
      'La fecha de referencia es anterior al último período registrado.',
    );
  }

  final daysSinceStart = DayKey.diffInDays(mostRecent.startDate, today);

  if (daysSinceStart > config.maxValidCycleLengthDays) {
    return StaleDataPrediction(
      lastPeriodStartDate: mostRecent.startDate,
      daysSinceLastPeriodStart: daysSinceStart,
    );
  }

  final completeCycles = sorted.where((c) => c.cycleLengthDays != null).toList();
  final validCycles = completeCycles
      .where((c) =>
          c.cycleLengthDays! >= config.minValidCycleLengthDays &&
          c.cycleLengthDays! <= config.maxValidCycleLengthDays)
      .toList();
  final excludedCyclesCount = completeCycles.length - validCycles.length;
  if (excludedCyclesCount > 0) {
    confidenceReasons.add(
      'Se excluyeron $excludedCyclesCount ciclo(s) fuera del rango válido '
      '(${config.minValidCycleLengthDays}-${config.maxValidCycleLengthDays} días).',
    );
  }

  final windowed = validCycles.length > config.maxCyclesConsidered
      ? validCycles.sublist(validCycles.length - config.maxCyclesConsidered)
      : validCycles;
  final completeCyclesConsidered = windowed.length;

  final double averageCycleLengthDays;
  final double cycleLengthStdDevDays;
  final double averagePeriodLengthDays;
  final double rangeHalfWidthDays;

  if (completeCyclesConsidered < config.minCompleteCyclesForMedium) {
    averageCycleLengthDays = config.defaultCycleLengthDays.toDouble();
    cycleLengthStdDevDays = 0;
    averagePeriodLengthDays = mostRecent.periodLengthDays.toDouble();
    rangeHalfWidthDays = config.defaultRangeHalfWidthDays.toDouble();
    confidenceReasons.add(
      'Menos de ${config.minCompleteCyclesForMedium} ciclos completos '
      'registrados; se usa un promedio por defecto de '
      '${config.defaultCycleLengthDays} días.',
    );
  } else {
    final cycleLengths = windowed.map((c) => c.cycleLengthDays!).toList();
    final periodLengths = windowed.map((c) => c.periodLengthDays).toList();
    final cycleStats = _weightedMeanAndStdDev(cycleLengths);
    final periodStats = _weightedMeanAndStdDev(periodLengths);
    averageCycleLengthDays = cycleStats.mean;
    cycleLengthStdDevDays = cycleStats.stdDev;
    averagePeriodLengthDays = periodStats.mean;
    rangeHalfWidthDays = math.max(
      config.rangeStdDevMultiplier * cycleStats.stdDev,
      config.minRangeHalfWidthDays.toDouble(),
    );
  }

  final halfWidthDays = rangeHalfWidthDays.round();
  final nextPeriodExpectedDate =
      DayKey.addDays(mostRecent.startDate, averageCycleLengthDays.round());
  final nextPeriodEarliestDate = DayKey.addDays(nextPeriodExpectedDate, -halfWidthDays);
  final nextPeriodLatestDate = DayKey.addDays(nextPeriodExpectedDate, halfWidthDays);
  final estimatedOvulationDate =
      DayKey.addDays(nextPeriodExpectedDate, -config.lutealPhaseDays);
  final fertileWindowStartDate =
      DayKey.addDays(estimatedOvulationDate, -config.fertileWindowDaysBeforeOvulation);
  final fertileWindowEndDate = estimatedOvulationDate;

  // Fase actual. menstrualEndDay usa el mayor entre la duracion
  // observada del periodo mas reciente (que puede seguir activo y ya
  // superar el promedio historico) y el promedio historico, para no
  // "salir" de la fase menstrual mientras todavia hay sangrado
  // registrado por encima de lo usual.
  final rawCycleDay = daysSinceStart + 1;
  final cycleDay = rawCycleDay < 1 ? 1 : rawCycleDay;
  final menstrualEndDay = math.max(
    mostRecent.periodLengthDays,
    averagePeriodLengthDays.round(),
  );
  final ovulationCycleDay =
      DayKey.diffInDays(mostRecent.startDate, estimatedOvulationDate) + 1;
  final ovulatoryStart = ovulationCycleDay - config.ovulationPhaseHalfWidthDays;
  final ovulatoryEnd = ovulationCycleDay + config.ovulationPhaseHalfWidthDays;

  final CyclePhase currentPhase;
  if (cycleDay <= menstrualEndDay) {
    currentPhase = CyclePhase.menstrual;
  } else if (cycleDay >= ovulatoryStart && cycleDay <= ovulatoryEnd) {
    currentPhase = CyclePhase.ovulatoria;
  } else if (cycleDay < ovulatoryStart) {
    currentPhase = CyclePhase.folicular;
  } else {
    currentPhase = CyclePhase.lutea;
  }

  final isPeriodLate = DayKey.diffInDays(nextPeriodLatestDate, today) > 0;
  final daysLate = isPeriodLate ? DayKey.diffInDays(nextPeriodLatestDate, today) : 0;

  final PredictionConfidence confidence;
  if (completeCyclesConsidered < config.minCompleteCyclesForMedium) {
    confidence = PredictionConfidence.low;
  } else {
    final ratio = cycleLengthStdDevDays / averageCycleLengthDays;
    if (ratio > config.highStdDevRelativeRatio) {
      confidence = PredictionConfidence.low;
      confidenceReasons.add(
        'Variabilidad alta entre ciclos (±${(ratio * 100).toStringAsFixed(0)}% '
        'del promedio).',
      );
    } else if (completeCyclesConsidered >= config.minCompleteCyclesForHigh) {
      confidence = PredictionConfidence.high;
    } else {
      confidence = PredictionConfidence.medium;
    }
  }

  return ActivePrediction(
    lastPeriodStartDate: mostRecent.startDate,
    daysSinceLastPeriodStart: daysSinceStart,
    averageCycleLengthDays: averageCycleLengthDays,
    cycleLengthStdDevDays: cycleLengthStdDevDays,
    averagePeriodLengthDays: averagePeriodLengthDays,
    completeCyclesConsidered: completeCyclesConsidered,
    excludedCyclesCount: excludedCyclesCount,
    nextPeriodEarliestDate: nextPeriodEarliestDate,
    nextPeriodExpectedDate: nextPeriodExpectedDate,
    nextPeriodLatestDate: nextPeriodLatestDate,
    estimatedOvulationDate: estimatedOvulationDate,
    fertileWindowStartDate: fertileWindowStartDate,
    fertileWindowEndDate: fertileWindowEndDate,
    currentPhase: currentPhase,
    isPeriodLate: isPeriodLate,
    daysLate: daysLate,
    confidence: confidence,
    confidenceReasons: confidenceReasons,
  );
}
