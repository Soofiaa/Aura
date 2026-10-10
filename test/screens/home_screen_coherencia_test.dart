import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/models/day_enums.dart';
import 'package:aura/data/notifications/notification_reconciler.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/screens/home_screen.dart';
import 'package:aura/utils/day_key.dart';

import '../support/fake_notification_scheduler.dart';

/// Coherencia de Inicio con el periodo en curso (investigacion del
/// hallazgo #1). Datos inventados: periodos de 5 dias cerrados que
/// empiezan el 09/07, 05/08, 03/09 y 01/10 de 2026 (ciclos de 27, 29 y
/// 28 dias). Proximo periodo 27/10 - 31/10, ovulacion 15/10, ventana
/// 10/10 - 15/10.
void main() {
  late AppDatabase db;
  late CycleRepository repo;

  const fases = [
    'Fase menstrual',
    'Fase folicular',
    'Fase ovulatoria',
    'Fase lútea',
  ];
  const tarjeta = '¿Sigue tu período hoy?';

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
        tester.view.physicalSize = const Size(800, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await body(tester);
        await db.close();
      });

  Future<void> periodo(String inicio, {int dias = 5, bool cerrar = true}) async {
    final fechas = [for (var i = 0; i < dias; i++) DayKey.addDays(inicio, i)];
    await repo.markPeriodDays(fechas);
    if (cerrar) {
      await repo.closePeriod(inicio, fechas.last, today: fechas.last);
    }
  }

  Future<void> historial() async {
    for (final inicio in ['2026-07-09', '2026-08-05', '2026-09-03']) {
      await periodo(inicio);
    }
  }

  Future<void> pumpHome(WidgetTester tester, String today) async {
    final fecha = DateTime.parse(today);
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        repository: repo,
        clock: () => fecha,
        reconciler: NotificationReconciler(repo, FakeNotificationScheduler(),
            clock: () => fecha),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// La unica fase que se ve en Inicio.
  void soloFase(String fase) {
    for (final f in fases) {
      expect(find.text(f), f == fase ? findsOneWidget : findsNothing,
          reason: f);
    }
  }

  void sinFertilidad() {
    expect(find.textContaining('Ovulación estimada'), findsNothing);
    expect(find.textContaining('mayor probabilidad de fertilidad'),
        findsNothing);
  }

  void conFertilidad() {
    expect(find.text('Ovulación estimada: 15/10/2026'), findsOneWidget);
    expect(find.textContaining('10/10/2026 - 15/10/2026'), findsOneWidget);
  }

  group('periodo en curso', () {
    testHome(
        'sangrado marcado ayer a 3 dias del cierre (dia 9): fase menstrual, '
        'sin fertilidad y la tarjeta sin una duracion que contradiga el dia',
        (tester) async {
      await historial();
      await periodo('2026-10-01');
      await repo.markPeriodDay('2026-10-08');
      await pumpHome(tester, '2026-10-09');

      soloFase('Fase menstrual');
      sinFertilidad();
      expect(find.text(tarjeta), findsOneWidget);
      expect(
          find.text('Día 9 de tu período · ya superó tu duración estimada '
              '(5 días)'),
          findsOneWidget);
      expect(find.textContaining('duración estimada: 5'), findsNothing);
      // El proximo periodo se sigue mostrando como siempre.
      expect(find.text('Próximo período: 27/10/2026 - 31/10/2026'),
          findsOneWidget);
    });

    testHome('sangrado registrado hoy (dia 9): fase menstrual y sin fertilidad',
        (tester) async {
      await historial();
      await periodo('2026-10-01');
      await repo.upsertDay(
        date: '2026-10-09',
        isPeriodDaySwitch: true,
        flow: FlowIntensity.moderado,
      );
      await pumpHome(tester, '2026-10-09');

      soloFase('Fase menstrual');
      sinFertilidad();
      // Hoy ya tiene respuesta: no se vuelve a preguntar.
      expect(find.text(tarjeta), findsNothing);
    });

    testHome(
        'spotting a 7 dias del cierre, dia siguiente (dia 14): menstrual y no '
        'ovulatoria', (tester) async {
      await historial();
      await periodo('2026-10-01');
      await repo.markPeriodDays(['2026-10-12', '2026-10-13']);
      await pumpHome(tester, '2026-10-14');

      soloFase('Fase menstrual');
      sinFertilidad();
      expect(
          find.text('Día 14 de tu período · ya superó tu duración estimada '
              '(5 días)'),
          findsOneWidget);
    });

    testHome(
        'periodo normal en curso (dia 3, marcado hasta ayer): menstrual, sin '
        'fertilidad y la duracion estimada de siempre', (tester) async {
      await historial();
      await periodo('2026-10-01', dias: 2, cerrar: false);
      await pumpHome(tester, '2026-10-03');

      soloFase('Fase menstrual');
      sinFertilidad();
      expect(find.text('Día 3 de tu período · duración estimada: 5 días'),
          findsOneWidget);
    });
  });

  group('periodo cerrado hoy', () {
    testHome(
        'Termino hoy tras un sangrado que reabrio el periodo (dia 9): fase '
        'menstrual, sin ovulacion ni ventana y sin tarjeta', (tester) async {
      await historial();
      await periodo('2026-10-01');
      await repo.markPeriodDay('2026-10-08');
      // "Termino hoy": completa los dias y cierra el periodo en hoy.
      await repo.closePeriod('2026-10-01', '2026-10-09', today: '2026-10-09');
      await pumpHome(tester, '2026-10-09');

      soloFase('Fase menstrual');
      sinFertilidad();
      expect(find.text(tarjeta), findsNothing);
      expect(find.text('Próximo período: 27/10/2026 - 31/10/2026'),
          findsOneWidget);
    });
  });

  group('sin periodo en curso', () {
    testHome('periodo recien cerrado (dia siguiente al cierre): todo visible',
        (tester) async {
      await historial();
      await periodo('2026-10-01');
      await pumpHome(tester, '2026-10-06');

      soloFase('Fase folicular');
      conFertilidad();
      expect(find.text(tarjeta), findsNothing);
    });

    testHome('lejos del periodo (dia 9): fase folicular y fertilidad visibles',
        (tester) async {
      await historial();
      await periodo('2026-10-01');
      await pumpHome(tester, '2026-10-09');

      soloFase('Fase folicular');
      conFertilidad();
      expect(find.text(tarjeta), findsNothing);
    });

    testHome(
        'periodo sin cerrar pero sin sangrado desde hace 3 dias: se presenta '
        'como hoy', (tester) async {
      await historial();
      await periodo('2026-10-01', cerrar: false);
      await pumpHome(tester, '2026-10-08');

      soloFase('Fase folicular');
      conFertilidad();
      expect(find.text(tarjeta), findsNothing);
    });
  });
}
