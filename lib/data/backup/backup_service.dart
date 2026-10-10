import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/backup_codec.dart';
import '../../domain/backup_crypto.dart';
import '../../utils/app_version.dart';
import '../../utils/day_key.dart';
import '../repositories/cycle_repository.dart';
import 'backup_reminder_store.dart';
import 'pre_migration_copy.dart' as copy;

/// Lo que la confirmacion de importar necesita mostrar: cuantos dias hay
/// hoy en el telefono y cuantos trae el respaldo. "Dias" son todos los
/// que tienen registro (tambien los de "no hubo sangrado"); los de
/// periodo son los que el calendario marca.
class ImportPreview {
  const ImportPreview({
    required this.data,
    required this.currentDayCount,
    required this.currentPeriodDayCount,
  });

  final BackupData data;
  final int currentDayCount;
  final int currentPeriodDayCount;

  int get incomingDayCount => data.days.length;

  int get incomingPeriodDayCount =>
      data.days.where((d) => d.isPeriodDay).length;

  /// Dias que se pierden al reemplazar (0 si el respaldo trae igual o
  /// mas dias). Es una diferencia de cantidades, no de fechas.
  int get daysLost =>
      currentDayCount > incomingDayCount ? currentDayCount - incomingDayCount : 0;
}

/// Por que no se pudo crear un respaldo (o la copia previa a importar).
enum BackupWriteCause {
  /// Un dia guardado tiene una fecha fuera del rango que el formato
  /// acepta (ver [BackupWriteException.outOfRangeDate]).
  dateOutOfRange,

  /// Los datos actuales no pasan la validacion por otro motivo.
  invalidData,

  /// No se pudo escribir el archivo.
  fileSystem,
}

/// Error al crear un respaldo o la copia previa a importar. La UI arma
/// el mensaje con [cause] y [outOfRangeDate]; [detail] es solo para
/// depuracion y nunca se muestra a la usuaria.
class BackupWriteException implements Exception {
  BackupWriteException(this.cause, this.detail, {this.outOfRangeDate});

  final BackupWriteCause cause;

  /// Fecha 'yyyy-MM-dd' fuera de rango, solo con
  /// [BackupWriteCause.dateOutOfRange].
  final String? outOfRangeDate;

  final String detail;

  @override
  String toString() => 'BackupWriteException($cause): $detail';
}

/// Pasos de "Borrar todos los datos" (ver [BackupService.deleteAllData]).
enum BackupDeleteStep { database, backups, temporaryFiles, backupReminder }

/// Fallo uno o mas pasos de "Borrar todos los datos"; los demas se
/// intentaron igual.
class BackupDeleteException implements Exception {
  BackupDeleteException(this.failedSteps, this.errors);

  final List<BackupDeleteStep> failedSteps;
  final List<Object> errors;

  @override
  String toString() => 'BackupDeleteException($failedSteps): $errors';
}

/// No hay copia previa valida para deshacer la ultima importacion.
class BackupUndoUnavailableException implements Exception {
  BackupUndoUnavailableException(this.detail);
  final String detail;

  @override
  String toString() => 'BackupUndoUnavailableException: $detail';
}

/// Ejecuta un trabajo pesado (derivar la clave, cifrar, descifrar) fuera
/// del hilo de la interfaz. En la app es [runInIsolate]; los tests usan
/// [runInSameIsolate]. Lo que el trabajo captura tiene que poder viajar a
/// otro isolate: textos, bytes, parametros y funciones de nivel superior,
/// nunca el servicio ni el repositorio.
typedef BackupTaskRunner = Future<R> Function<R>(FutureOr<R> Function() task);

/// [BackupTaskRunner] de la app: Isolate.run.
Future<R> runInIsolate<R>(FutureOr<R> Function() task) => Isolate.run(task);

/// [BackupTaskRunner] para tests: corre en el mismo isolate.
Future<R> runInSameIsolate<R>(FutureOr<R> Function() task) async => task();

/// Cifra el documento de `formatVersion` 1. Tiene que ser una funcion de
/// nivel superior o estatica: viaja al isolate. Inyectable para probar
/// que la verificacion de HU6b-10 detecta un cifrador defectuoso.
typedef BackupEncryptFunction = Future<String> Function(
    String documentV1Json, String password, Argon2idParams params);

