import 'dart:convert';
import 'dart:io';

import 'package:aura/data/backup/auto_drive_backup_service.dart';
import 'package:aura/data/backup/drive_api_client.dart';
import 'package:aura/data/backup/drive_backup_gateway.dart';
import 'package:aura/data/backup/drive_backup_settings_store.dart';
import 'package:aura/domain/backup_crypto.dart';
import 'package:aura/utils/keystore_vault.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGateway implements DriveBackupGateway {
  _FakeGateway();

  DriveSignInResult signInResult = const DriveSignedIn('ana@gmail.com');
  DriveApiException? uploadError;
  final uploads = <(String, List<int>)>[];
  int signOutCalls = 0;

  @override
  Future<String?> restoreSession() async => 'ana@gmail.com';

  @override
  Future<DriveSignInResult> signIn() async => signInResult;

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
  _FakeVault();

  bool failOpen = false;
  int sealCalls = 0;

  @override
  Future<String> seal(String plaintext) async {
    sealCalls++;
    return 'sellada:$plaintext';
  }

  @override
  Future<String> open(String blob) async {
    if (failOpen) throw const KeystoreVaultException();
    expect(blob, startsWith('sellada:'));
    return blob.substring('sellada:'.length);
  }
}

Future<String> _fakeEncrypt(
    String document, String password, Argon2idParams params) async {
  return 'CIFRADO($password):$document';
}

void main() {
  late Directory support;
  late DriveBackupSettingsStore settings;
  late _FakeGateway gateway;
  late _FakeVault vault;
  late int recordCalls;
  late AutoDriveBackupService service;

  final json = '{"app":"Aura","data":{"dailyLogs":[]}}';

  AutoDriveBackupService build({DateTime Function()? now}) => AutoDriveBackupService(
        settings: settings,
        gateway: gateway,
        vault: vault,
        buildExportJson: () async => json,
        recordBackup: () async => recordCalls++,
        encrypt: _fakeEncrypt,
        now: now ?? () => DateTime(2026, 10, 20, 9),
      );

  setUp(() {
    support = Directory.systemTemp.createTempSync('aura_auto_');
    settings = DriveBackupSettingsStore(supportDirectory: () async => support);
    gateway = _FakeGateway();
    vault = _FakeVault();
    recordCalls = 0;
    service = build();
  });

  tearDown(() => support.deleteSync(recursive: true));

  Future<void> habilitar({String password = 'una contrasena'}) async {
    final result = await service.enable(password: password);
    expect(result, isA<DriveEnabled>());
  }

  test('apagado: no pide red ni clave', () async {
    expect(await service.maybeBackup(), AutoBackupStatus.deshabilitado);
    expect(gateway.uploads, isEmpty);
  });

  test('activar: pide cuenta, sella la clave y hace el primer respaldo',
      () async {
    final result = await service.enable(password: 'una contrasena');

    expect(result, isA<DriveEnabled>());
    expect((result as DriveEnabled).email, 'ana@gmail.com');
    expect(result.primerRespaldo, AutoBackupStatus.ok);
    expect(vault.sealCalls, 1);
    expect(gateway.uploads.single.$1, automaticBackupFileName);

    // El archivo que sube esta cifrado: contiene la clave como mucho dentro
    // del sobre, y el JSON en claro no aparece.
    final contenido = utf8.decode(gateway.uploads.single.$2);
    expect(contenido, startsWith('CIFRADO(una contrasena):'));
    expect(contenido, contains('"dailyLogs"'));

    // Queda anotado para el recordatorio (HU-08) y en los ajustes.
    expect(recordCalls, 1);
    final guardado = await settings.read();
    expect(guardado.habilitado, isTrue);
    expect(guardado.cuenta, 'ana@gmail.com');
    expect(guardado.claveSellada, 'sellada:una contrasena');
    expect(guardado.ultimoRespaldo, '2026-10-20');
  });

  test('el mismo dia no vuelve a subir; force si', () async {
    await habilitar();

    expect(await service.maybeBackup(), AutoBackupStatus.sinCambios);
    expect(gateway.uploads, hasLength(1));

    expect(await service.maybeBackup(force: true), AutoBackupStatus.ok);
    expect(gateway.uploads, hasLength(2));
  });

  test('al dia siguiente vuelve a subir solo', () async {
    await habilitar();
    service = build(now: () => DateTime(2026, 10, 21, 8));

    expect(await service.maybeBackup(), AutoBackupStatus.ok);
    expect(gateway.uploads, hasLength(2));
    expect(recordCalls, 2);
  });

  test('cancelar el inicio de sesion no cambia nada', () async {
    gateway.signInResult = const DriveSignInCancelled();

    expect(await service.enable(password: 'x'), isA<EnableDriveCancelled>());
    expect((await settings.read()).habilitado, isFalse);
    expect(gateway.uploads, isEmpty);
  });

  test('sin Keystore (permiso u otro telefono): avisa y no sube', () async {
    await habilitar();
    vault.failOpen = true;

    expect(await service.maybeBackup(force: true),
        AutoBackupStatus.claveNoDisponible);
    expect(gateway.uploads, hasLength(1)); // solo el de activar
  });

  test('sin red: queda el fallo anotado y reintenta al dia siguiente',
      () async {
    await habilitar();
    gateway.uploadError =
        DriveApiException(DriveApiFailure.offline, 'sin conexion');
    service = build(now: () => DateTime(2026, 10, 21, 8));

    expect(await service.maybeBackup(), AutoBackupStatus.offline);
    final trasFallo = await settings.read();
    expect(trasFallo.ultimoFallo, DriveApiFailure.offline);
    expect(trasFallo.ultimoRespaldo, '2026-10-20'); // no avanzo

    gateway.uploadError = null;
    expect(await service.maybeBackup(), AutoBackupStatus.ok);
    final trasReintento = await settings.read();
    expect(trasReintento.ultimoFallo, isNull);
    expect(trasReintento.ultimoRespaldo, '2026-10-21');
    expect(recordCalls, 2);
  });

  test('sesion revocada: unauthorized anotado', () async {
    await habilitar();
    gateway.uploadError =
        DriveApiException(DriveApiFailure.unauthorized, 'revocada');
    service = build(now: () => DateTime(2026, 10, 21, 8));

    expect(await service.maybeBackup(), AutoBackupStatus.unauthorized);
    expect((await settings.read()).ultimoFallo, DriveApiFailure.unauthorized);
  });

  test('desactivar apaga, olvida la cuenta y cierra la sesion', () async {
    await habilitar();

    await service.disable();

    expect(await settings.read(), const DriveBackupSettings());
    expect(gateway.signOutCalls, 1);
    expect(await service.maybeBackup(force: true),
        AutoBackupStatus.deshabilitado);
  });

  test('los respaldos se hacen de a uno, cada llamada con su resultado',
      () async {
    await habilitar();
    final futuros = [
      for (var i = 0; i < 3; i++) service.maybeBackup(force: true),
    ];

    final resultados = await Future.wait(futuros);

    expect(resultados, everyElement(AutoBackupStatus.ok));
    expect(gateway.uploads, hasLength(4)); // activar + 3
  });
}
