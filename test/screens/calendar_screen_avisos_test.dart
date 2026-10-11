import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/screens/calendar_screen.dart';

/// Avisos del Calendario con el mismo texto y puntuacion que el resto de
/// la app: "Ese dia ya esta registrado.", "Esos dias ya estan
/// registrados." y "Marca quitada.". Datos inventados: dias marcados del
/// 10 al 14 de julio de 2026; "hoy" es el 20.
void main() {
  late AppDatabase db;
  late CycleRepository repo;

  const unDia = 'Ese día ya está registrado.';
  const variosDias = 'Esos días ya están registrados.';
  const quitada = 'Marca quitada.';

  setUpAll(() async {
    await initializeDateFormatting();
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CycleRepository(db);
  });

  String jul(int day) => '2026-07-${day.toString().padLeft(2, '0')}';

  Future<void> pumpCalendar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await repo.markPeriodDays([for (var d = 10; d <= 14; d++) jul(d)]);
    final hoy = DateTime.parse(jul(20));
    await tester.pumpWidget(MaterialApp(
      home: CalendarScreen(repository: repo, clock: () => hoy),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  // Sin ensureVisible: en una celda del calendario cambia de mes.
  Future<void> tapDay(WidgetTester tester, int day) async {
    await tester.tap(find.text('$day'));
    await tester.pumpAndSettle();
  }

  Future<List<DailyLogRow>> filas() => (db.select(db.dailyLogs)
        ..orderBy([(t) => OrderingTerm.asc(t.date)]))
      .get();

  testWidgets('rango de un dia ya marcado: "$unDia" sin cambiar nada',
      (tester) async {
    await pumpCalendar(tester);
    final antes = await tester.runAsync(filas);
    await tapText(tester, 'Elegir varios días');
    await tapDay(tester, 11);
    await tapText(tester, 'Marcar período');

    expect(find.text(unDia), findsOneWidget);
    expect(find.text('Deshacer'), findsNothing);
    expect(await tester.runAsync(filas), antes);
    await db.close();
  });

  testWidgets('rango de varios dias ya marcados: "$variosDias" sin cambiar '
      'nada', (tester) async {
    await pumpCalendar(tester);
    final antes = await tester.runAsync(filas);
    await tapText(tester, 'Elegir varios días');
    await tapDay(tester, 11);
    await tapDay(tester, 12);
    await tapText(tester, 'Marcar período');

    expect(find.text(variosDias), findsOneWidget);
    expect(find.text('Deshacer'), findsNothing);
    expect(await tester.runAsync(filas), antes);
    await db.close();
  });

  testWidgets('marcar un dia que ya estaba marcado: "$unDia"',
      (tester) async {
    await pumpCalendar(tester);
    // El panel de un dia marcado ofrece "Quitar marca", no "Marcar
    // periodo": este aviso cubre que se haya marcado por otro lado.
    final estado = tester.state(find.byType(CalendarScreen)) as dynamic;
    await estado.registrarDia(DateTime.parse(jul(12)));
    await tester.pumpAndSettle();

    expect(find.text(unDia), findsOneWidget);
    await db.close();
  });

  testWidgets('quitar una marca: "$quitada" con Deshacer', (tester) async {
    await pumpCalendar(tester);
    await tapDay(tester, 12);
    await tapText(tester, 'Quitar marca');

    expect(find.text(quitada), findsOneWidget);
    expect(find.text('Deshacer'), findsOneWidget);
    await db.close();
  });
}
