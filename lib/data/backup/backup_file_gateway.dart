import 'dart:io';
import 'dart:typed_data';

/// Puente entre el respaldo y el sistema de archivos del telefono: la
/// hoja de compartir, el "Guardar como" y el selector de archivos. Las
/// pantallas dependen solo de esta interfaz (nunca de share_plus ni de
/// file_picker) para que los tests usen un falso sin canales de
/// plataforma. La implementacion real esta en
/// plugin_backup_file_gateway.dart.
abstract class BackupFileGateway {
  /// Abre la hoja de compartir del sistema con [file]. Devuelve false si
  /// la usuaria la cierra sin elegir destino, y true si eligio uno o si
  /// la plataforma no puede informar que paso. No borra el archivo al
  /// volver: la app de destino puede seguir leyendolo (ver
  /// BackupService.cleanTemporaryFiles).
  Future<bool> shareFile(File file);

  /// Abre el "Guardar como" del sistema y escribe [bytes] donde la
  /// usuaria elija. Devuelve false si cancela; lanza si la escritura
  /// falla.
  Future<bool> saveToDevice({
    required String fileName,
    required Uint8List bytes,
  });

  /// Abre el selector de archivos y devuelve la ruta local del archivo
  /// elegido, o null si la usuaria cancela. En Android es una copia en
  /// cache/file_picker/ que BackupService.readBackupFile borra al leerla.
  Future<String?> pickBackupFile();
}

BackupFileGateway? _backupFileGatewayInstance;

/// Instancia de la app, asignada en main.dart con la implementacion real
/// (los tests la inyectan en SettingsScreen o reemplazan esta).
BackupFileGateway get backupFileGateway =>
    _backupFileGatewayInstance ??
    (throw StateError('backupFileGateway no fue asignado en main()'));

set backupFileGateway(BackupFileGateway value) =>
    _backupFileGatewayInstance = value;
