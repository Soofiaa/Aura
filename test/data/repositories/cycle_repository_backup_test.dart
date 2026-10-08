import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/models/day_enums.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/domain/backup_codec.dart';

/// El fixture v3 ya convertido al schema actual, como lo importa la app.
BackupData _fixture() => upgradeBackupData(_fixtureV3(), today: '2026-10-04');

BackupData _fixtureV3() {
  final result = decodeBackup(
      utf8.encode(File('test/fixtures/backup_v3.json').readAsStringSync()));
  return (result as BackupParseSuccess).data;
}

const _settings = BackupSettings(
  onboardingSeen: true,
  notificationsEnabled: false,
  periodReminderEnabled: true,
  fertileWindowRemindersEnabled: false,
  showDetailsEnabled: false,
  reminderHour: 9,
  reminderMinute: 0,
);

BackupData _dataWith(List<BackupDay> days) => BackupData(
      schemaVersion: currentBackupSchemaVersion,
      appVersion: '1.0.1',
      exportedAt: '2026-10-04T10:15:00-03:00',
      days: days,
      settings: _settings,
    );

void main() {
  late AppDatabase db;
  late CycleRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CycleRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// Datos "actuales" del telefono, distintos de los del fixture.
  Future<void> seedCurrentData() async {
    await repo.upsertDay(
      date: '2026-05-01',
      isPeriodDaySwitch: true,
      flow: FlowIntensity.ligero,
      mood: Mood.feliz,
      notes: 'dato actual',
      symptoms: {Symptom.acne},
    );
    await repo.markPeriodDays(['2026-05-02', '2026-05-03']);
    await repo.setNotificationsEnabled(true);
    await repo.setReminderTime(hour: 7, minute: 45);
  }

  test('el schema del formato de respaldo es el de la base', () {
    expect(currentBackupSchemaVersion, db.schemaVersion);
  });

  group('readBackupData', () {
    test('lee todas las tablas con dias por fecha y sintomas por nombre',
        () async {
      await repo.upsertDay(
        date: '2026-03-02',
        isPeriodDaySwitch: false,
        symptoms: {Symptom.hinchazon, Symptom.acne, Symptom.cansancio},
      );
      await repo.markPeriodDay('2026-03-01');
      await repo.setReminderTime(hour: 20, minute: 5);

      final data = await repo.readBackupData(
          appVersion: '1.0.1', exportedAt: '2026-10-04T10:15:00-03:00');

      expect(data.schemaVersion, currentBackupSchemaVersion);
      expect([for (final d in data.days) d.date], ['2026-03-01', '2026-03-02']);
      expect(data.days[1].symptoms,
          [Symptom.acne, Symptom.cansancio, Symptom.hinchazon]);
      expect(data.settings.reminderHour, 20);
      expect(data.settings.reminderMinute, 5);
    });

    test('base vacia: sin dias y con los ajustes de fabrica', () async {
      final data = await repo.readBackupData(
          appVersion: '1.0.1', exportedAt: '2026-10-04T10:15:00-03:00');
      expect(data.days, isEmpty);
      expect(data.settings.periodReminderEnabled, isTrue);
      expect(data.settings.reminderHour, 9);
    });
  });

  group('replaceAllWithBackup', () {
    test('reemplaza todos los dias y sintomas por los del respaldo', () async {
      await seedCurrentData();
      final fixture = _fixture();

      await repo.replaceAllWithBackup(fixture);

      expect(await repo.getDay('2026-05-01'), isNull);
      expect(await repo.countDays(), 7);
      final exported = await repo.readBackupData(
          appVersion: fixture.appVersion, exportedAt: fixture.exportedAt);
      expect(exported.days, fixture.days);
    });

    test('exportar desde una base e importar en otra deja datos identicos',
        () async {
      await repo.replaceAllWithBackup(_fixture());
      final exportado = await repo.readBackupData(
          appVersion: '1.0.1', exportedAt: '2026-10-04T10:15:00-03:00');

      final otraDb = AppDatabase.forTesting(
          NativeDatabase.memory(setup: enableForeignKeys));
      final otroRepo = CycleRepository(otraDb);
      await otroRepo.replaceAllWithBackup(_dataWith([
        const BackupDay(
            date: '2020-01-01', isPeriodDay: true, periodDayExplicit: false),
      ]));
      final texto = encodeBackup(exportado);
      final reimportado =
          (decodeBackup(utf8.encode(texto)) as BackupParseSuccess).data;
      await otroRepo.replaceAllWithBackup(reimportado);

      final reExportado = await otroRepo.readBackupData(
          appVersion: '1.0.1', exportedAt: '2026-10-04T10:15:00-03:00');
      expect(encodeBackup(reExportado), texto);
      await otraDb.close();
    });

    test('importa los ajustes de recordatorios pero conserva el interruptor '
        'general del telefono (encendido)', () async {
      await repo.setNotificationsEnabled(true);
      await repo.replaceAllWithBackup(_dataWith(const []).withSettings(
        const BackupSettings(
          onboardingSeen: false,
          notificationsEnabled: false,
          periodReminderEnabled: false,
          fertileWindowRemindersEnabled: true,
          showDetailsEnabled: true,
          reminderHour: 22,
          reminderMinute: 10,
        ),
      ));

      final s = await repo.getNotificationSettings();
      expect(s.notificationsEnabled, isTrue);
      expect(s.periodReminderEnabled, isFalse);
      expect(s.fertileWindowRemindersEnabled, isTrue);
      expect(s.showDetailsEnabled, isTrue);
      expect(s.reminderHour, 22);
      expect(s.reminderMinute, 10);
      expect(await repo.getOnboardingSeen(), isTrue,
          reason: 'quien importa ya esta usando la app');
    });

    test('conserva el interruptor general del telefono (apagado) aunque el '
        'respaldo lo traiga encendido', () async {
      await repo.setNotificationsEnabled(false);
      await repo.replaceAllWithBackup(_fixture());
      expect(await repo.getNotificationsEnabled(), isFalse);
    });

    test('si una fila viola el CHECK, la transaccion se revierte y los datos '
        'actuales quedan intactos', () async {
      await seedCurrentData();
      final antes = await repo.readBackupData(
          appVersion: 'x', exportedAt: 'x');

      // Sin pasar por decodeBackup: flujo en un dia sin sangrado, que el
      // CHECK de daily_logs rechaza a mitad de la insercion.
      final invalido = _dataWith(const [
        BackupDay(
            date: '2026-01-01', isPeriodDay: true, periodDayExplicit: false),
        BackupDay(
          date: '2026-01-02',
          isPeriodDay: false,
          periodDayExplicit: false,
          flow: FlowIntensity.abundante,
        ),
      ]);

      await expectLater(repo.replaceAllWithBackup(invalido), throwsA(anything));

      final despues = await repo.readBackupData(
          appVersion: 'x', exportedAt: 'x');
      expect(despues.days, antes.days);
      expect(despues.settings, antes.settings);
    });

    test('fechas repetidas (clave primaria) tambien revierten todo', () async {
      await seedCurrentData();
      final repetido = _dataWith(const [
        BackupDay(
            date: '2026-01-01', isPeriodDay: true, periodDayExplicit: false),
        BackupDay(
            date: '2026-01-01', isPeriodDay: false, periodDayExplicit: false),
      ]);

      await expectLater(repo.replaceAllWithBackup(repetido), throwsA(anything));
      expect(await repo.countDays(), 3);
      expect(await repo.getSymptomsForDay('2026-05-01'), {Symptom.acne});
    });

    test('los streams de ciclos y de dias de sangrado emiten los datos '
        'importados', () async {
      await seedCurrentData();
      final ciclos = repo.watchDerivedCycles();
      final dias = repo.watchPeriodDayDates();
      expect(await dias.first, ['2026-05-01', '2026-05-02', '2026-05-03']);

      await repo.replaceAllWithBackup(_fixture());

      expect(await dias.first,
          ['2026-08-28', '2026-08-29', '2026-08-30', '2026-08-31', '2026-09-25']);
      final derivados = await ciclos.first;
      expect(derivados.map((c) => c.startDate), ['2026-08-28', '2026-09-25']);
    });
  });

  test('countDays cuenta todos los dias registrados, con o sin sangrado',
      () async {
    expect(await repo.countDays(), 0);
    await seedCurrentData();
    await repo.upsertDay(date: '2026-06-01', isPeriodDaySwitch: false);
    expect(await repo.countDays(), 4);
  });

  group('respaldo v4: period_end y duracion habitual', () {
    test('readBackupData exporta period_end y typicalPeriodLength', () async {
      await repo.markPeriodDays(['2026-03-01', '2026-03-02']);
      await db.into(db.dailyLogs).insertOnConflictUpdate(
            DailyLogsCompanion.insert(
              date: '2026-03-02',
              isPeriodDay: const Value(true),
              periodEnd: const Value(PeriodEndSource.declared),
            ),
          );
      await repo.setTypicalPeriodLength(6);

      final data =
          await repo.readBackupData(appVersion: 'x', exportedAt: 'x');
      expect(data.days.map((d) => d.periodEnd),
          [null, PeriodEndSource.declared]);
      expect(data.settings.typicalPeriodLength, 6);
    });

    test('replaceAllWithBackup importa period_end y typicalPeriodLength',
        () async {
      await repo.replaceAllWithBackup(_dataWith(const [
        BackupDay(
            date: '2026-03-01', isPeriodDay: true, periodDayExplicit: false),
        BackupDay(
          date: '2026-03-02',
          isPeriodDay: true,
          periodDayExplicit: false,
          periodEnd: PeriodEndSource.inferred,
        ),
      ]).withSettings(const BackupSettings(
        onboardingSeen: true,
        notificationsEnabled: false,
        periodReminderEnabled: true,
        fertileWindowRemindersEnabled: false,
        showDetailsEnabled: false,
        reminderHour: 9,
        reminderMinute: 0,
        typicalPeriodLength: 3,
      )));

      expect((await repo.getDay('2026-03-02'))!.periodEnd,
          PeriodEndSource.inferred);
      expect(await repo.getTypicalPeriodLength(), 3);
      expect((await repo.getDerivedCycles()).single.isClosed, isTrue);
    });

    test(
        'replaceAllWithBackup rechaza datos de un schema anterior sin '
        'convertir y no toca nada', () async {
      await seedCurrentData();
      final antes = await repo.readBackupData(appVersion: 'x', exportedAt: 'x');

      await expectLater(
          repo.replaceAllWithBackup(_fixtureV3()), throwsArgumentError);

      final despues =
          await repo.readBackupData(appVersion: 'x', exportedAt: 'x');
      expect(despues.days, antes.days);
      expect(despues.settings, antes.settings);
    });
  });

  // HU-05, CP5a: "Mostrar ovulacion y ventana fertil" (schema 5).
  group('HU-05 CP5a - showFertileWindow', () {
    BackupData fixtureFile(String name) {
      final result = decodeBackup(
          utf8.encode(File('test/fixtures/$name').readAsStringSync()));
      return upgradeBackupData((result as BackupParseSuccess).data,
          today: '2026-10-07');
    }

    test('base nueva: activado; el setter lo cambia y lo ven los tres '
        'lectores', () async {
      expect(await repo.getShowFertileWindow(), isTrue);
      expect((await repo.getPredictionInputs()).showFertileWindow, isTrue);
      expect((await repo.getNotificationSettings()).showFertileWindow, isTrue);

      await repo.setShowFertileWindow(false);
      expect(await repo.getShowFertileWindow(), isFalse);
      expect((await repo.getPredictionInputs()).showFertileWindow, isFalse);
      expect(
          (await repo.getNotificationSettings()).showFertileWindow, isFalse);
    });

    test('ida y vuelta de respaldo con el interruptor en true y en false',
        () async {
      for (final value in [true, false]) {
        await repo.setShowFertileWindow(value);
        final exported = await repo.readBackupData(
            appVersion: '1.1.0', exportedAt: '2026-10-07T10:00:00-03:00');
        expect(exported.settings.showFertileWindow, value);

        // Pasa por el texto del archivo, como en la app.
        final parsed = decodeBackup(utf8.encode(encodeBackup(exported)));
        final data = (parsed as BackupParseSuccess).data;

        final other = AppDatabase.forTesting(
            NativeDatabase.memory(setup: enableForeignKeys));
        final otherRepo = CycleRepository(other);
        await otherRepo.setShowFertileWindow(!value);
        await otherRepo.replaceAllWithBackup(data);
        expect(await otherRepo.getShowFertileWindow(), value,
            reason: 'valor $value');
        await other.close();
      }
    });

    test('importar backup_v5.json deja el interruptor apagado', () async {
      await repo.replaceAllWithBackup(fixtureFile('backup_v5.json'));
      expect(await repo.getShowFertileWindow(), isFalse);
    });

    test('respaldos v3 y v4 se restauran con true', () async {
      for (final name in ['backup_v3.json', 'backup_v4.json']) {
        await repo.setShowFertileWindow(false);
        await repo.replaceAllWithBackup(fixtureFile(name));
        expect(await repo.getShowFertileWindow(), isTrue, reason: name);
      }
    });

    test('"Borrar todos los datos" lo devuelve a true (default de la '
        'columna)', () async {
      await repo.setShowFertileWindow(false);
      await repo.deleteAllData();
      expect(await repo.getShowFertileWindow(), isTrue);
      expect((await repo.getPredictionInputs()).showFertileWindow, isTrue);
    });

    test('watchPredictionInputs emite de nuevo al cambiarlo', () async {
      final emitted = <bool>[];
      final sub = repo
          .watchPredictionInputs()
          .listen((i) => emitted.add(i.showFertileWindow));
      await pumpEventQueue();
      await repo.setShowFertileWindow(false);
      await pumpEventQueue();
      await sub.cancel();
      expect(emitted.first, isTrue);
      expect(emitted.last, isFalse);
    });
  });
}

extension on BackupData {
  BackupData withSettings(BackupSettings settings) => BackupData(
        schemaVersion: schemaVersion,
        appVersion: appVersion,
        exportedAt: exportedAt,
        days: days,
        settings: settings,
      );
}
