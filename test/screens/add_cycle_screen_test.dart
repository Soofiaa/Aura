import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/models/day_enums.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/screens/add_cycle_screen.dart';
import 'package:aura/utils/day_key.dart';

/// AddCycleScreen hace Navigator.pop al guardar, asi que se abre desde
/// una ruta base (como desde Inicio) en vez de usarla como home.
Future<void> _abrirFormulario(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddCycleScreen()),
        ),
        child: const Text('abrir'),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

Future<void> _tocar(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _guardar(WidgetTester tester) =>
    _tocar(tester, find.text('Guardar registro'));

bool _interruptorEncendido(WidgetTester tester) =>
    tester.widget<Switch>(find.byType(Switch)).value;

List<String> _resumen(List<dynamic> ciclos) =>
    ciclos.map((c) => '${c.startDate}/${c.periodLengthDays}').toList();

void main() {
  late AppDatabase db;
  late CycleRepository repo;
  final hoy = DayKey.today();

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CycleRepository(db);
    cycleRepository = repo;
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets(
      'B-1: registrar solo un sintoma en un dia nuevo no lo marca como '
      'sangrado ni crea un periodo', (tester) async {
    await repo.markPeriodDays([
      for (var i = 20; i >= 17; i--) DayKey.addDays(hoy, -i),
    ]);
    final ciclosAntes = _resumen(await repo.getDerivedCycles());

    await _abrirFormulario(tester);
    await _tocar(tester, find.text('Dolor de cabeza'));
    await _guardar(tester);

    final row = await repo.getDay(hoy);
    expect(row, isNotNull);
    expect(row!.isPeriodDay, isFalse);
    expect(row.flow, isNull);
    expect(await repo.getSymptomsForDay(hoy), {Symptom.dolorDeCabeza});
    expect(_resumen(await repo.getDerivedCycles()), ciclosAntes);
  });

  // Un "no" explicito cierra el periodo previo (periodConfirmedEnded en
  // cycle_deriver): solo debe escribirse al apagar el interruptor sobre
  // un dia que ya era de sangrado, nunca al registrar otra cosa.
  final soloOtroDato = <String, Future<void> Function(WidgetTester)>{
    'un sintoma': (tester) => _tocar(tester, find.text('Dolor de cabeza')),
    'un estado de animo': (tester) async {
      await _tocar(tester, find.text('Sin registrar'));
      await _tocar(tester, find.text('Feliz').last);
    },
    'una nota': (tester) async {
      await tester.enterText(find.byType(TextFormField), 'Solo una nota');
      await tester.pumpAndSettle();
    },
  };
  soloOtroDato.forEach((que, registrar) {
    testWidgets(
        'registrar solo $que en un dia nuevo con el interruptor apagado no '
        'guarda un "no" explicito', (tester) async {
      await repo.markPeriodDays([DayKey.addDays(hoy, -3)]);

      await _abrirFormulario(tester);
      expect(_interruptorEncendido(tester), isFalse);
      await registrar(tester);
      await _guardar(tester);

      final row = await repo.getDay(hoy);
      expect(row!.isPeriodDay, isFalse);
      expect(row.periodDayExplicit, isFalse);
      final ciclos = await repo.getDerivedCycles();
      expect(ciclos.last.periodConfirmedEnded, isFalse);
    });
  });

  testWidgets(
      'agregar un sintoma a un dia marcado sin tocar el interruptor lo deja '
      'como sangrado y sin "no" explicito', (tester) async {
    await repo.markPeriodDay(hoy);

    await _abrirFormulario(tester);
    await _tocar(tester, find.text('Dolor de cabeza'));
    await _guardar(tester);

    final row = await repo.getDay(hoy);
    expect(row!.isPeriodDay, isTrue);
    expect(row.periodDayExplicit, isFalse);
    expect(await repo.getPeriodDayDates(), [hoy]);
  });

  testWidgets(
      'B-2: encender el sangrado sin elegir flujo guarda flujo null y no '
      'altera el promedio', (tester) async {
    for (var i = 30; i >= 28; i--) {
      await repo.upsertDay(
        date: DayKey.addDays(hoy, -i),
        isPeriodDaySwitch: true,
        flow: FlowIntensity.abundante,
      );
    }
    expect(await repo.getAverageFlow(), 3.0);

    await _abrirFormulario(tester);
    await _tocar(tester, find.byType(Switch));
    await _guardar(tester);

    final row = await repo.getDay(hoy);
    expect(row!.isPeriodDay, isTrue);
    expect(row.flow, isNull);
    expect(await repo.getAverageFlow(), 3.0);
  });

  testWidgets(
      'B-2: agregar un sintoma a un dia marcado en el calendario no le '
      'inventa un flujo', (tester) async {
    await repo.markPeriodDay(hoy);

    await _abrirFormulario(tester);
    expect(_interruptorEncendido(tester), isTrue);
    await _tocar(tester, find.text('Dolor de cabeza'));
    await _guardar(tester);

    final row = await repo.getDay(hoy);
    expect(row!.isPeriodDay, isTrue);
    expect(row.flow, isNull);
  });

  testWidgets('un dia con flujo guardado se abre con el interruptor y el flujo',
      (tester) async {
    await repo.upsertDay(
      date: hoy,
      isPeriodDaySwitch: true,
      flow: FlowIntensity.moderado,
    );

    await _abrirFormulario(tester);

    expect(_interruptorEncendido(tester), isTrue);
    expect(find.text('Moderado'), findsOneWidget);
  });

  testWidgets(
      'cambiar la fecha a un dia sin registro apaga el interruptor y oculta '
      'el flujo', (tester) async {
    await repo.upsertDay(
      date: hoy,
      isPeriodDaySwitch: true,
      flow: FlowIntensity.moderado,
    );

    await _abrirFormulario(tester);
    expect(_interruptorEncendido(tester), isTrue);

    // Dia 15 del mes anterior: siempre pasado y sin registro.
    await _tocar(tester, find.byIcon(Icons.calendar_today));
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(_interruptorEncendido(tester), isFalse);
    expect(find.text('Flujo menstrual'), findsNothing);
  });

  testWidgets('apagar el interruptor en un dia marcado lo guarda como un "no" '
      'explicito', (tester) async {
    await repo.markPeriodDay(hoy);

    await _abrirFormulario(tester);
    await _tocar(tester, find.byType(Switch));
    await _guardar(tester);

    final row = await repo.getDay(hoy);
    expect(row!.isPeriodDay, isFalse);
    expect(row.flow, isNull);
    expect(row.periodDayExplicit, isTrue);
  });

  testWidgets('elegir un flujo lo guarda y "Sin especificar" lo vuelve a null',
      (tester) async {
    await _abrirFormulario(tester);
    await _tocar(tester, find.byType(Switch));
    await _tocar(tester, find.text('Sin especificar'));
    await _tocar(tester, find.text('Moderado').last);
    await _guardar(tester);

    expect((await repo.getDay(hoy))!.flow, FlowIntensity.moderado);

    // Espera a que se vaya el SnackBar del primer guardado: si no, tapa
    // el boton "Guardar registro" de la segunda apertura.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await _abrirFormulario(tester);
    await _tocar(tester, find.text('Moderado'));
    await _tocar(tester, find.text('Sin especificar').last);
    await _guardar(tester);

    final row = await repo.getDay(hoy);
    expect(row!.isPeriodDay, isTrue);
    expect(row.flow, isNull);
  });

  testWidgets(
      'B-3: guardar sin tocar el estado de animo no registra "Normal"',
      (tester) async {
    await _abrirFormulario(tester);
    await _tocar(tester, find.text('Dolor de cabeza'));
    await _guardar(tester);

    expect((await repo.getDay(hoy))!.mood, isNull);
    expect(await repo.getMoodFrequency(), isEmpty);
  });

  testWidgets('el selector de fecha no permite elegir dias futuros',
      (tester) async {
    await _abrirFormulario(tester);
    await _tocar(tester, find.byIcon(Icons.calendar_today));

    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(picker.lastDate, DateUtils.dateOnly(DateTime.now()));
  });
}
