import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aura/data/backup/backup_file_gateway.dart';
import 'package:aura/data/backup/backup_service.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/domain/backup_codec.dart';

/// Gateway falso: no toca canales de plataforma, solo registra que se le
/// pidio y devuelve lo configurado.
class FakeBackupFileGateway implements BackupFileGateway {
  /// Ruta que devuelve el selector; null simula que la usuaria cancela.
  String? pickResult;
  int pickCount = 0;

  final List<File> sharedFiles = [];
  Object? shareError;

  /// Resultado del "Guardar como": false simula que la usuaria cancela.
  bool saveResult = true;
  Object? saveError;
  String? savedFileName;
  Uint8List? savedBytes;

  @override
  Future<String?> pickBackupFile() async {
    pickCount++;
    return pickResult;
  }

  @override
  Future<void> shareFile(File file) async {
    if (shareError != null) throw shareError!;
    sharedFiles.add(file);
  }

  @override
  Future<bool> saveToDevice({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (saveError != null) throw saveError!;
    if (!saveResult) return false;
    savedFileName = fileName;
    savedBytes = bytes;
    return true;
  }
}

/// BackupService falso para tests de widget: la E/S real de archivos no
/// avanza dentro del reloj falso de testWidgets, asi que los archivos se
/// simulan en memoria. Los datos SI pasan por el repositorio real (base
/// en memoria) y el contenido por el codec real; el manejo de archivos
/// real se prueba en test/data/backup/backup_service_test.dart.
class FakeBackupService extends BackupService {
  FakeBackupService(this._repo)
      : super(
          _repo,
          supportDirectory: () => throw UnimplementedError(),
          temporaryDirectory: () => throw UnimplementedError(),
          clock: () => DateTime(2026, 10, 4, 10, 15),
        );

  final CycleRepository _repo;

  /// Contenido de los archivos que el selector puede devolver, por ruta.
  final Map<String, List<int>> files = {};

  /// Si no es null, importBackup espera a que se complete (para probar
  /// la pantalla bloqueada y el doble toque).
  Completer<void>? importGate;

  /// Error que lanza la creacion del respaldo (export o copia previa).
  BackupWriteException? writeError;

  int importCount = 0;
  int undoCount = 0;
  int deleteAllDataCallCount = 0;
  bool failOnDelete = false;
  String? _preImportCopy;

  @override
  Future<String> buildExportJson() async {
    if (writeError != null) throw writeError!;
    return super.buildExportJson();
  }

  @override
  Future<File> writeExportFile() async {
    await buildExportJson();
    return File('cache/aura_respaldo/${exportFileName()}');
  }

  @override
  Future<BackupParseResult> readBackupFile(String path) async =>
      decodeBackup(files[path]!);

  @override
  Future<void> importBackup(BackupData data) async {
    importCount++;
    _preImportCopy = await buildExportJson();
    if (importGate != null) await importGate!.future;
    await _repo.replaceAllWithBackup(data);
  }

  @override
  Future<bool> hasPreImportCopy() async => _preImportCopy != null;

  @override
  Future<void> undoLastImport() async {
    undoCount++;
    final copy = _preImportCopy;
    if (copy == null) {
      throw BackupUndoUnavailableException('no hay copia previa');
    }
    final result = decodeBackup(utf8.encode(copy));
    await _repo.replaceAllWithBackup((result as BackupParseSuccess).data);
  }

  @override
  Future<void> deleteAllData() async {
    deleteAllDataCallCount++;
    if (failOnDelete) throw StateError('detalle interno que no se muestra');
    _preImportCopy = null;
    await _repo.deleteAllData();
  }

  @override
  Future<void> cleanTemporaryFiles() async {}
}
