import 'dart:convert';

import '../data/models/day_enums.dart';
import '../utils/day_key.dart';

/// Formato de respaldo de Aura (HU-06): JSON propio y versionado, sin
/// depender de drift ni de Flutter, para poder validarlo entero en
/// memoria antes de tocar la base de datos.
///
/// - `formatVersion` versiona el envoltorio (cifrado incluido, HU-06b).
/// - `schemaVersion` versiona los datos: es el schema drift con que se
///   exporto. Un respaldo de un schema anterior se importa; uno posterior
///   se rechaza.
const String backupFormatId = 'aura-backup';
const int backupFormatVersion = 1;

/// Schema drift actual (AppDatabase.schemaVersion). Duplicado aca para
/// que el dominio no importe drift; un test compara ambos valores.
const int currentBackupSchemaVersion = 3;

/// Primer schema que pudo exportar respaldos (la funcion nace en v3):
/// un `schemaVersion` menor no puede venir de Aura.
const int minBackupSchemaVersion = 3;

/// Tope de tamano del archivo antes de parsearlo. Un ano completo con
/// registro diario pesa unos 55 KB; 5 MB deja margen de sobra y evita
/// cargar en memoria un archivo cualquiera elegido por error.
const int maxBackupSizeBytes = 5 * 1024 * 1024;

/// Fecha minima aceptada en un respaldo. Ninguna pantalla permitio nunca
/// fechas anteriores a 2020 (formulario y calendario desde v1.0), pero la
/// pregunta de Inicio guarda "hoy" segun el reloj del telefono, que puede
/// estar mal puesto. 1970-01-01 es el inicio del reloj de Android: nada
/// legitimo puede ser anterior, y basta para rechazar basura como el
/// ano 0001.
const String minBackupDate = '1970-01-01';

/// Las fechas futuras del formulario de la v1.0 llegaban hasta el
/// 2030-12-31 (`lastDate: DateTime(2030)`, commit inicial), asi que un
/// respaldo legitimo puede traerlas aunque hoy ya no se puedan crear.
const String legacyMaxBackupDate = '2030-12-31';

/// Margen sobre la fecha de exportacion para el tope superior: cubre la
/// diferencia de zona horaria entre el instante de exportacion y el dia
/// local guardado.
const int exportDateMarginDays = 2;

class BackupDay {
  const BackupDay({
    required this.date,
    required this.isPeriodDay,
    required this.periodDayExplicit,
    this.flow,
    this.mood,
    this.notes,
    this.symptoms = const [],
  });

  final String date;
  final bool isPeriodDay;
  final bool periodDayExplicit;
  final FlowIntensity? flow;
  final Mood? mood;
  final String? notes;
  final List<Symptom> symptoms;

  @override
  bool operator ==(Object other) =>
      other is BackupDay &&
      other.date == date &&
      other.isPeriodDay == isPeriodDay &&
      other.periodDayExplicit == periodDayExplicit &&
      other.flow == flow &&
      other.mood == mood &&
      other.notes == notes &&
      _listEquals(other.symptoms, symptoms);

  @override
  int get hashCode => Object.hash(date, isPeriodDay, periodDayExplicit, flow,
      mood, notes, Object.hashAll(symptoms));

  @override
  String toString() => 'BackupDay($date, period=$isPeriodDay, '
      'explicit=$periodDayExplicit, $flow, $mood, $notes, $symptoms)';
}

class BackupSettings {
  const BackupSettings({
    required this.onboardingSeen,
    required this.notificationsEnabled,
    required this.periodReminderEnabled,
    required this.fertileWindowRemindersEnabled,
    required this.showDetailsEnabled,
    required this.reminderHour,
    required this.reminderMinute,
  });

  final bool onboardingSeen;
  final bool notificationsEnabled;
  final bool periodReminderEnabled;
  final bool fertileWindowRemindersEnabled;
  final bool showDetailsEnabled;
  final int reminderHour;
  final int reminderMinute;

  @override
  bool operator ==(Object other) =>
      other is BackupSettings &&
      other.onboardingSeen == onboardingSeen &&
      other.notificationsEnabled == notificationsEnabled &&
      other.periodReminderEnabled == periodReminderEnabled &&
      other.fertileWindowRemindersEnabled == fertileWindowRemindersEnabled &&
      other.showDetailsEnabled == showDetailsEnabled &&
      other.reminderHour == reminderHour &&
      other.reminderMinute == reminderMinute;

