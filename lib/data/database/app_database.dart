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

  /// true si el valor actual de is_period_day vino de una accion directa
  /// y dedicada (la pregunta "Sigue tu periodo hoy?" o "Quitar marca" del
  /// calendario), no del formulario general de sintomas. Sin esto no se
  /// puede distinguir "explicitamente no sangro" de "no se declaro nada
  /// sobre sangrado" cuando is_period_day=false (ver fase de registro
  /// rapido de fin de periodo).
  BoolColumn get periodDayExplicit =>
      boolean().withDefault(const Constant(false))();

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
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
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
        },
        // PRAGMA foreign_keys se activaba solo via el `setup` del
        // NativeDatabase real; beforeOpen lo garantiza para CUALQUIER
        // QueryExecutor (incluidos los de test que no lo pasen), sin
        // depender de que cada lugar que crea una conexion se acuerde.
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
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
