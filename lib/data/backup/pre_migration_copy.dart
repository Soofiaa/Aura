import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Carpeta de copias automaticas dentro del almacenamiento privado de la
/// app (directorio de soporte). "Borrar todos los datos" la borra entera.
const String backupsDirName = 'respaldos';

/// Copia del archivo de la base tomada justo antes de migrar a v4 (R-5):
/// red de seguridad si la migracion dejara la base inutilizable. Se borra
/// tras el primer "Guardar en el telefono" exitoso, a los
/// [preMigrationCopyMaxAge] o con "Borrar todos los datos".
const String preMigrationCopyFileName = 'antes_de_migrar_v4.sqlite';

const Duration preMigrationCopyMaxAge = Duration(days: 30);

/// Solo se copia una base que todavia tiene que migrar a v4: user_version
/// entre 1 y 3. 0 es una base recien creada (no hay datos que proteger) y
/// 4 o mas ya esta migrada.
const int _firstVersionToCopy = 1;
const int _lastVersionToCopy = 3;

/// No se pudo escribir la copia previa; la base no se abre ni se migra.
class PreMigrationCopyException implements Exception {
  PreMigrationCopyException(this.cause, {required this.outOfSpace});

  final Object cause;

  /// El telefono no tiene espacio para la copia.
  final bool outOfSpace;

  @override
  String toString() =>
      'PreMigrationCopyException(outOfSpace: $outOfSpace): $cause';
}

/// Copia [database] a [backupsDir]/[preMigrationCopyFileName] si va a
/// migrar a v4 y la copia todavia no existe. Se llama ANTES de que drift
/// abra la base. Usa VACUUM INTO (copia coherente aunque quede un journal
/// pendiente) a un archivo temporal y lo renombra, para que un corte a
/// mitad de camino nunca deje una copia a medias. Lanza
/// [PreMigrationCopyException] si no la puede escribir.
///
/// [copyInto] reemplaza el VACUUM INTO en los tests.
void ensurePreMigrationCopy({
  required File database,
  required Directory backupsDir,
  @visibleForTesting void Function(Database db, String path)? copyInto,
}) {
  if (!database.existsSync()) return; // instalacion nueva

  final target = File(p.join(backupsDir.path, preMigrationCopyFileName));
  final tmp = File('${target.path}.tmp');
  final Database db;
  try {
    db = sqlite3.open(database.path);
  } on Object catch (e) {
    throw PreMigrationCopyException(e, outOfSpace: isOutOfSpaceError(e));
  }
  try {
    final version = db.userVersion;
    if (version < _firstVersionToCopy || version > _lastVersionToCopy) return;
    if (target.existsSync()) return;

    backupsDir.createSync(recursive: true);
    if (tmp.existsSync()) tmp.deleteSync();
    (copyInto ?? _vacuumInto)(db, tmp.path);
    tmp.renameSync(target.path);
  } on Object catch (e) {
    try {
      if (tmp.existsSync()) tmp.deleteSync();
    } on FileSystemException {
      // Se reintenta en la proxima apertura o al borrar los datos.
    }
    throw PreMigrationCopyException(e, outOfSpace: isOutOfSpaceError(e));
  } finally {
    db.dispose();
  }
}

void _vacuumInto(Database db, String path) =>
    db.execute('VACUUM INTO ?', [path]);

/// Codigos de "sin espacio": SQLITE_FULL (13) de SQLite, ENOSPC (28) en
/// Android/Linux y ERROR_DISK_FULL (112) / ERROR_HANDLE_DISK_FULL (39) en
/// Windows.
const int _sqliteFull = 13;
const Set<int> _osOutOfSpaceCodes = {28, 39, 112};

/// true si [error] (de SQLite o del sistema de archivos) es por falta de
/// espacio en el telefono.
bool isOutOfSpaceError(Object error) => switch (error) {
      PreMigrationCopyException(:final outOfSpace) => outOfSpace,
      SqliteException(:final resultCode) => resultCode == _sqliteFull,
      FileSystemException(:final osError?) =>
        _osOutOfSpaceCodes.contains(osError.errorCode),
      _ => false,
    };
