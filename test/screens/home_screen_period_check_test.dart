import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/screens/home_screen.dart';

Future<void> _seedPeriod(
  CycleRepository repo,
  DateTime periodStart,
  int length,
) async {
  for (var i = 0; i < length; i++) {
    final day = periodStart.add(Duration(days: i));
    final key = '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    await repo.markPeriodDay(key);
  }
}

/// 2 ciclos completos de 28 dias + uno abierto empezando 2026-02-26;
/// "hoy" en 2026-02-27 (dia de ciclo 2) cae en fase menstrual.
Future<CycleRepository> _seedMenstrualPhaseToday(AppDatabase db) async {
  final repo = CycleRepository(db);
  await _seedPeriod(repo, DateTime(2026, 1, 1), 5);
  await _seedPeriod(repo, DateTime(2026, 1, 29), 5);
  await repo.markPeriodDay('2026-02-26'); // solo el dia 1 del ciclo abierto
  return repo;
}

void main() {
  const fakeToday = '2026-02-27';

  testWidgets('tarjeta visible en fase menstrual sin respuesta de hoy',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    final repo = await _seedMenstrualPhaseToday(db);

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(repository: repo, clock: () => DateTime(2026, 2, 27)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('¿Sigue tu período hoy?'), findsOneWidget);

    await db.close();
  });

  testWidgets('tarjeta oculta si hoy ya tiene is_period_day=true',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    final repo = await _seedMenstrualPhaseToday(db);
    await repo.markPeriodDay(fakeToday);

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(repository: repo, clock: () => DateTime(2026, 2, 27)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('¿Sigue tu período hoy?'), findsNothing);

    await db.close();
  });

  testWidgets(
      'tarjeta oculta si hoy ya tiene is_period_day=false con '
      'period_day_explicit=true', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    final repo = await _seedMenstrualPhaseToday(db);
    await repo.setPeriodDayExplicitly(fakeToday, isPeriodDay: false);

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(repository: repo, clock: () => DateTime(2026, 2, 27)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('¿Sigue tu período hoy?'), findsNothing);

    await db.close();
  });

  testWidgets('tocar "Sí" tambien oculta la tarjeta (reactivo)',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    final repo = await _seedMenstrualPhaseToday(db);

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(repository: repo, clock: () => DateTime(2026, 2, 27)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('¿Sigue tu período hoy?'), findsOneWidget);

    await tester.tap(find.text('Sí'));
    await tester.pumpAndSettle();

    expect(find.text('¿Sigue tu período hoy?'), findsNothing);
    expect((await repo.getDay(fakeToday))!.isPeriodDay, isTrue);

    await db.close();
  });

  testWidgets('tocar "No" oculta la tarjeta y "Deshacer" la trae de vuelta',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    final repo = await _seedMenstrualPhaseToday(db);

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(repository: repo, clock: () => DateTime(2026, 2, 27)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();

    expect(find.text('¿Sigue tu período hoy?'), findsNothing);
    final afterNo = await repo.getDay(fakeToday);
    expect(afterNo!.isPeriodDay, isFalse);
    expect(afterNo.periodDayExplicit, isTrue);

    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();

    // Antes de "No" no habia fila para hoy: deshacer debe borrarla.
    expect(await repo.getDay(fakeToday), isNull);
    expect(find.text('¿Sigue tu período hoy?'), findsOneWidget);

    await db.close();
  });
}
