import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/contraceptive.dart';

/// Ajustes de ESTE telefono que no son datos del ciclo: como el estado del
/// recordatorio de respaldo, no van en la base (sin migracion) ni en el
/// respaldo exportado, y ni importar ni "Deshacer" los tocan.
class DeviceSettings {
  const DeviceSettings({
    this.ocultarEnRecientes = true,
    this.avisoAtraso = false,
    this.tema = ThemeMode.system,
    this.recordatorioDiario = false,
    this.anticonceptivo,
  });

  /// "Ocultar Aura en Recientes" (FLAG_SECURE): la miniatura de la app en
  /// Recientes sale en blanco y no se pueden hacer capturas. Activado por
  /// defecto.
  final bool ocultarEnRecientes;

  /// Aviso "Te llego?" el primer dia de atraso del periodo. Opt-in, como
  /// los demas recordatorios, y sujeto al interruptor general.
  final bool avisoAtraso;

  /// Tema claro, oscuro o el del telefono (por defecto).
  final ThemeMode tema;

  /// Un aviso diario a la hora del recordatorio para registrar el dia,
  /// salvo que ese dia ya este registrado. Opt-in.
  final bool recordatorioDiario;

  /// Recordatorio de anticonceptivo; null si esta apagado.
  final ContraceptiveReminder? anticonceptivo;

  DeviceSettings copyWith(
          {bool? ocultarEnRecientes,
          bool? avisoAtraso,
          ThemeMode? tema,
          bool? recordatorioDiario,
          // Funcion para poder apagarlo (null).
          ContraceptiveReminder? Function()? anticonceptivo}) =>
      DeviceSettings(
        ocultarEnRecientes: ocultarEnRecientes ?? this.ocultarEnRecientes,
        avisoAtraso: avisoAtraso ?? this.avisoAtraso,
        tema: tema ?? this.tema,
        recordatorioDiario: recordatorioDiario ?? this.recordatorioDiario,
        anticonceptivo:
            anticonceptivo != null ? anticonceptivo() : this.anticonceptivo,
      );

  Map<String, Object?> toJson() => {
        'version': DeviceSettingsStore.formatVersion,
        'ocultarEnRecientes': ocultarEnRecientes,
        'avisoAtraso': avisoAtraso,
        'tema': tema.name,
        'recordatorioDiario': recordatorioDiario,
        'anticonceptivo': anticonceptivo?.toJson(),
      };

  /// null si [raw] no es un estado valido de la version actual: quien lo
  /// lee usa los valores por defecto.
  static DeviceSettings? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    if (raw['version'] != DeviceSettingsStore.formatVersion) return null;
    final ocultar = raw['ocultarEnRecientes'];
    final aviso = raw['avisoAtraso'];
    if (ocultar is! bool || aviso is! bool) return null;
    // Sin 'tema' (archivos de antes del tema oscuro) o desconocido: el del
    // telefono.
    final tema = ThemeMode.values
        .where((m) => m.name == raw['tema'])
        .firstOrNull ?? ThemeMode.system;
    return DeviceSettings(
        ocultarEnRecientes: ocultar,
        avisoAtraso: aviso,
        tema: tema,
        // Sin el campo (archivos anteriores): apagado.
        recordatorioDiario: raw['recordatorioDiario'] == true,
        // Sin el campo o invalido: apagado.
        anticonceptivo: ContraceptiveReminder.fromJson(raw['anticonceptivo']));
  }

  @override
  bool operator ==(Object other) =>
      other is DeviceSettings &&
      other.ocultarEnRecientes == ocultarEnRecientes &&
      other.avisoAtraso == avisoAtraso &&
      other.tema == tema &&
      other.recordatorioDiario == recordatorioDiario &&
      other.anticonceptivo == anticonceptivo;

  @override
  int get hashCode => 
      Object.hash(ocultarEnRecientes, avisoAtraso, tema, recordatorioDiario,
          anticonceptivo);

  @override
  String toString() => 'DeviceSettings(ocultarEnRecientes: '
      '$ocultarEnRecientes, avisoAtraso: $avisoAtraso, tema: $tema, '
      'recordatorioDiario: $recordatorioDiario, '
      'anticonceptivo: $anticonceptivo)';
}

