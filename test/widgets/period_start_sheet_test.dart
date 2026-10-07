import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/models/day_enums.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/domain/current_period.dart';
import 'package:aura/domain/cycle_predictor.dart';
import 'package:aura/widgets/period_start_sheet.dart';

/// Hoja "Me llego hoy" (HU-02), abierta solo desde un boton de prueba:
/// todavia no esta conectada a Inicio ni al Calendario (CP3b y CP4).
/// Fechas inventadas; "hoy" es el 15 de julio de 2026.
void main() {
  late AppDatabase db;
  late CycleRepository repo;

  const today = '2026-07-15';
  const yesterday = '2026-07-14';

  setUpAll(() async {
    await initializeDateFormatting();
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CycleRepository(db);
  });

  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () =>
                  showPeriodStartSheet(context, repository: repo, today: today),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.text('Marcar mi período'));
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

  Future<List<String>> markedDays() async =>
      (await repo.getPeriodDayDates())..sort();

  bool confirmEnabled(WidgetTester tester) =>
      tester
          .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Marcar mi período'))
          .onPressed !=
      null;

  testWidgets('muestra el titulo, las tres opciones, la duracion estimada y '
      'la nota', (tester) async {
    await openSheet(tester);

    expect(find.text('¿Cuándo empezó tu período?'), findsOneWidget);
    expect(find.text('Hoy'), findsOneWidget);
    expect(find.text('Ayer'), findsOneWidget);
    expect(find.text('Otro día'), findsOneWidget);
    expect(
        find.text('Duración estimada: 5 días (puedes cambiarla en Ajustes)'),
        findsOneWidget);
    expect(find.textContaining('Solo se guarda el primer día'),
        findsOneWidget);
    await db.close();
  });

  testWidgets('la duracion estimada sale del ajuste guardado y usa "1 dia"',
      (tester) async {
    await repo.setTypicalPeriodLength(1);
    await openSheet(tester);
    expect(
        find.text('Duración estimada: 1 día (puedes cambiarla en Ajustes)'),
        findsOneWidget);
    await db.close();
  });

  testWidgets('Hoy esta elegido por defecto y marca solo hoy', (tester) async {
    await openSheet(tester);
    await confirm(tester);

    expect(await markedDays(), [today]);
    expect((await repo.getDay(today))!.periodEnd, isNull);
    expect(find.text('Inicio del período registrado.'), findsOneWidget);
    expect(find.text('Deshacer'), findsOneWidget);
    await db.close();
  });

  testWidgets('Ayer marca solo ayer', (tester) async {
    await openSheet(tester);
    await tester.tap(find.text('Ayer'));
    await tester.pumpAndSettle();
    await confirm(tester);

    expect(await markedDays(), [yesterday]);
    await db.close();
  });

  testWidgets('Otro dia abre el selector, que termina en hoy, y marca el dia '
      'elegido', (tester) async {
    await openSheet(tester);
    await tester.tap(find.text('Otro día'));
    await tester.pumpAndSettle();

    final picker =
        tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    expect(picker.lastDate, DateTime(2026, 7, 15));
    await tester.tap(find.text('10'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.textContaining('10 de julio'), findsOneWidget);
    await confirm(tester);
    expect(await markedDays(), ['2026-07-10']);
    await db.close();
  });

  testWidgets('un dia futuro no se puede elegir', (tester) async {
    await openSheet(tester);
    await tester.tap(find.text('Otro día'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('16'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await confirm(tester);

    expect(await markedDays(), isNot(contains('2026-07-16')));
    expect(await markedDays(), [today]);
    await db.close();
  });

  testWidgets('cancelar el selector de Otro dia vuelve a la opcion anterior',
      (tester) async {
    await openSheet(tester);
    await tester.tap(find.text('Ayer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Otro día'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await confirm(tester);

    expect(await markedDays(), [yesterday]);
    await db.close();
  });

  testWidgets('cerrar la hoja sin confirmar no escribe nada', (tester) async {
    final before = await dump();
    await openSheet(tester);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('¿Cuándo empezó tu período?'), findsNothing);
    expect(await dump(), before);
    await db.close();
  });

  testWidgets('decision 7: avisa si el dia se sumaria al periodo anterior, '
      'sin bloquear', (tester) async {
    await repo.markPeriodDays(['2026-07-06', '2026-07-07', '2026-07-08']);
    await openSheet(tester);

    expect(find.textContaining('se sumará a ese período'), findsOneWidget);
    expect(find.textContaining('8 de julio'), findsOneWidget);
    expect(confirmEnabled(tester), isTrue);

    await confirm(tester);
    expect((await repo.getDerivedCycles()).single.periodLengthDays, 10);
    await db.close();
  });

  testWidgets('decision 7: sin aviso si el periodo anterior quedo a mas de 7 '
      'dias', (tester) async {
    await repo.markPeriodDays(['2026-07-06', '2026-07-07']);
    await openSheet(tester);
    expect(find.textContaining('se sumará a ese período'), findsNothing);
    await db.close();
  });

  testWidgets('un dia ya marcado: avisa y no deja confirmar ni escribe',
      (tester) async {
    await repo.markPeriodDays([yesterday]);
    final before = await dump();
    await openSheet(tester);
    await tester.tap(find.text('Ayer'));
    await tester.pumpAndSettle();

    expect(find.text('Ese día ya está registrado.'), findsOneWidget);
    expect(confirmEnabled(tester), isFalse);
    expect(await dump(), before);
    await db.close();
  });

  testWidgets('Deshacer deja la base exactamente como estaba',
      (tester) async {
    await repo.markPeriodDays(['2026-06-01', '2026-06-02']);
    await db.into(db.dailyLogs).insert(DailyLogsCompanion.insert(
          date: today,
          mood: const Value(Mood.cansada),
          notes: const Value('nota inventada'),
        ));
    final before = await dump();
    await openSheet(tester);
    await confirm(tester);
    expect(await dump(), isNot(before));

    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();

    expect(await dump(), before);
    await db.close();
  });

  testWidgets('no toca animo, notas ni sintomas del dia marcado',
      (tester) async {
    await repo.upsertDay(
      date: today,
      isPeriodDaySwitch: false,
      mood: Mood.irritable,
      notes: 'nota inventada',
      symptoms: {Symptom.dolorDeCabeza, Symptom.antojos},
    );
    await openSheet(tester);
    await confirm(tester);

    final day = await repo.getDay(today);
    expect(day!.isPeriodDay, isTrue);
    expect(day.mood, Mood.irritable);
    expect(day.notes, 'nota inventada');
    expect(day.flow, isNull);
    expect(await repo.getSymptomsForDay(today),
        {Symptom.dolorDeCabeza, Symptom.antojos});
    await db.close();
  });

  testWidgets('accesibilidad: opciones y boton con etiqueta y 48 dp',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await openSheet(tester);

    for (final label in ['Hoy', 'Ayer', 'Otro día', 'Marcar mi período']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    for (final finder in [
      find.widgetWithText(RadioListTile<PeriodStartOption>, 'Hoy'),
      find.widgetWithText(RadioListTile<PeriodStartOption>, 'Ayer'),
      find.widgetWithText(RadioListTile<PeriodStartOption>, 'Otro día'),
      find.widgetWithText(FilledButton, 'Marcar mi período'),
    ]) {
      expect(tester.getSize(finder).height, greaterThanOrEqualTo(48));
    }

    semantics.dispose();
    await db.close();
  });

  testWidgets('decision 7 hacia adelante: avisa si el dia elegido queda a 7 '
      'dias o menos antes de un periodo posterior', (tester) async {
    await repo.markPeriodDays(['2026-07-12', '2026-07-13']);
    await openSheet(tester);
    await tester.tap(find.text('Otro día'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(
        find.text('Ese día está muy cerca de tu período que empezó el 12 de '
            'julio, así que se sumará a ese período.'),
        findsOneWidget);
    expect(confirmEnabled(tester), isTrue);
    await confirm(tester);
    final cycle = (await repo.getDerivedCycles()).single;
    expect(cycle.startDate, '2026-07-05');
    await db.close();
  });

  testWidgets('decision 7: entre dos periodos cercanos avisa que se unen',
      (tester) async {
    await repo.markPeriodDays(['2026-07-01', '2026-07-02', '2026-07-12']);
    await openSheet(tester);
    await tester.tap(find.text('Otro día'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('7'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.textContaining('los dos se unirán en un solo período'),
        findsOneWidget);
    await db.close();
  });

  testWidgets('la duracion de la hoja es la misma que usan los dias estimados '
      '(el ajuste), aunque el promedio de periodos cerrados sea otro',
      (tester) async {
    // Historia inventada: dos periodos cerrados de 3 dias, ajuste en 7.
    await repo.markPeriodDays(['2026-05-01', '2026-05-02', '2026-05-03']);
    await repo.setPeriodDayExplicitly('2026-05-04', isPeriodDay: false);
    await repo.markPeriodDays(['2026-06-01', '2026-06-02', '2026-06-03']);
    await repo.setPeriodDayExplicitly('2026-06-04', isPeriodDay: false);
    await repo.setTypicalPeriodLength(7);
    await openSheet(tester);

    expect(
        find.text('Duración estimada: 7 días (puedes cambiarla en Ajustes)'),
        findsOneWidget);
    await confirm(tester);

    final inputs = await repo.getPredictionInputs();
    final estimated = estimatedPeriodDays(
      cycles: inputs.cycles,
      typicalPeriodLengthDays: inputs.typicalPeriodLengthDays,
      today: today,
    );
    // Hoy marcado + 6 estimados = los 7 dias que dijo la hoja.
    expect(estimated.length + 1, 7);
    expect(estimated.last, '2026-07-21');
    // El promedio del predictor (fases) es otro numero: 3.
    final prediction = predictCycle(
        cycles: inputs.cycles, today: today, config: inputs.config);
    expect((prediction! as ActivePrediction).averagePeriodLengthDays, 3);
    await db.close();
  });
}
