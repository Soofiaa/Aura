// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $DailyLogsTable extends DailyLogs
    with TableInfo<$DailyLogsTable, DailyLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isPeriodDayMeta = const VerificationMeta(
    'isPeriodDay',
  );
  @override
  late final GeneratedColumn<bool> isPeriodDay = GeneratedColumn<bool>(
    'is_period_day',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_period_day" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumnWithTypeConverter<FlowIntensity?, String> flow =
      GeneratedColumn<String>(
        'flow',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<FlowIntensity?>($DailyLogsTable.$converterflown);
  @override
  late final GeneratedColumnWithTypeConverter<Mood?, String> mood =
      GeneratedColumn<String>(
        'mood',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<Mood?>($DailyLogsTable.$convertermoodn);
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _periodDayExplicitMeta = const VerificationMeta(
    'periodDayExplicit',
  );
  @override
  late final GeneratedColumn<bool> periodDayExplicit = GeneratedColumn<bool>(
    'period_day_explicit',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("period_day_explicit" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  late final GeneratedColumnWithTypeConverter<PeriodEndSource?, String>
  periodEnd = GeneratedColumn<String>(
    'period_end',
    aliasedName,
    true,
    check: () => periodEnd.isNull() | isPeriodDay.equals(true),
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  ).withConverter<PeriodEndSource?>($DailyLogsTable.$converterperiodEndn);
  @override
  List<GeneratedColumn> get $columns => [
    date,
    isPeriodDay,
    flow,
    mood,
    notes,
    periodDayExplicit,
    periodEnd,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<DailyLogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('is_period_day')) {
      context.handle(
        _isPeriodDayMeta,
        isPeriodDay.isAcceptableOrUnknown(
          data['is_period_day']!,
          _isPeriodDayMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('period_day_explicit')) {
      context.handle(
        _periodDayExplicitMeta,
        periodDayExplicit.isAcceptableOrUnknown(
          data['period_day_explicit']!,
          _periodDayExplicitMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {date};
  @override
  DailyLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyLogRow(
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      isPeriodDay: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_period_day'],
      )!,
      flow: $DailyLogsTable.$converterflown.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}flow'],
        ),
      ),
      mood: $DailyLogsTable.$convertermoodn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}mood'],
        ),
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      periodDayExplicit: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}period_day_explicit'],
      )!,
      periodEnd: $DailyLogsTable.$converterperiodEndn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}period_end'],
        ),
      ),
    );
  }

  @override
  $DailyLogsTable createAlias(String alias) {
    return $DailyLogsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<FlowIntensity, String, String> $converterflow =
      const EnumNameConverter<FlowIntensity>(FlowIntensity.values);
  static JsonTypeConverter2<FlowIntensity?, String?, String?> $converterflown =
      JsonTypeConverter2.asNullable($converterflow);
  static JsonTypeConverter2<Mood, String, String> $convertermood =
      const EnumNameConverter<Mood>(Mood.values);
  static JsonTypeConverter2<Mood?, String?, String?> $convertermoodn =
      JsonTypeConverter2.asNullable($convertermood);
  static JsonTypeConverter2<PeriodEndSource, String, String>
  $converterperiodEnd = const EnumNameConverter<PeriodEndSource>(
    PeriodEndSource.values,
  );
  static JsonTypeConverter2<PeriodEndSource?, String?, String?>
  $converterperiodEndn = JsonTypeConverter2.asNullable($converterperiodEnd);
}

class DailyLogRow extends DataClass implements Insertable<DailyLogRow> {
  final String date;
  final bool isPeriodDay;
  final FlowIntensity? flow;
  final Mood? mood;
  final String? notes;

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
  final bool periodDayExplicit;

