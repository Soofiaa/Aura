import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/screens/main_navigation_screen.dart';

/// Toca el destino de la NavigationBar con esa etiqueta, no cualquier
/// otro texto igual en pantalla (ej. "Calendario" tambien aparece como
/// boton de acceso rapido dentro de HomeScreen).
Future<void> _tapNavDestination(WidgetTester tester, String label) async {
  final finder = find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    // calendar_screen.dart usa DateFormat/TableCalendar en español; sin
    // esto, LocaleDataException al construir la pantalla.
    await initializeDateFormatting();
  });

  late AppDatabase db;
  late CycleRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CycleRepository(db);
    // MainNavigationScreen y sus 4 pantallas usan el singleton global:
    // se reemplaza aca para que todas compartan la misma base en memoria
    // sin tener que agregarle un parametro de repositorio a cada una.
    cycleRepository = repo;
  });

  testWidgets('navega a los 4 destinos sin excepciones', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MainNavigationScreen()));
    await tester.pumpAndSettle();

    for (final label in ['Calendario', 'Estadísticas', 'Ajustes', 'Inicio']) {
      await _tapNavDestination(tester, label);
      expect(tester.takeException(), isNull, reason: 'al navegar a $label');
    }

    await db.close();
  });

  testWidgets(
      'registrar un dia de sangrado hace que el inicio deje de mostrar '
      '"Registra tu primer día"', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MainNavigationScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Registra tu primer día'), findsOneWidget);

    await tester.tap(find.text('Registrar día'));
    await tester.pumpAndSettle();

    // El interruptor "Día de sangrado" arranca apagado en un dia nuevo
    // (hallazgo B-1): hay que encenderlo para registrar un periodo.
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    final guardarButton = find.text('Guardar registro');
    await tester.ensureVisible(guardarButton);
    await tester.pumpAndSettle();
    await tester.tap(guardarButton);
    await tester.pumpAndSettle();

    // De vuelta en Inicio (AddCycleScreen hace Navigator.pop al guardar);
    // el stream de home_screen ya deberia reflejar el dia recien creado.
    expect(find.textContaining('Registra tu primer día'), findsNothing);

    await db.close();
  });
}
