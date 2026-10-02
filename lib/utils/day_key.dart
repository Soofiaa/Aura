/// Claves de dia calendario como texto 'yyyy-MM-dd'.
///
/// Las diferencias de dias se calculan via DateTime.utc, nunca con
/// DateTime local: en Chile el cambio de hora ocurre a medianoche
/// (ver 2026-04-04/05 y 2026-09-05/06/07), lo que produce dias de
/// 23 o 25 horas y rompe difference().inDays con fechas locales.
class DayKey {
  DayKey._();

  /// Construye la clave a partir de los componentes de calendario
  /// (year/month/day) de [date], sin importar su zona horaria.
  static String fromDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String today() => fromDate(DateTime.now());

  /// Parsea una clave 'yyyy-MM-dd' a un DateTime.utc a medianoche,
  /// usado solo como ancla para aritmetica de dias (no representa un
  /// instante real en UTC).
  static DateTime toUtcAnchor(String key) {
    final parts = key.split('-');
    if (parts.length != 3) {
      throw FormatException('Clave de dia invalida: $key');
    }
    final y = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final d = int.parse(parts[2]);
    return DateTime.utc(y, m, d);
  }

  /// Diferencia en dias calendario entre [a] y [b] (b - a).
  static int diffInDays(String a, String b) {
    return toUtcAnchor(b).difference(toUtcAnchor(a)).inDays;
  }

  static String addDays(String key, int days) {
    final anchor = toUtcAnchor(key).add(Duration(days: days));
    return fromDate(anchor);
  }

  /// true si [a] es cronologicamente anterior a [b]. El formato
  /// 'yyyy-MM-dd' con ceros a la izquierda ordena lexicograficamente
  /// igual que cronologicamente, pero se usa la via UTC para mantener
  /// una unica fuente de verdad sobre como comparar claves.
  static bool isBefore(String a, String b) => diffInDays(a, b) > 0;

  static int compare(String a, String b) => a.compareTo(b);
}
