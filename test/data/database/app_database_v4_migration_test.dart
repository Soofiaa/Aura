import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/models/day_enums.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/domain/backup_codec.dart';
import '../../drift/aura/generated/schema.dart';

/// Una fila de daily_logs (y sus sintomas) para armar una base v3.
class _Row {
  const _Row(
    this.date, {
    this.period = false,
    this.explicit = false,
    this.flow,
    this.mood,
    this.notes,
    this.symptoms = const [],
  });

  final String date;
  final bool period;
  final bool explicit;
  final String? flow;
  final String? mood;
  final String? notes;
  final List<String> symptoms;
}

_Row _p(String date) => _Row(date, period: true);
_Row _no(String date) => _Row(date, explicit: true);

const _today = '2026-10-07';

late SchemaVerifier _verifier;

/// Base con el schema v3 exacto (volcado de drift_schemas) y user_version 3.
Future<InitializedSchema> _v3(
  List<_Row> rows, {
  BackupSettings? settings,
}) async {
  final schema = await _verifier.schemaAt(3);
  final raw = schema.rawDatabase;
  for (final r in rows) {
    raw.execute(
      'INSERT INTO daily_logs (date, is_period_day, flow, mood, notes, '
      'period_day_explicit) VALUES (?, ?, ?, ?, ?, ?)',
      [r.date, r.period ? 1 : 0, r.flow, r.mood, r.notes, r.explicit ? 1 : 0],
    );
    for (final s in r.symptoms) {
      raw.execute(
          'INSERT INTO daily_log_symptoms (log_date, symptom) VALUES (?, ?)',
          [r.date, s]);
    }
  }
  if (settings != null) {
    raw.execute(
      'INSERT INTO app_settings (id, onboarding_seen, notifications_enabled, '
      'period_reminder_enabled, fertile_window_reminders_enabled, '
      'show_details_enabled, reminder_hour, reminder_minute) '
      'VALUES (0, ?, ?, ?, ?, ?, ?, ?)',
      [
        settings.onboardingSeen ? 1 : 0,
        settings.notificationsEnabled ? 1 : 0,
        settings.periodReminderEnabled ? 1 : 0,
        settings.fertileWindowRemindersEnabled ? 1 : 0,
        settings.showDetailsEnabled ? 1 : 0,
        settings.reminderHour,
        settings.reminderMinute,
      ],
    );
  }
  return schema;
}

AppDatabase _open(
  InitializedSchema schema, {
  String today = _today,
  Future<void> Function(MigrationTestPoint point)? hook,
}) =>
    AppDatabase.forTesting(
      schema.newConnection(),
      today: () => today,
      migrationTestHook: hook,
    );

/// Abre (y migra) la base, y devuelve el period_end de cada dia que lo
/// tiene.
Future<Map<String, PeriodEndSource>> _migrateAndReadEnds(
  InitializedSchema schema, {
  String today = _today,
}) async {
  final db = _open(schema, today: today);
  final rows = await db.select(db.dailyLogs).get();
  await db.close();
  return {
    for (final r in rows)
      if (r.periodEnd != null) r.date: r.periodEnd!,
  };
}

List<String> _columns(InitializedSchema schema, String table) => [
      for (final row in schema.rawDatabase.select('PRAGMA table_info($table)'))
        row['name'] as String,
    ];

int _rawCount(InitializedSchema schema, String table) =>
    schema.rawDatabase.select('SELECT COUNT(*) AS c FROM $table').single['c']
        as int;

