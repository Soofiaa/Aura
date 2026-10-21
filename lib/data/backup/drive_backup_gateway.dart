import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'drive_api_client.dart';

/// Unico alcance que Aura pide a Drive: la app solo ve los archivos que
/// ella crea (carpeta "Aura"); no lee ni borra nada mas de la cuenta.
const String driveScope = 'https://www.googleapis.com/auth/drive.file';

/// Resultado de intentar iniciar sesion con Google.
sealed class DriveSignInResult {
  const DriveSignInResult();
}

class DriveSignedIn extends DriveSignInResult {
  const DriveSignedIn(this.email);

  final String email;

  @override
  bool operator ==(Object other) =>
      other is DriveSignedIn && other.email == email;

  @override
  int get hashCode => email.hashCode;
}

class DriveSignInCancelled extends DriveSignInResult {
  const DriveSignInCancelled();
}

class DriveSignInFailed extends DriveSignInResult {
  const DriveSignInFailed();
}

/// Lo que el servicio de respaldo automatico (HU-09) necesita de Drive.
abstract class DriveBackupGateway {
  /// La sesion que el telefono ya tenia, si la hay; sin pedir nada a la
  /// usuaria y sin mostrar UI.
  Future<String?> restoreSession();

  /// Pide elegir cuenta y autorizar Drive. [DriveSignedIn] con el correo,
  /// cancelado o fallido; nunca lanza.
  Future<DriveSignInResult> signIn();

  /// Cierra la sesion de Google de la app.
  Future<void> signOut();

  /// Sube el respaldo [bytes] como [fileName] dentro de la carpeta Aura,
  /// reemplazando el archivo anterior. Lanza [DriveApiException] si falla.
  Future<void> uploadBackup({
    required String fileName,
    required List<int> bytes,
  });
}

/// Implementacion de la app: google_sign_in 7 (sesion del telefono) +
/// [DriveApiClient] (REST con el token de acceso).
class PluginDriveBackupGateway implements DriveBackupGateway {
  PluginDriveBackupGateway({required String clientId, http.Client? client})
      : _clientId = clientId {
    _api = DriveApiClient(accessToken: _silentToken, client: client);
  }

  final String _clientId;
  late final DriveApiClient _api;
  GoogleSignInAccount? _cuenta;

  /// initialize() solo puede llamarse una vez en todo el proceso
  /// (singleton de GoogleSignIn), asi que vive en la clase.
  static bool _inicializado = false;

  Future<void> _asegurarInicializado() async {
    if (_inicializado) return;
    await GoogleSignIn.instance.initialize(serverClientId: _clientId);
    _inicializado = true;
  }

  /// Token sin mostrar UI: si no hay sesion o falta el alcance, [unauthorized].
  Future<String> _silentToken() async {
    final instance = GoogleSignIn.instance;
    final account =
        _cuenta ?? await instance.attemptLightweightAuthentication();
    if (account == null) {
      throw DriveApiException(DriveApiFailure.unauthorized, 'sin sesion');
    }
    _cuenta = account;
    final authorization =
        await account.authorizationClient.authorizationForScopes(
      const [driveScope],
    );
    if (authorization == null) {
      throw DriveApiException(DriveApiFailure.unauthorized, 'sin alcance');
    }
    return authorization.accessToken;
  }

  @override
  Future<String?> restoreSession() async {
    try {
      await _asegurarInicializado();
      final account =
          await GoogleSignIn.instance.attemptLightweightAuthentication();
      if (account == null) return null;
      _cuenta = account;
      return account.email;
    } catch (_) {
      // Configuracion del client id o error del SDK: sin sesion.
      return null;
    }
  }

  @override
  Future<DriveSignInResult> signIn() async {
    try {
      await _asegurarInicializado();
      final account = await GoogleSignIn.instance
          .authenticate(scopeHint: const [driveScope]);
      // authorizeScopes lanza GoogleSignInException si la usuaria niega el
      // alcance; authorizationForScopes devuelve null sin pedir nada.
      await account.authorizationClient
          .authorizationForScopes(const [driveScope]) ??
          await account.authorizationClient
              .authorizeScopes(const [driveScope]);
      _cuenta = account;
      return DriveSignedIn(account.email);
    } on GoogleSignInException catch (e) {
      return switch (e.code) {
        GoogleSignInExceptionCode.canceled ||
        GoogleSignInExceptionCode.interrupted =>
          const DriveSignInCancelled(),
        _ => const DriveSignInFailed(),
      };
    } catch (_) {
      return const DriveSignInFailed();
    }
  }

  @override
  Future<void> signOut() async {
    _cuenta = null;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Sin sesion que cerrar: el resultado es el mismo.
    }
  }

  @override
  Future<void> uploadBackup({
    required String fileName,
    required List<int> bytes,
  }) async {
    final folderId = await _api.ensureFolder();
    await _api.uploadOrReplace(
      folderId: folderId,
      fileName: fileName,
      bytes: bytes,
    );
  }
}
