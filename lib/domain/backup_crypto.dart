import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// Cifrado del respaldo (HU-06b, decisiones HU6b-1 a HU6b-12 de la
/// especificacion). Dart puro, sin Flutter: `cryptography` 2.9.0 en sus
/// implementaciones Dart (DartArgon2id, DartAesGcm); no se usa
/// cryptography_flutter ni FlutterCryptography.enable() (HU6b-5).
///
/// El archivo cifrado (`formatVersion` 2) es un JSON con:
///   format, formatVersion, app, encryption {cipher, kdf, kdfParams
///   {memoryKiB, iterations, parallelism}, salt, nonce}, ciphertext.
/// `ciphertext` es base64 de (texto cifrado || etiqueta GCM de 16 bytes).
/// Lo que se cifra es el documento de `formatVersion` 1 completo, byte a
/// byte (el mismo que escribe encodeBackup), asi que al descifrar se valida
/// con el mismo decodeBackup.
///
/// Contrasena (HU6b-11, decidido): NO se normaliza el texto Unicode. Se
/// codifica en UTF-8 tal como llega. Una misma contrasena escrita con otra
/// composicion de caracteres (por ejemplo, "n" + tilde combinable en vez
/// de "ñ") no abriria el archivo; con los teclados de Android el riesgo se
/// considera bajo.

const String encryptedBackupCipher = 'AES-256-GCM';
const String encryptedBackupKdf = 'Argon2id';
const int encryptedBackupSaltLength = 16;
const int encryptedBackupNonceLength = 12;
const int encryptedBackupTagLength = 16;
const int encryptedBackupKeyLength = 32;

/// Mensaje unico de HU6b-8: GCM no distingue una contrasena equivocada de
/// un archivo alterado.
const String wrongPasswordOrDamagedMessage =
    'La contraseña no es correcta o el archivo está dañado. No se cambió nada.';

