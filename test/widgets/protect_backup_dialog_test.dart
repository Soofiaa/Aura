import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/main.dart';
import 'package:aura/utils/aura_localizations.dart';
import 'package:aura/utils/colors.dart';
import 'package:aura/widgets/protect_backup_dialog.dart';

import '../support/contrast.dart';

/// HU-06b CP3: dialogo "Proteger tu respaldo". Contrasenas inventadas.
void main() {
  late ProtectBackupChoice? result;
  late bool closed;

  final password = find.byKey(const ValueKey('protect-password'));
  final repeat = find.byKey(const ValueKey('protect-repeat'));
  final proteger = find.widgetWithText(FilledButton, 'Proteger y continuar');

  ThemeData darkTheme() => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
  );

  Future<void> open(
    WidgetTester tester, {
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
                result = await showProtectBackupDialog(ctx);
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
      tester.widget<FilledButton>(proteger).onPressed != null;

  Future<void> unfocus(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
  }

  testWidgets('textos, aviso visible y ayuda', (tester) async {
    await open(tester);
    expect(find.text('Proteger tu respaldo'), findsOneWidget);
    expect(
      find.text(
        'Elige una contraseña para cifrar el archivo. Sin ella, '
        'nadie podrá leerlo aunque lo obtenga.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Aura no guarda tu contraseña y no puede recuperarla. Si '
        'la olvidas, no podrás abrir este respaldo.',
      ),
      findsOneWidget,
    );
    expect(find.text('Contraseña'), findsOneWidget);
    expect(find.text('Repite la contraseña'), findsOneWidget);
    expect(
      find.text(
        'Mínimo 10 caracteres. Una frase con varias palabras es '
        'fácil de recordar y difícil de adivinar.',
      ),
      findsOneWidget,
    );
    expect(find.text('Continuar sin contraseña'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(enabled(tester), isFalse);
  });

  testWidgets('campos: ocultos, sin autocorreccion, sugerencias, '
      'autocompletado ni aprendizaje del teclado', (tester) async {
    await open(tester);
    for (final f in [password, repeat]) {
      final field = tester.widget<TextField>(f);
      expect(field.obscureText, isTrue);
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
      expect(field.enableIMEPersonalizedLearning, isFalse);
      expect(field.autofillHints, isNull);
    }
  });

  group('validacion', () {
    testWidgets('con menos de 10 caracteres no continua; el error aparece '
        'al salir del campo, no mientras se escribe', (tester) async {
      await open(tester);
      await tester.enterText(password, 'nueve-car');
      await tester.pump();
      expect(find.text('Usa al menos 10 caracteres.'), findsNothing);
      await tester.enterText(repeat, 'nueve-car');
      await tester.pump();
      expect(find.text('Usa al menos 10 caracteres.'), findsOneWidget);
      expect(enabled(tester), isFalse);
      await tester.tap(proteger);
      await tester.pumpAndSettle();
      expect(closed, isFalse);
    });

    testWidgets('si no coinciden no continua y lo dice al salir del campo', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(password, 'una frase larga');
      await tester.enterText(repeat, 'una frase larg');
      await tester.pump();
      expect(find.text('Las contraseñas no coinciden.'), findsNothing);
      await unfocus(tester);
      expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
      expect(enabled(tester), isFalse);
      await tester.tap(proteger);
      await tester.pumpAndSettle();
      expect(closed, isFalse);
    });

    testWidgets('igualdad exacta: una "ñ" escrita como "n" + tilde no '
        'coincide (sin normalizar)', (tester) async {
      await open(tester);
      await tester.enterText(password, 'contrase\u00f1a larga');
      await tester.enterText(repeat, 'contrasen\u0303a larga');
      await tester.pump();
      expect(enabled(tester), isFalse);
    });

    testWidgets('el largo se mide en puntos de codigo: 9 emoji + 1 letra '
        'alcanzan', (tester) async {
      await open(tester);
      const p = '🌸🌸🌸🌸🌸🌸🌸🌸🌸a';
      await tester.enterText(password, p);
      await tester.enterText(repeat, p);
      await tester.pump();
      expect(enabled(tester), isTrue);
    });

    testWidgets('valida y coincide: devuelve la contrasena escrita', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(password, 'mi casa es muy azul');
      await tester.enterText(repeat, 'mi casa es muy azul');
      await tester.pump();
      expect(enabled(tester), isTrue);
      await tester.tap(proteger);
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect((result as ProtectWithPassword).password, 'mi casa es muy azul');
      expect(find.text('Proteger tu respaldo'), findsNothing);
    });
  });

  testWidgets('el indicador cambia de etiqueta y se anuncia', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    expect(find.textContaining('Fortaleza:'), findsNothing);
    for (final (p, label) in [
      ('contraseña', 'Débil'),
      ('mi casa es azul', 'Aceptable'),
      ('mi casa es muy azul', 'Fuerte'),
    ]) {
      await tester.enterText(password, p);
      await tester.pump();
      expect(find.text('Fortaleza: $label'), findsOneWidget);
      expect(find.text('Es solo una orientación.'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Fortaleza: $label. Es solo una orientación.'),
        findsOneWidget,
      );
    }
    semantics.dispose();
  });

  testWidgets('mostrar y ocultar afecta a los dos campos', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    expect(find.byTooltip('Mostrar contraseña'), findsOneWidget);
    await tester.tap(find.byTooltip('Mostrar contraseña'));
    await tester.pump();
    expect(tester.widget<TextField>(password).obscureText, isFalse);
    expect(tester.widget<TextField>(repeat).obscureText, isFalse);
    expect(find.byTooltip('Ocultar contraseña'), findsOneWidget);
    expect(
      tester.getSemantics(find.byTooltip('Ocultar contraseña')),
      isSemantics(tooltip: 'Ocultar contraseña', isButton: true),
    );
    await tester.tap(find.byTooltip('Ocultar contraseña'));
    await tester.pump();
    expect(tester.widget<TextField>(password).obscureText, isTrue);
    expect(tester.widget<TextField>(repeat).obscureText, isTrue);
    semantics.dispose();
  });

  group('sin contrasena', () {
    Finder confirmButton() => find.descendant(
      of: find.byType(AlertDialog).last,
      matching: find.text('Continuar sin contraseña'),
    );

    testWidgets('pide confirmacion; "Volver" vuelve al dialogo sin elegir', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Continuar sin contraseña'));
      await tester.pumpAndSettle();
      expect(find.text('¿Continuar sin contraseña?'), findsOneWidget);
      expect(
        find.text(
          'El archivo contendrá tus datos sin cifrar. Cualquiera '
          'que lo obtenga podrá leerlos.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Volver'));
      await tester.pumpAndSettle();
      expect(find.text('¿Continuar sin contraseña?'), findsNothing);
      expect(find.text('Proteger tu respaldo'), findsOneWidget);
      expect(closed, isFalse);
    });

    testWidgets('confirmado: devuelve "sin contrasena"', (tester) async {
      await open(tester);
      await tester.tap(find.text('Continuar sin contraseña'));
      await tester.pumpAndSettle();
      await tester.tap(confirmButton());
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(result, isA<ProtectWithoutPassword>());
    });
  });

  testWidgets('tocar fuera del dialogo no lo cierra ni pierde lo escrito', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(password, 'mi casa es muy azul');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(closed, isFalse);
    expect(find.text('Proteger tu respaldo'), findsOneWidget);
    expect(
      tester.widget<TextField>(password).controller!.text,
      'mi casa es muy azul',
    );
  });

  testWidgets('"atras" cierra sin elegir', (tester) async {
    await open(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
  });

  testWidgets('el indicador es una region en vivo (se anuncia al cambiar de '
      'nivel)', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    await tester.enterText(password, 'mi casa es azul');
    await tester.pump();
    final node = tester.getSemantics(
      find.bySemanticsLabel(
        'Fortaleza: Aceptable. Es solo una orientaci\u00f3n.',
      ),
    );
    expect(node, isSemantics(isLiveRegion: true));
    semantics.dispose();
  });

  testWidgets('Cancelar cierra sin elegir', (tester) async {
    await open(tester);
    await tester.enterText(password, 'mi casa es muy azul');
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
  });

  testWidgets('texto a 2,0 en 360 dp: sin overflow, con errores e indicador', (
    tester,
  ) async {
    await open(tester, textScale: 2, size: const Size(360, 780));
    await tester.enterText(password, 'corta');
    await tester.enterText(repeat, 'otra');
    await unfocus(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Usa al menos 10 caracteres.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Continuar sin contraseña'),
      50,
      scrollable: find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(tester.takeException(), isNull);
  });

  for (final (name, theme) in [('claro', null), ('oscuro', darkTheme())]) {
    testWidgets('contraste AA (4,5:1) de los textos nuevos, tema $name', (
      tester,
    ) async {
      await open(tester, theme: theme);
      await tester.enterText(password, 'mi casa es muy azul');
      await tester.pump();
      final scheme = Theme.of(tester.element(proteger)).colorScheme;
      final dialogBg = tester
          .widget<Material>(
            find
                .descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(Material),
                )
                .first,
          )
          .color!;
      final strength = tester
          .widget<Text>(find.text('Fortaleza: Fuerte'))
          .style!
          .color!;
      final note = tester
          .widget<Text>(find.text('Es solo una orientación.'))
          .style!
          .color!;
      expect(contrastRatio(strength, dialogBg), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(note, dialogBg), greaterThanOrEqualTo(4.5));
      expect(
        contrastRatio(scheme.onErrorContainer, scheme.errorContainer),
        greaterThanOrEqualTo(4.5),
        reason: 'aviso de que no hay recuperacion',
      );
    });
  }

  testWidgets('la contrasena escrita no aparece en ningun texto ni en la '
      'semantica mientras esta oculta', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    const secreto = 'Secreto Inventado 2026';
    await tester.enterText(password, secreto);
    await tester.enterText(repeat, secreto);
    await unfocus(tester);

    for (final e in find.byType(Text).evaluate()) {
      final data = (e.widget as Text).data ?? '';
      expect(data, isNot(contains(secreto)));
    }
    bool containsSecret(SemanticsNode node) {
      final d = node.getSemanticsData();
      return [
        d.label,
        d.value,
        d.hint,
        d.tooltip,
        d.increasedValue,
        d.decreasedValue,
      ].any((t) => t.contains('Secreto'));
    }

    // Hay nodos (sanity check) y ninguno lleva la contrasena.
    expect(find.semantics.byPredicate((_) => true), findsWidgets);
    expect(find.semantics.byPredicate(containsSecret), findsNothing);
    semantics.dispose();
  });
}
