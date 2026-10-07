import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'package:aura/data/database/app_database.dart';

void main() {
  test(
      'migracion encadenada v1 -> v4: agrega todas las columnas nuevas y '
      'preserva los datos viejos', () async {
    // Base "v1" armada a mano con el esquema exacto que tenia la app
    // antes de la fase de notificaciones, para no depender de la
    // herramienta completa de schema-snapshots de drift_dev.
    final raw = sqlite3.sqlite3.openInMemory();
    raw.execute('''
      CREATE TABLE daily_logs (
        date TEXT NOT NULL,
        is_period_day INTEGER NOT NULL DEFAULT 0 CHECK (is_period_day IN (0, 1)),
        flow TEXT NULL,
        mood TEXT NULL,
        notes TEXT NULL,
        PRIMARY KEY (date),
        CHECK ((flow IS NULL) OR (is_period_day = 1))
      );
    ''');
    raw.execute('''
      CREATE TABLE daily_log_symptoms (
        log_date TEXT NOT NULL,
        symptom TEXT NOT NULL,
        PRIMARY KEY (log_date, symptom),
        FOREIGN KEY (log_date) REFERENCES daily_logs (date) ON DELETE CASCADE
      );
    ''');
    raw.execute('''
      CREATE TABLE app_settings (
        id INTEGER NOT NULL DEFAULT 0,
        onboarding_seen INTEGER NOT NULL DEFAULT 0 CHECK (onboarding_seen IN (0, 1)),
        notifications_enabled INTEGER NOT NULL DEFAULT 1 CHECK (notifications_enabled IN (0, 1)),
        PRIMARY KEY (id),
        CHECK (id = 0)
      );
    ''');
    // Dato real preexistente: un dia de sangrado ya registrado, y
    // onboarding/notificaciones con el significado viejo.
    raw.execute(
      "INSERT INTO daily_logs (date, is_period_day) VALUES ('2026-01-01', 1);",
    );
    raw.execute(
      'INSERT INTO app_settings (id, onboarding_seen, notifications_enabled) '
      'VALUES (0, 1, 1);',
    );
    // Le dice a drift "esta base ya esta en la version 1" para que corra
    // la cadena completa al abrirla: los dos bloques escritos a mano (v1 ->
    // v3) y el paso generado 3 -> 4.
    raw.userVersion = 1;

    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));

    final settingsRow =
        await (db.select(db.appSettings)..where((t) => t.id.equals(0)))
            .getSingle();
    expect(settingsRow.onboardingSeen, isTrue, reason: 'dato viejo preservado');
    expect(settingsRow.notificationsEnabled, isFalse,
        reason: 'migracion debe forzarlo a false, no heredar el true viejo');
    expect(settingsRow.periodReminderEnabled, isTrue);
    expect(settingsRow.fertileWindowRemindersEnabled, isFalse);
    expect(settingsRow.showDetailsEnabled, isFalse);
    expect(settingsRow.reminderHour, 9);
    expect(settingsRow.reminderMinute, 0);
    expect(settingsRow.typicalPeriodLength, 5);

    final dayRow = await (db.select(db.dailyLogs)
          ..where((t) => t.date.equals('2026-01-01')))
        .getSingle();
    expect(dayRow.isPeriodDay, isTrue, reason: 'dato viejo preservado');
    expect(dayRow.periodDayExplicit, isFalse,
        reason:
            'nunca existio un camino que escribiera una negacion explicita '
            'antes de esta version; default false es correcto');
    expect(dayRow.periodEnd, isNull,
        reason: 'un periodo de 1 solo dia queda abierto (D-2)');
    expect(raw.userVersion, 4);

    await db.close();
  });

  test(
      'migracion v2 -> v4: agrega period_day_explicit con default false '
      'sin tocar is_period_day existente', () async {
    // Base "v2" (con las columnas de notificaciones de app_settings ya
    // presentes, pero sin period_day_explicit en daily_logs).
    final raw = sqlite3.sqlite3.openInMemory();
    raw.execute('''
      CREATE TABLE daily_logs (
        date TEXT NOT NULL,
        is_period_day INTEGER NOT NULL DEFAULT 0 CHECK (is_period_day IN (0, 1)),
        flow TEXT NULL,
        mood TEXT NULL,
        notes TEXT NULL,
        PRIMARY KEY (date),
        CHECK ((flow IS NULL) OR (is_period_day = 1))
      );
    ''');
    raw.execute('''
      CREATE TABLE daily_log_symptoms (
        log_date TEXT NOT NULL,
        symptom TEXT NOT NULL,
        PRIMARY KEY (log_date, symptom),
        FOREIGN KEY (log_date) REFERENCES daily_logs (date) ON DELETE CASCADE
      );
    ''');
    raw.execute('''
      CREATE TABLE app_settings (
        id INTEGER NOT NULL DEFAULT 0,
        onboarding_seen INTEGER NOT NULL DEFAULT 0 CHECK (onboarding_seen IN (0, 1)),
        notifications_enabled INTEGER NOT NULL DEFAULT 0 CHECK (notifications_enabled IN (0, 1)),
        period_reminder_enabled INTEGER NOT NULL DEFAULT 1 CHECK (period_reminder_enabled IN (0, 1)),
        fertile_window_reminders_enabled INTEGER NOT NULL DEFAULT 0 CHECK (fertile_window_reminders_enabled IN (0, 1)),
        show_details_enabled INTEGER NOT NULL DEFAULT 0 CHECK (show_details_enabled IN (0, 1)),
        reminder_hour INTEGER NOT NULL DEFAULT 9,
        reminder_minute INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (id),
        CHECK (id = 0)
      );
    ''');
    raw.execute(
      "INSERT INTO daily_logs (date, is_period_day) VALUES ('2026-02-10', 0);",
    );
    raw.userVersion = 2;

    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));

    final dayRow = await (db.select(db.dailyLogs)
          ..where((t) => t.date.equals('2026-02-10')))
        .getSingle();
    expect(dayRow.isPeriodDay, isFalse, reason: 'dato viejo preservado');
    expect(dayRow.periodDayExplicit, isFalse);
    expect(dayRow.periodEnd, isNull);
    expect(raw.userVersion, 4);

    await db.close();
  });
}
