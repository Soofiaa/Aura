import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/models/day_enums.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/screens/add_cycle_screen.dart';
import 'package:aura/screens/stats_screen.dart';
import 'package:aura/utils/app_snackbar.dart';
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

/// true si el chip del sintoma [label] se ve marcado (icono de check).
bool _sintomaMarcado(WidgetTester tester, String label) {
  final chip = find.ancestor(
    of: find.text(label),
    matching: find.byType(GestureDetector),
  );
  final icono = tester.widget<Icon>(
    find.descendant(of: chip.first, matching: find.byType(Icon)),
  );
  return icono.icon == Icons.check_circle;
}

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

  testWidgets(
      'cambiar la fecha a un dia sin registro no arrastra el animo ni el '
      'flujo del dia anterior', (tester) async {
    await repo.upsertDay(
      date: hoy,
      isPeriodDaySwitch: true,
      flow: FlowIntensity.moderado,
      mood: Mood.feliz,
    );

    await _abrirFormulario(tester);
    expect(find.text('Feliz'), findsOneWidget);
    expect(find.text('Moderado'), findsOneWidget);

    // Dia 15 del mes anterior: siempre pasado y sin registro.
    await _tocar(tester, find.byIcon(Icons.calendar_today));
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<DropdownButton<Mood?>>(find.byType(DropdownButton<Mood?>))
          .value,
      isNull,
    );
    expect(find.text('Sin registrar'), findsOneWidget);
    expect(find.text('Feliz'), findsNothing);
    expect(_interruptorEncendido(tester), isFalse);

    await _tocar(tester, find.byType(Switch));
    expect(
      tester
          .widget<DropdownButton<FlowIntensity?>>(
              find.byType(DropdownButton<FlowIntensity?>))
          .value,
      isNull,
    );
    expect(find.text('Sin especificar'), findsOneWidget);
    expect(find.text('Moderado'), findsNothing);
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
    await tester.pump(snackBarDuration + const Duration(seconds: 1));
    await tester.pumpAndSettle();

    await _abrirFormulario(tester);
    await _tocar(tester, find.text('Moderado'));
    await _tocar(tester, find.text('Sin especificar').last);
    await _guardar(tester);

    final row = await repo.getDay(hoy);
    expect(row!.isPeriodDay, isTrue);
    expect(row.flow, isNull);
  });

  testWidgets('el interruptor "Día de sangrado" usa el estilo del tema',
      (tester) async {
    await _abrirFormulario(tester);
    final interruptor = tester.widget<Switch>(find.byType(Switch));
    expect(interruptor.activeThumbColor, isNull);
    expect(interruptor.activeTrackColor, isNull);
  });

  testWidgets('el titulo es "Registrar día", igual que el boton de Inicio',
      (tester) async {
    await _abrirFormulario(tester);
    expect(
      find.descendant(
          of: find.byType(AppBar), matching: find.text('Registrar día')),
      findsOneWidget,
    );
    expect(find.text('Registrar síntomas'), findsNothing);
  });

  testWidgets(
      'un dia con sintomas guardados se abre con esos sintomas marcados',
      (tester) async {
    await repo.upsertDay(
      date: hoy,
      isPeriodDaySwitch: false,
      symptoms: {Symptom.cansancio, Symptom.dolorDeCabeza},
    );

    // El formulario carga el dia de forma asincrona, despues de
    // construir el selector: los sintomas llegan tarde y deben verse.
    await _abrirFormulario(tester);

    expect(_sintomaMarcado(tester, 'Cansancio'), isTrue);
    expect(_sintomaMarcado(tester, 'Dolor de cabeza'), isTrue);
    expect(_sintomaMarcado(tester, 'Dolor abdominal'), isFalse);
    expect(_sintomaMarcado(tester, 'Antojos'), isFalse);
  });

  testWidgets(
      'en un dia guardado se puede desmarcar y marcar sintomas, y se guarda '
      'exactamente lo que se ve', (tester) async {
    await repo.upsertDay(
      date: hoy,
      isPeriodDaySwitch: false,
      symptoms: {Symptom.cansancio, Symptom.dolorDeCabeza},
    );

    await _abrirFormulario(tester);
    await _tocar(tester, find.text('Cansancio'));
    await _tocar(tester, find.text('Antojos'));

    expect(_sintomaMarcado(tester, 'Cansancio'), isFalse);
    expect(_sintomaMarcado(tester, 'Antojos'), isTrue);
    expect(_sintomaMarcado(tester, 'Dolor de cabeza'), isTrue);

    await _guardar(tester);

    expect(await repo.getSymptomsForDay(hoy),
        {Symptom.dolorDeCabeza, Symptom.antojos});
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

  // #9: sin desbordes a 360 x 640 con letra grande (menus, fecha y chips).
  group('360 x 640 sin desbordes', () {
    for (final guardado in [false, true]) {
      for (final escala in [1.0, 1.3, 1.5, 2.0]) {
        testWidgets(
            '${guardado ? 'dia guardado (sangrado, todos los sintomas)' : 'dia vacio'}'
            ', texto $escala', (tester) async {
          if (guardado) {
            await repo.upsertDay(
              date: hoy,
              isPeriodDaySwitch: true,
              flow: FlowIntensity.abundante,
              mood: Mood.irritable,
              notes: 'Nota de prueba',
              symptoms: Symptom.values.toSet(),
            );
          }
          tester.view.physicalSize = const Size(360, 640);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = escala;
          addTearDown(tester.view.reset);
          addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpWidget(const MaterialApp(home: AddCycleScreen()));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (guardado) {
            expect(find.text('Abundante'), findsOneWidget);
            expect(find.text('Irritable'), findsOneWidget);
          }
        });
      }
    }
  });

  // #11: un dia sin registro que se guarda vacio no crea una fila.
  group('registro vacio', () {
    const nada = 'No había nada para guardar.';
    const guardado = 'Registro guardado correctamente ✅';

    // Como _abrirFormulario, pero la ruta base tiene Scaffold para ver el
    // aviso que se muestra al volver.
    Future<void> abrir(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddCycleScreen()),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    Future<void> elegir(WidgetTester tester, String menu, String opcion) async {
      await _tocar(tester, find.text(menu));
      await tester.tap(find.text(opcion).last);
      await tester.pumpAndSettle();
    }

    Future<void> notas(WidgetTester tester, String texto) async {
      final campo = find.byType(TextFormField);
      await tester.ensureVisible(campo);
      await tester.enterText(campo, texto);
      await tester.pumpAndSettle();
    }

    testWidgets('dia nuevo sin nada: no crea fila y avisa', (tester) async {
      await abrir(tester);
      await _guardar(tester);

      expect(await repo.getDay(hoy), isNull);
      expect(await repo.hasAnyLog(), isFalse);
      expect(find.text(nada), findsOneWidget);
      expect(find.text(guardado), findsNothing);
      expect(find.byType(AddCycleScreen), findsNothing); // se cerro
    });

    testWidgets('dia nuevo, solo notas: se guarda', (tester) async {
      await abrir(tester);
      await notas(tester, 'Algo de cansancio');
      await _guardar(tester);
      expect((await repo.getDay(hoy))!.notes, 'Algo de cansancio');
      expect(find.text(guardado), findsOneWidget);
    });

    testWidgets('dia nuevo, solo un sintoma: se guarda', (tester) async {
      await abrir(tester);
      await _tocar(tester, find.text('Antojos'));
      await _guardar(tester);
      expect(await repo.getDay(hoy), isNotNull);
      expect(await repo.getSymptomsForDay(hoy), {Symptom.antojos});
    });

    testWidgets('dia nuevo, solo animo: se guarda', (tester) async {
      await abrir(tester);
      await elegir(tester, 'Sin registrar', 'Feliz');
      await _guardar(tester);
      expect((await repo.getDay(hoy))!.mood, Mood.feliz);
    });

    testWidgets('dia nuevo, solo sangrado (sin flujo): se guarda',
        (tester) async {
      await abrir(tester);
      await _tocar(tester, find.byType(Switch));
      await _guardar(tester);
      final row = await repo.getDay(hoy);
      expect(row!.isPeriodDay, isTrue);
      expect(row.flow, isNull);
    });

    testWidgets(
        'dia con "no hubo sangrado" explicito, guardado sin tocar: se '
        'conserva', (tester) async {
      await repo.markPeriodDays([hoy]);
      await repo.setPeriodDayExplicitly(hoy, isPeriodDay: false);
      expect((await repo.getDay(hoy))!.periodDayExplicit, isTrue);

      await abrir(tester);
      await _guardar(tester);
      final row = await repo.getDay(hoy);
      expect(row, isNotNull);
      expect(row!.isPeriodDay, isFalse);
      expect(row.periodDayExplicit, isTrue);
      expect(find.text(guardado), findsOneWidget);
    });

    testWidgets('dia de sangrado: apagar el interruptor deja el "no"',
        (tester) async {
      await repo.upsertDay(date: hoy, isPeriodDaySwitch: true);
      await abrir(tester);
      expect(_interruptorEncendido(tester), isTrue);
      await _tocar(tester, find.byType(Switch));
      await _guardar(tester);
      final row = await repo.getDay(hoy);
      expect(row!.isPeriodDay, isFalse);
      expect(row.periodDayExplicit, isTrue);
    });

    testWidgets(
        'dia existente: borrar sus notas y sintomas se guarda (fila vacia a '
        'proposito)', (tester) async {
      await repo.upsertDay(
        date: hoy,
        isPeriodDaySwitch: false,
        notes: 'Antes',
        symptoms: {Symptom.acne},
      );
      await abrir(tester);
      await notas(tester, '');
      await _tocar(tester, find.text('Acné'));
      await _guardar(tester);
      final row = await repo.getDay(hoy);
      expect(row, isNotNull);
      expect(row!.notes, '');
      expect(await repo.getSymptomsForDay(hoy), isEmpty);
      expect(find.text(guardado), findsOneWidget);
    });

    testWidgets('dia nuevo: escribir una nota y borrarla no crea fila',
        (tester) async {
      await abrir(tester);
      await notas(tester, 'borrador');
      await notas(tester, '');
      await _guardar(tester);
      expect(await repo.getDay(hoy), isNull);
      expect(find.text(nada), findsOneWidget);
    });

    testWidgets('dia nuevo: notas solo con espacios cuentan como vacias',
        (tester) async {
      await abrir(tester);
      await notas(tester, '   ');
      await _guardar(tester);
      expect(await repo.getDay(hoy), isNull);
      expect(find.text(nada), findsOneWidget);
    });

    testWidgets(
        'dia nuevo: un flujo elegido con el sangrado luego apagado no '
        'cuenta ni se guarda', (tester) async {
      await abrir(tester);
      await _tocar(tester, find.byType(Switch));
      await elegir(tester, 'Sin especificar', 'Abundante');
      await _tocar(tester, find.byType(Switch));
      await _guardar(tester);
      expect(await repo.getDay(hoy), isNull);
      expect(find.text(nada), findsOneWidget);
    });

    testWidgets('Estadisticas sigue en estado vacio tras guardar vacio',
        (tester) async {
      await abrir(tester);
      await _guardar(tester);
      await tester.pumpWidget(const MaterialApp(home: StatsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Aún no hay registros guardados 🩷'), findsOneWidget);
      // Estadisticas observa la base: se cierra dentro del test (en
      // tearDown quedan timers de drift pendientes).
      await db.close();
    });
  });
}
