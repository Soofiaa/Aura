import 'package:intl/intl.dart';

class DateUtilsAura {
  static String formatFechaLarga(DateTime fecha) {
    final formato = DateFormat("d 'de' MMMM 'de' y", 'es_ES');
    return formato.format(fecha);
  }

  static String formatFechaCorta(DateTime fecha) {
    final formato = DateFormat('dd/MM/yyyy');
    return formato.format(fecha);
  }

  static int diasHasta(DateTime fecha) {
    final hoy = DateTime.now();
    return fecha.difference(DateTime(hoy.year, hoy.month, hoy.day)).inDays;
  }

  static String tiempoRelativo(DateTime fecha) {
    final dias = diasHasta(fecha);
    if (dias == 0) return "Hoy";
    if (dias == 1) return "Mañana";
    if (dias == -1) return "Ayer";
    if (dias > 1 && dias <= 7) return "En $dias días";
    if (dias < -1 && dias >= -7) return "Hace ${dias.abs()} días";

    final formato = DateFormat("d 'de' MMM", 'es_ES');
    return formato.format(fecha);
  }

  static String formatConDia(DateTime fecha) {
    final formato = DateFormat("EEEE d 'de' MMMM", 'es_ES');
    String texto = formato.format(fecha);
    return texto[0].toUpperCase() + texto.substring(1);
  }

  static bool estaEntre(DateTime fecha, DateTime inicio, DateTime fin) {
    return fecha.isAfter(inicio) && fecha.isBefore(fin);
  }

  static int diferenciaSemanas(DateTime fecha1, DateTime fecha2) {
    return fecha1.difference(fecha2).inDays ~/ 7;
  }
}
