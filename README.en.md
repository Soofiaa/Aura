# Aura

An Android app to log your menstrual cycle and estimate its phases. **Local-first**: no account, no server of its own and no analytics. Data lives on the phone and only leaves in a backup the user chooses: a file or, if they turn it on, their own Google Drive.

[Versión en español](README.md)

**Website:** [soofiaa.github.io/Aura/en](https://soofiaa.github.io/Aura/en/) · [User guide](https://soofiaa.github.io/Aura/en/guide.html) · [Project report](https://soofiaa.github.io/Aura/en/report.html)

> **Status:** v1.2.0, in closed testing on Google Play · Android only · personal portfolio project, in real daily use. The new features already in the code (English UI, pregnancy mode, dark theme, daily reminder, birth-control reminder, PDF summary, redesigned statistics and widget) arrive in the next Google Play update.

## Screenshots

<table><tr><td align="center"><img src="docs/screenshots/inicio.png" width="170" alt="Home: current phase and next period"></td><td align="center"><img src="docs/screenshots/calendario.png" width="170" alt="Calendar with the estimated fertile window"></td><td align="center"><img src="docs/screenshots/registrar-dia.png" width="170" alt="Log a day"></td><td align="center"><img src="docs/screenshots/estadisticas.png" width="170" alt="Statistics"></td><td align="center"><img src="docs/screenshots/ajustes.png" width="170" alt="Settings and data"></td></tr></table>

Order: Home, Calendar, Log a day, Statistics and Settings. *The screenshots are from earlier versions (Settings is from 1.1.0, before the Drive backup) and don't show the features in the next update.* (They show the Spanish UI.)

## What it does

- Logs bleeding days, flow intensity, mood, symptoms and notes.
- "Me llegó hoy" ("it started today") on Home and in the Calendar: logs only the first day of the period (today, yesterday or another day).
- Derives cycles from those logs (cycles are never created by hand).
- Predicts the next period with a **range** and a confidence level (low / medium / high). The estimated ovulation and fertile window are only shown with medium or high confidence and when the period is not late (on Home, not during the menstrual phase either), and can be hidden in Settings.
- Shows the current phase: menstrual, follicular, ovulatory and luteal (none while the period is late).
- Calendar showing logged days, the estimated days of the current period (dotted border), the estimated fertile window and ovulation (under Home's confidence, lateness and toggle conditions) and multi-day selection; it rolls over to the next day at midnight and has a "Go to today" button.
- Statistics with summary cards (typical cycle, typical period, regularity and next period), a bar chart of recent cycles with the typical length, short explanations of each figure, and mood shown as bars.
- **PDF summary for the doctor** (button in Statistics): generated on the phone, with no server, including cycle and period length, regularity, the next-period estimate, a chart and history of the last 12 cycles, top symptoms and mood, flow, pregnancies (current and previous) and the birth-control method if configured. Shared through Android's share sheet (the user chooses where).
- Optional local reminders, with discreet text by default, plus an optional "Did your period arrive?" notice on the first day of lateness.
- Daily reminder (optional, off by default): a notification every day at the reminder time if that day has nothing logged yet.
- Birth-control reminder (optional): pill (every day), patch (weekly, 3 weeks + 1 patch-free week), ring (3 weeks in, 1 out), monthly injection (every 30 days) or 3-month injection (every 13 weeks), with its own time and generic text unless "Show details in notifications" is on.
- **Pregnancy mode** (Settings → "Pregnancy mode"): from the first day of the last period, Home shows weeks and days of pregnancy and the probable due date (estimated from that date). It pauses predictions, the fertile window and cycle reminders, and hides "My period started today" in the Calendar. It ends by choosing the outcome (birth / loss / not specified) and date, or with "I turned it on by mistake", which deletes it; the last ended pregnancy can be corrected or deleted. No celebratory texts: the same message for any outcome. Predictions resume once a new period is logged after the end, and cycles spanning a pregnancy are left out of predictions, the chart and the PDF.
- **Home-screen widget** (Android): shows the next period ("In 5 days · Nov 14 – Nov 20"), the day of the period, days late or weeks of pregnancy; tapping it opens Aura.
- Dark theme: Settings → Theme (system default, light or dark; per phone).
- Interface in Spanish or English following the phone language; edge-to-edge display and no orientation lock.
- Lets you mark the end of a period and remove marks.
- Backup and restore to a JSON file from Settings → "Your data", with an optional password to encrypt the file, "Undo" right after importing, and "Undo last import" in Settings while the pre-import copy exists.
- Backup reminder: if 30 days pass without one, Home shows a card (no notification); it only keeps the date of the last backup on the phone and sends nothing off it.
- **Automatic backup to Google Drive** (optional, off by default) in Settings → "Your data": once a day — when the app is opened, resumed, or a log is saved — it uploads the same encrypted backup file to an **Aura** folder in the user's own Google Drive. The password is chosen once and never leaves the phone: the key is sealed in Android's Keystore, and without that password the file cannot be read. Aura connects to Drive with the `drive.file` scope, which only lets it see the files it creates itself; it can be disconnected from Settings, and "Delete all data" also forgets the account. The build needs an OAuth client ID: see [`docs/DRIVE_SETUP.md`](docs/DRIVE_SETUP.md).
- Full data wipe from Settings (followed by database compaction so no leftovers remain).

## Privacy by design

- Data lives in a SQLite database inside the app's private storage.
- `allowBackup="false"`: Android does not copy it to the cloud, and `dataExtractionRules` blocks direct phone-to-phone transfer over cable or Wi-Fi as well: the only way data leaves is through Aura's own backup file.
- **"Hide Aura from Recents"** (on by default, can be turned off in Settings → Privacy): the app preview in the Recents screen is blank, and screenshots or screen recordings are blocked.
- After deleting all data, the database is compacted (`VACUUM`) and freed pages overwrite what was deleted (`secure_delete`): no remnants of deleted notes or symptoms remain.
- Data only leaves the phone if the user creates a backup and chooses where to save it or who to share it with, or if they turn on the automatic backup to their own Google Drive (optional, see above), or if they share the PDF summary (see below). The file contains health data. It can be protected with a password (optional): it is encrypted on the phone (AES-256-GCM, with the key derived using Argon2id) and cannot be read without the password (a weak password can be guessed). For file backups, Aura does not store the password and cannot recover it; for the automatic Drive backup it keeps it sealed in the Android Keystore so it can back up every day without asking. Without a password, the file is not encrypted and anyone who opens it can read it. The password protects only the file, not the data inside the phone. Aura does not receive or keep a copy. The `INTERNET` permission exists only for the automatic Drive backup; with it off, the app does not use the network.
- When updating from 1.0 (schema v3), before converting the database the app saves a safety copy in its private storage; it is deleted after saving a backup to the phone, on app start once it is more than 30 days old, or with "Delete all data".
- When an import is confirmed, the app first saves an unencrypted copy of the current data in its private storage, only for "Undo"; the next import replaces it and "Delete all data" removes it.
- Notifications use generic text and private lock-screen visibility unless the user opts into details.
- **Widget:** anyone looking at the home screen can read it. With **"Discreet widget"** (Settings → Privacy) it shows only "Aura · Tap to open", no data, and the widget picker description is just "Aura". So it can change day without opening the app, Aura leaves the widget's texts for the next 60 days in its private storage (SharedPreferences, excluded from Android backup).
- **PDF summary:** it contains health data and only leaves the phone if the user shares it. The temporary file lives in the app's private cache and "Delete all data" removes it.
- **Birth-control reminder:** stored only on this phone (device settings file); it is not included in backups and not sent anywhere.
- **Pregnancies:** stored in the local database (schema v6) and included in backups (format v6).
- Privacy policy: [`docs/privacy.html`](docs/privacy.html).

## Documentation

- [Project report](https://soofiaa.github.io/Aura/informe.html) (Spanish, with an English executive summary; also as [PDF](docs/Aura_Informe.pdf))
- [Technical annexes](docs/anexos/00_INDICE.md): requirements, use cases, architecture, data model, permissions and privacy, quality and testing, decisions (in Spanish)
- [Functional specification v1.1](docs/ESPECIFICACION_v1.1.md): user stories, requirements and acceptance criteria (in Spanish).
- [HU-09: Google Drive backup](docs/HU-09_respaldo_drive_v1.2.md) (in Spanish)
- [Drive setup](docs/DRIVE_SETUP.md) (in Spanish)
- [Privacy policy](https://soofiaa.github.io/Aura/privacy.html)

## Architecture

```mermaid
flowchart LR
    UI[Flutter screens] --> Repo[CycleRepository]
    Repo --> DB[(drift / SQLite)]
    Repo --> Dom[Pure domain]
    Dom --> Der[cycle_deriver]
    Dom --> Pred[cycle_predictor]
    Dom --> Plan[notification_planner]
    Plan --> Rec[NotificationReconciler]
    Rec --> Sch[NotificationScheduler]
    UI --> Bak[BackupService]
    Bak --> Repo
    Bak --> Drv[AutoDriveBackupService]
    Drv --> Api[DriveApiClient]
    Drv --> Vault[KeystoreVault]
    DB -. reactive streams .-> UI
```

```
lib/
├── app_startup.dart
├── main.dart
├── domain/        # pure logic, no Flutter or database
│   ├── backup_codec.dart
│   ├── backup_crypto.dart
│   ├── backup_reminder.dart
│   ├── contraceptive.dart
│   ├── cycle_deriver.dart
│   ├── cycle_predictor.dart
│   ├── current_period.dart
│   ├── fertile_marks.dart
│   ├── legacy_period_ends.dart
│   ├── notification_planner.dart
│   ├── password_strength.dart
│   ├── range_selection.dart
│   └── symptom_ranking.dart
├── data/
│   ├── backup/          # BackupService, file and reminder stores
│   │                    # + automatic Drive backup (HU-09): drive_api_client,
│   │                    #   auto_drive_backup_service, drive_backup_gateway, pre_migration_copy
│   ├── database/        # drift (schema v6)
│   ├── models/          # day enums (flow, mood, symptoms)
│   ├── repositories/    # CycleRepository
│   ├── notifications/   # reconciler
│   ├── device_settings_store.dart  # per-phone settings (no migration needed)
│   ├── doctor_report.dart          # PDF summary for the doctor
│   └── home_widget_sync.dart       # home-screen widget texts
├── screens/       # home, calendar, add entry, stats, settings, backup, onboarding
├── widgets/       # password dialogs, period start sheet, symptom selector, backup card
└── utils/         # DayKey, colors, strings, time zone, Keystore, Android channels
```

## Design decisions (and why)

**Dates as `yyyy-MM-dd` text, arithmetic in UTC.** A calendar day is not an instant. Storing it as text avoids time-zone drift. In Chile the DST change happens at midnight, so local midnight sometimes doesn't exist; doing arithmetic on `DayKey` in UTC removes that whole class of bugs.

**Derived cycles, not stored.** Only bleeding days are stored. A new cycle starts when the previous bleeding day is more than 7 days earlier. This gives a single source of truth, and editing one day recomputes everything consistently.

**A pure, testable prediction engine.** Linearly weighted average of the **last 6 valid complete cycles** (recent ones weigh more; cycles shorter than 15 or longer than 60 days are filtered out first), with a weighted standard deviation. The uncertainty range is `max(1.5·σ, 2 days)` (3 days with fewer than 2 cycles). Ovulation = next period − 14 days; fertile window = ovulation −5 … ovulation. Confidence is low with fewer than 2 cycles or when the deviation exceeds 18% of the average; then ovulation and the fertile window are not shown, nor if estimated ovulation would fall inside the bleeding period (cycles of 15–19 days), nor while the period is late. Once today is more than 60 days after the start of the last period **and** more than 7 days past the late end of the range, the app shows "stale data" instead of a false prediction.

**Pure notification planner + reconciler.** `planNotifications` computes what should be scheduled (a pure function tested with fixed dates). The reconciler waits until it has both cycles and settings (a half-populated plan would cancel everything already scheduled), runs reconciliations one at a time (the last one wins) and absorbs a plugin failure until the next data change or when the app comes back to the foreground. A `NotificationScheduler` interface allows a fake in tests.

**`period_day_explicit` (schema v3).** Distinguishes "the user explicitly said there was no bleeding" from a default value. It is a deliberate exception to non-destructive writes, needed so "remove mark" and period-end are reliable.

## How prediction works (and its limits)

Aura uses the **calendar method**: it projects from past cycles. It is an estimate, not a measurement. It uses no basal temperature or hormone tests, so with irregular cycles the range will be wide and confidence low. **It is not a contraceptive method or a medical device.**

## Quality and testing

More than 1,370 tests (domain with fixed dates, repository on an in-memory database, planner and reconciler with a fake scheduler, widget tests for the screens, plus manifest and gradle checks run from tests). Later verification (code audits and manual testing on the phone) found bugs the initial tests had missed; each fix came with a regression test.

## Running it

Requirements: stable Flutter and JDK 17–21 (not 25).

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
flutter test
```

Signed release build: see [`android/RELEASE.md`](android/RELEASE.md). The signing key and `key.properties` are **not** in the repository.

## Not yet implemented

- Encryption of the data inside the phone (the password protects only the backup file)
- iOS

## Health notice

Aura provides estimates for informational purposes only. It does not replace advice from a healthcare professional.

## License

All rights reserved. The code is published for viewing and evaluation only; see [LICENSE](LICENSE).
