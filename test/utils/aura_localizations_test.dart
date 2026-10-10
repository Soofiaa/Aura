import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/utils/aura_localizations.dart';

/// Textos del sistema (Material) en espanol con flutter_localizations,
/// aunque el telefono o el test esten en otro idioma (hallazgo #14 de la
/// auditoria: "Back", "Tab 1 of 4", "Scrim", "Dismiss" y el selector de
/// fecha salian en ingles).
void main() {
  Future<BuildContext> pumpApp(WidgetTester tester, {Widget? home}) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: auraLocalizationsDelegates,
      supportedLocales: auraSupportedLocales,
      locale: auraLocale,
      home: home ??
          Builder(builder: (c) {
            ctx = c;
            return const SizedBox();
          }),
    ));
    return ctx;
  }

  testWidgets('los textos de Material salen en espanol', (tester) async {
    final l = MaterialLocalizations.of(await pumpApp(tester));
    expect(l.backButtonTooltip, 'Atrás');
    expect(l.closeButtonTooltip, 'Cerrar');
    expect(l.cancelButtonLabel, 'Cancelar');
    expect(l.tabLabel(tabIndex: 1, tabCount: 4), 'Pestaña 1 de 4');
    expect(l.scrimLabel, 'Sombreado');
    expect(l.modalBarrierDismissLabel, 'Cerrar');
    expect(l.datePickerHelpText, 'Seleccionar fecha');
  });

  testWidgets(
      'en espanol aunque el idioma del telefono sea otro (sin locale en la '
      'app)', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: auraLocalizationsDelegates,
      home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    ));
    expect(MaterialLocalizations.of(ctx).backButtonTooltip, 'Atrás');
    expect(MaterialLocalizations.of(ctx).closeButtonTooltip, 'Cerrar');
  });

  testWidgets('el selector de fecha esta en espanol', (tester) async {
    final ctx = await pumpApp(tester);
    showDatePicker(
      context: ctx,
      initialDate: DateTime(2026, 10, 2),
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime(2026, 12, 31),
    );
    await tester.pumpAndSettle();

    expect(find.text('Seleccionar fecha'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('OK'), findsNothing);
    expect(find.textContaining('octubre'), findsWidgets);
    expect(find.textContaining('October'), findsNothing);
  });

  testWidgets('la flecha atras se anuncia "Atrás"', (tester) async {
    final ctx = await pumpApp(tester);
    Navigator.of(ctx).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(appBar: AppBar(title: const Text('x'))),
    ));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Atrás'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
  });
}
