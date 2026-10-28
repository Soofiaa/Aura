import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aura/data/backup/auto_drive_backup_service.dart';
import 'package:aura/data/backup/backup_service.dart' show runInSameIsolate;
import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/models/day_enums.dart';
import 'package:aura/data/notifications/notification_reconciler.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/screens/home_screen.dart';
import 'package:aura/screens/settings_screen.dart';
import 'package:aura/utils/day_key.dart';

import '../support/fake_backup.dart';
import '../support/fake_device_settings.dart';
import '../support/fake_drive_backup.dart';
import '../support/fake_drive_backup_settings_store.dart';
import '../support/fake_notification_scheduler.dart';

/// Modo embarazo, paso 3: Inicio y Ajustes.
void main() {
  late AppDatabase db;
  late CycleRepository repo;

  setUpAll(() async {
    await initializeDateFormatting();
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CycleRepository(db);
  });

  group('Inicio', () {
    Future<void> pumpInicio(WidgetTester tester, String hoy) async {
      final fecha = DateTime.parse(hoy);
      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(
          repository: repo,
          clock: () => fecha,
          reconciler: NotificationReconciler(repo, FakeNotificationScheduler(),
              clock: () => fecha),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('activo: semanas, fecha probable de parto y sin prediccion '
        'ni "Me llegó hoy"', (tester) async {
      await repo.markPeriodDays(['2026-08-01', '2026-08-02']);
      await repo.startPregnancy('2026-08-01');
      // 38 dias: 5 semanas y 3 dias; parto 01/08 + 280 = 08/05/2027.
      await pumpInicio(tester, '2026-09-08');

      expect(find.text('Tu embarazo'), findsOneWidget);
      expect(find.text('5 semanas y 3 días'), findsOneWidget);
      expect(find.textContaining('Fecha probable de parto: 8 de mayo de 2027'),
          findsOneWidget);
      expect(find.textContaining('Próximo período'), findsNothing);
      expect(find.text('Me llegó hoy'), findsNothing);
      await db.close();
    });

    testWidgets('terminado sin periodo despues: pausa sin mencionar como '
        'termino', (tester) async {
      await repo.markPeriodDays(['2026-08-01']);
      await repo.startPregnancy('2026-08-01');
      await repo.endPregnancy('2026-09-01', PregnancyOutcome.perdida);
      await pumpInicio(tester, '2026-09-08');

      expect(find.text('Predicciones en pausa'), findsOneWidget);
      expect(find.text('Tu ciclo actual'), findsOneWidget);
      expect(find.textContaining('Pérdida'), findsNothing);
      expect(find.text('Me llegó hoy'), findsOneWidget);
      await db.close();
    });
  });

  group('Ajustes', () {
    Future<void> pumpAjustes(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SettingsScreen(
          repository: repo,
          scheduler: FakeNotificationScheduler(),
          backupService: FakeBackupService(repo),
          fileGateway: FakeBackupFileGateway(),
          deviceSettings: FakeDeviceSettingsStore(),
          androidSystem: FakeAndroidSystem(),
          driveBackup: AutoDriveBackupService(
            settings: FakeDriveBackupSettingsStore(),
            gateway: FakeBlankDriveBackupGateway(),
            vault: FakeBlankKeystoreVault(),
            buildExportJson: () async => '{}',
            recordBackup: () async {},
            runner: runInSameIsolate,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    final interruptor = find.widgetWithText(SwitchListTile, 'Modo embarazo');

    Future<List<PregnancyRow>> embarazos(WidgetTester tester) async =>
        db.select(db.pregnancies).get();

    Future<void> tocarInterruptor(WidgetTester tester) async {
      await tester.scrollUntilVisible(interruptor, 200);
      await tester.tap(interruptor);
      await tester.pumpAndSettle();
    }

    testWidgets('activar usa por defecto el inicio del ultimo periodo; '
        'terminar pide como y cuando', (tester) async {
      final inicio = DayKey.addDays(DayKey.fromDate(DateTime.now()), -10);
      await repo.markPeriodDays([inicio]);
      await pumpAjustes(tester);

      await tocarInterruptor(tester);
      expect(find.text('Primer día de tu última regla'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      var rows = await embarazos(tester);
      expect(rows.single.startDate, inicio);
      expect(tester.widget<SwitchListTile>(interruptor).value, isTrue);

      await tocarInterruptor(tester);
      await tester.tap(find.text('Prefiero no decirlo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      rows = await embarazos(tester);
      expect(rows.single.endDate, DayKey.fromDate(DateTime.now()));
      expect(rows.single.outcome, PregnancyOutcome.sinEspecificar);
      expect(find.text('Modo embarazo terminado.'), findsOneWidget);
      await db.close();
    });

    testWidgets('"Lo activé por error" lo borra', (tester) async {
      await repo.startPregnancy(DayKey.fromDate(DateTime.now()));
      await pumpAjustes(tester);

      await tocarInterruptor(tester);
      await tester.tap(find.text('Lo activé por error'));
      await tester.pumpAndSettle();
      expect(await embarazos(tester), isEmpty);
      await db.close();
    });
  });
}