  @override
  int get hashCode => Object.hash(
      onboardingSeen,
      notificationsEnabled,
      periodReminderEnabled,
      fertileWindowRemindersEnabled,
      showDetailsEnabled,
      reminderHour,
      reminderMinute);
}

/// Contenido completo de un respaldo, ya validado.
class BackupData {
  const BackupData({
    required this.schemaVersion,
    required this.appVersion,
    required this.exportedAt,
    required this.days,
    required this.settings,
  });

  final int schemaVersion;
  final String appVersion;

  /// Instante de exportacion en ISO 8601 con desfase de zona
  /// (ej. 2026-10-04T10:15:00-03:00), tal como se escribio.
  final String exportedAt;

  final List<BackupDay> days;
  final BackupSettings settings;

  int get symptomCount =>
      days.fold(0, (total, day) => total + day.symptoms.length);
}

/// Por que se rechazo un archivo. La UI elige el mensaje segun esto;
/// [BackupParseFailure.detail] es solo para tests y depuracion, nunca se
/// muestra.
enum BackupError {
  /// No es JSON, no es un objeto o no tiene `format: aura-backup`.
  notABackup,

  /// Es un respaldo de Aura pero el contenido no pasa la validacion.
  damaged,

  /// Viene de una version mas nueva de Aura (schema, envoltorio o
  /// cifrado que esta version no conoce).
  newerVersion,

  /// Supera [maxBackupSizeBytes].
  tooLarge,

  /// El archivo elegido no se pudo leer del disco.
  unreadable,
}

sealed class BackupParseResult {
  const BackupParseResult();
}

class BackupParseSuccess extends BackupParseResult {
  const BackupParseSuccess(this.data);
  final BackupData data;
}

class BackupParseFailure extends BackupParseResult {
  const BackupParseFailure(this.error, this.detail, {this.outOfRangeDate});
  final BackupError error;
  final String detail;

  /// Fecha 'yyyy-MM-dd' que quedo fuera de [minBackupDate] y el tope
  /// superior, si ese fue el motivo del rechazo. Dato estructurado para
  /// que la UI arme el mensaje sin leer [detail].
  final String? outOfRangeDate;

  @override
  String toString() => 'BackupParseFailure($error: $detail)';
}

/// Serializa [data] de forma determinista: dias ordenados por fecha y
/// sintomas por nombre, claves siempre en el mismo orden. Dos
/// exportaciones de los mismos datos producen el mismo texto (salvo
/// `exportedAt`).
String encodeBackup(BackupData data) {
  final days = [...data.days]..sort((a, b) => a.date.compareTo(b.date));
  final dailyLogs = [
    for (final day in days)
      {
        'date': day.date,
        'isPeriodDay': day.isPeriodDay,
        'periodDayExplicit': day.periodDayExplicit,
        'flow': day.flow?.name,
        'mood': day.mood?.name,
        'notes': day.notes,
        'symptoms': [for (final s in day.symptoms) s.name]..sort(),
      },
  ];
  final s = data.settings;
  final root = {
    'format': backupFormatId,
    'formatVersion': backupFormatVersion,
    'schemaVersion': data.schemaVersion,
    'app': 'Aura',
    'appVersion': data.appVersion,
    'exportedAt': data.exportedAt,
    'encryption': null,
    'data': {
      'dailyLogs': dailyLogs,
      'settings': {
        'onboardingSeen': s.onboardingSeen,
        'notificationsEnabled': s.notificationsEnabled,
        'periodReminderEnabled': s.periodReminderEnabled,
        'fertileWindowRemindersEnabled': s.fertileWindowRemindersEnabled,
        'showDetailsEnabled': s.showDetailsEnabled,
        'reminderHour': s.reminderHour,
        'reminderMinute': s.reminderMinute,
      },
    },
    'counts': {
      'dailyLogs': days.length,
      'symptoms': data.symptomCount,
    },
  };
  return '${const JsonEncoder.withIndent('  ').convert(root)}\n';
}

/// Instante local en ISO 8601 con desfase de zona, al segundo
/// (ej. 2026-10-04T10:15:00-03:00). DateTime.toIso8601String() de una
/// hora local no incluye el desfase.
String formatExportedAt(DateTime local) {
  String two(int n) => n.toString().padLeft(2, '0');
  final offset = local.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final abs = offset.abs();
  return '${DayKey.fromDate(local)}T${two(local.hour)}:${two(local.minute)}:'
      '${two(local.second)}$sign${two(abs.inHours)}:'
      '${two(abs.inMinutes.remainder(60))}';
}

