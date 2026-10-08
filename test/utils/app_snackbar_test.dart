import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/main.dart';
import 'package:aura/utils/app_snackbar.dart';
import 'package:aura/utils/aura_localizations.dart';

import '../support/contrast.dart';

/// showAppSnackBar: cuanto dura cada tipo de aviso, el aviso persistente
/// con su "x" y que un aviso nuevo reemplaza al anterior. Con el tema y
/// los delegados de la app (main.dart).
void main() {
  late BuildContext ctx;

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: auraTheme(),
        localizationsDelegates: auraLocalizationsDelegates,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
  }

  Future<void> mostrar(
    WidgetTester tester,
    String texto, {
    bool conDeshacer = false,
    bool persistent = false,
  }) async {
    showAppSnackBar(
      ctx,
      texto,
      action: conDeshacer
          ? SnackBarAction(label: 'Deshacer', onPressed: () {})
          : null,
      persistent: persistent,
    );
    // Termina la animacion de entrada: el temporizador corre desde ahi.
    await tester.pumpAndSettle();
  }

  test('las duraciones son 5 s (simple) y 7 s (con Deshacer)', () {
    expect(snackBarDuration, const Duration(seconds: 5));
    expect(undoSnackBarDuration, const Duration(seconds: 7));
  });

  testWidgets('aviso simple: sigue a los 4,9 s y se cierra a los 5 s', (
    tester,
  ) async {
    await pumpApp(tester);
    await mostrar(tester, 'Aviso simple');

    await tester.pump(const Duration(milliseconds: 4900));
    expect(find.text('Aviso simple'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('Aviso simple'), findsNothing);
  });

  testWidgets('aviso con Deshacer: sigue a los 6,9 s y se cierra a los 7 s', (
    tester,
  ) async {
    await pumpApp(tester);
    await mostrar(tester, 'Con Deshacer', conDeshacer: true);

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.persist, isFalse);
    expect(snackBar.showCloseIcon, isFalse);

    await tester.pump(const Duration(milliseconds: 6900));
    expect(find.text('Con Deshacer'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('Con Deshacer'), findsNothing);
  });

  group('aviso persistente (exito de la importacion)', () {
    testWidgets('sigue visible tras 60 s', (tester) async {
      await pumpApp(tester);
      await mostrar(tester, 'Importado', conDeshacer: true, persistent: true);

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.persist, isTrue);
      expect(snackBar.showCloseIcon, isTrue);

      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(find.text('Importado'), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Deshacer'), findsOneWidget);
    });

    testWidgets('la "x" se llama "Cerrar" para el lector de pantalla y lo '
        'cierra', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpApp(tester);
      await mostrar(tester, 'Importado', conDeshacer: true, persistent: true);

      expect(find.byTooltip('Cerrar'), findsOneWidget);
      // TalkBack lee el tooltip del boton como su nombre.
      expect(
        tester.getSemantics(find.byTooltip('Cerrar')),
        isSemantics(tooltip: 'Cerrar', isButton: true),
      );
      expect(find.byTooltip('Close'), findsNothing);

      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.text('Importado'), findsNothing);
      semantics.dispose();
    });

    testWidgets('la "x" contrasta con el fondo del aviso (al menos 4,5:1)', (
      tester,
    ) async {
      await pumpApp(tester);
      await mostrar(tester, 'Importado', conDeshacer: true, persistent: true);

      final cerrar = find.byTooltip('Cerrar');
      final icono = tester.widget<IconButton>(
        find.ancestor(of: cerrar, matching: find.byType(IconButton)).first,
      );
      // El Material mas externo del aviso es su fondo.
      final fondo = tester
          .widget<Material>(
            find
                .descendant(
                  of: find.byType(SnackBar),
                  matching: find.byType(Material),
                )
                .first,
          )
          .color!;
      expect(contrastRatio(icono.color!, fondo), greaterThanOrEqualTo(4.5));
    });
  });

  testWidgets('un aviso nuevo reemplaza al anterior, aunque sea persistente', (
    tester,
  ) async {
    await pumpApp(tester);
    await mostrar(tester, 'Primero', conDeshacer: true, persistent: true);
    await mostrar(tester, 'Segundo');
    expect(find.text('Primero'), findsNothing);
    expect(find.text('Segundo'), findsOneWidget);
  });
}
