import '../data/models/day_enums.dart';
import '../utils/day_key.dart';
import 'cycle_deriver.dart';

/// Regla D-2 (docs/ESPECIFICACION_v1.1.md, seccion 10): que periodos de
/// los datos de la v1.0 se cierran con period_end = inferred al pasar a
/// v4. La usan la migracion de la base y la conversion de un respaldo v3,
/// para que ambas den el mismo resultado. Funcion pura: "hoy" llega como
/// parametro.
///
/// Regla conservadora: un periodo abierto solo queda fuera del promedio
/// de duracion, mientras que un cierre equivocado lo distorsiona.

/// Minimo de dias marcados para inferir el cierre. Con 1 solo dia no se
/// distingue un periodo real de 1 dia de uno en que solo se marco el
/// inicio (R-2).
const int legacyMinMarkedDays = 2;

/// Hueco interno maximo (dias sin marcar entre dos dias marcados
/// seguidos) para inferir el cierre (D-2 y R-2).
const int legacyMaxInternalGapDays = 1;

/// El periodo mas reciente solo se cierra si su ultimo dia es de hace
/// MAS de esta cantidad de dias: antes puede seguir creciendo.
const int legacyRecentPeriodDays = 7;

/// Por que un periodo queda como queda. El orden de los valores es el
/// orden en que se evaluan: se informa el primer motivo que aplica.
enum LegacyPeriodOutcome {
  /// Ya cerrado por la regla del "no" explicito; no se escribe nada.
  closedByExplicitNo,

  /// Su ultimo dia ya tiene period_end (base que paso por una app v3
  /// despues de la v4); no se escribe nada.
  alreadyHasEnd,

  /// Menos de [legacyMinMarkedDays] dias marcados: queda abierto.
  singleDay,

  /// Hueco interno mayor a [legacyMaxInternalGapDays]: queda abierto.
  gapTooLarge,

  /// Es el periodo mas reciente y termino hace [legacyRecentPeriodDays]
  /// dias o menos (o en el futuro): puede seguir, queda abierto.
  mayContinue,

  /// Se cierra: period_end = inferred en su ultimo dia.
  inferred,
}

/// Resultado de evaluar un periodo con la regla D-2.
class LegacyPeriodAssessment {
  const LegacyPeriodAssessment({
    required this.startDate,
    required this.lastDate,
    required this.markedDays,
    required this.periodLengthDays,
    required this.maxInternalGapDays,
    required this.outcome,
  });

  final String startDate;

  /// Ultimo dia marcado: donde se escribe period_end si se infiere.
  final String lastDate;

  /// Dias con is_period_day = 1 (no la duracion).
  final int markedDays;

  /// Primer a ultimo dia marcado, inclusive (igual que CycleSummary).
  final int periodLengthDays;

  /// Mayor cantidad de dias sin marcar entre dos dias marcados seguidos
  /// (0 si todos son consecutivos).
  final int maxInternalGapDays;

  final LegacyPeriodOutcome outcome;

  /// Cerrado despues de aplicar la regla (por el "no", por un
  /// period_end previo o por inferencia).
  bool get isClosed =>
      outcome == LegacyPeriodOutcome.closedByExplicitNo ||
      outcome == LegacyPeriodOutcome.alreadyHasEnd ||
      outcome == LegacyPeriodOutcome.inferred;
}

/// Evalua cada periodo de [periodDays] (claves 'yyyy-MM-dd' con
/// is_period_day = 1, en cualquier orden) con la regla D-2. Devuelve un
/// resultado por periodo, del mas antiguo al mas reciente.
///
/// [explicitNonPeriodDays] son los "no" explicitos (is_period_day = 0 y
/// period_day_explicit = 1); [periodEnds], las fechas que ya tienen
/// period_end. Las filas con solo sintomas, animo o notas no entran en
/// ninguna lista: no son dias marcados y cuentan como hueco.
List<LegacyPeriodAssessment> assessLegacyPeriods({
  required List<String> periodDays,
  List<String> explicitNonPeriodDays = const [],
  Map<String, PeriodEndSource> periodEnds = const {},
  required String today,
  int maxGap = maxGapWithinPeriod,
}) {
  final runs = groupPeriodRuns(periodDays, maxGap: maxGap);
  final explicitNo = explicitNonPeriodDays.toSet().toList();

  return [
    for (var i = 0; i < runs.length; i++)
      _assessRun(
        runs[i],
        isMostRecent: i == runs.length - 1,
        explicitNo: explicitNo,
        periodEnds: periodEnds,
        today: today,
        maxGap: maxGap,
      ),
  ];
}

/// Fechas donde la migracion (o la conversion de un respaldo v3) escribe
/// period_end = inferred, ordenadas. Ver [assessLegacyPeriods].
List<String> inferLegacyPeriodEnds({
  required List<String> periodDays,
  List<String> explicitNonPeriodDays = const [],
  Map<String, PeriodEndSource> periodEnds = const {},
  required String today,
  int maxGap = maxGapWithinPeriod,
}) {
  return [
    for (final period in assessLegacyPeriods(
      periodDays: periodDays,
      explicitNonPeriodDays: explicitNonPeriodDays,
      periodEnds: periodEnds,
      today: today,
      maxGap: maxGap,
    ))
      if (period.outcome == LegacyPeriodOutcome.inferred) period.lastDate,
  ];
}

LegacyPeriodAssessment _assessRun(
  List<String> run, {
  required bool isMostRecent,
  required List<String> explicitNo,
  required Map<String, PeriodEndSource> periodEnds,
  required String today,
  required int maxGap,
}) {
  final first = run.first;
  final last = run.last;

  var maxInternalGapDays = 0;
  for (var i = 1; i < run.length; i++) {
    final unmarked = DayKey.diffInDays(run[i - 1], run[i]) - 1;
    if (unmarked > maxInternalGapDays) maxInternalGapDays = unmarked;
  }

  final LegacyPeriodOutcome outcome;
  if (isEndConfirmedByExplicitNo(last, explicitNo, maxGap: maxGap)) {
    outcome = LegacyPeriodOutcome.closedByExplicitNo;
  } else if (periodEnds.containsKey(last)) {
    outcome = LegacyPeriodOutcome.alreadyHasEnd;
  } else if (run.length < legacyMinMarkedDays) {
    outcome = LegacyPeriodOutcome.singleDay;
  } else if (maxInternalGapDays > legacyMaxInternalGapDays) {
    outcome = LegacyPeriodOutcome.gapTooLarge;
  } else if (isMostRecent &&
      DayKey.diffInDays(last, today) <= legacyRecentPeriodDays) {
    // Incluye un ultimo dia en el futuro (diferencia negativa).
    outcome = LegacyPeriodOutcome.mayContinue;
  } else {
    outcome = LegacyPeriodOutcome.inferred;
  }

  return LegacyPeriodAssessment(
    startDate: first,
    lastDate: last,
    markedDays: run.length,
    periodLengthDays: DayKey.diffInDays(first, last) + 1,
    maxInternalGapDays: maxInternalGapDays,
    outcome: outcome,
  );
}
