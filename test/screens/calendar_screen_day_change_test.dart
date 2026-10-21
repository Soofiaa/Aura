import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/screens/calendar_screen.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  Future<void> pumpCalendar(
      WidgetTester tester, CycleRepository repo, DateTime Function() clock) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: CalendarScreen(repository: repo, clock: clock),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('si la medianoche pasa con la app abierta, el dia nuevo deja '
      'de estar deshabilitado (sin tocar nada)', (tester) async {
    final db =
        AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    final repo = CycleRepository(db);
    var fakeNow = DateTime(2026, 4, 25, 23, 59);
    await pumpCalendar(tester, repo, () => fakeNow);

    // El 26 es futuro: tocarlo no abre el panel del dia.
    await tester.tap(find.text('26').first);
    await tester.pumpAndSettle();
    expect(find.text('Marcar período'), findsNothing);

    fakeNow = DateTime(2026, 4, 26, 0, 0, 5);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();

    await tester.tap(find.text('26').first);
    await tester.pumpAndSettle();
    expect(find.text('Marcar período'), findsOneWidget);

    await db.close();
  });

  testWidgets('"Ir a hoy" vuelve al mes actual', (tester) async {
    final db =
        AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    final repo = CycleRepository(db);
    await pumpCalendar(tester, repo, () => DateTime(2026, 10, 20, 10));

    expect(find.text('octubre de 2026'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.text('agosto de 2026'), findsOneWidget);

    await tester.tap(find.byTooltip('Ir a hoy'));
    await tester.pumpAndSettle();
    expect(find.text('octubre de 2026'), findsOneWidget);

    await db.close();
  });

  testWidgets('despues de 2030 el calendario sigue abriendo', (tester) async {
    final db =
        AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    final repo = CycleRepository(db);
    await pumpCalendar(tester, repo, () => DateTime(2031, 2, 1, 10));

    expect(tester.takeException(), isNull);
    expect(find.text('febrero de 2031'), findsOneWidget);

    await db.close();
  });
}
