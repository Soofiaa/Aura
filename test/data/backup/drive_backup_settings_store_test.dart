import 'dart:io';

import 'package:aura/data/backup/drive_api_client.dart';
import 'package:aura/data/backup/drive_backup_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory support;
  late DriveBackupSettingsStore store;

  setUp(() {
    support = Directory.systemTemp.createTempSync('aura_drive_');
    store = DriveBackupSettingsStore(supportDirectory: () async => support);
  });

  tearDown(() => support.deleteSync(recursive: true));

  File archivo() => File(p.join(support.path, DriveBackupSettingsStore.fileName));

  test('sin archivo: valores por defecto (apagado, sin cuenta), sin escribir',
      () async {
    expect(await store.read(), const DriveBackupSettings());
    expect(archivo().existsSync(), isFalse);
  });

  test('guarda y vuelve a leer desde otra instancia', () async {
    await store.guardar(const DriveBackupSettings(
      habilitado: true,
      cuenta: 'ana@gmail.com',
      claveSellada: 'blob',
      ultimoRespaldo: '2026-10-20',
      ultimoFallo: DriveApiFailure.offline,
    ));

    final otra = DriveBackupSettingsStore(supportDirectory: () async => support);
    expect(
        await otra.read(),
        const DriveBackupSettings(
          habilitado: true,
          cuenta: 'ana@gmail.com',
          claveSellada: 'blob',
          ultimoRespaldo: '2026-10-20',
          ultimoFallo: DriveApiFailure.offline,
        ));
    expect(File('${archivo().path}.tmp').existsSync(), isFalse);
  });

  test('el blob de la clave jamas sale en toString', () async {
    const settings = DriveBackupSettings(claveSellada: 'SECRETO-BLOB');
    expect(settings.toString(), isNot(contains('SECRETO-BLOB')));
  });

  test('archivo danado o de otra version: valores por defecto', () async {
    for (final contenido in [
      'esto no es json',
      '{"version": 99}',
      '{"version": 1, "habilitado": "si"}',
    ]) {
      archivo().writeAsStringSync(contenido);
      expect(await store.read(), const DriveBackupSettings(),
          reason: contenido);
    }
  });

  test('ultimoFallo desconocido: archivo invalido (valores por defecto)',
      () async {
    archivo().writeAsStringSync('{"version": 1, "habilitado": true, '
        '"cuenta": "a@b.c", "claveSellada": "x", "ultimoRespaldo": null, '
        '"ultimoFallo": "inventado"}');
    expect(await store.read(), const DriveBackupSettings());
  });

  test('delete borra el archivo y emite el estado por defecto', () async {
    await store.guardar(
        const DriveBackupSettings(habilitado: true, cuenta: 'a@b.c'));
    final events = <DriveBackupSettings>[];
    final sub = store.watch().listen(events.add);

    await store.delete();

    expect(archivo().existsSync(), isFalse);
    await store.read();
    expect(events.last, const DriveBackupSettings());
    await sub.cancel();
  });
}
