/// Client ID de OAuth de Google para el respaldo en Google Drive (HU-09).
///
/// Nunca vive en el repositorio: se pasa en tiempo de compilacion con
/// `--dart-define` (o `--dart-define-from-file=secrets.json`, que esta en
/// .gitignore; ver docs/DRIVE_SETUP.md).
///
/// En Android, google_sign_in 7 ignora `clientId` y exige el
/// `serverClientId`: el client ID de tipo "Aplicacion web" del proyecto,
/// el mismo para depuracion y publicacion. Los client IDs de tipo Android
/// (paquete + SHA-1) solo tienen que existir en el proyecto: Google los
/// usa para reconocer la app que pide el acceso.
///
/// Vacio = esta compilacion no tiene el respaldo en Drive configurado;
/// Ajustes lo muestra como "configuracion pendiente" y no intenta entrar
/// a la cuenta.
String driveClientId() => const String.fromEnvironment('DRIVE_WEB_CLIENT_ID');
