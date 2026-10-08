import 'package:drift/drift.dart';

import '../../domain/backup_codec.dart';
import '../../domain/current_period.dart';
import '../../domain/cycle_deriver.dart';
import '../../domain/cycle_predictor.dart';
import '../../domain/notification_planner.dart';
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
  ///   null (el CHECK de la tabla lo exige igual), period_end a null (su
  ///   CHECK tambien: un dia sin sangrado no puede ser el fin de un
  ///   periodo) y period_day_explicit a true. El periodo sigue cerrado por
  ///   ese "no" explicito.
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
      var clearPeriodEnd = false;

      if (isPeriodDaySwitch) {
        effectiveIsPeriodDay = true;
        effectiveFlow = flow;
        explicitOverride = false;
      } else if (wasExplicitTrue) {
        effectiveIsPeriodDay = false;
        effectiveFlow = null;
        explicitOverride = true;
        clearPeriodEnd = true;
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
              periodEnd:
                  clearPeriodEnd ? const Value(null) : const Value.absent(),
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

  /// Marca [date] como dia de sangrado. La app ya no lo usa (marca con
  /// [markPeriodDayWithSnapshot]); lo usan los tests para sembrar datos.
  /// No toca flow,
  /// mood, notes, sintomas ni period_end de un dia existente (marcar el
  /// dia siguiente a un fin reabre el periodo sin borrar la marca, R-4). Devuelve false si el
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
  /// desde una accion directa y dedicada ("Quitar marca" en el
  /// calendario; antes tambien el "Si"/"No" de Inicio) -- NUNCA desde
  /// el formulario general (ese usa [upsertDay]). Siempre marca
  /// period_day_explicit=true, sea que [isPeriodDay] confirme true o
  /// false. No toca mood, notes ni sintomas. Con [isPeriodDay] false
  /// limpia period_end (lo exige su CHECK); el periodo sigue cerrado por
  /// el "no" explicito que queda guardado.
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
            periodEnd:
                isPeriodDay ? const Value.absent() : const Value(null),
          ),
        );
  }

  /// Igual que [markPeriodDay], para varios dias a la vez. La app ya no
  /// lo usa (el rango del calendario usa [markPeriodRangeWithSnapshot]);
  /// lo usan los tests para sembrar datos. No toca periodDayExplicit,
  /// igual que markPeriodDay: si alguno de estos dias ya era explicito
  /// en false, el flag se mantiene pero deja de tener efecto porque
  /// deriveCycles solo lo consulta cuando isPeriodDay es false.
  Future<void> markPeriodDays(List<String> dates) async {
    if (dates.isEmpty) return;
    await _db.batch((batch) {
      batch.insertAllOnConflictUpdate(_db.dailyLogs, [
        for (final date in dates)
          DailyLogsCompanion(date: Value(date), isPeriodDay: const Value(true)),
      ]);
    });
  }

  Stream<DailyLogRow?> watchDay(String date) {
    return (_db.select(_db.dailyLogs)..where((t) => t.date.equals(date)))
        .watchSingleOrNull();
  }

  Future<void> _writeSnapshotRow(String date, DailyLogRow? snapshot) async {
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
            periodEnd: Value(snapshot.periodEnd),
          ),
        );
  }

  // --- Acciones del periodo con foto para "Deshacer" (HU-03, HU-04) ---

  /// Foto de las filas completas de daily_logs de [dates] (null para las
  /// que no existen), incluido period_end. Los sintomas no entran: estas
  /// acciones nunca los tocan.
  Future<DaysSnapshot> takeDaysSnapshot(Iterable<String> dates) async {
    final wanted = dates.toSet();
    if (wanted.isEmpty) return DaysSnapshot(const {});
    final rows = await (_db.select(_db.dailyLogs)
          ..where((t) => t.date.isIn(wanted)))
        .get();
    final byDate = {for (final r in rows) r.date: r};
    return DaysSnapshot({for (final d in wanted) d: byDate[d]});
  }

  /// Deshace una accion de varios dias: deja cada dia de [snapshot]
  /// exactamente como estaba (o lo borra si no existia) en una sola
  /// transaccion. Si una escritura falla, no cambia ningun dia.
  Future<void> restoreDaysSnapshot(DaysSnapshot snapshot) async {
    if (snapshot.rows.isEmpty) return;
    await _db.transaction(() async {
      for (final date in snapshot.dates) {
        await _writeSnapshotRow(date, snapshot.rows[date]);
      }
    });
  }

  /// Marca como sangrado sin tocar flow, mood, notes, sintomas,
  /// period_day_explicit ni period_end (como [markPeriodDay]).
  Future<void> _markRows(Iterable<String> dates) async {
    for (final date in dates) {
      await _db.into(_db.dailyLogs).insertOnConflictUpdate(
            DailyLogsCompanion(
                date: Value(date), isPeriodDay: const Value(true)),
          );
    }
  }

  Future<void> _writeDeclaredEnd(String date) async {
    await _db.into(_db.dailyLogs).insertOnConflictUpdate(
          DailyLogsCompanion(
            date: Value(date),
            isPeriodDay: const Value(true),
            periodEnd: const Value(PeriodEndSource.declared),
          ),
        );
  }

  /// "Termino hoy" / "Termino otro dia" (HU-03): en una transaccion,
  /// valida con checkPeriodEnd, marca los dias de daysToMarkWhenClosing
  /// (los "No" explicitos se respetan, decision 3) sin pisar mood, notes
  /// ni sintomas, y guarda period_end = declared en [endDate]. Devuelve la
  /// foto de los dias tocados para "Deshacer".
  ///
  /// Lanza [PeriodEndException] si checkPeriodEnd encuentra un problema
  /// (incluido un "No" explicito en [endDate]), y [ArgumentError] si
  /// [periodStart] no es el primer dia de un periodo. En ambos casos no
  /// cambia nada. [today] es solo para tests.
  Future<DaysSnapshot> closePeriod(
    String periodStart,
    String endDate, {
    String? today,
  }) {
    final now = today ?? DayKey.today();
    return _db.transaction(() async {
      final days = _splitRows(await _db.select(_db.dailyLogs).get());
      final isStart = groupPeriodRuns(days.periodDays)
          .any((run) => run.first == periodStart);
      if (!isStart) {
        throw ArgumentError.value(
            periodStart, 'periodStart', 'no es el primer dia de un periodo');
      }
      final check = checkPeriodEnd(
        periodStart: periodStart,
        endDate: endDate,
        today: now,
        periodDays: days.periodDays,
        explicitNonPeriodDays: days.explicitNonPeriodDays,
      );
      if (!check.isValid) throw PeriodEndException(check);

      final toMark = daysToMarkWhenClosing(
        periodStart: periodStart,
        endDate: endDate,
        periodDays: days.periodDays,
        explicitNonPeriodDays: days.explicitNonPeriodDays,
      );
      final snapshot = await takeDaysSnapshot([...toMark, endDate]);
      await _markRows(toMark.where((d) => d != endDate));
      await _writeDeclaredEnd(endDate);
      return snapshot;
    });
  }

  /// Marca [date] como sangrado con foto para "Deshacer" (HU-04 crit. 7).
  /// Igual que [markPeriodRangeWithSnapshot] con un rango de un dia.
  Future<MarkDaysResult> markPeriodDayWithSnapshot(
    String date, {
    required bool closeAtEnd,
    String? today,
  }) =>
      markPeriodRangeWithSnapshot(date, date,
          closeAtEnd: closeAtEnd, today: today);

  /// Marca como sangrado todos los dias de [start] a [end] (U-1), sin
  /// pisar flow, mood, notes, sintomas ni period_end, en una transaccion.
  /// Marcar el dia siguiente a un fin lo reabre sin borrar la marca (R-4).
  ///
  /// Con [closeAtEnd] (R-1, "Si, termino") guarda period_end = declared en
  /// [end] solo si, ya marcado el rango, [end] es el ultimo dia de su
  /// periodo y checkPeriodEnd no encuentra problema: los rangos no se
  /// bloquean (decision 5), solo no se cierran. Se revalida aqui con la
  /// base, no con lo que vio la pantalla. La foto cubre todo el rango.
  Future<MarkDaysResult> markPeriodRangeWithSnapshot(
    String start,
    String end, {
    required bool closeAtEnd,
    String? today,
  }) async {
    if (DayKey.isBefore(end, start)) {
      throw ArgumentError.value(end, 'end', 'es anterior a $start');
    }
    final now = today ?? DayKey.today();
    final range = [
      for (var d = start; !DayKey.isBefore(end, d); d = DayKey.addDays(d, 1))
        d,
    ];
    return _db.transaction(() async {
      final snapshot = await takeDaysSnapshot(range);
      final toMark = [
        for (final d in range)
          if (snapshot.rows[d]?.isPeriodDay != true) d,
      ];
      await _markRows(toMark);

      var closed = false;
      if (closeAtEnd) {
        final days = _splitRows(await _db.select(_db.dailyLogs).get());
        final run = groupPeriodRuns(days.periodDays)
            .firstWhere((r) => r.contains(end));
        final check = checkPeriodEnd(
          periodStart: run.first,
          endDate: end,
          today: now,
          periodDays: days.periodDays,
          explicitNonPeriodDays: days.explicitNonPeriodDays,
        );
        if (check.isValid) {
          await _writeDeclaredEnd(end);
          closed = true;
        }
      }
      return MarkDaysResult(
          snapshot: snapshot, newlyMarked: toMark.length, closed: closed);
    });
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
    final days = _splitRows(rows);
    final periodEnds = {
      for (final r in rows)
        if (r.periodEnd != null) r.date: r.periodEnd!,
    };
    return deriveCycles(days.periodDays,
        explicitNonPeriodDays: days.explicitNonPeriodDays,
        periodEnds: periodEnds);
  }

  ({List<String> periodDays, List<String> explicitNonPeriodDays}) _splitRows(
          List<DailyLogRow> rows) =>
      (
        periodDays: [for (final r in rows) if (r.isPeriodDay) r.date],
        explicitNonPeriodDays: [
          for (final r in rows)
            if (!r.isPeriodDay && r.periodDayExplicit) r.date,
        ],
      );

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

  /// Lo que necesita predictCycle: los ciclos derivados y la duracion
  /// habitual del periodo. Emite de nuevo cuando cambian los dias
  /// (daily_logs) O los ajustes (app_settings), y lee ambos en la misma
  /// transaccion. Igual que [watchDerivedCycles], no calcula la
  /// prediccion: "hoy" lo decide quien escucha.
  Stream<PredictionInputs> watchPredictionInputs() {
    return _db
        .customSelect('SELECT 1',
            readsFrom: {_db.dailyLogs, _db.appSettings})
        .watch()
        .asyncMap((_) => getPredictionInputs());
  }

  Future<PredictionInputs> getPredictionInputs() {
    return _db.transaction(() async {
      final rows = await _db.select(_db.dailyLogs).get();
      final settings = await (_db.select(_db.appSettings)
            ..where((t) => t.id.equals(0)))
          .getSingleOrNull();
      return PredictionInputs(
        cycles: _deriveFromRows(rows),
        typicalPeriodLengthDays:
            settings?.typicalPeriodLength ?? defaultTypicalPeriodLength,
        showFertileWindow: settings?.showFertileWindow ?? true,
      );
    });
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

  /// Duracion habitual del periodo (HU-01). Vuelve a
  /// [defaultTypicalPeriodLength] tras "Borrar todos los datos".
  Future<int> getTypicalPeriodLength() async =>
      (await _ensureSettingsRow()).typicalPeriodLength;

  /// Lanza [ArgumentError] fuera de [minTypicalPeriodLength] a
  /// [maxTypicalPeriodLength] (la base tambien lo impide con un CHECK).
  Future<void> setTypicalPeriodLength(int days) async {
    if (days < minTypicalPeriodLength || days > maxTypicalPeriodLength) {
      throw ArgumentError.value(days, 'days',
          'debe estar entre $minTypicalPeriodLength y $maxTypicalPeriodLength');
    }
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion(
            id: const Value(0),
            typicalPeriodLength: Value(days),
          ),
        );
  }

  /// "Mostrar ovulacion y ventana fertil" (HU-05). Vuelve a true tras
  /// "Borrar todos los datos".
  Future<bool> getShowFertileWindow() async =>
      (await _ensureSettingsRow()).showFertileWindow;

  Future<void> setShowFertileWindow(bool value) async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion(
            id: const Value(0),
            showFertileWindow: Value(value),
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
        showFertileWindow: row.showFertileWindow,
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

  // --- Respaldo (HU-06) ---

  /// Lee todas las tablas para exportarlas. Los dias salen ordenados por
  /// fecha y los sintomas por nombre (exportacion determinista).
  Future<BackupData> readBackupData({
    required String appVersion,
    required String exportedAt,
  }) async {
    return _db.transaction(() async {
      final logs = await (_db.select(_db.dailyLogs)
            ..orderBy([(t) => OrderingTerm.asc(t.date)]))
          .get();
      final symptomRows = await _db.select(_db.dailyLogSymptoms).get();
      final symptomsByDate = <String, List<Symptom>>{};
      for (final row in symptomRows) {
        symptomsByDate.putIfAbsent(row.logDate, () => []).add(row.symptom);
      }
      final settings = await _ensureSettingsRow();
      return BackupData(
        // El schema del formato que se escribe (un test exige que sea el
        // de la base).
        schemaVersion: currentBackupSchemaVersion,
        appVersion: appVersion,
        exportedAt: exportedAt,
        days: [
          for (final log in logs)
            BackupDay(
              date: log.date,
              isPeriodDay: log.isPeriodDay,
              periodDayExplicit: log.periodDayExplicit,
              periodEnd: log.periodEnd,
              flow: log.flow,
              mood: log.mood,
              notes: log.notes,
              symptoms: (symptomsByDate[log.date] ?? [])
                ..sort((a, b) => a.name.compareTo(b.name)),
            ),
        ],
        settings: BackupSettings(
          onboardingSeen: settings.onboardingSeen,
          notificationsEnabled: settings.notificationsEnabled,
          periodReminderEnabled: settings.periodReminderEnabled,
          fertileWindowRemindersEnabled:
              settings.fertileWindowRemindersEnabled,
          showDetailsEnabled: settings.showDetailsEnabled,
          reminderHour: settings.reminderHour,
          reminderMinute: settings.reminderMinute,
          typicalPeriodLength: settings.typicalPeriodLength,
          showFertileWindow: settings.showFertileWindow,
        ),
      );
    });
  }

  Future<int> countDays() async {
    final countExp = _db.dailyLogs.date.count();
    final query = _db.selectOnly(_db.dailyLogs)..addColumns([countExp]);
    return (await query.getSingle()).read(countExp) ?? 0;
  }

  /// Reemplaza TODOS los datos por los de [data] en una unica
  /// transaccion: si cualquier escritura falla (ej. un CHECK), drift
  /// revierte y los datos anteriores quedan intactos. Nunca borrar y
  /// luego insertar fuera de una transaccion.
  ///
  /// El interruptor general de notificaciones NO se importa: depende del
  /// permiso de ESTE telefono, asi que conserva su valor actual. El resto
  /// de los ajustes de recordatorios si se importa, y la duracion
  /// habitual del periodo tambien. onboardingSeen queda en true: quien
  /// importa ya esta usando la app. "Mostrar ovulacion y ventana fertil"
  /// tambien se importa (un respaldo v3 o v4 lo trae activado).
  ///
  /// [data] tiene que estar en el schema actual: un respaldo anterior se
  /// convierte antes con upgradeBackupData (regla D-2), para que ningun
  /// camino importe datos v3 sin aplicarla.
  Future<void> replaceAllWithBackup(BackupData data) async {
    if (data.schemaVersion != currentBackupSchemaVersion) {
      throw ArgumentError.value(data.schemaVersion, 'data.schemaVersion',
          'convertir con upgradeBackupData antes de importar');
    }
    await _db.transaction(() async {
      final current = await _ensureSettingsRow();
      await _db.delete(_db.dailyLogSymptoms).go();
      await _db.delete(_db.dailyLogs).go();
      await _db.delete(_db.appSettings).go();

      final s = data.settings;
      await _db.batch((batch) {
        batch.insertAll(_db.dailyLogs, [
          for (final day in data.days)
            DailyLogsCompanion.insert(
              date: day.date,
              isPeriodDay: Value(day.isPeriodDay),
              flow: Value(day.flow),
              mood: Value(day.mood),
              notes: Value(day.notes),
              periodDayExplicit: Value(day.periodDayExplicit),
              periodEnd: Value(day.periodEnd),
            ),
        ]);
        batch.insertAll(_db.dailyLogSymptoms, [
          for (final day in data.days)
            for (final symptom in day.symptoms)
              DailyLogSymptomsCompanion.insert(
                  logDate: day.date, symptom: symptom),
        ]);
        batch.insert(
          _db.appSettings,
          AppSettingsCompanion.insert(
            id: const Value(0),
            onboardingSeen: const Value(true),
            notificationsEnabled: Value(current.notificationsEnabled),
            periodReminderEnabled: Value(s.periodReminderEnabled),
            fertileWindowRemindersEnabled:
                Value(s.fertileWindowRemindersEnabled),
            showDetailsEnabled: Value(s.showDetailsEnabled),
            reminderHour: Value(s.reminderHour),
            reminderMinute: Value(s.reminderMinute),
            typicalPeriodLength: Value(s.typicalPeriodLength),
            showFertileWindow: Value(s.showFertileWindow),
          ),
        );
      });
    });
  }

  /// Borra TODAS las tablas (daily_logs, daily_log_symptoms,
  /// app_settings), incluidos los ajustes: al recrearse la fila, cada
  /// ajuste vuelve al valor por defecto de su columna (ej.
  /// show_fertile_window vuelve a activado). Usado por
  /// BackupService.deleteAllData() (que ademas borra los archivos de
  /// respaldo) tras confirmacion explicita del usuario.
  Future<void> deleteAllData() async {
    await _db.transaction(() async {
      await _db.delete(_db.dailyLogSymptoms).go();
      await _db.delete(_db.dailyLogs).go();
      await _db.delete(_db.appSettings).go();
    });
  }
}

