import 'package:flutter/services.dart';

/// Guarda y recupera un texto pequeno (la clave que protege los respaldos
/// automaticos de Drive, HU-09) cifrandolo con el Keystore de Android: la
/// app nunca escribe la clave en claro ni en sus archivos.
abstract class KeystoreVault {
  /// Devuelve el texto sellado, que puede guardarse en disco.
  Future<String> seal(String plaintext);

  /// Recupera el texto sellado con [seal]. Lanza [KeystoreVaultException]
  /// si el Keystore falla (por ejemplo, despues de borrar la app).
  Future<String> open(String blob);
}

/// El Keystore no pudo sellar o abrir. No incluye el texto en ningun campo.
class KeystoreVaultException implements Exception {
  const KeystoreVaultException();

  @override
  String toString() => 'KeystoreVaultException';
}

class MethodChannelKeystoreVault implements KeystoreVault {
  const MethodChannelKeystoreVault();

  static const _channel = MethodChannel('com.soofiaa.aura/system');

  @override
  Future<String> seal(String plaintext) => _invoke('keystoreEncrypt', plaintext);

  @override
  Future<String> open(String blob) => _invoke('keystoreDecrypt', blob);

  Future<String> _invoke(String method, String argument) async {
    try {
      final result = await _channel.invokeMethod<String>(method, argument);
      if (result == null) throw const KeystoreVaultException();
      return result;
    } on MissingPluginException {
      // Fuera de Android (tests de integracion, escritorio).
      throw const KeystoreVaultException();
    } on PlatformException {
      throw const KeystoreVaultException();
    }
  }
}

KeystoreVault? _keystoreVaultInstance;

/// Instancia unica para la app.
KeystoreVault get keystoreVault =>
    _keystoreVaultInstance ??= const MethodChannelKeystoreVault();

/// Solo para tests.
set keystoreVault(KeystoreVault value) => _keystoreVaultInstance = value;
