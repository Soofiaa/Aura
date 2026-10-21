import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:aura/data/device_settings_store.dart';

void main() {
  late Directory support;
  late DeviceSettingsStore store;

  setUp(() {
    support = Directory.systemTemp.createTempSync('aura_ajustes_');
    store = DeviceSettingsStore(supportDirectory: () async => support);
  });

  tearDown(() => support.deleteSync(recursive: true));

  File archivo() => File(p.join(support.path, DeviceSettingsStore.fileName));

  test('sin archivo: valores por defecto (Recientes oculto, sin aviso de '
      'atraso), sin escribir nada', () async {
    expect(await store.read(), const DeviceSettings());
    expect(const DeviceSettings().ocultarEnRecientes, isTrue);
    expect(const DeviceSettings().avisoAtraso, isFalse);
    expect(archivo().existsSync(), isFalse);
  });

  test('guarda y vuelve a leer desde otra instancia', () async {
    await store.setOcultarEnRecientes(false);
    await store.setAvisoAtraso(true);

    final otra = DeviceSettingsStore(supportDirectory: () async => support);
    expect(await otra.read(),
        const DeviceSettings(ocultarEnRecientes: false, avisoAtraso: true));
    expect(File('${archivo().path}.tmp').existsSync(), isFalse);
  });

  test('archivo danado o de otra version: valores por defecto', () async {
    for (final contenido in [
      'no es json',
      '{"version": 99, "ocultarEnRecientes": false, "avisoAtraso": true}',
      '{"version": 1, "ocultarEnRecientes": "no", "avisoAtraso": true}',
    ]) {
      archivo().writeAsStringSync(contenido);
      expect(await store.read(), const DeviceSettings(), reason: contenido);
    }
  });

  test('watch emite el estado actual y cada cambio', () async {
    final emitidos = <DeviceSettings>[];
    final sub = store.watch().listen(emitidos.add);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await store.setAvisoAtraso(true);
    await store.delete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();

    expect(emitidos, [
      const DeviceSettings(),
      const DeviceSettings(avisoAtraso: true),
      const DeviceSettings(),
    ]);
  });

  test('delete borra el archivo y un .tmp huerfano', () async {
    await store.setAvisoAtraso(true);
    final tmp = File('${archivo().path}.tmp')..writeAsStringSync('x');
    await store.delete();
    expect(archivo().existsSync(), isFalse);
    expect(tmp.existsSync(), isFalse);
  });
}
