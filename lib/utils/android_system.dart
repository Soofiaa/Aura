import 'package:flutter/services.dart';

/// Lo poco que Aura le pide a Android fuera de los plugins (ver
/// MainActivity.kt): ocultar la app en Recientes y abrir los ajustes de
/// notificaciones del sistema.
abstract class AndroidSystem {
  /// FLAG_SECURE: con [enabled], la miniatura en Recientes sale en blanco y
  /// no se pueden hacer capturas ni grabar la pantalla. MainActivity lo
  /// activa al crearse; la app lo apaga si la usuaria lo eligio.
  Future<void> setScreenProtection(bool enabled);

  /// Abre los ajustes de notificaciones de Aura en Android. false si no se
  /// pudo.
  Future<bool> openNotificationSettings();

  /// Guarda los textos del widget de la pantalla de inicio (ver
  /// home_widget_sync.dart) y lo redibuja.
  Future<void> updateHomeWidget(String payload);
}

class MethodChannelAndroidSystem implements AndroidSystem {
  const MethodChannelAndroidSystem();

  static const _channel = MethodChannel('com.soofiaa.aura/system');

  @override
  Future<void> setScreenProtection(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setScreenProtection', enabled);
    } on MissingPluginException {
      // Fuera de Android (tests de integracion, escritorio): nada que hacer.
    } on PlatformException {
      // Sin efecto: la proteccion queda como estaba.
    }
  }

  @override
  Future<bool> openNotificationSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openNotificationSettings') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> updateHomeWidget(String payload) async {
    try {
      await _channel.invokeMethod<void>('updateHomeWidget', payload);
    } on MissingPluginException {
      // Fuera de Android: no hay widget.
    } on PlatformException {
      // El widget queda con los textos anteriores.
    }
  }
}

AndroidSystem? _androidSystemInstance;

AndroidSystem get androidSystem =>
    _androidSystemInstance ??= const MethodChannelAndroidSystem();

/// Solo para tests.
set androidSystem(AndroidSystem value) => _androidSystemInstance = value;
