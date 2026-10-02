import 'package:drift/drift.dart';

import '../../domain/cycle_deriver.dart';
import '../../domain/notification_planner.dart';
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
  /// Semantica del interruptor de sangrado (ver fase 2, y revisada en la
  /// fase de registro rapido de fin de periodo):
  /// - Si [isPeriodDaySwitch] es true: is_period_day pasa a true, flow se
  ///   fija a [flow], y period_day_explicit se limpia a false (un "si"
  ///   ya no es una negacion).
  /// - Si [isPeriodDaySwitch] es false y el dia YA estaba en true: esto
  ///   solo puede pasar si la usuaria vio el interruptor prellenado en
  ///   "si" (add_cycle_screen prellena desde el dato existente) y lo
  ///   apago a proposito -- es una correccion deliberada, equivalente a
  ///   "Quitar marca" del calendario. is_period_day pasa a false, flow a
  ///   null (el CHECK de la tabla lo exige igual) y period_day_explicit
  ///   a true.
  /// - Si [isPeriodDaySwitch] es false y el dia NO estaba en true (sin
  ///   fila previa, o ya en false): es el default del formulario, no una
  ///   declaracion -- is_period_day se queda en false (o se crea en
  ///   false) y period_day_explicit NO se toca (si ya era true por una
  ///   negacion explicita previa, se mantiene).
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
      final wasExplicitTrue = existing?.isPeriodDay == true;

      final bool effectiveIsPeriodDay;
      final FlowIntensity? effectiveFlow;
      final bool? explicitOverride;

      if (isPeriodDaySwitch) {
        effectiveIsPeriodDay = true;
        effectiveFlow = flow;
        explicitOverride = false;
      } else if (wasExplicitTrue) {
        effectiveIsPeriodDay = false;
        effectiveFlow = null;
        explicitOverride = true;
      } else {
        effectiveIsPeriodDay = existing?.isPeriodDay ?? false;
        effectiveFlow = existing?.flow;
        explicitOverride = null;
      }

      await _db.into(_db.dailyLogs).insertOnConflictUpdate(
            DailyLogsCompanion(
              date: Value(date),
              isPeriodDay: Value(effectiveIsPeriodDay),
              flow: Value(effectiveFlow),
              mood: Value(mood),
              notes: Value(notes),
              periodDayExplicit: explicitOverride == null
                  ? const Value.absent()
                  : Value(explicitOverride),
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

  /// Confirma explicitamente si [date] fue o no un dia de sangrado,
  /// desde una accion directa y dedicada (la pregunta "Sigue tu periodo
  /// hoy?" en Inicio, o "Quitar marca" en el calendario) -- NUNCA desde
  /// el formulario general (ese usa [upsertDay]). Siempre marca
  /// period_day_explicit=true, sea que [isPeriodDay] confirme true o
  /// false. No toca mood, notes ni sintomas.
  Future<void> setPeriodDayExplicitly(
    String date, {
    required bool isPeriodDay,
  }) async {
    final existing = await getDay(date);
    await _db.into(_db.dailyLogs).insertOnConflictUpdate(
          DailyLogsCompanion(
            date: Value(date),
            isPeriodDay: Value(isPeriodDay),
            // Si se confirma que no hubo sangrado, cualquier flow previo
            // deja de tener sentido (y el CHECK de la tabla lo exige).
            flow: Value(isPeriodDay ? existing?.flow : null),
            periodDayExplicit: const Value(true),
          ),
        );
  }

  Stream<DailyLogRow?> watchDay(String date) {
    return (_db.select(_db.dailyLogs)..where((t) => t.date.equals(date)))
        .watchSingleOrNull();
  }

  /// Deshace una escritura anterior restaurando exactamente la fila que
  /// habia antes (o borrandola si no existia ninguna). Pensado para el
  /// "Deshacer" que acompaña a [setPeriodDayExplicitly].
  Future<void> restoreDaySnapshot(String date, DailyLogRow? snapshot) async {
    if (snapshot == null) {
      await (_db.delete(_db.dailyLogs)..where((t) => t.date.equals(date)))
          .go();
      return;
    }
    await _db.into(_db.dailyLogs).insertOnConflictUpdate(
          DailyLogsCompanion(
            date: Value(date),
            isPeriodDay: Value(snapshot.isPeriodDay),
            flow: Value(snapshot.flow),
            mood: Value(snapshot.mood),
            notes: Value(snapshot.notes),
            periodDayExplicit: Value(snapshot.periodDayExplicit),
          ),
        );
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

  /// Separa las filas de daily_logs en dias de sangrado y dias
  /// confirmados explicitamente como "sin sangrado" (nunca los default
  /// del formulario general), para pasarselos a deriveCycles. Ambas
  /// listas salen de la MISMA lectura, para que nunca queden
  /// inconsistentes entre si.
  List<CycleSummary> _deriveFromRows(List<DailyLogRow> rows) {
    final periodDays = [for (final r in rows) if (r.isPeriodDay) r.date];
    final explicitNonPeriodDays = [
      for (final r in rows) if (!r.isPeriodDay && r.periodDayExplicit) r.date,
    ];
    return deriveCycles(periodDays, explicitNonPeriodDays: explicitNonPeriodDays);
  }

  Future<List<CycleSummary>> getDerivedCycles() async {
    final rows = await _db.select(_db.dailyLogs).get();
    return _deriveFromRows(rows);
  }

  /// Igual que [getDerivedCycles], pero reactivo: emite de nuevo cada vez
  /// que cambia algun dia en daily_logs (registrar un dia, marcar un dia
  /// desde el calendario, confirmar fin de periodo, borrar todos los
  /// datos), sin importar por donde se navego para llegar a la pantalla.
  /// Evita tener que acordarse de "recargar" a mano en cada punto de
  /// navegacion que podria cambiar datos.
  ///
  /// Deliberadamente NO devuelve un `Stream<CyclePrediction?>` ya
  /// calculado: ese calculo necesita un "hoy", y un stream atado solo a
  /// escrituras en la base nunca se entera de que paso la medianoche o
  /// de que la app volvio a primer plano al dia siguiente sin que nadie
  /// haya tocado un dato. Por eso la UI (home_screen) es quien decide
  /// "hoy" y llama a predictCycle() ella misma con cada emision de este
  /// stream.
  Stream<List<CycleSummary>> watchDerivedCycles() {
    return _db.select(_db.dailyLogs).watch().map(_deriveFromRows);
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

  /// Igual que llamar hasAnyLog()+getSymptomFrequency()+getMoodFrequency()+
  /// getAverageFlow() juntos, pero reactivo: se recalculan los 4 de nuevo
  /// cada vez que cambia daily_logs. upsertDay() y deleteAllData() siempre
  /// escriben en daily_logs en la misma transaccion en que tocan
  /// daily_log_symptoms o app_settings, asi que observar solo daily_logs
  /// alcanza para detectar cualquier cambio relevante para estas
  /// estadisticas.
  Stream<StatsSnapshot> watchStats() {
    return _db.select(_db.dailyLogs).watch().asyncMap((_) async {
      return StatsSnapshot(
        hasAnyLog: await hasAnyLog(),
        symptomFrequency: await getSymptomFrequency(),
        moodFrequency: await getMoodFrequency(),
        averageFlow: await getAverageFlow(),
      );
    });
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

  Future<void> setPeriodReminderEnabled(bool value) async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion(
            id: const Value(0),
            periodReminderEnabled: Value(value),
          ),
        );
  }

  Future<void> setFertileWindowRemindersEnabled(bool value) async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion(
            id: const Value(0),
            fertileWindowRemindersEnabled: Value(value),
          ),
        );
  }

  Future<void> setShowDetailsEnabled(bool value) async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion(
            id: const Value(0),
            showDetailsEnabled: Value(value),
          ),
        );
  }

  Future<void> setReminderTime({required int hour, required int minute}) async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion(
            id: const Value(0),
            reminderHour: Value(hour),
            reminderMinute: Value(minute),
          ),
        );
  }

  NotificationSettings _toNotificationSettings(AppSettingsRow row) =>
      NotificationSettings(
        notificationsEnabled: row.notificationsEnabled,
        periodReminderEnabled: row.periodReminderEnabled,
        fertileWindowRemindersEnabled: row.fertileWindowRemindersEnabled,
        showDetailsEnabled: row.showDetailsEnabled,
        reminderHour: row.reminderHour,
        reminderMinute: row.reminderMinute,
      );

  Future<NotificationSettings> getNotificationSettings() async =>
      _toNotificationSettings(await _ensureSettingsRow());

  /// Reactivo: se recalcula cada vez que cambia app_settings (cualquier
  /// toggle, la hora, etc), para que quien reconcilia notificaciones
  /// (ver NotificationReconciler) no tenga que sondear a mano.
  Stream<NotificationSettings> watchNotificationSettings() {
    return (_db.select(_db.appSettings)..where((t) => t.id.equals(0)))
        .watchSingleOrNull()
        .asyncMap((row) async =>
            _toNotificationSettings(row ?? await _ensureSettingsRow()));
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

/// Resultado combinado de [CycleRepository.watchStats] (y equivalente a
/// llamar hasAnyLog/getSymptomFrequency/getMoodFrequency/getAverageFlow
/// por separado).
class StatsSnapshot {
  final bool hasAnyLog;
  final Map<Symptom, int> symptomFrequency;
  final Map<Mood, int> moodFrequency;
  final double averageFlow;

  const StatsSnapshot({
    required this.hasAnyLog,
    required this.symptomFrequency,
    required this.moodFrequency,
    required this.averageFlow,
  });
}

AppDatabase? _appDatabaseInstance;

/// Instancia unica de AppDatabase para toda la app (no hay DI framework
/// en este proyecto). Las pantallas usan [cycleRepository], no esto
/// directamente.
AppDatabase get appDatabase => _appDatabaseInstance ??= AppDatabase();

/// Solo para tests: reemplaza la instancia global (ej. por una con
/// NativeDatabase.memory()) antes de montar los widgets que la usan.
set appDatabase(AppDatabase value) => _appDatabaseInstance = value;

CycleRepository? _cycleRepositoryInstance;

CycleRepository get cycleRepository =>
    _cycleRepositoryInstance ??= CycleRepository(appDatabase);

/// Solo para tests: reemplaza el repositorio global.
set cycleRepository(CycleRepository value) => _cycleRepositoryInstance = value;
