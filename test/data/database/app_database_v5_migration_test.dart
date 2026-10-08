import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/models/day_enums.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/domain/backup_codec.dart';
import 'package:aura/domain/cycle_deriver.dart';
import 'package:aura/domain/cycle_predictor.dart';
import '../../drift/aura/generated/schema.dart';

/// HU-05, CP5a: migracion 4 -> 5 (show_fertile_window). Datos inventados
/// (test/fixtures/backup_v4.json). Cada test cierra su base.

late SchemaVerifier _verifier;

/// Posterior al ultimo dia del fixture v4 (2026-07-28).
const _today = '2026-08-05';

BackupData _fixtureV4() {
  final result = decodeBackup(
    utf8.encode(File('test/fixtures/backup_v4.json').readAsStringSync()),
  );
  return (result as BackupParseSuccess).data;
}

/// Base con el schema v4 exacto (volcado de drift_schemas) y user_version
/// 4, con los dias del fixture v4 y ajustes no predeterminados (o sin
/// fila de ajustes si [withSettings] es false).
Future<InitializedSchema> _v4({
  bool withData = true,
  bool withSettings = true,
}) async {
  final schema = await _verifier.schemaAt(4);
  final raw = schema.rawDatabase;
  if (withData) {
    for (final d in _fixtureV4().days) {
      raw.execute(
        'INSERT INTO daily_logs (date, is_period_day, flow, mood, notes, '
        'period_day_explicit, period_end) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          d.date,
          d.isPeriodDay ? 1 : 0,
          d.flow?.name,
          d.mood?.name,
          d.notes,
          d.periodDayExplicit ? 1 : 0,
          d.periodEnd?.name,
        ],
      );
      for (final s in d.symptoms) {
        raw.execute(
          'INSERT INTO daily_log_symptoms (log_date, symptom) VALUES (?, ?)',
          [d.date, s.name],
        );
      }
    }
  }
  if (withSettings) {
    raw.execute(
      'INSERT INTO app_settings (id, onboarding_seen, notifications_enabled, '
      'period_reminder_enabled, fertile_window_reminders_enabled, '
      'show_details_enabled, reminder_hour, reminder_minute, '
      'typical_period_length) VALUES (0, 1, 1, 0, 1, 1, 21, 30, 7)',
    );
  }
  return schema;
}

AppDatabase _open(
  InitializedSchema schema, {
  Future<void> Function(MigrationTestPoint point)? hook,
}) => AppDatabase.forTesting(
  schema.newConnection(),
  today: () => _today,
  migrationTestHook: hook,
);

/// Todas las filas de las tres tablas, con todas las columnas que ya
/// existian en v4 (sin show_fertile_window), en orden estable.
Map<String, List<Map<String, Object?>>> _dumpV4Columns(
  InitializedSchema schema,
) {
  final raw = schema.rawDatabase;
  List<Map<String, Object?>> rows(String sql) => [
    for (final r in raw.select(sql))
      {
        for (final c in r.keys)
          if (c != 'show_fertile_window') c: r[c],
      },
  ];
  return {
    'daily_logs': rows('SELECT * FROM daily_logs ORDER BY date'),
    'daily_log_symptoms': rows(
      'SELECT * FROM daily_log_symptoms ORDER BY log_date, symptom',
    ),
    'app_settings': rows('SELECT * FROM app_settings ORDER BY id'),
  };
}

List<String> _columns(InitializedSchema schema, String table) => [
  for (final row in schema.rawDatabase.select('PRAGMA table_info($table)'))
    row['name'] as String,
];

/// Las entradas del predictor leidas en crudo de una base v4, igual que
/// CycleRepository._deriveFromRows (sin pasar por el codigo v5).
({List<CycleSummary> cycles, int typical}) _rawInputs(
  InitializedSchema schema,
) {
  final raw = schema.rawDatabase;
  final rows = raw.select(
    'SELECT date, is_period_day, period_day_explicit, period_end '
    'FROM daily_logs',
  );
  final cycles = deriveCycles(
    [
      for (final r in rows)
        if (r['is_period_day'] == 1) r['date'] as String,
    ],
    explicitNonPeriodDays: [
      for (final r in rows)
        if (r['is_period_day'] == 0 && r['period_day_explicit'] == 1)
          r['date'] as String,
    ],
    periodEnds: {
      for (final r in rows)
        if (r['period_end'] != null)
          r['date'] as String: PeriodEndSource.values.byName(
            r['period_end'] as String,
          ),
    },
  );
  final typical =
      raw
              .select('SELECT typical_period_length AS t FROM app_settings')
              .single['t']
          as int;
  return (cycles: cycles, typical: typical);
}

