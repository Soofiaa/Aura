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
  late final GeneratedColumnWithTypeConverter<Flow?, String> flow =
      GeneratedColumn<String>(
        'flow',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<Flow?>($DailyLogsTable.$converterflown);
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
  @override
  List<GeneratedColumn> get $columns => [date, isPeriodDay, flow, mood, notes];
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
    );
  }

  @override
  $DailyLogsTable createAlias(String alias) {
    return $DailyLogsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<Flow, String, String> $converterflow =
      const EnumNameConverter<Flow>(Flow.values);
  static JsonTypeConverter2<Flow?, String?, String?> $converterflown =
      JsonTypeConverter2.asNullable($converterflow);
  static JsonTypeConverter2<Mood, String, String> $convertermood =
      const EnumNameConverter<Mood>(Mood.values);
  static JsonTypeConverter2<Mood?, String?, String?> $convertermoodn =
      JsonTypeConverter2.asNullable($convertermood);
}

class DailyLogRow extends DataClass implements Insertable<DailyLogRow> {
  final String date;
  final bool isPeriodDay;
  final Flow? flow;
  final Mood? mood;
  final String? notes;
  const DailyLogRow({
    required this.date,
    required this.isPeriodDay,
    this.flow,
    this.mood,
    this.notes,
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
    };
  }

