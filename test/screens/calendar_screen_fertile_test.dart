import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/screens/calendar_screen.dart';
import 'package:aura/utils/colors.dart';
import 'package:aura/utils/day_key.dart';
import 'package:aura/widgets/period_day_marks.dart';

/// Calendario, HU-05 CP5d-2: marcas de la ventana fertil y de la
/// ovulacion (misma regla que Inicio, visibleFertileMarks), su prioridad
/// frente a la seleccion y a los dias de periodo, la leyenda y el color
/// de los dias futuros. Datos inventados; los periodos duran 5 dias y
/// estan abiertos (duracion estimada 5, el ajuste).
///
/// Cuenta: con ciclos iguales de N dias, esperado = ultimo inicio + N;
/// ovulacion = esperado - 14; ventana = ovulacion - 5 .. ovulacion (6
/// dias); rango del proximo periodo = esperado +-2 (semiancho minimo).
void main() {
  late AppDatabase db;
  late CycleRepository repo;

  const ventana = 'ventana fértil estimada';
  const ovulacion = 'ovulación estimada';
  const leyendaVentana = 'Ventana fértil estimada';
  const leyendaOvulacion = 'Ovulación estimada';
  const aviso = 'Estimación; no es un método anticonceptivo.';

  setUpAll(() async {
    await initializeDateFormatting();
  });

  setUp(() {
    db = AppDatabase.forTesting(
      NativeDatabase.memory(setup: enableForeignKeys),
    );
    repo = CycleRepository(db);
  });

  // La base se cierra dentro de cada test (en tearDown deja timers de
  // drift pendientes y el test no termina).
  void testCalendar(
    String description,
    Future<void> Function(WidgetTester) body,
  ) => testWidgets(description, (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await body(tester);
    semantics.dispose();
    await db.close();
  });

  Future<void> seedPeriods(List<String> starts, {int length = 5}) async {
    await repo.markPeriodDays([
      for (final start in starts)
        for (var i = 0; i < length; i++) DayKey.addDays(start, i),
    ]);
  }

  Future<void> pumpCalendar(
    WidgetTester tester,
    String today, {
    double textScale = 1,
  }) async {
    final date = DateTime.parse(today);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: CalendarScreen(repository: repo, clock: () => date),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> mesSiguiente(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
  }

  Future<void> mesAnterior(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
  }

  /// Numeros de los dias del mes visible cuya marca tiene [etiqueta].
  Set<int> diasCon(WidgetTester tester, String etiqueta) {
    final marcas = [
      for (final e in find.bySemanticsLabel(etiqueta).evaluate())
        tester.getRect(find.byWidget(e.widget)),
    ];
    return {
      for (var d = 1; d <= 31; d++)
        if (find.text('$d').evaluate().length == 1 &&
            marcas.any((r) => r.contains(tester.getCenter(find.text('$d')))))
          d,
    };
  }

  /// Marcas dibujadas en las celdas (sin las muestras de la leyenda).
  Finder enCalendario(String key) => find.descendant(
    of: find.byType(TableCalendar),
    matching: find.byKey(ValueKey(key)),
  );

  void sinMarcas() {
    expect(find.bySemanticsLabel(ventana), findsNothing);
    expect(find.bySemanticsLabel(ovulacion), findsNothing);
  }

  void sinLeyendaFertil() {
    expect(find.text(leyendaVentana), findsNothing);
    expect(find.text(leyendaOvulacion), findsNothing);
    expect(find.text(aviso), findsNothing);
  }

  void conLeyendaFertil() {
    expect(find.text('Período registrado'), findsOneWidget);
    expect(find.text(leyendaVentana), findsOneWidget);
    expect(find.text(leyendaOvulacion), findsOneWidget);
    expect(find.text(aviso), findsOneWidget);
  }

  // Ciclos de 28 con el ultimo inicio el 01/07: 11/03, 08/04, 06/05,
  // 03/06 y 01/07 (+28 cada uno). Esperado 29/07; ovulacion 15/07;
  // ventana 10/07 - 15/07; rango 27/07 - 31/07.
  const altaJulio = [
    '2026-03-11',
    '2026-04-08',
    '2026-05-06',
    '2026-06-03',
    '2026-07-01',
  ];
  // Sin el 11/03: 3 ciclos completos (confianza media), mismas fechas.
  final mediaJulio = altaJulio.sublist(1);

  group('marcas con el interruptor encendido', () {
    for (final (nombre, inicios) in [
      ('alta', altaJulio),
      ('media', mediaJulio),
    ]) {
      testCalendar(
        '$nombre: 10-14/07 ventana, 15/07 ovulacion; 09 y 16 sin marca',
        (tester) async {
          await seedPeriods(inicios);
          await repo.setShowFertileWindow(true);
          // Hoy 07/07: dia 7 del ciclo, sin estimados (el periodo ya tiene
          // sus 5 dias) y la ventana entera en dias futuros.
          await pumpCalendar(tester, '2026-07-07');

          expect(diasCon(tester, ventana), {10, 11, 12, 13, 14});
          expect(diasCon(tester, ovulacion), {15});
          expect(find.bySemanticsLabel(ventana), findsNWidgets(5));
          expect(find.bySemanticsLabel(ovulacion), findsOneWidget);
          expect(enCalendario('fertile-bar'), findsNWidgets(6));
          // El punto solo en la ovulacion (no depende solo del color).
          expect(enCalendario('ovulation-dot'), findsOneWidget);
          conLeyendaFertil();
        },
      );
    }

    testCalendar(
      'ventana que cruza de julio a agosto: al pasar de mes aparecen '
      'las marcas que caen en agosto',
      (tester) async {
        // Inicios 30/03, 27/04, 25/05, 22/06 y 20/07 (+28). Esperado
        // 17/08 (20/07 + 28); ovulacion 03/08; ventana 29/07 - 03/08.
        await seedPeriods([
          '2026-03-30',
          '2026-04-27',
          '2026-05-25',
          '2026-06-22',
          '2026-07-20',
        ]);
        await pumpCalendar(tester, '2026-07-25');

        expect(diasCon(tester, ventana), {29, 30, 31});
        expect(diasCon(tester, ovulacion), isEmpty);
        expect(diasCon(tester, ventana).contains(28), isFalse);
        conLeyendaFertil();

        await mesSiguiente(tester);
        expect(diasCon(tester, ventana), {1, 2});
        expect(diasCon(tester, ovulacion), {3});
        // 04/08 sin marca.
        expect(diasCon(tester, ventana).contains(4), isFalse);
      },
    );
  });

  group('sin marcas', () {
    testCalendar('interruptor apagado: sin marcas, sin entradas nuevas en la '
        'leyenda y sin el aviso', (tester) async {
      await seedPeriods(altaJulio);
      await repo.setShowFertileWindow(false);
      await pumpCalendar(tester, '2026-07-07');
      sinMarcas();
      sinLeyendaFertil();
      expect(find.byKey(const ValueKey('fertile-bar')), findsNothing);
      expect(find.text('Período registrado'), findsOneWidget);
      // Periodo de 5 dias ya completo: no hay estimados que mostrar.
      expect(find.text('Estimado sin confirmar'), findsNothing);
    });

    testCalendar('confianza baja (un solo periodo)', (tester) async {
      // Con promedio 28 la ventana seria 10/07 - 15/07.
      await seedPeriods(['2026-07-01']);
      await pumpCalendar(tester, '2026-07-07');
      sinMarcas();
      sinLeyendaFertil();
    });

    testCalendar('periodo atrasado (confianza alta)', (tester) async {
      // Extremo tardio 31/07; el 01/08 es 1 dia de atraso.
      await seedPeriods(altaJulio);
      await pumpCalendar(tester, '2026-08-01');
      sinMarcas();
      sinLeyendaFertil();
      await mesAnterior(tester);
      sinMarcas();
    });

    testCalendar('datos viejos (mas de 60 dias)', (tester) async {
      // 01/09 son 62 dias desde el 01/07.
      await seedPeriods(altaJulio);
      await pumpCalendar(tester, '2026-09-01');
      sinMarcas();
      sinLeyendaFertil();
      await mesAnterior(tester);
      await mesAnterior(tester);
      sinMarcas();
    });
  });

  group('prioridad: seleccion > periodo > ventana', () {
    testCalendar(
      'a) y b) ciclo corto: el estimado conserva solo su marca y los '
      'dias registrados no llevan marca de ventana',
      (tester) async {
        // Ciclos de 16 (3 completos, confianza media): inicios 03/06, 19/06,
        // 05/07 y 21/07; del ultimo, marcados el 21 y el 22. Esperado
        // 06/08 (21/07 + 16); ovulacion 23/07; ventana 18/07 - 23/07.
        // Estimados: 23, 24 y 25 (duracion 5).
        await seedPeriods(['2026-06-03', '2026-06-19', '2026-07-05']);
        await seedPeriods(['2026-07-21'], length: 2);
        await pumpCalendar(tester, '2026-07-22');

        expect(diasCon(tester, 'estimado'), {23, 24, 25});
        // a) 23 es ovulacion y estimado: solo "estimado".
        expect(diasCon(tester, ovulacion), isEmpty);
        // b) 21 y 22 estan registrados: sin ventana.
        expect(diasCon(tester, ventana), {18, 19, 20});
      },
    );

    testCalendar('c) dia seleccionado dentro de la ventana: sin marca', (
      tester,
    ) async {
      // Hoy 20/07: la ventana 10-15/07 ya paso y se puede tocar.
      await seedPeriods(altaJulio);
      await pumpCalendar(tester, '2026-07-20');
      expect(diasCon(tester, ventana), {10, 11, 12, 13, 14});

      await tester.tap(find.text('12'));
      await tester.pumpAndSettle();
      expect(diasCon(tester, ventana), {10, 11, 13, 14});
      expect(diasCon(tester, ovulacion), {15});
    });
  });

  testCalendar('leyenda: aviso con el mismo estilo que el de Inicio', (
    tester,
  ) async {
    await seedPeriods(altaJulio);
    await pumpCalendar(tester, '2026-07-07');
    conLeyendaFertil();
    final estilo = tester.widget<Text>(find.text(aviso)).style!;
    expect(estilo.fontSize, 12);
    expect(estilo.fontStyle, FontStyle.italic);
    expect(estilo.color, Colors.grey[700]);
  });

  testCalendar('leyenda sin datos: solo registrado', (tester) async {
    await pumpCalendar(tester, '2026-07-07');
    expect(find.text('Período registrado'), findsOneWidget);
    expect(find.text('Estimado sin confirmar'), findsNothing);
    sinLeyendaFertil();
  });

  testCalendar('numero de los dias futuros en AppColors.textSecondary', (
    tester,
  ) async {
    await pumpCalendar(tester, '2026-07-07');
    for (final dia in ['8', '20', '31']) {
      expect(
        tester.widget<Text>(find.text(dia)).style?.color,
        AppColors.textSecondary,
        reason: dia,
      );
    }
  });

  testCalendar('texto a 1,5 en 360 dp: sin errores de layout con marcas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1400);
    await seedPeriods(altaJulio);
    await pumpCalendar(tester, '2026-07-07', textScale: 1.5);
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel(ovulacion), findsOneWidget);
    expect(find.bySemanticsLabel(ventana), findsNWidgets(5));
  });

  testCalendar('se actualiza sola al cambiar el interruptor', (tester) async {
    await seedPeriods(altaJulio);
    await pumpCalendar(tester, '2026-07-07');
    expect(diasCon(tester, ovulacion), {15});

    await repo.setShowFertileWindow(false);
    await tester.pumpAndSettle();
    sinMarcas();
    sinLeyendaFertil();

    await repo.setShowFertileWindow(true);
    await tester.pumpAndSettle();
    expect(diasCon(tester, ventana), {10, 11, 12, 13, 14});
    expect(diasCon(tester, ovulacion), {15});
    conLeyendaFertil();
  });

  // #23: el punto de la ovulacion va justo encima de la barra, debajo del
  // numero, como en la leyenda (antes iba arriba de la celda y parecia
  // del dia de la fila anterior).
  group('posicion del punto de la ovulacion', () {
    Rect enLaColumnaDel15(WidgetTester tester, String key) {
      final centro = tester.getCenter(find.text('15').hitTestable());
      return find
          .descendant(
              of: find.byType(TableCalendar<dynamic>),
              matching: find.byKey(ValueKey(key)))
          .evaluate()
          .map((e) => tester.getRect(find.byWidget(e.widget)))
          .where((r) =>
              (r.center.dx - centro.dx).abs() < 10 &&
              (r.center.dy - centro.dy).abs() < 40)
          .single;
    }

    for (final escala in [1.0, 1.3, 1.5]) {
      testCalendar('texto $escala: justo sobre la barra, bajo el numero',
          (tester) async {
        await seedPeriods(altaJulio);
        await pumpCalendar(tester, '2026-07-07', textScale: escala);
        final punto = enLaColumnaDel15(tester, 'ovulation-dot');
        final barra = enLaColumnaDel15(tester, 'fertile-bar');
        final numero = tester.getRect(find.text('15').hitTestable());

        expect((punto.center.dx - barra.center.dx).abs(), lessThan(0.5));
        expect(barra.top - punto.bottom, FertileDayMark.dotGap);
        // En la celda del 15, por debajo del centro de su numero.
        expect(punto.top, greaterThan(numero.center.dy));
        // Con el texto normal no toca el numero. Con letra grande (1,3 o
        // mas) la caja del numero puede tocar el punto: limitacion conocida.
        if (escala == 1.0) {
          expect(punto.top, greaterThanOrEqualTo(numero.bottom));
        }
        expect(tester.takeException(), isNull);
      });
    }

    testCalendar('la leyenda sigue con el punto sobre la barra',
        (tester) async {
      await seedPeriods(altaJulio);
      await pumpCalendar(tester, '2026-07-07');
      final leyenda = find.byType(CalendarLegend);
      final punto = tester.getRect(find.descendant(
          of: leyenda, matching: find.byKey(const ValueKey('ovulation-dot'))));
      final barra = tester.getRect(find
          .descendant(
              of: leyenda, matching: find.byKey(const ValueKey('fertile-bar')))
          .last);
      expect(punto.bottom, lessThanOrEqualTo(barra.top));
      expect((punto.center.dx - barra.center.dx).abs(), lessThan(0.5));
    });
  });
}
