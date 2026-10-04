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
import 'package:aura/utils/app_version.dart';

BackupData _fixture() {
  final result = decodeBackup(
      utf8.encode(File('test/fixtures/backup_v3.json').readAsStringSync()));
  return (result as BackupParseSuccess).data;
}

void main() {
  late AppDatabase db;
  late CycleRepository repo;
  late Directory root;
  late Directory support;
  late Directory temp;
  late DateTime now;
  late BackupService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CycleRepository(db);
    root = Directory.systemTemp.createTempSync('aura_backup_test');
    support = Directory(p.join(root.path, 'support'))..createSync();
    temp = Directory(p.join(root.path, 'cache'))..createSync();
    now = DateTime(2026, 10, 4, 10, 15);
    service = BackupService(
      repo,
      supportDirectory: () async => support,
      temporaryDirectory: () async => temp,
      clock: () => now,
    );
  });

  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  File preImportFile() => File(p.join(support.path,
      BackupService.backupsDirName, BackupService.preImportFileName));

  Future<void> seedCurrentData() async {
    await repo.upsertDay(
      date: '2026-05-01',
      isPeriodDaySwitch: true,
      flow: FlowIntensity.ligero,
      notes: 'dato actual',
      symptoms: {Symptom.acne},
    );
    await repo.markPeriodDays(['2026-05-02', '2026-05-03']);
    // Quien llega a Ajustes ya paso el onboarding; importar siempre lo
    // deja en true.
    await repo.setOnboardingSeen(true);
  }

  Future<String> currentDataJson() async => encodeBackup(
      await repo.readBackupData(appVersion: 'x', exportedAt: 'x'));

  group('exportar', () {
    test('el JSON trae version de la app, fecha con zona y todos los datos',
        () async {
      await seedCurrentData();
      final json = await service.buildExportJson();
      final data = (decodeBackup(utf8.encode(json)) as BackupParseSuccess).data;

      expect(data.appVersion, appVersionName);
      expect(data.exportedAt, startsWith('2026-10-04T10:15:00'));
      expect(data.days, hasLength(3));
      expect(data.days.first.symptoms, [Symptom.acne]);
    });

    test('escribe el archivo en su carpeta temporal y lo deja ahi (la app de '
        'destino puede seguir leyendolo)', () async {
      await seedCurrentData();
      final file = await service.writeExportFile();

      expect(p.basename(file.path), 'aura_respaldo_2026-10-04.json');
      expect(p.dirname(file.path),
          p.join(temp.path, BackupService.exportDirName));
      expect(file.existsSync(), isTrue);
      expect(decodeBackup(file.readAsBytesSync()), isA<BackupParseSuccess>());
    });

    test('antes de exportar borra los temporales de la exportacion anterior '
        'y la copia de share_plus', () async {
      final primero = await service.writeExportFile();
      final sharePlus = Directory(p.join(temp.path, 'share_plus'))
        ..createSync();
      File(p.join(sharePlus.path, p.basename(primero.path)))
          .writeAsStringSync('copia compartida');

      now = DateTime(2026, 10, 5, 9);
      final segundo = await service.writeExportFile();

      expect(primero.existsSync(), isFalse);
      expect(sharePlus.existsSync(), isFalse);
      expect(segundo.existsSync(), isTrue);
    });

    test('un dia despues de 2030-12-31 impide el respaldo e informa la '
        'causa y la fecha como datos, no como texto', () async {
      // Un dia mas alla del tope de fechas (reloj adelantado en el pasado):
      // ese respaldo no se podria volver a importar.
      await repo.markPeriodDay('2026-05-01');
      await repo.markPeriodDay('2031-01-01');

      await expectLater(
        service.writeExportFile(),
        throwsA(isA<BackupWriteException>()
            .having((e) => e.cause, 'cause', BackupWriteCause.dateOutOfRange)
            .having((e) => e.outOfRangeDate, 'outOfRangeDate', '2031-01-01')),
      );
      expect(Directory(p.join(temp.path, BackupService.exportDirName))
          .existsSync(), isFalse);
    });

    test('la misma fecha fuera de rango bloquea la importacion (no hay copia '
        'previa posible) con el mismo dato estructurado', () async {
      await repo.markPeriodDay('2031-01-01');

      await expectLater(
        service.importBackup(_fixture()),
        throwsA(isA<BackupWriteException>()
            .having((e) => e.cause, 'cause', BackupWriteCause.dateOutOfRange)
            .having((e) => e.outOfRangeDate, 'outOfRangeDate', '2031-01-01')),
      );
      expect(await repo.countDays(), 1);
    });
  });

  test('cleanTemporaryFiles borra solo las carpetas del respaldo', () async {
    await service.writeExportFile();
    Directory(p.join(temp.path, 'share_plus')).createSync();
    final ajeno = File(p.join(temp.path, 'otro_archivo.txt'))
      ..writeAsStringSync('no es del respaldo');

    await service.cleanTemporaryFiles();

    expect(Directory(p.join(temp.path, BackupService.exportDirName))
        .existsSync(), isFalse);
    expect(Directory(p.join(temp.path, 'share_plus')).existsSync(), isFalse);
    expect(ajeno.existsSync(), isTrue);
  });

  test('cleanTemporaryFiles tambien borra las copias de file_picker',
      () async {
    final copia = File(p.join(temp.path, 'file_picker', '1700000000000',
        'respaldo.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('datos de salud');

    await service.cleanTemporaryFiles();

    expect(copia.existsSync(), isFalse);
    expect(Directory(p.join(temp.path, 'file_picker')).existsSync(), isFalse);
  });

  group('readBackupFile (archivo elegido para importar)', () {
    File copiaDelSelector(List<int> bytes) => File(p.join(
        temp.path, BackupService.pickerDirName, '1700000000000', 'r.json'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);

    test('un respaldo valido se decodifica y la copia se borra al leerla',
        () async {
      final copia = copiaDelSelector(
          File('test/fixtures/backup_v3.json').readAsBytesSync());

      final result = await service.readBackupFile(copia.path);

      expect(result, isA<BackupParseSuccess>());
      expect(copia.existsSync(), isFalse);
      expect(copia.parent.existsSync(), isFalse,
          reason: 'tambien la carpeta <instante> vacia');
    });

    test('un archivo invalido tambien se borra', () async {
      final copia = copiaDelSelector(utf8.encode('no es un respaldo'));

      final result = await service.readBackupFile(copia.path);

      expect((result as BackupParseFailure).error, BackupError.notABackup);
      expect(copia.existsSync(), isFalse);
    });

    test('mas de 5 MB se rechaza por tamano (sin decodificar) y se borra',
        () async {
      final copia = copiaDelSelector(List.filled(maxBackupSizeBytes + 1, 0x20));

      final result = await service.readBackupFile(copia.path);

      expect((result as BackupParseFailure).error, BackupError.tooLarge);
      expect(result.detail, '${maxBackupSizeBytes + 1} bytes');
      expect(copia.existsSync(), isFalse);
    });

    test('un archivo que no se puede leer devuelve unreadable', () async {
      final result = await service.readBackupFile(p.join(
          temp.path, BackupService.pickerDirName, 'no_existe.json'));
      expect((result as BackupParseFailure).error, BackupError.unreadable);
    });

    test('nunca borra un archivo fuera de cache/file_picker', () async {
      final ajeno = File(p.join(root.path, 'mis_documentos', 'respaldo.json'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(
            File('test/fixtures/backup_v3.json').readAsBytesSync());

      final result = await service.readBackupFile(ajeno.path);

      expect(result, isA<BackupParseSuccess>());
      expect(ajeno.existsSync(), isTrue);
    });
  });

  test('cleanTemporaryFiles sin nada que borrar no falla', () async {
    await service.cleanTemporaryFiles();
  });

  group('previewImport', () {
    test('cuenta los dias actuales y los que se pierden', () async {
      await seedCurrentData();
      final preview = await service.previewImport(_fixture());
      expect(preview.currentDayCount, 3);
      expect(preview.incomingDayCount, 7);
      expect(preview.daysLost, 0);
    });

    test('daysLost cuando el respaldo trae menos dias que los actuales',
        () async {
      await repo.markPeriodDays(
          [for (var d = 1; d <= 9; d++) '2026-06-0$d']);
      final preview = await service.previewImport(_fixture());
      expect(preview.daysLost, 2);
    });
  });

  group('importar', () {
    test('guarda la copia previa con los datos actuales y luego reemplaza',
        () async {
      await seedCurrentData();
      final antes = await repo.readBackupData(appVersion: 'x', exportedAt: 'x');

      await service.importBackup(_fixture());

      expect(await repo.countDays(), 7);
      final copia = decodeBackup(preImportFile().readAsBytesSync());
      expect(copia, isA<BackupParseSuccess>());
      expect((copia as BackupParseSuccess).data.days, antes.days);
      expect(copia.data.settings, antes.settings);
      expect(File('${preImportFile().path}.tmp').existsSync(), isFalse);
    });

    test('si la copia previa no se puede escribir, no se importa nada',
        () async {
      await seedCurrentData();
      final antes = await currentDataJson();
      // La carpeta de soporte es en realidad un archivo: crear respaldos/
      // dentro falla.
      final bloqueado = File(p.join(root.path, 'bloqueado'))
        ..writeAsStringSync('');
      service = BackupService(
        repo,
        supportDirectory: () async => Directory(bloqueado.path),
        temporaryDirectory: () async => temp,
        clock: () => now,
      );

      await expectLater(
        service.importBackup(_fixture()),
        throwsA(isA<BackupWriteException>()
            .having((e) => e.cause, 'cause', BackupWriteCause.fileSystem)
            .having((e) => e.outOfRangeDate, 'outOfRangeDate', isNull)),
      );
      expect(await currentDataJson(), antes);
    });

    test('un .tmp viejo de un intento anterior no impide una copia nueva',
        () async {
      await seedCurrentData();
      final tmp = File('${preImportFile().path}.tmp')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('restos de un intento cortado');

      await service.importBackup(_fixture());

      expect(tmp.existsSync(), isFalse);
      expect(decodeBackup(preImportFile().readAsBytesSync()),
          isA<BackupParseSuccess>());
      expect(await repo.countDays(), 7);
    });

    test('si la escritura de la copia falla a mitad, el .tmp se limpia y no '
        'se importa nada', () async {
      await seedCurrentData();
      final antes = await currentDataJson();
      // El destino es una carpeta con contenido: el rename del .tmp falla
      // despues de haberlo escrito.
      Directory(preImportFile().path).createSync(recursive: true);
      File(p.join(preImportFile().path, 'algo')).writeAsStringSync('x');

      await expectLater(
        service.importBackup(_fixture()),
        throwsA(isA<BackupWriteException>()
            .having((e) => e.cause, 'cause', BackupWriteCause.fileSystem)),
      );
      expect(File('${preImportFile().path}.tmp').existsSync(), isFalse);
      expect(await currentDataJson(), antes);
    });

    test('una segunda importacion reemplaza la copia previa', () async {
      await seedCurrentData();
      await service.importBackup(_fixture());
      final despuesDeLaPrimera =
          await repo.readBackupData(appVersion: 'x', exportedAt: 'x');

      await service.importBackup(_fixture());

      final copia =
          (decodeBackup(preImportFile().readAsBytesSync()) as BackupParseSuccess)
              .data;
      expect(copia.days, despuesDeLaPrimera.days);
    });
  });

  group('deshacer la importacion', () {
    test('vuelve a los datos de antes', () async {
      await seedCurrentData();
      final antes = await currentDataJson();
      await service.importBackup(_fixture());

      await service.undoLastImport();

      expect(await currentDataJson(), antes);
    });

    test('no sobrescribe antes_de_importar.json y se puede repetir', () async {
      await seedCurrentData();
      await service.importBackup(_fixture());
      final copia = preImportFile().readAsBytesSync();
      final modificada = preImportFile().lastModifiedSync();

      now = DateTime(2026, 10, 4, 18);
      await service.undoLastImport();
      await service.undoLastImport();

      expect(preImportFile().readAsBytesSync(), copia);
      expect(preImportFile().lastModifiedSync(), modificada);
      expect(await repo.countDays(), 3);
    });

    test('sin copia previa avisa que no se puede deshacer', () async {
      expect(await service.hasPreImportCopy(), isFalse);
      await expectLater(service.undoLastImport(),
          throwsA(isA<BackupUndoUnavailableException>()));
    });

    test('con una copia previa danada no toca los datos', () async {
      await seedCurrentData();
      preImportFile()
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{"format": "aura-backup"');
      final antes = await currentDataJson();

      await expectLater(service.undoLastImport(),
          throwsA(isA<BackupUndoUnavailableException>()));
      expect(await currentDataJson(), antes);
    });
  });

  test('borrar todos los datos elimina tambien un .tmp huerfano de la copia '
      'previa (borra la carpeta respaldos/ completa)', () async {
    final carpeta =
        Directory(p.join(support.path, BackupService.backupsDirName))
          ..createSync();
    final huerfano = File(p.join(carpeta.path, 'antes_de_importar.json.tmp'))
      ..writeAsStringSync('datos de salud a medio escribir');

    await service.deleteAllData();

    expect(huerfano.existsSync(), isFalse);
    expect(carpeta.existsSync(), isFalse);
  });

  test('si falla el borrado de la copia, igual se borran la base y los '
      'temporales, y se propaga un unico error', () async {
    await seedCurrentData();
    await service.writeExportFile();
    Directory(p.join(temp.path, 'share_plus')).createSync();
    service = BackupService(
      repo,
      supportDirectory: () async =>
          throw const FileSystemException('sin acceso a respaldos/'),
      temporaryDirectory: () async => temp,
      clock: () => now,
    );

    await expectLater(
      service.deleteAllData(),
      throwsA(isA<BackupDeleteException>().having(
          (e) => e.failedSteps, 'failedSteps', [BackupDeleteStep.backups])),
    );
    expect(await repo.countDays(), 0);
    expect(Directory(p.join(temp.path, BackupService.exportDirName))
        .existsSync(), isFalse);
    expect(Directory(p.join(temp.path, 'share_plus')).existsSync(), isFalse);
  });

  test('borrar todos los datos elimina la base, la copia previa y los '
      'temporales', () async {
    await seedCurrentData();
    await service.importBackup(_fixture());
    await service.writeExportFile();
    Directory(p.join(temp.path, 'share_plus')).createSync();
    expect(preImportFile().existsSync(), isTrue);

    await service.deleteAllData();

    expect(await repo.countDays(), 0);
    expect(preImportFile().existsSync(), isFalse);
    expect(await service.hasPreImportCopy(), isFalse);
    expect(Directory(p.join(temp.path, BackupService.exportDirName))
        .existsSync(), isFalse);
    expect(Directory(p.join(temp.path, 'share_plus')).existsSync(), isFalse);
  });
}
