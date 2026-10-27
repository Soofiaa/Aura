import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/models/day_enums.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/domain/backup_codec.dart';

/// Modo embarazo, paso 1 (datos): tabla pregnancies y su respaldo.
void main() {
  late AppDatabase db;
  late CycleRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CycleRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<PregnancyRow>> all() => repo.watchPregnancies().first;

  test('iniciar, terminar y volver a iniciar', () async {
    await repo.startPregnancy('2025-01-10');
    expect((await all()).single.endDate, isNull);

    await repo.endPregnancy('2025-10-01', PregnancyOutcome.nacimiento);
    await repo.startPregnancy('2026-07-28');

    final rows = await all();
    expect([for (final r in rows) (r.startDate, r.endDate, r.outcome)], [
      ('2025-01-10', '2025-10-01', PregnancyOutcome.nacimiento),
      ('2026-07-28', null, null),
    ]);
  });

  test('no permite dos activos ni empezar antes del fin del anterior',
      () async {
    await repo.startPregnancy('2025-01-10');
    expect(() => repo.startPregnancy('2026-01-01'), throwsStateError);

    await repo.endPregnancy('2025-10-01', PregnancyOutcome.perdida);
    expect(() => repo.startPregnancy('2025-10-01'), throwsArgumentError);
    expect(await all(), hasLength(1));
  });

  test('terminar sin uno activo falla; terminar antes del inicio lo rechaza '
      'el CHECK', () async {
    expect(() => repo.endPregnancy('2025-10-01', PregnancyOutcome.perdida),
        throwsStateError);
    await repo.startPregnancy('2025-01-10');
    await expectLater(
        repo.endPregnancy('2025-01-09', PregnancyOutcome.sinEspecificar),
        throwsA(isA<SqliteException>()));
    expect((await all()).single.endDate, isNull);
  });

  test('CHECK: endDate y outcome van juntos', () async {
    await expectLater(
      db.customStatement("INSERT INTO pregnancies (start_date, end_date) "
          "VALUES ('2025-01-10', '2025-02-01')"),
      throwsA(isA<SqliteException>()),
    );
  });

  test('borrar un embarazo', () async {
    await repo.startPregnancy('2025-01-10');
    await repo.deletePregnancy('2025-01-10');
    expect(await all(), isEmpty);
  });

  test('respaldo: exportar e importar conserva los embarazos y el sintoma '
      'nuevo', () async {
    final v6 = (decodeBackup(utf8
                .encode(File('test/fixtures/backup_v6.json').readAsStringSync()))
            as BackupParseSuccess)
        .data;
    await repo.startPregnancy('2020-01-01');
    await repo.replaceAllWithBackup(v6);

    final out = await repo.readBackupData(
        appVersion: v6.appVersion, exportedAt: v6.exportedAt);
    expect(out.pregnancies, v6.pregnancies);
    expect(out.days, v6.days);
  });

  test('importar un respaldo v5 deja la tabla vacia', () async {
    final v5 = (decodeBackup(utf8
                .encode(File('test/fixtures/backup_v5.json').readAsStringSync()))
            as BackupParseSuccess)
        .data;
    await repo.startPregnancy('2020-01-01');
    await repo
        .replaceAllWithBackup(upgradeBackupData(v5, today: '2026-10-07'));
    expect(await all(), isEmpty);
  });

  test('deleteAllData borra los embarazos', () async {
    await repo.startPregnancy('2025-01-10');
    await repo.deleteAllData();
    expect(await all(), isEmpty);
  });
}
