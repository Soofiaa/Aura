import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/models/day_enums.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/domain/cycle_deriver.dart';
import 'package:aura/screens/calendar_screen.dart';

/// Calendario, CP4c: "Elegir varios dias" (U-1) con R-1 y R-4. Datos
/// inventados en julio de 2026; "hoy" es el 20 salvo que se diga otra
/// cosa.
void main() {
  late AppDatabase db;
  late CycleRepository repo;

  const elegir = 'Elegir varios días';
  const marcar = 'Marcar período';

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
        final semantics = tester.ensureSemantics();
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await body(tester);
        semantics.dispose();
        await db.close();
      });

  String jul(int day) => '2026-07-${day.toString().padLeft(2, '0')}';

  Future<void> mark(List<int> days) =>
      repo.markPeriodDays([for (final d in days) jul(d)]);

  Future<void> pumpCalendar(WidgetTester tester, [int today = 20]) async {
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

  // El boton de modo rango dice "Cancelar" (visible); los dialogos
  // tambien tienen un "Cancelar": este toca el del dialogo abierto.
  Future<void> tapEnDialogo(WidgetTester tester, String text) async {
    await tester.tap(find.descendant(
        of: find.byType(Dialog), matching: find.text(text)));
    await tester.pumpAndSettle();
  }

  Future<void> tapDay(WidgetTester tester, int day) async {
    await tester.tap(find.text('$day'));
    await tester.pumpAndSettle();
  }

  Future<void> elegirRango(WidgetTester tester, int desde, int hasta) async {
    await tapText(tester, elegir);
    await tapDay(tester, desde);
    await tapDay(tester, hasta);
  }

  Future<void> deshacer(WidgetTester tester) async {
    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();
  }

  Future<List<String>> markedDays() async =>
      (await repo.getPeriodDayDates())..sort();

  Finder etiqueta(String label) => find.bySemanticsLabel(label);

  /// La marca con [label] cubre el centro del numero [day].
  bool cubre(WidgetTester tester, String label, int day) {
    final centro = tester.getRect(find.text('$day')).center;
    return etiqueta(label).evaluate().any(
        (e) => tester.getRect(find.byWidget(e.widget)).contains(centro));
  }

  group('seleccion y pintado (U-1)', () {
    testCalendar('un toque pinta solo el primer dia; el segundo pinta el '
        'primero, los del medio y el ultimo, y el panel lo resume',
        (tester) async {
      await pumpCalendar(tester);
      await tapText(tester, elegir);
      expect(find.text('Toca el primer día.'), findsOneWidget);

      await tapDay(tester, 5);
      expect(etiqueta('inicio del rango'), findsOneWidget);
      expect(cubre(tester, 'inicio del rango', 5), isTrue);
      expect(etiqueta('dentro del rango'), findsNothing);
      expect(etiqueta('fin del rango'), findsNothing);
      expect(find.text('5 jul · 1 día'), findsOneWidget);
      expect(find.text('Ahora toca el último día.'), findsOneWidget);

      await tapDay(tester, 8);
      expect(cubre(tester, 'inicio del rango', 5), isTrue);
      expect(cubre(tester, 'dentro del rango', 6), isTrue);
      expect(cubre(tester, 'dentro del rango', 7), isTrue);
      expect(cubre(tester, 'fin del rango', 8), isTrue);
      expect(etiqueta('dentro del rango'), findsNWidgets(2));
      expect(find.text('5 jul → 8 jul · 4 días'), findsOneWidget);
      expect(find.text('Toca otro día para cambiar el final.'),
          findsOneWidget);
    });

    testCalendar('tocar el inicio de un rango completo deja un rango de 1 '
        'dia; tocar antes del inicio lo mueve', (tester) async {
      await pumpCalendar(tester);
      await elegirRango(tester, 5, 8);
      await tapDay(tester, 5);
      expect(etiqueta('inicio y fin del rango'), findsOneWidget);
      expect(find.text('5 jul → 5 jul · 1 día'), findsOneWidget);

      await tapDay(tester, 3);
      expect(find.text('3 jul → 5 jul · 3 días'), findsOneWidget);
    });

    testCalendar('el rango tapa el punteado de un estimado; fuera del rango '
        'sigue punteado', (tester) async {
      await mark([12, 13, 14]);
      await pumpCalendar(tester, 15);
      expect(etiqueta('estimado'), findsNWidgets(2)); // 15 y 16
      await elegirRango(tester, 13, 15);
      expect(cubre(tester, 'fin del rango', 15), isTrue);
      expect(etiqueta('estimado'), findsOneWidget);
    });

    testCalendar('"Cancelar seleccion" vacia el rango, sale del modo y no '
        'cambia nada', (tester) async {
      await mark([1]);
      final antes = await dump();
      await pumpCalendar(tester);
      await elegirRango(tester, 5, 8);
      await tapText(tester, 'Cancelar');

      expect(etiqueta('inicio del rango'), findsNothing);
      expect(find.text(marcar), findsNothing);
      expect(find.text(elegir), findsOneWidget);
      expect(await dump(), antes);
    });
  });

  group('rango largo', () {
    testCalendar('mas de 10 dias: aviso en el panel y confirmacion extra; '
        'Cancelar no cambia nada y Continuar marca', (tester) async {
      await pumpCalendar(tester);
      await elegirRango(tester, 1, 12);
      expect(find.text('Son más de 10 días: revisa que sea correcto.'),
          findsOneWidget);

      await tapText(tester, marcar);
      expect(find.text('Confirmar rango largo'), findsOneWidget);
      await tapEnDialogo(tester, 'Cancelar');
      expect(await markedDays(), isEmpty);

      await tapText(tester, marcar);
      await tapText(tester, 'Continuar');
      expect(await markedDays(), hasLength(12));
    });

    testCalendar('10 dias no piden confirmacion', (tester) async {
      await pumpCalendar(tester);
      await elegirRango(tester, 1, 10);
      expect(find.textContaining('Son más de'), findsNothing);
      await tapText(tester, marcar);
      expect(find.text('Confirmar rango largo'), findsNothing);
      expect(await markedDays(), hasLength(10));
    });
  });

  group('R-1', () {
    testCalendar('termina hace 2 dias o mas: marca y cierra; aviso con '
        'Deshacer exacto', (tester) async {
      final antes = await dump();
      await pumpCalendar(tester);
      await elegirRango(tester, 5, 8);
      await tapText(tester, marcar);

      expect(find.text('¿Ya terminó tu período?'), findsNothing);
      expect(find.text('4 días registrados como menstruación.'),
          findsOneWidget);
      expect(await markedDays(), [jul(5), jul(6), jul(7), jul(8)]);
      expect((await repo.getDay(jul(8)))!.periodEnd, PeriodEndSource.declared);

      await deshacer(tester);
      expect(await dump(), antes);
    });

    testCalendar('termina ayer: pregunta; "Sí, terminó" cierra',
        (tester) async {
      await pumpCalendar(tester);
      await elegirRango(tester, 17, 19);
      await tapText(tester, marcar);
      expect(find.text('¿Ya terminó tu período?'), findsOneWidget);
      await tapText(tester, 'Sí, terminó');
      expect((await repo.getDay(jul(19)))!.periodEnd, PeriodEndSource.declared);
    });

    testCalendar('termina hoy: pregunta; "Todavía no" solo marca',
        (tester) async {
      await pumpCalendar(tester);
      await elegirRango(tester, 18, 20);
      await tapText(tester, marcar);
      await tapText(tester, 'Todavía no');
      expect(await markedDays(), [jul(18), jul(19), jul(20)]);
      expect((await repo.getDay(jul(20)))!.periodEnd, isNull);
      expect((await repo.getDerivedCycles()).single.isClosed, isFalse);
    });

    testCalendar('el fin del rango no es el ultimo dia del periodo: solo '
        'marca, sin preguntar ni bloquear', (tester) async {
      await mark([10, 11, 12]);
      await pumpCalendar(tester);
      await elegirRango(tester, 7, 8);
      await tapText(tester, marcar);

      expect(find.text('¿Ya terminó tu período?'), findsNothing);
      expect(find.text('2 días registrados como menstruación.'),
          findsOneWidget);
      expect((await repo.getDay(jul(8)))!.periodEnd, isNull);
      final ciclo = (await repo.getDerivedCycles()).single;
      expect(ciclo.startDate, jul(7));
      expect(ciclo.isClosed, isFalse);
    });

    testCalendar('decision 14: un periodo de 1 dia pide confirmacion; '
        'Cancelar no cambia nada', (tester) async {
      final antes = await dump();
      await pumpCalendar(tester);
      await elegirRango(tester, 10, 10);
      await tapText(tester, marcar);
      expect(find.text('¿Tu período duró solo 1 día?'), findsOneWidget);
      await tapEnDialogo(tester, 'Cancelar');
      expect(await dump(), antes);
    });

    testCalendar('decision 14: confirmar marca y cierra el periodo de 1 dia',
        (tester) async {
      await pumpCalendar(tester);
      await elegirRango(tester, 10, 10);
      await tapText(tester, marcar);
      await tapText(tester, 'Sí, duró 1 día');
      expect(find.text('1 día registrado como menstruación.'), findsOneWidget);
      expect((await repo.getDay(jul(10)))!.periodEnd, PeriodEndSource.declared);
    });
  });

  group('R-4: rango junto a un periodo cerrado', () {
    testCalendar('hace 2 dias o mas: lo extiende y lo cierra en el nuevo '
        'ultimo dia; el fin viejo queda guardado e ignorado; Deshacer exacto',
        (tester) async {
      await mark([1, 2, 3, 4]);
      await repo.closePeriod(jul(1), jul(4), today: jul(20));
      final antes = await dump();
      await pumpCalendar(tester);
      await elegirRango(tester, 5, 6);
      await tapText(tester, marcar);

      expect((await repo.getDay(jul(4)))!.periodEnd, PeriodEndSource.declared);
      expect((await repo.getDay(jul(6)))!.periodEnd, PeriodEndSource.declared);
      final ciclo = (await repo.getDerivedCycles()).single;
      expect(ciclo.periodLengthDays, 6);
      expect(ciclo.isClosed, isTrue);

      await deshacer(tester);
      expect(await dump(), antes);
    });

    testCalendar('hoy o ayer con "Todavía no": lo reabre (fin viejo '
        'ignorado)', (tester) async {
      await mark([15, 16, 17]);
      await repo.closePeriod(jul(15), jul(17), today: jul(20));
      await pumpCalendar(tester);
      await elegirRango(tester, 18, 19);
      await tapText(tester, marcar);
      await tapText(tester, 'Todavía no');

      expect((await repo.getDay(jul(17)))!.periodEnd, PeriodEndSource.declared);
      final ciclo = (await repo.getDerivedCycles()).single;
      expect(ciclo.periodLengthDays, 5);
      expect(ciclo.periodEnd, isNull);
      expect(ciclo.isClosed, isFalse);
    });
  });

  testCalendar('un "No" explicito dentro del rango se marca (la seleccion '
      'manda); animo, notas y sintomas intactos; Deshacer exacto',
      (tester) async {
    await db.into(db.dailyLogs).insert(DailyLogsCompanion.insert(
          date: jul(6),
          isPeriodDay: const Value(false),
          periodDayExplicit: const Value(true),
          mood: const Value(Mood.cansada),
          notes: const Value('nota inventada'),
        ));
    await db.into(db.dailyLogSymptoms).insert(DailyLogSymptomsCompanion.insert(
          logDate: jul(6),
          symptom: Symptom.dolorDeCabeza,
        ));
    final antes = await dump();
    await pumpCalendar(tester);
    await elegirRango(tester, 5, 7);
    await tapText(tester, marcar);

    final seis = (await repo.getDay(jul(6)))!;
    expect(seis.isPeriodDay, isTrue);
    expect(seis.mood, Mood.cansada);
    expect(seis.notes, 'nota inventada');
    expect((await db.select(db.dailyLogSymptoms).get()).single.symptom,
        Symptom.dolorDeCabeza);
    expect(find.text('3 días registrados como menstruación.'), findsOneWidget);

    await deshacer(tester);
    expect(await dump(), antes);
  });

  group('rango que se solapa con dias ya marcados', () {
    test('groupPeriodRuns no repite dias aunque la lista los repita', () {
      final runs = groupPeriodRuns(
          [jul(5), jul(6), jul(7), jul(6), jul(7), jul(8), jul(9)]);
      expect(runs, [
        [jul(5), jul(6), jul(7), jul(8), jul(9)]
      ]);
    });

    testCalendar('a) los tramos quedan bien y sin repetidas; no pregunta por '
        '1 dia', (tester) async {
      await mark([5, 6, 7]);
      await pumpCalendar(tester);
      await elegirRango(tester, 6, 9);
      await tapText(tester, marcar);

      expect(find.text('¿Tu período duró solo 1 día?'), findsNothing);
      expect(find.text('2 días registrados como menstruación.'),
          findsOneWidget);
      expect(await markedDays(), [jul(5), jul(6), jul(7), jul(8), jul(9)]);
      final ciclo = (await repo.getDerivedCycles()).single;
      expect(ciclo.startDate, jul(5));
      expect(ciclo.periodLengthDays, 5);
      expect(ciclo.periodEnd, PeriodEndSource.declared);
    });

    testCalendar('b) rango de 1 dia sobre un dia ya marcado y aislado: '
        'pregunta por 1 dia igual que sin solape', (tester) async {
      await mark([10]);
      final antes = await dump();
      await pumpCalendar(tester);
      await elegirRango(tester, 10, 10);
      await tapText(tester, marcar);
      expect(find.text('¿Tu período duró solo 1 día?'), findsOneWidget);
      await tapEnDialogo(tester, 'Cancelar');
      expect(await dump(), antes);
      // Cancelar deja la seleccion como estaba.
      expect(etiqueta('inicio y fin del rango'), findsOneWidget);

      await tapText(tester, marcar);
      await tapText(tester, 'Sí, duró 1 día');
      expect((await repo.getDay(jul(10)))!.periodEnd, PeriodEndSource.declared);
      expect(find.text('Período terminado el 10 de julio.'), findsOneWidget);
    });

    testCalendar('b) rango de 1 dia sobre el ultimo dia de un periodo mas '
        'largo: no pregunta por 1 dia', (tester) async {
      await mark([8, 9, 10]);
      await pumpCalendar(tester);
      await elegirRango(tester, 10, 10);
      await tapText(tester, marcar);
      expect(find.text('¿Tu período duró solo 1 día?'), findsNothing);
      expect((await repo.getDay(jul(10)))!.periodEnd, PeriodEndSource.declared);
    });
  });

  testCalendar('accesibilidad: botones de al menos 48 dp', (tester) async {
    await pumpCalendar(tester);
    Size size(String text) => tester.getSize(find.ancestor(
        of: find.text(text), matching: find.bySubtype<ButtonStyleButton>()));

    expect(size(elegir).height, greaterThanOrEqualTo(48));
    expect(size('Me llegó hoy').height, greaterThanOrEqualTo(48));
    await elegirRango(tester, 5, 6);
    expect(size('Cancelar').height, greaterThanOrEqualTo(48));
    expect(size(marcar).height, greaterThanOrEqualTo(48));
  });

  testCalendar(
      'modo rango: se ve "Cancelar" y el lector dice "Cancelar selección" en '
      'un solo nodo', (tester) async {
    await pumpCalendar(tester);
    await tapText(tester, elegir);

    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Cancelar selección'), findsNothing);
    final boton = find.ancestor(
        of: find.text('Cancelar'), matching: find.byType(OutlinedButton));
    expect(
      tester.getSemantics(boton),
      matchesSemantics(
        label: 'Cancelar selección',
        isButton: true,
        hasTapAction: true,
        hasFocusAction: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
      ),
    );
    // Sin un segundo nodo que repita la lectura.
    expect(find.bySemanticsLabel('Cancelar'), findsNothing);
    expect(find.bySemanticsLabel('Cancelar selección'), findsOneWidget);
  });

  for (final escala in [1.0, 1.3]) {
    testWidgets('360 x 640, texto $escala: los dos botones miden lo mismo',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = escala;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpCalendar(tester);
      double alto(String texto) => tester
          .getSize(find.ancestor(
              of: find.text(texto),
              matching: find.bySubtype<ButtonStyleButton>()))
          .height;

      expect(alto(elegir), alto('Me llegó hoy'));
      await tester.tap(find.text(elegir));
      await tester.pumpAndSettle();
      expect(alto('Cancelar'), alto('Me llegó hoy'));
      expect(tester.takeException(), isNull);
      await db.close();
    });
  }
}