/// [BackupEncryptFunction] de la app: [encryptBackup] (sal y nonce de
/// Random.secure()).
Future<String> encryptBackupDocument(
        String documentV1Json, String password, Argon2idParams params) =>
    encryptBackup(documentV1Json, password, params: params);

/// Por que no se pudo crear un respaldo cifrado.
enum BackupEncryptionFailure {
  /// El cifrado mismo fallo (no se llego a escribir el archivo).
  encryptionFailed,

  /// El archivo escrito no descifra exactamente al documento original
  /// (HU6b-10).
  verificationFailed,

  /// El archivo escrito supera el tope de tamano de un respaldo.
  tooLarge,
}

/// Error al crear un respaldo cifrado. Nunca incluye la contrasena: ni
/// en [detail] ni en [toString]. [message] es el texto para la usuaria.
class BackupEncryptionException implements Exception {
  BackupEncryptionException(this.cause, this.detail);

  final BackupEncryptionFailure cause;

  /// Solo para depuracion; nunca se muestra.
  final String detail;

  String get message => switch (cause) {
        BackupEncryptionFailure.encryptionFailed =>
          'No se pudo crear el respaldo protegido. No se guardó ningún '
              'archivo.',
        BackupEncryptionFailure.verificationFailed =>
          'No se pudo crear el respaldo protegido: la comprobación del '
              'archivo falló. No se guardó ningún archivo.',
        BackupEncryptionFailure.tooLarge =>
          'No se pudo crear el respaldo protegido: el archivo supera el '
              'tamaño máximo. No se guardó ningún archivo.',
      };

  @override
  String toString() => 'BackupEncryptionException($cause): $detail';
}

/// Resultado de intentar abrir un respaldo cifrado con una contrasena
/// ([BackupService.unlockBackup]). Ninguno escribe nada.
sealed class BackupUnlockResult {
  const BackupUnlockResult();
}

/// Contrasena correcta y documento valido: [data] sigue el mismo camino
/// que un respaldo sin cifrar (previewImport e importBackup).
class BackupUnlocked extends BackupUnlockResult {
  const BackupUnlocked(this.data);
  final BackupData data;

  @override
  String toString() => 'BackupUnlocked(${data.days.length} dias)';
}

/// Contrasena incorrecta o archivo alterado (HU6b-8: no se distinguen).
/// Se puede reintentar con el mismo [BackupNeedsPassword].
class BackupUnlockWrongPasswordOrDamaged extends BackupUnlockResult {
  const BackupUnlockWrongPasswordOrDamaged();

  String get message => wrongPasswordOrDamagedMessage;

  @override
  String toString() => 'BackupUnlockWrongPasswordOrDamaged';
}

/// Se descifro, pero el documento no es un respaldo importable (por
/// ejemplo, de un schema posterior). [error] es el mismo que daria un
/// respaldo sin cifrar con ese contenido.
class BackupUnlockInvalid extends BackupUnlockResult {
  const BackupUnlockInvalid(this.error, this.detail);
  final BackupError error;

  /// Solo para depuracion; nunca se muestra.
  final String detail;

  @override
  String toString() => 'BackupUnlockInvalid($error: $detail)';
}

// Trabajos que viajan al isolate. Son funciones de nivel superior que
// arman el cierre: asi el cierre solo captura sus argumentos.

Future<String> Function() _encryptJob(BackupEncryptFunction encrypt,
        String documentV1Json, String password, Argon2idParams params) =>
    () => encrypt(documentV1Json, password, params);

/// null si no descifra (contrasena, sal, parametros o datos alterados).
Future<Uint8List?> Function() _decryptJob(Uint8List fileBytes, String password) =>
    () async {
      try {
        return await decryptBackup(fileBytes, password);
      } on BackupCryptoException {
        return null;
      }
    };

