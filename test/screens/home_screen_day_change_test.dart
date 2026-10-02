import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/screens/home_screen.dart';

/// Marca [periodStart] y los [length] dias siguientes como dias de
/// sangrado, sin pasar por el formulario (solo para dejar datos de
/// prueba listos en la base).
Future<void> _seedPeriod(
  CycleRepository repo,
  DateTime periodStart,
  int length,
) async {
  for (var i = 0; i < length; i++) {
    final day = periodStart.add(Duration(days: i));
    final key =
        '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    await repo.markPeriodDay(key);
  }
}

/// 3 ciclos completos de 28 dias (periodos de 5 dias) + uno abierto:
/// 2026-01-01, 2026-01-29, 2026-02-26, 2026-03-26 (abierto).
/// nextPeriodExpectedDate = 2026-04-23, extremo tardio = 2026-04-25.
Future<CycleRepository> _seedRegularCycles(AppDatabase db) async {
  final repo = CycleRepository(db);
  await _seedPeriod(repo, DateTime(2026, 1, 1), 5);
  await _seedPeriod(repo, DateTime(2026, 1, 29), 5);
  await _seedPeriod(repo, DateTime(2026, 2, 26), 5);
  await _seedPeriod(repo, DateTime(2026, 3, 26), 5);
  return repo;
}

void main() {
  testWidgets(
      'al volver a primer plano (resumed) con otro dia, la fase y el '
      'atraso se recalculan sin tocar la base', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    final repo = await _seedRegularCycles(db);

    var fakeNow = DateTime(2026, 3, 28); // dia 3 del ciclo abierto

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(repository: repo, clock: () => fakeNow),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Fase menstrual'), findsOneWidget);
    expect(find.textContaining('Período atrasado'), findsNothing);

    // El reloj "avanza" mientras la app estaba en segundo plano: ya
    // pasamos el extremo tardio del rango (2026-04-25) por 3 dias. No se
    // escribe nada en la base entre un pump y otro.
    fakeNow = DateTime(2026, 4, 28);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Período atrasado por 3 días'), findsOneWidget);
    expect(find.text('Fase menstrual'), findsNothing);

    // Cerrar la base ANTES de que termine el cuerpo del test (no con
    // addTearDown/tearDown): drift deja un Timer interno pendiente
    // hasta que la conexion se cierra, y flutter_test revienta con "A
    // Timer is still pending" si eso pasa despues de que termina el
    // test. Ojo: desmontar el widget primero (pumpWidget con otro
    // widget) antes de cerrar la base cuelga el test; cerrar
    // directamente con el widget todavia montado funciona bien.
    await db.close();
  });

  testWidgets(
      'si la medianoche pasa con la app abierta, la fase y el atraso se '
      'recalculan solos (sin resumed, sin tocar la base)', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    final repo = await _seedRegularCycles(db);

    // Un minuto antes de la medianoche del 2026-04-26: "hoy" todavia es
    // 2026-04-25, que es justo el extremo tardio (no esta atrasado).
    var fakeNow = DateTime(2026, 4, 25, 23, 59);

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(repository: repo, clock: () => fakeNow),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Período atrasado'), findsNothing);

    // Avanza el reloj a justo despues de medianoche y deja que el timer
    // interno (programado en initState para dentro de 1 minuto) dispare.
    fakeNow = DateTime(2026, 4, 26, 0, 0, 5);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();

    expect(find.text('Período atrasado por 1 día'), findsOneWidget);

    await db.close();
  });
}
