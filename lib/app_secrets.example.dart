// Plantilla del client ID de OAuth para el respaldo en Google Drive
// (HU-09). Copia este archivo como lib/app_secrets.dart y pega ahi tus
// client IDs.
//
//   cp lib/app_secrets.example.dart lib/app_secrets.dart
//
// lib/app_secrets.dart esta en .gitignore: NUNCA se commitea ni se sube a
// ningun repositorio. Los pasos para crear los client IDs estan en
// docs/DRIVE_SETUP.md.
import 'package:flutter/foundation.dart';

class AppSecrets {
  /// Client ID de tipo "Android" del paquete `com.soofiaa.aura.debug`,
  /// con el SHA-1 del keystore de depuracion.
  static const String driveClientIdDebug =
      'PEGA_AQUI_EL_CLIENT_ID_DE_DEPURACION.apps.googleusercontent.com';

  /// Client ID de tipo "Android" del paquete `com.soofiaa.aura` (publica en
  /// Play), con el SHA-1 de la keystore de publicacion.
  static const String driveClientIdRelease =
      'PEGA_AQUI_EL_CLIENT_ID_DE_PUBLICACION.apps.googleusercontent.com';

  /// El que corresponde al modo de compilacion.
  static String get driveClientId =>
      kReleaseMode ? driveClientIdRelease : driveClientIdDebug;
}
