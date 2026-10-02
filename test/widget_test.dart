// Smoke test: verifica que la app arranca sin lanzar excepciones,
// tanto si el onboarding ya fue visto como si no.
//
// El caso "onboardingVisto: true" prueba HomeScreen directamente (en vez
// de a traves de AuraApp) con un CycleRepository en memoria: HomeScreen
// toca la base de datos real en initState (getPrediction), y el entorno
// de flutter_test no tiene el canal de plataforma de path_provider que
// esa base de datos necesita para abrir el archivo real.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/main.dart';
import 'package:aura/screens/home_screen.dart';

void main() {
  testWidgets('HomeScreen arranca y muestra la app bar sin datos registrados',
      (WidgetTester tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    final repo = CycleRepository(db);
    addTearDown(db.close);

    await tester.pumpWidget(MaterialApp(home: HomeScreen(repository: repo)));
    await tester.pumpAndSettle();

    expect(find.text('Aura 🌸'), findsOneWidget);
  });

  testWidgets('AuraApp arranca y muestra el onboarding cuando onboardingVisto es false',
      (WidgetTester tester) async {
    await tester.pumpWidget(const AuraApp(onboardingVisto: false));
    await tester.pumpAndSettle();

    expect(find.text('Bienvenida a Aura 🌸'), findsOneWidget);
  });
}
