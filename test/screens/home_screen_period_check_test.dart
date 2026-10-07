import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/models/day_enums.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/screens/home_screen.dart';
import 'package:aura/utils/day_key.dart';

/// Tarjeta "¿Sigue tu periodo hoy?" (HU-03) y "Me llego hoy" en Inicio.
/// Datos inventados: dos ciclos de 28 dias y un periodo abierto que
/// empieza el 2026-02-26; "hoy" es el 2026-02-27 salvo que se diga otra
/// cosa.
void main() {
  const fakeToday = '2026-02-27';
  const card = '¿Sigue tu período hoy?';

  late AppDatabase db;
  late CycleRepository repo;

  setUpAll(() async {
    await initializeDateFormatting();
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CycleRepository(db);
  });

  // La base se cierra al final de cada test, dentro del cuerpo: cerrarla
  // en tearDown deja timers de drift pendientes y el test no termina.
  void testHome(
          String description, Future<void> Function(WidgetTester) body) =>
      testWidgets(description, (tester) async {
        await body(tester);
        await db.close();
      });

  Future<void> seedRange(String start, int length) async {
    await repo.markPeriodDays(
        [for (var i = 0; i < length; i++) DayKey.addDays(start, i)]);
  }

  /// Dos ciclos de 28 dias como historia (abiertos: el promedio de
  /// duracion sale del ajuste).
  Future<void> seedHistory() async {
    await seedRange('2026-01-01', 5);
    await seedRange('2026-01-29', 5);
  }

  Future<void> pumpHome(WidgetTester tester, [String today = fakeToday]) async {
    final date = DateTime.parse(today);
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(repository: repo, clock: () => date),
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

  Future<void> tapAndSettle(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> pickDay(WidgetTester tester, String day) async {
    await tester.tap(find.text(day));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  group('visibilidad de la tarjeta', () {
    testHome('visible en fase menstrual, periodo abierto y sin respuesta '
        'de hoy, con la linea de contexto', (tester) async {
      await seedHistory();
      await repo.markPeriodDay('2026-02-26');
      await pumpHome(tester);

      expect(find.text(card), findsOneWidget);
      expect(find.text('Día 2 de tu período · duración estimada: 5 días'),
          findsOneWidget);
      expect(find.text('Sigue'), findsOneWidget);
      expect(find.text('Terminó hoy'), findsOneWidget);
      expect(find.text('Ya terminó antes'), findsOneWidget);
      expect(find.text('Me llegó hoy'), findsNothing);
    });

    testHome('sin periodos cerrados la linea de contexto usa el ajuste; '
        'cambiarlo cambia el numero', (tester) async {
      await seedHistory();
      await repo.markPeriodDay('2026-02-26');
      await repo.setTypicalPeriodLength(7);
      await pumpHome(tester);
      expect(find.text('Día 2 de tu período · duración estimada: 7 días'),
          findsOneWidget);

      await repo.setTypicalPeriodLength(4);
      await tester.pumpAndSettle();
      expect(find.text('Día 2 de tu período · duración estimada: 4 días'),
          findsOneWidget);
    });

    testHome('con periodos cerrados de 3 dias la linea de contexto muestra '
        '3 aunque el ajuste sea 7, sin mencionar Ajustes, y el ajuste no '
        'lo cambia', (tester) async {
      // Dos periodos cerrados de 3 dias (fin declarado en su ultimo dia).
      await seedRange('2026-01-01', 3);
      await repo.closePeriod('2026-01-01', '2026-01-03', today: fakeToday);
      await seedRange('2026-01-29', 3);
      await repo.closePeriod('2026-01-29', '2026-01-31', today: fakeToday);
      await repo.markPeriodDay('2026-02-26');
      await repo.setTypicalPeriodLength(7);
      await pumpHome(tester);
      expect(find.text('Día 2 de tu período · duración estimada: 3 días'),
          findsOneWidget);
      expect(find.textContaining('Ajustes'), findsNothing);

      await repo.setTypicalPeriodLength(12);
      await tester.pumpAndSettle();
      expect(find.text('Día 2 de tu período · duración estimada: 3 días'),
          findsOneWidget);
    });

    testHome('oculta si hoy ya tiene is_period_day=true', (tester) async {
      await seedHistory();
      await repo.markPeriodDays(['2026-02-26', fakeToday]);
      await pumpHome(tester);
      expect(find.text(card), findsNothing);
    });

    testHome('oculta si hoy ya tiene un "No" explicito', (tester) async {
      await seedHistory();
      await repo.markPeriodDay('2026-02-26');
      await repo.setPeriodDayExplicitly(fakeToday, isPeriodDay: false);
      await pumpHome(tester);
      expect(find.text(card), findsNothing);
    });

    testHome('oculta si el periodo actual esta cerrado (caso 13); se ve '
        '"Me llego hoy"', (tester) async {
      await seedHistory();
      await db.into(db.dailyLogs).insert(DailyLogsCompanion.insert(
            date: '2026-02-26',
            isPeriodDay: const Value(true),
            periodEnd: const Value(PeriodEndSource.declared),
          ));
      await pumpHome(tester);
      expect(find.text(card), findsNothing);
      expect(find.text('Me llegó hoy'), findsOneWidget);
    });

    testHome('oculta fuera de la fase menstrual', (tester) async {
      await seedHistory();
      await seedRange('2026-02-26', 4);
      await pumpHome(tester, '2026-03-10');
      expect(find.text(card), findsNothing);
    });

    // Periodo de 6 dias (2026-02-26 a 2026-03-03), mas largo que la fase
    // menstrual del predictor (5 dias: historia sin periodos cerrados, asi
    // que usa la duracion habitual).
    testHome('visible fuera de la fase menstrual si el ultimo dia marcado '
        'es ayer', (tester) async {
      await seedHistory();
      await seedRange('2026-02-26', 6);
      await pumpHome(tester, '2026-03-04');
      expect(find.text(card), findsOneWidget);
      expect(find.text('Día 7 de tu período · duración estimada: 5 días'),
          findsOneWidget);
    });

    testHome('oculta fuera de la fase menstrual si el ultimo dia marcado '
        'es de hace 2 dias', (tester) async {
      await seedHistory();
      await seedRange('2026-02-26', 6);
      await pumpHome(tester, '2026-03-05');
      expect(find.text(card), findsNothing);
    });

    testHome('fuera de la fase menstrual con el ultimo dia marcado ayer: '
        'tras "Sigue" se oculta por hoy', (tester) async {
      await seedHistory();
      await seedRange('2026-02-26', 6);
      await pumpHome(tester, '2026-03-04');
      await tapAndSettle(tester, 'Sigue');
      expect(find.text(card), findsNothing);
      final row = await (db.select(db.dailyLogs)
            ..where((t) => t.date.equals('2026-03-04')))
          .getSingle();
      expect(row.isPeriodDay, isTrue);
    });

    testHome('oculta si no hay periodo actual aunque la fase sea menstrual '
        '(ultimo dia marcado hace mas de 7 dias)', (tester) async {
      await seedHistory();
      await repo.markPeriodDay('2026-02-26');
      await repo.setTypicalPeriodLength(15);
      await pumpHome(tester, '2026-03-08');
      expect(find.text(card), findsNothing);
      expect(find.text('Me llegó hoy'), findsOneWidget);
    });

    testHome('sin datos: sin tarjeta y con "Me llego hoy"', (tester) async {
      await pumpHome(tester);
      expect(find.text(card), findsNothing);
      expect(find.text('Me llegó hoy'), findsOneWidget);
    });
  });

  group('Sigue', () {
    testHome('marca hoy, oculta la tarjeta y Deshacer deja la base '
        'exactamente igual', (tester) async {
      await seedHistory();
      await repo.markPeriodDay('2026-02-26');
      final before = await dump();
      await pumpHome(tester);

      await tapAndSettle(tester, 'Sigue');

      expect(find.text(card), findsNothing);
      expect((await repo.getDay(fakeToday))!.isPeriodDay, isTrue);
      expect(find.text('Día marcado como sangrado.'), findsOneWidget);

      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(await dump(), before);
      expect(find.text(card), findsOneWidget);
    });

    testHome('el aviso con Deshacer se cierra solo a los 8 segundos',
        (tester) async {
      await seedHistory();
      await repo.markPeriodDay('2026-02-26');
      await pumpHome(tester);

      await tapAndSettle(tester, 'Sigue');
      expect(find.text('Día marcado como sangrado.'), findsOneWidget);

      await tester.pump(const Duration(seconds: 7));
      expect(find.text('Día marcado como sangrado.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Día marcado como sangrado.'), findsNothing);
    });
  });

  group('Termino hoy', () {
    /// Periodo abierto 22-24 feb con un "No" explicito el 23 y un dia sin
    /// marcar (25) con animo, notas y sintomas; duracion habitual 7 para
    /// que el 27 siga en fase menstrual.
    Future<void> seedWithGaps() async {
      await seedHistory();
      await repo.setTypicalPeriodLength(7);
      await repo.markPeriodDays(['2026-02-22', '2026-02-24']);
      await repo.setPeriodDayExplicitly('2026-02-23', isPeriodDay: false);
      await repo.upsertDay(
        date: '2026-02-25',
        isPeriodDaySwitch: false,
        mood: Mood.cansada,
        notes: 'nota inventada',
        symptoms: {Symptom.dolorAbdominal},
      );
    }

    testHome('completa los dias sin registro, respeta el "No", no toca '
        'animo/notas/sintomas y cierra hoy; Deshacer exacto', (tester) async {
      await seedWithGaps();
      final before = await dump();
      await pumpHome(tester);
      expect(find.text(card), findsOneWidget);

      await tapAndSettle(tester, 'Terminó hoy');

      expect(find.text('Período terminado hoy.'), findsOneWidget);
      expect(find.text(card), findsNothing);
      final no = await repo.getDay('2026-02-23');
      expect(no!.isPeriodDay, isFalse);
      expect(no.periodDayExplicit, isTrue);
      final filled = await repo.getDay('2026-02-25');
      expect(filled!.isPeriodDay, isTrue);
      expect(filled.mood, Mood.cansada);
      expect(filled.notes, 'nota inventada');
      expect(await repo.getSymptomsForDay('2026-02-25'),
          {Symptom.dolorAbdominal});
      expect((await repo.getDay('2026-02-26'))!.isPeriodDay, isTrue);
      expect((await repo.getDay(fakeToday))!.periodEnd,
          PeriodEndSource.declared);
      final cycles = await repo.getDerivedCycles();
      expect(cycles.last.isClosed, isTrue);

      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(await dump(), before);
    });
  });

  group('Ya termino antes', () {
    testHome('el selector va del inicio a hoy y abre en el ultimo dia '
        'marcado', (tester) async {
      await seedHistory();
      await seedRange('2026-02-24', 2);
      await pumpHome(tester);

      await tapAndSettle(tester, 'Ya terminó antes');

      final picker =
          tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
      expect(picker.firstDate, DateTime(2026, 2, 24));
      expect(picker.lastDate, DateTime(2026, 2, 27));
      expect(picker.initialDate, DateTime(2026, 2, 25));
    });

    testHome('cierra en el dia elegido; Deshacer exacto', (tester) async {
      await seedHistory();
      await seedRange('2026-02-24', 3);
      final before = await dump();
      await pumpHome(tester);

      await tapAndSettle(tester, 'Ya terminó antes');
      await pickDay(tester, '26');

      expect(find.text('Período terminado el 26 de febrero.'), findsOneWidget);
      expect((await repo.getDay('2026-02-26'))!.periodEnd,
          PeriodEndSource.declared);
      expect(await repo.getDay(fakeToday), isNull);

      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(await dump(), before);
    });

    testHome('cancelar el selector no cambia nada', (tester) async {
      await seedHistory();
      await seedRange('2026-02-24', 3);
      final before = await dump();
      await pumpHome(tester);

      await tapAndSettle(tester, 'Ya terminó antes');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(await dump(), before);
      expect(find.text(card), findsOneWidget);
    });

    testHome('decision 5: dias marcados despues bloquean con su mensaje y '
        'no cambia nada', (tester) async {
      await seedHistory();
      await seedRange('2026-02-24', 3);
      final before = await dump();
      await pumpHome(tester);

      await tapAndSettle(tester, 'Ya terminó antes');
      await pickDay(tester, '25');

      expect(
          find.text('Después de ese día hay 1 día marcado. Quítalo primero '
              'o elige otro día.'),
          findsOneWidget);
      expect(find.text('Deshacer'), findsNothing);
      expect(await dump(), before);
    });

    testHome('decision 5 con varios dias: mensaje en plural',
        (tester) async {
      await seedHistory();
      await seedRange('2026-02-24', 3);
      await pumpHome(tester);

      await tapAndSettle(tester, 'Ya terminó antes');
      await pickDay(tester, '24');

      expect(
          find.text('Después de ese día hay 2 días marcados. Quítalos '
              'primero o elige otro día.'),
          findsOneWidget);
    });

    testHome('un dia con "No" explicito no puede ser el fin: mensaje '
        'propio y no cambia nada', (tester) async {
      await seedHistory();
      await repo.setTypicalPeriodLength(7);
      await repo.markPeriodDays(['2026-02-22', '2026-02-24']);
      await repo.setPeriodDayExplicitly('2026-02-23', isPeriodDay: false);
      final before = await dump();
      await pumpHome(tester);

      await tapAndSettle(tester, 'Ya terminó antes');
      await pickDay(tester, '23');

      expect(
          find.text('Ese día lo registraste sin sangrado, así que no puede '
              'ser el último día de tu período. Elige otro día.'),
          findsOneWidget);
      expect(await dump(), before);
    });

    testHome('decision 14: un periodo de 1 dia pide confirmacion; '
        '"Cancelar" no cambia nada', (tester) async {
      await seedHistory();
      await repo.markPeriodDay('2026-02-26');
      final before = await dump();
      await pumpHome(tester);

      await tapAndSettle(tester, 'Ya terminó antes');
      await pickDay(tester, '26');

      expect(find.text('¿Tu período duró solo 1 día?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(await dump(), before);
    });

    testHome('decision 14: confirmar cierra el periodo de 1 dia; Deshacer '
        'exacto', (tester) async {
      await seedHistory();
      await repo.markPeriodDay('2026-02-26');
      final before = await dump();
      await pumpHome(tester);

      await tapAndSettle(tester, 'Ya terminó antes');
      await pickDay(tester, '26');
      await tester.tap(find.text('Sí, duró 1 día'));
      await tester.pumpAndSettle();

      expect(find.text('Período terminado el 26 de febrero.'), findsOneWidget);
      final cycle = (await repo.getDerivedCycles()).last;
      expect(cycle.periodLengthDays, 1);
      expect(cycle.periodEnd, PeriodEndSource.declared);

      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(await dump(), before);
    });

    testHome('sin confirmacion de 1 dia si el periodo tiene mas dias',
        (tester) async {
      await seedHistory();
      await seedRange('2026-02-25', 2);
      await pumpHome(tester);

      await tapAndSettle(tester, 'Ya terminó antes');
      await pickDay(tester, '26');

      expect(find.text('¿Tu período duró solo 1 día?'), findsNothing);
      expect(find.text('Período terminado el 26 de febrero.'), findsOneWidget);
    });
  });

  group('Me llego hoy en Inicio', () {
    testHome('abre la hoja y marca hoy; Deshacer exacto', (tester) async {
      await seedHistory();
      final before = await dump();
      await pumpHome(tester, '2026-03-20');

      await tapAndSettle(tester, 'Me llegó hoy');
      expect(find.text('¿Cuándo empezó tu período?'), findsOneWidget);
      await tester.tap(find.text('Marcar mi período'));
      await tester.pumpAndSettle();

      expect((await repo.getDay('2026-03-20'))!.isPeriodDay, isTrue);
      expect(find.text('Inicio del período registrado.'), findsOneWidget);
      expect(find.text('Me llegó hoy'), findsNothing,
          reason: 'ahora hay un periodo abierto en curso');

      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(await dump(), before);
    });
  });

  testHome('accesibilidad: botones de la tarjeta de 48 dp con su texto '
      'como etiqueta', (tester) async {
    final semantics = tester.ensureSemantics();
    await seedHistory();
    await repo.markPeriodDay('2026-02-26');
    await pumpHome(tester);

    for (final label in ['Sigue', 'Terminó hoy', 'Ya terminó antes']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      final size = tester.getSize(find.ancestor(
          of: find.text(label), matching: find.bySubtype<ButtonStyleButton>()));
      expect(size.width, greaterThanOrEqualTo(48), reason: label);
      expect(size.height, greaterThanOrEqualTo(48), reason: label);
    }
    semantics.dispose();
  });
}
