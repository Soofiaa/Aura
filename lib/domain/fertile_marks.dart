import 'cycle_predictor.dart';

/// Fechas de ovulacion y ventana fertil que la app muestra (claves
/// 'yyyy-MM-dd', las mismas de [ActivePrediction]).
class FertileMarks {
  const FertileMarks({
    required this.ovulationDate,
    required this.windowStartDate,
    required this.windowEndDate,
  });

  final String ovulationDate;
  final String windowStartDate;
  final String windowEndDate;

  @override
  bool operator ==(Object other) =>
      other is FertileMarks &&
      other.ovulationDate == ovulationDate &&
      other.windowStartDate == windowStartDate &&
      other.windowEndDate == windowEndDate;

  @override
  int get hashCode =>
      Object.hash(ovulationDate, windowStartDate, windowEndDate);

  @override
  String toString() =>
      'FertileMarks(ovulation: $ovulationDate, '
      'window: $windowStartDate..$windowEndDate)';
}

/// Regla unica de que fertilidad se muestra (HU-05), para Inicio y el
/// Calendario. Null salvo que se cumplan todas:
/// - hay una [ActivePrediction] (ni null ni [StaleDataPrediction]);
/// - la usuaria quiere verla ([showFertileWindow], H5-3);
/// - la confianza no es baja (H5-1 A: la ovulacion se resta del proximo
///   periodo, asi que es menos confiable todavia);
/// - el periodo no esta atrasado: el ciclo real ya supero lo estimado y
///   la ovulacion estimada de este ciclo ya no dice nada.
/// El predictor no cambia: esto es solo lo que se muestra.
FertileMarks? visibleFertileMarks(
  CyclePrediction? prediction, {
  required bool showFertileWindow,
}) {
  if (prediction is! ActivePrediction) return null;
  if (!showFertileWindow) return null;
  if (prediction.confidence == PredictionConfidence.low) return null;
  if (prediction.isPeriodLate) return null;
  return FertileMarks(
    ovulationDate: prediction.estimatedOvulationDate,
    windowStartDate: prediction.fertileWindowStartDate,
    windowEndDate: prediction.fertileWindowEndDate,
  );
}
