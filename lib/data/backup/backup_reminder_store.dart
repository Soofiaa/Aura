import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/backup_reminder.dart';
import '../../utils/day_key.dart';

/// Estado del recordatorio de respaldo de ESTE telefono. No es un dato de
/// salud ni un ajuste del ciclo: no va en la base (sin migracion) ni en el
/// respaldo exportado, y ni importar ni "Deshacer" lo tocan.
class BackupReminderState {
  const BackupReminderState({
    required this.primerUso,
    this.ultimoRespaldo,
    this.pospuestoHasta,
    this.activado = true,
  });

  /// Primera vez que se leyo el estado (o desde "Borrar todos los datos").
  final String primerUso;

  /// Ultimo respaldo guardado, o compartido con exito, desde este telefono.
  final String? ultimoRespaldo;

  /// "Ahora no": el recordatorio vuelve este dia (ver
  /// deberiaRecordarRespaldo).
  final String? pospuestoHasta;

  /// Interruptor "Recordarme crear un respaldo" (activado por defecto).
  final bool activado;

  BackupReminderState copyWith({
    String? ultimoRespaldo,
    String? pospuestoHasta,
    bool clearPospuestoHasta = false,
    bool? activado,
  }) =>
      BackupReminderState(
        primerUso: primerUso,
        ultimoRespaldo: ultimoRespaldo ?? this.ultimoRespaldo,
        pospuestoHasta:
            clearPospuestoHasta ? null : (pospuestoHasta ?? this.pospuestoHasta),
        activado: activado ?? this.activado,
      );

  Map<String, Object?> toJson() => {
        'version': BackupReminderStore.formatVersion,
        'primerUso': primerUso,
        'ultimoRespaldo': ultimoRespaldo,
        'pospuestoHasta': pospuestoHasta,
        'activado': activado,
      };

  /// null si [raw] no es un estado valido de la version actual: quien lo
  /// lee usa los valores por defecto.
  static BackupReminderState? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    if (raw['version'] != BackupReminderStore.formatVersion) return null;
    final primerUso = raw['primerUso'];
    final ultimoRespaldo = raw['ultimoRespaldo'];
    final pospuestoHasta = raw['pospuestoHasta'];
    final activado = raw['activado'];
    if (primerUso is! String || !_esDayKey(primerUso)) return null;
    if (ultimoRespaldo != null &&
        (ultimoRespaldo is! String || !_esDayKey(ultimoRespaldo))) {
      return null;
    }
    if (pospuestoHasta != null &&
        (pospuestoHasta is! String || !_esDayKey(pospuestoHasta))) {
      return null;
    }
    if (activado is! bool) return null;
    return BackupReminderState(
      primerUso: primerUso,
      ultimoRespaldo: ultimoRespaldo as String?,
      pospuestoHasta: pospuestoHasta as String?,
      activado: activado,
    );
  }

  static final _formatoDayKey = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// 'yyyy-MM-dd' de un dia que existe (rechaza 2026-02-30).
  static bool _esDayKey(String key) =>
      _formatoDayKey.hasMatch(key) &&
      DayKey.fromDate(DayKey.toUtcAnchor(key)) == key;

  @override
  bool operator ==(Object other) =>
      other is BackupReminderState &&
      other.primerUso == primerUso &&
      other.ultimoRespaldo == ultimoRespaldo &&
      other.pospuestoHasta == pospuestoHasta &&
      other.activado == activado;

  @override
  int get hashCode =>
      Object.hash(primerUso, ultimoRespaldo, pospuestoHasta, activado);

  @override
  String toString() => 'BackupReminderState(primerUso: $primerUso, '
      'ultimoRespaldo: $ultimoRespaldo, pospuestoHasta: $pospuestoHasta, '
      'activado: $activado)';
}

/// Guarda [BackupReminderState] en un JSON pequeno en el almacenamiento
/// privado de la app (files/), fuera de la base: asi no hace falta migrar
/// ni cambia el formato del respaldo. Las operaciones van en fila (una a
/// la vez) y cada escritura es atomica (temporal + rename), como la copia
/// previa a importar de BackupService.
class BackupReminderStore {
  BackupReminderStore({
    required Future<Directory> Function() supportDirectory,
    DateTime Function()? clock,
  })  : _supportDirectory = supportDirectory,
        _clock = clock ?? DateTime.now;

  static const String fileName = 'recordatorio_respaldo.json';
  static const int formatVersion = 1;

  final Future<Directory> Function() _supportDirectory;
  final DateTime Function() _clock;

  final StreamController<BackupReminderState> _changes =
      StreamController<BackupReminderState>.broadcast();
  Future<void> _fila = Future.value();

  /// Hoy segun el reloj del almacen (el mismo que anota las fechas).
  String today() => DayKey.fromDate(_clock());

