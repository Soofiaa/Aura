import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:aura/data/backup/backup_service.dart';
import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/models/day_enums.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/domain/backup_codec.dart';
import 'package:aura/domain/backup_crypto.dart';
import 'package:aura/utils/app_version.dart';

/// HU-06b CP2: exportar e importar cifrado en BackupService. Datos
/// inventados, base en memoria. Salvo un test, los trabajos corren en el
/// mismo isolate ([runInSameIsolate]) con parametros reducidos.

const _small = Argon2idParams(memoryKiB: 8192, iterations: 1, parallelism: 1);
const _password = 'Clave inventada: ñandú 🌸';

/// Cifra bien y despues invierte un bit del texto cifrado: un cifrador
/// defectuoso que la verificacion de HU6b-10 tiene que detectar.
Future<String> _corruptCiphertext(
  String doc,
  String password,
  Argon2idParams params,
) async {
  final root =
      jsonDecode(await encryptBackup(doc, password, params: params))
          as Map<String, dynamic>;
  final c = base64.decode(root['ciphertext'] as String);
  c[0] ^= 0x01;
  root['ciphertext'] = base64.encode(c);
  return jsonEncode(root);
}

/// Cifra bien pero escribe otra sal en el encabezado (un error "al escribir
/// la sal"): solo se detecta volviendo a derivar la clave.
Future<String> _wrongSaltInHeader(
  String doc,
  String password,
  Argon2idParams params,
) async {
  final root =
      jsonDecode(await encryptBackup(doc, password, params: params))
          as Map<String, dynamic>;
  final enc = root['encryption'] as Map<String, dynamic>;
  final salt = base64.decode(enc['salt'] as String);
  salt[0] ^= 0x01;
  enc['salt'] = base64.encode(salt);
  return jsonEncode(root);
}

/// Falla incluyendo la contrasena en su mensaje: el servicio no debe
/// propagar ese texto.
Future<String> _failingWithPassword(
  String doc,
  String password,
  Argon2idParams params,
) => throw StateError('fallo con la contrasena $password');

