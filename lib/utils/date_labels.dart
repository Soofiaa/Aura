import 'package:intl/intl.dart';

import 'period_end_messages.dart';

/// "4 de octubre" (el de dayMonthLabel) si [dayKey] es del mismo ano que
/// [today]; "4 de octubre de 2025" (el de los mensajes del respaldo) si
/// es de otro. Lo usan Ajustes y la tarjeta del recordatorio de respaldo.
String dayMonthLabelWithYear(String dayKey, {required String today}) {
  if (dayKey.substring(0, 4) == today.substring(0, 4)) {
    return dayMonthLabel(dayKey);
  }
  return DateFormat("d 'de' MMMM 'de' y", 'es').format(DateTime.parse(dayKey));
}
