import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/models/day_enums.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/domain/current_period.dart';

/// CP1b de la interfaz del periodo cerrado: foto de varios dias,
/// closePeriod y marcar dia/rango con foto. Fechas inventadas de 2026;
/// "hoy" es el 15 de julio salvo que se diga otra cosa. Los numeros de
/// "caso" son los de la tabla de casos borde de la propuesta (Etapa A).
void main() {
  late AppDatabase db;
  late CycleRepository repo;

  const today = '2026-07-15';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CycleRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// Escribe una fila tal cual, sin pasar por la logica del repositorio
  /// (como la dejan la migracion v4, el formulario o una version vieja).
  Future<void> put(
    String date, {
    bool period = false,
    bool explicit = false,
    PeriodEndSource? end,
    FlowIntensity? flow,
    Mood? mood,
    String? notes,
    Set<Symptom> symptoms = const {},
  }) async {
    await db.into(db.dailyLogs).insert(DailyLogsCompanion.insert(
          date: date,
          isPeriodDay: Value(period),
          periodDayExplicit: Value(explicit),
          periodEnd: Value(end),
          flow: Value(flow),
          mood: Value(mood),
          notes: Value(notes),
        ));
    for (final s in symptoms) {
      await db
          .into(db.dailyLogSymptoms)
          .insert(DailyLogSymptomsCompanion.insert(logDate: date, symptom: s));
    }
  }

  Future<void> marked(List<String> dates) async {
    for (final d in dates) {
      await put(d, period: true);
    }
  }

  /// Toda la base de dias (filas completas y sintomas), para comparar
  /// "antes" y "despues de Deshacer" sin elegir columnas a mano.
  Future<List<Object>> dump() async {
    final logs = await (db.select(db.dailyLogs)
          ..orderBy([(t) => OrderingTerm.asc(t.date)]))
        .get();
    final symptoms = await (db.select(db.dailyLogSymptoms)
          ..orderBy([
            (t) => OrderingTerm.asc(t.logDate),
            (t) => OrderingTerm.asc(t.symptom),
          ]))
        .get();
    return [...logs, ...symptoms];
  }

  /// Hace fallar cualquier escritura de [date] en daily_logs (para probar
  /// que una transaccion a medias no deja nada escrito).
  Future<void> failWritesOn(String date) async {
    await db.customStatement('''
      CREATE TRIGGER fail_insert BEFORE INSERT ON daily_logs
      WHEN NEW.date = '$date' BEGIN SELECT RAISE(ABORT, 'forzado'); END''');
    await db.customStatement('''
      CREATE TRIGGER fail_update BEFORE UPDATE ON daily_logs
      WHEN NEW.date = '$date' BEGIN SELECT RAISE(ABORT, 'forzado'); END''');
    await db.customStatement('''
      CREATE TRIGGER fail_delete BEFORE DELETE ON daily_logs
      WHEN OLD.date = '$date' BEGIN SELECT RAISE(ABORT, 'forzado'); END''');
  }

  Matcher throwsPeriodEnd(PeriodEndProblem problem) => throwsA(
      isA<PeriodEndException>().having((e) => e.problem, 'problem', problem));

  group('foto de varios dias (takeDaysSnapshot / restoreDaysSnapshot)', () {
    test('captura filas completas y la ausencia de fila', () async {
      await put('2026-07-10',
          period: true,
          end: PeriodEndSource.declared,
          flow: FlowIntensity.ligero,
          mood: Mood.feliz,
          notes: 'nota');

      final snapshot =
          await repo.takeDaysSnapshot(['2026-07-11', '2026-07-10']);

      expect(snapshot.dates, ['2026-07-10', '2026-07-11']);
      expect(snapshot.rows['2026-07-10'], await repo.getDay('2026-07-10'));
      expect(snapshot.rows['2026-07-10']!.periodEnd, PeriodEndSource.declared);
      expect(snapshot.rows.containsKey('2026-07-11'), isTrue);
      expect(snapshot.rows['2026-07-11'], isNull);
    });

    test('restaura exactamente, incluido period_end, y borra las filas que '
        'no existian', () async {
      await put('2026-07-10', period: true, mood: Mood.feliz);
      await put('2026-07-11',
          period: true, end: PeriodEndSource.inferred, notes: 'n');
      await put('2026-07-12', explicit: true);
      final before = await dump();
      final snapshot = await repo.takeDaysSnapshot(
          ['2026-07-10', '2026-07-11', '2026-07-12', '2026-07-13']);

      await repo.setPeriodDayExplicitly('2026-07-11', isPeriodDay: false);
      await repo.markPeriodDays(['2026-07-12', '2026-07-13']);
      await repo.restoreDaysSnapshot(snapshot);

      expect(await dump(), before);
    });

    test('no toca dias fuera de la foto', () async {
      await marked(['2026-07-10', '2026-07-20']);
      final snapshot = await repo.takeDaysSnapshot(['2026-07-10']);
      await repo.setPeriodDayExplicitly('2026-07-20', isPeriodDay: false);

      await repo.restoreDaysSnapshot(snapshot);

      expect((await repo.getDay('2026-07-20'))!.isPeriodDay, isFalse);
    });

    test('atomicidad: si una escritura falla no cambia nada', () async {
      await marked(['2026-07-10']);
      final snapshot = await repo
          .takeDaysSnapshot(['2026-07-10', '2026-07-11', '2026-07-12']);
      await repo.markPeriodDays(['2026-07-11', '2026-07-12']);
      await repo.setPeriodDayExplicitly('2026-07-10', isPeriodDay: false);
      final changed = await dump();

      // El 12 es el ultimo que se restaura: el 10 y el 11 ya se habrian
      // escrito si no hubiera transaccion.
      await failWritesOn('2026-07-12');
      await expectLater(repo.restoreDaysSnapshot(snapshot), throwsA(anything));

      expect(await dump(), changed);
    });

    test('atomicidad con el CHECK de period_end: una fila invalida en la foto '
        'revierte las demas', () async {
      await marked(['2026-07-10']);
      final bad = DailyLogRow(
        date: '2026-07-11',
        isPeriodDay: false,
        periodDayExplicit: false,
        periodEnd: PeriodEndSource.declared,
      );
      final snapshot =
          DaysSnapshot({'2026-07-10': null, '2026-07-11': bad});
      final before = await dump();

      await expectLater(repo.restoreDaysSnapshot(snapshot), throwsA(anything));

      expect(await dump(), before);
    });

    test('restaurar una foto vacia no hace nada', () async {
      await marked(['2026-07-10']);
      final before = await dump();
      await repo.restoreDaysSnapshot(await repo.takeDaysSnapshot([]));
      expect(await dump(), before);
    });
  });

  group('closePeriod', () {
    test('caso 3: solo hoy marcado, "Termino hoy" deja un periodo de 1 dia '
        'cerrado', () async {
      await marked([today]);

      await repo.closePeriod(today, today, today: today);

      final day = await repo.getDay(today);
      expect(day!.isPeriodDay, isTrue);
      expect(day.periodEnd, PeriodEndSource.declared);
      final cycle = (await repo.getDerivedCycles()).single;
      expect(cycle.periodLengthDays, 1);
      expect(cycle.isClosed, isTrue);
    });

    test('caso 4: abierto 10-13, "Termino hoy" el 15 marca 14 y 15 con el fin '
        'en el 15; Deshacer quita 14, 15 y el fin', () async {
      await marked(['2026-07-10', '2026-07-11', '2026-07-12', '2026-07-13']);
      final before = await dump();

      final snapshot =
          await repo.closePeriod('2026-07-10', today, today: today);

      expect((await repo.getDay('2026-07-14'))!.isPeriodDay, isTrue);
      expect((await repo.getDay(today))!.periodEnd, PeriodEndSource.declared);
      final cycle = (await repo.getDerivedCycles()).single;
      expect(cycle.periodLengthDays, 6);
      expect(cycle.isClosed, isTrue);
      expect(snapshot.dates, ['2026-07-14', today]);

      await repo.restoreDaysSnapshot(snapshot);

      expect(await dump(), before);
      expect((await repo.getDerivedCycles()).single.isClosed, isFalse);
    });

    test('caso 5 (decision 5A): dias marcados despues del dia elegido '
        'bloquean con markedDaysAfter y no cambia nada', () async {
      await marked(['2026-07-10', '2026-07-11', '2026-07-12', '2026-07-13',
          '2026-07-14']);
      final before = await dump();

      await expectLater(
        repo.closePeriod('2026-07-10', '2026-07-12', today: today),
        throwsA(isA<PeriodEndException>()
            .having((e) => e.problem, 'problem',
                PeriodEndProblem.markedDaysAfter)
            .having((e) => e.check.markedDaysAfter, 'markedDaysAfter', 2)),
      );
      expect(await dump(), before);
    });

    test('caso 6: un dia anterior al inicio o futuro lanza el error tipado y '
        'no cambia nada', () async {
      await marked(['2026-07-10', '2026-07-11']);
      final before = await dump();

      await expectLater(
          repo.closePeriod('2026-07-10', '2026-07-09', today: today),
          throwsPeriodEnd(PeriodEndProblem.beforeStart));
      await expectLater(
          repo.closePeriod('2026-07-10', '2026-07-16', today: today),
          throwsPeriodEnd(PeriodEndProblem.future));
      expect(await dump(), before);
    });

    test('CHECK de period_end: cerrar en un dia con "No" explicito lanza '
        'noBleedingThatDay y no cambia nada', () async {
      await marked(['2026-07-10', '2026-07-11']);
      await put('2026-07-13', explicit: true, mood: Mood.triste);
      final before = await dump();

      await expectLater(
          repo.closePeriod('2026-07-10', '2026-07-13', today: today),
          throwsPeriodEnd(PeriodEndProblem.noBleedingThatDay));
      expect(await dump(), before);
    });

    test('decision 3B: los "No" explicitos del medio se respetan', () async {
      await marked(['2026-07-10']);
      await put('2026-07-11', explicit: true);

      final snapshot =
          await repo.closePeriod('2026-07-10', '2026-07-13', today: today);

      final no = await repo.getDay('2026-07-11');
      expect(no!.isPeriodDay, isFalse);
      expect(no.periodDayExplicit, isTrue);
      expect((await repo.getDay('2026-07-12'))!.isPeriodDay, isTrue);
      expect(snapshot.dates, ['2026-07-12', '2026-07-13']);
      final cycle = (await repo.getDerivedCycles()).single;
      expect(cycle.periodLengthDays, 4);
      expect(cycle.periodEnd, PeriodEndSource.declared);
    });

    test('animo, notas y sintomas de los dias completados y del fin quedan '
        'intactos', () async {
      await marked(['2026-07-10']);
      await put('2026-07-11',
          mood: Mood.irritable, notes: 'dolor', symptoms: {Symptom.dolorAbdominal});
      await put('2026-07-12',
          period: true,
          flow: FlowIntensity.abundante,
          mood: Mood.feliz,
          notes: 'fin',
          symptoms: {Symptom.cansancio, Symptom.antojos});

      await repo.closePeriod('2026-07-10', '2026-07-12', today: today);

      final completed = await repo.getDay('2026-07-11');
      expect(completed!.isPeriodDay, isTrue);
      expect(completed.mood, Mood.irritable);
      expect(completed.notes, 'dolor');
      expect(completed.flow, isNull);
      expect(await repo.getSymptomsForDay('2026-07-11'), {Symptom.dolorAbdominal});
      final end = await repo.getDay('2026-07-12');
      expect(end!.periodEnd, PeriodEndSource.declared);
      expect(end.flow, FlowIntensity.abundante);
      expect(end.mood, Mood.feliz);
      expect(end.notes, 'fin');
      expect(await repo.getSymptomsForDay('2026-07-12'),
          {Symptom.cansancio, Symptom.antojos});
    });

    test('un fin inferido en el dia elegido pasa a declared y Deshacer lo '
        'vuelve a inferred', () async {
      await marked(['2026-07-10']);
      await put('2026-07-11', period: true, end: PeriodEndSource.inferred);
      final before = await dump();

      final snapshot =
          await repo.closePeriod('2026-07-10', '2026-07-11', today: today);
      expect((await repo.getDay('2026-07-11'))!.periodEnd,
          PeriodEndSource.declared);

      await repo.restoreDaysSnapshot(snapshot);
      expect(await dump(), before);
    });

    test('atomicidad: si falla la escritura del fin, los dias completados '
        'tampoco quedan', () async {
      await marked(['2026-07-10', '2026-07-11']);
      final before = await dump();
      await failWritesOn(today);

      await expectLater(
          repo.closePeriod('2026-07-10', today, today: today),
          throwsA(isNot(isA<PeriodEndException>())));
      expect(await dump(), before);
    });

    test('periodStart que no es el primer dia de un periodo es un error de '
        'programacion (ArgumentError) y no cambia nada', () async {
      await marked(['2026-07-10', '2026-07-11']);
      final before = await dump();

      await expectLater(
          repo.closePeriod('2026-07-11', '2026-07-12', today: today),
          throwsArgumentError);
      await expectLater(
          repo.closePeriod('2026-07-09', '2026-07-12', today: today),
          throwsArgumentError);
      expect(await dump(), before);
    });
  });

  group('casos 7 y 8: quitar marca en un periodo cerrado (con foto)', () {
    Future<void> closed10to14() async {
      await marked(['2026-07-10', '2026-07-11', '2026-07-12', '2026-07-13']);
      await put('2026-07-14', period: true, end: PeriodEndSource.declared);
    }

    test('caso 7: quitar el 12 (interior) deja un solo periodo, cerrado en el '
        '14; Deshacer restaura el 12', () async {
      await closed10to14();
      final before = await dump();
      final snapshot = await repo.takeDaysSnapshot(['2026-07-12']);

      await repo.setPeriodDayExplicitly('2026-07-12', isPeriodDay: false);

      final cycle = (await repo.getDerivedCycles()).single;
      expect(cycle.periodLengthDays, 5);
      expect(cycle.periodEnd, PeriodEndSource.declared);
      expect(cycle.isClosed, isTrue);

      await repo.restoreDaysSnapshot(snapshot);
      expect(await dump(), before);
    });

    test('caso 8: quitar el 14 (ultimo) borra su fin por el CHECK y el '
        'periodo 10-13 queda cerrado por el "No"; Deshacer restaura el fin',
        () async {
      await closed10to14();
      final before = await dump();
      final snapshot = await repo.takeDaysSnapshot(['2026-07-14']);

      await repo.setPeriodDayExplicitly('2026-07-14', isPeriodDay: false);

      expect((await repo.getDay('2026-07-14'))!.periodEnd, isNull);
      final cycle = (await repo.getDerivedCycles()).single;
      expect(cycle.periodLengthDays, 4);
      expect(cycle.periodEnd, isNull);
      expect(cycle.periodConfirmedEnded, isTrue);
      expect(cycle.isClosed, isTrue);

      await repo.restoreDaysSnapshot(snapshot);
      expect(await dump(), before);
      expect((await repo.getDerivedCycles()).single.periodEnd,
          PeriodEndSource.declared);
    });
  });

  group('markPeriodDayWithSnapshot', () {
    test('marca un dia nuevo y la foto lo deshace', () async {
      final before = await dump();

      final result = await repo.markPeriodDayWithSnapshot('2026-07-10',
          closeAtEnd: false, today: today);

      expect(result.newlyMarked, 1);
      expect(result.closed, isFalse);
      expect(result.changedAnything, isTrue);
      expect((await repo.getDay('2026-07-10'))!.isPeriodDay, isTrue);

      await repo.restoreDaysSnapshot(result.snapshot);
      expect(await dump(), before);
    });

    test('un dia ya marcado no cambia nada (sin closeAtEnd)', () async {
      await put('2026-07-10', period: true, mood: Mood.feliz);
      final before = await dump();

      final result = await repo.markPeriodDayWithSnapshot('2026-07-10',
          closeAtEnd: false, today: today);

      expect(result.newlyMarked, 0);
      expect(result.closed, isFalse);
      expect(result.changedAnything, isFalse);
      expect(await dump(), before);
    });

    test('no pisa animo, notas, sintomas ni un "No" explicito previo',
        () async {
      await put('2026-07-10',
          explicit: true,
          mood: Mood.triste,
          notes: 'x',
          symptoms: {Symptom.dolorAbdominal});

      await repo.markPeriodDayWithSnapshot('2026-07-10',
          closeAtEnd: false, today: today);

      final day = await repo.getDay('2026-07-10');
      expect(day!.isPeriodDay, isTrue);
      expect(day.mood, Mood.triste);
      expect(day.notes, 'x');
      expect(await repo.getSymptomsForDay('2026-07-10'), {Symptom.dolorAbdominal});
    });

    test('caso 9 y R-4: marcar el dia siguiente a un fin declarado reabre sin '
        'borrar la marca; Deshacer lo vuelve a cerrar', () async {
      await marked(['2026-07-10', '2026-07-11', '2026-07-12', '2026-07-13']);
      await put('2026-07-14', period: true, end: PeriodEndSource.declared);
      final before = await dump();

      final result = await repo.markPeriodDayWithSnapshot(today,
          closeAtEnd: false, today: today);

      expect((await repo.getDay('2026-07-14'))!.periodEnd,
          PeriodEndSource.declared);
      var cycle = (await repo.getDerivedCycles()).single;
      expect(cycle.periodLengthDays, 6);
      expect(cycle.periodEnd, isNull);
      expect(cycle.isClosed, isFalse);

      await repo.restoreDaysSnapshot(result.snapshot);
      expect(await dump(), before);
      cycle = (await repo.getDerivedCycles()).single;
      expect(cycle.periodEnd, PeriodEndSource.declared);
      expect(cycle.isClosed, isTrue);
    });

    test('R-4: si se quita el dia que reabrio, el fin anterior vuelve a valer',
        () async {
      await marked(['2026-07-10', '2026-07-11', '2026-07-12', '2026-07-13']);
      await put('2026-07-14', period: true, end: PeriodEndSource.declared);
      await repo.markPeriodDayWithSnapshot(today,
          closeAtEnd: false, today: today);

      await repo.setPeriodDayExplicitly(today, isPeriodDay: false);

      final cycle = (await repo.getDerivedCycles()).single;
      expect(cycle.periodLengthDays, 5);
      expect(cycle.periodEnd, PeriodEndSource.declared);
      expect(cycle.isClosed, isTrue);
    });

    test('closeAtEnd sobre el ultimo dia del periodo guarda declared',
        () async {
      await marked(['2026-07-10', '2026-07-11']);

      final result = await repo.markPeriodDayWithSnapshot('2026-07-12',
          closeAtEnd: true, today: today);

      expect(result.closed, isTrue);
      expect((await repo.getDay('2026-07-12'))!.periodEnd,
          PeriodEndSource.declared);
      expect((await repo.getDerivedCycles()).single.isClosed, isTrue);
    });

    test('closeAtEnd sobre un dia ya marcado que es el ultimo: solo escribe '
        'el fin, y Deshacer lo quita', () async {
      await marked(['2026-07-10', '2026-07-11']);
      final before = await dump();

      final result = await repo.markPeriodDayWithSnapshot('2026-07-11',
          closeAtEnd: true, today: today);

      expect(result.newlyMarked, 0);
      expect(result.closed, isTrue);
      expect(result.changedAnything, isTrue);
      await repo.restoreDaysSnapshot(result.snapshot);
      expect(await dump(), before);
    });

    test('closeAtEnd se revalida: con dias marcados despues no guarda el fin '
        'y solo marca', () async {
      await marked(['2026-07-10', '2026-07-13']);

      final result = await repo.markPeriodDayWithSnapshot('2026-07-11',
          closeAtEnd: true, today: today);

      expect(result.newlyMarked, 1);
      expect(result.closed, isFalse);
      expect((await repo.getDay('2026-07-11'))!.periodEnd, isNull);
      expect((await repo.getDerivedCycles()).single.isClosed, isFalse);
    });

    test('closeAtEnd se revalida: un dia futuro no se cierra', () async {
      await marked(['2026-07-14']);

      final result = await repo.markPeriodDayWithSnapshot(today,
          closeAtEnd: true, today: '2026-07-14');

      expect(result.closed, isFalse);
      expect((await repo.getDay(today))!.periodEnd, isNull);
    });
  });

  group('markPeriodRangeWithSnapshot', () {
    test('marca el rango, cuenta solo los dias nuevos y Deshacer restaura '
        'todos los dias del rango', () async {
      await put('2026-07-11', period: true, mood: Mood.feliz);
      await put('2026-07-12', mood: Mood.triste, symptoms: {Symptom.dolorAbdominal});
      final before = await dump();

      final result = await repo.markPeriodRangeWithSnapshot(
          '2026-07-10', '2026-07-12',
          closeAtEnd: false, today: today);

      expect(result.newlyMarked, 2);
      expect(result.closed, isFalse);
      expect(result.snapshot.dates, ['2026-07-10', '2026-07-11', '2026-07-12']);
      final kept = await repo.getDay('2026-07-12');
      expect(kept!.isPeriodDay, isTrue);
      expect(kept.mood, Mood.triste);
      expect(await repo.getSymptomsForDay('2026-07-12'), {Symptom.dolorAbdominal});

      await repo.restoreDaysSnapshot(result.snapshot);
      expect(await dump(), before);
    });

    test('un rango con inicio posterior al final es ArgumentError', () async {
      await expectLater(
          repo.markPeriodRangeWithSnapshot('2026-07-12', '2026-07-10',
              closeAtEnd: false, today: today),
          throwsArgumentError);
    });

    test('atomicidad: si falla una escritura no se marca ningun dia',
        () async {
      final before = await dump();
      await failWritesOn('2026-07-12');

      await expectLater(
          repo.markPeriodRangeWithSnapshot('2026-07-10', '2026-07-12',
              closeAtEnd: true, today: today),
          throwsA(anything));
      expect(await dump(), before);
    });

    test('caso 19: rango 13-14 con hoy 15 y "Si, termino" (closeAtEnd) cierra '
        'en el 14; Deshacer deja todo como estaba', () async {
      final before = await dump();

      final result = await repo.markPeriodRangeWithSnapshot(
          '2026-07-13', '2026-07-14',
          closeAtEnd: true, today: today);

      expect(result.closed, isTrue);
      final cycle = (await repo.getDerivedCycles()).single;
      expect(cycle.startDate, '2026-07-13');
      expect(cycle.periodLengthDays, 2);
      expect(cycle.periodEnd, PeriodEndSource.declared);

      await repo.restoreDaysSnapshot(result.snapshot);
      expect(await dump(), before);
    });

    test('caso 19: "Todavia no" (sin closeAtEnd) solo marca y queda abierto',
        () async {
      final result = await repo.markPeriodRangeWithSnapshot(
          '2026-07-13', '2026-07-14',
          closeAtEnd: false, today: today);

      expect(result.closed, isFalse);
      expect((await repo.getDay('2026-07-14'))!.periodEnd, isNull);
      expect((await repo.getDerivedCycles()).single.isClosed, isFalse);
    });

    test('decision 5 en rangos: no se bloquea; con dias marcados despues '
        'marca pero no guarda el fin', () async {
      await marked(['2026-07-14']);

      final result = await repo.markPeriodRangeWithSnapshot(
          '2026-07-10', '2026-07-12',
          closeAtEnd: true, today: today);

      expect(result.newlyMarked, 3);
      expect(result.closed, isFalse);
      expect((await repo.getDay('2026-07-12'))!.periodEnd, isNull);
    });

    test('alargar un periodo cerrado con closeAtEnd mueve el fin: el viejo '
        'queda interior y el nuevo es declared', () async {
      await marked(['2026-07-10']);
      await put('2026-07-11', period: true, end: PeriodEndSource.inferred);

      final result = await repo.markPeriodRangeWithSnapshot(
          '2026-07-12', '2026-07-13',
          closeAtEnd: true, today: today);

      expect(result.closed, isTrue);
      expect((await repo.getDay('2026-07-11'))!.periodEnd,
          PeriodEndSource.inferred);
      final cycle = (await repo.getDerivedCycles()).single;
      expect(cycle.periodLengthDays, 4);
      expect(cycle.periodEnd, PeriodEndSource.declared);
    });
  });

  group('casos 16 a 18: bases v3 migradas', () {
    test('caso 16: periodo 1-5 jun cerrado como inferido que en realidad fue '
        '1-6: marcar el 6 lo reabre; cerrarlo en el 6 deja declared',
        () async {
      await marked(['2026-06-01', '2026-06-02', '2026-06-03', '2026-06-04']);
      await put('2026-06-05', period: true, end: PeriodEndSource.inferred);

      await repo.markPeriodDayWithSnapshot('2026-06-06',
          closeAtEnd: false, today: today);
      var cycle = (await repo.getDerivedCycles()).single;
      expect(cycle.periodLengthDays, 6);
      expect(cycle.isClosed, isFalse);
      expect((await repo.getDay('2026-06-05'))!.periodEnd,
          PeriodEndSource.inferred);

      final result = await repo.markPeriodDayWithSnapshot('2026-06-06',
          closeAtEnd: true, today: today);
      expect(result.closed, isTrue);
      cycle = (await repo.getDerivedCycles()).single;
      expect(cycle.periodEnd, PeriodEndSource.declared);
      expect(cycle.isClosed, isTrue);
    });

    test('caso 16 en un solo paso: rango que termina el 6 con closeAtEnd',
        () async {
      await marked(['2026-06-01', '2026-06-02', '2026-06-03', '2026-06-04']);
      await put('2026-06-05', period: true, end: PeriodEndSource.inferred);
      final before = await dump();

      final result = await repo.markPeriodRangeWithSnapshot(
          '2026-06-05', '2026-06-06',
          closeAtEnd: true, today: today);

      expect(result.newlyMarked, 1);
      expect(result.closed, isTrue);
      expect((await repo.getDerivedCycles()).single.periodEnd,
          PeriodEndSource.declared);
      await repo.restoreDaysSnapshot(result.snapshot);
      expect(await dump(), before);
    });

    test('caso 17: periodo inferido 1-5 jun que termino el 4: quitar el 5 lo '
        'deja cerrado en el 4 por el "No"', () async {
      await marked(['2026-06-01', '2026-06-02', '2026-06-03', '2026-06-04']);
      await put('2026-06-05', period: true, end: PeriodEndSource.inferred);

      await repo.setPeriodDayExplicitly('2026-06-05', isPeriodDay: false);

      final cycle = (await repo.getDerivedCycles()).single;
      expect(cycle.periodLengthDays, 4);
      expect(cycle.periodEnd, isNull);
      expect(cycle.periodConfirmedEnded, isTrue);
      expect(cycle.isClosed, isTrue);
    });

    test('caso 18: periodo abierto por un hueco de 2 dias; un rango sobre el '
        'hueco completa los dias y no cierra (hay dias despues)', () async {
      await marked(['2026-06-01', '2026-06-02', '2026-06-05']);

      final result = await repo.markPeriodRangeWithSnapshot(
          '2026-06-03', '2026-06-04',
          closeAtEnd: true, today: today);

      expect(result.newlyMarked, 2);
      expect(result.closed, isFalse);
      final cycle = (await repo.getDerivedCycles()).single;
      expect(cycle.periodLengthDays, 5);
      expect(cycle.isClosed, isFalse);
    });

    test('caso 18: un rango que cubre el hueco y el ultimo dia cierra en el '
        'ultimo', () async {
      await marked(['2026-06-01', '2026-06-02', '2026-06-05']);

      final result = await repo.markPeriodRangeWithSnapshot(
          '2026-06-03', '2026-06-05',
          closeAtEnd: true, today: today);

      expect(result.newlyMarked, 2);
      expect(result.closed, isTrue);
      final cycle = (await repo.getDerivedCycles()).single;
      expect(cycle.periodLengthDays, 5);
      expect(cycle.periodEnd, PeriodEndSource.declared);
    });
  });

  group('caso 11: Deshacer exacto de cada accion', () {
    /// Base con de todo: dos periodos, fines declared e inferred, "No"
    /// explicitos, animo, notas y sintomas.
    Future<void> richBase() async {
      await marked(['2026-06-01', '2026-06-02']);
      await put('2026-06-03', period: true, end: PeriodEndSource.inferred);
      await put('2026-06-04', explicit: true, mood: Mood.normal);
      await put('2026-07-10',
          period: true,
          flow: FlowIntensity.moderado,
          symptoms: {Symptom.dolorAbdominal});
      await put('2026-07-11', mood: Mood.feliz, notes: 'n');
      await put('2026-07-12', explicit: true);
    }

    final actions = <String, Future<DaysSnapshot> Function(CycleRepository)>{
      'closePeriod': (r) => r.closePeriod('2026-07-10', today, today: today),
      'marcar un dia': (r) async => (await r.markPeriodDayWithSnapshot(
              '2026-07-11',
              closeAtEnd: false,
              today: today))
          .snapshot,
      'marcar un dia con cierre': (r) async => (await r
              .markPeriodDayWithSnapshot('2026-07-13',
                  closeAtEnd: true, today: today))
          .snapshot,
      'marcar un rango con cierre': (r) async => (await r
              .markPeriodRangeWithSnapshot('2026-06-03', '2026-06-06',
                  closeAtEnd: true, today: today))
          .snapshot,
    };

    for (final entry in actions.entries) {
      test(entry.key, () async {
        await richBase();
        final before = await dump();

        final snapshot = await entry.value(repo);
        expect(await dump(), isNot(before));

        await repo.restoreDaysSnapshot(snapshot);
        expect(await dump(), before);
      });
    }
  });
}
