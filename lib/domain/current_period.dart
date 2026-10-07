import '../utils/day_key.dart';
import 'cycle_deriver.dart';

/// El periodo mas reciente, si todavia es "actual" (ver
/// [findCurrentPeriod]). Lo usan Inicio y el Calendario para decidir que
/// ofrecer ("Sigue", "Termino hoy", "Me llego hoy") y que dias estimar.
class CurrentPeriod {
  const CurrentPeriod({
    required this.startDate,
    required this.lastMarkedDate,
    required this.isClosed,
    required this.dayNumber,
  });

  /// Primer dia marcado del periodo.
  final String startDate;

  /// Ultimo dia marcado del periodo (puede ser anterior a hoy).
  final String lastMarkedDate;

  /// Cerrado segun D-1: fin guardado en su ultimo dia o un "No" explicito
  /// entre 1 y 7 dias despues.
  final bool isClosed;

  /// Dia de hoy dentro del periodo: 1 el dia del inicio.
  final int dayNumber;

  bool get isOpen => !isClosed;
}

/// El periodo mas reciente (el de inicio mas reciente en [cycles]), solo
/// mientras todavia pueda seguir: su ultimo dia marcado es de hace
/// [maxGap] dias o menos y hoy no es anterior a su inicio. Si pasaron mas
/// dias, un dia marcado hoy empezaria otro periodo (regla de
/// [deriveCycles]), asi que no hay periodo actual: devuelve null. Un
/// periodo antiguo que quedo abierto nunca es el actual.
CurrentPeriod? findCurrentPeriod({
  required List<CycleSummary> cycles,
  required String today,
  int maxGap = maxGapWithinPeriod,
}) {
  if (cycles.isEmpty) return null;
  final latest = cycles.reduce(
      (a, b) => DayKey.compare(a.startDate, b.startDate) >= 0 ? a : b);
  final lastMarked =
      DayKey.addDays(latest.startDate, latest.periodLengthDays - 1);

  if (DayKey.isBefore(today, latest.startDate)) return null;
  if (DayKey.diffInDays(lastMarked, today) > maxGap) return null;

  return CurrentPeriod(
    startDate: latest.startDate,
    lastMarkedDate: lastMarked,
    isClosed: latest.isClosed,
    dayNumber: DayKey.diffInDays(latest.startDate, today) + 1,
  );
}

/// Dias estimados del periodo actual (decision E-1): desde el dia
/// siguiente al ultimo marcado hasta completar la duracion habitual
/// contada desde el inicio. Solo si el periodo actual (ver
/// [findCurrentPeriod]) esta abierto. Pueden incluir dias pasados sin
/// marcar y dias futuros. Nunca se guardan.
List<String> estimatedPeriodDays({
  required List<CycleSummary> cycles,
  required int typicalPeriodLengthDays,
  required String today,
}) {
  final current = findCurrentPeriod(cycles: cycles, today: today);
  if (current == null || current.isClosed) return const [];

  final lastEstimated =
      DayKey.addDays(current.startDate, typicalPeriodLengthDays - 1);
  return [
    for (var day = DayKey.addDays(current.lastMarkedDate, 1);
        !DayKey.isBefore(lastEstimated, day);
        day = DayKey.addDays(day, 1))
      day,
  ];
}

/// "Confirmar dias" solo esta disponible cuando el ultimo dia estimado es
/// hoy o ya paso (decision 4): nunca se guarda un dia futuro.
bool canConfirmEstimates({
  required List<String> estimatedDays,
  required String today,
}) =>
    estimatedDays.isNotEmpty && !DayKey.isBefore(today, estimatedDays.last);

/// Por que no se puede terminar un periodo en un dia (decision 5).
enum PeriodEndProblem {
  /// El dia es anterior al inicio del periodo.
  beforeStart,

  /// El dia es posterior a hoy.
  future,

  /// Hay dias marcados despues de ese dia dentro del mismo periodo.
  markedDaysAfter,

  /// Ese dia tiene un "No" explicito (no hubo sangrado): no puede ser el
  /// ultimo dia del periodo, y el CHECK de D-1 no permite guardar ahi el
  /// fin.
  noBleedingThatDay,
}

class PeriodEndCheck {
  const PeriodEndCheck({this.problem, this.markedDaysAfter = 0});

  final PeriodEndProblem? problem;

  /// Cuantos dias marcados hay despues del dia elegido dentro del mismo
  /// periodo (para el mensaje de bloqueo).
  final int markedDaysAfter;

  bool get isValid => problem == null;
}