/// Guarda [DeviceSettings] en un JSON pequeno en el almacenamiento privado
/// de la app, con el mismo esquema que BackupReminderStore: operaciones en
/// fila y escritura atomica (temporal + rename).
class DeviceSettingsStore {
  DeviceSettingsStore({required Future<Directory> Function() supportDirectory})
      : _supportDirectory = supportDirectory;

  static const String fileName = 'ajustes_telefono.json';
  static const int formatVersion = 1;

  final Future<Directory> Function() _supportDirectory;

  final StreamController<DeviceSettings> _changes =
      StreamController<DeviceSettings>.broadcast();
  Future<void> _fila = Future.value();

  Future<File> _file() async =>
      File(p.join((await _supportDirectory()).path, fileName));

  /// El estado actual y despues cada cambio. Admite varias suscripciones.
  Stream<DeviceSettings> watch() => Stream.multi((controller) {
        final sub = _changes.stream.listen(controller.add);
        read().then(controller.add, onError: controller.addError);
        controller.onCancel = sub.cancel;
      });

  /// Lee el estado. Si no existe, esta danado o no se puede leer, devuelve
  /// los valores por defecto (no los escribe: no hace falta).
  Future<DeviceSettings> read() => _enFila(() => _leer());

  Future<DeviceSettings> setOcultarEnRecientes(bool value) =>
      _actualizar((s) => s.copyWith(ocultarEnRecientes: value));

  Future<DeviceSettings> setAvisoAtraso(bool value) =>
      _actualizar((s) => s.copyWith(avisoAtraso: value));

  Future<DeviceSettings> setTema(ThemeMode value) =>
      _actualizar((s) => s.copyWith(tema: value));

  Future<DeviceSettings> setRecordatorioDiario(bool value) =>
      _actualizar((s) => s.copyWith(recordatorioDiario: value));

  Future<DeviceSettings> setAnticonceptivo(ContraceptiveReminder? value) =>
      _actualizar((s) => s.copyWith(anticonceptivo: () => value));

  /// "Borrar todos los datos": vuelve a los valores por defecto.
  Future<void> delete() => _enFila(() async {
        final file = await _file();
        for (final f in [file, File('${file.path}.tmp')]) {
          if (await f.exists()) await f.delete();
        }
        _changes.add(const DeviceSettings());
      });

  Future<T> _enFila<T>(Future<T> Function() op) {
    final result = _fila.then((_) => op());
    _fila = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<DeviceSettings> _actualizar(
          DeviceSettings Function(DeviceSettings) cambio) =>
      _enFila(() async {
        final nuevo = cambio(await _leer(paraEscribir: true));
        await _escribir(nuevo);
        _changes.add(nuevo);
        return nuevo;
      });

  /// [paraEscribir]: si el archivo existe pero no se puede leer, lanza en
  /// vez de devolver los valores por defecto, para no pisar un estado
  /// valido.
  Future<DeviceSettings> _leer({bool paraEscribir = false}) async {
    final file = await _file();
    try {
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final state = DeviceSettings.fromJson(jsonDecode(utf8.decode(bytes)));
        if (state != null) return state;
      }
    } on FileSystemException {
      if (paraEscribir) rethrow;
    } on FormatException {
      // Archivo danado: valores por defecto.
    }
    return const DeviceSettings();
  }

  Future<void> _escribir(DeviceSettings state) async {
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

DeviceSettingsStore? _deviceSettingsStoreInstance;

/// Instancia unica para la app, como backupReminderStore.
DeviceSettingsStore get deviceSettingsStore => _deviceSettingsStoreInstance ??=
    DeviceSettingsStore(supportDirectory: getApplicationSupportDirectory);

/// Solo para tests.
set deviceSettingsStore(DeviceSettingsStore value) =>
    _deviceSettingsStoreInstance = value;
