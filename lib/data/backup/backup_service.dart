import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/backup_codec.dart';
import '../../utils/app_version.dart';
import '../../utils/day_key.dart';
import '../repositories/cycle_repository.dart';

/// Lo que la confirmacion de importar necesita mostrar: cuantos dias hay
/// hoy en el telefono y cuantos trae el respaldo.
class ImportPreview {
  const ImportPreview({
    required this.data,
    required this.currentDayCount,
  });

  final BackupData data;
  final int currentDayCount;

  int get incomingDayCount => data.days.length;

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
enum BackupDeleteStep { database, backups, temporaryFiles }

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

/// Archivos del respaldo (HU-06): exportar, importar con copia previa,
/// deshacer la importacion y limpiar temporales. Los datos pasan siempre
/// por [CycleRepository]; esta clase solo agrega el manejo de archivos.
class BackupService {
  BackupService(
    this._repository, {
    required Future<Directory> Function() supportDirectory,
    required Future<Directory> Function() temporaryDirectory,
    DateTime Function()? clock,
  })  : _supportDirectory = supportDirectory,
        _temporaryDirectory = temporaryDirectory,
        _clock = clock ?? DateTime.now;

  final CycleRepository _repository;
  final Future<Directory> Function() _supportDirectory;
  final Future<Directory> Function() _temporaryDirectory;
  final DateTime Function() _clock;

  /// Copia automatica de los datos anteriores a la ultima importacion,
  /// dentro del almacenamiento privado de la app. Hay una sola: cada
  /// importacion la reemplaza, deshacer no.
  static const String backupsDirName = 'respaldos';
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
  Future<File> writeExportFile() async {
    final json = await buildExportJson();
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

  /// Nombre sugerido para el archivo exportado.
  String exportFileName() =>
      'aura_respaldo_${DayKey.fromDate(_clock())}.json';

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
  /// en la cache la borra apenas termina, sea valido o no. No lanza.
  Future<BackupParseResult> readBackupFile(String path) async {
    final file = File(path);
    try {
      final length = await file.length();
      if (length > maxBackupSizeBytes) {
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

  Future<ImportPreview> previewImport(BackupData data) async {
    return ImportPreview(
      data: data,
      currentDayCount: await _repository.countDays(),
    );
  }

  /// Importa [data] reemplazando todo. Primero guarda la copia previa de
  /// los datos actuales; si esa copia no se puede escribir, no se importa
  /// nada. El reemplazo es una unica transaccion.
  Future<void> importBackup(BackupData data) async {
    await _writePreImportCopy();
    await _repository.replaceAllWithBackup(data);
  }

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
        await _repository.replaceAllWithBackup(data);
      case BackupParseFailure():
        throw BackupUndoUnavailableException('copia previa invalida: $result');
    }
  }

  /// "Borrar todos los datos": la base, la carpeta respaldos/ completa
  /// (copia previa y cualquier .tmp huerfano) y los temporales del
  /// respaldo. Intenta siempre los tres pasos aunque alguno falle, para
  /// no dejar datos de salud por un error en otro paso, y al final lanza
  /// un unico [BackupDeleteException] si alguno fallo.
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
    );

/// Solo para tests: reemplaza el servicio global.
set backupService(BackupService value) => _backupServiceInstance = value;
