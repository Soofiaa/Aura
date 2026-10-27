import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import '../../drift/aura/generated/schema.dart';

/// Migracion 5 -> 6 (modo embarazo): solo crea la tabla pregnancies.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  Future<InitializedSchema> v5() async {
    final schema = await verifier.schemaAt(5);
    final raw = schema.rawDatabase;
    raw.execute("INSERT INTO daily_logs (date, is_period_day, period_end) "
        "VALUES ('2026-07-01', 1, 'declared')");
    raw.execute("INSERT INTO daily_log_symptoms (log_date, symptom) "
        "VALUES ('2026-07-01', 'acne')");
    raw.execute('INSERT INTO app_settings (id, show_fertile_window) '
        'VALUES (0, 0)');
    return schema;
  }

  List<Object?> dump(InitializedSchema schema) => [
        for (final t in ['daily_logs', 'daily_log_symptoms', 'app_settings'])
          schema.rawDatabase.select('SELECT * FROM $t').toList(),
      ];

  test('conserva los datos y crea la tabla vacia', () async {
    final schema = await v5();
    final before = dump(schema);

    final db = AppDatabase.forTesting(schema.newConnection());
    expect(await CycleRepository(db).watchPregnancies().first, isEmpty);
    await db.close();

    expect(schema.rawDatabase.userVersion, 6);
    expect(dump(schema), before);
  });

  test('tolera la tabla ya creada con user_version 5', () async {
    final schema = await v5();
    var db = AppDatabase.forTesting(schema.newConnection());
    await CycleRepository(db).startPregnancy('2026-07-01');
    await db.close();
    schema.rawDatabase.userVersion = 5;

    db = AppDatabase.forTesting(schema.newConnection());
    expect(await CycleRepository(db).watchPregnancies().first, hasLength(1));
    await db.close();
    expect(schema.rawDatabase.userVersion, 6);
  });
}
