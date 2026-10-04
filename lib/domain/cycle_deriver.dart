import '../utils/day_key.dart';

/// Si entre un dia de sangrado y el dia de sangrado anterior pasan mas de
/// esta cantidad de dias, se considera el inicio de un ciclo nuevo en vez
/// de una continuacion (p.ej. un dia olvidado) del mismo periodo.
const int maxGapWithinPeriod = 7;

/// Resumen de un ciclo derivado de los dias de sangrado registrados.
class CycleSummary {
  /// Primer dia de sangrado del periodo ('yyyy-MM-dd').
  final String startDate;

  /// Duracion del periodo de sangrado: dias desde el primer hasta el
  /// ultimo dia de sangrado de ese periodo, inclusive (si hubo un dia sin
  /// registrar en el medio pero dentro de [maxGapWithinPeriod], igual
  /// cuenta como parte del mismo periodo).
  final int periodLengthDays;

  /// Duracion del ciclo: dias entre el inicio de este ciclo y el inicio
  /// del siguiente. Null si es el ultimo ciclo (aun abierto, sin un
  /// proximo periodo registrado todavia).
  final int? cycleLengthDays;

  /// true si hay un dia confirmado explicitamente como "sin sangrado"
  /// (is_period_day=false con period_day_explicit=true) dentro de los
  /// dias de tolerancia despues del ultimo dia de sangrado de este
  /// periodo. Ese "no" explicito lo escriben el "No" de la pregunta de
  /// Inicio y "Quitar marca" del calendario
  /// (CycleRepository.setPeriodDayExplicitly), y el formulario general
  /// unicamente cuando se apaga el interruptor sobre un dia que ya era
  /// de sangrado (CycleRepository.upsertDay); "Deshacer" puede
  /// restaurarlo (restoreDaySnapshot). Marcar dias o rangos en el
  /// calendario (markPeriodDay/markPeriodDays) no lo escribe. Permite
  /// que predictCycle deje de alargar la fase menstrual por el promedio
  /// historico cuando la usuaria ya confirmo que termino.
  final bool periodConfirmedEnded;

  const CycleSummary({
    required this.startDate,
    required this.periodLengthDays,
    required this.cycleLengthDays,
    this.periodConfirmedEnded = false,
  });

  @override
  bool operator ==(Object other) =>
      other is CycleSummary &&
      other.startDate == startDate &&
      other.periodLengthDays == periodLengthDays &&
      other.cycleLengthDays == cycleLengthDays &&
      other.periodConfirmedEnded == periodConfirmedEnded;

  @override
  int get hashCode => Object.hash(
      startDate, periodLengthDays, cycleLengthDays, periodConfirmedEnded);

  @override
  String toString() =>
      'CycleSummary(startDate: $startDate, periodLengthDays: $periodLengthDays, '
      'cycleLengthDays: $cycleLengthDays, periodConfirmedEnded: $periodConfirmedEnded)';
}

/// Deriva los ciclos a partir de la lista de dias marcados como dia de
/// sangrado (is_period_day = true). Funcion pura, sin dependencia de la
/// base de datos: [periodDays] son claves 'yyyy-MM-dd' en cualquier orden,
/// con o sin duplicados.
///
/// Un dia de sangrado inicia un ciclo nuevo si el dia de sangrado anterior
/// (una vez ordenados y sin duplicados) quedo a mas de [maxGap] dias de
/// distancia; de lo contrario se considera parte del mismo periodo.
List<CycleSummary> deriveCycles(
  List<String> periodDays, {
  int maxGap = maxGapWithinPeriod,
  List<String> explicitNonPeriodDays = const [],
}) {
  if (periodDays.isEmpty) return [];

  final sorted = periodDays.toSet().toList()..sort(DayKey.compare);
  final nonPeriodSorted = explicitNonPeriodDays.toSet().toList()
    ..sort(DayKey.compare);

  // Agrupa en corridas: una corrida nueva empieza cuando el hueco con el
  // dia anterior supera maxGap.
  final runs = <List<String>>[];
  var currentRun = <String>[sorted.first];
  for (var i = 1; i < sorted.length; i++) {
    final gap = DayKey.diffInDays(sorted[i - 1], sorted[i]);
    if (gap > maxGap) {
      runs.add(currentRun);
      currentRun = <String>[sorted[i]];
    } else {
      currentRun.add(sorted[i]);
    }
  }
  runs.add(currentRun);

  final summaries = <CycleSummary>[];
  for (var i = 0; i < runs.length; i++) {
    final run = runs[i];
    final periodStart = run.first;
    final periodEnd = run.last;
    final periodLengthDays = DayKey.diffInDays(periodStart, periodEnd) + 1;
    final isLast = i == runs.length - 1;
    final cycleLengthDays =
        isLast ? null : DayKey.diffInDays(periodStart, runs[i + 1].first);

    final periodConfirmedEnded = nonPeriodSorted.any((explicitDate) {
      final gap = DayKey.diffInDays(periodEnd, explicitDate);
      return gap > 0 && gap <= maxGap;
    });

    summaries.add(CycleSummary(
      startDate: periodStart,
      periodLengthDays: periodLengthDays,
      cycleLengthDays: cycleLengthDays,
      periodConfirmedEnded: periodConfirmedEnded,
    ));
  }

  return summaries;
}
