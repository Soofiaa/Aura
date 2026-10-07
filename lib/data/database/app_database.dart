import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../domain/legacy_period_ends.dart';
import '../../utils/day_key.dart';
import '../models/day_enums.dart';
import 'app_database.steps.dart';

part 'app_database.g.dart';

/// Un dia calendario. La fecha es la clave primaria (texto 'yyyy-MM-dd',
/// ver lib/utils/day_key.dart) en vez de un id autoincremental: a lo sumo
/// un registro por dia, y el upsert por fecha es directo.
@DataClassName('DailyLogRow')
class DailyLogs extends Table {
  TextColumn get date => text()();
  BoolColumn get isPeriodDay =>
      boolean().withDefault(const Constant(false))();
  TextColumn get flow => textEnum<FlowIntensity>().nullable()();
  TextColumn get mood => textEnum<Mood>().nullable()();
  TextColumn get notes => text().nullable()();

  /// true si el valor actual de is_period_day vino de una declaracion
  /// explicita: la pregunta "Sigue tu periodo hoy?" de Inicio o "Quitar
  /// marca" del calendario (CycleRepository.setPeriodDayExplicitly), o el
  /// formulario general unicamente al apagar el interruptor de sangrado
  /// sobre un dia que ya estaba marcado (CycleRepository.upsertDay).
  /// Registrar otros datos en el formulario o marcar dias en el
  /// calendario no lo escribe. Sin esto no se puede distinguir
  /// "explicitamente no sangro" de "no se declaro nada sobre sangrado"
  /// cuando is_period_day=false (ver fase de registro rapido de fin de
  /// periodo).
  BoolColumn get periodDayExplicit =>
      boolean().withDefault(const Constant(false))();

  /// Fin del periodo (decision D-1): se guarda solo en el ULTIMO dia de
  /// sangrado, con su origen (declared / inferred). Un period_end en un
  /// dia interior no cuenta (R-4). El CHECK va en la columna, no en la
  /// tabla, para que una base nueva y una migrada (ADD COLUMN) tengan el
  /// mismo schema; impide guardarlo en un dia sin sangrado.
  // El getter se nombra a si mismo en check(): es el patron de drift. Los
  // getters de esta clase solo los lee drift_dev; en ejecucion se usa el
  // closure del codigo generado.
  TextColumn get periodEnd => textEnum<PeriodEndSource>()
      .nullable()
      // ignore: recursive_getters
      .check(periodEnd.isNull() | isPeriodDay.equals(true))();

  @override
  Set<Column> get primaryKey => {date};

  // Regla de negocio: flow != null implica is_period_day = true. Se
  // aplica tambien en CycleRepository antes de escribir, pero se deja
  // como CHECK para que ninguna escritura directa a la tabla pueda
  // violarla.
  @override
  List<String> get customConstraints => [
        'CHECK ((flow IS NULL) OR (is_period_day = 1))',
      ];
}

@DataClassName('DailyLogSymptomRow')
class DailyLogSymptoms extends Table {
  TextColumn get logDate => text()();
  TextColumn get symptom => textEnum<Symptom>()();

  @override
  Set<Column> get primaryKey => {logDate, symptom};

  // Declarado como SQL crudo en vez de .references(): con drift 2.20 ese
  // helper no genero la clausula REFERENCES (ver commit), asi que se usa
  // la forma explicita que si se verifico que aparece en el CREATE TABLE.
  @override
  List<String> get customConstraints => [
        'FOREIGN KEY (log_date) REFERENCES daily_logs (date) ON DELETE CASCADE',
      ];
}

/// Fila unica de ajustes de la app. dark_mode y default_cycle_length se
/// dejan fuera deliberadamente por ahora (ver fase 2, punto 4).
@DataClassName('AppSettingsRow')
class AppSettings extends Table {
  IntColumn get id => integer().withDefault(const Constant(0))();
  BoolColumn get onboardingSeen =>
      boolean().withDefault(const Constant(false))();

  /// Interruptor GENERAL de notificaciones (controla el permiso de
  /// Android y si se programa cualquier aviso). No es especifico del
  /// recordatorio de periodo; ver [periodReminderEnabled] para eso.
  /// Default false: las notificaciones son opt-in, no opt-out.
  BoolColumn get notificationsEnabled =>
      boolean().withDefault(const Constant(false))();

  BoolColumn get periodReminderEnabled =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get fertileWindowRemindersEnabled =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get showDetailsEnabled =>
      boolean().withDefault(const Constant(false))();
  IntColumn get reminderHour => integer().withDefault(const Constant(9))();
  IntColumn get reminderMinute => integer().withDefault(const Constant(0))();