/// Parametros de Argon2id. Version 0x13 (la unica que implementa
/// DartArgon2id, la del RFC 9106) y salida de [encryptedBackupKeyLength]
/// bytes; los dos son fijos y no van en el archivo.
class Argon2idParams {
  const Argon2idParams({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  /// Produccion (HU6b-2): m = 19 456 KiB, t = 2, p = 1. Medido en CP0:
  /// ~214 ms en un POCO X6 Pro (profile), Dart puro en un isolate.
  static const production = Argon2idParams(
    memoryKiB: 19456,
    iterations: 2,
    parallelism: 1,
  );

  /// Limites que se aceptan al importar. Se comprueban ANTES de derivar la
  /// clave, para que un archivo manipulado no pida recursos enormes:
  /// - memoria de 8 192 KiB (8 MiB, por debajo del minimo de OWASP de 12
  ///   MiB, margen para no rechazar un ajuste hacia abajo) a 65 536 KiB (64
  ///   MiB, ~3,4 veces produccion; una gama media lo aguanta);
  /// - iteraciones de 1 a 10 (10 con 19 MiB seria ~1 s en el telefono de
  ///   medicion);
  /// - paralelismo exactamente 1: DartArgon2id con mas carriles necesita
  ///   mas isolates, y produccion usa 1.
  static const int minMemoryKiB = 8192;
  static const int maxMemoryKiB = 65536;
  static const int minIterations = 1;
  static const int maxIterations = 10;
  static const int minParallelism = 1;
  static const int maxParallelism = 1;

  final int memoryKiB;
  final int iterations;
  final int parallelism;

  /// Algun valor por encima del maximo: puede venir de una version mas
  /// nueva que subio los parametros.
  bool get isAboveLimits =>
      memoryKiB > maxMemoryKiB ||
      iterations > maxIterations ||
      parallelism > maxParallelism;

  bool get isWithinLimits =>
      memoryKiB >= minMemoryKiB &&
      memoryKiB <= maxMemoryKiB &&
      iterations >= minIterations &&
      iterations <= maxIterations &&
      parallelism >= minParallelism &&
      parallelism <= maxParallelism;

  @override
  bool operator ==(Object other) =>
      other is Argon2idParams &&
      other.memoryKiB == memoryKiB &&
      other.iterations == iterations &&
      other.parallelism == parallelism;

  @override
  int get hashCode => Object.hash(memoryKiB, iterations, parallelism);

  @override
  String toString() =>
      'Argon2idParams(m: $memoryKiB KiB, t: $iterations, p: $parallelism)';
}

/// Deriva la clave de [encryptedBackupKeyLength] bytes a partir de los
/// bytes UTF-8 de la contrasena. Inyectable en tests (por ejemplo, para
/// comprobar que un archivo fuera de rango se rechaza sin derivar).
typedef BackupKeyDeriver =
    Future<Uint8List> Function(
      List<int> passwordUtf8,
      List<int> salt,
      Argon2idParams params,
    );

/// Argon2id en Dart puro (DartArgon2id de `cryptography` 2.9.0).
Future<Uint8List> deriveBackupKey(
  List<int> passwordUtf8,
  List<int> salt,
  Argon2idParams params,
) async {
  final kdf = DartArgon2id(
    parallelism: params.parallelism,
    memory: params.memoryKiB,
    iterations: params.iterations,
    hashLength: encryptedBackupKeyLength,
  );
  final derived = await kdf.deriveKey(
    secretKey: SecretKeyData(passwordUtf8),
    nonce: salt,
  );
  final bytes = await derived.extractBytes();
  final copy = Uint8List.fromList(bytes);
  // Mejor esfuerzo: la lista que devuelve extractBytes es la interna.
  _zero(bytes);
  return copy;
}

/// Por que no se pudo cifrar o descifrar.
enum BackupCryptoError {
  /// Contrasena incorrecta o archivo alterado (HU6b-8: no se distinguen).
  wrongPasswordOrDamaged,

  /// El encabezado o el `ciphertext` no tienen la forma esperada (claves,
  /// tipos, base64, largos).
  invalidFormat,

  /// `cipher` o `kdf` desconocidos: pueden venir de una version mas nueva.
  unsupportedAlgorithm,

  /// Parametros de Argon2id fuera de los limites de [Argon2idParams].
  paramsOutOfRange,
}

class BackupCryptoException implements Exception {
  BackupCryptoException(this.error, this.detail, {this.params});

  final BackupCryptoError error;

  /// Con [BackupCryptoError.paramsOutOfRange]: los parametros leidos.
  final Argon2idParams? params;

  /// Solo para tests y depuracion; nunca se muestra.
  final String detail;

  @override
  String toString() => 'BackupCryptoException($error: $detail)';
}

/// Encabezado ya validado de un respaldo cifrado (todo menos `ciphertext`).
class EncryptedBackupHeader {
  const EncryptedBackupHeader({
    required this.app,
    required this.params,
    required this.salt,
    required this.nonce,
  });

  final String app;
  final Argon2idParams params;
  final Uint8List salt;
  final Uint8List nonce;

  /// Bytes del dato adicional autenticado de GCM: JSON en UTF-8, sin
  /// espacios, con las claves en orden alfabetico en todos los niveles, de
  /// exactamente estos campos:
  ///
  ///     {"app":<app>,
  ///      "encryption":{"cipher":"AES-256-GCM","kdf":"Argon2id",
  ///        "kdfParams":{"iterations":<t>,"memoryKiB":<m>,"parallelism":<p>},
  ///        "nonce":<base64>,"salt":<base64>},
  ///      "format":"aura-backup","formatVersion":2}
  ///
  /// (en una sola linea; los saltos de arriba son solo para leerlo). Los
  /// numeros van como enteros decimales y las cadenas con el escape de
  /// jsonEncode. Se arma desde los valores ya validados, no desde el texto
  /// del archivo: cambiar espacios o el orden de las claves en el archivo
  /// no cambia el AAD; cambiar cualquier valor si.
  Uint8List canonicalAad() => Uint8List.fromList(
    utf8.encode(jsonEncode(_sortedKeys(_headerMap(this)))),
  );
}

/// Respaldo cifrado ya separado en encabezado y [ciphertext] (texto
/// cifrado || etiqueta), sin descifrar.
class EncryptedBackupEnvelope {
  const EncryptedBackupEnvelope(this.header, this.ciphertext);

  final EncryptedBackupHeader header;
  final Uint8List ciphertext;
}

Map<String, Object?> _headerMap(EncryptedBackupHeader h) => {
  'format': 'aura-backup',
  'formatVersion': 2,
  'app': h.app,
  'encryption': {
    'cipher': encryptedBackupCipher,
    'kdf': encryptedBackupKdf,
    'kdfParams': {
      'memoryKiB': h.params.memoryKiB,
      'iterations': h.params.iterations,
      'parallelism': h.params.parallelism,
    },
    'salt': base64.encode(h.salt),
    'nonce': base64.encode(h.nonce),
  },
};

/// Copia de [value] con las claves de todos los mapas en orden alfabetico
/// (por unidades de codigo UTF-16, String.compareTo).
Object? _sortedKeys(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return {for (final k in keys) k: _sortedKeys(value[k])};
  }
  return value;
}

/// Cifra [documentV1Json] (el texto que devuelve encodeBackup) con
/// [password] y devuelve el JSON de `formatVersion` 2. Sal y nonce nuevos
/// en cada llamada, de [random] (Random.secure() por defecto): dos
/// cifrados de los mismos datos no son iguales.
Future<String> encryptBackup(
  String documentV1Json,
  String password, {
  Argon2idParams params = Argon2idParams.production,
  Random? random,
  BackupKeyDeriver deriveKey = deriveBackupKey,
}) async {
  if (!params.isWithinLimits) {
    throw BackupCryptoException(
      BackupCryptoError.paramsOutOfRange,
      'al cifrar: $params',
    );
  }
  final rng = random ?? Random.secure();
  Uint8List randomBytes(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => rng.nextInt(256)));
  final header = EncryptedBackupHeader(
    app: 'Aura',
    params: params,
    salt: randomBytes(encryptedBackupSaltLength),
    nonce: randomBytes(encryptedBackupNonceLength),
  );
  final key = await deriveKey(utf8.encode(password), header.salt, params);
  try {
    final box = await DartAesGcm.with256bits().encrypt(
      utf8.encode(documentV1Json),
      secretKey: SecretKeyData(key),
      nonce: header.nonce,
      aad: header.canonicalAad(),
    );
    final root = <String, Object?>{
      ..._headerMap(header),
      'ciphertext': base64.encode([...box.cipherText, ...box.mac.bytes]),
    };
    return '${const JsonEncoder.withIndent('  ').convert(root)}\n';
  } finally {
    _zero(key);
  }
}