/// Entradas de predictCycle que vienen de la base (ver
/// [CycleRepository.watchPredictionInputs]).
class PredictionInputs {
  final List<CycleSummary> cycles;
  final int typicalPeriodLengthDays;

  /// "Mostrar ovulacion y ventana fertil" (HU-05). Lo usa Inicio.
  final bool showFertileWindow;

  const PredictionInputs({
    required this.cycles,
    required this.typicalPeriodLengthDays,
    this.showFertileWindow = true,
  });

  PredictionConfig get config =>
      PredictionConfig(typicalPeriodLengthDays: typicalPeriodLengthDays);
}

/// Foto de varios dias de daily_logs para "Deshacer" (ver
/// [CycleRepository.takeDaysSnapshot]): fila completa por fecha, o null
/// si ese dia no tenia fila.
class DaysSnapshot {
  DaysSnapshot(Map<String, DailyLogRow?> rows) : rows = Map.unmodifiable(rows);

  final Map<String, DailyLogRow?> rows;

  /// Fechas de la foto, en orden.
  List<String> get dates => rows.keys.toList()..sort(DayKey.compare);
}

/// Resultado de marcar un dia o un rango con foto.
class MarkDaysResult {
  const MarkDaysResult({
    required this.snapshot,
    required this.newlyMarked,
    required this.closed,
  });

  /// Foto de todos los dias del rango, para "Deshacer".
  final DaysSnapshot snapshot;

  /// Dias que no estaban marcados y ahora si.
  final int newlyMarked;

  /// Si se guardo period_end = declared en el ultimo dia del rango.
  final bool closed;

  /// false si no se escribio nada (un dia que ya estaba marcado, sin
  /// cierre): la pantalla muestra "Ese dia ya esta registrado".
  bool get changedAnything => newlyMarked > 0 || closed;
}

/// [CycleRepository.closePeriod] no puede terminar el periodo en ese dia.
class PeriodEndException implements Exception {
  const PeriodEndException(this.check);

  final PeriodEndCheck check;

  PeriodEndProblem get problem => check.problem!;

  @override
  String toString() => 'PeriodEndException($problem)';
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
