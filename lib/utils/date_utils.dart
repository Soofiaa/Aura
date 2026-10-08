import 'package:intl/intl.dart';

class DateUtilsAura {
  static String formatFechaCorta(DateTime fecha) {
    final formato = DateFormat('dd/MM/yyyy');
    return formato.format(fecha);
  }
}
