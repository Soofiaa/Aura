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

  // watch() con varias suscripciones, igual en el real y en el falso.
  final hora = DateTime(2026, 10, 10, 9, 30);
  final almacenes = <String, BackupReminderStore Function()>{
    'real': () => BackupReminderStore(
          supportDirectory: () async => Directory(p.join(root.path, 'files')),
          clock: () => hora,
        ),
    'falso': () => FakeBackupReminderStore(clock: () => hora),
  };
  final queNoSeLeen = <String, BackupReminderStore Function()>{
    'real': () => BackupReminderStore(
          supportDirectory: () async => throw StateError('sin carpeta'),
          clock: () => hora,
        ),
    'falso': () =>
        FakeBackupReminderStore(clock: () => hora)
          ..readError = StateError('sin carpeta'),
  };
  const inicial = BackupReminderState(primerUso: '2026-10-10');
  const pospuesto =
      BackupReminderState(primerUso: '2026-10-10', pospuestoHasta: '2026-10-17');

  almacenes.forEach((nombre, crear) {
    group('watch, almacen $nombre', () {
      test('dos suscriptores a la vez reciben el estado actual y los cambios',
          () async {
        final store = crear();
        final stream = store.watch();
        final a = <BackupReminderState>[];
        final b = <BackupReminderState>[];
        final subA = stream.listen(a.add);
        final subB = stream.listen(b.add);
        await store.read();
        await pumpEventQueue();
        await store.postpone();
        await pumpEventQueue();
        await subA.cancel();
        await subB.cancel();

        expect(a, [inicial, pospuesto]);
        expect(b, [inicial, pospuesto]);
      });

      test('cancelar suelta la suscripcion y se puede volver a escuchar',
          () async {
        final store = crear();
        final stream = store.watch();
        final primera = <BackupReminderState>[];
        final sub = stream.listen(primera.add);
        // La lectura de watch va en la fila: esta termina despues.
        await store.read();
        await pumpEventQueue();
        await sub.cancel();
        await store.postpone();
        await pumpEventQueue();
        expect(primera, [inicial]);

        final segunda = <BackupReminderState>[];
        final otra = stream.listen(segunda.add);
        await store.read();
        await pumpEventQueue();
        await store.setEnabled(false);
        await pumpEventQueue();
        await otra.cancel();
        expect(segunda, [
          pospuesto,
          const BackupReminderState(
              primerUso: '2026-10-10',
              pospuestoHasta: '2026-10-17',
              activado: false),
        ]);
      });
    });
  });

  queNoSeLeen.forEach((nombre, crear) {
    test('watch, almacen $nombre: un error de lectura llega a cada '
        'suscriptor como error del stream', () async {
      final stream = crear().watch();
      final errores = <List<Object>>[[], []];
      final datos = <BackupReminderState>[];
      final subs = [
        for (final lista in errores)
          stream.listen(datos.add, onError: (Object e) => lista.add(e)),
      ];
      await pumpEventQueue();
      for (final s in subs) {
        await s.cancel();
      }
      expect(datos, isEmpty);
      for (final lista in errores) {
        expect(lista, [isA<StateError>()]);
      }
    });
  });
}
