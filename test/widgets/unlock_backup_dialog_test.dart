import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/main.dart';
import 'package:aura/utils/aura_localizations.dart';
import 'package:aura/utils/colors.dart';
import 'package:aura/widgets/unlock_backup_dialog.dart';

import '../support/contrast.dart';

/// HU-06b CP4: dialogo "Respaldo protegido". Contrasenas inventadas.
void main() {
  late String? result;
  late bool closed;

  final field = find.byKey(const ValueKey('unlock-password'));
  final abrir = find.widgetWithText(FilledButton, 'Abrir respaldo');

  ThemeData darkTheme() => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
  );

  Future<void> open(
    WidgetTester tester, {
    String? initialPassword,
    String? errorText,
    double textScale = 1,
    ThemeData? theme,
    Size size = const Size(420, 1000),
  }) async {
    result = null;
    closed = false;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? auraTheme(),
        localizationsDelegates: auraLocalizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                result = await showUnlockBackupDialog(
                  ctx,
                  initialPassword: initialPassword,
                  errorText: errorText,
                );
                closed = true;
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester) =>
      tester.widget<FilledButton>(abrir).onPressed != null;

  testWidgets('textos exactos, sin indicador ni aviso de recuperacion', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Respaldo protegido'), findsOneWidget);
    expect(
      find.text(
        'Este respaldo está protegido con contraseña. Escríbela '
        'para abrirlo.',
      ),
      findsOneWidget,
    );
    expect(find.text('Contraseña'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Abrir respaldo'), findsOneWidget);
    expect(find.textContaining('Fortaleza'), findsNothing);
    expect(find.textContaining('no puede recuperarla'), findsNothing);
    expect(find.textContaining('Mínimo'), findsNothing);
  });

  testWidgets('campo seguro, con foco automatico', (tester) async {
    await open(tester);
    final f = tester.widget<TextField>(field);
    expect(f.obscureText, isTrue);
    expect(f.autocorrect, isFalse);
    expect(f.enableSuggestions, isFalse);
    expect(f.enableIMEPersonalizedLearning, isFalse);
    expect(f.autofillHints, isNull);
    expect(f.autofocus, isTrue);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
  });

  testWidgets('"Abrir respaldo" deshabilitado con el campo vacio; sin largo '
      'minimo', (tester) async {
    await open(tester);
    expect(enabled(tester), isFalse);
    await tester.enterText(field, 'abc');
    await tester.pump();
    expect(enabled(tester), isTrue);
    await tester.tap(abrir);
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, 'abc');
  });

  testWidgets('la tecla del teclado envia', (tester) async {
    await open(tester);
    await tester.enterText(field, 'una clave inventada');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(result, 'una clave inventada');
  });

  testWidgets('mostrar y ocultar', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    await tester.tap(find.byTooltip('Mostrar contraseña'));
    await tester.pump();
    expect(tester.widget<TextField>(field).obscureText, isFalse);
    expect(
      tester.getSemantics(find.byTooltip('Ocultar contraseña')),
      isSemantics(tooltip: 'Ocultar contraseña', isButton: true),
    );
    await tester.tap(find.byTooltip('Ocultar contraseña'));
    await tester.pump();
    expect(tester.widget<TextField>(field).obscureText, isTrue);
    semantics.dispose();
  });

  testWidgets('tocar fuera no lo cierra; Cancelar si, sin resultado', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(field, 'una clave inventada');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(closed, isFalse);
    expect(find.text('Respaldo protegido'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
  });

  testWidgets('reintento: muestra el error y lo escrito vuelve seleccionado', (
    tester,
  ) async {
    await open(
      tester,
      initialPassword: 'clave mal escrita',
      errorText:
          'La contraseña no es correcta o el archivo está dañado. '
          'No se cambió nada.',
    );
    expect(
      find.text(
        'La contraseña no es correcta o el archivo está dañado. '
        'No se cambió nada.',
      ),
      findsOneWidget,
    );
    final c = tester.widget<TextField>(field).controller!;
    expect(c.text, 'clave mal escrita');
    expect(c.selection, const TextSelection(baseOffset: 0, extentOffset: 17));
    expect(enabled(tester), isTrue);
  });

  testWidgets('texto a 2,0 en 360 dp: sin overflow, con el error', (
    tester,
  ) async {
    await open(
      tester,
      textScale: 2,
      size: const Size(360, 780),
      initialPassword: 'x',
      errorText:
          'La contraseña no es correcta o el archivo está dañado. '
          'No se cambió nada.',
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Abrir respaldo').hitTestable(), findsOneWidget);
  });

  for (final (name, theme) in [('claro', null), ('oscuro', darkTheme())]) {
    testWidgets('contraste AA de los textos nuevos, tema $name', (
      tester,
    ) async {
      await open(
        tester,
        theme: theme,
        initialPassword: 'x',
        errorText:
            'La contraseña no es correcta o el archivo está dañado. '
            'No se cambió nada.',
      );
      final scheme = Theme.of(tester.element(abrir)).colorScheme;
      final bg = tester
          .widget<Material>(
            find
                .descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(Material),
                )
                .first,
          )
          .color!;
      final body = DefaultTextStyle.of(
        tester.element(
          find.text(
            'Este respaldo está protegido con contraseña. Escríbela para '
            'abrirlo.',
          ),
        ),
      ).style.color!;
      expect(contrastRatio(body, bg), greaterThanOrEqualTo(4.5));
      expect(
        contrastRatio(scheme.error, bg),
        greaterThanOrEqualTo(4.5),
        reason: 'texto de error',
      );
    });
  }
}
