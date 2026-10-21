import 'package:aura/data/backup/auto_drive_backup_service.dart';
import 'package:aura/data/backup/backup_service.dart';
import 'package:aura/data/backup/drive_api_client.dart';
import 'package:aura/data/backup/drive_backup_gateway.dart';
import 'package:aura/data/backup/drive_backup_settings_store.dart';
import 'package:aura/domain/backup_crypto.dart';
import 'package:aura/screens/drive_backup_section.dart';
import 'package:aura/utils/day_key.dart';
import 'package:aura/utils/keystore_vault.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_drive_backup_settings_store.dart';

class _FakeGateway implements DriveBackupGateway {
  DriveApiException? uploadError;
  final uploads = <(String, List<int>)>[];
  int signOutCalls = 0;

  @override
  Future<String?> restoreSession() async => 'ana@gmail.com';

  @override
  Future<DriveSignInResult> signIn() async =>
      const DriveSignedIn('ana@gmail.com');

  @override
  Future<void> signOut() async => signOutCalls++;

  @override
  Future<void> uploadBackup({
    required String fileName,
    required List<int> bytes,
  }) async {
    final error = uploadError;
    if (error != null) throw error;
    uploads.add((fileName, bytes));
  }
}

class _FakeVault implements KeystoreVault {
  int sealCalls = 0;

  @override
  Future<String> seal(String plaintext) async {
    sealCalls++;
    return 'sellada:$plaintext';
  }

  @override
  Future<String> open(String blob) async {
    expect(blob, startsWith('sellada:'));
    return blob.substring('sellada:'.length);
  }
}

Future<String> _fakeEncrypt(
    String document, String password, Argon2idParams params) async {
  return 'CIFRADO($password):$document';
}

