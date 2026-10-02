import 'package:drift/drift.dart';

import '../../domain/cycle_deriver.dart';
import '../../domain/cycle_predictor.dart';
import '../../utils/day_key.dart';
import '../database/app_database.dart';
import '../models/day_enums.dart';

/// Unica capa que toca drift. Pantallas y servicios (incluida la fase 3
/// de prediccion) dependen de esta clase, nunca de AppDatabase
/// directamente.
class CycleRepository {
  CycleRepository(this._db);

  final AppDatabase _db;

  Future<DailyLogRow?> getDay(String date) {
    return (_db.select(_db.dailyLogs)..where((t) => t.date.equals(date)))
        .getSingleOrNull();
  }

  Future<Set<Symptom>> getSymptomsForDay(String date) async {
    final rows = await (_db.select(_db.dailyLogSymptoms)
          ..where((t) => t.logDate.equals(date)))
        .get();
    return rows.map((r) => r.symptom).toSet();
  }

  /// Upsert por fecha para el formulario de add_cycle_screen.
  ///
  /// Semantica decidida para no desmarcar un dia de sangrado por
  /// accidente (ver fase 2, conflicto flow/period):
  /// - Si [isPeriodDaySwitch] es true: is_period_day pasa a true y flow
  ///   se fija a [flow] (lo que haya elegido el dropdown).
  /// - Si [isPeriodDaySwitch] es false: is_period_day y flow se
  ///   CONSERVAN tal como estaban (no se fuerzan a false/null). Esto
  ///   cubre el caso "dia marcado como periodo desde el calendario, luego
  ///   se guarda un registro de sintomas con el interruptor apagado": el
  ///   dia sigue siendo un dia de periodo, con el mismo flow que tenia.
  ///   Si el dia no existia antes, queda is_period_day=false, flow=null,
  ///   como es natural.
  ///
  /// mood, notes y symptoms siempre se sobrescriben con lo que llega
  /// (el formulario siempre presenta un valor actual para esos campos,
  /// a diferencia del interruptor de sangrado).
  Future<void> upsertDay({
    required String date,
    required bool isPeriodDaySwitch,
    FlowIntensity? flow,
    Mood? mood,
    String? notes,
    Set<Symptom> symptoms = const {},
  }) async {
    await _db.transaction(() async {
      final existing = await getDay(date);

      final effectiveIsPeriodDay =
          isPeriodDaySwitch ? true : (existing?.isPeriodDay ?? false);
      final effectiveFlow = isPeriodDaySwitch ? flow : existing?.flow;

      await _db.into(_db.dailyLogs).insertOnConflictUpdate(
            DailyLogsCompanion(
              date: Value(date),
              isPeriodDay: Value(effectiveIsPeriodDay),
              flow: Value(effectiveFlow),
              mood: Value(mood),
              notes: Value(notes),
            ),
          );

      await (_db.delete(_db.dailyLogSymptoms)
            ..where((t) => t.logDate.equals(date)))
          .go();
      if (symptoms.isNotEmpty) {
        await _db.batch((batch) {
          batch.insertAll(_db.dailyLogSymptoms, [
            for (final s in symptoms)
              DailyLogSymptomsCompanion.insert(logDate: date, symptom: s),
          ]);
        });
      }
    });
  }

  /// Marca [date] como dia de sangrado (calendar_screen). No toca flow,
  /// mood, notes ni sintomas de un dia existente. Devuelve false si el
  /// dia ya estaba marcado (para mostrar "ya estaba registrado" como
  /// antes).
  Future<bool> markPeriodDay(String date) async {
    final existing = await getDay(date);
    if (existing?.isPeriodDay == true) return false;

    await _db.into(_db.dailyLogs).insertOnConflictUpdate(
          DailyLogsCompanion(date: Value(date), isPeriodDay: const Value(true)),
        );
    return true;
  }

  Future<List<String>> getPeriodDayDates() async {
    final rows = await (_db.select(_db.dailyLogs)
          ..where((t) => t.isPeriodDay.equals(true)))
        .get();
    return rows.map((r) => r.date).toList();
  }

  Stream<List<String>> watchPeriodDayDates() {
    final query = _db.select(_db.dailyLogs)
      ..where((t) => t.isPeriodDay.equals(true));
    return query.watch().map((rows) => rows.map((r) => r.date).toList());
  }

  Future<List<CycleSummary>> getDerivedCycles() async {
    final dates = await getPeriodDayDates();
    return deriveCycles(dates);
  }