  Future<File> _file() async =>
      File(p.join((await _supportDirectory()).path, fileName));

  /// El estado actual y despues cada cambio, para la interfaz. Admite
  /// varias suscripciones (tambien volver a escuchar el mismo stream):
  /// cada una lee el estado por su cuenta y suelta la suya al cancelar.
  Stream<BackupReminderState> watch() =>
      Stream.multi((controller) {
        final sub = _changes.stream.listen(controller.add);
        read().then(controller.add, onError: controller.addError);
        controller.onCancel = sub.cancel;
      });

  /// Lee el estado. La primera vez (o si el archivo esta danado o es de
  /// una version desconocida) usa los valores por defecto con primerUso =
  /// hoy y los guarda. Si no los puede guardar, igual los devuelve: nunca
  /// impide usar la app. Si el archivo existe pero falla la lectura, solo
  /// devuelve los valores por defecto: no pisa un estado que puede ser
  /// valido.
  Future<BackupReminderState> read() => _enFila(_leer);

  /// Un respaldo se guardo o se compartio con exito hoy. Tambien quita un
  /// "Ahora no" pendiente. Lanza si no se puede escribir.
  Future<BackupReminderState> recordBackup() => _actualizar((s) =>
      s.copyWith(ultimoRespaldo: today(), clearPospuestoHasta: true));

  /// "Ahora no": pospone [diasPosponerRecordatorioRespaldo] dias.
  Future<BackupReminderState> postpone() => _actualizar((s) => s.copyWith(
      pospuestoHasta:
          DayKey.addDays(today(), diasPosponerRecordatorioRespaldo)));

  /// Interruptor "Recordarme crear un respaldo".
  Future<BackupReminderState> setEnabled(bool value) =>
      _actualizar((s) => s.copyWith(activado: value));

  /// "Borrar todos los datos": borra el archivo (y un .tmp huerfano). La
  /// interfaz recibe los valores por defecto; se vuelven a guardar en la
  /// proxima lectura.
  Future<void> delete() => _enFila(() async {
        final file = await _file();
        for (final f in [file, File('${file.path}.tmp')]) {
          if (await f.exists()) await f.delete();
        }
        _changes.add(BackupReminderState(primerUso: today()));
      });

  Future<T> _enFila<T>(Future<T> Function() op) {
    final result = _fila.then((_) => op());
    _fila = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<BackupReminderState> _actualizar(
          BackupReminderState Function(BackupReminderState) cambio) =>
      _enFila(() async {
        final nuevo = cambio(await _leer(paraEscribir: true));
        await _escribir(nuevo);
        _changes.add(nuevo);
        return nuevo;
      });

  /// [paraEscribir]: si el archivo existe pero no se puede leer, lanza en
  /// vez de devolver los valores por defecto, para que la escritura que
  /// sigue no reemplace un estado valido por uno nuevo.
  Future<BackupReminderState> _leer({bool paraEscribir = false}) async {
    final file = await _file();
    try {
      if (await file.exists()) {
        // Bytes y decodificacion aparte: un UTF-8 invalido es un archivo
        // danado (FormatException), no un error de lectura.
        final bytes = await file.readAsBytes();
        final state =
            BackupReminderState.fromJson(jsonDecode(utf8.decode(bytes)));
        if (state != null) return state;
      }
    } on FileSystemException {
      // Existe pero no se pudo leer (permisos, E/S): no se reescribe.
      if (paraEscribir) rethrow;
      return BackupReminderState(primerUso: today());
    } on FormatException {
      // Archivo danado: se usan los valores por defecto.
    }
    final inicial = BackupReminderState(primerUso: today());
    try {
      await _escribir(inicial);
    } on FileSystemException {
      // Se reintenta en la proxima lectura o escritura.
    }
    return inicial;
  }

  Future<void> _escribir(BackupReminderState state) async {
    final target = await _file();
    final tmp = File('${target.path}.tmp');
    try {
      await target.parent.create(recursive: true);
      if (await tmp.exists()) await tmp.delete();
      await tmp.writeAsString(jsonEncode(state.toJson()), flush: true);
      await tmp.rename(target.path);
    } on FileSystemException {
      try {
        if (await tmp.exists()) await tmp.delete();
      } on FileSystemException {
        // Se limpia en la proxima escritura o al borrar los datos.
      }
      rethrow;
    }
  }
}

BackupReminderStore? _backupReminderStoreInstance;

/// Instancia unica para la app, como [backupService].
BackupReminderStore get backupReminderStore =>
    _backupReminderStoreInstance ??=
        BackupReminderStore(supportDirectory: getApplicationSupportDirectory);

/// Solo para tests.
set backupReminderStore(BackupReminderStore value) =>
    _backupReminderStoreInstance = value;