/// Lee y valida el encabezado y el `ciphertext` de un respaldo cifrado
/// ya parseado como JSON. Sincrona y sin derivar nada: un archivo mal
/// formado, con algoritmos desconocidos o con parametros fuera de rango
/// se rechaza aqui.
EncryptedBackupEnvelope parseEncryptedBackup(Map<String, dynamic> root) {
  _exactKeys(root, const {
    'format',
    'formatVersion',
    'app',
    'encryption',
    'ciphertext',
  }, 'raiz');
  if (root['format'] != 'aura-backup' || root['formatVersion'] != 2) {
    throw BackupCryptoException(
      BackupCryptoError.invalidFormat,
      'format o formatVersion',
    );
  }
  final app = root['app'];
  if (app is! String) {
    throw BackupCryptoException(BackupCryptoError.invalidFormat, 'app');
  }
  final enc = root['encryption'];
  if (enc is! Map<String, dynamic>) {
    throw BackupCryptoException(
      BackupCryptoError.invalidFormat,
      'encryption no es un objeto',
    );
  }
  _exactKeys(enc, const {
    'cipher',
    'kdf',
    'kdfParams',
    'salt',
    'nonce',
  }, 'encryption');
  final cipher = enc['cipher'];
  final kdf = enc['kdf'];
  if (cipher is! String || kdf is! String) {
    throw BackupCryptoException(
      BackupCryptoError.invalidFormat,
      'cipher o kdf',
    );
  }
  if (cipher != encryptedBackupCipher || kdf != encryptedBackupKdf) {
    throw BackupCryptoException(
      BackupCryptoError.unsupportedAlgorithm,
      '$cipher / $kdf',
    );
  }
  final kp = enc['kdfParams'];
  if (kp is! Map<String, dynamic>) {
    throw BackupCryptoException(
      BackupCryptoError.invalidFormat,
      'kdfParams no es un objeto',
    );
  }
  _exactKeys(kp, const {'memoryKiB', 'iterations', 'parallelism'}, 'kdfParams');
  final m = kp['memoryKiB'], t = kp['iterations'], p = kp['parallelism'];
  if (m is! int || t is! int || p is! int) {
    throw BackupCryptoException(
      BackupCryptoError.invalidFormat,
      'kdfParams no son enteros',
    );
  }
  final params = Argon2idParams(memoryKiB: m, iterations: t, parallelism: p);
  if (!params.isWithinLimits) {
    throw BackupCryptoException(
      BackupCryptoError.paramsOutOfRange,
      '$params',
      params: params,
    );
  }
  final salt = _base64Field(enc, 'salt');
  final nonce = _base64Field(enc, 'nonce');
  final ciphertext = _base64Field(root, 'ciphertext');
  if (salt.length != encryptedBackupSaltLength ||
      nonce.length != encryptedBackupNonceLength ||
      ciphertext.length < encryptedBackupTagLength) {
    throw BackupCryptoException(
      BackupCryptoError.invalidFormat,
      'largos: sal ${salt.length}, nonce ${nonce.length}, '
      'ciphertext ${ciphertext.length}',
    );
  }
  return EncryptedBackupEnvelope(
    EncryptedBackupHeader(app: app, params: params, salt: salt, nonce: nonce),
    ciphertext,
  );
}