void main() {
  late FakeDriveBackupSettingsStore store;
  late _FakeGateway gateway;
  late _FakeVault vault;
  late AutoDriveBackupService service;

  setUp(() {
    store = FakeDriveBackupSettingsStore();
    gateway = _FakeGateway();
    vault = _FakeVault();
    service = AutoDriveBackupService(
      settings: store,
      gateway: gateway,
      vault: vault,
      buildExportJson: () async => '{"app":"Aura"}',
      recordBackup: () async {},
      encrypt: _fakeEncrypt,
      // En widget tests el isolate real (Isolate.run) no avanza dentro del
      // fake async: se usa el runner de tests del codigo del respaldo.
      runner: runInSameIsolate,
    );
  });

  Future<void> pumpSeccion(WidgetTester tester,
      {String id = 'id-de-prueba.apps.googleusercontent.com'}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DriveBackupSection(
            service: service,
            settingsStore: store,
            clientId: id,
          ),
        ),
      ),
    ));
    // Deja llegar el primer evento de watch() (lectura de archivo).
    await tester.pumpAndSettle();
  }

  SwitchListTile interruptor(WidgetTester tester) =>
      tester.widget<SwitchListTile>(
          find.byKey(const Key('respaldo_drive_switch')));

  Future<void> habilitarEnStore({DriveApiFailure? fallo}) async {
    await store.guardar(DriveBackupSettings(
      habilitado: true,
      cuenta: 'ana@gmail.com',
      claveSellada: 'sellada:frase con varias palabras',
      ultimoRespaldo: DayKey.fromDate(DateTime.now()),
      ultimoFallo: fallo,
    ));
  }

  testWidgets('apagado: explica que el respaldo va cifrado y no ofrece '
      'respaldar ahora', (tester) async {
    await pumpSeccion(tester);

    expect(find.byKey(const Key('respaldo_drive_switch')), findsOneWidget);
    expect(interruptor(tester).value, isFalse);
    expect(find.textContaining('cifrado con una contraseña'), findsOneWidget);
    expect(find.byKey(const Key('respaldar_ahora')), findsNothing);
  });

  testWidgets('sin client ID: el interruptor queda deshabilitado con la '
      'configuracion pendiente', (tester) async {
    await pumpSeccion(tester, id: '');

    expect(interruptor(tester).onChanged, isNull);
    expect(find.textContaining('Configuración pendiente'), findsOneWidget);

    await tester.tap(find.byKey(const Key('respaldo_drive_switch')));
    await tester.pumpAndSettle();
    expect(find.text('Proteger respaldos en Drive'), findsNothing);
    expect((await store.read()).habilitado, isFalse);
  });

  testWidgets('activar: pide la contrasena una sola vez, sube el primer '
      'respaldo y enciende', (tester) async {
    await pumpSeccion(tester);

    await tester.tap(find.byKey(const Key('respaldo_drive_switch')));
    await tester.pumpAndSettle();

    expect(find.text('Proteger respaldos en Drive'), findsOneWidget);
    // Sin salida "sin contrasena": el automatico siempre va cifrado.
    expect(find.text('Continuar sin contraseña'), findsNothing);

    await tester.enterText(
        find.byKey(const ValueKey('protect-password')), 'frase con varias palabras');
    await tester.enterText(
        find.byKey(const ValueKey('protect-repeat')), 'frase con varias palabras');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activar respaldo'));
    await tester.pumpAndSettle();

    expect(interruptor(tester).value, isTrue);
    expect(find.textContaining('Cuenta: ana@gmail.com'), findsOneWidget);
    expect(find.textContaining('Último respaldo: hoy'), findsOneWidget);
    expect(find.textContaining('primer respaldo subido a Google Drive'),
        findsOneWidget);
    expect(gateway.uploads, hasLength(1));
    expect(vault.sealCalls, 1);
    expect((await store.read()).habilitado, isTrue);
    expect((await store.read()).claveSellada, isNotNull);
  });

  testWidgets('cancelar el dialogo deja el respaldo apagado', (tester) async {
    await pumpSeccion(tester);

    await tester.tap(find.byKey(const Key('respaldo_drive_switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(interruptor(tester).value, isFalse);
    expect((await store.read()).habilitado, isFalse);
    expect(gateway.uploads, isEmpty);
    expect(vault.sealCalls, 0);
  });

  testWidgets('respaldar ahora: con exito avisa y sube el archivo',
      (tester) async {
    await habilitarEnStore();
    await pumpSeccion(tester);

    await tester.tap(find.byKey(const Key('respaldar_ahora')));
    await tester.pumpAndSettle();

    expect(find.text('Respaldo subido a Google Drive.'), findsOneWidget);
    expect(gateway.uploads.single.$1, automaticBackupFileName);
    expect(find.byKey(const Key('respaldo_drive_fallo')), findsNothing);
  });

  testWidgets('respaldar ahora sin conexion: avisa y anota el fallo en la '
      'seccion', (tester) async {
    await habilitarEnStore();
    gateway.uploadError = DriveApiException(DriveApiFailure.offline, 'x');
    await pumpSeccion(tester);

    await tester.tap(find.byKey(const Key('respaldar_ahora')));
    await tester.pumpAndSettle();

    expect(find.text('Sin conexión: el próximo respaldo automático lo '
        'reintentará.'), findsOneWidget);
    expect(find.byKey(const Key('respaldo_drive_fallo')), findsOneWidget);
    expect(find.textContaining('Último intento falló: sin conexión'),
        findsOneWidget);
    expect((await store.read()).ultimoFallo, DriveApiFailure.offline);
  });

  testWidgets('quitar respaldo: confirma, cierra la sesion y apaga',
      (tester) async {
    await habilitarEnStore();
    await pumpSeccion(tester);
    expect(interruptor(tester).value, isTrue);

    await tester.tap(find.byKey(const Key('respaldo_drive_switch')));
    await tester.pumpAndSettle();
    expect(find.text('¿Quitar el respaldo automático?'), findsOneWidget);

    await tester.tap(find.text('Quitar respaldo'));
    await tester.pumpAndSettle();

    expect(interruptor(tester).value, isFalse);
    expect(find.text('Respaldo automático desactivado.'), findsOneWidget);
    expect(gateway.signOutCalls, 1);
    expect((await store.read()).habilitado, isFalse);
  });
}
