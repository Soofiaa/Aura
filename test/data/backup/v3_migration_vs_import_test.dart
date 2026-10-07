import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/models/day_enums.dart';
import 'package:aura/domain/backup_codec.dart';
import 'package:aura/utils/day_key.dart';
import '../../drift/aura/generated/schema.dart';

/// Propiedad de la v4: para los mismos datos v3 y el mismo "hoy", migrar
/// la base y convertir el respaldo equivalente (upgradeBackupData) dejan
/// exactamente los mismos period_end. Ambos caminos usan la misma regla
/// D-2 (inferLegacyPeriodEnds).

const _settings = BackupSettings(
  onboardingSeen: true,
  notificationsEnabled: false,
  periodReminderEnabled: true,
  fertileWindowRemindersEnabled: false,
  showDetailsEnabled: false,
  reminderHour: 9,
  reminderMinute: 0,
);

late SchemaVerifier _verifier;

/// Migra una base v3 con [days] y devuelve sus period_end.
Future<Map<String, PeriodEndSource>> _viaMigration(
    List<BackupDay> days, String today) async {
  final schema = await _verifier.schemaAt(3);
  for (final d in days) {
    schema.rawDatabase.execute(
      'INSERT INTO daily_logs (date, is_period_day, flow, mood, notes, '
      'period_day_explicit) VALUES (?, ?, ?, ?, ?, ?)',
      [
        d.date,
        d.isPeriodDay ? 1 : 0,
        d.flow?.name,
        d.mood?.name,
        d.notes,
        d.periodDayExplicit ? 1 : 0,
      ],
    );
  }
  final db = AppDatabase.forTesting(schema.newConnection(), today: () => today);
  final rows = await db.select(db.dailyLogs).get();
  await db.close();
  return {
    for (final r in rows)
      if (r.periodEnd != null) r.date: r.periodEnd!,
  };
}

/// Convierte el respaldo v3 equivalente (pasando por el archivo JSON).
Map<String, PeriodEndSource> _viaImport(List<BackupDay> days, String today) {
  final text = encodeBackup(BackupData(
    schemaVersion: 3,
    appVersion: '1.0.1',
    exportedAt: '2026-10-04T10:15:00-03:00',
    days: days,
    settings: _settings,
  ));
  final decoded = (decodeBackup(utf8.encode(text)) as BackupParseSuccess).data;
  expect(decoded.schemaVersion, 3);
  final upgraded = upgradeBackupData(decoded, today: today);
  return {
    for (final d in upgraded.days)
      if (d.periodEnd != null) d.date: d.periodEnd!,
  };
}

/// Historial v3 inventado y reproducible: periodos de 1 a 8 dias con
/// huecos internos de 0 a 3 dias, ciclos de 18 a 40 dias, a veces un "no"
/// explicito tras el periodo y dias con solo sintomas.
List<BackupDay> _randomHistory(Random random) {
  final days = <String, BackupDay>{};
  var start = DayKey.addDays('2025-12-01', random.nextInt(60));
  final periods = 1 + random.nextInt(9);
  for (var p = 0; p < periods; p++) {
    final length = 1 + random.nextInt(8);
    var day = start;
    var last = start;
    for (var i = 0; i < length; i++) {
      days[day] = BackupDay(
        date: day,
        isPeriodDay: true,
        periodDayExplicit: random.nextInt(5) == 0,
        flow: random.nextBool() ? FlowIntensity.moderado : null,
      );
      last = day;
      day = DayKey.addDays(day, 1 + (random.nextInt(4) == 0 ? random.nextInt(4) : 0));
    }
    if (random.nextInt(3) == 0) {
      final no = DayKey.addDays(last, 1 + random.nextInt(9));
      days.putIfAbsent(no,
          () => BackupDay(date: no, isPeriodDay: false, periodDayExplicit: true));
    }
    if (random.nextBool()) {
      final symptom = DayKey.addDays(last, 3 + random.nextInt(10));
      days.putIfAbsent(
        symptom,
        () => BackupDay(
          date: symptom,
          isPeriodDay: false,
          periodDayExplicit: false,
          notes: '',
          symptoms: const [Symptom.cansancio],
        ),
      );
    }
    start = DayKey.addDays(start, 18 + random.nextInt(23));
  }
  return days.values.toList()..sort((a, b) => a.date.compareTo(b.date));
}

void main() {
  setUpAll(() {
    _verifier = SchemaVerifier(GeneratedHelper());
  });

  test('fixture backup_v3.json', () async {
    final v3 = (decodeBackup(
            File('test/fixtures/backup_v3.json').readAsBytesSync())
        as BackupParseSuccess)
        .data;
    for (final today in ['2026-10-04', '2026-10-30']) {
      expect(await _viaMigration(v3.days, today), _viaImport(v3.days, today),
          reason: 'hoy = $today');
    }
  });

  test('40 historiales inventados con distintos "hoy"', () async {
    final random = Random(20261007);
    var totalClosed = 0;
    for (var i = 0; i < 40; i++) {
      final days = _randomHistory(random);
      final lastDay = days.last.date;
      // "Hoy" alrededor del ultimo dia: antes (fechas futuras), dentro y
      // despues de los 7 dias.
      final today = DayKey.addDays(lastDay, random.nextInt(20) - 3);
      final migrated = await _viaMigration(days, today);
      final imported = _viaImport(days, today);
      expect(migrated, imported, reason: 'historial $i, hoy = $today');
      totalClosed += migrated.length;
    }
    // La propiedad no es trivial: los historiales si cierran periodos.
    expect(totalClosed, greaterThan(20));
  });
}