  /// Duracion habitual del periodo en dias (HU-01): 1 a 15, por defecto 5.
  /// La usa el predictor cuando no hay periodos cerrados (P-1).
  IntColumn get typicalPeriodLength => integer()
      // ignore: recursive_getters
      .check(typicalPeriodLength.isBetweenValues(
          minTypicalPeriodLength, maxTypicalPeriodLength))
      .withDefault(const Constant(defaultTypicalPeriodLength))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (id = 0)'];
}

@DriftDatabase(tables: [DailyLogs, DailyLogSymptoms, AppSettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase()
      : _today = DayKey.today,
        _migrationTestHook = null,
        super(_openConnection());

  /// Constructor para tests: recibe un QueryExecutor propio (tipicamente
  /// NativeDatabase.memory()) en vez de abrir el archivo real en disco.
  /// [today] fija el "hoy" de la migracion a v4 (regla D-2) y
  /// [migrationTestHook] permite simular fallos en puntos de la
  /// migracion.
  AppDatabase.forTesting(
    super.executor, {
    String Function()? today,
    @visibleForTesting
    Future<void> Function(MigrationTestPoint point)? migrationTestHook,
  })  : _today = today ?? DayKey.today,
        _migrationTestHook = migrationTestHook;

  /// "Hoy" ('yyyy-MM-dd') para la regla D-2 de la migracion a v4.
  final String Function() _today;

  final Future<void> Function(MigrationTestPoint point)? _migrationTestHook;

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        // drift NO envuelve onUpgrade en una transaccion: sin esta, un
        // fallo a mitad de camino dejaria columnas nuevas con el
        // user_version viejo, y la apertura siguiente fallaria siempre
        // con "duplicate column". SQLite revierte tambien ALTER TABLE y
        // PRAGMA user_version.
        onUpgrade: (m, from, to) => transaction(() async {
          await _upgradeLegacy(m, from);
          // Pasos generados por drift_dev (app_database.steps.dart) desde
          // el volcado v3: no existen pasos 1->2 ni 2->3 (esos son los
          // bloques escritos a mano), asi que se parte de 3. Cada paso
          // escribe PRAGMA user_version dentro de esta transaccion.
          await m.runMigrationSteps(
            from: math.max(from, 3),
            to: to,
            steps: migrationSteps(from3To4: _from3To4),
          );
        }),
        // PRAGMA foreign_keys se activaba solo via el `setup` del
        // NativeDatabase real; beforeOpen lo garantiza para CUALQUIER
        // QueryExecutor (incluidos los de test que no lo pasen), sin
        // depender de que cada lugar que crea una conexion se acuerde.
        beforeOpen: (details) async {
          await _migrationTestHook?.call(MigrationTestPoint.beforeOpen);
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Migracion 3 -> 4 (decisiones D-1 y D-2). Corre dentro de la
  /// transaccion de onUpgrade.
  ///
  /// Tolera columnas ya existentes: una base v4 abierta por una app v3
  /// queda con user_version 3 y las columnas puestas, y al volver a la v4
  /// un ADD COLUMN repetido fallaria siempre.
  Future<void> _from3To4(Migrator m, Schema4 schema) async {
    // Pasos 1 a 3: columnas nuevas (todas las filas quedan en NULL / 5).
    if (!await _hasColumn('daily_logs', 'period_end')) {
      await m.addColumn(schema.dailyLogs, schema.dailyLogs.periodEnd);
    }
    if (!await _hasColumn('app_settings', 'typical_period_length')) {
      await m.addColumn(
          schema.appSettings, schema.appSettings.typicalPeriodLength);
    }

    // Paso 4: SQL crudo, sin depender de las clases generadas de la app.
    final rows = await customSelect(
      'SELECT date, is_period_day, period_day_explicit, period_end '
      'FROM daily_logs',
    ).get();
    final logCount = rows.length;
    final symptomCount = await _count('daily_log_symptoms');

    // Paso 5: regla D-2 (funcion pura compartida con la conversion de
    // respaldos v3).
    final periodDays = <String>[];
    final explicitNo = <String>[];
    final existingEnds = <String, PeriodEndSource>{};
    for (final row in rows) {
      final date = row.read<String>('date');
      final isPeriodDay = row.read<int>('is_period_day') == 1;
      if (isPeriodDay) {
        periodDays.add(date);
      } else if (row.read<int>('period_day_explicit') == 1) {
        explicitNo.add(date);
      }
      final end = row.readNullable<String>('period_end');
      if (end != null) {
        existingEnds[date] = PeriodEndSource.values.byName(end);
      }
    }
    final toClose = inferLegacyPeriodEnds(
      periodDays: periodDays,
      explicitNonPeriodDays: explicitNo,
      periodEnds: existingEnds,
      today: _today(),
    );

    // Paso 6: solo se escribe period_end; ningun otro dato cambia.
    var updated = 0;
    for (final date in toClose) {
      updated += await customUpdate(
        'UPDATE daily_logs SET period_end = ? '
        'WHERE date = ? AND is_period_day = 1 AND period_end IS NULL',
        variables: [
          Variable<String>(PeriodEndSource.inferred.name),
          Variable<String>(date),
        ],
        updates: {dailyLogs},
      );
    }
    if (updated != toClose.length) {
      throw StateError('migracion v4: se cerraron $updated periodos de '
          '${toClose.length}');
    }
    await _migrationTestHook?.call(MigrationTestPoint.afterPeriodEndUpdate);

    // Paso 7: verificacion antes de confirmar (RNF-2).
    if (await _count('daily_logs') != logCount ||
        await _count('daily_log_symptoms') != symptomCount) {
      throw StateError('migracion v4: cambio la cantidad de filas');
    }
    final orphans = await customSelect('PRAGMA foreign_key_check').get();
    if (orphans.isNotEmpty) {
      throw StateError('migracion v4: foreign_key_check con '
          '${orphans.length} filas');
    }
    final badEnds = await customSelect(
      'SELECT COUNT(*) AS c FROM daily_logs '
      'WHERE period_end IS NOT NULL AND is_period_day = 0',
    ).getSingle();
    if (badEnds.read<int>('c') != 0) {
      throw StateError('migracion v4: period_end en un dia sin sangrado');
    }
    await _migrationTestHook?.call(MigrationTestPoint.afterVerification);
    // Paso 8: runMigrationSteps escribe user_version = 4 al volver.
  }

  Future<bool> _hasColumn(String table, String column) async {
    final columns = await customSelect('PRAGMA table_info($table)').get();
    return columns.any((c) => c.read<String>('name') == column);
  }

  Future<int> _count(String table) async =>
      (await customSelect('SELECT COUNT(*) AS c FROM $table').getSingle())
          .read<int>('c');

  /// Migraciones v1 -> v3, escritas a mano antes de los pasos generados.
  Future<void> _upgradeLegacy(Migrator m, int from) async {
    if (from < 2) {
      await m.addColumn(appSettings, appSettings.periodReminderEnabled);
      await m.addColumn(
          appSettings, appSettings.fertileWindowRemindersEnabled);
      await m.addColumn(appSettings, appSettings.showDetailsEnabled);
      await m.addColumn(appSettings, appSettings.reminderHour);
      await m.addColumn(appSettings, appSettings.reminderMinute);
      // notifications_enabled pasa de default true a default false
      // (opt-in): las filas que ya existian deben quedar en false,
      // no heredar el default viejo.
      await (update(appSettings)..where((t) => t.id.equals(0)))
          .write(const AppSettingsCompanion(
        notificationsEnabled: Value(false),
      ));
    }
    if (from < 3) {
      // Default false para todas las filas existentes es correcto:
      // antes de esta version no existia ningun camino de codigo
      // que escribiera una negacion EXPLICITA de sangrado, asi que
      // no hay dato historico que reinterpretar.
      await m.addColumn(dailyLogs, dailyLogs.periodDayExplicit);
    }
  }
}

/// Puntos de la migracion a v4 donde un test puede simular un fallo
/// (ver [AppDatabase.forTesting]).
enum MigrationTestPoint {
  /// Paso 6: despues de escribir period_end, dentro de la transaccion.
  afterPeriodEndUpdate,

  /// Paso 7: despues de la verificacion, dentro de la transaccion.
  afterVerification,

  /// En beforeOpen: despues de confirmar la transaccion de onUpgrade y
  /// antes de que drift escriba user_version por su cuenta.
  beforeOpen,
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'aura.sqlite'));
    return NativeDatabase.createInBackground(file, setup: enableForeignKeys);
  });
}

/// SQLite no aplica ON DELETE CASCADE salvo que foreign_keys este
/// activado explicitamente por conexion; sin esto, borrar un daily_log
/// dejaria huerfanas sus filas en daily_log_symptoms. Publica a proposito:
/// cualquier QueryExecutor nuevo (incluidos los de test) debe pasar esto
/// como `setup`, o el cascade declarado en el esquema no se aplica de
/// verdad.
void enableForeignKeys(Database database) {
  database.execute('PRAGMA foreign_keys = ON');
}
