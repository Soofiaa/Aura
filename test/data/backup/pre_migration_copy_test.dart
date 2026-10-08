import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:aura/data/backup/pre_migration_copy.dart';
import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/models/day_enums.dart';
import '../../drift/aura/generated/schema_v3.dart' as v3;

void main() {
  late Directory root;
  late File dbFile;
  late Directory backups;

  File copyFile() => File(p.join(backups.path, preMigrationCopyFileName));
  File tmpFile() => File('${copyFile().path}.tmp');

  /// Archivo de base v3 real (schema exacto del volcado) con un dia de
  /// sangrado y [userVersion] en el encabezado.
  Future<void> createV3File({int userVersion = 3}) async {
    final db = v3.DatabaseAtV3(NativeDatabase(dbFile));
    await db.customStatement(
        "INSERT INTO daily_logs (date, is_period_day) VALUES ('2026-08-01', 1)");
    await db.close();
    final raw = sqlite3.open(dbFile.path);
    raw.userVersion = userVersion;
    raw.dispose();
  }

  T withRaw<T>(File file, T Function(Database db) action) {
    final raw = sqlite3.open(file.path);
    try {
      return action(raw);
    } finally {
      raw.dispose();
    }
  }

  List<String> columns(File file, String table) => withRaw(file, (db) => [
        for (final row in db.select('PRAGMA table_info($table)'))
          row['name'] as String,
      ]);

  setUp(() {
    root = Directory.systemTemp.createTempSync('aura_copia_test');
    dbFile = File(p.join(root.path, 'app_flutter', 'aura.sqlite'))
      ..parent.createSync();
    backups = Directory(p.join(root.path, 'files', backupsDirName));
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('ensurePreMigrationCopy', () {
    for (final version in [1, 2, 3]) {
      test('con user_version $version crea la copia con los mismos datos',
          () async {
        await createV3File(userVersion: version);

        ensurePreMigrationCopy(database: dbFile, backupsDir: backups);

        expect(copyFile().existsSync(), isTrue);
        expect(tmpFile().existsSync(), isFalse);
        withRaw(copyFile(), (db) {
          expect(db.userVersion, version);
          expect(db.select('SELECT date FROM daily_logs').single['date'],
              '2026-08-01');
        });
        withRaw(dbFile, (db) => expect(db.userVersion, version));
      });
    }

    test('instalacion nueva (sin archivo): no crea copia ni archivo de base',
        () {
      ensurePreMigrationCopy(database: dbFile, backupsDir: backups);
      expect(dbFile.existsSync(), isFalse);
      expect(backups.existsSync(), isFalse);
    });

    test('base ya v4: no crea copia', () async {
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      await db.customSelect('SELECT 1').get();
      await db.close();
      withRaw(dbFile, (raw) => expect(raw.userVersion, 5));

      ensurePreMigrationCopy(database: dbFile, backupsDir: backups);

      expect(copyFile().existsSync(), isFalse);
    });

    test('base con user_version 0 (recien creada, sin migraciones): no crea '
        'copia', () {
      withRaw(dbFile, (raw) => raw.execute('CREATE TABLE x (y)'));
      ensurePreMigrationCopy(database: dbFile, backupsDir: backups);
      expect(copyFile().existsSync(), isFalse);
    });

    test('una copia que ya existe no se sobrescribe', () async {
      await createV3File();
      backups.createSync(recursive: true);
      copyFile().writeAsStringSync('copia anterior');

      ensurePreMigrationCopy(database: dbFile, backupsDir: backups);

      expect(copyFile().readAsStringSync(), 'copia anterior');
    });

    test('un .tmp de un intento anterior se reemplaza', () async {
      await createV3File();
      backups.createSync(recursive: true);
      tmpFile().writeAsStringSync('a medias');

      ensurePreMigrationCopy(database: dbFile, backupsDir: backups);

      expect(tmpFile().existsSync(), isFalse);
      withRaw(copyFile(), (db) => expect(db.userVersion, 3));
    });

    test('si la carpeta no se puede crear, lanza sin falta de espacio', () async {
      await createV3File();
      backups.parent.createSync(recursive: true);
      File(backups.path).writeAsStringSync('no es una carpeta');

      expect(
        () => ensurePreMigrationCopy(database: dbFile, backupsDir: backups),
        throwsA(isA<PreMigrationCopyException>()
            .having((e) => e.outOfSpace, 'outOfSpace', isFalse)),
      );
    });

    test(
        'sin espacio (SQLITE_FULL a mitad de la copia): lanza con '
        'outOfSpace y borra el .tmp', () async {
      await createV3File();

      expect(
        () => ensurePreMigrationCopy(
          database: dbFile,
          backupsDir: backups,
          copyInto: (db, path) {
            File(path).writeAsStringSync('a medias');
            throw SqliteException(13, 'database or disk is full');
          },
        ),
        throwsA(isA<PreMigrationCopyException>()
            .having((e) => e.outOfSpace, 'outOfSpace', isTrue)),
      );
      expect(tmpFile().existsSync(), isFalse);
      expect(copyFile().existsSync(), isFalse);
    });
  });

  group('isOutOfSpaceError', () {
    test('reconoce SQLITE_FULL y ENOSPC; no otros errores', () {
      expect(isOutOfSpaceError(SqliteException(13, 'full')), isTrue);
      expect(isOutOfSpaceError(SqliteException(13 | (1 << 8), 'full')), isTrue,
          reason: 'codigo extendido con resultado SQLITE_FULL');
      expect(
          isOutOfSpaceError(const FileSystemException(
              'x', 'y', OSError('No space left on device', 28))),
          isTrue);
      expect(isOutOfSpaceError(SqliteException(1, 'error')), isFalse);
      expect(
          isOutOfSpaceError(const FileSystemException(
              'x', 'y', OSError('Permission denied', 13))),
          isFalse);
      expect(isOutOfSpaceError(StateError('x')), isFalse);
    });
  });

  group('openDatabaseFile (copia y luego drift)', () {
    AppDatabase openWithCopy({String today = '2026-10-07'}) =>
        AppDatabase.forTesting(
          LazyDatabase(
              () => openDatabaseFile(database: dbFile, backupsDir: backups)),
          today: () => today,
        );

    test('copia la base v3 y despues migra; la copia queda en v3', () async {
      await createV3File();
      await withRawAsync(dbFile, "INSERT INTO daily_logs (date, is_period_day) "
          "VALUES ('2026-08-02', 1)");

      final db = openWithCopy();
      final rows = await db.select(db.dailyLogs).get();
      await db.close();

      expect(rows.map((r) => r.periodEnd),
          [null, PeriodEndSource.inferred]);
      withRaw(dbFile, (raw) => expect(raw.userVersion, 5));
      withRaw(copyFile(), (raw) => expect(raw.userVersion, 3));
      expect(columns(copyFile(), 'daily_logs'), isNot(contains('period_end')));
    });

    test('si la copia no se puede escribir, no migra: la base queda en v3',
        () async {
      await createV3File();
      backups.parent.createSync(recursive: true);
      File(backups.path).writeAsStringSync('no es una carpeta');

      final db = openWithCopy();
      await expectLater(db.customSelect('SELECT 1').get(),
          throwsA(isA<PreMigrationCopyException>()));
      // Cerrar una base que no llego a abrir vuelve a lanzar el error.
      await expectLater(db.close(), throwsA(isA<PreMigrationCopyException>()));

      withRaw(dbFile, (raw) => expect(raw.userVersion, 3));
      expect(columns(dbFile, 'daily_logs'), isNot(contains('period_end')));
    });

    test('al volver a abrir una base ya migrada no hace otra copia', () async {
      await createV3File();
      final first = openWithCopy();
      await first.customSelect('SELECT 1').get();
      await first.close();
      copyFile().deleteSync();

      final again = openWithCopy();
      await again.customSelect('SELECT 1').get();
      await again.close();

      expect(copyFile().existsSync(), isFalse);
    });
  });
}

Future<void> withRawAsync(File file, String sql) async {
  final raw = sqlite3.open(file.path);
  try {
    raw.execute(sql);
  } finally {
    raw.dispose();
  }
}
