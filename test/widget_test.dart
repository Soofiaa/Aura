// Smoke test: verifica que la app arranca sin lanzar excepciones,
// tanto si el onboarding ya fue visto como si no.

import 'package:flutter_test/flutter_test.dart';

import 'package:aura/main.dart';

void main() {
  testWidgets('AuraApp arranca y muestra HomeScreen cuando onboardingVisto es true',
      (WidgetTester tester) async {
    await tester.pumpWidget(const AuraApp(onboardingVisto: true));
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
