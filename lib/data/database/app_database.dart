import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/day_enums.dart';

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
  BoolColumn get notificationsEnabled =>
      boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (id = 0)'];
}

@DriftDatabase(tables: [DailyLogs, DailyLogSymptoms, AppSettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Constructor para tests: recibe un QueryExecutor propio (tipicamente
  /// NativeDatabase.memory()) en vez de abrir el archivo real en disco.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;
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