  DailyLogRow copyWith({
    String? date,
    bool? isPeriodDay,
    Value<Flow?> flow = const Value.absent(),
    Value<Mood?> mood = const Value.absent(),
    Value<String?> notes = const Value.absent(),
  }) => DailyLogRow(
    date: date ?? this.date,
    isPeriodDay: isPeriodDay ?? this.isPeriodDay,
    flow: flow.present ? flow.value : this.flow,
    mood: mood.present ? mood.value : this.mood,
    notes: notes.present ? notes.value : this.notes,
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
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyLogRow(')
          ..write('date: $date, ')
          ..write('isPeriodDay: $isPeriodDay, ')
          ..write('flow: $flow, ')
          ..write('mood: $mood, ')
          ..write('notes: $notes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(date, isPeriodDay, flow, mood, notes);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyLogRow &&
          other.date == this.date &&
          other.isPeriodDay == this.isPeriodDay &&
          other.flow == this.flow &&
          other.mood == this.mood &&
          other.notes == this.notes);
}

class DailyLogsCompanion extends UpdateCompanion<DailyLogRow> {
  final Value<String> date;
  final Value<bool> isPeriodDay;
  final Value<Flow?> flow;
  final Value<Mood?> mood;
  final Value<String?> notes;
  final Value<int> rowid;
  const DailyLogsCompanion({
    this.date = const Value.absent(),
    this.isPeriodDay = const Value.absent(),
    this.flow = const Value.absent(),
    this.mood = const Value.absent(),
    this.notes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailyLogsCompanion.insert({
    required String date,
    this.isPeriodDay = const Value.absent(),
    this.flow = const Value.absent(),
    this.mood = const Value.absent(),
    this.notes = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : date = Value(date);
  static Insertable<DailyLogRow> custom({
    Expression<String>? date,
    Expression<bool>? isPeriodDay,
    Expression<String>? flow,
    Expression<String>? mood,
    Expression<String>? notes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (date != null) 'date': date,
      if (isPeriodDay != null) 'is_period_day': isPeriodDay,
      if (flow != null) 'flow': flow,
      if (mood != null) 'mood': mood,
      if (notes != null) 'notes': notes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailyLogsCompanion copyWith({
    Value<String>? date,
    Value<bool>? isPeriodDay,
    Value<Flow?>? flow,
    Value<Mood?>? mood,
    Value<String?>? notes,
    Value<int>? rowid,
  }) {
    return DailyLogsCompanion(
      date: date ?? this.date,
      isPeriodDay: isPeriodDay ?? this.isPeriodDay,
      flow: flow ?? this.flow,
      mood: mood ?? this.mood,
      notes: notes ?? this.notes,
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
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    onboardingSeen,
    notificationsEnabled,
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
  final bool notificationsEnabled;
  const AppSettingsRow({
    required this.id,
    required this.onboardingSeen,
    required this.notificationsEnabled,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['onboarding_seen'] = Variable<bool>(onboardingSeen);
    map['notifications_enabled'] = Variable<bool>(notificationsEnabled);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(
      id: Value(id),
      onboardingSeen: Value(onboardingSeen),
      notificationsEnabled: Value(notificationsEnabled),
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
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'onboardingSeen': serializer.toJson<bool>(onboardingSeen),
      'notificationsEnabled': serializer.toJson<bool>(notificationsEnabled),
    };
  }

  AppSettingsRow copyWith({
    int? id,
    bool? onboardingSeen,
    bool? notificationsEnabled,
  }) => AppSettingsRow(
    id: id ?? this.id,
    onboardingSeen: onboardingSeen ?? this.onboardingSeen,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
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
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsRow(')
          ..write('id: $id, ')
          ..write('onboardingSeen: $onboardingSeen, ')
          ..write('notificationsEnabled: $notificationsEnabled')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, onboardingSeen, notificationsEnabled);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSettingsRow &&
          other.id == this.id &&
          other.onboardingSeen == this.onboardingSeen &&
          other.notificationsEnabled == this.notificationsEnabled);
}

class AppSettingsCompanion extends UpdateCompanion<AppSettingsRow> {
  final Value<int> id;
  final Value<bool> onboardingSeen;
  final Value<bool> notificationsEnabled;
  const AppSettingsCompanion({
    this.id = const Value.absent(),
    this.onboardingSeen = const Value.absent(),
    this.notificationsEnabled = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    this.id = const Value.absent(),
    this.onboardingSeen = const Value.absent(),
    this.notificationsEnabled = const Value.absent(),
  });
  static Insertable<AppSettingsRow> custom({
    Expression<int>? id,
    Expression<bool>? onboardingSeen,
    Expression<bool>? notificationsEnabled,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (onboardingSeen != null) 'onboarding_seen': onboardingSeen,
      if (notificationsEnabled != null)
        'notifications_enabled': notificationsEnabled,
    });
  }

  AppSettingsCompanion copyWith({
    Value<int>? id,
    Value<bool>? onboardingSeen,
    Value<bool>? notificationsEnabled,
  }) {
    return AppSettingsCompanion(
      id: id ?? this.id,
      onboardingSeen: onboardingSeen ?? this.onboardingSeen,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
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
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('id: $id, ')
          ..write('onboardingSeen: $onboardingSeen, ')
          ..write('notificationsEnabled: $notificationsEnabled')
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
      Value<Flow?> flow,
      Value<Mood?> mood,
      Value<String?> notes,
      Value<int> rowid,
    });
typedef $$DailyLogsTableUpdateCompanionBuilder =
    DailyLogsCompanion Function({
      Value<String> date,
      Value<bool> isPeriodDay,
      Value<Flow?> flow,
      Value<Mood?> mood,
      Value<String?> notes,
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

  ColumnWithTypeConverterFilters<Flow?, Flow, String> get flow =>
      $composableBuilder(
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

  GeneratedColumnWithTypeConverter<Flow?, String> get flow =>
      $composableBuilder(column: $table.flow, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Mood?, String> get mood =>
      $composableBuilder(column: $table.mood, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);
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
                Value<Flow?> flow = const Value.absent(),
                Value<Mood?> mood = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyLogsCompanion(
                date: date,
                isPeriodDay: isPeriodDay,
                flow: flow,
                mood: mood,
                notes: notes,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String date,
                Value<bool> isPeriodDay = const Value.absent(),
                Value<Flow?> flow = const Value.absent(),
                Value<Mood?> mood = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailyLogsCompanion.insert(
                date: date,
                isPeriodDay: isPeriodDay,
                flow: flow,
                mood: mood,
                notes: notes,
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
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<int> id,
      Value<bool> onboardingSeen,
      Value<bool> notificationsEnabled,
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
              }) => AppSettingsCompanion(
                id: id,
                onboardingSeen: onboardingSeen,
                notificationsEnabled: notificationsEnabled,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<bool> onboardingSeen = const Value.absent(),
                Value<bool> notificationsEnabled = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                id: id,
                onboardingSeen: onboardingSeen,
                notificationsEnabled: notificationsEnabled,
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
