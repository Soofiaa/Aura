import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/data/database/app_database.dart';
import '../../drift/aura/generated/schema.dart';

/// Migracion 6 -> 7 (respaldo con ajustes del dispositivo): la base no
/// cambia.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('conserva todos los datos de una base v6', () async {
    final schema = await verifier.schemaAt(6);
    final raw = schema.rawDatabase;
    raw.execute("INSERT INTO daily_logs (date, is_period_day, flow, "
        "period_end, notes) VALUES ('2026-07-01', 1, 'moderado', "
        "'declared', 'nota inventada')");
    raw.execute("INSERT INTO daily_logs (date, is_period_day, "
        "period_day_explicit) VALUES ('2026-07-10', 0, 1)");
    raw.execute("INSERT INTO daily_log_symptoms (log_date, symptom) "
        "VALUES ('2026-07-01', 'acne')");
    raw.execute('INSERT INTO app_settings (id, show_fertile_window, '
        'typical_period_length) VALUES (0, 0, 4)');
    raw.execute("INSERT INTO pregnancies (start_date, end_date, outcome) "
        "VALUES ('2025-01-10', '2025-10-01', 'nacimiento')");
    raw.execute("INSERT INTO pregnancies (start_date) "
        "VALUES ('2026-07-28')");
    List<Object?> dump() => [
          for (final t in [
            'daily_logs',
            'daily_log_symptoms',
            'app_settings',
            'pregnancies',
          ])
            raw.select('SELECT * FROM $t').toList(),
        ];
    final before = dump();

    final db = AppDatabase.forTesting(schema.newConnection());
    await db.customSelect('SELECT 1').get();
    await db.close();

    expect(raw.userVersion, 7);
    expect(dump(), before);
  });
}
