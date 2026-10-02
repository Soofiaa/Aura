import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'package:aura/data/database/app_database.dart';

void main() {
  test(
      'migracion v1 -> v2: agrega las columnas nuevas y fuerza '
      'notifications_enabled a false sin perder onboarding_seen', () async {
    // Base "v1" armada a mano con el esquema exacto que tenia la app
    // antes de esta fase (ver fase 2), para no depender de la
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
    // Dato real preexistente: onboarding ya visto, notificaciones
    // (viejo significado generico) activadas.
    raw.execute(
      'INSERT INTO app_settings (id, onboarding_seen, notifications_enabled) '
      'VALUES (0, 1, 1);',
    );
    // Le dice a drift "esta base ya esta en la version 1" para que
    // corra onUpgrade(1, 2) en vez de onCreate() al abrirla.
    raw.userVersion = 1;

    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));

    final row =
        await (db.select(db.appSettings)..where((t) => t.id.equals(0)))
            .getSingle();

    expect(row.onboardingSeen, isTrue, reason: 'dato viejo preservado');
    expect(row.notificationsEnabled, isFalse,
        reason: 'migracion debe forzarlo a false, no heredar el true viejo');
    expect(row.periodReminderEnabled, isTrue);
    expect(row.fertileWindowRemindersEnabled, isFalse);
    expect(row.showDetailsEnabled, isFalse);
    expect(row.reminderHour, 9);
    expect(row.reminderMinute, 0);

    await db.close();
  });
}
