import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/domain/backup_codec.dart';
import 'package:aura/domain/backup_crypto.dart';

/// HU-06b CP1: cifrado del respaldo (backup_crypto.dart) y su paso por
/// decodeBackup. Datos inventados. Casi todos los tests usan parametros
/// reducidos dentro de los limites (8 MiB, t = 1) para que la suite sea
/// rapida; los de produccion solo en el vector de HU6b-12 y en una ida y
/// vuelta.

const _small = Argon2idParams(memoryKiB: 8192, iterations: 1, parallelism: 1);
const _password = 'contraseña de prueba';

/// Contrasena de test/fixtures/backup_v5_cifrado.json (datos inventados:
/// el contenido de backup_v5.json cifrado con [_small]).
const _fixturePassword = 'Fixture CP1: ñandú 🌸 árbol';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

List<int> _unhex(String h) => [
  for (var i = 0; i < h.length; i += 2)
    int.parse(h.substring(i, i + 2), radix: 16),
];

String _fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync().replaceAll('\r\n', '\n');

/// El documento v5 en la forma exacta que escribe encodeBackup (LF).
String _v5Document() {
  final data =
      (decodeBackup(utf8.encode(_fixture('backup_v5.json')))
              as BackupParseSuccess)
          .data;
  return encodeBackup(data);
}

BackupData _data(String document) =>
    (decodeBackup(utf8.encode(document)) as BackupParseSuccess).data;

void _expectSameData(BackupData actual, BackupData expected) {
  expect(actual.schemaVersion, expected.schemaVersion);
  expect(actual.appVersion, expected.appVersion);
  expect(actual.exportedAt, expected.exportedAt);
  expect(actual.days, expected.days);
  expect(actual.settings, expected.settings);
}

Future<String> _encrypt(
  String doc, {
  String password = _password,
  Argon2idParams params = _small,
  int seed = 7,
}) => encryptBackup(doc, password, params: params, random: Random(seed));