/// Revisa si el periodo que empieza en [periodStart] puede terminar en
/// [endDate] con "Termino otro dia" o "Termino este dia". Se bloquea si
/// hay dias marcados despues dentro del mismo periodo (decision 5): la
/// usuaria tiene que quitarlos primero o elegir otro dia. Tambien si
/// [endDate] tiene un "No" explicito en [explicitNonPeriodDays]: al
/// cerrar no se marca (decision 3) y el fin no se puede guardar en un dia
/// sin sangrado. [periodDays] son todos los dias marcados; solo cuentan
/// los del periodo de [periodStart].
PeriodEndCheck checkPeriodEnd({
  required String periodStart,
  required String endDate,
  required String today,
  required List<String> periodDays,
  required List<String> explicitNonPeriodDays,
  int maxGap = maxGapWithinPeriod,
}) {
  if (DayKey.isBefore(endDate, periodStart)) {
    return const PeriodEndCheck(problem: PeriodEndProblem.beforeStart);
  }
  if (DayKey.isBefore(today, endDate)) {
    return const PeriodEndCheck(problem: PeriodEndProblem.future);
  }
  if (explicitNonPeriodDays.contains(endDate)) {
    return const PeriodEndCheck(problem: PeriodEndProblem.noBleedingThatDay);
  }
  final run = groupPeriodRuns(periodDays, maxGap: maxGap).firstWhere(
    (r) => r.contains(periodStart),
    orElse: () => const [],
  );
  final after = run.where((d) => DayKey.isBefore(endDate, d)).length;
  if (after > 0) {
    return PeriodEndCheck(
        problem: PeriodEndProblem.markedDaysAfter, markedDaysAfter: after);
  }
  return const PeriodEndCheck();
}

/// Dias que se marcan como sangrado al terminar un periodo en [endDate]
/// (HU-03, crit. 2, con la decision 3): los dias de [periodStart] a
/// [endDate] que no estan marcados y no tienen un "No" explicito. Un "No"
/// es una declaracion de la usuaria y se respeta.
List<String> daysToMarkWhenClosing({
  required String periodStart,
  required String endDate,
  required List<String> periodDays,
  required List<String> explicitNonPeriodDays,
}) {
  final marked = periodDays.toSet();
  final explicitNo = explicitNonPeriodDays.toSet();
  return [
    for (var day = periodStart;
        !DayKey.isBefore(endDate, day);
        day = DayKey.addDays(day, 1))
      if (!marked.contains(day) && !explicitNo.contains(day)) day,
  ];
}

/// "Termino hoy" / "Termino otro dia" que deja un periodo de 1 dia pide
/// confirmacion (pregunta "Tu periodo duro solo 1 dia?", decision 14).
bool needsSingleDayConfirmation({
  required String periodStart,
  required String endDate,
}) =>
    periodStart == endDate;

/// Decision 7: si marcar [day] como inicio de un periodo lo sumaria a un
/// periodo anterior (porque queda a [maxGap] dias o menos de su ultimo
/// dia marcado, la regla de [deriveCycles]), devuelve ese ultimo dia
/// marcado para avisarlo. Null si empezaria un periodo nuevo o si [day]
/// ya esta marcado. Solo cuentan periodos anteriores a [day].
String? periodThatDayWouldJoin({
  required String day,
  required List<String> periodDays,
  int maxGap = maxGapWithinPeriod,
}) {
  if (periodDays.contains(day)) return null;
  String? lastBefore;
  for (final marked in periodDays) {
    if (DayKey.isBefore(marked, day) &&
        (lastBefore == null || DayKey.isBefore(lastBefore, marked))) {
      lastBefore = marked;
    }
  }
  if (lastBefore == null) return null;
  return DayKey.diffInDays(lastBefore, day) <= maxGap ? lastBefore : null;
}

/// Decision 7, hacia adelante: si marcar [day] lo sumaria a un periodo
/// POSTERIOR (porque queda a [maxGap] dias o menos antes de su primer
/// dia), devuelve ese primer dia para avisarlo. Null si [day] ya esta
/// marcado, si no hay un periodo que empiece a esa distancia, o si el
/// dia marcado siguiente no es el inicio de un periodo (entonces [day]
/// cae en un hueco de un periodo ya existente, y eso lo cubre
/// [periodThatDayWouldJoin]).
String? laterPeriodThatDayWouldJoin({
  required String day,
  required List<String> periodDays,
  int maxGap = maxGapWithinPeriod,
}) {
  if (periodDays.contains(day)) return null;
  for (final run in groupPeriodRuns(periodDays, maxGap: maxGap)) {
    final start = run.first;
    if (DayKey.isBefore(day, start)) {
      final gap = DayKey.diffInDays(day, start);
      // Solo el primer periodo posterior a [day] puede quedar cerca.
      return gap <= maxGap ? start : null;
    }
    if (!DayKey.isBefore(run.last, day)) return null;
  }
  return null;
}
