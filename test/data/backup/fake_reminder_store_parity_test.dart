import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:aura/data/backup/backup_reminder_store.dart';

import '../../support/fake_backup.dart';

/// FakeBackupReminderStore (tests de widget) debe comportarse como el
/// almacen real: misma secuencia de operaciones, mismos resultados y
/// mismas emisiones de watch.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('aura_reminder_parity');
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<(List<Object>, List<BackupReminderState>)> recorrer(
      BackupReminderStore store, void Function(DateTime) fijarHora) async {
    final emitidos = <BackupReminderState>[];
    final sub = store.watch().listen(emitidos.add);
    await pumpEventQueue();
    final resultados = <Object>[
      await store.read(),
      await store.postpone(),
      await store.setEnabled(false),
    ];
    fijarHora(DateTime(2026, 10, 20, 8, 0));
    resultados
      ..add(await store.recordBackup())
      ..add(await store.read())
      ..add(store.today());
    await store.delete();
    fijarHora(DateTime(2026, 11, 2, 23, 30));
    resultados
      ..add(await store.read())
      ..add(await store.setEnabled(true));
    await pumpEventQueue();
    await sub.cancel();
    return (resultados, emitidos);
  }

  test('misma secuencia, mismos resultados y emisiones', () async {
    var horaReal = DateTime(2026, 10, 10, 9, 30);
    final real = BackupReminderStore(
      supportDirectory: () async => Directory(p.join(root.path, 'files')),
      clock: () => horaReal,
    );
    var horaFalsa = DateTime(2026, 10, 10, 9, 30);
    final falso = FakeBackupReminderStore(clock: () => horaFalsa);

    final deReal = await recorrer(real, (h) => horaReal = h);
    final deFalso = await recorrer(falso, (h) => horaFalsa = h);

    expect(deFalso.$1, deReal.$1);
    expect(deFalso.$2, deReal.$2);
    // La secuencia de verdad recorre los casos que importan.
    expect(deReal.$2.first, const BackupReminderState(primerUso: '2026-10-10'));
    expect(deReal.$1.last, const BackupReminderState(primerUso: '2026-11-02'));
  });
}
