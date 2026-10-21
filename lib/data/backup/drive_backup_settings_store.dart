import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'drive_api_client.dart';

/// Ajustes del respaldo automatico en Google Drive (HU-09). Como los demas
/// datos de este telefono: fuera de la base y del respaldo exportado, sin
/// migracion, y "Borrar todos los datos" los borra.
class DriveBackupSettings {
  const DriveBackupSettings({
    this.habilitado = false,
    this.cuenta = '',
    this.claveSellada = '',
    this.ultimoRespaldo,
    this.ultimoFallo,
  });

  /// Prendido o no por la usuaria.
  final bool habilitado;

  /// Correo de la cuenta de Google elegida; vacio si nunca se activo.
  final String cuenta;

  /// La clave que protege los archivos, sellada por el Keystore de Android
  /// (base64). NUNCA la clave en claro: si el Keystore la pierde, hace
  /// falta que la usuaria vuelva a definirla.
  final String claveSellada;

  /// Dia ('yyyy-MM-dd') del ultimo respaldo automatico con exito.
  final String? ultimoRespaldo;

  /// Ultimo fallo conocido, para que Ajustes lo muestre. null = sin fallo.
  final DriveApiFailure? ultimoFallo;

  DriveBackupSettings copyWith({
    bool? habilitado,
    String? cuenta,
    String? claveSellada,
  }) =>
      DriveBackupSettings(
        habilitado: habilitado ?? this.habilitado,
        cuenta: cuenta ?? this.cuenta,
        claveSellada: claveSellada ?? this.claveSellada,
        ultimoRespaldo: ultimoRespaldo,
        ultimoFallo: ultimoFallo,
      );

  Map<String, Object?> toJson() => {
        'version': DriveBackupSettingsStore.formatVersion,
        'habilitado': habilitado,
        'cuenta': cuenta,
        'claveSellada': claveSellada,
        'ultimoRespaldo': ultimoRespaldo,
        'ultimoFallo': ultimoFallo?.name,
      };

  static DriveBackupSettings? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    if (raw['version'] != DriveBackupSettingsStore.formatVersion) return null;
    final habilitado = raw['habilitado'];
    final cuenta = raw['cuenta'];
    final clave = raw['claveSellada'];
    final falloCrudo = raw['ultimoFallo'];
    if (habilitado is! bool || cuenta is! String || clave is! String) {
      return null;
    }
    String? ultimoRespaldo;
    final respaldoCrudo = raw['ultimoRespaldo'];
    if (respaldoCrudo != null) {
      if (respaldoCrudo is! String) return null;
      ultimoRespaldo = respaldoCrudo;
    }
    DriveApiFailure? fallo;
    if (falloCrudo != null) {
      if (falloCrudo is! String) return null;
      fallo = DriveApiFailure.values.asNameMap()[falloCrudo];
      if (fallo == null) return null;
    }
    return DriveBackupSettings(
      habilitado: habilitado,
      cuenta: cuenta,
      claveSellada: clave,
      ultimoRespaldo: ultimoRespaldo,
      ultimoFallo: fallo,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DriveBackupSettings &&
      other.habilitado == habilitado &&
      other.cuenta == cuenta &&
      other.claveSellada == claveSellada &&
      other.ultimoRespaldo == ultimoRespaldo &&
      other.ultimoFallo == ultimoFallo;

  @override
  int get hashCode =>
      Object.hash(habilitado, cuenta, claveSellada, ultimoRespaldo, ultimoFallo);

  @override
  String toString() => 'DriveBackupSettings(habilitado: $habilitado, '
      'cuenta: $cuenta, ultimoRespaldo: $ultimoRespaldo, '
      'ultimoFallo: $ultimoFallo, claveSellada: [blob])';
}

/// Guarda [DriveBackupSettings] en un JSON pequeno en el almacenamiento
/// privado, con el mismo esquema que DeviceSettingsStore: operaciones en
/// fila y escritura atomica (temporal + rename).
class DriveBackupSettingsStore {
  DriveBackupSettingsStore(
      {required Future<Directory> Function() supportDirectory})
      : _supportDirectory = supportDirectory;

  static const String fileName = 'respaldo_drive.json';
  static const int formatVersion = 1;

  final Future<Directory> Function() _supportDirectory;

  final StreamController<DriveBackupSettings> _changes =
      StreamController<DriveBackupSettings>.broadcast();
  Future<void> _fila = Future.value();

  Future<File> _file() async =>
      File(p.join((await _supportDirectory()).path, fileName));

  /// El estado actual y despues cada cambio.
  Stream<DriveBackupSettings> watch() => Stream.multi((controller) {
        final sub = _changes.stream.listen(controller.add);
        read().then(controller.add, onError: controller.addError);
        controller.onCancel = sub.cancel;
      });

  Future<DriveBackupSettings> read() => _enFila(() => _leer());

  Future<DriveBackupSettings> guardar(DriveBackupSettings nuevo) =>
      _enFila(() async {
        await _escribir(nuevo);
        _changes.add(nuevo);
        return nuevo;
      });

  /// "Borrar todos los datos".
  Future<void> delete() => _enFila(() async {
        final file = await _file();
        for (final f in [file, File('${file.path}.tmp')]) {
          if (await f.exists()) await f.delete();
        }
        _changes.add(const DriveBackupSettings());
      });

  Future<T> _enFila<T>(Future<T> Function() op) {
    final result = _fila.then((_) => op());
    _fila = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<DriveBackupSettings> _leer({bool paraEscribir = false}) async {
    final file = await _file();
    try {
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final state = DriveBackupSettings.fromJson(jsonDecode(utf8.decode(bytes)));
        if (state != null) return state;
      }
    } on FileSystemException {
      if (paraEscribir) rethrow;
    } on FormatException {
      // Archivo danado: valores por defecto.
    }
    return const DriveBackupSettings();
  }

  Future<void> _escribir(DriveBackupSettings state) async {
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

DriveBackupSettingsStore? _driveBackupSettingsStoreInstance;

/// Instancia unica para la app.
DriveBackupSettingsStore get driveBackupSettingsStore =>
    _driveBackupSettingsStoreInstance ??=
        DriveBackupSettingsStore(supportDirectory: getApplicationSupportDirectory);

/// Solo para tests.
set driveBackupSettingsStore(DriveBackupSettingsStore value) =>
    _driveBackupSettingsStoreInstance = value;
