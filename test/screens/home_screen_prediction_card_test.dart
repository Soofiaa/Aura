import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/screens/home_screen.dart';
import 'package:aura/utils/day_key.dart';

/// HU-05, CP1: caracterizacion de la tarjeta de prediccion de Inicio.
/// Fija los textos que se ven HOY en cada estado. Datos inventados;
/// todos los periodos duran 5 dias y estan abiertos. Las fechas se ven
/// como dd/MM/yyyy.
void main() {
  late AppDatabase db;
  late CycleRepository repo;

  const aviso = 'Esta es una estimación, no un método anticonceptivo.';
  const ventanaBaja = 'Confianza baja: esta ventana puede no ser precisa.';

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

  double fertileOpacity(WidgetTester tester) => tester
      .widget<Opacity>(find.ancestor(
          of: find.textContaining('Días de mayor probabilidad de fertilidad'),
          matching: find.byType(Opacity)))
      .opacity;

  // Cuatro periodos cada 28 dias: 3 ciclos completos (confianza media).
  const tresCiclos = ['2026-01-01', '2026-01-29', '2026-02-26', '2026-03-26'];

  testHome('sin datos: tarjeta vacia y el aviso', (tester) async {
    await pumpHome(tester, '2026-03-28');
    expect(find.text('Aún no hay datos suficientes'), findsOneWidget);
    expect(
        find.text('Registra tu primer día para ver una predicción de tu '
            'ciclo.'),
        findsOneWidget);
    expect(find.textContaining('Próximo período:'), findsNothing);
    expect(find.textContaining('Confianza:'), findsNothing);
    expect(find.text(aviso), findsOneWidget);
  });

  testHome('1 periodo: promedio 28, confianza baja, ovulacion y ventana '
      'fertil visibles (atenuada) y el motivo', (tester) async {
    // Inicio 01/02; esperado 01/03 (+28), rango 26/02 - 04/03 (+-3).
    // Ovulacion 15/02 (esperado - 14); ventana 10/02 - 15/02.
    await seedPeriods(['2026-02-01']);
    await pumpHome(tester, '2026-02-03');

    expect(find.text('Fase menstrual'), findsOneWidget);
    expect(find.text('Próximo período: 26/02/2026 - 04/03/2026'),
        findsOneWidget);
    expect(find.text('Estimado: 01/03/2026'), findsOneWidget);
    expect(find.text('Ovulación estimada: 15/02/2026'), findsOneWidget);
    expect(
        find.text('Días de mayor probabilidad de fertilidad (estimación):\n'
            '10/02/2026 - 15/02/2026'),
        findsOneWidget);
    expect(find.text(ventanaBaja), findsOneWidget);
    expect(fertileOpacity(tester), 0.5);
    expect(find.text('Confianza: Baja'), findsOneWidget);
    expect(
        find.text('Menos de 2 ciclos completos registrados; se usa un '
            'promedio por defecto de 28 días.'),
        findsOneWidget);
    expect(find.text(aviso), findsOneWidget);
  });

  testHome('confianza media: 3 ciclos de 28, ventana sin atenuar ni '
      'advertencia', (tester) async {
    await seedPeriods(tresCiclos);
    await pumpHome(tester, '2026-03-28');

    expect(find.text('Confianza: Media'), findsOneWidget);
    expect(find.textContaining('Ovulación estimada:'), findsOneWidget);
    expect(find.text(ventanaBaja), findsNothing);
    expect(fertileOpacity(tester), 1.0);
    expect(find.textContaining('Período atrasado'), findsNothing);
    expect(find.text(aviso), findsOneWidget);
  });

  testHome('confianza alta: 4 ciclos de 28', (tester) async {
    await seedPeriods(['2025-12-04', ...tresCiclos]);
    await pumpHome(tester, '2026-03-28');
    expect(find.text('Confianza: Alta'), findsOneWidget);
    expect(find.text(ventanaBaja), findsNothing);
  });

  // Atrasado: ultimo inicio 26/03; esperado 23/04 (+28); extremo tardio
  // 25/04 (semiancho 2). El 26/04 es 1 dia de atraso; el 28/04, 3.
  testHome('atrasado por 1 dia: singular', (tester) async {
    await seedPeriods(tresCiclos);
    await pumpHome(tester, '2026-04-26');
    expect(find.text('Período atrasado por 1 día'), findsOneWidget);
  });

  testHome('atrasado por 3 dias: plural, con la prediccion igual',
      (tester) async {
    await seedPeriods(tresCiclos);
    await pumpHome(tester, '2026-04-28');
    expect(find.text('Período atrasado por 3 días'), findsOneWidget);
    expect(find.text('Confianza: Media'), findsOneWidget);
    expect(find.textContaining('Próximo período:'), findsOneWidget);
  });

  testHome('datos viejos (mas de 60 dias): tarjeta de datos desactualizados '
      'sin fase ni prediccion', (tester) async {
    // Inicio 01/01; el 03/03 son 61 dias.
    await seedPeriods(['2026-01-01']);
    await pumpHome(tester, '2026-03-03');

    expect(find.text('Hace tiempo que no registras...'), findsOneWidget);
    expect(
        find.text('Tu último registro fue el 01/01/2026 (hace 61 días). '
            'Registra un nuevo día para volver a ver una predicción.'),
        findsOneWidget);
    expect(find.textContaining('Fase '), findsNothing);
    expect(find.textContaining('Próximo período:'), findsNothing);
    expect(find.textContaining('Ovulación estimada'), findsNothing);
    expect(find.textContaining('Confianza:'), findsNothing);
    expect(find.text(aviso), findsOneWidget);
  });

  testHome('exactamente 60 dias todavia muestra la prediccion',
      (tester) async {
    await seedPeriods(['2026-01-01']);
    await pumpHome(tester, '2026-03-02');
    expect(find.text('Hace tiempo que no registras...'), findsNothing);
    expect(find.textContaining('Próximo período:'), findsOneWidget);
  });
}
