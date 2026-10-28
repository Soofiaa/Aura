import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aura/data/device_settings_store.dart';
import 'package:aura/data/home_widget_sync.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/domain/cycle_deriver.dart';

import '../support/fake_device_settings.dart';

CycleSummary _c(String start, int? length, {bool ended = true}) => CycleSummary(
    startDate: start,
    periodLengthDays: 5,
    cycleLengthDays: length,
    periodConfirmedEnded: ended);

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  final ciclos = [
    _c('2026-07-09', 28),
    _c('2026-08-06', 28),
    _c('2026-09-03', 28),
    _c('2026-10-01', null),
  ];
  final inputs = PredictionInputs(cycles: ciclos, typicalPeriodLengthDays: 5);
  String texto(PredictionInputs i, String hoy, {bool discreet = false}) {
    final t = homeWidgetText(i, hoy, discreet: discreet);
    return '${t.title} | ${t.text}';
  }

  test('proximo periodo, en curso, atrasado y discreto', () {
    expect(texto(inputs, '2026-10-20'), startsWith('Próximo período | En 9 días · '));
    expect(texto(inputs, '2026-10-28'), startsWith('Próximo período | Mañana · '));
    expect(texto(inputs, '2026-11-05'), 'Período atrasado | 5 días de atraso');
    expect(texto(inputs, '2026-10-20', discreet: true), 'Aura | Toca para abrir');

    final abierto = PredictionInputs(cycles: [
      ...ciclos.take(3),
      _c('2026-10-01', null, ended: false),
    ], typicalPeriodLengthDays: 5);
    expect(texto(abierto, '2026-10-02'),
        'Día 2 de tu período | Toca para registrar hoy');
  });

  test('sin datos y embarazo (activo o terminado)', () {
    expect(
        texto(const PredictionInputs(cycles: [], typicalPeriodLengthDays: 5),
            '2026-10-28'),
        'Aura | Registra tu primer día');
    expect(
        texto(
            PredictionInputs(
                cycles: ciclos,
                typicalPeriodLengthDays: 5,
                pregnancies: [(start: '2026-10-01', end: null)]),
            '2026-10-28'),
        'Tu embarazo | 3 semanas y 6 días');
    expect(
        texto(
            PredictionInputs(
                cycles: ciclos,
                typicalPeriodLengthDays: 5,
                pregnancies: [(start: '2026-10-01', end: '2026-10-20')]),
            '2026-10-28'),
        startsWith('Predicciones en pausa'));
  });

  test('payload: un texto por dia desde hoy y uno de respaldo', () {
    final json = jsonDecode(
        homeWidgetPayload(inputs, '2026-10-20', discreet: false)) as Map;
    final dias = json['days'] as Map;
    expect(dias.length, homeWidgetDays);
    expect(dias.keys.first, '2026-10-20');
    expect(dias['2026-10-28'][1], startsWith('Mañana'));
    expect(json['fallback'], ['Aura', 'Toca para abrir']);
  });

  test('sync: envia al tener datos y ajustes, y con cada cambio', () async {
    final enviados = <String>[];
    final datos = StreamController<PredictionInputs>();
    final ajustes = FakeDeviceSettingsStore();
    startHomeWidgetSync(
      inputs: datos.stream,
      settings: ajustes.watch(),
      system: _Grabador(enviados),
      today: () => '2026-10-20',
    );
    datos.add(inputs);
    await pumpEventQueue();
    expect(enviados, hasLength(1));
    expect(enviados.single, contains('Próximo período'));

    await ajustes.setWidgetDiscreto(true);
    await pumpEventQueue();
    expect(enviados, hasLength(2));
    expect(enviados.last, isNot(contains('Próximo período')));
    await datos.close();
  });

  test('ajuste guardado y leido', () {
    const s = DeviceSettings(widgetDiscreto: true);
    expect(DeviceSettings.fromJson(s.toJson()), s);
    final viejo = Map.of(s.toJson())..remove('widgetDiscreto');
    expect(DeviceSettings.fromJson(viejo)!.widgetDiscreto, isFalse);
  });
}

class _Grabador extends FakeAndroidSystem {
  _Grabador(this.enviados);
  final List<String> enviados;

  @override
  Future<void> updateHomeWidget(String payload) async => enviados.add(payload);
}
