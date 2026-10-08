import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/models/day_enums.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/screens/stats_screen.dart';

/// HU-05, CP1: caracterizacion de Estadisticas. Fija lo que muestra HOY:
/// solo flujo, sintomas y animo; nada de ciclos. Datos inventados.
void main() {
  late AppDatabase db;
  late CycleRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CycleRepository(db);
    // StatsScreen usa el repositorio global.
    cycleRepository = repo;
  });

  // La base se cierra dentro de cada test (en tearDown deja timers de
  // drift pendientes y el test no termina).
  void testStats(
          String description, Future<void> Function(WidgetTester) body) =>
      testWidgets(description, (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await body(tester);
        await db.close();
      });

  Future<void> pumpStats(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: StatsScreen()));
    await tester.pumpAndSettle();
  }

  testStats('sin registros: solo el estado vacio', (tester) async {
    await pumpStats(tester);
    expect(find.text('Estadísticas'), findsOneWidget);
    expect(find.text('Aún no hay registros guardados 🩷'), findsOneWidget);
    expect(find.text('Promedio de flujo'), findsNothing);
    expect(find.byType(BarChart), findsNothing);
    expect(find.byType(PieChart), findsNothing);
  });

  testStats('con datos: promedio de flujo, sintomas y animo; nada de ciclos',
      (tester) async {
    // Tres periodos de 2 dias cada 28 dias (2 ciclos completos). Flujo
    // moderado (2) y abundante (3) alternados: promedio 2,5 -> Abundante
    // (el corte de Moderado es < 2,5).
    final dias = [
      '2026-01-01', '2026-01-02', //
      '2026-01-29', '2026-01-30', //
      '2026-02-26', '2026-02-27',
    ];
    for (var i = 0; i < dias.length; i++) {
      await db.into(db.dailyLogs).insert(DailyLogsCompanion.insert(
            date: dias[i],
            isPeriodDay: const Value(true),
            flow: Value(i.isEven ? FlowIntensity.moderado : FlowIntensity.abundante),
            mood: Value(i == 0 ? Mood.cansada : null),
          ));
    }
    await db.into(db.dailyLogSymptoms).insert(DailyLogSymptomsCompanion.insert(
          logDate: '2026-01-01',
          symptom: Symptom.dolorAbdominal,
        ));
    await pumpStats(tester);

    expect(find.text('Aún no hay registros guardados 🩷'), findsNothing);
    expect(find.text('Promedio de flujo'), findsOneWidget);
    expect(find.text('Abundante'), findsOneWidget);
    expect(find.text('Síntomas más frecuentes'), findsOneWidget);
    expect(find.byType(BarChart), findsOneWidget);
    expect(find.text(Symptom.dolorAbdominal.label), findsOneWidget);
    expect(find.text('Estados de ánimo registrados'), findsOneWidget);
    expect(find.byType(PieChart), findsOneWidget);

    // Hoy no hay ninguna seccion de ciclos ni el texto de R-7.
    expect(find.textContaining('ciclo'), findsNothing);
    expect(find.textContaining('Ciclo'), findsNothing);
    expect(find.textContaining('Según tu ajuste'), findsNothing);
    expect(find.textContaining('Regularidad'), findsNothing);
  });

  testStats('solo un dia sin flujo: "Sin datos" y sin graficos',
      (tester) async {
    await db.into(db.dailyLogs).insert(DailyLogsCompanion.insert(
          date: '2026-01-01',
          isPeriodDay: const Value(true),
        ));
    await pumpStats(tester);
    expect(find.text('Promedio de flujo'), findsOneWidget);
    expect(find.text('Sin datos'), findsOneWidget);
    expect(find.byType(BarChart), findsNothing);
    expect(find.byType(PieChart), findsNothing);
  });
}
