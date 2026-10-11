import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/app_startup.dart';
import 'package:aura/data/backup/pre_migration_copy.dart';
import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/repositories/cycle_repository.dart' show appDatabase;
import 'package:aura/main.dart';
import 'package:aura/screens/update_error_screen.dart';
import 'drift/aura/generated/schema.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  /// Base v3 con un dia de sangrado cuya migracion falla en el paso 7
  /// mientras [shouldFail] devuelva true (hook de pruebas de la base).
  Future<(InitializedSchema, AppDatabase Function())> failingV3(
      bool Function() shouldFail) async {
    final schema = await verifier.schemaAt(3);
    schema.rawDatabase.execute(
        "INSERT INTO daily_logs (date, is_period_day) VALUES ('2026-08-01', 1)");
    AppDatabase create() => AppDatabase.forTesting(
          schema.newConnection(),
          migrationTestHook: (point) async {
            if (shouldFail() && point == MigrationTestPoint.afterVerification) {
              throw StateError('falla simulada de la migracion');
            }
          },
        );
    return (schema, create);
  }

  AppDatabase outOfSpaceDatabase() => AppDatabase.forTesting(LazyDatabase(
        () => throw PreMigrationCopyException(
          SqliteException(13, 'database or disk is full'),
          outOfSpace: true,
        ),
      ));

  group('AppStartup', () {
    test(
        'si la migracion falla: StartupFailed, no arranca nada y la base '
        'queda en v3; al reintentar sin fallo abre y arranca una vez',
        () async {
      var fail = true;
      final (schema, create) = await failingV3(() => fail);
      var readyCount = 0;
      final startup =
          AppStartup(createDatabase: create, onReady: () => readyCount++);

      final first = await startup.open();
      expect(first, isA<StartupFailed>());
      expect((first as StartupFailed).outOfSpace, isFalse);
      expect(readyCount, 0);
      expect(schema.rawDatabase.userVersion, 3);

      fail = false;
      final second = await startup.open();
      expect(second, isA<StartupReady>());
      expect((second as StartupReady).onboardingSeen, isFalse);
      expect(readyCount, 1);
      expect(schema.rawDatabase.userVersion, 5);
      final days = await appDatabase.select(appDatabase.dailyLogs).get();
      expect(days.single.date, '2026-08-01');
      await appDatabase.close();
    });

    test(
        'si crear la base lanza una excepcion: StartupFailed, y al '
        'reintentar se puede abrir', () async {
      var attempts = 0;
      var readyCount = 0;
      final startup = AppStartup(
        createDatabase: () {
          attempts++;
          if (attempts == 1) throw StateError('no se pudo crear la base');
          return AppDatabase.forTesting(
              NativeDatabase.memory(setup: enableForeignKeys));
        },
        onReady: () => readyCount++,
      );

      final first = await startup.open();
      expect(first, isA<StartupFailed>());
      expect((first as StartupFailed).outOfSpace, isFalse);
      expect(first.error, isA<StateError>());
      expect(readyCount, 0);

      final second = await startup.open();
      expect(second, isA<StartupReady>());
      expect(readyCount, 1);
      await appDatabase.close();
    });

    test('sin espacio para la copia previa: StartupFailed con outOfSpace',
        () async {
      var readyCount = 0;
      final startup = AppStartup(
          createDatabase: outOfSpaceDatabase, onReady: () => readyCount++);

      final result = await startup.open();

      expect(result, isA<StartupFailed>());
      expect((result as StartupFailed).outOfSpace, isTrue);
      expect(readyCount, 0);
    });
  });

  group('pantalla de error al actualizar', () {
    testWidgets(
        'muestra el mensaje con el correo y "Reintentar"; si reintentar '
        'funciona, entra a la app', (tester) async {
      var fail = true;
      final (_, create) = await failingV3(() => fail);
      var readyCount = 0;
      final startup =
          AppStartup(createDatabase: create, onReady: () => readyCount++);
      final initial = await startup.open();

      await tester
          .pumpWidget(AuraRoot(startup: startup, initialResult: initial));
      await tester.pumpAndSettle();

      expect(find.text(UpdateErrorScreen.title), findsOneWidget);
      expect(
        find.text('Aura no pudo abrir tus datos, pero no borró nada. Cierra '
            'la app y vuelve a abrirla. Si el problema sigue, no desinstales '
            'la app, porque se perderían tus datos, y escribe a '
            'sofia.menzel.dev@gmail.com'),
        findsOneWidget,
      );
      expect(find.textContaining('sofia.menzel.dev@gmail.com'), findsOneWidget);
      expect(find.text(UpdateErrorScreen.outOfSpaceMessage), findsNothing);

      // Un reintento que vuelve a fallar deja la misma pantalla.
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text(UpdateErrorScreen.title), findsOneWidget);
      expect(readyCount, 0);

      fail = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(find.text(UpdateErrorScreen.title), findsNothing);
      expect(find.text('Bienvenida a Aura'), findsOneWidget);
      expect(readyCount, 1);
      await appDatabase.close();
    });

    testWidgets('sin espacio muestra el mensaje propio', (tester) async {
      final startup =
          AppStartup(createDatabase: outOfSpaceDatabase, onReady: () {});
      final initial = await startup.open();

      await tester
          .pumpWidget(AuraRoot(startup: startup, initialResult: initial));
      await tester.pumpAndSettle();

      expect(find.text(UpdateErrorScreen.title), findsOneWidget);
      expect(find.text(UpdateErrorScreen.outOfSpaceMessage), findsOneWidget);
      expect(find.text(UpdateErrorScreen.outOfSpaceSafeMessage),
          findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });
  });

  testWidgets('la app llama "Cerrar" a la "x" de Material (por ejemplo, la '
      'del aviso de la importacion)', (tester) async {
    final (_, create) = await failingV3(() => false);
    final startup = AppStartup(createDatabase: create, onReady: () {});
    final initial = await startup.open();

    await tester.pumpWidget(AuraRoot(startup: startup, initialResult: initial));
    await tester.pumpAndSettle();

    final pantalla = tester.element(find.text('Bienvenida a Aura'));
    expect(MaterialLocalizations.of(pantalla).closeButtonTooltip, 'Cerrar');
    await appDatabase.close();
  });
}
