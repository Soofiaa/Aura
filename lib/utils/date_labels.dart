import 'package:intl/intl.dart';

import 'aura_localizations.dart';
import 'period_end_messages.dart';

/// "4 de octubre" (el de dayMonthLabel) si [dayKey] es del mismo ano que
/// [today]; "4 de octubre de 2025" (el de los mensajes del respaldo) si
/// es de otro. Lo usan Ajustes y la tarjeta del recordatorio de respaldo.
String dayMonthLabelWithYear(String dayKey, {required String today}) {
  if (dayKey.substring(0, 4) == today.substring(0, 4)) {
    return dayMonthLabel(dayKey);
  }
  return fullDateLabel(dayKey);
}

/// "4 oct", para donde no cabe la fecha larga (Estadisticas, el widget).
String shortDayMonthLabel(String dayKey) =>
    DateFormat(auraIsEnglish ? 'MMM d' : 'd MMM', auraLanguage)
        .format(DateTime.parse(dayKey));

/// "4 de octubre de 2025", siempre con el ano (la fecha del formulario
/// "Registrar dia"). TalkBack la lee bien, a diferencia de "4/10/2025".
String fullDateLabel(String dayKey) =>
    DateFormat(auraIsEnglish ? 'MMMM d, y' : "d 'de' MMMM 'de' y", auraLanguage)
        .format(DateTime.parse(dayKey));