Future<BackupUnlockResult> Function() _unlockJob(
        BackupNeedsPassword pending, String password) =>
    () async {
      final BackupParseResult result;
      try {
        result = await decodeEncryptedBackup(pending, password);
      } on BackupCryptoException {
        return const BackupUnlockWrongPasswordOrDamaged();
      }
      return switch (result) {
        BackupParseSuccess(:final data) => BackupUnlocked(data),
        BackupParseFailure(:final error, :final detail) =>
          BackupUnlockInvalid(error, detail),
        // decodeEncryptedBackup ya rechaza un cifrado dentro de otro.
        BackupNeedsPassword() =>
          const BackupUnlockInvalid(BackupError.damaged, 'cifrado anidado'),
      };
    };

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Archivos del respaldo (HU-06): exportar, importar con copia previa,
/// deshacer la importacion y limpiar temporales. Los datos pasan siempre
/// por [CycleRepository]; esta clase solo agrega el manejo de archivos.
class BackupService {
  BackupService(
    this._repository, {
    required Future<Directory> Function() supportDirectory,
    required Future<Directory> Function() temporaryDirectory,
    DateTime Function()? clock,
    BackupTaskRunner runTask = runInIsolate,
    Argon2idParams encryptionParams = Argon2idParams.production,
    BackupEncryptFunction encrypt = encryptBackupDocument,
    int maxFileBytes = maxBackupSizeBytes,
    BackupReminderStore? reminderStore,
  })  : _supportDirectory = supportDirectory,
        _temporaryDirectory = temporaryDirectory,
        _clock = clock ?? DateTime.now,
        _reminderStore = reminderStore ??
            BackupReminderStore(
                supportDirectory: supportDirectory, clock: clock),
        _runTask = runTask,
        _encryptionParams = encryptionParams,
        _encrypt = encrypt,
        _maxFileBytes = maxFileBytes;

  final CycleRepository _repository;
  final Future<Directory> Function() _supportDirectory;
  final Future<Directory> Function() _temporaryDirectory;
  final DateTime Function() _clock;

  /// Recordatorio de respaldo: "Borrar todos los datos" tambien lo borra.
  final BackupReminderStore _reminderStore;

  // Cifrado (HU-06b). La contrasena nunca se guarda en un campo: vive
  // solo durante la llamada que la recibe.
  final BackupTaskRunner _runTask;
  final Argon2idParams _encryptionParams;
  final BackupEncryptFunction _encrypt;

  /// Tope de tamano de un archivo de respaldo, cifrado o no, al leerlo y
  /// al verificar uno cifrado recien escrito. Inyectable solo para tests.
  final int _maxFileBytes;

  /// Copia automatica de los datos anteriores a la ultima importacion,
  /// dentro del almacenamiento privado de la app. Hay una sola: cada
  /// importacion la reemplaza, deshacer no. En la misma carpeta queda la
  /// copia previa a la migracion v4 (ver pre_migration_copy.dart).
  static const String backupsDirName = copy.backupsDirName;
  static const String preImportFileName = 'antes_de_importar.json';

  /// Carpeta propia dentro del directorio temporal para el archivo que
  /// se comparte.
  static const String exportDirName = 'aura_respaldo';

  /// Carpeta donde file_picker copia el archivo elegido para importar
  /// (`cache/file_picker/<instante>/<nombre>`), antes de que Dart pueda
  /// revisar su tamano.
  static const String pickerDirName = 'file_picker';

  /// Carpetas del directorio temporal que pueden contener una copia de un
  /// respaldo: la nuestra, la que share_plus usa para pasarle el archivo
  /// a la app de destino (ver su FileProvider) y la de file_picker.
  static const List<String> temporaryDirNames = [
    exportDirName,
    'share_plus',
    pickerDirName,
  ];

  /// Respaldo de los datos actuales como JSON. Se valida a si mismo antes
  /// de devolverse: nunca se entrega un archivo que esta misma version no
  /// podria importar.
  Future<String> buildExportJson() async {
    final data = await _repository.readBackupData(
      appVersion: appVersionName,
      exportedAt: formatExportedAt(_clock()),
    );
    final json = encodeBackup(data);
    final check = decodeBackup(utf8.encode(json));
    if (check is BackupParseFailure) {
      final date = check.outOfRangeDate;
      throw BackupWriteException(
        date != null
            ? BackupWriteCause.dateOutOfRange
            : BackupWriteCause.invalidData,
        'el respaldo no pasa su validacion: $check',
        outOfRangeDate: date,
      );
    }
    return json;
  }