  /// Prediccion para "hoy" (reloj real). El motor (predictCycle) sigue
  /// siendo puro y testeable por separado; este metodo solo lo conecta
  /// con los datos reales, igual que getDerivedCycles() envuelve
  /// deriveCycles().
  Future<CyclePrediction?> getPrediction({
    PredictionConfig config = const PredictionConfig(),
  }) async {
    final cycles = await getDerivedCycles();
    return predictCycle(cycles: cycles, today: DayKey.today(), config: config);
  }

  Future<bool> hasAnyLog() async {
    final countExp = _db.dailyLogs.date.count();
    final query = _db.selectOnly(_db.dailyLogs)..addColumns([countExp]);
    final row = await query.getSingle();
    return (row.read(countExp) ?? 0) > 0;
  }

  // --- Estadisticas (consultas SQL, no agregadas en Dart) ---

  // Nota: se usa SQL crudo (customSelect) en vez de selectOnly()+groupBy()
  // tipado porque GeneratedColumnWithTypeConverter (las columnas
  // textEnum<T>) no es asignable a Expression<T> en drift 2.20 - ver
  // commit. textEnum guarda el .name del enum como texto.
  Future<Map<Symptom, int>> getSymptomFrequency() async {
    final rows = await _db.customSelect(
      'SELECT symptom, COUNT(*) AS c FROM daily_log_symptoms GROUP BY symptom',
      readsFrom: {_db.dailyLogSymptoms},
    ).get();
    return {
      for (final row in rows)
        Symptom.values.byName(row.data['symptom'] as String):
            row.data['c'] as int,
    };
  }

  Future<Map<Mood, int>> getMoodFrequency() async {
    final rows = await _db.customSelect(
      'SELECT mood, COUNT(*) AS c FROM daily_logs WHERE mood IS NOT NULL GROUP BY mood',
      readsFrom: {_db.dailyLogs},
    ).get();
    return {
      for (final row in rows)
        Mood.values.byName(row.data['mood'] as String): row.data['c'] as int,
    };
  }

  /// Promedio de flujo en la escala Ligero=1, Moderado=2, Abundante=3
  /// (misma escala que usaba stats_screen.dart). 0 si no hay datos.
  Future<double> getAverageFlow() async {
    final result = await _db.customSelect(
      '''
      SELECT AVG(
        CASE flow
          WHEN 'ligero' THEN 1
          WHEN 'moderado' THEN 2
          WHEN 'abundante' THEN 3
        END
      ) AS avg_flow
      FROM daily_logs
      WHERE flow IS NOT NULL
      ''',
      readsFrom: {_db.dailyLogs},
    ).getSingleOrNull();
    final value = result?.data['avg_flow'];
    if (value == null) return 0;
    return (value as num).toDouble();
  }

  // --- Ajustes (fila unica) ---

  Future<AppSettingsRow> _ensureSettingsRow() async {
    final existing = await (_db.select(_db.appSettings)
          ..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    if (existing != null) return existing;

    await _db.into(_db.appSettings).insertOnConflictUpdate(
          const AppSettingsCompanion(id: Value(0)),
        );
    return (_db.select(_db.appSettings)..where((t) => t.id.equals(0)))
        .getSingle();
  }

  Future<bool> getOnboardingSeen() async =>
      (await _ensureSettingsRow()).onboardingSeen;

  Future<void> setOnboardingSeen(bool value) async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion(id: const Value(0), onboardingSeen: Value(value)),
        );
  }

  Future<bool> getNotificationsEnabled() async =>
      (await _ensureSettingsRow()).notificationsEnabled;

  Future<void> setNotificationsEnabled(bool value) async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion(
            id: const Value(0),
            notificationsEnabled: Value(value),
          ),
        );
  }

  /// Borra TODAS las tablas (daily_logs, daily_log_symptoms,
  /// app_settings), incluidos los ajustes. Usado por
  /// settings_screen._borrarDatos() tras confirmacion explicita del
  /// usuario.
  Future<void> deleteAllData() async {
    await _db.transaction(() async {
      await _db.delete(_db.dailyLogSymptoms).go();
      await _db.delete(_db.dailyLogs).go();
      await _db.delete(_db.appSettings).go();
    });
  }
}

AppDatabase? _appDatabaseInstance;

/// Instancia unica de AppDatabase para toda la app (no hay DI framework
/// en este proyecto). Las pantallas usan [cycleRepository], no esto
/// directamente.
AppDatabase get appDatabase => _appDatabaseInstance ??= AppDatabase();

CycleRepository? _cycleRepositoryInstance;

CycleRepository get cycleRepository =>
    _cycleRepositoryInstance ??= CycleRepository(appDatabase);
