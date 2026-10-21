import 'package:flutter/foundation.dart';

/// Client ID de OAuth de Google para el respaldo en Google Drive (HU-09).
///
/// Nunca vive en el repositorio: se pasa en tiempo de compilacion con
/// `--dart-define` (o `--dart-define-from-file=secrets.json`, que esta en
/// .gitignore; ver docs/DRIVE_SETUP.md). Google ata cada client ID al
/// nombre del paquete y al SHA-1 de la keystore, por eso hay dos: uno
/// para depuracion (`com.soofiaa.aura.debug`) y otro para publicar.
///
/// Vacio = esta compilacion no tiene el respaldo en Drive configurado;
/// Ajustes lo muestra como "configuracion pendiente" y no intenta entrar
/// a la cuenta.
String driveClientId() => kReleaseMode
    ? const String.fromEnvironment('DRIVE_CLIENT_ID_RELEASE')
    : const String.fromEnvironment('DRIVE_CLIENT_ID_DEBUG');
