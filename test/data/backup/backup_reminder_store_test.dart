import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:aura/data/backup/backup_reminder_store.dart';

void main() {
  late Directory root;
  late Directory support;
  late DateTime now;
  late BackupReminderStore store;

  BackupReminderStore nuevoStore() => BackupReminderStore(
        supportDirectory: () async => support,
        clock: () => now,
      );

  setUp(() {
    root = Directory.systemTemp.createTempSync('aura_reminder_test');
    support = Directory(p.join(root.path, 'files'))..createSync();
    now = DateTime(2026, 10, 10, 9, 30);
    store = nuevoStore();
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  File archivo() => File(p.join(support.path, BackupReminderStore.fileName));
  File temporal() => File('${archivo().path}.tmp');

  Map<String, Object?> contenido() =>
      jsonDecode(archivo().readAsStringSync()) as Map<String, Object?>;

  test('el archivo va en la raiz de files/ y se llama recordatorio_respaldo',
      () {
    expect(BackupReminderStore.fileName, 'recordatorio_respaldo.json');
    expect(BackupReminderStore.formatVersion, 1);
  });

  group('primera lectura', () {
    test('crea primerUso = hoy con los valores por defecto y lo guarda',
        () async {
      final state = await store.read();

      expect(state, const BackupReminderState(primerUso: '2026-10-10'));
      expect(state.activado, isTrue);
      expect(state.ultimoRespaldo, isNull);
      expect(state.pospuestoHasta, isNull);
      expect(contenido(), {
        'version': 1,
        'primerUso': '2026-10-10',
        'ultimoRespaldo': null,
        'pospuestoHasta': null,
        'activado': true,
      });
      expect(temporal().existsSync(), isFalse);
    });

    test('las lecturas siguientes conservan primerUso aunque pasen dias',
        () async {
      await store.read();
      now = DateTime(2026, 11, 3, 23, 59);
      expect((await store.read()).primerUso, '2026-10-10');
      expect((await nuevoStore().read()).primerUso, '2026-10-10');
    });
  });

  group('escrituras', () {
    test('recordBackup guarda hoy (reloj inyectado) y otra instancia lo lee',
        () async {
      await store.read();
      now = DateTime(2026, 10, 20, 0, 5);
      final state = await store.recordBackup();

      expect(state.ultimoRespaldo, '2026-10-20');
      expect(state.primerUso, '2026-10-10');
      expect((await nuevoStore().read()).ultimoRespaldo, '2026-10-20');
    });

    test('recordBackup sin lectura previa tambien crea primerUso', () async {
      final state = await store.recordBackup();
      expect(state.primerUso, '2026-10-10');
      expect(state.ultimoRespaldo, '2026-10-10');
    });

    test('postpone pospone 7 dias y recordBackup lo quita', () async {
      expect((await store.postpone()).pospuestoHasta, '2026-10-17');
      expect((await nuevoStore().read()).pospuestoHasta, '2026-10-17');

      final state = await store.recordBackup();
      expect(state.pospuestoHasta, isNull);
      expect(contenido()['pospuestoHasta'], isNull);
    });

    test('postpone cruza el cambio de horario de septiembre por dias', () async {
      now = DateTime(2026, 9, 3, 22, 0);
      expect((await store.postpone()).pospuestoHasta, '2026-09-10');
    });

    test('setEnabled se guarda', () async {
      expect((await store.setEnabled(false)).activado, isFalse);
      expect((await nuevoStore().read()).activado, isFalse);
      expect((await store.setEnabled(true)).activado, isTrue);
      expect(contenido()['activado'], isTrue);
    });

    test('las operaciones seguidas no se pisan', () async {
      await Future.wait([
        store.read(),
        store.postpone(),
        store.setEnabled(false),
        store.recordBackup(),
      ]);
      expect(await nuevoStore().read(), const BackupReminderState(
        primerUso: '2026-10-10',
        ultimoRespaldo: '2026-10-10',
        activado: false,
      ));
    });

    test('un .tmp viejo no impide escribir y no queda', () async {
      temporal().writeAsStringSync('a medio escribir');
      await store.recordBackup();
      expect(temporal().existsSync(), isFalse);
      expect(contenido()['ultimoRespaldo'], '2026-10-10');
    });

    test('si no se puede escribir, recordBackup lanza y no deja .tmp',
        () async {
      // Una carpeta en lugar del archivo hace fallar el rename.
      Directory(archivo().path).createSync();
      await expectLater(
          store.recordBackup(), throwsA(isA<FileSystemException>()));
      expect(temporal().existsSync(), isFalse);
    });

    test('si no se puede escribir, read igual devuelve los valores por '
        'defecto', () async {
      Directory(archivo().path).createSync();
      expect(await store.read(),
          const BackupReminderState(primerUso: '2026-10-10'));
    });
  });

  group('archivo ilegible: valores por defecto', () {
    final casos = <String, String>{
      'no es JSON': 'no es json {',
      'JSON que no es objeto': '[1, 2]',
      'version desconocida':
          '{"version":2,"primerUso":"2026-01-01","ultimoRespaldo":null,'
              '"pospuestoHasta":null,"activado":true}',
      'sin version':
          '{"primerUso":"2026-01-01","ultimoRespaldo":null,'
              '"pospuestoHasta":null,"activado":true}',
      'fecha que no existe':
          '{"version":1,"primerUso":"2026-02-30","ultimoRespaldo":null,'
              '"pospuestoHasta":null,"activado":true}',
      'fecha con otro formato':
          '{"version":1,"primerUso":"2026-01-01","ultimoRespaldo":"1/9/2026",'
              '"pospuestoHasta":null,"activado":true}',
      'activado que no es bool':
          '{"version":1,"primerUso":"2026-01-01","ultimoRespaldo":null,'
              '"pospuestoHasta":null,"activado":"si"}',
      'falta primerUso':
          '{"version":1,"ultimoRespaldo":null,"pospuestoHasta":null,'
              '"activado":true}',
    };
    casos.forEach((caso, texto) {
      test(caso, () async {
        archivo().writeAsStringSync(texto);
        expect(await store.read(),
            const BackupReminderState(primerUso: '2026-10-10'));
        // Queda reemplazado por uno valido.
        expect(contenido()['version'], 1);
        expect(contenido()['primerUso'], '2026-10-10');
      });
    });

    test('un archivo valido de la version 1 se lee tal cual', () async {
      archivo().writeAsStringSync(
          '{"version":1,"primerUso":"2026-01-01","ultimoRespaldo":"2026-09-01",'
          '"pospuestoHasta":"2026-10-12","activado":false}');
      expect(
          await store.read(),
          const BackupReminderState(
            primerUso: '2026-01-01',
            ultimoRespaldo: '2026-09-01',
            pospuestoHasta: '2026-10-12',
            activado: false,
          ));
    });
  });

  group('borrar', () {
    test('delete borra el archivo y un .tmp huerfano', () async {
      await store.recordBackup();
      temporal().writeAsStringSync('huerfano');
      await store.delete();
      expect(archivo().existsSync(), isFalse);
      expect(temporal().existsSync(), isFalse);
    });

    test('despues de delete, primerUso vuelve a ser el dia de la lectura',
        () async {
      await store.recordBackup();
      await store.delete();
      now = DateTime(2026, 12, 1, 8, 0);
      expect(await store.read(),
          const BackupReminderState(primerUso: '2026-12-01'));
    });

    test('delete sin archivo no falla', () async {
      await store.delete();
      expect(archivo().existsSync(), isFalse);
    });
  });

  group('watch (para la interfaz)', () {
    test('emite el estado actual y cada cambio', () async {
      final emitidos = <BackupReminderState>[];
      final sub = store.watch().listen(emitidos.add);
      await store.read();
      await store.postpone();
      await store.recordBackup();
      await store.setEnabled(false);
      await store.delete();
      await pumpEventQueue();
      await sub.cancel();

      expect(emitidos.first, const BackupReminderState(primerUso: '2026-10-10'));
      expect(emitidos.skip(1).toList(), [
        const BackupReminderState(
            primerUso: '2026-10-10', pospuestoHasta: '2026-10-17'),
        const BackupReminderState(
            primerUso: '2026-10-10', ultimoRespaldo: '2026-10-10'),
        const BackupReminderState(
            primerUso: '2026-10-10',
            ultimoRespaldo: '2026-10-10',
            activado: false),
        const BackupReminderState(primerUso: '2026-10-10'),
      ]);
      // delete no vuelve a crear el archivo por si solo.
      expect(archivo().existsSync(), isFalse);
    });
  });
}
