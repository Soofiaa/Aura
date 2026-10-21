import 'package:aura/utils/keystore_vault.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.soofiaa.aura/system');
  final log = <MethodCall>[];

  void mock(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      log.add(call);
      return handler(call);
    });
  }

  setUp(log.clear);

  test('seal envia el texto al canal y devuelve el blob', () async {
    mock((call) async => 'Zm9vYmFy');

    final blob = await const MethodChannelKeystoreVault().seal('secreto');

    expect(blob, 'Zm9vYmFy');
    expect(log.single.method, 'keystoreEncrypt');
    expect(log.single.arguments, 'secreto');
  });

  test('open envia el blob al canal y devuelve el texto', () async {
    mock((call) async => 'una contrasena');

    final text = await const MethodChannelKeystoreVault().open('Zm9vYmFy');

    expect(text, 'una contrasena');
    expect(log.single.method, 'keystoreDecrypt');
    expect(log.single.arguments, 'Zm9vYmFy');
  });

  test('sin plataforma (tests, escritorio) lanza KeystoreVaultException',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);

    expect(
      () => const MethodChannelKeystoreVault().seal('secreto'),
      throwsA(isA<KeystoreVaultException>()),
    );
  });

  test('error del Keystore se traduce y no deja pasar PlatformException',
      () async {
    mock((call) => throw PlatformException(code: 'keystore'));

    expect(
      () => const MethodChannelKeystoreVault().open('blob'),
      throwsA(isA<KeystoreVaultException>()),
    );
  });

  test('respuesta nula del canal tambien es KeystoreVaultException', () async {
    mock((call) async => null);

    expect(
      () => const MethodChannelKeystoreVault().seal('secreto'),
      throwsA(isA<KeystoreVaultException>()),
    );
  });
}
