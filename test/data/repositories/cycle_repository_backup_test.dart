import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/models/day_enums.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/domain/backup_codec.dart';

BackupData _fixture() {
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
      schemaVersion: 3,
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

      expect(data.schemaVersion, 3);
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