Future<void> _openExpectingFailure(AppDatabase db) async {
  await expectLater(db.customSelect('SELECT 1').get(), throwsA(anything));
  await db.close();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUpAll(() {
    _verifier = SchemaVerifier(GeneratedHelper());
  });

  test(
    'la base v4 de partida: user_version 4, sin la columna, con datos',
    () async {
      final schema = await _v4();
      expect(schema.rawDatabase.userVersion, 4);
      expect(
        _columns(schema, 'app_settings'),
        isNot(contains('show_fertile_window')),
      );
      final dump = _dumpV4Columns(schema);
      expect(dump['daily_logs'], hasLength(8));
      expect(dump['daily_log_symptoms'], hasLength(3));
      expect(dump['app_settings'], hasLength(1));
      schema.rawDatabase.dispose();
    },
  );

  group('a) migracion v4 -> v5 con datos', () {
    test('las filas existentes no cambian (todas las columnas v4) y el '
        'interruptor queda en true', () async {
      final schema = await _v4();
      final before = _dumpV4Columns(schema);

      final db = _open(schema);
      final repo = CycleRepository(db);
      expect(await repo.getShowFertileWindow(), isTrue);
      expect((await repo.getPredictionInputs()).showFertileWindow, isTrue);
      expect((await repo.getNotificationSettings()).showFertileWindow, isTrue);
      // Ajustes previos leidos por la app, sin cambios.
      final n = await repo.getNotificationSettings();
      expect(n.notificationsEnabled, isTrue);
      expect(n.periodReminderEnabled, isFalse);
      expect(n.fertileWindowRemindersEnabled, isTrue);
      expect(n.showDetailsEnabled, isTrue);
      expect((n.reminderHour, n.reminderMinute), (21, 30));
      expect(await repo.getTypicalPeriodLength(), 7);
      await db.close();

      expect(schema.rawDatabase.userVersion, 5);
      expect(_dumpV4Columns(schema), before);
      expect(
        schema.rawDatabase
            .select('SELECT show_fertile_window AS v FROM app_settings')
            .map((r) => r['v'])
            .toList(),
        [1],
      );
    });

    test(
      'predictCycle da el mismo resultado antes y despues de migrar',
      () async {
        final schema = await _v4();
        final before = _rawInputs(schema);
        final predBefore = predictCycle(
          cycles: before.cycles,
          today: _today,
          config: PredictionConfig(typicalPeriodLengthDays: before.typical),
        );

        final db = _open(schema);
        final inputs = await CycleRepository(db).getPredictionInputs();
        await db.close();

        expect(inputs.cycles, before.cycles);
        expect(inputs.typicalPeriodLengthDays, before.typical);
        final predAfter = predictCycle(
          cycles: inputs.cycles,
          today: _today,
          config: inputs.config,
        );
        expect(predBefore, isA<ActivePrediction>());
        expect(predAfter, predBefore);
        // Inicios 06-02, 06-30 y 07-28: dos ciclos de 28 dias.
        expect(
          (predAfter as ActivePrediction).nextPeriodExpectedDate,
          '2026-08-25',
        );
      },
    );

    test('base v4 vacia (sin dias ni fila de ajustes): migra y el ajuste se '
        'crea en true', () async {
      final schema = await _v4(withData: false, withSettings: false);
      final db = _open(schema);
      expect(await CycleRepository(db).getShowFertileWindow(), isTrue);
      await db.close();
      expect(schema.rawDatabase.userVersion, 5);
      expect(_columns(schema, 'app_settings'), contains('show_fertile_window'));
    });

    test(
      'v3 -> v5 en una sola apertura: agrega las columnas de v4 y v5',
      () async {
        final schema = await _verifier.schemaAt(3);
        schema.rawDatabase.execute(
          'INSERT INTO daily_logs (date, is_period_day) VALUES (?, 1)',
          ['2026-08-01'],
        );
        final db = _open(schema);
        expect(await CycleRepository(db).getShowFertileWindow(), isTrue);
        await db.close();
        expect(schema.rawDatabase.userVersion, 5);
        expect(_columns(schema, 'daily_logs'), contains('period_end'));
        expect(
          _columns(schema, 'app_settings'),
          containsAll(['typical_period_length', 'show_fertile_window']),
        );
      },
    );
  });

  group('b) atomicidad', () {
    test('un fallo despues de agregar la columna deja la base en v4 intacta; '
        'al reintentar migra', () async {
      final schema = await _v4();
      final before = _dumpV4Columns(schema);

      await _openExpectingFailure(
        _open(
          schema,
          hook: (p) async {
            if (p == MigrationTestPoint.afterV5Column) {
              throw StateError('falla simulada');
            }
          },
        ),
      );

      expect(schema.rawDatabase.userVersion, 4);
      expect(
        _columns(schema, 'app_settings'),
        isNot(contains('show_fertile_window')),
      );
      expect(_dumpV4Columns(schema), before);

      final db = _open(schema);
      expect(await CycleRepository(db).getShowFertileWindow(), isTrue);
      await db.close();
      expect(schema.rawDatabase.userVersion, 5);
      expect(_dumpV4Columns(schema), before);
    });
  });

  group('c) migracion repetida o con la columna ya presente', () {
    test('columna ya presente con user_version 4: no falla y no pisa el '
        'valor guardado', () async {
      final schema = await _v4();
      var db = _open(schema);
      await CycleRepository(db).setShowFertileWindow(false);
      await db.close();
      // Como si una app anterior hubiera dejado user_version en 4 con la
      // columna ya agregada.
      schema.rawDatabase.userVersion = 4;

      db = _open(schema);
      expect(await CycleRepository(db).getShowFertileWindow(), isFalse);
      await db.close();
      expect(schema.rawDatabase.userVersion, 5);
      expect(
        _columns(
          schema,
          'app_settings',
        ).where((c) => c == 'show_fertile_window'),
        hasLength(1),
      );
    });

    test('abrir dos veces una base ya migrada no repite nada', () async {
      final schema = await _v4();
      for (var i = 0; i < 2; i++) {
        final db = _open(schema);
        expect(await CycleRepository(db).getShowFertileWindow(), isTrue);
        await db.close();
        expect(schema.rawDatabase.userVersion, 5);
      }
    });
  });

  test('CHECK: show_fertile_window solo admite 0 o 1', () async {
    final schema = await _v4();
    final db = _open(schema);
    await db.customSelect('SELECT 1').get();
    await db.close();
    expect(
      () => schema.rawDatabase.execute(
        'UPDATE app_settings SET show_fertile_window = 2',
      ),
      throwsA(isA<SqliteException>()),
    );
  });
}
