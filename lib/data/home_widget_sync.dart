import 'dart:async';
import 'dart:convert';

import '../domain/current_period.dart';
import '../domain/cycle_predictor.dart';
import '../utils/android_system.dart';
import '../utils/aura_localizations.dart';
import '../utils/date_labels.dart';
import '../utils/day_key.dart';
import 'device_settings_store.dart';
import 'repositories/cycle_repository.dart';

/// Dias por adelantado que se le dejan escritos al widget: Android lo
/// redibuja sin abrir la app y elige el texto del dia.
const int homeWidgetDays = 60;

/// Titulo y texto del widget de la pantalla de inicio en [today], con lo
/// mismo que muestra Inicio. [discreet]: sin datos, solo "Aura".
({String title, String text}) homeWidgetText(PredictionInputs inputs,
    String today, {required bool discreet}) {
  if (discreet) return (title: 'Aura', text: tr('Toca para abrir', 'Tap to open'));

  if (inputs.predictionsPaused) {
    final embarazo = inputs.pregnancies.last;
    if (embarazo.end != null) {
      return (
        title: tr('Predicciones en pausa', 'Predictions paused'),
        text: tr('Registra tu período cuando vuelva',
            'Log your period when it returns'),
      );
    }
    final dias = DayKey.diffInDays(embarazo.start, today);
    final s = dias ~/ 7, d = dias % 7;
    return (
      title: tr('Tu embarazo', 'Your pregnancy'),
      text: tr('$s ${s == 1 ? 'semana' : 'semanas'} y $d ${d == 1 ? 'día' : 'días'}',
          '$s ${s == 1 ? 'week' : 'weeks'} and $d ${d == 1 ? 'day' : 'days'}'),
    );
  }

  final prediccion =
      predictCycle(cycles: inputs.cycles, today: today, config: inputs.config);
  switch (prediccion) {
    case null:
      return (
        title: 'Aura',
        text: tr('Registra tu primer día', 'Log your first day'),
      );
    case StaleDataPrediction():
      return (
        title: 'Aura',
        text: tr('Registra tu período para ver una predicción',
            'Log your period to see a prediction'),
      );
    case ActivePrediction p:
      // Periodo en curso, como en Inicio (_periodoEnCurso).
      final actual = findCurrentPeriod(cycles: inputs.cycles, today: today);
      if (actual != null &&
          actual.isOpen &&
          (p.currentPhase == CyclePhase.menstrual ||
              actual.lastMarkedDate == today ||
              actual.lastMarkedDate == DayKey.addDays(today, -1))) {
        return (
          title: tr('Día ${actual.dayNumber} de tu período',
              'Day ${actual.dayNumber} of your period'),
          text: tr('Toca para registrar hoy', 'Tap to log today'),
        );
      }
      if (p.isPeriodLate) {
        return (
          title: tr('Período atrasado', 'Period late'),
          text: tr('${p.daysLate} ${p.daysLate == 1 ? 'día' : 'días'} de atraso',
              '${p.daysLate} ${p.daysLate == 1 ? 'day' : 'days'} late'),
        );
      }
      final faltan = DayKey.diffInDays(today, p.nextPeriodExpectedDate);
      final cuando = faltan <= 0
          ? tr('Hoy', 'Today')
          : faltan == 1
              ? tr('Mañana', 'Tomorrow')
              : tr('En $faltan días', 'In $faltan days');
      return (
        title: tr('Próximo período', 'Next period'),
        text: '$cuando · ${shortDayMonthLabel(p.nextPeriodEarliestDate)} – '
            '${shortDayMonthLabel(p.nextPeriodLatestDate)}',
      );
  }
}

/// JSON que lee AuraWidgetProvider.kt: el texto de cada dia desde [today]
/// y uno para despues (si la app no se abre en [homeWidgetDays] dias).
String homeWidgetPayload(PredictionInputs inputs, String today,
    {required bool discreet}) {
  final dias = <String, List<String>>{};
  for (var i = 0; i < homeWidgetDays; i++) {
    final dia = DayKey.addDays(today, i);
    final t = homeWidgetText(inputs, dia, discreet: discreet);
    dias[dia] = [t.title, t.text];
  }
  return jsonEncode({
    'days': dias,
    'fallback': ['Aura', tr('Toca para abrir', 'Tap to open')],
  });
}

/// Mantiene el widget al dia con cada cambio de datos o de ajustes, el
/// resto de la vida de la app (como notificationReconciler).
void startHomeWidgetSync({
  required Stream<PredictionInputs> inputs,
  required Stream<DeviceSettings> settings,
  required AndroidSystem system,
  String Function() today = DayKey.today,
}) {
  PredictionInputs? datos;
  DeviceSettings? ajustes;
  void enviar() {
    if (datos == null || ajustes == null) return;
    unawaited(system.updateHomeWidget(homeWidgetPayload(datos!, today(),
        discreet: ajustes!.widgetDiscreto)));
  }

  inputs.listen((v) {
    datos = v;
    enviar();
  }, onError: (Object _) {});
  settings.listen((v) {
    ajustes = v;
    enviar();
  }, onError: (Object _) {});
}
