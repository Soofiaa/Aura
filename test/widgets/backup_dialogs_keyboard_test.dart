import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/main.dart';
import 'package:aura/utils/aura_localizations.dart';
import 'package:aura/widgets/protect_backup_dialog.dart';
import 'package:aura/widgets/unlock_backup_dialog.dart';

/// HU-06b CP4 (anexo): los dialogos de contrasena con el teclado en
/// pantalla simulado (viewInsets.bottom = 300 dp), en 360x640 y 360x780,
/// con texto a 1,0 y 1,5.
void main() {
  const keyboard = 300.0;

  Future<void> open(
    WidgetTester tester,
    Size size,
    double textScale,
    Future<Object?> Function(BuildContext) show,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: auraTheme(),
        localizationsDelegates: auraLocalizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Align(
              alignment: Alignment.topLeft,
              child: TextButton(
                onPressed: () => show(ctx),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  /// Parte visible de la pantalla: por encima del teclado.
  void expectAboveKeyboard(WidgetTester tester, Finder f, Size size) {
    final r = tester.getRect(f);
    expect(r.top, greaterThanOrEqualTo(0), reason: '$f arriba');
    expect(
      r.bottom,
      lessThanOrEqualTo(size.height - keyboard),
      reason: '$f debajo del teclado: $r',
    );
  }

  Finder dialogScrollable() => find
      .descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable),
      )
      .first;

  for (final size in const [Size(360, 640), Size(360, 780)]) {
    for (final scale in const [1.0, 1.5]) {
      final caso = '${size.width.toInt()}x${size.height.toInt()}, texto $scale';

      testWidgets('Proteger tu respaldo, $caso', (tester) async {
        await open(tester, size, scale, showProtectBackupDialog);
        expect(tester.takeException(), isNull);

        final cancelar = find.text('Cancelar');
        final proteger = find.text('Proteger y continuar');
        expectAboveKeyboard(tester, cancelar, size);
        expectAboveKeyboard(tester, proteger, size);
        expect(cancelar.hitTestable(), findsOneWidget);
        expect(proteger.hitTestable(), findsOneWidget);

        for (final key in ['protect-password', 'protect-repeat']) {
          final field = find.byKey(ValueKey(key));
          await tester.scrollUntilVisible(
            field,
            40,
            scrollable: dialogScrollable(),
          );
          await tester.tap(field);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expectAboveKeyboard(tester, field, size);
          await tester.enterText(field, 'una frase de prueba larga');
          await tester.pumpAndSettle();
          expectAboveKeyboard(tester, field, size);
        }

        // Los botones siguen en pantalla y se pueden tocar.
        expectAboveKeyboard(tester, proteger, size);
        await tester.tap(
          find.widgetWithText(FilledButton, 'Proteger y continuar'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Proteger tu respaldo'), findsNothing);
      });

      testWidgets('Respaldo protegido, $caso', (tester) async {
        await open(
          tester,
          size,
          scale,
          (ctx) => showUnlockBackupDialog(
            ctx,
            initialPassword: 'x',
            errorText:
                'La contraseña no es correcta o el archivo está '
                'dañado. No se cambió nada.',
          ),
        );
        expect(tester.takeException(), isNull);
        final field = find.byKey(const ValueKey('unlock-password'));
        await tester.scrollUntilVisible(
          field,
          40,
          scrollable: dialogScrollable(),
        );
        await tester.tap(field);
        await tester.pumpAndSettle();
        expectAboveKeyboard(tester, field, size);
        expectAboveKeyboard(tester, find.text('Cancelar'), size);
        expectAboveKeyboard(tester, find.text('Abrir respaldo'), size);
        expect(find.text('Cancelar').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(find.text('Respaldo protegido'), findsNothing);
      });
    }
  }
}
