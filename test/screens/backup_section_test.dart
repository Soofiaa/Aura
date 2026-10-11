import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aura/data/backup/backup_file_gateway.dart';
import 'package:aura/data/backup/backup_reminder_store.dart';
import 'package:aura/data/backup/backup_service.dart';
import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/notifications/notification_reconciler.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/domain/backup_codec.dart';
import 'package:aura/screens/main_navigation_screen.dart';
import 'package:aura/screens/settings_screen.dart';

import '../support/fake_backup.dart';
import '../support/fake_notification_scheduler.dart';

/// test/fixtures/backup_v3.json: 7 dias, exportado el 2026-10-04.
List<int> _fixtureBytes() =>
    File('test/fixtures/backup_v3.json').readAsBytesSync();

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  late AppDatabase db;
  late CycleRepository repo;
  late FakeBackupService backup;
  late FakeBackupFileGateway gateway;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CycleRepository(db);
    backup = FakeBackupService(repo);
    gateway = FakeBackupFileGateway();
    // Respaldo exitoso: anota la fecha en memoria (la E/S real no
    // avanza dentro de testWidgets).
    backupReminderStore = FakeBackupReminderStore();
  });

  /// Pantalla alta para que toda la lista de Ajustes quepa sin scroll.
  void tallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> irA(WidgetTester tester, String destino) async {
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text(destino)));
    await tester.pumpAndSettle();
  }

  Future<void> pumpSettings(WidgetTester tester) async {
    tallView(tester);
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        repository: repo,
        scheduler: FakeNotificationScheduler(),
        backupService: backup,
        fileGateway: gateway,
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Datos actuales del telefono: [n] dias de sangrado en mayo de 2026.
  Future<void> seedDays(int n) async {
    await repo.markPeriodDays([
      for (var d = 1; d <= n; d++) '2026-05-${d.toString().padLeft(2, '0')}',
    ]);
  }

  Future<void> abrirConfirmacion(WidgetTester tester) async {
    backup.files['respaldo.json'] = _fixtureBytes();
    gateway.pickResult = 'respaldo.json';
    await tester.tap(find.text('Restaurar un respaldo'));
    await tester.pumpAndSettle();
    expect(find.text('¿Reemplazar tus datos?'), findsOneWidget);
  }

  Future<void> importarFixture(WidgetTester tester) async {
    await abrirConfirmacion(tester);
    await tester.tap(find.text('Reemplazar'));
    await tester.pumpAndSettle();
  }

  const exito =
      'Listo: se importaron 7 días.\nSi te equivocaste, toca Deshacer.';

  /// HU-06b CP3: en "Proteger tu respaldo", "Continuar sin contraseña" y
  /// confirmarlo (el camino sin cifrar, igual que antes de HU-06b).
  Future<void> sinContrasena(WidgetTester tester) async {
    await tester.tap(find.text('Continuar sin contraseña'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog).last,
        matching: find.text('Continuar sin contraseña')));
    await tester.pumpAndSettle();
  }

  testWidgets('"Tus datos" reemplaza a "Gestión de datos" con las dos '
      'opciones de respaldo antes de "Borrar todos los datos"', (tester) async {
    await pumpSettings(tester);

    expect(find.text('Tus datos'), findsOneWidget);
    expect(find.text('Gestión de datos'), findsNothing);
    expect(find.text('Guarda tus registros en un archivo'), findsOneWidget);
    expect(find.text('Reemplaza tus datos por los de un archivo'),
        findsOneWidget);
    final yCrear = tester.getTopLeft(find.text('Crear respaldo')).dy;
    final yRestaurar = tester.getTopLeft(find.text('Restaurar un respaldo')).dy;
    final yBorrar = tester.getTopLeft(find.text('Borrar todos los datos')).dy;
    expect(yCrear < yRestaurar && yRestaurar < yBorrar, isTrue);

    await db.close();
  });

  group('crear respaldo', () {
    testWidgets('advierte que son datos de salud antes de exportar, y '
        'Cancelar no exporta nada', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('Crear respaldo'));
      await tester.pumpAndSettle();

      expect(find.text('Tu respaldo tiene datos de salud'), findsOneWidget);
      expect(
        find.text('Incluye tus días de período, síntomas, ánimo y notas. '
            'Guárdalo en un lugar que solo tú uses. Si lo compartes con una '
            'app, esa app tendrá una copia.'),
        findsOneWidget,
      );
      expect(find.text('Guardar en el teléfono'), findsOneWidget);
      expect(find.text('Compartir'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(gateway.sharedFiles, isEmpty);
      expect(gateway.savedBytes, isNull);
      expect(find.byType(SnackBar), findsNothing);
      await db.close();
    });

    testWidgets('Compartir abre la hoja de compartir con el archivo y avisa',
        (tester) async {
      await seedDays(2);
      await pumpSettings(tester);

      await tester.tap(find.text('Crear respaldo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compartir'));
      await tester.pumpAndSettle();
      await sinContrasena(tester);

      expect(gateway.sharedFiles, hasLength(1));
      expect(gateway.sharedFiles.single.path,
          endsWith('aura_respaldo_2026-10-04.json'));
      expect(find.text('Respaldo listo. Guárdalo en un lugar seguro.'),
          findsOneWidget);
      expect(backup.preMigrationCopyDeleteCount, 0,
          reason: 'compartir no borra la copia previa a la migracion: '
              'share_plus puede informar unavailable sin enviar nada');
      await db.close();
    });

    testWidgets('si se cierra la hoja de compartir sin elegir destino no '
        'aparece ningun mensaje', (tester) async {
      await seedDays(2);
      gateway.shareResult = BackupShareResult.dismissed;
      await pumpSettings(tester);

      await tester.tap(find.text('Crear respaldo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compartir'));
      await tester.pumpAndSettle();
      await sinContrasena(tester);

      expect(gateway.sharedFiles, hasLength(1));
      expect(find.byType(SnackBar), findsNothing);
      await db.close();
    });

    testWidgets('Guardar en el teléfono escribe un respaldo valido y avisa '
        'sin mostrar la ruta', (tester) async {
      await seedDays(2);
      await pumpSettings(tester);

      await tester.tap(find.text('Crear respaldo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar en el teléfono'));
      await tester.pumpAndSettle();
      await sinContrasena(tester);

      expect(gateway.savedFileName, 'aura_respaldo_2026-10-04.json');
      final result = decodeBackup(gateway.savedBytes!);
      expect((result as BackupParseSuccess).data.days, hasLength(2));
      expect(find.text('Respaldo guardado.'), findsOneWidget);
      expect(backup.preMigrationCopyDeleteCount, 1,
          reason: 'un guardado exitoso borra la copia previa a la migracion');
      await db.close();
    });

    testWidgets('si se cancela el "Guardar como" no aparece ningun mensaje',
        (tester) async {
      gateway.saveResult = false;
      await pumpSettings(tester);

      await tester.tap(find.text('Crear respaldo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar en el teléfono'));
      await tester.pumpAndSettle();
      await sinContrasena(tester);

      expect(find.byType(SnackBar), findsNothing);
      expect(backup.preMigrationCopyDeleteCount, 0);
      await db.close();
    });

    testWidgets('si guardar falla, el mensaje no muestra el detalle',
        (tester) async {
      gateway.saveError = const FileSystemException('detalle interno');
      await pumpSettings(tester);

      await tester.tap(find.text('Crear respaldo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar en el teléfono'));
      await tester.pumpAndSettle();
      await sinContrasena(tester);

      expect(find.text('No se pudo guardar el respaldo.'), findsOneWidget);
      expect(find.textContaining('detalle interno'), findsNothing);
      expect(backup.preMigrationCopyDeleteCount, 0);
      await db.close();
    });

    testWidgets('fecha fuera de rango: el mensaje nombra la fecha, armado '
        'con los datos de la excepcion', (tester) async {
      backup.writeError = BackupWriteException(
        BackupWriteCause.dateOutOfRange,
        'detalle interno',
        outOfRangeDate: '2031-01-01',
      );
      await pumpSettings(tester);

      await tester.tap(find.text('Crear respaldo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compartir'));
      await tester.pumpAndSettle();
      await sinContrasena(tester);

      expect(
        find.text('No se pudo crear el respaldo: hay un día con una fecha '
            'fuera de rango (1 de enero de 2031).'),
        findsOneWidget,
      );
      expect(gateway.sharedFiles, isEmpty);
      expect(find.textContaining('detalle interno'), findsNothing);
      await db.close();
    });
  });

  group('restaurar un respaldo', () {
    testWidgets('cancelar el selector no hace nada', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('Restaurar un respaldo'));
      await tester.pumpAndSettle();

      expect(gateway.pickCount, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      await db.close();
    });

    testWidgets('un archivo que no es respaldo muestra su mensaje y no cambia '
        'los datos', (tester) async {
      await seedDays(3);
      backup.files['foto.jpg'] = utf8.encode('no es un respaldo');
      gateway.pickResult = 'foto.jpg';
      await pumpSettings(tester);

      await tester.tap(find.text('Restaurar un respaldo'));
      await tester.pumpAndSettle();

      expect(
          find.text('Este archivo no es un respaldo de Aura. No se cambió '
              'nada.'),
          findsOneWidget);
      expect(find.text('¿Reemplazar tus datos?'), findsNothing);
      expect(backup.importCount, 0);
      expect(await repo.countDays(), 3);
      await db.close();
    });

    testWidgets('un respaldo de una version mas nueva se rechaza con su '
        'mensaje', (tester) async {
      final map = jsonDecode(utf8.decode(_fixtureBytes())) as Map;
      map['schemaVersion'] = currentBackupSchemaVersion + 1;
      backup.files['nuevo.json'] = utf8.encode(jsonEncode(map));
      gateway.pickResult = 'nuevo.json';
      await pumpSettings(tester);

      await tester.tap(find.text('Restaurar un respaldo'));
      await tester.pumpAndSettle();

      expect(
          find.text('Este respaldo es de una versión más nueva de Aura. '
              'Actualiza la app y vuelve a intentarlo. No se cambió nada.'),
          findsOneWidget);
      expect(backup.importCount, 0);
      await db.close();
    });

    testWidgets('un respaldo danado se rechaza con su mensaje',
        (tester) async {
      final bytes = _fixtureBytes();
      backup.files['cortado.json'] = bytes.sublist(0, bytes.length ~/ 2);
      gateway.pickResult = 'cortado.json';
      await pumpSettings(tester);

      await tester.tap(find.text('Restaurar un respaldo'));
      await tester.pumpAndSettle();

      expect(
          find.text('El respaldo está dañado o incompleto. No se cambió '
              'nada.'),
          findsOneWidget);
      await db.close();
    });

    testWidgets('la confirmacion muestra fecha y conteos; Cancelar no cambia '
        'nada', (tester) async {
      await seedDays(3);
      await pumpSettings(tester);
      await abrirConfirmacion(tester);

      expect(
        find.text('El respaldo es del 4 de octubre de 2026 y tiene 7 días '
            'con registro (5 de período). En este teléfono tienes 3 días con '
            'registro (3 de período), que se reemplazarán por los del '
            'respaldo. Antes, Aura guardará una copia de tus datos '
            'actuales.'),
        findsOneWidget,
      );
      expect(find.textContaining('días menos'), findsNothing);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(backup.importCount, 0);
      expect(await repo.countDays(), 3);
      expect(find.byType(SnackBar), findsNothing);
      await db.close();
    });

    testWidgets('los dias con la marca quitada cuentan como registro pero no '
        'como periodo', (tester) async {
      await repo.markPeriodDay('2026-05-01');
      await repo.setPeriodDayExplicitly('2026-05-02', isPeriodDay: false);
      await pumpSettings(tester);
      await abrirConfirmacion(tester);

      expect(
          find.textContaining('En este teléfono tienes 2 días con registro '
              '(1 de período), que'),
          findsOneWidget);
      await db.close();
    });

    testWidgets('un solo dia con registro va en singular', (tester) async {
      await repo.setPeriodDayExplicitly('2026-05-02', isPeriodDay: false);
      await pumpSettings(tester);
      await abrirConfirmacion(tester);

      expect(
          find.textContaining('En este teléfono tienes 1 día con registro '
              '(0 de período), que'),
          findsOneWidget);
      await db.close();
    });

    testWidgets('si el respaldo tiene menos dias, la confirmacion avisa '
        'cuantos se pierden', (tester) async {
      await seedDays(9);
      await pumpSettings(tester);
      await abrirConfirmacion(tester);

      expect(
        find.text('El respaldo tiene 2 días menos que los que tienes ahora; '
            'se perderán.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      await db.close();
    });

    testWidgets('Reemplazar importa los datos y muestra el exito con '
        'Deshacer', (tester) async {
      await seedDays(3);
      await pumpSettings(tester);

      await importarFixture(tester);

      expect(backup.importCount, 1);
      expect(await repo.countDays(), 7);
      expect(find.text(exito), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Deshacer'), findsOneWidget);
      await db.close();
    });

    testWidgets('el mensaje de exito no se cierra solo', (tester) async {
      await pumpSettings(tester);
      await importarFixture(tester);

      await tester.pump(const Duration(seconds: 15));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 15));

      expect(find.text(exito), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Deshacer'), findsOneWidget);
      await db.close();
    });

    testWidgets('Deshacer vuelve a los datos de antes con undoLastImport',
        (tester) async {
      await seedDays(3);
      await pumpSettings(tester);
      await importarFixture(tester);

      await tester.tap(find.widgetWithText(SnackBarAction, 'Deshacer'));
      await tester.pumpAndSettle();

      expect(backup.undoCount, 1);
      expect(await repo.countDays(), 3);
      expect(await repo.getDay('2026-08-28'), isNull);
      expect(find.text('Se restauraron tus datos anteriores.'), findsOneWidget);
      await db.close();
    });

    testWidgets('doble toque en Reemplazar importa una sola vez y no cierra '
        'la pantalla de Ajustes', (tester) async {
      await pumpSettings(tester);
      await abrirConfirmacion(tester);

      // Dos activaciones antes del siguiente cuadro. Con toques reales
      // Flutter ya descarta el segundo; se llama a onPressed directo para
      // probar la guarda propia del dialogo (sin ella, el segundo pop
      // cerraria la pantalla de Ajustes).
      final boton = tester.widget<TextButton>(
          find.widgetWithText(TextButton, 'Reemplazar'));
      boton.onPressed!();
      boton.onPressed!();
      await tester.pumpAndSettle();

      expect(backup.importCount, 1);
      expect(find.text('Ajustes'), findsOneWidget);
      expect(find.text(exito), findsOneWidget);
      await db.close();
    });

    testWidgets('durante la importacion la pantalla queda bloqueada y no se '
        'puede iniciar otra', (tester) async {
      await pumpSettings(tester);
      backup.importGate = Completer<void>();
      await abrirConfirmacion(tester);

      await tester.tap(find.text('Reemplazar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Importando tu respaldo…'), findsOneWidget);
      final restaurar = tester.widget<ListTile>(
          find.widgetWithText(ListTile, 'Restaurar un respaldo'));
      expect(restaurar.enabled, isFalse);

      // Ni "atras" ni otro toque cierran el bloqueo o abren otro selector.
      await tester.binding.handlePopRoute();
      await tester.tap(find.text('Restaurar un respaldo'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Importando tu respaldo…'), findsOneWidget);
      expect(gateway.pickCount, 1);

      backup.importGate!.complete();
      await tester.pumpAndSettle();

      expect(find.text('Importando tu respaldo…'), findsNothing);
      expect(find.text(exito), findsOneWidget);
      expect(backup.importCount, 1);
      await db.close();
    });

    testWidgets('antes de importar se descartan los "Deshacer" pendientes de '
        'otras pantallas', (tester) async {
      await pumpSettings(tester);
      ScaffoldMessenger.of(tester.element(find.byType(SettingsScreen)))
          .showSnackBar(SnackBar(
        content: const Text('Marca quitada.'),
        action: SnackBarAction(label: 'Deshacer', onPressed: () {}),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Marca quitada.'), findsOneWidget);

      await importarFixture(tester);

      expect(find.text('Marca quitada.'), findsNothing);
      expect(find.text(exito), findsOneWidget);
      await db.close();
    });
  });

  /// Abre la app completa e importa desde Ajustes un respaldo con un
  /// solo dia de sangrado, el 10 de hace dos meses (siempre en el pasado
  /// y dentro del rango). Devuelve ese dia; la app queda en Ajustes con
  /// el mensaje de exito a la vista.
  Future<String> importarEnLaApp(WidgetTester tester) async {
    tallView(tester);
    cycleRepository = repo;
    backupService = backup;
    backupFileGateway = gateway;
    notificationScheduler = FakeNotificationScheduler();

    final now = DateTime.now();
    final mes = DateTime(now.year, now.month - 2, 1);
    final dia = '${mes.year.toString().padLeft(4, '0')}-'
        '${mes.month.toString().padLeft(2, '0')}-10';
    backup.files['respaldo.json'] = utf8.encode(encodeBackup(BackupData(
      schemaVersion: currentBackupSchemaVersion,
      appVersion: '1.0.1',
      exportedAt: formatExportedAt(now),
      days: [BackupDay(date: dia, isPeriodDay: true, periodDayExplicit: false)],
      settings: const BackupSettings(
        onboardingSeen: true,
        notificationsEnabled: false,
        periodReminderEnabled: true,
        fertileWindowRemindersEnabled: false,
        showDetailsEnabled: false,
        reminderHour: 9,
        reminderMinute: 0,
      ),
    )));
    gateway.pickResult = 'respaldo.json';

    await tester.pumpWidget(const MaterialApp(home: MainNavigationScreen()));
    await tester.pumpAndSettle();
    await irA(tester, 'Ajustes');
    await tester.tap(find.text('Restaurar un respaldo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reemplazar'));
    await tester.pumpAndSettle();
    expect(find.text('Listo: se importó 1 día.\nSi te equivocaste, toca '
        'Deshacer.'), findsOneWidget);
    return dia;
  }

  /// En el Calendario, retrocede dos meses y selecciona el dia 10.
  Future<void> seleccionarDiaImportado(WidgetTester tester) async {
    await irA(tester, 'Calendario');
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('10').first);
    await tester.pumpAndSettle();
  }

  testWidgets('el Calendario muestra los dias importados desde Ajustes',
      (tester) async {
    await importarEnLaApp(tester);
    await seleccionarDiaImportado(tester);

    expect(find.text('Quitar marca'), findsOneWidget);
    await db.close();
  });

  group('el mensaje de exito no bloquea los mensajes siguientes', () {
    testWidgets('"Marca quitada" del Calendario se ve enseguida y su '
        'Deshacer sigue funcionando', (tester) async {
      final dia = await importarEnLaApp(tester);
      await seleccionarDiaImportado(tester);

      await tester.tap(find.text('Quitar marca'));
      await tester.pumpAndSettle();

      expect(find.text('Marca quitada.'), findsOneWidget);
      expect((await repo.getDay(dia))!.isPeriodDay, isFalse);

      await tester.tap(find.widgetWithText(SnackBarAction, 'Deshacer'));
      await tester.pumpAndSettle();

      expect((await repo.getDay(dia))!.isPeriodDay, isTrue);
      expect(backup.undoCount, 0);
      await db.close();
    });

    testWidgets('"Datos borrados" de Ajustes se ve enseguida',
        (tester) async {
      await importarEnLaApp(tester);

      await tester.tap(find.text('Borrar todos los datos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Borrar todo'));
      await tester.pumpAndSettle();

      expect(find.text('Datos borrados correctamente 💧'), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Deshacer'), findsNothing);
      await db.close();
    });
  });
}