/// Intenta abrir la base y espera que falle (la migracion se interrumpe).
Future<void> _openExpectingFailure(AppDatabase db) async {
  await expectLater(db.customSelect('SELECT 1').get(), throwsA(anything));
  await db.close();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUpAll(() {
    _verifier = SchemaVerifier(GeneratedHelper());
  });

  test('la base v3 de partida tiene user_version 3 y no tiene las columnas '
      'nuevas', () async {
    final schema = await _v3([]);
    expect(schema.rawDatabase.userVersion, 3);
    expect(_columns(schema, 'daily_logs'), isNot(contains('period_end')));
  });

  group('migracion con los datos de backup_v3.json', () {
    late BackupData fixture;

    setUpAll(() {
      final result = decodeBackup(
          utf8.encode(File('test/fixtures/backup_v3.json').readAsStringSync()));
      fixture = (result as BackupParseSuccess).data;
    });

    test(
        'conserva las 7 filas y los 9 sintomas campo por campo, no escribe '
        'ningun period_end y deja typical_period_length en 5', () async {
      final schema = await _v3(
        [
          for (final d in fixture.days)
            _Row(
              d.date,
              period: d.isPeriodDay,
              explicit: d.periodDayExplicit,
              flow: d.flow?.name,
              mood: d.mood?.name,
              notes: d.notes,
              symptoms: [for (final s in d.symptoms) s.name],
            ),
        ],
        settings: fixture.settings,
      );

      final db = _open(schema, today: '2026-10-04');
      final rows = await (db.select(db.dailyLogs)
            ..orderBy([(t) => OrderingTerm.asc(t.date)]))
          .get();
      final symptoms = await db.select(db.dailyLogSymptoms).get();
      final settings = await db.select(db.appSettings).getSingle();
      await db.close();

      expect(schema.rawDatabase.userVersion, 4);
      expect(rows, hasLength(7));
      expect(symptoms, hasLength(9));
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final day = fixture.days[i];
        expect(row.date, day.date);
        expect(row.isPeriodDay, day.isPeriodDay, reason: day.date);
        expect(row.periodDayExplicit, day.periodDayExplicit, reason: day.date);
        expect(row.flow, day.flow, reason: day.date);
        expect(row.mood, day.mood, reason: day.date);
        expect(row.notes, day.notes, reason: day.date);
        expect(row.periodEnd, isNull,
            reason: 'el fixture no ejercita D-2 (H-5): ${day.date}');
        expect(
          {
            for (final s in symptoms)
              if (s.logDate == day.date) s.symptom,
          },
          day.symptoms.toSet(),
          reason: day.date,
        );
      }
      final s = fixture.settings;
      expect(settings.onboardingSeen, s.onboardingSeen);
      expect(settings.notificationsEnabled, s.notificationsEnabled);
      expect(settings.periodReminderEnabled, s.periodReminderEnabled);
      expect(settings.fertileWindowRemindersEnabled,
          s.fertileWindowRemindersEnabled);
      expect(settings.showDetailsEnabled, s.showDetailsEnabled);
      expect(settings.reminderHour, s.reminderHour);
      expect(settings.reminderMinute, s.reminderMinute);
      expect(settings.typicalPeriodLength, 5);
    });
  });

  group('casos borde de la regla D-2 sobre una base real', () {
    test('base vacia (sin dias ni fila de ajustes)', () async {
      final schema = await _v3([]);
      final db = _open(schema);
      final repo = CycleRepository(db);
      expect(await repo.getDerivedCycles(), isEmpty);
      expect(await repo.getTypicalPeriodLength(), 5);
      await db.close();
      expect(schema.rawDatabase.userVersion, 4);
      expect(_columns(schema, 'daily_logs'), contains('period_end'));
      expect(_columns(schema, 'app_settings'),
          contains('typical_period_length'));
    });

    test(
        'fila sin sangrado, sin "no" explicito y con notas vacias: no forma '
        'un periodo y la migracion la conserva', () async {
      final schema = await _v3([const _Row('2026-09-15', notes: '')]);
      final db = _open(schema);
      final repo = CycleRepository(db);
      final rows = await db.select(db.dailyLogs).get();
      expect(rows, hasLength(1));
      expect(rows.single.isPeriodDay, isFalse);
      expect(rows.single.periodDayExplicit, isFalse);
      expect(rows.single.notes, '');
      expect(rows.single.periodEnd, isNull);
      expect(await repo.getDerivedCycles(), isEmpty);
      await db.close();
    });

    test(
        'historial mixto: solo se cierran los periodos que cumplen D-2, y '
        'ningun otro dato cambia', () async {
      final rows = [
        // 1. Cerrado por un "no" explicito: no se escribe nada.
        _p('2026-03-01'), _p('2026-03-02'), _p('2026-03-03'),
        _no('2026-03-04'),
        // 2. Hueco de 1 dia con una fila de sintomas (sin sangrado) en el
        //    hueco: se cierra en el 04-01.
        _p('2026-03-29'), _p('2026-03-30'),
        const _Row('2026-03-31', notes: '', symptoms: ['cansancio']),
        _p('2026-04-01'),
        // 3. Hueco de 2 dias: abierto.
        _p('2026-04-26'), _p('2026-04-27'), _p('2026-04-30'), _p('2026-05-01'),
        // 4. Un solo dia: abierto.
        _p('2026-05-24'),
        // 5. Muy largo (20 dias seguidos): se cierra (D-2 no pone tope).
        for (var d = 20; d <= 30; d++) _p('2026-06-$d'),
        for (var d = 1; d <= 9; d++) _p('2026-07-0$d'),
        // 6. "No" explicito dentro del periodo y un "si" explicito: se
        //    cierra en su ultimo dia, el 08-24.
        _p('2026-08-20'),
        const _Row('2026-08-21', period: true, explicit: true),
        _no('2026-08-22'), _p('2026-08-23'), _p('2026-08-24'),
        // 7. En curso (el mas reciente termina hoy): abierto.
        _p('2026-10-05'), _p('2026-10-06'), _p(_today),
      ];
      final schema = await _v3(rows);
      final logsBefore = _rawCount(schema, 'daily_logs');

      final db = _open(schema);
      final after = {
        for (final r in await db.select(db.dailyLogs).get()) r.date: r,
      };
      final cycles = await CycleRepository(db).getDerivedCycles();
      await db.close();

      expect(after, hasLength(logsBefore));
      expect(_rawCount(schema, 'daily_log_symptoms'), 1);
      expect(
        {
          for (final r in after.values)
            if (r.periodEnd != null) r.date: r.periodEnd,
        },
        {
          '2026-04-01': PeriodEndSource.inferred,
          '2026-07-09': PeriodEndSource.inferred,
          '2026-08-24': PeriodEndSource.inferred,
        },
      );
      for (final r in rows) {
        final row = after[r.date]!;
        expect(row.isPeriodDay, r.period, reason: r.date);
        expect(row.periodDayExplicit, r.explicit, reason: r.date);
        expect(row.notes, r.notes, reason: r.date);
      }
      expect(cycles.map((c) => c.isClosed),
          [true, true, false, false, true, true, false]);
    });

    test('el mas reciente termino hace exactamente 7 dias: abierto', () async {
      final ends = await _migrateAndReadEnds(
          await _v3([_p('2026-09-29'), _p('2026-09-30')]));
      expect(ends, isEmpty);
    });

    test('el mas reciente termino hace mas de 7 dias, con 2 dias: cerrado',
        () async {
      final ends = await _migrateAndReadEnds(
          await _v3([_p('2026-09-28'), _p('2026-09-29')]));
      expect(ends, {'2026-09-29': PeriodEndSource.inferred});
    });

    test('el mas reciente de 1 solo dia, de hace mas de 7 dias: abierto',
        () async {
      final ends = await _migrateAndReadEnds(await _v3([_p('2026-09-01')]));
      expect(ends, isEmpty);
    });

    test('dias con fecha futura: el periodo futuro queda abierto', () async {
      final ends = await _migrateAndReadEnds(await _v3([
        _p('2026-08-01'), _p('2026-08-02'),
        _p('2027-03-10'), _p('2027-03-11'),
      ]));
      expect(ends, {'2026-08-02': PeriodEndSource.inferred});
    });

    test('"hoy" sale del reloj inyectado', () async {
      final rows = [_p('2026-09-28'), _p('2026-09-29')];
      expect(await _migrateAndReadEnds(await _v3(rows), today: '2026-10-07'),
          {'2026-09-29': PeriodEndSource.inferred});
      expect(await _migrateAndReadEnds(await _v3(rows), today: '2026-10-06'),
          isEmpty);
    });
  });

  group('atomicidad: un fallo dentro de la transaccion deja la base en v3',
      () {
    for (final point in [
      MigrationTestPoint.afterPeriodEndUpdate,
      MigrationTestPoint.afterVerification,
    ]) {
      test('fallo en ${point.name}', () async {
        final schema = await _v3([
          _p('2026-08-01'), _p('2026-08-02'),
          const _Row('2026-08-10', notes: 'nota', symptoms: ['acne']),
        ]);

        await _openExpectingFailure(_open(schema, hook: (p) async {
          if (p == point) throw StateError('falla simulada');
        }));

        expect(schema.rawDatabase.userVersion, 3);
        expect(_columns(schema, 'daily_logs'), isNot(contains('period_end')));
        expect(_columns(schema, 'app_settings'),
            isNot(contains('typical_period_length')));
        expect(_rawCount(schema, 'daily_logs'), 3);
        expect(_rawCount(schema, 'daily_log_symptoms'), 1);

        // Al reintentar sin el fallo, migra bien.
        expect(await _migrateAndReadEnds(schema),
            {'2026-08-02': PeriodEndSource.inferred});
        expect(schema.rawDatabase.userVersion, 4);
      });
    }
  });

  group('user_version despues de confirmar la transaccion', () {
    test(
        'fallo en beforeOpen (transaccion ya confirmada): user_version ya es '
        '4, porque el paso lo escribe dentro de la transaccion; al reabrir no '
        'se repite nada', () async {
      final schema = await _v3([_p('2026-08-01'), _p('2026-08-02')]);

      await _openExpectingFailure(_open(schema, hook: (p) async {
        if (p == MigrationTestPoint.beforeOpen) {
          throw StateError('falla simulada');
        }
      }));

      expect(schema.rawDatabase.userVersion, 4);
      expect(_columns(schema, 'daily_logs'), contains('period_end'));
      expect(await _migrateAndReadEnds(schema),
          {'2026-08-02': PeriodEndSource.inferred});
    });

    test(
        'la ventana "transaccion confirmada, user_version aun en 3" (por '
        'ejemplo, una base v4 abierta por una app v3): la migracion tolera '
        'las columnas existentes y no vuelve a escribir cierres', () async {
      final schema = await _v3([
        _p('2026-08-01'), _p('2026-08-02'), // se cierra (inferred)
        _p('2026-09-01'), _p('2026-09-02'), // se marcara declared a mano
      ], settings: null);
      // Primera migracion completa.
      expect(await _migrateAndReadEnds(schema, today: '2026-08-20'),
          {'2026-08-02': PeriodEndSource.inferred});
      // Estado de la ventana: columnas v4 confirmadas, user_version 3, y
      // datos escritos mientras tanto (un fin declarado, un ajuste).
      final raw = schema.rawDatabase;
      raw.execute("UPDATE daily_logs SET period_end = 'declared' "
          "WHERE date = '2026-09-02'");
      raw.execute('INSERT INTO app_settings (id, typical_period_length) '
          'VALUES (0, 7)');
      raw.userVersion = 3;

      final db = _open(schema);
      final repo = CycleRepository(db);
      final ends = {
        for (final r in await db.select(db.dailyLogs).get())
          if (r.periodEnd != null) r.date: r.periodEnd!,
      };
      expect(await repo.getTypicalPeriodLength(), 7);
      await db.close();

      expect(raw.userVersion, 4);
      expect(ends, {
        '2026-08-02': PeriodEndSource.inferred,
        '2026-09-02': PeriodEndSource.declared,
      });
      expect(
          _columns(schema, 'daily_logs')
              .where((c) => c == 'period_end')
              .length,
          1);
    });
  });

  group('CHECK de las columnas nuevas', () {
    Future<void> expectChecks(AppDatabase db) async {
      await db.into(db.dailyLogs).insert(DailyLogsCompanion.insert(
            date: '2026-08-01',
            isPeriodDay: const Value(true),
            periodEnd: const Value(PeriodEndSource.declared),
          ));
      await expectLater(
        db.into(db.dailyLogs).insert(DailyLogsCompanion.insert(
              date: '2026-08-02',
              periodEnd: const Value(PeriodEndSource.declared),
            )),
        throwsA(isA<SqliteException>()),
        reason: 'period_end en un dia sin sangrado',
      );
      await expectLater(
        (db.update(db.dailyLogs)..where((t) => t.date.equals('2026-08-01')))
            .write(const DailyLogsCompanion(isPeriodDay: Value(false))),
        throwsA(isA<SqliteException>()),
        reason: 'quitar el sangrado sin limpiar period_end',
      );
      for (final invalid in [0, 16]) {
        await expectLater(
          db.into(db.appSettings).insertOnConflictUpdate(AppSettingsCompanion(
                id: const Value(0),
                typicalPeriodLength: Value(invalid),
              )),
          throwsA(isA<SqliteException>()),
          reason: 'typical_period_length $invalid',
        );
      }
      for (final valid in [1, 15]) {
        await db.into(db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion(
                id: const Value(0), typicalPeriodLength: Value(valid)));
      }
    }

    test('en una base nueva', () async {
      final db = AppDatabase.forTesting(
          NativeDatabase.memory(setup: enableForeignKeys));
      await expectChecks(db);
      await db.close();
    });

    test('en una base migrada desde v3', () async {
      final db = _open(await _v3([]));
      await expectChecks(db);
      await db.close();
    });
  });
}