/// Valida y decodifica un archivo de respaldo completo. No lanza: todo
/// problema vuelve como [BackupParseFailure].
BackupParseResult decodeBackup(List<int> bytes) {
  if (bytes.length > maxBackupSizeBytes) {
    return BackupParseFailure(
        BackupError.tooLarge, '${bytes.length} bytes');
  }
  final Object? root;
  try {
    root = jsonDecode(utf8.decode(bytes));
  } on FormatException catch (e) {
    // Un respaldo de Aura cortado a la mitad deja de ser JSON valido,
    // pero sigue siendo "un respaldo danado" y no "otro archivo".
    final text = utf8.decode(bytes, allowMalformed: true);
    final error = text.contains('"$backupFormatId"')
        ? BackupError.damaged
        : BackupError.notABackup;
    return BackupParseFailure(error, 'no es JSON: $e');
  }
  if (root is! Map<String, dynamic> || root['format'] != backupFormatId) {
    return const BackupParseFailure(
        BackupError.notABackup, 'falta format: aura-backup');
  }
  try {
    return BackupParseSuccess(_parseRoot(root));
  } on _Invalid catch (e) {
    return BackupParseFailure(e.error, e.detail,
        outOfRangeDate: e.outOfRangeDate);
  }
}

class _Invalid implements Exception {
  _Invalid(this.detail, [this.error = BackupError.damaged])
      : outOfRangeDate = null;
  _Invalid.outOfRange(String date)
      : detail = 'fecha fuera de rango $date',
        error = BackupError.damaged,
        outOfRangeDate = date;
  final String detail;
  final BackupError error;
  final String? outOfRangeDate;
}

BackupData _parseRoot(Map<String, dynamic> root) {
  final formatVersion = _int(root, 'formatVersion');
  if (formatVersion > backupFormatVersion) {
    throw _Invalid('formatVersion $formatVersion', BackupError.newerVersion);
  }
  if (formatVersion < 1) throw _Invalid('formatVersion $formatVersion');

  // El cifrado llega con HU-06b: un archivo cifrado solo puede venir de
  // una version mas nueva.
  if (!root.containsKey('encryption')) throw _Invalid('falta encryption');
  if (root['encryption'] != null) {
    throw _Invalid('respaldo cifrado', BackupError.newerVersion);
  }

  final schemaVersion = _int(root, 'schemaVersion');
  if (schemaVersion > currentBackupSchemaVersion) {
    throw _Invalid('schemaVersion $schemaVersion', BackupError.newerVersion);
  }
  if (schemaVersion < minBackupSchemaVersion) {
    throw _Invalid('schemaVersion $schemaVersion');
  }

  _string(root, 'app');
  final appVersion = _string(root, 'appVersion');
  final exportedAt = _string(root, 'exportedAt');
  final exportedAtDate = DateTime.tryParse(exportedAt);
  if (exportedAtDate == null) throw _Invalid('exportedAt $exportedAt');

  final data = _map(root, 'data');
  final maxDate = _maxAllowedDate(exportedAt);
  final rawLogs = _list(data, 'dailyLogs');
  final days = <BackupDay>[];
  final seen = <String>{};
  for (final raw in rawLogs) {
    if (raw is! Map<String, dynamic>) throw _Invalid('dia no es objeto');
    final day = _parseDay(raw, maxDate);
    if (!seen.add(day.date)) throw _Invalid('fecha repetida ${day.date}');
    days.add(day);
  }
  days.sort((a, b) => a.date.compareTo(b.date));

  final settings = _parseSettings(_map(data, 'settings'));

  final result = BackupData(
    schemaVersion: schemaVersion,
    appVersion: appVersion,
    exportedAt: exportedAt,
    days: List.unmodifiable(days),
    settings: settings,
  );

  // counts detecta un archivo truncado o editado a mano que, aun siendo
  // JSON valido, perdio dias o sintomas.
  final counts = _map(root, 'counts');
  if (_int(counts, 'dailyLogs') != days.length ||
      _int(counts, 'symptoms') != result.symptomCount) {
    throw _Invalid('counts no coincide con los datos');
  }
  return result;
}