  /// Escribe el respaldo en el directorio temporal para compartirlo o
  /// guardarlo. Antes borra los temporales de exportaciones anteriores;
  /// el archivo nuevo NO se borra al volver de la hoja de compartir,
  /// porque la app de destino puede seguir leyendolo.
  ///
  /// Con [password] (HU-06b) el archivo va cifrado, se llama
  /// `aura_respaldo_protegido_<fecha>.json` y antes de devolverlo se
  /// verifica (HU6b-10, ver [_verifyEncryptedExport]); si la verificacion
  /// falla se borra y se lanza [BackupEncryptionException]. Sin
  /// [password], el archivo y su nombre son los de siempre.
  Future<File> writeExportFile({String? password}) async {
    final json = await buildExportJson();
    if (password != null) return _writeEncryptedExportFile(json, password);
    try {
      await cleanTemporaryFiles();
      final dir = Directory(
          p.join((await _temporaryDirectory()).path, exportDirName));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, exportFileName()));
      await file.writeAsString(json, flush: true);
      return file;
    } on FileSystemException catch (e) {
      throw BackupWriteException(
          BackupWriteCause.fileSystem, 'no se pudo escribir el respaldo: $e');
    }
  }

  /// Nombre sugerido para el archivo exportado. [protected]: respaldo
  /// cifrado (HU6b-7), solo como ayuda visual; el cifrado se detecta por
  /// el contenido.
  String exportFileName({bool protected = false}) => protected
      ? 'aura_respaldo_protegido_${DayKey.fromDate(_clock())}.json'
      : 'aura_respaldo_${DayKey.fromDate(_clock())}.json';

  Future<File> _writeEncryptedExportFile(String json, String password) async {
    final String encrypted;
    try {
      encrypted = await _runTask(
          _encryptJob(_encrypt, json, password, _encryptionParams));
    } catch (e) {
      throw BackupEncryptionException(BackupEncryptionFailure.encryptionFailed,
          'no se pudo cifrar: ${e.runtimeType}');
    }
    final File file;
    try {
      await cleanTemporaryFiles();
      final dir = Directory(
          p.join((await _temporaryDirectory()).path, exportDirName));
      await dir.create(recursive: true);
      file = File(p.join(dir.path, exportFileName(protected: true)));
      await file.writeAsString(encrypted, flush: true);
    } on FileSystemException catch (e) {
      throw BackupWriteException(
          BackupWriteCause.fileSystem, 'no se pudo escribir el respaldo: $e');
    }
    try {
      await _verifyEncryptedExport(file, json, password);
    } catch (e) {
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // Queda en la carpeta temporal: se borra al abrir la app o en la
        // proxima exportacion (cleanTemporaryFiles).
      }
      if (e is BackupEncryptionException) rethrow;
      throw BackupEncryptionException(
          BackupEncryptionFailure.verificationFailed,
          'error al verificar: ${e.runtimeType}');
    }
    return file;
  }

  /// HU6b-10: relee el archivo final desde el disco, comprueba el tope de
  /// tamano y lo pasa por la misma funcion publica de descifrado que usa
  /// la importacion ([decryptBackup]: lee el encabezado, vuelve a derivar
  /// la clave y descifra). El resultado tiene que ser exactamente
  /// [json]. Asi se detecta tambien un error al escribir la sal o los
  /// parametros, a costa de una derivacion extra (~0,2 s, CP0).
  Future<void> _verifyEncryptedExport(
      File file, String json, String password) async {
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException catch (e) {
      throw BackupEncryptionException(
          BackupEncryptionFailure.verificationFailed, 'no se pudo releer: $e');
    }
    if (bytes.length > _maxFileBytes) {
      throw BackupEncryptionException(
          BackupEncryptionFailure.tooLarge, '${bytes.length} bytes');
    }
    final clear = await _runTask(_decryptJob(bytes, password));
    if (clear == null || !_sameBytes(clear, utf8.encode(json))) {
      throw BackupEncryptionException(
          BackupEncryptionFailure.verificationFailed,
          'el archivo no descifra al documento original');
    }
  }

  /// Bytes de un archivo ya exportado (por ejemplo, el cifrado y verificado
  /// por [writeExportFile]) para "Guardar en el telefono".
  Future<Uint8List> readExportFile(File file) => file.readAsBytes();

  /// Borra un archivo exportado. No lanza: si falla, queda en la carpeta
  /// temporal y se borra al abrir la app o en la proxima exportacion.
  Future<void> deleteExportFile(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Ver cleanTemporaryFiles.
    }
  }

  /// Borra las copias temporales del respaldo. Se llama al abrir la app,
  /// antes de cada exportacion y al borrar todos los datos.
  Future<void> cleanTemporaryFiles() async {
    final temp = await _temporaryDirectory();
    for (final name in temporaryDirNames) {
      final dir = Directory(p.join(temp.path, name));
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  }

  /// Lee y valida el archivo elegido para importar. Revisa el tamano
  /// antes de cargarlo en memoria, y si es la copia que file_picker dejo
  /// en la cache la borra apenas termina, sea valido o no. No lanza. Un
  /// respaldo cifrado vuelve como [BackupNeedsPassword] (ya parseado: no
  /// hace falta volver a elegir el archivo); se abre con [unlockBackup].
  /// El tope de tamano es el mismo con o sin cifrado.
  Future<BackupParseResult> readBackupFile(String path) async {
    final file = File(path);
    try {
      final length = await file.length();
      if (length > _maxFileBytes) {
        return BackupParseFailure(BackupError.tooLarge, '$length bytes');
      }
      return decodeBackup(await file.readAsBytes());
    } on FileSystemException catch (e) {
      return BackupParseFailure(BackupError.unreadable, '$e');
    } finally {
      await _deletePickerCopy(file);
    }
  }

  /// Solo borra dentro de cache/file_picker/: nunca un archivo de la
  /// usuaria fuera de la cache de la app.
  Future<void> _deletePickerCopy(File file) async {
    try {
      final pickerDir =
          p.join((await _temporaryDirectory()).path, pickerDirName);
      if (!p.isWithin(pickerDir, file.path)) return;
      if (await file.exists()) await file.delete();
      final parent = file.parent;
      if (p.isWithin(pickerDir, parent.path) &&
          (await parent.list().isEmpty)) {
        await parent.delete();
      }
    } on FileSystemException {
      // Se reintenta al abrir la app (cleanTemporaryFiles).
    }
  }

  /// Intenta abrir un respaldo cifrado con [password], fuera del hilo de
  /// la interfaz. No escribe nada: ni la copia previa a importar ni la
  /// base. Con [BackupUnlocked], los datos siguen el mismo camino que un
  /// respaldo sin cifrar ([previewImport] e [importBackup]). Con
  /// [BackupUnlockWrongPasswordOrDamaged] se puede reintentar con el mismo
  /// [pending]. No lanza: un error inesperado (por ejemplo, del isolate)
  /// vuelve como [BackupUnlockInvalid] con solo el tipo del error, nunca
  /// su mensaje (podria contener datos).
  Future<BackupUnlockResult> unlockBackup(
      BackupNeedsPassword pending, String password) async {
    try {
      return await _runTask(_unlockJob(pending, password));
    } on BackupCryptoException {
      // Ya se trata dentro del trabajo; por si acaso.
      return const BackupUnlockWrongPasswordOrDamaged();
    } catch (e) {
      return BackupUnlockInvalid(
          BackupError.damaged, 'error inesperado: ${e.runtimeType}');
    }
  }

  Future<ImportPreview> previewImport(BackupData data) async {
    return ImportPreview(
      data: data,
      currentDayCount: await _repository.countDays(),
      currentPeriodDayCount: (await _repository.getPeriodDayDates()).length,
    );
  }

  /// Importa [data] reemplazando todo. Primero guarda la copia previa de
  /// los datos actuales; si esa copia no se puede escribir, no se importa
  /// nada. Un respaldo de un schema anterior se convierte antes (regla
  /// D-2, con "hoy" = el dia de la importacion). El reemplazo es una unica
  /// transaccion.
  Future<void> importBackup(BackupData data) async {
    final current = _upgrade(data);
    await _writePreImportCopy();
    await _repository.replaceAllWithBackup(current);
  }

  BackupData _upgrade(BackupData data) =>
      upgradeBackupData(data, today: DayKey.fromDate(_clock()));

  Future<bool> hasPreImportCopy() async => (await _preImportFile()).exists();

  /// Vuelve a los datos de antes de la ultima importacion. No reescribe
  /// la copia previa: deshacer dos veces deja los mismos datos.
  Future<void> undoLastImport() async {
    final file = await _preImportFile();
    if (!await file.exists()) {
      throw BackupUndoUnavailableException('no hay copia previa');
    }
    final result = decodeBackup(await file.readAsBytes());
    switch (result) {
      case BackupParseSuccess(:final data):
        // La copia la escribe esta version (schema actual); una copia v3
        // de antes de actualizar se convierte igual que un respaldo.
        await _repository.replaceAllWithBackup(_upgrade(data));
      case BackupParseFailure():
        throw BackupUndoUnavailableException('copia previa invalida: $result');
      case BackupNeedsPassword():
        // La copia previa la escribe la app y nunca va cifrada.
        throw BackupUndoUnavailableException('copia previa cifrada');
    }
  }

  /// Borra la copia del archivo de la base tomada antes de migrar a v4.
  /// Se llama tras un "Guardar en el telefono" exitoso: desde ahi la
  /// usuaria tiene una copia completa y mas reciente fuera de la app. NO
  /// tras compartir, porque share_plus puede informar `unavailable` aunque
  /// no se haya enviado nada. Borra tambien un .tmp huerfano.
  Future<void> deletePreMigrationCopy() async {
    for (final file in await _preMigrationFiles()) {
      if (await file.exists()) await file.delete();
    }
  }

  /// Borra la copia previa a la migracion si tiene mas de
  /// [copy.preMigrationCopyMaxAge] segun su fecha de modificacion (la del
  /// VACUUM INTO). Se llama al abrir la app.
  Future<void> deleteExpiredPreMigrationCopy() async {
    final files = await _preMigrationFiles();
    final target = files.first;
    if (!await target.exists()) return;
    final age = _clock().difference(await target.lastModified());
    if (age > copy.preMigrationCopyMaxAge) {
      for (final file in files) {
        if (await file.exists()) await file.delete();
      }
    }
  }

  Future<List<File>> _preMigrationFiles() async {
    final path = p.join(
        (await _backupsDirectory()).path, copy.preMigrationCopyFileName);
    return [File(path), File('$path.tmp')];
  }

  /// "Borrar todos los datos": la base, la carpeta respaldos/ completa
  /// (copia previa a importar, copia previa a la migracion v4 y cualquier
  /// .tmp huerfano), los temporales del respaldo y el estado del
  /// recordatorio de respaldo. Intenta siempre todos los pasos aunque
  /// alguno falle, para no dejar datos de salud por un error en otro
  /// paso, y al final lanza un unico [BackupDeleteException] si alguno
  /// fallo.
  Future<void> deleteAllData() async {
    final failedSteps = <BackupDeleteStep>[];
    final errors = <Object>[];
    Future<void> attempt(
        BackupDeleteStep step, Future<void> Function() action) async {
      try {
        await action();
      } catch (e) {
        failedSteps.add(step);
        errors.add(e);
      }
    }

    await attempt(BackupDeleteStep.database, _repository.deleteAllData);
    await attempt(BackupDeleteStep.backups, () async {
      final dir = await _backupsDirectory();
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    await attempt(BackupDeleteStep.temporaryFiles, cleanTemporaryFiles);
    await attempt(BackupDeleteStep.backupReminder, _reminderStore.delete);

    if (failedSteps.isNotEmpty) {
      throw BackupDeleteException(failedSteps, errors);
    }
  }

  Future<Directory> _backupsDirectory() async =>
      Directory(p.join((await _supportDirectory()).path, backupsDirName));

  Future<File> _preImportFile() async =>
      File(p.join((await _backupsDirectory()).path, preImportFileName));

  /// Escritura atomica: archivo temporal + rename, para que un corte a
  /// mitad de camino nunca deje una copia previa a medias. Un .tmp de un
  /// intento anterior se borra antes, y el propio se limpia si algo
  /// falla.
  Future<void> _writePreImportCopy() async {
    final json = await buildExportJson();
    final target = await _preImportFile();
    final tmp = File('${target.path}.tmp');
    try {
      await target.parent.create(recursive: true);
      if (await tmp.exists()) await tmp.delete();
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(target.path);
    } on FileSystemException catch (e) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } on FileSystemException {
        // Se reintenta en la proxima importacion o al borrar los datos.
      }
      throw BackupWriteException(BackupWriteCause.fileSystem,
          'no se pudo escribir la copia previa: $e');
    }
  }
}

BackupService? _backupServiceInstance;

/// Instancia unica para la app, como [cycleRepository].
BackupService get backupService => _backupServiceInstance ??= BackupService(
      cycleRepository,
      supportDirectory: getApplicationSupportDirectory,
      temporaryDirectory: getTemporaryDirectory,
      reminderStore: backupReminderStore,
    );

/// Solo para tests: reemplaza el servicio global.
set backupService(BackupService value) => _backupServiceInstance = value;
