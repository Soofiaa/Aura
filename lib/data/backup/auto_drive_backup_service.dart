import 'dart:convert';

import 'package:aura/domain/backup_crypto.dart';
import 'package:aura/utils/day_key.dart';
import 'package:aura/utils/keystore_vault.dart';

import 'backup_service.dart';
import 'drive_api_client.dart';
import 'drive_backup_gateway.dart';
import 'drive_backup_settings_store.dart';

/// Nombre del archivo automatico dentro de la carpeta "Aura". Siempre el
/// mismo: cada respaldo reemplaza al anterior.
const String automaticBackupFileName = 'aura_respaldo_automatico.json';

/// Que salio un respaldo automatico.
enum AutoBackupStatus {
  /// Subido y anotado.
  ok,

  /// Ya hay un respaldo de hoy (sin [force]).
  sinCambios,

  /// La usuaria no tiene el respaldo automatico prendido.
  deshabilitado,

  /// El Keystore de Android ya no tiene la clave (por ejemplo, despues de
  /// borrar la app): hay que definir la contrasena de nuevo.
  claveNoDisponible,

  /// Sin conexion.
  offline,

  /// La sesion de Google expiro o fue revocada.
  unauthorized,

  /// Google rechazo la operacion o fallo algo interno.
  failed,
}

/// Resultado de activar el respaldo automatico.
sealed class EnableDriveResult {
  const EnableDriveResult();
}

class DriveEnabled extends EnableDriveResult {
  const DriveEnabled(this.email, {this.primerRespaldo});

  final String email;

  /// Estado del primer respaldo, si corrio; null si aun no.
  final AutoBackupStatus? primerRespaldo;
}

class EnableDriveCancelled extends EnableDriveResult {
  const EnableDriveCancelled();
}

class EnableDriveFailed extends EnableDriveResult {
  const EnableDriveFailed();
}

class EnableClaveNoDisponible extends EnableDriveResult {
  const EnableClaveNoDisponible();
}

/// Respaldos automaticos a Google Drive (HU-09): una vez al dia, siempre
/// cifrados con la clave que la usuaria definio una vez (sellada por el
/// Keystore), y sin tocar nada si no esta habilitado.
class AutoDriveBackupService {
  AutoDriveBackupService({
    required DriveBackupSettingsStore settings,
    required DriveBackupGateway gateway,
    required KeystoreVault vault,
    required Future<String> Function() buildExportJson,
    required Future<void> Function() recordBackup,
    BackupEncryptFunction encrypt = encryptBackupDocument,
    DateTime Function()? now,
  })  : _settings = settings,
        _gateway = gateway,
        _vault = vault,
        _buildExportJson = buildExportJson,
        _recordBackup = recordBackup,
        _encrypt = encrypt,
        _now = now ?? DateTime.now;

  final DriveBackupSettingsStore _settings;
  final DriveBackupGateway _gateway;
  final KeystoreVault _vault;
  final Future<String> Function() _buildExportJson;
  final Future<void> Function() _recordBackup;
  final BackupEncryptFunction _encrypt;
  final DateTime Function() _now;

  /// Respaldos en fila: uno a la vez, cada llamada con su resultado.
  Future<void> _fila = Future.value();

  /// Respaldar si toca. Con [force] ignora el tope de "una vez al dia".
  Future<AutoBackupStatus> maybeBackup({bool force = false}) {
    final result = _fila.then((_) => _ejecutar(force: force));
    _fila = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Activa el respaldo: pide cuenta de Google y una contrasena, sella la
  /// clave con el Keystore, guarda y hace el primer respaldo. Nunca lanza.
  Future<EnableDriveResult> enable({required String password}) async {
    final signIn = await _gateway.signIn();
    switch (signIn) {
      case DriveSignInCancelled():
        return const EnableDriveCancelled();
      case DriveSignInFailed():
        return const EnableDriveFailed();
      case DriveSignedIn(:final email):
        final String sellada;
        try {
          sellada = await _vault.seal(password);
        } on KeystoreVaultException {
          return const EnableClaveNoDisponible();
        }
        await _settings.guardar(DriveBackupSettings(
          habilitado: true,
          cuenta: email,
          claveSellada: sellada,
        ));
        final primerRespaldo = await maybeBackup(force: true);
        return DriveEnabled(email, primerRespaldo: primerRespaldo);
    }
  }

  /// Apaga el respaldo automatico y olvida la cuenta en la app.
  Future<void> disable() async {
    final actual = await _settings.read();
    if (!actual.habilitado && actual.cuenta.isEmpty) return;
    await _settings.guardar(const DriveBackupSettings());
    await _gateway.signOut();
  }

  /// "Borrar todos los datos".
  Future<void> deleteAllData() => _settings.delete();

  Future<AutoBackupStatus> _ejecutar({required bool force}) async {
    final actual = await _settings.read();
    if (!actual.habilitado) return AutoBackupStatus.deshabilitado;
    final hoy = DayKey.fromDate(_now());
    if (!force && actual.ultimoRespaldo == hoy) {
      return AutoBackupStatus.sinCambios;
    }
    if (actual.claveSellada.isEmpty) {
      return AutoBackupStatus.claveNoDisponible;
    }

    final String clave;
    try {
      clave = await _vault.open(actual.claveSellada);
    } on KeystoreVaultException {
      return AutoBackupStatus.claveNoDisponible;
    }

    final String contenido;
    try {
      final json = await _buildExportJson();
      // La referencia al cifrador sale como variable local: el closure que
      // viaja al isolate no puede capturar "this".
      final encrypt = _encrypt;
      contenido = await runInIsolate(
          () => encrypt(json, clave, Argon2idParams.production));
    } catch (_) {
      return AutoBackupStatus.failed;
    }

    try {
      await _gateway.uploadBackup(
        fileName: automaticBackupFileName,
        bytes: utf8.encode(contenido),
      );
    } on DriveApiException catch (e) {
      await _guardarFallo(actual, e.cause);
      return switch (e.cause) {
        DriveApiFailure.offline => AutoBackupStatus.offline,
        DriveApiFailure.unauthorized => AutoBackupStatus.unauthorized,
        DriveApiFailure.failed => AutoBackupStatus.failed,
      };
    }

    await _settings.guardar(DriveBackupSettings(
      habilitado: true,
      cuenta: actual.cuenta,
      claveSellada: actual.claveSellada,
      ultimoRespaldo: hoy,
    ));
    await _recordBackup();
    return AutoBackupStatus.ok;
  }

  Future<void> _guardarFallo(
      DriveBackupSettings actual, DriveApiFailure fallo) async {
    try {
      await _settings.guardar(DriveBackupSettings(
        habilitado: actual.habilitado,
        cuenta: actual.cuenta,
        claveSellada: actual.claveSellada,
        ultimoRespaldo: actual.ultimoRespaldo,
        ultimoFallo: fallo,
      ));
    } catch (_) {
      // El proximo intento reintenta de todos modos.
    }
  }
}
