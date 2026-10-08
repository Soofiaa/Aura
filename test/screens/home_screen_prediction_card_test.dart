import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/screens/home_screen.dart';
import 'package:aura/utils/day_key.dart';

/// Tarjeta de prediccion de Inicio. CP1 de HU-05 fijo los textos; el CP3
/// cambia a proposito lo que se ve con confianza baja (sin ovulacion ni
/// ventana fertil, H5-1 A), con un periodo atrasado (sin fase) y con
/// datos viejos. Datos inventados; todos los periodos duran 5 dias y
/// estan abiertos. Las fechas se ven como dd/MM/yyyy.
void main() {
  late AppDatabase db;
  late CycleRepository repo;

  const avisoPie = 'Esta es una estimación, no un método anticonceptivo.';
  const avisoTarjeta = 'Estimación; no es un método anticonceptivo.';
  const masCiclos =
      'Con más ciclos registrados podremos estimar tu ventana fértil.';
  const variabilidad =
      'Tus ciclos varían mucho, así que no mostramos tu ventana fértil.';
  const ventana = 'Días de mayor probabilidad de fertilidad';

  setUpAll(() async {
    await initializeDateFormatting();
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CycleRepository(db);
  });

  // La base se cierra dentro de cada test (en tearDown deja timers de
  // drift pendientes y el test no termina).
  void testHome(
          String description, Future<void> Function(WidgetTester) body) =>
      testWidgets(description, (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await body(tester);
        await db.close();
      });

  Future<void> seedPeriods(List<String> starts) async {
    await repo.markPeriodDays([
      for (final start in starts)
        for (var i = 0; i < 5; i++) DayKey.addDays(start, i),
    ]);
  }

  Future<void> pumpHome(WidgetTester tester, String today) async {
    final date = DateTime.parse(today);
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(repository: repo, clock: () => date),
    ));
    await tester.pumpAndSettle();
  }

  /// Textos visibles, en el orden del arbol de widgets.
  List<String> textos(WidgetTester tester) => [
        for (final e in find.byType(Text).evaluate())
          if ((e.widget as Text).data != null) (e.widget as Text).data!,
      ];

  /// Comprueba que no se ve ninguna linea de fase.
  void sinFase() {
    for (final fase in [
      'Fase menstrual',
      'Fase folicular',
      'Fase ovulatoria',
      'Fase lútea'
    ]) {
      expect(find.text(fase), findsNothing, reason: fase);
    }
  }

  void sinOvulacionNiVentana() {
    expect(find.textContaining('Ovulación estimada'), findsNothing);
    expect(find.textContaining(ventana), findsNothing);
    expect(find.text(avisoTarjeta), findsNothing);
    expect(find.textContaining('Confianza baja: esta ventana'), findsNothing);
    expect(find.byType(Opacity), findsNothing);
  }

  /// La linea de aviso de la tarjeta va inmediatamente despues de la
  /// ventana fertil, y el aviso del pie sigue.
  void avisoJustoDespuesDeLaVentana(WidgetTester tester) {
    final t = textos(tester);
    final i = t.indexWhere((s) => s.startsWith(ventana));
    expect(i, isNot(-1));
    expect(t[i + 1], avisoTarjeta);
    expect(find.text(avisoTarjeta), findsOneWidget);
    expect(find.text(avisoPie), findsOneWidget);
    final estiloTarjeta = tester.widget<Text>(find.text(avisoTarjeta)).style!;
    expect(estiloTarjeta.fontSize, 12);
    expect(estiloTarjeta.fontStyle, FontStyle.italic);
    expect(estiloTarjeta.color, Colors.grey[700]);
    final estiloPie = tester.widget<Text>(find.text(avisoPie)).style!;
    expect(estiloPie.color, Colors.grey[700]);
  }

  // Cuatro periodos cada 28 dias: 3 ciclos completos (confianza media).
  const tresCiclos = ['2026-01-01', '2026-01-29', '2026-02-26', '2026-03-26'];

  testHome('sin datos: tarjeta vacia y el aviso del pie', (tester) async {
    await pumpHome(tester, '2026-03-28');
    expect(find.text('Aún no hay datos suficientes'), findsOneWidget);
    expect(
        find.text('Registra tu primer día para ver una predicción de tu '
            'ciclo.'),
        findsOneWidget);
    expect(find.textContaining('Próximo período:'), findsNothing);
    expect(find.textContaining('Confianza:'), findsNothing);
    expect(find.text(avisoPie), findsOneWidget);
  });

  group('confianza baja', () {
    testHome('1 periodo: proximo periodo con "(valor por defecto)", sin '
        'ovulacion ni ventana, y el texto de mas ciclos', (tester) async {
      // Inicio 01/02; esperado 01/03 (+28), rango 26/02 - 04/03 (+-3).
      await seedPeriods(['2026-02-01']);
      await pumpHome(tester, '2026-02-03');

      expect(find.text('Fase menstrual'), findsOneWidget);
      expect(find.text('Próximo período: 26/02/2026 - 04/03/2026'),
          findsOneWidget);
      expect(find.text('Estimado: 01/03/2026 (valor por defecto)'),
          findsOneWidget);
      sinOvulacionNiVentana();
      expect(find.text(masCiclos), findsOneWidget);
      expect(find.text(variabilidad), findsNothing);
      expect(find.text('Confianza: Baja'), findsOneWidget);
      expect(
          find.text('Menos de 2 ciclos completos registrados; se usa un '
              'promedio por defecto de 28 días.'),
          findsOneWidget);
      expect(find.text(avisoPie), findsOneWidget);
    });

    testHome('b) 1 ciclo completo (pocos datos): texto de mas ciclos',
        (tester) async {
      // Inicios 01/01 y 02/02 (ciclo de 32, que se ignora): esperado
      // 02/03 (02/02 + 28).
      await seedPeriods(['2026-01-01', '2026-02-02']);
      await pumpHome(tester, '2026-02-04');
      expect(find.text('Estimado: 02/03/2026 (valor por defecto)'),
          findsOneWidget);
      sinOvulacionNiVentana();
      expect(find.text(masCiclos), findsOneWidget);
      expect(find.text('Confianza: Baja'), findsOneWidget);
    });

    testHome('a) variabilidad alta (4 ciclos, razon > 0,18): sin ventana y '
        'con el texto de variabilidad', (tester) async {
      // Ciclos de 20, 31, 23 y 20 dias (razon 0,180005, ver el CP1 en
      // cycle_predictor_test.dart). Inicios 01/01, 21/01, 21/02, 16/03 y
      // 05/04; promedio 23,1 -> esperado 28/04 (05/04 + 23).
      await seedPeriods(
          ['2026-01-01', '2026-01-21', '2026-02-21', '2026-03-16', '2026-04-05']);
      await pumpHome(tester, '2026-04-07');

      expect(find.text('Estimado: 28/04/2026'), findsOneWidget);
      sinOvulacionNiVentana();
      expect(find.text(variabilidad), findsOneWidget);
      expect(find.text(masCiclos), findsNothing);
      expect(find.text('Confianza: Baja'), findsOneWidget);
      expect(
          find.text('Variabilidad alta entre ciclos (±18% del promedio).'),
          findsOneWidget);
    });

    testHome('c) dia ovulatorio con confianza baja: no hay linea de fase',
        (tester) async {
      // 1 periodo, promedio 28: ovulacion el dia 15 (ovulatoria 14-16).
      await seedPeriods(['2026-02-01']);
      await pumpHome(tester, '2026-02-15');
      sinFase();
      expect(find.text('Confianza: Baja'), findsOneWidget);
      expect(find.textContaining('Próximo período:'), findsOneWidget);
    });

    testHome('c) las demas fases si se ven con confianza baja (lutea, dia '
        '20)', (tester) async {
      await seedPeriods(['2026-02-01']);
      await pumpHome(tester, '2026-02-20');
      expect(find.text('Fase lútea'), findsOneWidget);
    });
  });

  group('confianza media y alta', () {
    testHome('d) media: ovulacion, ventana y el aviso justo despues de la '
        'ventana, sin advertencias de confianza baja', (tester) async {
      await seedPeriods(tresCiclos);
      await pumpHome(tester, '2026-03-28');

      expect(find.text('Confianza: Media'), findsOneWidget);
      expect(find.textContaining('Ovulación estimada:'), findsOneWidget);
      expect(find.textContaining('Estimado: '), findsOneWidget);
      expect(find.textContaining('(valor por defecto)'), findsNothing);
      expect(find.text(masCiclos), findsNothing);
      expect(find.text(variabilidad), findsNothing);
      expect(find.byType(Opacity), findsNothing);
      avisoJustoDespuesDeLaVentana(tester);
    });

    testHome('d) media en dia ovulatorio: la fase ovulatoria si se ve',
        (tester) async {
      // Ultimo inicio 26/03; ovulacion el dia 15 = 09/04.
      await seedPeriods(tresCiclos);
      await pumpHome(tester, '2026-04-09');
      expect(find.text('Fase ovulatoria'), findsOneWidget);
    });

    testHome('e) alta (4 ciclos de 28): lo mismo', (tester) async {
      await seedPeriods(['2025-12-04', ...tresCiclos]);
      await pumpHome(tester, '2026-03-28');
      expect(find.text('Confianza: Alta'), findsOneWidget);
      expect(find.textContaining('Ovulación estimada:'), findsOneWidget);
      avisoJustoDespuesDeLaVentana(tester);
    });
  });

  // Atrasado: ultimo inicio 26/03; esperado 23/04 (+28); extremo tardio
  // 25/04 (semiancho 2). El 26/04 es 1 dia de atraso; el 28/04, 3.
  group('f) atrasado: sin linea de fase', () {
    testHome('1 dia: singular', (tester) async {
      await seedPeriods(tresCiclos);
      await pumpHome(tester, '2026-04-26');
      expect(find.text('Período atrasado por 1 día'), findsOneWidget);
      sinFase();
      expect(find.textContaining('Próximo período:'), findsOneWidget);
      expect(find.text('Confianza: Media'), findsOneWidget);
    });

    testHome('3 dias: plural', (tester) async {
      await seedPeriods(tresCiclos);
      await pumpHome(tester, '2026-04-28');
      expect(find.text('Período atrasado por 3 días'), findsOneWidget);
      sinFase();
      expect(find.textContaining('Ovulación estimada:'), findsOneWidget);
      expect(find.text(avisoTarjeta), findsOneWidget);
    });
  });

  testHome('datos viejos (mas de 60 dias): nuevo cuerpo, sin fase ni '
      'prediccion', (tester) async {
    // Inicio 01/01; el 03/03 son 61 dias.
    await seedPeriods(['2026-01-01']);
    await pumpHome(tester, '2026-03-03');

    expect(find.text('Hace tiempo que no registras...'), findsOneWidget);
    expect(
        find.text('Tu último período empezó el 01/01/2026 (hace 61 días). '
            'Registra un nuevo día para volver a ver una predicción.'),
        findsOneWidget);
    sinFase();
    expect(find.textContaining('Próximo período:'), findsNothing);
    expect(find.textContaining('Ovulación estimada'), findsNothing);
    expect(find.textContaining('Confianza:'), findsNothing);
    expect(find.text(avisoPie), findsOneWidget);
  });

  testHome('exactamente 60 dias todavia muestra la prediccion',
      (tester) async {
    await seedPeriods(['2026-01-01']);
    await pumpHome(tester, '2026-03-02');
    expect(find.text('Hace tiempo que no registras...'), findsNothing);
    expect(find.textContaining('Próximo período:'), findsOneWidget);
  });
}
