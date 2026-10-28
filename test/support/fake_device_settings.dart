import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;

import 'package:aura/data/device_settings_store.dart';
import 'package:aura/domain/contraceptive.dart';
import 'package:aura/utils/android_system.dart';

/// Ajustes de este telefono en memoria para tests de widget (la E/S real
/// no avanza dentro del reloj falso de testWidgets). El almacen real se
/// prueba en test/data/device_settings_store_test.dart.
class FakeDeviceSettingsStore extends DeviceSettingsStore {
  FakeDeviceSettingsStore([this._state = const DeviceSettings()])
      : super(supportDirectory: () => throw UnimplementedError());

  DeviceSettings _state;
  final StreamController<DeviceSettings> _cambios =
      StreamController<DeviceSettings>.broadcast();

  /// Si no es null, toda escritura lo lanza sin cambiar nada.
  Object? writeError;

  DeviceSettings get current => _state;

  @override
  Stream<DeviceSettings> watch() => Stream.multi((controller) {
        final sub = _cambios.stream.listen(controller.add);
        read().then(controller.add, onError: controller.addError);
        controller.onCancel = sub.cancel;
      });

  @override
  Future<DeviceSettings> read() async => _state;

  @override
  Future<DeviceSettings> setOcultarEnRecientes(bool value) async =>
      _cambiar(_state.copyWith(ocultarEnRecientes: value));

  @override
  Future<DeviceSettings> setAvisoAtraso(bool value) async =>
      _cambiar(_state.copyWith(avisoAtraso: value));

  @override
  Future<DeviceSettings> setTema(ThemeMode value) async =>
      _cambiar(_state.copyWith(tema: value));

  @override
  Future<DeviceSettings> setRecordatorioDiario(bool value) async =>
      _cambiar(_state.copyWith(recordatorioDiario: value));

  @override
  Future<DeviceSettings> setAnticonceptivo(ContraceptiveReminder? value) async =>
      _cambiar(_state.copyWith(anticonceptivo: () => value));

  @override
  Future<void> delete() async => _cambiar(const DeviceSettings());

  DeviceSettings _cambiar(DeviceSettings nuevo) {
    if (writeError != null) throw writeError!;
    _state = nuevo;
    _cambios.add(nuevo);
    return nuevo;
  }
}

class FakeAndroidSystem implements AndroidSystem {
  final List<bool> screenProtectionCalls = [];
  int openNotificationSettingsCount = 0;

  @override
  Future<void> setScreenProtection(bool enabled) async =>
      screenProtectionCalls.add(enabled);

  @override
  Future<bool> openNotificationSettings() async {
    openNotificationSettingsCount++;
    return true;
  }
}