  /// Fin del periodo (decision D-1): se guarda solo en el ULTIMO dia de
  /// sangrado, con su origen (declared / inferred). Un period_end en un
  /// dia interior no cuenta (R-4). El CHECK va en la columna, no en la
  /// tabla, para que una base nueva y una migrada (ADD COLUMN) tengan el
  /// mismo schema; impide guardarlo en un dia sin sangrado.
  final PeriodEndSource? periodEnd;
  const DailyLogRow({
    required this.date,
    required this.isPeriodDay,
    this.flow,
    this.mood,
    this.notes,
    required this.periodDayExplicit,
    this.periodEnd,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['date'] = Variable<String>(date);
    map['is_period_day'] = Variable<bool>(isPeriodDay);
    if (!nullToAbsent || flow != null) {
      map['flow'] = Variable<String>(
        $DailyLogsTable.$converterflown.toSql(flow),
      );
    }
    if (!nullToAbsent || mood != null) {
      map['mood'] = Variable<String>(
        $DailyLogsTable.$convertermoodn.toSql(mood),
      );
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['period_day_explicit'] = Variable<bool>(periodDayExplicit);
    if (!nullToAbsent || periodEnd != null) {
      map['period_end'] = Variable<String>(
        $DailyLogsTable.$converterperiodEndn.toSql(periodEnd),
      );
    }
    return map;
  }

  DailyLogsCompanion toCompanion(bool nullToAbsent) {
    return DailyLogsCompanion(
      date: Value(date),
      isPeriodDay: Value(isPeriodDay),
      flow: flow == null && nullToAbsent ? const Value.absent() : Value(flow),
      mood: mood == null && nullToAbsent ? const Value.absent() : Value(mood),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      periodDayExplicit: Value(periodDayExplicit),
      periodEnd: periodEnd == null && nullToAbsent
          ? const Value.absent()
          : Value(periodEnd),
    );
  }

  factory DailyLogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyLogRow(
      date: serializer.fromJson<String>(json['date']),
      isPeriodDay: serializer.fromJson<bool>(json['isPeriodDay']),
      flow: $DailyLogsTable.$converterflown.fromJson(
        serializer.fromJson<String?>(json['flow']),
      ),
      mood: $DailyLogsTable.$convertermoodn.fromJson(
        serializer.fromJson<String?>(json['mood']),
      ),
      notes: serializer.fromJson<String?>(json['notes']),
      periodDayExplicit: serializer.fromJson<bool>(json['periodDayExplicit']),
      periodEnd: $DailyLogsTable.$converterperiodEndn.fromJson(
        serializer.fromJson<String?>(json['periodEnd']),
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'date': serializer.toJson<String>(date),
      'isPeriodDay': serializer.toJson<bool>(isPeriodDay),
      'flow': serializer.toJson<String?>(
        $DailyLogsTable.$converterflown.toJson(flow),
      ),
      'mood': serializer.toJson<String?>(
        $DailyLogsTable.$convertermoodn.toJson(mood),
      ),
      'notes': serializer.toJson<String?>(notes),
      'periodDayExplicit': serializer.toJson<bool>(periodDayExplicit),
      'periodEnd': serializer.toJson<String?>(
        $DailyLogsTable.$converterperiodEndn.toJson(periodEnd),
      ),
    };
  }

  DailyLogRow copyWith({
    String? date,
    bool? isPeriodDay,
    Value<FlowIntensity?> flow = const Value.absent(),
    Value<Mood?> mood = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    bool? periodDayExplicit,
    Value<PeriodEndSource?> periodEnd = const Value.absent(),
  }) => DailyLogRow(
    date: date ?? this.date,
    isPeriodDay: isPeriodDay ?? this.isPeriodDay,
    flow: flow.present ? flow.value : this.flow,
    mood: mood.present ? mood.value : this.mood,
    notes: notes.present ? notes.value : this.notes,
    periodDayExplicit: periodDayExplicit ?? this.periodDayExplicit,
    periodEnd: periodEnd.present ? periodEnd.value : this.periodEnd,
  );
  DailyLogRow copyWithCompanion(DailyLogsCompanion data) {
    return DailyLogRow(
      date: data.date.present ? data.date.value : this.date,
      isPeriodDay: data.isPeriodDay.present
          ? data.isPeriodDay.value
          : this.isPeriodDay,
      flow: data.flow.present ? data.flow.value : this.flow,
      mood: data.mood.present ? data.mood.value : this.mood,
      notes: data.notes.present ? data.notes.value : this.notes,
      periodDayExplicit: data.periodDayExplicit.present
          ? data.periodDayExplicit.value
          : this.periodDayExplicit,
      periodEnd: data.periodEnd.present ? data.periodEnd.value : this.periodEnd,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyLogRow(')
          ..write('date: $date, ')
          ..write('isPeriodDay: $isPeriodDay, ')
          ..write('flow: $flow, ')
          ..write('mood: $mood, ')
          ..write('notes: $notes, ')
          ..write('periodDayExplicit: $periodDayExplicit, ')
          ..write('periodEnd: $periodEnd')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    date,
    isPeriodDay,
    flow,
    mood,
    notes,
    periodDayExplicit,
    periodEnd,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyLogRow &&
          other.date == this.date &&
          other.isPeriodDay == this.isPeriodDay &&
          other.flow == this.flow &&
          other.mood == this.mood &&
          other.notes == this.notes &&
          other.periodDayExplicit == this.periodDayExplicit &&
          other.periodEnd == this.periodEnd);
}

class DailyLogsCompanion extends UpdateCompanion<DailyLogRow> {
  final Value<String> date;
  final Value<bool> isPeriodDay;
  final Value<FlowIntensity?> flow;
  final Value<Mood?> mood;
  final Value<String?> notes;
  final Value<bool> periodDayExplicit;
  final Value<PeriodEndSource?> periodEnd;
  final Value<int> rowid;
  const DailyLogsCompanion({
    this.date = const Value.absent(),
    this.isPeriodDay = const Value.absent(),
    this.flow = const Value.absent(),
    this.mood = const Value.absent(),
    this.notes = const Value.absent(),
    this.periodDayExplicit = const Value.absent(),
    this.periodEnd = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailyLogsCompanion.insert({
    required String date,
    this.isPeriodDay = const Value.absent(),
    this.flow = const Value.absent(),
    this.mood = const Value.absent(),
    this.notes = const Value.absent(),
    this.periodDayExplicit = const Value.absent(),
    this.periodEnd = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : date = Value(date);
  static Insertable<DailyLogRow> custom({
    Expression<String>? date,
    Expression<bool>? isPeriodDay,
    Expression<String>? flow,
    Expression<String>? mood,
    Expression<String>? notes,
    Expression<bool>? periodDayExplicit,
    Expression<String>? periodEnd,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (date != null) 'date': date,
      if (isPeriodDay != null) 'is_period_day': isPeriodDay,
      if (flow != null) 'flow': flow,
      if (mood != null) 'mood': mood,
      if (notes != null) 'notes': notes,
      if (periodDayExplicit != null) 'period_day_explicit': periodDayExplicit,
      if (periodEnd != null) 'period_end': periodEnd,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailyLogsCompanion copyWith({
    Value<String>? date,
    Value<bool>? isPeriodDay,
    Value<FlowIntensity?>? flow,
    Value<Mood?>? mood,
    Value<String?>? notes,
    Value<bool>? periodDayExplicit,
    Value<PeriodEndSource?>? periodEnd,
    Value<int>? rowid,
  }) {
    return DailyLogsCompanion(
      date: date ?? this.date,
      isPeriodDay: isPeriodDay ?? this.isPeriodDay,
      flow: flow ?? this.flow,
      mood: mood ?? this.mood,
      notes: notes ?? this.notes,
      periodDayExplicit: periodDayExplicit ?? this.periodDayExplicit,
      periodEnd: periodEnd ?? this.periodEnd,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (isPeriodDay.present) {
      map['is_period_day'] = Variable<bool>(isPeriodDay.value);
    }
    if (flow.present) {
      map['flow'] = Variable<String>(
        $DailyLogsTable.$converterflown.toSql(flow.value),
      );
    }
    if (mood.present) {
      map['mood'] = Variable<String>(
        $DailyLogsTable.$convertermoodn.toSql(mood.value),
      );
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (periodDayExplicit.present) {
      map['period_day_explicit'] = Variable<bool>(periodDayExplicit.value);
    }
    if (periodEnd.present) {
      map['period_end'] = Variable<String>(
        $DailyLogsTable.$converterperiodEndn.toSql(periodEnd.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyLogsCompanion(')
          ..write('date: $date, ')
          ..write('isPeriodDay: $isPeriodDay, ')
          ..write('flow: $flow, ')
          ..write('mood: $mood, ')
          ..write('notes: $notes, ')
          ..write('periodDayExplicit: $periodDayExplicit, ')
          ..write('periodEnd: $periodEnd, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DailyLogSymptomsTable extends DailyLogSymptoms
    with TableInfo<$DailyLogSymptomsTable, DailyLogSymptomRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyLogSymptomsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _logDateMeta = const VerificationMeta(
    'logDate',
  );
  @override
  late final GeneratedColumn<String> logDate = GeneratedColumn<String>(
    'log_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Symptom, String> symptom =
      GeneratedColumn<String>(
        'symptom',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Symptom>($DailyLogSymptomsTable.$convertersymptom);
  @override
  List<GeneratedColumn> get $columns => [logDate, symptom];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_log_symptoms';
  @override
  VerificationContext validateIntegrity(
    Insertable<DailyLogSymptomRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('log_date')) {
      context.handle(
        _logDateMeta,
        logDate.isAcceptableOrUnknown(data['log_date']!, _logDateMeta),
      );
    } else if (isInserting) {
      context.missing(_logDateMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {logDate, symptom};
  @override
  DailyLogSymptomRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyLogSymptomRow(
      logDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}log_date'],
      )!,
      symptom: $DailyLogSymptomsTable.$convertersymptom.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}symptom'],
        )!,
      ),
    );
  }

  @override
  $DailyLogSymptomsTable createAlias(String alias) {
    return $DailyLogSymptomsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<Symptom, String, String> $convertersymptom =
      const EnumNameConverter<Symptom>(Symptom.values);
}

class DailyLogSymptomRow extends DataClass
    implements Insertable<DailyLogSymptomRow> {
  final String logDate;
  final Symptom symptom;
  const DailyLogSymptomRow({required this.logDate, required this.symptom});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['log_date'] = Variable<String>(logDate);
    {
      map['symptom'] = Variable<String>(
        $DailyLogSymptomsTable.$convertersymptom.toSql(symptom),
      );
    }
    return map;
  }

  DailyLogSymptomsCompanion toCompanion(bool nullToAbsent) {
    return DailyLogSymptomsCompanion(
      logDate: Value(logDate),
      symptom: Value(symptom),
    );
  }

  factory DailyLogSymptomRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyLogSymptomRow(
      logDate: serializer.fromJson<String>(json['logDate']),
      symptom: $DailyLogSymptomsTable.$convertersymptom.fromJson(
        serializer.fromJson<String>(json['symptom']),
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'logDate': serializer.toJson<String>(logDate),
      'symptom': serializer.toJson<String>(
        $DailyLogSymptomsTable.$convertersymptom.toJson(symptom),
      ),
    };
  }

  DailyLogSymptomRow copyWith({String? logDate, Symptom? symptom}) =>
      DailyLogSymptomRow(
        logDate: logDate ?? this.logDate,
        symptom: symptom ?? this.symptom,
      );
  DailyLogSymptomRow copyWithCompanion(DailyLogSymptomsCompanion data) {
    return DailyLogSymptomRow(
      logDate: data.logDate.present ? data.logDate.value : this.logDate,
      symptom: data.symptom.present ? data.symptom.value : this.symptom,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyLogSymptomRow(')
          ..write('logDate: $logDate, ')
          ..write('symptom: $symptom')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(logDate, symptom);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyLogSymptomRow &&
          other.logDate == this.logDate &&
          other.symptom == this.symptom);
}

class DailyLogSymptomsCompanion extends UpdateCompanion<DailyLogSymptomRow> {
  final Value<String> logDate;
  final Value<Symptom> symptom;
  final Value<int> rowid;
  const DailyLogSymptomsCompanion({
    this.logDate = const Value.absent(),
    this.symptom = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailyLogSymptomsCompanion.insert({
    required String logDate,
    required Symptom symptom,
    this.rowid = const Value.absent(),
  }) : logDate = Value(logDate),
       symptom = Value(symptom);
  static Insertable<DailyLogSymptomRow> custom({
    Expression<String>? logDate,
    Expression<String>? symptom,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (logDate != null) 'log_date': logDate,
      if (symptom != null) 'symptom': symptom,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailyLogSymptomsCompanion copyWith({
    Value<String>? logDate,
    Value<Symptom>? symptom,
    Value<int>? rowid,
  }) {
    return DailyLogSymptomsCompanion(
      logDate: logDate ?? this.logDate,
      symptom: symptom ?? this.symptom,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (logDate.present) {
      map['log_date'] = Variable<String>(logDate.value);
    }
    if (symptom.present) {
      map['symptom'] = Variable<String>(
        $DailyLogSymptomsTable.$convertersymptom.toSql(symptom.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyLogSymptomsCompanion(')
          ..write('logDate: $logDate, ')
          ..write('symptom: $symptom, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSettingsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _onboardingSeenMeta = const VerificationMeta(
    'onboardingSeen',
  );
  @override
  late final GeneratedColumn<bool> onboardingSeen = GeneratedColumn<bool>(
    'onboarding_seen',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("onboarding_seen" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _notificationsEnabledMeta =
      const VerificationMeta('notificationsEnabled');
  @override
  late final GeneratedColumn<bool> notificationsEnabled = GeneratedColumn<bool>(
    'notifications_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("notifications_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _periodReminderEnabledMeta =
      const VerificationMeta('periodReminderEnabled');
  @override
  late final GeneratedColumn<bool> periodReminderEnabled =
      GeneratedColumn<bool>(
        'period_reminder_enabled',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("period_reminder_enabled" IN (0, 1))',
        ),
        defaultValue: const Constant(true),
      );
  static const VerificationMeta _fertileWindowRemindersEnabledMeta =
      const VerificationMeta('fertileWindowRemindersEnabled');
  @override
  late final GeneratedColumn<bool> fertileWindowRemindersEnabled =
      GeneratedColumn<bool>(
        'fertile_window_reminders_enabled',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("fertile_window_reminders_enabled" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _showDetailsEnabledMeta =
      const VerificationMeta('showDetailsEnabled');
  @override
  late final GeneratedColumn<bool> showDetailsEnabled = GeneratedColumn<bool>(
    'show_details_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("show_details_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _reminderHourMeta = const VerificationMeta(
    'reminderHour',
  );
  @override
  late final GeneratedColumn<int> reminderHour = GeneratedColumn<int>(
    'reminder_hour',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(9),
  );
  static const VerificationMeta _reminderMinuteMeta = const VerificationMeta(
    'reminderMinute',
  );
  @override
  late final GeneratedColumn<int> reminderMinute = GeneratedColumn<int>(
    'reminder_minute',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _typicalPeriodLengthMeta =
      const VerificationMeta('typicalPeriodLength');
  @override
  late final GeneratedColumn<int> typicalPeriodLength = GeneratedColumn<int>(
    'typical_period_length',
    aliasedName,
    false,
    check: () => ComparableExpr(
      typicalPeriodLength,
    ).isBetweenValues(minTypicalPeriodLength, maxTypicalPeriodLength),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(defaultTypicalPeriodLength),
  );
  static const VerificationMeta _showFertileWindowMeta = const VerificationMeta(
    'showFertileWindow',
  );
  @override
  late final GeneratedColumn<bool> showFertileWindow = GeneratedColumn<bool>(
    'show_fertile_window',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("show_fertile_window" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    onboardingSeen,
    notificationsEnabled,
    periodReminderEnabled,
    fertileWindowRemindersEnabled,
    showDetailsEnabled,
    reminderHour,
    reminderMinute,
    typicalPeriodLength,
    showFertileWindow,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSettingsRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('onboarding_seen')) {
      context.handle(
        _onboardingSeenMeta,
        onboardingSeen.isAcceptableOrUnknown(
          data['onboarding_seen']!,
          _onboardingSeenMeta,
        ),
      );
    }
    if (data.containsKey('notifications_enabled')) {
      context.handle(
        _notificationsEnabledMeta,
        notificationsEnabled.isAcceptableOrUnknown(
          data['notifications_enabled']!,
          _notificationsEnabledMeta,
        ),
      );
    }
    if (data.containsKey('period_reminder_enabled')) {
      context.handle(
        _periodReminderEnabledMeta,
        periodReminderEnabled.isAcceptableOrUnknown(
          data['period_reminder_enabled']!,
          _periodReminderEnabledMeta,
        ),
      );
    }
    if (data.containsKey('fertile_window_reminders_enabled')) {
      context.handle(
        _fertileWindowRemindersEnabledMeta,
        fertileWindowRemindersEnabled.isAcceptableOrUnknown(
          data['fertile_window_reminders_enabled']!,
          _fertileWindowRemindersEnabledMeta,
        ),
      );
    }
    if (data.containsKey('show_details_enabled')) {
      context.handle(
        _showDetailsEnabledMeta,
        showDetailsEnabled.isAcceptableOrUnknown(
          data['show_details_enabled']!,
          _showDetailsEnabledMeta,
        ),
      );
    }
    if (data.containsKey('reminder_hour')) {
      context.handle(
        _reminderHourMeta,
        reminderHour.isAcceptableOrUnknown(
          data['reminder_hour']!,
          _reminderHourMeta,
        ),
      );
    }
    if (data.containsKey('reminder_minute')) {
      context.handle(
        _reminderMinuteMeta,
        reminderMinute.isAcceptableOrUnknown(
          data['reminder_minute']!,
          _reminderMinuteMeta,
        ),
      );
    }
    if (data.containsKey('typical_period_length')) {
      context.handle(
        _typicalPeriodLengthMeta,
        typicalPeriodLength.isAcceptableOrUnknown(
          data['typical_period_length']!,
          _typicalPeriodLengthMeta,
        ),
      );
    }
    if (data.containsKey('show_fertile_window')) {
      context.handle(
        _showFertileWindowMeta,
        showFertileWindow.isAcceptableOrUnknown(
          data['show_fertile_window']!,
          _showFertileWindowMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppSettingsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSettingsRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      onboardingSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}onboarding_seen'],
      )!,
      notificationsEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}notifications_enabled'],
      )!,
      periodReminderEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}period_reminder_enabled'],
      )!,
      fertileWindowRemindersEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}fertile_window_reminders_enabled'],
      )!,
      showDetailsEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}show_details_enabled'],
      )!,
      reminderHour: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reminder_hour'],
      )!,
      reminderMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reminder_minute'],
      )!,
      typicalPeriodLength: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}typical_period_length'],
      )!,
      showFertileWindow: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}show_fertile_window'],
      )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSettingsRow extends DataClass implements Insertable<AppSettingsRow> {
  final int id;
  final bool onboardingSeen;

  /// Interruptor GENERAL de notificaciones (controla el permiso de
  /// Android y si se programa cualquier aviso). No es especifico del
  /// recordatorio de periodo; ver [periodReminderEnabled] para eso.
  /// Default false: las notificaciones son opt-in, no opt-out.
  final bool notificationsEnabled;
  final bool periodReminderEnabled;
  final bool fertileWindowRemindersEnabled;
  final bool showDetailsEnabled;
  final int reminderHour;
  final int reminderMinute;

  /// Duracion habitual del periodo en dias (HU-01): 1 a 15, por defecto 5.
  /// La usa el predictor cuando no hay periodos cerrados (P-1).
  final int typicalPeriodLength;

  /// Mostrar la ovulacion y la ventana fertil estimadas (HU-05, H5-3):
  /// un solo interruptor para las dos. Por defecto activado; una base
  /// migrada desde v4 queda activada (sin cambio visible).
  final bool showFertileWindow;
  const AppSettingsRow({
    required this.id,
    required this.onboardingSeen,
    required this.notificationsEnabled,
    required this.periodReminderEnabled,
    required this.fertileWindowRemindersEnabled,
    required this.showDetailsEnabled,
    required this.reminderHour,
    required this.reminderMinute,
    required this.typicalPeriodLength,
    required this.showFertileWindow,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['onboarding_seen'] = Variable<bool>(onboardingSeen);
    map['notifications_enabled'] = Variable<bool>(notificationsEnabled);
    map['period_reminder_enabled'] = Variable<bool>(periodReminderEnabled);
    map['fertile_window_reminders_enabled'] = Variable<bool>(
      fertileWindowRemindersEnabled,
    );
    map['show_details_enabled'] = Variable<bool>(showDetailsEnabled);
    map['reminder_hour'] = Variable<int>(reminderHour);
    map['reminder_minute'] = Variable<int>(reminderMinute);
    map['typical_period_length'] = Variable<int>(typicalPeriodLength);
    map['show_fertile_window'] = Variable<bool>(showFertileWindow);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(
      id: Value(id),
      onboardingSeen: Value(onboardingSeen),
      notificationsEnabled: Value(notificationsEnabled),
      periodReminderEnabled: Value(periodReminderEnabled),
      fertileWindowRemindersEnabled: Value(fertileWindowRemindersEnabled),
      showDetailsEnabled: Value(showDetailsEnabled),
      reminderHour: Value(reminderHour),
      reminderMinute: Value(reminderMinute),
      typicalPeriodLength: Value(typicalPeriodLength),
      showFertileWindow: Value(showFertileWindow),
    );
  }

  factory AppSettingsRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSettingsRow(
      id: serializer.fromJson<int>(json['id']),
      onboardingSeen: serializer.fromJson<bool>(json['onboardingSeen']),
      notificationsEnabled: serializer.fromJson<bool>(
        json['notificationsEnabled'],
      ),
      periodReminderEnabled: serializer.fromJson<bool>(
        json['periodReminderEnabled'],
      ),
      fertileWindowRemindersEnabled: serializer.fromJson<bool>(
        json['fertileWindowRemindersEnabled'],
      ),
      showDetailsEnabled: serializer.fromJson<bool>(json['showDetailsEnabled']),
      reminderHour: serializer.fromJson<int>(json['reminderHour']),
      reminderMinute: serializer.fromJson<int>(json['reminderMinute']),
      typicalPeriodLength: serializer.fromJson<int>(
        json['typicalPeriodLength'],
      ),
      showFertileWindow: serializer.fromJson<bool>(json['showFertileWindow']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'onboardingSeen': serializer.toJson<bool>(onboardingSeen),
      'notificationsEnabled': serializer.toJson<bool>(notificationsEnabled),
      'periodReminderEnabled': serializer.toJson<bool>(periodReminderEnabled),
      'fertileWindowRemindersEnabled': serializer.toJson<bool>(
        fertileWindowRemindersEnabled,
      ),
      'showDetailsEnabled': serializer.toJson<bool>(showDetailsEnabled),
      'reminderHour': serializer.toJson<int>(reminderHour),
      'reminderMinute': serializer.toJson<int>(reminderMinute),
      'typicalPeriodLength': serializer.toJson<int>(typicalPeriodLength),
      'showFertileWindow': serializer.toJson<bool>(showFertileWindow),
    };
  }

  AppSettingsRow copyWith({
    int? id,
    bool? onboardingSeen,
    bool? notificationsEnabled,
    bool? periodReminderEnabled,
    bool? fertileWindowRemindersEnabled,
    bool? showDetailsEnabled,
    int? reminderHour,
    int? reminderMinute,
    int? typicalPeriodLength,
    bool? showFertileWindow,
  }) => AppSettingsRow(
    id: id ?? this.id,
    onboardingSeen: onboardingSeen ?? this.onboardingSeen,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    periodReminderEnabled: periodReminderEnabled ?? this.periodReminderEnabled,
    fertileWindowRemindersEnabled:
        fertileWindowRemindersEnabled ?? this.fertileWindowRemindersEnabled,
    showDetailsEnabled: showDetailsEnabled ?? this.showDetailsEnabled,
    reminderHour: reminderHour ?? this.reminderHour,
    reminderMinute: reminderMinute ?? this.reminderMinute,
    typicalPeriodLength: typicalPeriodLength ?? this.typicalPeriodLength,
    showFertileWindow: showFertileWindow ?? this.showFertileWindow,
  );
  AppSettingsRow copyWithCompanion(AppSettingsCompanion data) {
    return AppSettingsRow(
      id: data.id.present ? data.id.value : this.id,
      onboardingSeen: data.onboardingSeen.present
          ? data.onboardingSeen.value
          : this.onboardingSeen,
      notificationsEnabled: data.notificationsEnabled.present
          ? data.notificationsEnabled.value
          : this.notificationsEnabled,
      periodReminderEnabled: data.periodReminderEnabled.present
          ? data.periodReminderEnabled.value
          : this.periodReminderEnabled,
      fertileWindowRemindersEnabled: data.fertileWindowRemindersEnabled.present
          ? data.fertileWindowRemindersEnabled.value
          : this.fertileWindowRemindersEnabled,
      showDetailsEnabled: data.showDetailsEnabled.present
          ? data.showDetailsEnabled.value
          : this.showDetailsEnabled,
      reminderHour: data.reminderHour.present
          ? data.reminderHour.value
          : this.reminderHour,
      reminderMinute: data.reminderMinute.present
          ? data.reminderMinute.value
          : this.reminderMinute,
      typicalPeriodLength: data.typicalPeriodLength.present
          ? data.typicalPeriodLength.value
          : this.typicalPeriodLength,
      showFertileWindow: data.showFertileWindow.present
          ? data.showFertileWindow.value
          : this.showFertileWindow,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsRow(')
          ..write('id: $id, ')
          ..write('onboardingSeen: $onboardingSeen, ')
          ..write('notificationsEnabled: $notificationsEnabled, ')
          ..write('periodReminderEnabled: $periodReminderEnabled, ')
          ..write(
            'fertileWindowRemindersEnabled: $fertileWindowRemindersEnabled, ',
          )
          ..write('showDetailsEnabled: $showDetailsEnabled, ')
          ..write('reminderHour: $reminderHour, ')
          ..write('reminderMinute: $reminderMinute, ')
          ..write('typicalPeriodLength: $typicalPeriodLength, ')
          ..write('showFertileWindow: $showFertileWindow')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    onboardingSeen,
    notificationsEnabled,
    periodReminderEnabled,
    fertileWindowRemindersEnabled,
    showDetailsEnabled,
    reminderHour,
    reminderMinute,
    typicalPeriodLength,
    showFertileWindow,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSettingsRow &&
          other.id == this.id &&
          other.onboardingSeen == this.onboardingSeen &&
          other.notificationsEnabled == this.notificationsEnabled &&
          other.periodReminderEnabled == this.periodReminderEnabled &&
          other.fertileWindowRemindersEnabled ==
              this.fertileWindowRemindersEnabled &&
          other.showDetailsEnabled == this.showDetailsEnabled &&
          other.reminderHour == this.reminderHour &&
          other.reminderMinute == this.reminderMinute &&
          other.typicalPeriodLength == this.typicalPeriodLength &&
          other.showFertileWindow == this.showFertileWindow);
}

class AppSettingsCompanion extends UpdateCompanion<AppSettingsRow> {
  final Value<int> id;
  final Value<bool> onboardingSeen;
  final Value<bool> notificationsEnabled;
  final Value<bool> periodReminderEnabled;
  final Value<bool> fertileWindowRemindersEnabled;
  final Value<bool> showDetailsEnabled;
  final Value<int> reminderHour;
  final Value<int> reminderMinute;
  final Value<int> typicalPeriodLength;
  final Value<bool> showFertileWindow;
  const AppSettingsCompanion({
    this.id = const Value.absent(),
    this.onboardingSeen = const Value.absent(),
    this.notificationsEnabled = const Value.absent(),
    this.periodReminderEnabled = const Value.absent(),
    this.fertileWindowRemindersEnabled = const Value.absent(),
    this.showDetailsEnabled = const Value.absent(),
    this.reminderHour = const Value.absent(),
    this.reminderMinute = const Value.absent(),
    this.typicalPeriodLength = const Value.absent(),
    this.showFertileWindow = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    this.id = const Value.absent(),
    this.onboardingSeen = const Value.absent(),
    this.notificationsEnabled = const Value.absent(),
    this.periodReminderEnabled = const Value.absent(),
    this.fertileWindowRemindersEnabled = const Value.absent(),
    this.showDetailsEnabled = const Value.absent(),
    this.reminderHour = const Value.absent(),
    this.reminderMinute = const Value.absent(),
    this.typicalPeriodLength = const Value.absent(),
    this.showFertileWindow = const Value.absent(),
  });
  static Insertable<AppSettingsRow> custom({
    Expression<int>? id,
    Expression<bool>? onboardingSeen,
    Expression<bool>? notificationsEnabled,
    Expression<bool>? periodReminderEnabled,
    Expression<bool>? fertileWindowRemindersEnabled,
    Expression<bool>? showDetailsEnabled,
    Expression<int>? reminderHour,
    Expression<int>? reminderMinute,
    Expression<int>? typicalPeriodLength,
    Expression<bool>? showFertileWindow,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (onboardingSeen != null) 'onboarding_seen': onboardingSeen,
      if (notificationsEnabled != null)
        'notifications_enabled': notificationsEnabled,
      if (periodReminderEnabled != null)
        'period_reminder_enabled': periodReminderEnabled,
      if (fertileWindowRemindersEnabled != null)
        'fertile_window_reminders_enabled': fertileWindowRemindersEnabled,
      if (showDetailsEnabled != null)
        'show_details_enabled': showDetailsEnabled,
      if (reminderHour != null) 'reminder_hour': reminderHour,
      if (reminderMinute != null) 'reminder_minute': reminderMinute,
      if (typicalPeriodLength != null)
        'typical_period_length': typicalPeriodLength,
      if (showFertileWindow != null) 'show_fertile_window': showFertileWindow,
    });
  }

  AppSettingsCompanion copyWith({
    Value<int>? id,
    Value<bool>? onboardingSeen,
    Value<bool>? notificationsEnabled,
    Value<bool>? periodReminderEnabled,
    Value<bool>? fertileWindowRemindersEnabled,
    Value<bool>? showDetailsEnabled,
    Value<int>? reminderHour,
    Value<int>? reminderMinute,
    Value<int>? typicalPeriodLength,
    Value<bool>? showFertileWindow,
  }) {
    return AppSettingsCompanion(
      id: id ?? this.id,
      onboardingSeen: onboardingSeen ?? this.onboardingSeen,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      periodReminderEnabled:
          periodReminderEnabled ?? this.periodReminderEnabled,
      fertileWindowRemindersEnabled:
          fertileWindowRemindersEnabled ?? this.fertileWindowRemindersEnabled,
      showDetailsEnabled: showDetailsEnabled ?? this.showDetailsEnabled,
      reminderHour: reminderHour ?? this.reminderHour,
      reminderMinute: reminderMinute ?? this.reminderMinute,
      typicalPeriodLength: typicalPeriodLength ?? this.typicalPeriodLength,
      showFertileWindow: showFertileWindow ?? this.showFertileWindow,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (onboardingSeen.present) {
      map['onboarding_seen'] = Variable<bool>(onboardingSeen.value);
    }
    if (notificationsEnabled.present) {
      map['notifications_enabled'] = Variable<bool>(notificationsEnabled.value);
    }
    if (periodReminderEnabled.present) {
      map['period_reminder_enabled'] = Variable<bool>(
        periodReminderEnabled.value,
      );
    }
    if (fertileWindowRemindersEnabled.present) {
      map['fertile_window_reminders_enabled'] = Variable<bool>(
        fertileWindowRemindersEnabled.value,
      );
    }
    if (showDetailsEnabled.present) {
      map['show_details_enabled'] = Variable<bool>(showDetailsEnabled.value);
    }
    if (reminderHour.present) {
      map['reminder_hour'] = Variable<int>(reminderHour.value);
    }
    if (reminderMinute.present) {
      map['reminder_minute'] = Variable<int>(reminderMinute.value);
    }
    if (typicalPeriodLength.present) {
      map['typical_period_length'] = Variable<int>(typicalPeriodLength.value);
    }
    if (showFertileWindow.present) {
      map['show_fertile_window'] = Variable<bool>(showFertileWindow.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('id: $id, ')
          ..write('onboardingSeen: $onboardingSeen, ')
          ..write('notificationsEnabled: $notificationsEnabled, ')
          ..write('periodReminderEnabled: $periodReminderEnabled, ')
          ..write(
            'fertileWindowRemindersEnabled: $fertileWindowRemindersEnabled, ',
          )
          ..write('showDetailsEnabled: $showDetailsEnabled, ')
          ..write('reminderHour: $reminderHour, ')
          ..write('reminderMinute: $reminderMinute, ')
          ..write('typicalPeriodLength: $typicalPeriodLength, ')
          ..write('showFertileWindow: $showFertileWindow')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $DailyLogsTable dailyLogs = $DailyLogsTable(this);
  late final $DailyLogSymptomsTable dailyLogSymptoms = $DailyLogSymptomsTable(
    this,
  );
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    dailyLogs,
    dailyLogSymptoms,
    appSettings,
  ];
}

typedef $$DailyLogsTableCreateCompanionBuilder =
    DailyLogsCompanion Function({
      required String date,
      Value<bool> isPeriodDay,
      Value<FlowIntensity?> flow,
      Value<Mood?> mood,
      Value<String?> notes,
      Value<bool> periodDayExplicit,
      Value<PeriodEndSource?> periodEnd,
      Value<int> rowid,
    });
typedef $$DailyLogsTableUpdateCompanionBuilder =
    DailyLogsCompanion Function({
      Value<String> date,
      Value<bool> isPeriodDay,
      Value<FlowIntensity?> flow,
      Value<Mood?> mood,
      Value<String?> notes,
      Value<bool> periodDayExplicit,
      Value<PeriodEndSource?> periodEnd,
      Value<int> rowid,
    });

class $$DailyLogsTableFilterComposer
    extends Composer<_$AppDatabase, $DailyLogsTable> {
  $$DailyLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPeriodDay => $composableBuilder(
    column: $table.isPeriodDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<FlowIntensity?, FlowIntensity, String>
  get flow => $composableBuilder(
    column: $table.flow,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<Mood?, Mood, String> get mood =>
      $composableBuilder(
        column: $table.mood,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get periodDayExplicit => $composableBuilder(
    column: $table.periodDayExplicit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<PeriodEndSource?, PeriodEndSource, String>
  get periodEnd => $composableBuilder(
    column: $table.periodEnd,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );
}

class $$DailyLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $DailyLogsTable> {
  $$DailyLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPeriodDay => $composableBuilder(
    column: $table.isPeriodDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get flow => $composableBuilder(
    column: $table.flow,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mood => $composableBuilder(
    column: $table.mood,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get periodDayExplicit => $composableBuilder(
    column: $table.periodDayExplicit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get periodEnd => $composableBuilder(
    column: $table.periodEnd,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DailyLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DailyLogsTable> {
  $$DailyLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<bool> get isPeriodDay => $composableBuilder(
    column: $table.isPeriodDay,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<FlowIntensity?, String> get flow =>
      $composableBuilder(column: $table.flow, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Mood?, String> get mood =>
      $composableBuilder(column: $table.mood, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<bool> get periodDayExplicit => $composableBuilder(
    column: $table.periodDayExplicit,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<PeriodEndSource?, String> get periodEnd =>
      $composableBuilder(column: $table.periodEnd, builder: (column) => column);
}

class $$DailyLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DailyLogsTable,
          DailyLogRow,
          $$DailyLogsTableFilterComposer,
          $$DailyLogsTableOrderingComposer,
          $$DailyLogsTableAnnotationComposer,
          $$DailyLogsTableCreateCompanionBuilder,
          $$DailyLogsTableUpdateCompanionBuilder,
          (
            DailyLogRow,
            BaseReferences<_$AppDatabase, $DailyLogsTable, DailyLogRow>,
          ),
          DailyLogRow,
          PrefetchHooks Function()
        > {
  $$DailyLogsTableTableManager(_$AppDatabase db, $DailyLogsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailyLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailyLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DailyLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> date = const Value.absent(),
                Value<bool> isPeriodDay = const Value.absent(),
                Value<FlowIntensity?> flow = const Value.absent(),
                Value<Mood?> mood = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<bool> periodDayExplicit = const Value.absent(),
                Value<PeriodEndSource?> periodEnd = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyLogsCompanion(
                date: date,
                isPeriodDay: isPeriodDay,
                flow: flow,
                mood: mood,
                notes: notes,
                periodDayExplicit: periodDayExplicit,
                periodEnd: periodEnd,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String date,
                Value<bool> isPeriodDay = const Value.absent(),
                Value<FlowIntensity?> flow = const Value.absent(),
                Value<Mood?> mood = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<bool> periodDayExplicit = const Value.absent(),
                Value<PeriodEndSource?> periodEnd = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyLogsCompanion.insert(
                date: date,
                isPeriodDay: isPeriodDay,
                flow: flow,
                mood: mood,
                notes: notes,
                periodDayExplicit: periodDayExplicit,
                periodEnd: periodEnd,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DailyLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DailyLogsTable,
      DailyLogRow,
      $$DailyLogsTableFilterComposer,
      $$DailyLogsTableOrderingComposer,
      $$DailyLogsTableAnnotationComposer,
      $$DailyLogsTableCreateCompanionBuilder,
      $$DailyLogsTableUpdateCompanionBuilder,
      (
        DailyLogRow,
        BaseReferences<_$AppDatabase, $DailyLogsTable, DailyLogRow>,
      ),
      DailyLogRow,
      PrefetchHooks Function()
    >;
typedef $$DailyLogSymptomsTableCreateCompanionBuilder =
    DailyLogSymptomsCompanion Function({
      required String logDate,
      required Symptom symptom,
      Value<int> rowid,
    });
typedef $$DailyLogSymptomsTableUpdateCompanionBuilder =
    DailyLogSymptomsCompanion Function({
      Value<String> logDate,
      Value<Symptom> symptom,
      Value<int> rowid,
    });

class $$DailyLogSymptomsTableFilterComposer
    extends Composer<_$AppDatabase, $DailyLogSymptomsTable> {
  $$DailyLogSymptomsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get logDate => $composableBuilder(
    column: $table.logDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Symptom, Symptom, String> get symptom =>
      $composableBuilder(
        column: $table.symptom,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );
}

class $$DailyLogSymptomsTableOrderingComposer
    extends Composer<_$AppDatabase, $DailyLogSymptomsTable> {
  $$DailyLogSymptomsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get logDate => $composableBuilder(
    column: $table.logDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get symptom => $composableBuilder(
    column: $table.symptom,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DailyLogSymptomsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DailyLogSymptomsTable> {
  $$DailyLogSymptomsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get logDate =>
      $composableBuilder(column: $table.logDate, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Symptom, String> get symptom =>
      $composableBuilder(column: $table.symptom, builder: (column) => column);
}

class $$DailyLogSymptomsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DailyLogSymptomsTable,
          DailyLogSymptomRow,
          $$DailyLogSymptomsTableFilterComposer,
          $$DailyLogSymptomsTableOrderingComposer,
          $$DailyLogSymptomsTableAnnotationComposer,
          $$DailyLogSymptomsTableCreateCompanionBuilder,
          $$DailyLogSymptomsTableUpdateCompanionBuilder,
          (
            DailyLogSymptomRow,
            BaseReferences<
              _$AppDatabase,
              $DailyLogSymptomsTable,
              DailyLogSymptomRow
            >,
          ),
          DailyLogSymptomRow,
          PrefetchHooks Function()
        > {
  $$DailyLogSymptomsTableTableManager(
    _$AppDatabase db,
    $DailyLogSymptomsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailyLogSymptomsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailyLogSymptomsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DailyLogSymptomsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> logDate = const Value.absent(),
                Value<Symptom> symptom = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyLogSymptomsCompanion(
                logDate: logDate,
                symptom: symptom,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String logDate,
                required Symptom symptom,
                Value<int> rowid = const Value.absent(),
              }) => DailyLogSymptomsCompanion.insert(
                logDate: logDate,
                symptom: symptom,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DailyLogSymptomsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DailyLogSymptomsTable,
      DailyLogSymptomRow,
      $$DailyLogSymptomsTableFilterComposer,
      $$DailyLogSymptomsTableOrderingComposer,
      $$DailyLogSymptomsTableAnnotationComposer,
      $$DailyLogSymptomsTableCreateCompanionBuilder,
      $$DailyLogSymptomsTableUpdateCompanionBuilder,
      (
        DailyLogSymptomRow,
        BaseReferences<
          _$AppDatabase,
          $DailyLogSymptomsTable,
          DailyLogSymptomRow
        >,
      ),
      DailyLogSymptomRow,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<int> id,
      Value<bool> onboardingSeen,
      Value<bool> notificationsEnabled,
      Value<bool> periodReminderEnabled,
      Value<bool> fertileWindowRemindersEnabled,
      Value<bool> showDetailsEnabled,
      Value<int> reminderHour,
      Value<int> reminderMinute,
      Value<int> typicalPeriodLength,
      Value<bool> showFertileWindow,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<int> id,
      Value<bool> onboardingSeen,
      Value<bool> notificationsEnabled,
      Value<bool> periodReminderEnabled,
      Value<bool> fertileWindowRemindersEnabled,
      Value<bool> showDetailsEnabled,
      Value<int> reminderHour,
      Value<int> reminderMinute,
      Value<int> typicalPeriodLength,
      Value<bool> showFertileWindow,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get onboardingSeen => $composableBuilder(
    column: $table.onboardingSeen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get notificationsEnabled => $composableBuilder(
    column: $table.notificationsEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get periodReminderEnabled => $composableBuilder(
    column: $table.periodReminderEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get fertileWindowRemindersEnabled => $composableBuilder(
    column: $table.fertileWindowRemindersEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get showDetailsEnabled => $composableBuilder(
    column: $table.showDetailsEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reminderHour => $composableBuilder(
    column: $table.reminderHour,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reminderMinute => $composableBuilder(
    column: $table.reminderMinute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get typicalPeriodLength => $composableBuilder(
    column: $table.typicalPeriodLength,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get showFertileWindow => $composableBuilder(
    column: $table.showFertileWindow,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get onboardingSeen => $composableBuilder(
    column: $table.onboardingSeen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get notificationsEnabled => $composableBuilder(
    column: $table.notificationsEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get periodReminderEnabled => $composableBuilder(
    column: $table.periodReminderEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get fertileWindowRemindersEnabled => $composableBuilder(
    column: $table.fertileWindowRemindersEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get showDetailsEnabled => $composableBuilder(
    column: $table.showDetailsEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reminderHour => $composableBuilder(
    column: $table.reminderHour,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reminderMinute => $composableBuilder(
    column: $table.reminderMinute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get typicalPeriodLength => $composableBuilder(
    column: $table.typicalPeriodLength,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get showFertileWindow => $composableBuilder(
    column: $table.showFertileWindow,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<bool> get onboardingSeen => $composableBuilder(
    column: $table.onboardingSeen,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get notificationsEnabled => $composableBuilder(
    column: $table.notificationsEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get periodReminderEnabled => $composableBuilder(
    column: $table.periodReminderEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get fertileWindowRemindersEnabled => $composableBuilder(
    column: $table.fertileWindowRemindersEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get showDetailsEnabled => $composableBuilder(
    column: $table.showDetailsEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reminderHour => $composableBuilder(
    column: $table.reminderHour,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reminderMinute => $composableBuilder(
    column: $table.reminderMinute,
    builder: (column) => column,
  );

  GeneratedColumn<int> get typicalPeriodLength => $composableBuilder(
    column: $table.typicalPeriodLength,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get showFertileWindow => $composableBuilder(
    column: $table.showFertileWindow,
    builder: (column) => column,
  );
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTable,
          AppSettingsRow,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSettingsRow,
            BaseReferences<_$AppDatabase, $AppSettingsTable, AppSettingsRow>,
          ),
          AppSettingsRow,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<bool> onboardingSeen = const Value.absent(),
                Value<bool> notificationsEnabled = const Value.absent(),
                Value<bool> periodReminderEnabled = const Value.absent(),
                Value<bool> fertileWindowRemindersEnabled =
                    const Value.absent(),
                Value<bool> showDetailsEnabled = const Value.absent(),
                Value<int> reminderHour = const Value.absent(),
                Value<int> reminderMinute = const Value.absent(),
                Value<int> typicalPeriodLength = const Value.absent(),
                Value<bool> showFertileWindow = const Value.absent(),
              }) => AppSettingsCompanion(
                id: id,
                onboardingSeen: onboardingSeen,
                notificationsEnabled: notificationsEnabled,
                periodReminderEnabled: periodReminderEnabled,
                fertileWindowRemindersEnabled: fertileWindowRemindersEnabled,
                showDetailsEnabled: showDetailsEnabled,
                reminderHour: reminderHour,
                reminderMinute: reminderMinute,
                typicalPeriodLength: typicalPeriodLength,
                showFertileWindow: showFertileWindow,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<bool> onboardingSeen = const Value.absent(),
                Value<bool> notificationsEnabled = const Value.absent(),
                Value<bool> periodReminderEnabled = const Value.absent(),
                Value<bool> fertileWindowRemindersEnabled =
                    const Value.absent(),
                Value<bool> showDetailsEnabled = const Value.absent(),
                Value<int> reminderHour = const Value.absent(),
                Value<int> reminderMinute = const Value.absent(),
                Value<int> typicalPeriodLength = const Value.absent(),
                Value<bool> showFertileWindow = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                id: id,
                onboardingSeen: onboardingSeen,
                notificationsEnabled: notificationsEnabled,
                periodReminderEnabled: periodReminderEnabled,
                fertileWindowRemindersEnabled: fertileWindowRemindersEnabled,
                showDetailsEnabled: showDetailsEnabled,
                reminderHour: reminderHour,
                reminderMinute: reminderMinute,
                typicalPeriodLength: typicalPeriodLength,
                showFertileWindow: showFertileWindow,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTable,
      AppSettingsRow,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSettingsRow,
        BaseReferences<_$AppDatabase, $AppSettingsTable, AppSettingsRow>,
      ),
      AppSettingsRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$DailyLogsTableTableManager get dailyLogs =>
      $$DailyLogsTableTableManager(_db, _db.dailyLogs);
  $$DailyLogSymptomsTableTableManager get dailyLogSymptoms =>
      $$DailyLogSymptomsTableTableManager(_db, _db.dailyLogSymptoms);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
}