/// Deriva la clave con los parametros del encabezado, descifra y devuelve
/// los bytes del documento de `formatVersion` 1 tal como se cifraron.
/// Lanza [BackupCryptoException] con
/// [BackupCryptoError.wrongPasswordOrDamaged] si la etiqueta no coincide
/// (contrasena incorrecta o archivo alterado).
Future<Uint8List> decryptBackupEnvelope(
  EncryptedBackupEnvelope envelope,
  String password, {
  BackupKeyDeriver deriveKey = deriveBackupKey,
}) async {
  final h = envelope.header;
  // Ya validado en parseEncryptedBackup; se repite por si el sobre se
  // armo a mano.
  if (!h.params.isWithinLimits) {
    throw BackupCryptoException(
      BackupCryptoError.paramsOutOfRange,
      '${h.params}',
    );
  }
  final key = await deriveKey(utf8.encode(password), h.salt, h.params);
  try {
    final split = envelope.ciphertext.length - encryptedBackupTagLength;
    final clear = await DartAesGcm.with256bits().decrypt(
      SecretBox(
        envelope.ciphertext.sublist(0, split),
        nonce: h.nonce,
        mac: Mac(envelope.ciphertext.sublist(split)),
      ),
      secretKey: SecretKeyData(key),
      aad: h.canonicalAad(),
    );
    return Uint8List.fromList(clear);
  } on SecretBoxAuthenticationError {
    throw BackupCryptoException(
      BackupCryptoError.wrongPasswordOrDamaged,
      'etiqueta GCM',
    );
  } finally {
    _zero(key);
  }
}

/// Lee el archivo cifrado completo, valida el encabezado, vuelve a derivar
/// la clave, descifra y devuelve el documento de `formatVersion` 1
/// original. Es la funcion publica que usa la importacion y la verificacion
/// de HU6b-10.
Future<Uint8List> decryptBackup(
  List<int> fileBytes,
  String password, {
  BackupKeyDeriver deriveKey = deriveBackupKey,
}) async {
  final Object? root;
  try {
    root = jsonDecode(utf8.decode(fileBytes));
  } on FormatException catch (e) {
    throw BackupCryptoException(BackupCryptoError.invalidFormat, 'JSON: $e');
  }
  if (root is! Map<String, dynamic>) {
    throw BackupCryptoException(
      BackupCryptoError.invalidFormat,
      'no es un objeto',
    );
  }
  return decryptBackupEnvelope(
    parseEncryptedBackup(root),
    password,
    deriveKey: deriveKey,
  );
}

void _exactKeys(Map<String, dynamic> map, Set<String> keys, String where) {
  final actual = map.keys.toSet();
  if (actual.length != keys.length || !actual.containsAll(keys)) {
    throw BackupCryptoException(
      BackupCryptoError.invalidFormat,
      '$where: claves ${actual.toList()..sort()}',
    );
  }
}

/// Base64 estandar con relleno, en su forma canonica (volver a codificar
/// da el mismo texto). Rechaza caracteres invalidos, falta de relleno y
/// bits sobrantes.
Uint8List _base64Field(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! String) {
    throw BackupCryptoException(
      BackupCryptoError.invalidFormat,
      '$key no es texto',
    );
  }
  final Uint8List bytes;
  try {
    bytes = base64.decode(value);
  } on FormatException {
    throw BackupCryptoException(
      BackupCryptoError.invalidFormat,
      '$key no es base64',
    );
  }
  if (base64.encode(bytes) != value) {
    throw BackupCryptoException(
      BackupCryptoError.invalidFormat,
      '$key no es base64 canonico',
    );
  }
  return bytes;
}

void _zero(List<int> bytes) {
  try {
    bytes.fillRange(0, bytes.length, 0);
  } on UnsupportedError {
    // Lista inmutable: no se puede borrar (mejor esfuerzo).
  }
}
