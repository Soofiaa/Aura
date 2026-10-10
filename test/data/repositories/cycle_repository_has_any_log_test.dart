import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/repositories/cycle_repository.dart';

/// watchHasAnyLog (recordatorio de respaldo): reactivo y sin repetir
/// valores iguales. Datos inventados.
void main() {
  late AppDatabase db;
  late CycleRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CycleRepository(db);
  });

  tearDown(() => db.close());

  test('emite false sin registros, true con el primero y false al borrar '
      'todo', () async {
    final emitidos = <bool>[];
    final sub = repo.watchHasAnyLog().listen(emitidos.add);
    await pumpEventQueue();

    await repo.markPeriodDays(['2026-10-02']);
    await pumpEventQueue();
    // Otro dia no repite true.
    await repo.markPeriodDays(['2026-10-03']);
    await pumpEventQueue();
    await repo.deleteAllData();
    await pumpEventQueue();
    await sub.cancel();

    expect(emitidos, [false, true, false]);
  });

  test('coincide con hasAnyLog', () async {
    expect(await repo.watchHasAnyLog().first, await repo.hasAnyLog());
    await repo.markPeriodDays(['2026-10-02']);
    expect(await repo.watchHasAnyLog().first, isTrue);
    expect(await repo.hasAnyLog(), isTrue);
  });
}