/// Tope superior de fechas: el mayor entre el limite historico del
/// formulario v1.0 y la fecha de exportacion mas un margen. Que dependa
/// de `exportedAt` hace que un telefono con el reloj adelantado siga
/// pudiendo restaurar lo que el mismo guardo.
String _maxAllowedDate(String exportedAt) {
  final exportDay =
      exportedAt.length >= 10 ? exportedAt.substring(0, 10) : '';
  final candidate = _isValidDayKey(exportDay)
      ? DayKey.addDays(exportDay, exportDateMarginDays)
      : legacyMaxBackupDate;
  return candidate.compareTo(legacyMaxBackupDate) > 0
      ? candidate
      : legacyMaxBackupDate;
}

final _dayKeyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Formato 'yyyy-MM-dd' Y fecha real de calendario (rechaza 2026-02-30).
bool _isValidDayKey(String value) {
  if (!_dayKeyPattern.hasMatch(value)) return false;
  final parts = value.split('-').map(int.parse).toList();
  final date = DateTime.utc(parts[0], parts[1], parts[2]);
  return DayKey.fromDate(date) == value;
}

BackupDay _parseDay(Map<String, dynamic> raw, String maxDate) {
  final date = _string(raw, 'date');
  if (!_isValidDayKey(date)) throw _Invalid('fecha invalida $date');
  if (date.compareTo(minBackupDate) < 0 || date.compareTo(maxDate) > 0) {
    throw _Invalid.outOfRange(date);
  }
  final isPeriodDay = _bool(raw, 'isPeriodDay');
  final flow = _enumOrNull(raw, 'flow', FlowIntensity.values);
  if (flow != null && !isPeriodDay) {
    throw _Invalid('flujo sin sangrado en $date');
  }
  final rawSymptoms = _list(raw, 'symptoms');
  final symptoms = <Symptom>[];
  for (final s in rawSymptoms) {
    final symptom = s is String ? _byName(Symptom.values, s) : null;
    if (symptom == null) throw _Invalid('sintoma invalido $s en $date');
    if (symptoms.contains(symptom)) {
      throw _Invalid('sintoma repetido $s en $date');
    }
    symptoms.add(symptom);
  }
  symptoms.sort((a, b) => a.name.compareTo(b.name));
  if (!raw.containsKey('notes')) throw _Invalid('falta notes en $date');
  final notes = raw['notes'];
  if (notes != null && notes is! String) throw _Invalid('notes en $date');
  return BackupDay(
    date: date,
    isPeriodDay: isPeriodDay,
    periodDayExplicit: _bool(raw, 'periodDayExplicit'),
    flow: flow,
    mood: _enumOrNull(raw, 'mood', Mood.values),
    notes: notes as String?,
    symptoms: List.unmodifiable(symptoms),
  );
}

BackupSettings _parseSettings(Map<String, dynamic> raw) {
  final hour = _int(raw, 'reminderHour');
  final minute = _int(raw, 'reminderMinute');
  if (hour < 0 || hour > 23) throw _Invalid('reminderHour $hour');
  if (minute < 0 || minute > 59) throw _Invalid('reminderMinute $minute');
  return BackupSettings(
    onboardingSeen: _bool(raw, 'onboardingSeen'),
    notificationsEnabled: _bool(raw, 'notificationsEnabled'),
    periodReminderEnabled: _bool(raw, 'periodReminderEnabled'),
    fertileWindowRemindersEnabled:
        _bool(raw, 'fertileWindowRemindersEnabled'),
    showDetailsEnabled: _bool(raw, 'showDetailsEnabled'),
    reminderHour: hour,
    reminderMinute: minute,
  );
}

T _typed<T>(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! T) throw _Invalid('campo $key');
  return value;
}

int _int(Map<String, dynamic> map, String key) => _typed<int>(map, key);
bool _bool(Map<String, dynamic> map, String key) => _typed<bool>(map, key);
String _string(Map<String, dynamic> map, String key) =>
    _typed<String>(map, key);
List<dynamic> _list(Map<String, dynamic> map, String key) =>
    _typed<List<dynamic>>(map, key);
Map<String, dynamic> _map(Map<String, dynamic> map, String key) =>
    _typed<Map<String, dynamic>>(map, key);

/// null solo si la clave existe con valor null; una clave ausente o un
/// valor desconocido es un archivo danado.
T? _enumOrNull<T extends Enum>(
    Map<String, dynamic> map, String key, List<T> values) {
  if (!map.containsKey(key)) throw _Invalid('falta $key');
  final value = map[key];
  if (value == null) return null;
  final parsed = value is String ? _byName(values, value) : null;
  if (parsed == null) throw _Invalid('$key invalido: $value');
  return parsed;
}

T? _byName<T extends Enum>(List<T> values, String name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