void main() {
  late AppDatabase db;
  late CycleRepository repo;
  late Directory root;
  late Directory support;
  late Directory temp;
  final now = DateTime(2026, 10, 4, 10, 15);

  setUp(() {
    db = AppDatabase.forTesting(
      NativeDatabase.memory(setup: enableForeignKeys),
    );
    repo = CycleRepository(db);
    root = Directory.systemTemp.createTempSync('aura_backup_cifrado_test');
    support = Directory(p.join(root.path, 'support'))..createSync();
    temp = Directory(p.join(root.path, 'cache'))..createSync();
  });

  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  BackupService service({
    BackupTaskRunner runTask = runInSameIsolate,
    Argon2idParams params = _small,
    BackupEncryptFunction encrypt = encryptBackupDocument,
    int maxFileBytes = maxBackupSizeBytes,
  }) => BackupService(
    repo,
    supportDirectory: () async => support,
    temporaryDirectory: () async => temp,
    clock: () => now,
    runTask: runTask,
    encryptionParams: params,
    encrypt: encrypt,
    maxFileBytes: maxFileBytes,
  );

  File preImportFile() => File(
    p.join(
      support.path,
      BackupService.backupsDirName,
      BackupService.preImportFileName,
    ),
  );

  Directory exportDir() =>
      Directory(p.join(temp.path, BackupService.exportDirName));

  List<String> exportedFiles() => exportDir().existsSync()
      ? [for (final f in exportDir().listSync()) p.basename(f.path)]
      : const [];

  Future<void> seedData() async {
    await repo.upsertDay(
      date: '2026-05-01',
      isPeriodDaySwitch: true,
      flow: FlowIntensity.moderado,
      notes: 'nota inventada',
      symptoms: {Symptom.acne},
    );
    await repo.markPeriodDays(['2026-05-02', '2026-05-03', '2026-06-01']);
    await repo.setTypicalPeriodLength(4);
    await repo.setOnboardingSeen(true);
  }

  Future<String> currentDataJson() async =>
      encodeBackup(await repo.readBackupData(appVersion: 'x', exportedAt: 'x'));

  Future<BackupNeedsPassword> readPending(BackupService s, File file) async {
    final result = await s.readBackupFile(file.path);
    expect(result, isA<BackupNeedsPassword>());
    return result as BackupNeedsPassword;
  }

  group('exportar', () {
    test(
      'sin contrasena: mismo archivo y mismo nombre que antes de HU-06b',
      () async {
        await seedData();
        // Un cifrador que falla prueba ademas que el camino plano no cifra.
        final s = service(encrypt: _failingWithPassword);
        final file = await s.writeExportFile();
        expect(p.basename(file.path), 'aura_respaldo_2026-10-04.json');
        final expected = encodeBackup(
          await repo.readBackupData(
            appVersion: appVersionName,
            exportedAt: formatExportedAt(now),
          ),
        );
        expect(file.readAsBytesSync(), utf8.encode(expected));
        expect(file.readAsStringSync(), await s.buildExportJson());
      },
    );

    test('con contrasena: formatVersion 2, nombre protegido y descifra al '
        'documento sin cifrar', () async {
      await seedData();
      final s = service();
      final file = await s.writeExportFile(password: _password);
      expect(p.basename(file.path), 'aura_respaldo_protegido_2026-10-04.json');
      final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(root['formatVersion'], 2);
      expect(root.containsKey('data'), isFalse);
      final clear = await decryptBackup(file.readAsBytesSync(), _password);
      expect(utf8.decode(clear), await s.buildExportJson());
    });

    test('HU6b-10: un cifrador que corrompe un byte se detecta: falla, no '
        'deja archivo y no hay exito', () async {
      await seedData();
      final s = service(encrypt: _corruptCiphertext);
      await expectLater(
        s.writeExportFile(password: _password),
        throwsA(
          isA<BackupEncryptionException>().having(
            (e) => e.cause,
            'cause',
            BackupEncryptionFailure.verificationFailed,
          ),
        ),
      );
      expect(exportedFiles(), isEmpty);
    });

    test(
      'HU6b-10: una sal mal escrita en el encabezado tambien se detecta',
      () async {
        await seedData();
        final s = service(encrypt: _wrongSaltInHeader);
        await expectLater(
          s.writeExportFile(password: _password),
          throwsA(
            isA<BackupEncryptionException>().having(
              (e) => e.cause,
              'cause',
              BackupEncryptionFailure.verificationFailed,
            ),
          ),
        );
        expect(exportedFiles(), isEmpty);
      },
    );

    test(
      'HU6b-10: archivo por encima del tope: falla y no deja archivo',
      () async {
        await seedData();
        final s = service(maxFileBytes: 100);
        try {
          await s.writeExportFile(password: _password);
          fail('debia fallar');
        } on BackupEncryptionException catch (e) {
          expect(e.cause, BackupEncryptionFailure.tooLarge);
          expect(
            e.message,
            'No se pudo crear el respaldo protegido: el archivo supera el '
            'tamaño máximo. No se guardó ningún archivo.',
          );
        }
        expect(exportedFiles(), isEmpty);
      },
    );

    test('mensaje de la verificacion fallida, en espanol', () {
      expect(
        BackupEncryptionException(
          BackupEncryptionFailure.verificationFailed,
          'x',
        ).message,
        'No se pudo crear el respaldo protegido: la comprobación del '
        'archivo falló. No se guardó ningún archivo.',
      );
    });

    test('borra los temporales de exportaciones anteriores, igual que el '
        'plano', () async {
      await seedData();
      final s = service();
      await s.writeExportFile();
      await s.writeExportFile(password: _password);
      expect(exportedFiles(), ['aura_respaldo_protegido_2026-10-04.json']);
    });
  });

  group('importar', () {
    test('ida y vuelta: exportar cifrado, borrar, importar con la contrasena: '
        'mismos datos, por el mismo camino que un respaldo plano', () async {
      await seedData();
      final original = await currentDataJson();
      final s = service();
      final file = await s.writeExportFile(password: _password);
      final keep = File(p.join(root.path, 'respaldo.json'))
        ..writeAsBytesSync(file.readAsBytesSync());

      await repo.deleteAllData();
      await repo.upsertDay(
        date: '2026-07-07',
        isPeriodDaySwitch: true,
        notes: 'otro dato',
      );

      final pending = await readPending(s, keep);
      final unlocked = await s.unlockBackup(pending, _password);
      final data = (unlocked as BackupUnlocked).data;
      final preview = await s.previewImport(data);
      expect(preview.incomingDayCount, 4);
      expect(preview.currentDayCount, 1);
      await s.importBackup(data);

      expect(await currentDataJson(), original);
      // La copia previa es la de un respaldo plano.
      final copia = decodeBackup(preImportFile().readAsBytesSync());
      expect(copia, isA<BackupParseSuccess>());
      expect((copia as BackupParseSuccess).data.days.single.notes, 'otro dato');
    });

    test('contrasena incorrecta: nada cambia y no se crea la copia previa; '
        'despues, la correcta con el mismo archivo funciona', () async {
      await seedData();
      final s = service();
      final file = await s.writeExportFile(password: _password);
      final keep = File(p.join(root.path, 'respaldo.json'))
        ..writeAsBytesSync(file.readAsBytesSync());
      await repo.deleteAllData();
      await repo.upsertDay(
        date: '2026-07-07',
        isPeriodDaySwitch: true,
        notes: 'otro dato',
      );
      final before = await currentDataJson();

      final pending = await readPending(s, keep);
      final wrong = await s.unlockBackup(pending, 'no es la clave');
      expect(wrong, isA<BackupUnlockWrongPasswordOrDamaged>());
      expect(
        (wrong as BackupUnlockWrongPasswordOrDamaged).message,
        wrongPasswordOrDamagedMessage,
      );
      expect(await currentDataJson(), before);
      expect(preImportFile().existsSync(), isFalse);
      expect(
        Directory(
          p.join(support.path, BackupService.backupsDirName),
        ).existsSync(),
        isFalse,
      );

      final right = await s.unlockBackup(pending, _password);
      expect(right, isA<BackupUnlocked>());
      await s.importBackup((right as BackupUnlocked).data);
      expect(preImportFile().existsSync(), isTrue);
      expect(await repo.countDays(), 4);
    });

    test(
      'un cifrado dentro de otro: se descifra pero no es importable',
      () async {
        await seedData();
        final s = service();
        final inner = await encryptBackup(
          await s.buildExportJson(),
          _password,
          params: _small,
        );
        final outer = await encryptBackup(inner, _password, params: _small);
        final file = File(p.join(root.path, 'anidado.json'))
          ..writeAsStringSync(outer);
        final result = await s.unlockBackup(
          await readPending(s, file),
          _password,
        );
        expect(result, isA<BackupUnlockInvalid>());
        expect((result as BackupUnlockInvalid).error, BackupError.damaged);
        expect(preImportFile().existsSync(), isFalse);
      },
    );

    test(
      'tope de tamano en el camino cifrado: se rechaza antes de parsear',
      () async {
        await seedData();
        final file = await service().writeExportFile(password: _password);
        final keep = File(p.join(root.path, 'respaldo.json'))
          ..writeAsBytesSync(file.readAsBytesSync());
        expect(keep.lengthSync(), greaterThan(500));
        final result = await service(
          maxFileBytes: 500,
        ).readBackupFile(keep.path);
        expect((result as BackupParseFailure).error, BackupError.tooLarge);
      },
    );

    test(
      'tope de 5 MB con el valor real: un "cifrado" de mas de 5 MB',
      () async {
        // Este test cubre la defensa del codec: decodeBackup aplica su
        // propio tope (maxBackupSizeBytes) aunque el servicio no lo haga.
        // El tope del servicio lo cubre el test anterior (tope inyectado).
        final big = File(p.join(root.path, 'grande.json'))
          ..writeAsStringSync(
            '{"format":"aura-backup","formatVersion":2,'
            '"ciphertext":"${'A' * (maxBackupSizeBytes + 10)}"}',
          );
        final result = await service().readBackupFile(big.path);
        expect((result as BackupParseFailure).error, BackupError.tooLarge);
      },
    );

    test(
      'parametros fuera de rango: se rechaza sin pedir contrasena',
      () async {
        await seedData();
        final file = await service().writeExportFile(password: _password);
        final rootMap =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        ((rootMap['encryption'] as Map)['kdfParams'] as Map)['memoryKiB'] =
            999999;
        final edited = File(p.join(root.path, 'editado.json'))
          ..writeAsStringSync(jsonEncode(rootMap));
        final result = await service().readBackupFile(edited.path);
        expect((result as BackupParseFailure).error, BackupError.newerVersion);
      },
    );
  });

  test('parametros de PRODUCCION con Isolate.run real (una vez)', () async {
    await seedData();
    final original = await currentDataJson();
    final s = service(runTask: runInIsolate, params: Argon2idParams.production);
    final file = await s.writeExportFile(password: _password);
    final root0 = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect((root0['encryption'] as Map)['kdfParams'], {
      'memoryKiB': 19456,
      'iterations': 2,
      'parallelism': 1,
    });
    final keep = File(p.join(root.path, 'respaldo.json'))
      ..writeAsBytesSync(file.readAsBytesSync());
    await repo.deleteAllData();
    final unlocked = await s.unlockBackup(
      await readPending(s, keep),
      _password,
    );
    await s.importBackup((unlocked as BackupUnlocked).data);
    expect(await currentDataJson(), original);
  });

  group('runner: el trabajo pesado pasa siempre por runTask', () {
    late int calls;
    Future<R> counting<R>(FutureOr<R> Function() task) {
      calls++;
      return runInSameIsolate(task);
    }

    setUp(() => calls = 0);

    test('exportar con contrasena: 2 veces (cifrar y verificar)', () async {
      await seedData();
      await service(runTask: counting).writeExportFile(password: _password);
      expect(calls, 2);
    });

    test('exportar sin contrasena: 0 veces', () async {
      await seedData();
      await service(runTask: counting).writeExportFile();
      expect(calls, 0);
    });

    test('unlockBackup: 1 vez', () async {
      await seedData();
      final file = await service().writeExportFile(password: _password);
      final keep = File(p.join(root.path, 'respaldo.json'))
        ..writeAsBytesSync(file.readAsBytesSync());
      final s = service(runTask: counting);
      final pending = await readPending(s, keep);
      expect(await s.unlockBackup(pending, _password), isA<BackupUnlocked>());
      expect(calls, 1);
    });
  });

  test('unlockBackup no lanza: un error inesperado del runner vuelve como '
      'BackupUnlockInvalid, sin la contrasena', () async {
    await seedData();
    final file = await service().writeExportFile(password: _password);
    final keep = File(p.join(root.path, 'respaldo.json'))
      ..writeAsBytesSync(file.readAsBytesSync());
    Future<R> failing<R>(FutureOr<R> Function() task) =>
        throw StateError('x $_password');
    final s = service(runTask: failing);
    final pending = await readPending(s, keep);
    final result = await s.unlockBackup(pending, _password);
    expect(result, isA<BackupUnlockInvalid>());
    expect((result as BackupUnlockInvalid).error, BackupError.damaged);
    expect(result.detail, 'error inesperado: StateError');
    expect(result.toString(), isNot(contains(_password)));
    expect(result.toString(), isNot(contains('ñandú')));
    expect(preImportFile().existsSync(), isFalse);
  });

  group('la contrasena no se filtra', () {
    test('en las excepciones y resultados nuevos', () async {
      await seedData();
      final texts = <String>[];

      try {
        await service(
          encrypt: _failingWithPassword,
        ).writeExportFile(password: _password);
        fail('debia fallar');
      } on BackupEncryptionException catch (e) {
        expect(e.cause, BackupEncryptionFailure.encryptionFailed);
        texts.addAll([e.toString(), e.detail, e.message]);
      }
      try {
        await service(
          encrypt: _corruptCiphertext,
        ).writeExportFile(password: _password);
      } on BackupEncryptionException catch (e) {
        texts.addAll([e.toString(), e.detail, e.message]);
      }

      final s = service();
      final file = await s.writeExportFile(password: _password);
      final keep = File(p.join(root.path, 'respaldo.json'))
        ..writeAsBytesSync(file.readAsBytesSync());
      final pending = await readPending(s, keep);
      texts
        ..add(pending.toString())
        ..add((await s.unlockBackup(pending, 'otra $_password')).toString())
        ..add((await s.unlockBackup(pending, _password)).toString())
        ..add(const BackupUnlockInvalid(BackupError.damaged, 'x').toString())
        ..add(keep.readAsStringSync());

      for (final t in texts) {
        expect(t, isNot(contains(_password)));
        expect(t, isNot(contains('ñandú')));
      }
    });
  });
}
