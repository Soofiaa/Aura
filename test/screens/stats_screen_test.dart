import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/models/day_enums.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/domain/cycle_predictor.dart';
import 'package:aura/screens/stats_screen.dart';
import 'package:aura/utils/day_key.dart';

/// HU-05, CP1: caracterizacion de Estadisticas (flujo, sintomas y
/// animo). CP4: seccion "Tus ciclos". Datos inventados.
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
    expect(find.text('Tus ciclos'), findsNothing);
    expect(find.byType(BarChart), findsNothing);
    expect(find.byType(PieChart), findsNothing);
  });

  testStats('con datos: tus ciclos, promedio de flujo, sintomas y animo',
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

    // CP4: ahora si hay seccion de ciclos (2 ciclos de 28; periodos
    // abiertos, asi que la duracion del periodo sale del ajuste).
    expect(find.text('Tus ciclos'), findsOneWidget);
    expect(find.text('Ciclos considerados: 2'), findsOneWidget);
    expect(find.text('Duración típica del ciclo: 28 días'), findsOneWidget);
    expect(find.text('Regularidad: Regular'), findsOneWidget);
    expect(
        find.text('Duración típica del período: 5 días (según tu ajuste)'),
        findsOneWidget);
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
    // CP4: un periodo registrado ya muestra "Tus ciclos".
    expect(find.text('Registra al menos dos períodos para ver tus ciclos.'),
        findsOneWidget);
  });

  // --- HU-05, CP4: "Tus ciclos" ---

  /// Inserta un periodo de [days] dias desde [start]. Si [closed], su
  /// ultimo dia lleva period_end (cuenta para la duracion del periodo).
  Future<void> period(String start, {int days = 3, bool closed = false}) async {
    for (var i = 0; i < days; i++) {
      await db.into(db.dailyLogs).insert(DailyLogsCompanion.insert(
            date: DayKey.addDays(start, i),
            isPeriodDay: const Value(true),
            periodEnd: Value(
                closed && i == days - 1 ? PeriodEndSource.declared : null),
          ));
    }
  }

  /// Un periodo al inicio de cada ciclo de [lengths] y uno mas al final.
  Future<void> periodsEvery(String start, List<int> lengths,
      {int days = 3, bool closed = false}) async {
    var day = start;
    for (final length in [...lengths, null]) {
      await period(day, days: days, closed: closed);
      if (length != null) day = DayKey.addDays(day, length);
    }
  }

  const registra = 'Registra al menos dos períodos para ver tus ciclos.';
  const conDos = 'Con dos ciclos o más calculamos tu duración típica y tu '
      'regularidad.';

  testStats('sin periodos (solo animo): sin "Tus ciclos"', (tester) async {
    await db.into(db.dailyLogs).insert(DailyLogsCompanion.insert(
          date: '2026-03-01',
          mood: const Value(Mood.feliz),
        ));
    await pumpStats(tester);
    expect(find.text('Promedio de flujo'), findsOneWidget);
    expect(find.text('Tus ciclos'), findsNothing);
  });

  testStats('0 ciclos (un periodo): pide dos periodos, arriba del flujo',
      (tester) async {
    await period('2026-03-01');
    await pumpStats(tester);
    expect(find.text('Tus ciclos'), findsOneWidget);
    expect(find.text(registra), findsOneWidget);
    expect(
        find.text('Duración típica del período: 5 días (según tu ajuste)'),
        findsOneWidget);
    expect(find.textContaining('Ciclos considerados'), findsNothing);
    expect(find.textContaining('Regularidad'), findsNothing);
    expect(tester.getTopLeft(find.text('Tus ciclos')).dy,
        lessThan(tester.getTopLeft(find.text('Promedio de flujo')).dy));
  });

  testStats('1 ciclo: su duracion y el texto de dos ciclos; periodo segun '
      'tu ajuste', (tester) async {
    await repo.setTypicalPeriodLength(7);
    await periodsEvery('2026-03-01', [29]);
    await pumpStats(tester);
    expect(find.text('Ciclos considerados: 1'), findsOneWidget);
    expect(find.text('Tu único ciclo completo: 29 días'), findsOneWidget);
    expect(find.text(conDos), findsOneWidget);
    expect(
        find.text('Duración típica del período: 7 días (según tu ajuste)'),
        findsOneWidget);
    expect(find.text(registra), findsNothing);
    expect(find.textContaining('Duración típica del ciclo'), findsNothing);
    expect(find.textContaining('Regularidad'), findsNothing);
  });

  testStats('2+ ciclos: todas las filas; periodo segun tus periodos',
      (tester) async {
    // [26, 30, 28]: media (26 + 60 + 84) / 6 = 28,33 -> 28; razon 0,05.
    await periodsEvery('2026-01-01', [26, 30, 28], days: 4, closed: true);
    await pumpStats(tester);
    final filas = [
      'Ciclos considerados: 3',
      'Duración típica del ciclo: 28 días',
      'Más corto y más largo: 26 a 30 días',
      'Regularidad: Regular',
      'Duración típica del período: 4 días (según tus períodos)',
    ];
    for (final fila in filas) {
      expect(find.text(fila), findsOneWidget, reason: fila);
      // Cada fila es una sola frase para el lector de pantalla.
      expect(find.bySemanticsLabel(fila), findsOneWidget, reason: fila);
    }
    // En ese orden.
    final ys = [for (final f in filas) tester.getTopLeft(find.text(f)).dy];
    expect(ys, [...ys]..sort());
    expect(find.text(registra), findsNothing);
    expect(find.text(conDos), findsNothing);
    expect(find.textContaining('Tu único ciclo'), findsNothing);
    expect(find.textContaining('no se cuenta'), findsNothing);
  });

  testStats('2+ ciclos iguales: "Más corto y más largo: N días"; muy '
      'variable', (tester) async {
    await periodsEvery('2026-01-01', [28, 28]);
    await pumpStats(tester);
    expect(find.text('Más corto y más largo: 28 días'), findsOneWidget);
    await repo.deleteAllData();
    await periodsEvery('2025-06-01', [22, 34, 22, 34, 22, 34]);
    await tester.pumpAndSettle();
    expect(find.text('Más corto y más largo: 22 a 34 días'), findsOneWidget);
    expect(find.text('Regularidad: Muy variable'), findsOneWidget);
  });

  testStats('con excluidos: linea gris en plural y en singular',
      (tester) async {
    await periodsEvery('2026-01-01', [14, 28, 61, 30]);
    await pumpStats(tester);
    const plural =
        '2 ciclos no se cuentan por durar menos de 15 o más de 60 días.';
    expect(find.text(plural), findsOneWidget);
    expect(find.text('Ciclos considerados: 2'), findsOneWidget);
    expect(find.text('Más corto y más largo: 28 a 30 días'), findsOneWidget);
    // grey[700]: contraste >= 4,5:1 sobre blanco.
    expect(tester.widget<Text>(find.text(plural)).style!.color,
        Colors.grey[700]);

    await repo.deleteAllData();
    await periodsEvery('2026-01-01', [28, 70, 30]);
    await tester.pumpAndSettle();
    expect(
        find.text(
            '1 ciclo no se cuenta por durar menos de 15 o más de 60 días.'),
        findsOneWidget);
    expect(find.text('Ciclos considerados: 2'), findsOneWidget);
  });

  testStats('todos los ciclos excluidos: 0 considerados, sin pedir dos '
      'periodos', (tester) async {
    await periodsEvery('2026-01-01', [14]);
    await pumpStats(tester);
    expect(find.text('Ciclos considerados: 0'), findsOneWidget);
    expect(find.text(conDos), findsOneWidget);
    expect(
        find.text(
            '1 ciclo no se cuenta por durar menos de 15 o más de 60 días.'),
        findsOneWidget);
    expect(find.text(registra), findsNothing);
  });

  testStats('se actualiza sola al agregar periodos', (tester) async {
    await period('2026-01-01');
    await pumpStats(tester);
    expect(find.text(registra), findsOneWidget);

    await period('2026-01-29');
    await tester.pumpAndSettle();
    expect(find.text(registra), findsNothing);
    expect(find.text('Tu único ciclo completo: 28 días'), findsOneWidget);

    await period('2026-02-28', closed: true);
    await tester.pumpAndSettle();
    expect(find.text('Ciclos considerados: 2'), findsOneWidget);
    expect(find.text('Duración típica del ciclo: 29 días'), findsOneWidget);
    expect(
        find.text('Duración típica del período: 3 días (según tus períodos)'),
        findsOneWidget);
  });

  testStats('CLAVE: la duracion tipica del ciclo es la misma que usa '
      'predictCycle', (tester) async {
    await pumpStats(tester);
    for (final lengths in [
      [28, 28],
      [26, 30, 28],
      [20, 23, 23, 32],
      [32, 37, 25],
      [22, 34, 22, 34, 22, 34],
      [26, 27, 27, 30, 26, 29, 31, 33], // solo cuentan los 6 ultimos
      [14, 28, 61, 30, 27],
    ]) {
      await repo.deleteAllData();
      await periodsEvery('2025-01-01', lengths);
      await tester.pumpAndSettle();

      final inputs = await repo.getPredictionInputs();
      final p = predictCycle(
        cycles: inputs.cycles,
        today: DayKey.addDays(inputs.cycles.last.startDate, 2),
        config: inputs.config,
      ) as ActivePrediction;
      expect(
          find.text('Duración típica del ciclo: '
              '${p.averageCycleLengthDays.round()} días'),
          findsOneWidget,
          reason: '$lengths');
      final tope = p.completeCyclesConsidered ==
              inputs.config.maxCyclesConsidered
          ? ' (los más recientes)'
          : '';
      expect(
          find.text(
              'Ciclos considerados: ${p.completeCyclesConsidered}$tope'),
          findsOneWidget,
          reason: '$lengths');
    }
  });

  testStats('con el tope de ciclos: "(los más recientes)", con 6 exactos y '
      'con 8', (tester) async {
    await periodsEvery('2025-06-01', [28, 28, 28, 28, 28, 28]);
    await pumpStats(tester);
    expect(find.text('Ciclos considerados: 6 (los más recientes)'),
        findsOneWidget);

    await repo.deleteAllData();
    await periodsEvery('2025-06-01', [28, 28, 28, 28, 28, 28, 28, 28]);
    await tester.pumpAndSettle();
    expect(find.text('Ciclos considerados: 6 (los más recientes)'),
        findsOneWidget);

    // Por debajo del tope, sin la aclaracion.
    await repo.deleteAllData();
    await periodsEvery('2025-06-01', [28, 28, 28, 28, 28]);
    await tester.pumpAndSettle();
    expect(find.text('Ciclos considerados: 5'), findsOneWidget);
    expect(find.textContaining('(los más recientes)'), findsNothing);
  });
}
