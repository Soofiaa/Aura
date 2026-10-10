import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/screens/onboarding_screen.dart';

/// CP6: 4.a pagina del onboarding ("Tus datos son tuyos").
void main() {
  late AppDatabase db;
  late CycleRepository repo;

  const titulos = [
    'Bienvenida a Aura 🌸',
    'Registra tu bienestar 💕',
    'Conoce tus patrones 🌙',
    'Tus datos son tuyos 🔒',
  ];
  const textoCuarta = 'Aura funciona sin internet y guarda todo solo en este '
      'teléfono. Para no perder tus registros si cambias o pierdes el '
      'teléfono, crea un respaldo de vez en cuando desde Ajustes.';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CycleRepository(db);
  });

  Future<void> pumpOnboarding(WidgetTester tester,
      {Size tamano = const Size(360, 640), double escala = 1.0}) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = escala;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MaterialApp(
      home: OnboardingScreen(
        repository: repo,
        nextScreen: (_) => const Scaffold(body: Text('pantalla principal')),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Los puntos indicadores (uno por pagina).
  Finder puntos() => find.byType(AnimatedContainer);

  Future<void> siguiente(WidgetTester tester) async {
    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
  }

  testWidgets('4 paginas y 4 puntos; "Comenzar" solo en la ultima',
      (tester) async {
    await pumpOnboarding(tester);
    expect(puntos(), findsNWidgets(4));

    for (var i = 0; i < 4; i++) {
      expect(find.text(titulos[i]), findsOneWidget, reason: 'pagina ${i + 1}');
      final ultima = i == 3;
      expect(find.text('Comenzar'), ultima ? findsOneWidget : findsNothing);
      expect(find.text('Siguiente'), ultima ? findsNothing : findsOneWidget);
      // El punto de la pagina actual es el ancho.
      final anchos = [
        for (final e in puntos().evaluate())
          tester.getSize(find.byWidget(e.widget)).width
      ];
      final mayor = anchos.reduce((a, b) => a > b ? a : b);
      expect(anchos.indexOf(mayor), i);
      expect(anchos.where((a) => a == mayor), hasLength(1));
      if (!ultima) await siguiente(tester);
    }
    expect(find.text(textoCuarta), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    await db.close();
  });

  testWidgets('onboardingSeen se marca solo al tocar "Comenzar"',
      (tester) async {
    await pumpOnboarding(tester);
    for (var i = 0; i < 3; i++) {
      await siguiente(tester);
      expect(await tester.runAsync(repo.getOnboardingSeen), isFalse);
    }
    // En la 4.a pagina, sin tocar nada, todavia no.
    expect(find.text(titulos[3]), findsOneWidget);
    expect(await tester.runAsync(repo.getOnboardingSeen), isFalse);

    await tester.tap(find.text('Comenzar'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(repo.getOnboardingSeen), isTrue);
    expect(find.text('pantalla principal'), findsOneWidget);
    await db.close();
  });

  testWidgets('deslizando tambien se llega a la 4.a pagina', (tester) async {
    await pumpOnboarding(tester);
    for (var i = 0; i < 3; i++) {
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
    }
    expect(find.text(titulos[3]), findsOneWidget);
    expect(find.text('Comenzar'), findsOneWidget);
    await db.close();
  });

  group('360 x 640 sin desbordes', () {
    for (final escala in [1.0, 1.3, 1.5, 2.0]) {
      testWidgets('texto $escala: las 4 paginas, el texto se puede leer '
          'entero', (tester) async {
        await pumpOnboarding(tester, escala: escala);
        for (var i = 0; i < 4; i++) {
          expect(tester.takeException(), isNull, reason: 'pagina ${i + 1}');
          final pagina = find.ancestor(
            of: find.text(titulos[i]),
            matching: find.byType(SingleChildScrollView),
          );
          final descripcion = find.descendant(
            of: pagina,
            matching: find.byWidgetPredicate((w) =>
                w is Text &&
                w.data != titulos[i] &&
                (w.data ?? '').length > 40),
          );
          // Se puede leer entero: el comienzo se puede llevar a la vista
          // y, desplazandose hasta el final, tambien la ultima linea.
          final visible = tester.getRect(pagina);
          await tester.ensureVisible(descripcion);
          await tester.pumpAndSettle();
          expect(tester.getRect(descripcion).top,
              greaterThanOrEqualTo(visible.top - 0.5),
              reason: 'pagina ${i + 1}');
          final posicion = tester
              .state<ScrollableState>(find.descendant(
                  of: pagina, matching: find.byType(Scrollable)))
              .position;
          posicion.jumpTo(posicion.maxScrollExtent);
          await tester.pumpAndSettle();
          final rect = tester.getRect(descripcion);
          expect(rect.bottom, lessThanOrEqualTo(visible.bottom + 0.5),
              reason: 'pagina ${i + 1}');
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(360));
          if (i < 3) await siguiente(tester);
        }
        expect(find.text('Comenzar'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await db.close();
      });
    }

    testWidgets('texto 2,0: la 4.a pagina no entra entera y se desplaza',
        (tester) async {
      await pumpOnboarding(tester, escala: 2.0);
      for (var i = 0; i < 3; i++) {
        await siguiente(tester);
      }
      final scroll = find.descendant(
        of: find.ancestor(
          of: find.text(titulos[3]),
          matching: find.byType(SingleChildScrollView),
        ),
        matching: find.byType(Scrollable),
      );
      final posicion = tester.state<ScrollableState>(scroll).position;
      expect(posicion.maxScrollExtent, greaterThan(0));
      // Con el dedo (dos arrastres: el primero pierde la zona muerta).
      for (var i = 0; i < 2; i++) {
        await tester.drag(scroll, const Offset(0, -1200));
        await tester.pumpAndSettle();
      }
      expect(posicion.pixels, posicion.maxScrollExtent);
      expect(tester.takeException(), isNull);
      await db.close();
    });
  });
}