Map<String, dynamic> _map(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

Map<String, dynamic> _enc(Map<String, dynamic> root) =>
    root['encryption'] as Map<String, dynamic>;

Map<String, dynamic> _params(Map<String, dynamic> root) =>
    _enc(root)['kdfParams'] as Map<String, dynamic>;

/// Invierte un bit del campo base64 [key] de [map] (byte [index]; negativo
/// cuenta desde el final) y lo vuelve a codificar en base64 canonico.
void _flipBit(Map<String, dynamic> map, String key, int index) {
  final bytes = base64.decode(map[key] as String);
  final i = index < 0 ? bytes.length + index : index;
  bytes[i] ^= 0x01;
  map[key] = base64.encode(bytes);
}

/// Deriva con [_small] pero cuenta las llamadas.
class _CountingDeriver {
  int calls = 0;

  Future<Uint8List> call(
    List<int> password,
    List<int> salt,
    Argon2idParams params,
  ) {
    calls++;
    return deriveBackupKey(password, salt, params);
  }
}

Future<Uint8List> _mustNotDerive(
  List<int> password,
  List<int> salt,
  Argon2idParams params,
) => throw StateError('no debia derivar la clave');

Future<void> _expectWrongPassword(Future<Object?> future) => expectLater(
  future,
  throwsA(
    isA<BackupCryptoException>().having(
      (e) => e.error,
      'error',
      BackupCryptoError.wrongPasswordOrDamaged,
    ),
  ),
);

/// Ningun archivo manipulado importa nada: o decodeBackup ya lo rechaza, o
/// pide contrasena y el descifrado falla.
Future<void> _expectNotImported(
  Map<String, dynamic> root, {
  String password = _password,
}) async {
  final result = decodeBackup(utf8.encode(jsonEncode(root)));
  expect(result, isNot(isA<BackupParseSuccess>()));
  if (result is BackupNeedsPassword) {
    await _expectWrongPassword(decodeEncryptedBackup(result, password));
  }
}

void main() {
  group('a) y b) Argon2id: vectores conocidos', () {
    test(
      'a) HU6b-12: parametros de produccion (vector de libargon2)',
      () async {
        // Contrasena "contraseña-de-prueba-CP0" (UTF-8), m = 19 456 KiB,
        // t = 2, p = 1, 32 bytes, v19. Calculado con libargon2 (argon2-cffi)
        // el 2026-10-08 (ver HU6b-12 en la especificacion).
        final key = await deriveBackupKey(
          utf8.encode('contraseña-de-prueba-CP0'),
          _unhex('0b30557a9fc4e90e33587da2c7ec1136'),
          Argon2idParams.production,
        );
        expect(
          _hex(key),
          'c60b1eee88c5827b9cdb6ce18e8668fcc112ebb52214c9c1bb239a440a66314a',
        );
      },
    );

    test('b) RFC 9106, seccion 5.3 (Argon2id, parametros pequenos)', () async {
      // Fuera de los limites de un respaldo (p = 4, m = 32 KiB): se prueba
      // la misma implementacion (DartArgon2id) que usa deriveBackupKey.
      const kdf = DartArgon2id(
        parallelism: 4,
        memory: 32,
        iterations: 3,
        hashLength: 32,
      );
      final key = await kdf.deriveKey(
        secretKey: SecretKey(List.filled(32, 0x01)),
        nonce: List.filled(16, 0x02),
        optionalSecret: List.filled(8, 0x03),
        associatedData: List.filled(12, 0x04),
      );
      expect(
        _hex(await key.extractBytes()),
        '0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659',
      );
    });
  });

  // McGrew y Viega, "The Galois/Counter Mode of Operation (GCM)",
  // apendice B, Test Cases 13 a 16 (AES-256, IV de 96 bits), paginas 37 a
  // 39 de la version enviada al NIST.
  group('c) AES-256-GCM: vectores de McGrew y Viega', () {
    const k15 =
        'feffe9928665731c6d6a8f9467308308'
        'feffe9928665731c6d6a8f9467308308';
    const p15 =
        'd9313225f88406e5a55909c5aff5269a'
        '86a7a9531534f7da2e4c303d8a318a72'
        '1c3c0c95956809532fcf0e2449a6b525'
        'b16aedf5aa0de657ba637b391aafd255';
    const c15 =
        '522dc1f099567d07f47f37a32a84427d'
        '643a8cdcbfe5c0c97598a2bd2555d1aa'
        '8cb08e48590dbb3da7b08b1056828838'
        'c5f61e6393ba7a0abcc9f662898015ad';
    final cases = [
      (
        name: 'Test Case 13 (P vacio, sin A)',
        k: '0' * 64,
        p: '',
        a: '',
        iv: '0' * 24,
        c: '',
        t: '530f8afbc74536b9a963b4f1c4cb738b',
      ),
      (
        name: 'Test Case 14 (16 bytes, sin A)',
        k: '0' * 64,
        p: '0' * 32,
        a: '',
        iv: '0' * 24,
        c: 'cea7403d4d606b6e074ec5d3baf39d18',
        t: 'd0d1c8a799996bf0265b98b5d48ab919',
      ),
      (
        name: 'Test Case 15 (64 bytes, sin A)',
        k: k15,
        p: p15,
        a: '',
        iv: 'cafebabefacedbaddecaf888',
        c: c15,
        t: 'b094dac5d93471bdec1a502270e3cc6c',
      ),
      (
        name: 'Test Case 16 (60 bytes, con A)',
        k: k15,
        p: p15.substring(0, 120),
        a: 'feedfacedeadbeeffeedfacedeadbeefabaddad2',
        iv: 'cafebabefacedbaddecaf888',
        c: c15.substring(0, 120),
        t: '76fc6ece0f4e1768cddf8853bb2d551b',
      ),
    ];
    for (final tc in cases) {
      test(tc.name, () async {
        final aes = DartAesGcm.with256bits();
        final key = SecretKey(_unhex(tc.k));
        final box = await aes.encrypt(
          _unhex(tc.p),
          secretKey: key,
          nonce: _unhex(tc.iv),
          aad: _unhex(tc.a),
        );
        expect(_hex(box.cipherText), tc.c);
        expect(_hex(box.mac.bytes), tc.t);
        final clear = await aes.decrypt(box, secretKey: key, aad: _unhex(tc.a));
        expect(_hex(clear), tc.p);
      });
    }
  });

  group('encabezado canonico (AAD)', () {
    test('bytes exactos: claves en orden alfabetico, sin espacios, UTF-8', () {
      final header = EncryptedBackupHeader(
        app: 'Aura',
        params: Argon2idParams.production,
        salt: Uint8List.fromList(List.generate(16, (i) => i)),
        nonce: Uint8List.fromList(List.generate(12, (i) => 255 - i)),
      );
      expect(
        utf8.decode(header.canonicalAad()),
        '{"app":"Aura","encryption":{"cipher":"AES-256-GCM",'
        '"kdf":"Argon2id","kdfParams":{"iterations":2,"memoryKiB":19456,'
        '"parallelism":1},"nonce":"//79/Pv6+fj39vX0","salt":'
        '"AAECAwQFBgcICQoLDA0ODw=="},"format":"aura-backup",'
        '"formatVersion":2}',
      );
    });

    test(
      'el archivo lleva los campos de la especificacion, en orden',
      () async {
        final root = _map(await _encrypt(_v5Document()));
        expect(root.keys.toList(), [
          'format',
          'formatVersion',
          'app',
          'encryption',
          'ciphertext',
        ]);
        expect(root['format'], 'aura-backup');
        expect(root['formatVersion'], 2);
        expect(root['app'], 'Aura');
        expect(_enc(root).keys.toList(), [
          'cipher',
          'kdf',
          'kdfParams',
          'salt',
          'nonce',
        ]);
        expect(_enc(root)['cipher'], 'AES-256-GCM');
        expect(_enc(root)['kdf'], 'Argon2id');
        expect(_params(root), {
          'memoryKiB': 8192,
          'iterations': 1,
          'parallelism': 1,
        });
        expect(base64.decode(_enc(root)['salt'] as String), hasLength(16));
        expect(base64.decode(_enc(root)['nonce'] as String), hasLength(12));
      },
    );

    test('espacios y orden de claves del archivo no cambian el AAD', () async {
      final root = _map(await _encrypt(_v5Document()));
      // Mismo contenido, compacto y con encryption delante.
      final reordered = {
        'encryption': root['encryption'],
        'ciphertext': root['ciphertext'],
        'app': root['app'],
        'formatVersion': root['formatVersion'],
        'format': root['format'],
      };
      final clear = await decryptBackup(
        utf8.encode(jsonEncode(reordered)),
        _password,
      );
      expect(utf8.decode(clear), _v5Document());
    });
  });

  group('d) ida y vuelta', () {
    final doc = _v5Document();
    for (final pw in [
      'ñandú',
      'canción con tildes: áéíóú ÁÉÍÓÚ ü',
      'emoji 🌸🌙✨ y 👩🏽‍💻',
      '  espacios   al borde y en medio  ',
      'a',
    ]) {
      test(
        'contrasena "$pw": mismo documento byte a byte y mismo BackupData',
        () async {
          final file = await _encrypt(doc, password: pw);
          final clear = await decryptBackup(utf8.encode(file), pw);
          expect(clear, utf8.encode(doc));

          final pending = decodeBackup(utf8.encode(file));
          expect(pending, isA<BackupNeedsPassword>());
          final result = await decodeEncryptedBackup(
            pending as BackupNeedsPassword,
            pw,
          );
          _expectSameData((result as BackupParseSuccess).data, _data(doc));
        },
      );
    }

    test('con los parametros de produccion', () async {
      final file = await encryptBackup(doc, _password);
      expect(_params(_map(file)), {
        'memoryKiB': 19456,
        'iterations': 2,
        'parallelism': 1,
      });
      final clear = await decryptBackup(utf8.encode(file), _password);
      expect(clear, utf8.encode(doc));
    });

    test('HU6b-11: no se normaliza: "ñ" compuesta no abre con "n" + tilde '
        'combinable', () async {
      const compuesta = 'pi\u00f1a';
      const descompuesta = 'pin\u0303a';
      final file = await _encrypt(doc, password: compuesta);
      await _expectWrongPassword(
        decryptBackup(utf8.encode(file), descompuesta),
      );
      expect(
        await decryptBackup(utf8.encode(file), compuesta),
        utf8.encode(doc),
      );
    });
  });

  group('e) manipulacion: nada se importa', () {
    late Map<String, dynamic> base;
    setUpAll(() async {
      base = _map(await _encrypt(_v5Document()));
    });
    Map<String, dynamic> copy() => _map(jsonEncode(base)); // copia profunda

    test('sin tocar, si descifra (control)', () async {
      final result = decodeBackup(utf8.encode(jsonEncode(copy())));
      final ok = await decodeEncryptedBackup(
        result as BackupNeedsPassword,
        _password,
      );
      expect(ok, isA<BackupParseSuccess>());
    });

    test('1 bit del texto cifrado', () async {
      final m = copy();
      _flipBit(m, 'ciphertext', 0);
      await _expectNotImported(m);
    });

    test('1 bit de la etiqueta', () async {
      final m = copy();
      _flipBit(m, 'ciphertext', -1);
      await _expectNotImported(m);
    });

    test('1 bit del nonce', () async {
      final m = copy();
      _flipBit(_enc(m), 'nonce', 0);
      await _expectNotImported(m);
    });

    test('1 bit de la sal', () async {
      final m = copy();
      _flipBit(_enc(m), 'salt', 0);
      await _expectNotImported(m);
    });

    test('iterations (dentro de los limites)', () async {
      final m = copy();
      _params(m)['iterations'] = 2;
      await _expectNotImported(m);
    });

    test('memoryKiB (dentro de los limites)', () async {
      final m = copy();
      _params(m)['memoryKiB'] = 8193;
      await _expectNotImported(m);
    });

    test('algoritmo de cifrado o de derivacion', () async {
      final m1 = copy();
      _enc(m1)['cipher'] = 'AES-128-GCM';
      await _expectNotImported(m1);
      final m2 = copy();
      _enc(m2)['kdf'] = 'Argon2i';
      await _expectNotImported(m2);
    });

    test('app (solo lo cubre el AAD)', () async {
      final m = copy();
      m['app'] = 'Aurb';
      final pending = decodeBackup(utf8.encode(jsonEncode(m)));
      expect(pending, isA<BackupNeedsPassword>());
      await _expectNotImported(m);
    });

    test('formatVersion', () async {
      for (final v in [1, 3]) {
        final m = copy()..['formatVersion'] = v;
        await _expectNotImported(m);
      }
    });
  });

  group('f) contrasena incorrecta, truncado, base64 y limites', () {
    late String file;
    setUpAll(() async {
      file = await _encrypt(_v5Document());
    });

    test(
      'contrasena incorrecta: un solo error, con el mensaje de HU6b-8',
      () async {
        await _expectWrongPassword(
          decryptBackup(utf8.encode(file), 'otra contraseña'),
        );
        expect(
          wrongPasswordOrDamagedMessage,
          'La contraseña no es correcta o el archivo está dañado. '
          'No se cambió nada.',
        );
      },
    );

    test('archivo truncado en varios puntos: nada se importa', () async {
      final bytes = utf8.encode(file);
      for (final cut in [
        0,
        10,
        bytes.length ~/ 3,
        bytes.length ~/ 2,
        bytes.length - 40,
        bytes.length - 2,
      ]) {
        final result = decodeBackup(bytes.sublist(0, cut));
        expect(result, isA<BackupParseFailure>(), reason: 'corte $cut');
        expect(result, isNot(isA<BackupNeedsPassword>()), reason: 'corte $cut');
      }
    });

    test('ciphertext acortado (JSON valido): falla la etiqueta', () async {
      final m = _map(file);
      final c = base64.decode(m['ciphertext'] as String);
      m['ciphertext'] = base64.encode(c.sublist(0, c.length - 4));
      await _expectNotImported(m);
    });

    test('ciphertext de menos de 16 bytes: danado, sin pedir contrasena', () {
      final m = _map(file)..['ciphertext'] = base64.encode(List.filled(15, 1));
      final result = decodeBackup(utf8.encode(jsonEncode(m)));
      expect((result as BackupParseFailure).error, BackupError.damaged);
      expect(result, isNot(isA<BackupNeedsPassword>()));
    });

    test('base64 invalido o no canonico: danado', () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (m) => _enc(m)['salt'] = 'no es base64!',
        (m) => _enc(m)['nonce'] = '${_enc(m)['nonce']}=',
        (m) =>
            _enc(m)['salt'] = (_enc(m)['salt'] as String).replaceAll('=', ''),
        (m) => m['ciphertext'] = '%%%%',
        (m) => _enc(m)['salt'] = base64.encode(List.filled(15, 1)),
        (m) => _enc(m)['nonce'] = base64.encode(List.filled(16, 1)),
      ]) {
        final m = _map(file);
        mutate(m);
        final result = decodeBackup(utf8.encode(jsonEncode(m)));
        expect(result, isA<BackupParseFailure>());
        expect(result, isNot(isA<BackupNeedsPassword>()));
        expect((result as BackupParseFailure).error, BackupError.damaged);
      }
    });

    test('encabezado mal formado: claves de mas o de menos, tipos', () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (m) => _enc(m)['extra'] = 1,
        (m) => _enc(m).remove('nonce'),
        (m) => _params(m)['memoryKiB'] = '8192',
        (m) => m['encryption'] = null,
        (m) => m['encryption'] = 'AES',
        (m) => m['app'] = 1,
        (m) => m.remove('ciphertext'),
        (m) => m['schemaVersion'] = 5,
      ]) {
        final m = _map(file);
        mutate(m);
        final result = decodeBackup(utf8.encode(jsonEncode(m)));
        expect(result, isNot(isA<BackupNeedsPassword>()));
        expect((result as BackupParseFailure).error, BackupError.damaged);
      }
    });

    test(
      'parametros fuera de rango: se rechazan SIN derivar la clave',
      () async {
        final cases = <(String, int, BackupError)>[
          ('memoryKiB', 8191, BackupError.damaged),
          ('memoryKiB', 65537, BackupError.newerVersion),
          ('iterations', 0, BackupError.damaged),
          ('iterations', 11, BackupError.newerVersion),
          ('parallelism', 0, BackupError.damaged),
          ('parallelism', 2, BackupError.newerVersion),
        ];
        for (final (key, value, error) in cases) {
          final m = _map(file);
          _params(m)[key] = value;
          final bytes = utf8.encode(jsonEncode(m));
          final result = decodeBackup(bytes);
          expect(result, isNot(isA<BackupNeedsPassword>()), reason: key);
          expect(
            (result as BackupParseFailure).error,
            error,
            reason: '$key = $value',
          );
          await expectLater(
            decryptBackup(bytes, _password, deriveKey: _mustNotDerive),
            throwsA(
              isA<BackupCryptoException>().having(
                (e) => e.error,
                'error',
                BackupCryptoError.paramsOutOfRange,
              ),
            ),
            reason: '$key = $value',
          );
        }
      },
    );

    test('dentro de los limites si deriva, una sola vez', () async {
      final counter = _CountingDeriver();
      await decryptBackup(
        utf8.encode(file),
        _password,
        deriveKey: counter.call,
      );
      expect(counter.calls, 1);
    });

    test('cifrar con parametros fuera de rango tambien se rechaza', () {
      expect(
        encryptBackup(
          _v5Document(),
          _password,
          params: const Argon2idParams(
            memoryKiB: 4096,
            iterations: 1,
            parallelism: 1,
          ),
          deriveKey: _mustNotDerive,
        ),
        throwsA(isA<BackupCryptoException>()),
      );
    });
  });

  group('g) compatibilidad', () {
    test('los respaldos sin cifrar v3, v4 y v5 se siguen importando igual', () {
      for (final name in [
        'backup_v3.json',
        'backup_v4.json',
        'backup_v5.json',
      ]) {
        final result = decodeBackup(utf8.encode(_fixture(name)));
        expect(result, isA<BackupParseSuccess>(), reason: name);
      }
    });

    test('backup_v5_cifrado.json: con la contrasena da los datos de '
        'backup_v5.json', () async {
      final pending = decodeBackup(
        utf8.encode(_fixture('backup_v5_cifrado.json')),
      );
      expect(pending, isA<BackupNeedsPassword>());
      final needs = pending as BackupNeedsPassword;
      expect(needs.header.params, _small);
      expect(needs.ciphertext.length, greaterThan(16));

      final result = await decodeEncryptedBackup(needs, _fixturePassword);
      _expectSameData(
        (result as BackupParseSuccess).data,
        _data(_v5Document()),
      );
      await _expectWrongPassword(decodeEncryptedBackup(needs, _password));
    });

    test('un decodificador de formatVersion 1 rechaza un archivo cifrado', () {
      // decodeBackup de la app sin HU-06b (backup_codec.dart:343-354 en
      // bc3d388) rechaza como "version mas nueva" un formatVersion mayor que
      // 1 y un encryption no nulo; el archivo cifrado cumple las dos.
      final root = _map(_fixture('backup_v5_cifrado.json'));
      expect(root['formatVersion'] as int, greaterThan(backupFormatVersion));
      expect(root['encryption'], isNotNull);
      // Y en esta version, sin contrasena tampoco se importa nada: es un
      // BackupNeedsPassword (CP2: ya no es un BackupParseFailure).
      final result = decodeBackup(
        utf8.encode(_fixture('backup_v5_cifrado.json')),
      );
      expect(result, isA<BackupNeedsPassword>());
      expect(result, isNot(isA<BackupParseSuccess>()));
      expect(result, isNot(isA<BackupParseFailure>()));
    });

    test(
      'un documento cifrado dentro de otro se rechaza como danado',
      () async {
        final inner = await _encrypt(_v5Document());
        final outer = await _encrypt(inner, seed: 8);
        final pending = decodeBackup(utf8.encode(outer)) as BackupNeedsPassword;
        final result = await decodeEncryptedBackup(pending, _password);
        expect((result as BackupParseFailure).error, BackupError.damaged);
        expect(result, isNot(isA<BackupNeedsPassword>()));
      },
    );
  });

  group('h) aleatoriedad', () {
    test('dos cifrados de lo mismo, con la misma contrasena, no son iguales '
        '(sal y nonce distintos) y ambos descifran igual', () async {
      final doc = _v5Document();
      final a = await encryptBackup(doc, _password, params: _small);
      final b = await encryptBackup(doc, _password, params: _small);
      expect(a, isNot(b));
      expect(_enc(_map(a))['salt'], isNot(_enc(_map(b))['salt']));
      expect(_enc(_map(a))['nonce'], isNot(_enc(_map(b))['nonce']));
      expect(await decryptBackup(utf8.encode(a), _password), utf8.encode(doc));
      expect(await decryptBackup(utf8.encode(b), _password), utf8.encode(doc));
    });

    test('la sal y el nonce salen del generador inyectado', () async {
      final a = await _encrypt(_v5Document(), seed: 1);
      final b = await _encrypt(_v5Document(), seed: 1);
      expect(a, b);
    });
  });
}
