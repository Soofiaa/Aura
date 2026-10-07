import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/models/day_enums.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/screens/calendar_screen.dart';

/// Calendario, CP4b: "Termino este dia" (decision 11B). Datos inventados
/// en julio de 2026.
void main() {
  late AppDatabase db;
  late CycleRepository repo;

  const termino = 'Terminó este día';

  setUpAll(() async {
    await initializeDateFormatting();
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CycleRepository(db);
  });

  // La base se cierra dentro de cada test (en tearDown deja timers de
  // drift pendientes y el test no termina).
  void testCalendar(
          String description, Future<void> Function(WidgetTester) body) =>
      testWidgets(description, (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await body(tester);
        await db.close();
      });

  String jul(int day) => '2026-07-${day.toString().padLeft(2, '0')}';

  Future<void> mark(List<int> days) =>
      repo.markPeriodDays([for (final d in days) jul(d)]);

  Future<void> sayNo(int day) =>
      repo.setPeriodDayExplicitly(jul(day), isPeriodDay: false);

  Future<void> pumpCalendar(WidgetTester tester, int today) async {
    final date = DateTime.parse(jul(today));
    await tester.pumpWidget(MaterialApp(
      home: CalendarScreen(repository: repo, clock: () => date),
    ));
    await tester.pumpAndSettle();
  }

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

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> tapDay(WidgetTester tester, int day) async {
    await tester.tap(find.text('$day'));
    await tester.pumpAndSettle();
  }

  Future<List<String>> markedDays() async =>
      (await repo.getPeriodDayDates())..sort();

  group('caso 6: marcados 1 y 2, duracion 12, hoy el 10', () {
    testCalendar('cerrar el dia 5 completa 3, 4 y 5, declara el fin el 5 y '
        'Deshacer deja la base exactamente igual', (tester) async {
      await repo.setTypicalPeriodLength(12);
      await mark([1, 2]);
      final antes = await dump();
      await pumpCalendar(tester, 10);

      await tapDay(tester, 5);
      expect(find.text('Registrar día de menstruación'), findsOneWidget);
      await tapText(tester, termino);

      expect(find.text('Período terminado el 5 de julio.'), findsOneWidget);
      expect(await markedDays(), [jul(1), jul(2), jul(3), jul(4), jul(5)]);
      expect((await repo.getDay(jul(5)))!.periodEnd, PeriodEndSource.declared);
      final ciclo = (await repo.getDerivedCycles()).single;
      expect(ciclo.isClosed, isTrue);
      expect(ciclo.periodLengthDays, 5);

      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(await dump(), antes);
    });
  });

  testCalendar('decision 3B: respeta el "No" interior y no toca animo, '
      'notas ni sintomas', (tester) async {
    // Marcados 1 y 3, "No" el 2; el 4 sin sangrado pero con datos.
    // Duracion 12: el 5 es un estimado sin "Confirmar dias".
    await repo.setTypicalPeriodLength(12);
    await mark([1, 3]);
    await sayNo(2);
    await db.into(db.dailyLogs).insert(DailyLogsCompanion.insert(
          date: jul(4),
          mood: const Value(Mood.cansada),
          notes: const Value('nota inventada'),
        ));
    await db.into(db.dailyLogSymptoms).insert(DailyLogSymptomsCompanion.insert(
          logDate: jul(4),
          symptom: Symptom.dolorDeCabeza,
        ));
    await pumpCalendar(tester, 10);

    await tapDay(tester, 5);
    await tapText(tester, termino);

    final no = (await repo.getDay(jul(2)))!;
    expect(no.isPeriodDay, isFalse);
    expect(no.periodDayExplicit, isTrue);
    final cuatro = (await repo.getDay(jul(4)))!;
    expect(cuatro.isPeriodDay, isTrue);
    expect(cuatro.mood, Mood.cansada);
    expect(cuatro.notes, 'nota inventada');
    final sintomas = await db.select(db.dailyLogSymptoms).get();
    expect(sintomas.single.symptom, Symptom.dolorDeCabeza);
    expect((await repo.getDay(jul(5)))!.periodEnd, PeriodEndSource.declared);
  });

  testCalendar('decision 5A: con dias marcados despues bloquea con su '
      'mensaje y no cambia nada', (tester) async {
    await mark([1, 2, 4]);
    final antes = await dump();
    await pumpCalendar(tester, 10);

    await tapDay(tester, 3);
    await tapText(tester, termino);

    expect(
        find.text('Después de ese día hay 1 día marcado. Quítalo primero o '
            'elige otro día.'),
        findsOneWidget);
    expect(await dump(), antes);
  });

  testCalendar('un dia con "No" explicito muestra su mensaje y no cambia '
      'nada', (tester) async {
    await mark([1, 3]);
    await sayNo(2);
    final antes = await dump();
    await pumpCalendar(tester, 10);

    await tapDay(tester, 2);
    await tapText(tester, termino);

    expect(
        find.text('Ese día lo registraste sin sangrado, así que no puede ser '
            'el último día de tu período. Elige otro día.'),
        findsOneWidget);
    expect(await dump(), antes);
  });

  group('decision 14: periodo de 1 dia', () {
    testCalendar('Cancelar no cambia nada', (tester) async {
      await mark([1]);
      final antes = await dump();
      await pumpCalendar(tester, 5);

      await tapDay(tester, 1);
      expect(find.text('Quitar marca'), findsOneWidget);
      await tapText(tester, termino);
      expect(find.text('¿Tu período duró solo 1 día?'), findsOneWidget);
      await tapText(tester, 'Cancelar');
      expect(await dump(), antes);
    });

    testCalendar('confirmar cierra el periodo de 1 dia; Deshacer exacto',
        (tester) async {
      await mark([1]);
      final antes = await dump();
      await pumpCalendar(tester, 5);

      await tapDay(tester, 1);
      await tapText(tester, termino);
      await tapText(tester, 'Sí, duró 1 día');

      expect((await repo.getDay(jul(1)))!.periodEnd, PeriodEndSource.declared);
      expect(find.text('Período terminado el 1 de julio.'), findsOneWidget);
      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(await dump(), antes);
    });

    testCalendar('sin pregunta si el periodo tiene mas dias', (tester) async {
      await mark([1, 2]);
      await pumpCalendar(tester, 5);
      await tapDay(tester, 2);
      await tapText(tester, termino);
      expect(find.text('¿Tu período duró solo 1 día?'), findsNothing);
      expect((await repo.getDay(jul(2)))!.periodEnd, PeriodEndSource.declared);
    });
  });

  group('cuando no se ofrece', () {
    testCalendar('a mas de 7 dias del ultimo marcado', (tester) async {
      await mark([1, 2]);
      await pumpCalendar(tester, 15);
      await tapDay(tester, 9);
      expect(find.text(termino), findsOneWidget);
      await tapDay(tester, 10);
      expect(find.text(termino), findsNothing);
    });

    testCalendar('periodo cerrado', (tester) async {
      await mark([1, 2, 3]);
      await repo.closePeriod(jul(1), jul(3), today: jul(10));
      await pumpCalendar(tester, 10);
      await tapDay(tester, 3);
      expect(find.text(termino), findsNothing);
      await tapDay(tester, 5);
      expect(find.text(termino), findsNothing);
    });

    testCalendar('dia anterior al inicio y dia marcado que no es el ultimo',
        (tester) async {
      await mark([5, 6, 7]);
      await pumpCalendar(tester, 10);
      await tapDay(tester, 4);
      expect(find.text(termino), findsNothing);
      await tapDay(tester, 6);
      expect(find.text(termino), findsNothing);
      await tapDay(tester, 7);
      expect(find.text(termino), findsOneWidget);
    });
  });

  group('convivencia con "Confirmar dias" (marcados 12-14, duracion 5)', () {
    testCalendar('estimado anterior al ultimo: los dos botones', (tester) async {
      await mark([12, 13, 14]);
      await pumpCalendar(tester, 16);
      await tapDay(tester, 15);
      expect(find.text('Confirmar días'), findsOneWidget);
      expect(find.text(termino), findsOneWidget);

      await tapText(tester, termino);
      expect((await repo.getDay(jul(15)))!.periodEnd, PeriodEndSource.declared);
      expect(await repo.getDay(jul(16)), isNull);
    });

    testCalendar('el ultimo estimado: solo "Confirmar dias"', (tester) async {
      await mark([12, 13, 14]);
      await pumpCalendar(tester, 16);
      await tapDay(tester, 16);
      expect(find.text('Confirmar días'), findsOneWidget);
      expect(find.text(termino), findsNothing);
    });

    testCalendar('estimado sin Confirmar (ultimo estimado futuro): Registrar '
        'y "Termino este dia"', (tester) async {
      await mark([12, 13, 14]);
      await pumpCalendar(tester, 15);
      await tapDay(tester, 15);
      expect(find.text('Confirmar días'), findsNothing);
      expect(find.text('Registrar día de menstruación'), findsOneWidget);
      expect(find.text(termino), findsOneWidget);
    });
  });

  testCalendar('accesibilidad: "Termino este dia" de al menos 48 dp',
      (tester) async {
    await mark([1, 2]);
    await pumpCalendar(tester, 10);
    await tapDay(tester, 5);
    final size = tester.getSize(find.ancestor(
        of: find.text(termino), matching: find.bySubtype<ButtonStyleButton>()));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.width, greaterThanOrEqualTo(48));
  });
}
