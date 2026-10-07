import '../utils/day_key.dart';
import 'cycle_deriver.dart';

/// Rangos de mas de esta cantidad de dias piden confirmacion antes de
/// marcarse (HU-04, crit. 5).
const int longRangeConfirmationThreshold = 10;

/// Seleccion de un rango de dias en el Calendario (mejora U-1, opciones
/// A + B). Vive en el estado de la pantalla, no en table_calendar: cada
/// toque llega como un dia y [tap] decide el rango nuevo. Con un rango ya
/// completo, ningun toque lo reinicia: lo alarga, mueve el inicio o
/// acorta el final.
class RangeSelection {
  const RangeSelection._(this.start, this.end);

  static const RangeSelection empty = RangeSelection._(null, null);

  /// Primer dia ('yyyy-MM-dd'), o null si no hay seleccion.
  final String? start;

  /// Ultimo dia, o null si solo se eligio el inicio.
  final String? end;

  bool get isEmpty => start == null;
  bool get hasOnlyStart => start != null && end == null;
  bool get isComplete => start != null && end != null;

  /// Dias del rango; con solo el inicio, 1.
  int get dayCount =>
      isEmpty ? 0 : DayKey.diffInDays(start!, end ?? start!) + 1;

  /// Supera [longRangeConfirmationThreshold] dias.
  bool get isLong => dayCount > longRangeConfirmationThreshold;

  /// Todos los dias del rango, en orden.
  List<String> get days => [
        for (var i = 0; i < dayCount; i++) DayKey.addDays(start!, i),
      ];

  /// Nuevo rango tras tocar [day]:
  /// - vacio: [day] es el inicio;
  /// - solo inicio: [day] completa el rango (antes o despues del inicio;
  ///   el mismo dia deja un rango de 1 dia);
  /// - completo: despues del final lo alarga, antes del inicio mueve el
  ///   inicio, adentro acorta el final, el inicio deja un rango de 1 dia
  ///   y el final no cambia nada.
  RangeSelection tap(String day) {
    final s = start;
    final e = end;
    if (s == null) return RangeSelection._(day, null);
    if (e == null) {
      return DayKey.isBefore(day, s)
          ? RangeSelection._(day, s)
          : RangeSelection._(s, day);
    }
    if (DayKey.isBefore(e, day)) return RangeSelection._(s, day);
    if (DayKey.isBefore(day, s)) return RangeSelection._(day, e);
    if (day == e) return this;
    return RangeSelection._(s, day); // el inicio o un dia de adentro
  }

  /// "Cancelar seleccion".
  RangeSelection cleared() => empty;

  @override
  bool operator ==(Object other) =>
      other is RangeSelection && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'RangeSelection($start, $end)';
}

/// Que hacer con el fin del periodo al marcar un rango (regla R-1).
enum RangeEndAction {
  /// Se marca y se guarda el fin en el ultimo dia del rango.
  close,

  /// Se pregunta "Ya termino tu periodo?" antes de guardar el fin.
  ask,

  /// Solo se marca; el cierre que hubiera sigue valiendo.
  markOnly,
}

/// R-1 con la condicion de la decision 5: el fin solo se guarda si el
/// ultimo dia del rango es el ultimo dia del periodo que resulta de
/// marcarlo (si hay dias marcados despues dentro del mismo periodo, se
/// marca y nada mas). En ese caso: si termina hace 2 dias o mas se cierra;
/// si termina hoy o ayer se pregunta.
RangeEndAction rangeEndAction({
  required List<String> rangeDays,
  required List<String> existingPeriodDays,
  required String today,
  int maxGap = maxGapWithinPeriod,
}) {
  if (rangeDays.isEmpty) return RangeEndAction.markOnly;
  final rangeEnd = rangeDays.reduce((a, b) => DayKey.isBefore(a, b) ? b : a);
  final daysAgo = DayKey.diffInDays(rangeEnd, today);
  if (daysAgo < 0) return RangeEndAction.markOnly;

  final run = groupPeriodRuns([...existingPeriodDays, ...rangeDays],
          maxGap: maxGap)
      .firstWhere((r) => r.contains(rangeEnd));
  if (run.last != rangeEnd) return RangeEndAction.markOnly;

  return daysAgo >= 2 ? RangeEndAction.close : RangeEndAction.ask;
}
