import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/models/day_enums.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/screens/calendar_screen.dart';
import 'package:aura/utils/colors.dart';
import 'package:aura/utils/day_key.dart';

/// Calendario, CP4a: dias estimados (E-1), leyenda, "Me llego hoy",
/// "Confirmar dias" y Deshacer al tocar un dia. Datos inventados en
/// julio de 2026; sin historia cerrada la duracion estimada es el ajuste
/// (5 por defecto).
void main() {
  late AppDatabase db;
  late CycleRepository repo;

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

  Future<void> seedRange(String start, int length) async {
    await repo.markPeriodDays(
        [for (var i = 0; i < length; i++) DayKey.addDays(start, i)]);
  }

  Future<void> pumpCalendar(WidgetTester tester, String today) async {
    final date = DateTime.parse(today);
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

  Finder estimado() => find.bySemanticsLabel('estimado');

  group('dias estimados', () {
    testCalendar('solo en el periodo abierto mas reciente, con la etiqueta '
        '"estimado" (hoy y futuros incluidos)', (tester) async {
      // Periodo viejo abierto (1-2 jul) y periodo actual abierto (12-14).
      await seedRange('2026-07-01', 2);
      await seedRange('2026-07-12', 3);
      await pumpCalendar(tester, '2026-07-15');

      // Duracion 5 desde el 12: estimados el 15 (hoy) y el 16 (futuro).
      expect(estimado(), findsNWidgets(2));
      final dia15 = tester.getRect(find.text('15'));
      final dia16 = tester.getRect(find.text('16'));
      final marcas = [
        for (final e in estimado().evaluate())
          tester.getRect(find.byWidget(e.widget)),
      ];
      expect(marcas.where((r) => r.contains(dia15.center)), hasLength(1));
      expect(marcas.where((r) => r.contains(dia16.center)), hasLength(1));
    });

    testCalendar('sin puntos si el periodo actual esta cerrado',
        (tester) async {
      await seedRange('2026-07-12', 3);
      await repo.closePeriod('2026-07-12', '2026-07-14', today: '2026-07-15');
      await pumpCalendar(tester, '2026-07-15');
      expect(estimado(), findsNothing);
    });

    testCalendar('sin puntos si no hay datos', (tester) async {
      await pumpCalendar(tester, '2026-07-15');
      expect(estimado(), findsNothing);
    });

    testCalendar('usan la duracion estimada unica: con periodos cerrados de '
        '3 dias y ajuste 7, estima hasta el dia 3', (tester) async {
      await seedRange('2026-05-01', 3);
      await repo.closePeriod('2026-05-01', '2026-05-03', today: '2026-07-12');
      await seedRange('2026-06-01', 3);
      await repo.closePeriod('2026-06-01', '2026-06-03', today: '2026-07-12');
      await repo.setTypicalPeriodLength(7);
      await repo.markPeriodDay('2026-07-12');
      await pumpCalendar(tester, '2026-07-12');
      // 13 y 14 de julio.
      expect(estimado(), findsNWidgets(2));
    });

    testCalendar('leyenda con dias estimados: registrado y estimado, nada '
        'de fertilidad ni ovulacion', (tester) async {
      await seedRange('2026-07-12', 3);
      await pumpCalendar(tester, '2026-07-15');
      expect(estimado(), findsNWidgets(2));
      expect(find.text('Período registrado'), findsOneWidget);
      expect(find.text('Estimado sin confirmar'), findsOneWidget);
      expect(find.textContaining('értil'), findsNothing);
      expect(find.textContaining('vulaci'), findsNothing);
    });

    testCalendar('leyenda sin dias estimados (periodo cerrado): sin '
        '"Estimado sin confirmar"', (tester) async {
      await seedRange('2026-07-12', 3);
      await repo.closePeriod('2026-07-12', '2026-07-14', today: '2026-07-15');
      await pumpCalendar(tester, '2026-07-15');
      expect(estimado(), findsNothing);
      expect(find.text('Período registrado'), findsOneWidget);
      expect(find.text('Estimado sin confirmar'), findsNothing);
    });

    testCalendar('leyenda sin datos: solo "Período registrado"',
        (tester) async {
      await pumpCalendar(tester, '2026-07-15');
      expect(find.text('Período registrado'), findsOneWidget);
      expect(find.text('Estimado sin confirmar'), findsNothing);
      expect(find.textContaining('értil'), findsNothing);
      expect(find.textContaining('vulaci'), findsNothing);
    });

    testCalendar('la leyenda sigue a los estimados: al confirmar los dias, '
        'desaparece', (tester) async {
      // Periodo abierto del 12 con duracion 5: estimados 15 y 16; hoy 16,
      // asi que ya se pueden confirmar.
      await seedRange('2026-07-12', 3);
      await pumpCalendar(tester, '2026-07-16');
      expect(find.text('Estimado sin confirmar'), findsOneWidget);

      await repo.closePeriod('2026-07-12', '2026-07-16', today: '2026-07-16');
      await tester.pumpAndSettle();
      expect(estimado(), findsNothing);
      expect(find.text('Estimado sin confirmar'), findsNothing);
    });
  });

  group('Confirmar dias', () {
    testCalendar('oculto si el ultimo estimado es futuro: el estimado de hoy '
        'se comporta como un dia sin marcar', (tester) async {
      await seedRange('2026-07-12', 3);
      await pumpCalendar(tester, '2026-07-15');
      await tapDay(tester, 15);
      expect(find.text('Confirmar días'), findsNothing);
      expect(find.text('Marcar período'), findsOneWidget);
    });

    testCalendar('visible cuando el ultimo estimado es hoy; confirma, cierra '
        'el periodo y Deshacer deja la base exactamente igual',
        (tester) async {
      await seedRange('2026-07-12', 3);
      final antes = await dump();
      await pumpCalendar(tester, '2026-07-16');

      await tapDay(tester, 15);
      await tapText(tester, 'Confirmar días');
      expect(find.text('¿Confirmar los días estimados?'), findsOneWidget);
      expect(
          find.text('Se marcarán 2 días más como período y quedará '
              'terminado el 16 de julio.'),
          findsOneWidget);
      await tapText(tester, 'Confirmar');

      expect(
          find.text('Período confirmado: 5 días en total.'), findsOneWidget);
      expect((await repo.getDay('2026-07-15'))!.isPeriodDay, isTrue);
      final fin = (await repo.getDay('2026-07-16'))!;
      expect(fin.isPeriodDay, isTrue);
      expect(fin.periodEnd, PeriodEndSource.declared);
      expect(estimado(), findsNothing);

      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(await dump(), antes);
      expect(estimado(), findsNWidgets(2));
    });

    testCalendar('visible desde un estimado pasado cuando el ultimo ya paso; '
        'completa huecos y respeta el "No" explicito', (tester) async {
      // Marcados 10 y 12; "No" el 11; estimados 13 y 14; hoy 17.
      await repo.markPeriodDays(['2026-07-10', '2026-07-12']);
      await repo.setPeriodDayExplicitly('2026-07-11', isPeriodDay: false);
      await pumpCalendar(tester, '2026-07-17');

      await tapDay(tester, 13);
      await tapText(tester, 'Confirmar días');
      expect(
          find.text('Se marcarán 2 días más como período y quedará '
              'terminado el 14 de julio.'),
          findsOneWidget);
      await tapText(tester, 'Confirmar');

      expect((await repo.getDay('2026-07-11'))!.isPeriodDay, isFalse);
      expect((await repo.getDay('2026-07-14'))!.periodEnd,
          PeriodEndSource.declared);
    });

    testCalendar('textos en singular: "1 dia mas"', (tester) async {
      await seedRange('2026-07-12', 4);
      await pumpCalendar(tester, '2026-07-16');
      await tapDay(tester, 16);
      await tapText(tester, 'Confirmar días');
      expect(
          find.text('Se marcarán 1 día más como período y quedará '
              'terminado el 16 de julio.'),
          findsOneWidget);
      await tapText(tester, 'Confirmar');
      expect(
          find.text('Período confirmado: 5 días en total.'), findsOneWidget);
    });

    testCalendar('Cancelar no cambia nada', (tester) async {
      await seedRange('2026-07-12', 3);
      final antes = await dump();
      await pumpCalendar(tester, '2026-07-16');
      await tapDay(tester, 16);
      await tapText(tester, 'Confirmar días');
      await tapText(tester, 'Cancelar');
      expect(await dump(), antes);
      expect(estimado(), findsNWidgets(2));
    });
  });

  group('caso 6: pocos dias marcados y duracion estimada larga', () {
    // Marcados 1 y 2 de julio, duracion estimada 12 (ajuste, sin
    // periodos cerrados): estimados del 3 al 12.
    Future<void> seed() async {
      await repo.setTypicalPeriodLength(12);
      await seedRange('2026-07-01', 2);
    }

    testCalendar('el dia 3: 10 estimados (no se limitan a 7), sin Confirmar',
        (tester) async {
      await seed();
      await pumpCalendar(tester, '2026-07-03');
      expect(estimado(), findsNWidgets(10));
      await tapDay(tester, 3);
      expect(find.text('Confirmar días'), findsNothing);
      expect(find.text('Marcar período'), findsOneWidget);
    });

    testCalendar('el dia 9: siguen los 10 (7 ya pasados), todavia sin '
        'Confirmar porque el ultimo (12) es futuro', (tester) async {
      await seed();
      await pumpCalendar(tester, '2026-07-09');
      expect(estimado(), findsNWidgets(10));
      await tapDay(tester, 5);
      expect(find.text('Confirmar días'), findsNothing);
    });

    testCalendar('el dia 10: el ultimo marcado quedo a mas de 7 dias, ya no '
        'hay periodo actual y los estimados desaparecen sin poder '
        'confirmarse', (tester) async {
      await seed();
      await pumpCalendar(tester, '2026-07-10');
      expect(estimado(), findsNothing);
      await tapDay(tester, 5);
      expect(find.text('Confirmar días'), findsNothing);
    });
  });

  group('tocar un dia suelto', () {
    testCalendar('Registrar dia: aviso con Deshacer que deja la base '
        'exactamente igual', (tester) async {
      await repo.markPeriodDay('2026-06-01');
      final antes = await dump();
      await pumpCalendar(tester, '2026-07-15');
      await tapDay(tester, 5);
      await tapText(tester, 'Marcar período');

      expect(find.text('Día registrado como menstruación.'), findsOneWidget);
      expect((await repo.getDay('2026-07-05'))!.isPeriodDay, isTrue);
      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(await dump(), antes);
    });

    testCalendar('Quitar marca: Deshacer restaura la fila completa (con '
        'animo y notas)', (tester) async {
      await db.into(db.dailyLogs).insert(DailyLogsCompanion.insert(
            date: '2026-07-05',
            isPeriodDay: const Value(true),
            mood: const Value(Mood.cansada),
            notes: const Value('nota inventada'),
          ));
      final antes = await dump();
      await pumpCalendar(tester, '2026-07-15');
      await tapDay(tester, 5);
      await tapText(tester, 'Quitar marca');
      expect((await repo.getDay('2026-07-05'))!.isPeriodDay, isFalse);

      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(await dump(), antes);
    });
  });

  group('periodos cerrados', () {
    testCalendar('a) Quitar marca del ultimo dia de un periodo cerrado: sin '
        'error, el periodo queda cerrado por el "No" en el dia anterior y '
        'Deshacer deja la base exactamente igual', (tester) async {
      await seedRange('2026-07-01', 4);
      await repo.closePeriod('2026-07-01', '2026-07-04', today: '2026-07-15');
      final antes = await dump();
      await pumpCalendar(tester, '2026-07-15');

      await tapDay(tester, 4);
      await tapText(tester, 'Quitar marca');

      final fila = (await repo.getDay('2026-07-04'))!;
      expect(fila.isPeriodDay, isFalse);
      expect(fila.periodDayExplicit, isTrue);
      expect(fila.periodEnd, isNull);
      final ciclo = (await repo.getDerivedCycles()).single;
      expect(ciclo.periodLengthDays, 3);
      expect(ciclo.periodEnd, isNull);
      expect(ciclo.periodConfirmedEnded, isTrue);
      expect(ciclo.isClosed, isTrue);

      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(await dump(), antes);
    });

    testCalendar('b) Registrar el dia siguiente a un periodo cerrado lo '
        'extiende y lo reabre; el period_end viejo queda guardado pero se '
        'ignora (R-4); Deshacer exacto', (tester) async {
      await seedRange('2026-07-01', 4);
      await repo.closePeriod('2026-07-01', '2026-07-04', today: '2026-07-15');
      final antes = await dump();
      await pumpCalendar(tester, '2026-07-15');

      await tapDay(tester, 5);
      await tapText(tester, 'Marcar período');

      expect((await repo.getDay('2026-07-04'))!.periodEnd,
          PeriodEndSource.declared);
      final ciclo = (await repo.getDerivedCycles()).single;
      expect(ciclo.periodLengthDays, 5);
      expect(ciclo.periodEnd, isNull);
      expect(ciclo.isClosed, isFalse);

      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(await dump(), antes);
    });

    testCalendar('c) documenta el caso: un "No" explicito en un dia estimado '
        'solo es posible con datos futuros (p. ej. importados) y hoy se pinta '
        'punteado', (tester) async {
      // Marcados 1 y 2 de julio, duracion 12, hoy 8. Un "No" el 10 (en el
      // futuro, a mas de 7 dias del ultimo marcado: no cierra el periodo).
      await repo.setTypicalPeriodLength(12);
      await seedRange('2026-07-01', 2);
      await db.into(db.dailyLogs).insert(DailyLogsCompanion.insert(
            date: '2026-07-10',
            isPeriodDay: const Value(false),
            periodDayExplicit: const Value(true),
          ));
      await pumpCalendar(tester, '2026-07-08');
      // Estimados del 3 al 12, incluido el 10.
      expect(estimado(), findsNWidgets(10));
    });
  });

  group('hoy', () {
    BoxDecoration? decoracionDeHoy(WidgetTester tester) {
      final celda = find.ancestor(
          of: find.text('15'), matching: find.byType(AnimatedContainer));
      if (celda.evaluate().isNotEmpty) {
        return tester.widget<AnimatedContainer>(celda.first).decoration
            as BoxDecoration?;
      }
      return tester
          .widget<Container>(find
              .ancestor(of: find.text('15'), matching: find.byType(Container))
              .first)
          .decoration as BoxDecoration?;
    }

    testCalendar('hoy sin marcar: borde sin relleno y numero en negrita',
        (tester) async {
      await pumpCalendar(tester, '2026-07-15');
      final deco = decoracionDeHoy(tester)!;
      expect(deco.color, isNull);
      expect(deco.border, isNotNull);
      expect(tester.widget<Text>(find.text('15')).style!.fontWeight,
          FontWeight.bold);
    });

    testCalendar('hoy marcado: relleno de registrado', (tester) async {
      await repo.markPeriodDay('2026-07-15');
      await pumpCalendar(tester, '2026-07-15');
      expect(decoracionDeHoy(tester)!.color, AppColors.secondary);
    });
  });

  testCalendar('"Me llego hoy" siempre visible, abre la hoja', (tester) async {
    await seedRange('2026-07-12', 3);
    await pumpCalendar(tester, '2026-07-15');
    await tapText(tester, 'Me llegó hoy');
    expect(find.text('¿Cuándo empezó tu período?'), findsOneWidget);
  });

  testCalendar('accesibilidad: botones de al menos 48 dp', (tester) async {
    await seedRange('2026-07-12', 3);
    await pumpCalendar(tester, '2026-07-16');
    Size size(String text) =>
        tester.getSize(find.ancestor(
            of: find.text(text), matching: find.bySubtype<ButtonStyleButton>()));

    expect(size('Me llegó hoy').height, greaterThanOrEqualTo(48));
    await tapDay(tester, 16);
    expect(size('Confirmar días').height, greaterThanOrEqualTo(48));
    await tapDay(tester, 12);
    expect(size('Quitar marca').height, greaterThanOrEqualTo(48));
    await tapDay(tester, 5);
    expect(size('Marcar período').height,
        greaterThanOrEqualTo(48));
  });

  group('estado en texto y encabezado (accesibilidad)', () {
    // Cada celda del calendario es UN solo nodo: la fecha que arma
    // table_calendar y, si tiene, su estado ("período registrado", "hoy"),
    // que Flutter une con un salto de linea al fusionarlos.
    List<SemanticsNode> nodos(WidgetTester tester) {
      final lista = <SemanticsNode>[];
      void recorrer(SemanticsNode n) {
        lista.add(n);
        n.visitChildren((c) {
          recorrer(c);
          return true;
        });
      }

      recorrer(tester.binding.renderViews.first.owner!.semanticsOwner!
          .rootSemanticsNode!);
      return lista;
    }

    SemanticsNode celda(WidgetTester tester, String fecha) {
      final candidatas =
          nodos(tester).where((n) => n.label.startsWith(fecha)).toList();
      expect(candidatas, hasLength(1), reason: fecha);
      return candidatas.single;
    }

    void unSoloNodo(WidgetTester tester, String fecha, String etiqueta) {
      final nodo = celda(tester, fecha);
      expect(nodo.label, etiqueta);
      expect(nodo.getSemanticsData().hasAction(SemanticsAction.tap), isTrue,
          reason: 'la celda sigue siendo tocable');
      // Ningun hijo con el estado.
      final hijos = <String>[];
      nodo.visitChildren((c) {
        hijos.add(c.label);
        return true;
      });
      expect(hijos.where((l) => l.contains('registrado') || l == 'hoy'),
          isEmpty);
    }

    void sinNodoDeEstadoSuelto(WidgetTester tester) {
      final etiquetas = nodos(tester).map((n) => n.label).toSet();
      expect(etiquetas.contains('período registrado'), isFalse);
      expect(etiquetas.contains('hoy'), isFalse);
      expect(etiquetas.contains('período registrado, hoy'), isFalse);
    }

    testCalendar('celda sin estado: la misma etiqueta de siempre (solo fecha)',
        (tester) async {
      await seedRange('2026-07-10', 3);
      await repo.closePeriod('2026-07-10', '2026-07-12', today: '2026-07-15');
      await pumpCalendar(tester, '2026-07-15');
      unSoloNodo(tester, 'lunes, 13 de julio de 2026',
          'lunes, 13 de julio de 2026');
    });

    testCalendar('solo periodo registrado: fecha y estado en un solo nodo',
        (tester) async {
      await seedRange('2026-07-10', 3);
      await repo.closePeriod('2026-07-10', '2026-07-12', today: '2026-07-15');
      await pumpCalendar(tester, '2026-07-15');
      for (final fecha in [
        'viernes, 10 de julio de 2026',
        'sábado, 11 de julio de 2026',
        'domingo, 12 de julio de 2026',
      ]) {
        unSoloNodo(tester, fecha, '$fecha\nperíodo registrado');
      }
      sinNodoDeEstadoSuelto(tester);
    });

    testCalendar('solo hoy: fecha y "hoy" en un solo nodo', (tester) async {
      await seedRange('2026-07-10', 3);
      await repo.closePeriod('2026-07-10', '2026-07-12', today: '2026-07-15');
      await pumpCalendar(tester, '2026-07-15');
      unSoloNodo(tester, 'miércoles, 15 de julio de 2026',
          'miércoles, 15 de julio de 2026\nhoy');
      sinNodoDeEstadoSuelto(tester);
    });

    testCalendar('registrado y hoy: primero "período registrado", luego "hoy"',
        (tester) async {
      await seedRange('2026-07-14', 2);
      await pumpCalendar(tester, '2026-07-15');
      unSoloNodo(tester, 'miércoles, 15 de julio de 2026',
          'miércoles, 15 de julio de 2026\nperíodo registrado, hoy');
      unSoloNodo(tester, 'martes, 14 de julio de 2026',
          'martes, 14 de julio de 2026\nperíodo registrado');
      sinNodoDeEstadoSuelto(tester);
    });

    testCalendar('el toque desde el lector sigue seleccionando el dia',
        (tester) async {
      await seedRange('2026-07-10', 3);
      await repo.closePeriod('2026-07-10', '2026-07-12', today: '2026-07-15');
      await pumpCalendar(tester, '2026-07-15');
      celda(tester, 'viernes, 10 de julio de 2026');
      tester.semantics
          .tap(find.semantics.byLabel(RegExp(r'^viernes, 10 de julio de 2026')));
      await tester.pumpAndSettle();
      expect(find.text('Día seleccionado: 10 julio 2026'), findsOneWidget);
    });

    testCalendar('las marcas de siempre conservan su etiqueta junto al estado',
        (tester) async {
      // Periodo abierto desde el 12: el 15 (hoy) y el 16 son estimados.
      await seedRange('2026-07-12', 3);
      await pumpCalendar(tester, '2026-07-15');
      expect(estimado(), findsNWidgets(2));
      // Hoy: un nodo con fecha y estado; la marca "estimado" sigue como
      // su hijo, igual que en cualquier otro dia estimado.
      final hoy = celda(tester, 'miércoles, 15 de julio de 2026');
      expect(hoy.label, 'miércoles, 15 de julio de 2026\nhoy');
      final hijos = <String>[];
      hoy.visitChildren((c) {
        hijos.add(c.label);
        return true;
      });
      expect(hijos, ['estimado']);
    });

    testCalendar('las flechas de mes tienen etiqueta y cambian de mes',
        (tester) async {
      await pumpCalendar(tester, '2026-07-15');
      expect(find.text('julio de 2026'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Mes anterior'));
      await tester.pumpAndSettle();
      expect(find.text('junio de 2026'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Mes siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('julio de 2026'), findsOneWidget);

      final flecha = tester.getSize(find.ancestor(
          of: find.byIcon(Icons.chevron_left), matching: find.byType(InkWell)));
      expect(flecha.height, greaterThanOrEqualTo(48));
    });

    testCalendar('el titulo del mes es un encabezado, no un boton',
        (tester) async {
      await pumpCalendar(tester, '2026-07-15');
      expect(
        tester.getSemantics(find.text('julio de 2026')),
        matchesSemantics(label: 'julio de 2026', isHeader: true),
      );
      expect(
        find.ancestor(
            of: find.text('julio de 2026'),
            matching: find.byType(GestureDetector)),
        findsNothing,
      );
    });
  });

  testCalendar('periodo registrado: relleno pastel con borde fino', (tester) async {
    await seedRange('2026-07-10', 2);
    await pumpCalendar(tester, '2026-07-15');
    final celda = find
        .ancestor(of: find.text('10'), matching: find.byType(Container))
        .first;
    final deco = tester.widget<Container>(celda).decoration! as BoxDecoration;
    expect(deco.color, AppColors.secondary);
    final borde = (deco.border! as Border).top;
    expect(borde.color, AppColors.accentStrong);
    expect(borde.width, AppColors.thinBorderWidth);
  });
}
