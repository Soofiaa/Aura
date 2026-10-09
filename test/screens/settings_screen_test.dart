import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/domain/backup_codec.dart';
import 'package:aura/screens/settings_screen.dart';
import 'package:aura/utils/app_version.dart';

import '../support/fake_backup.dart';
import '../support/fake_notification_scheduler.dart';
import '../support/fake_url_launcher.dart';

void main() {
  late AppDatabase db;
  late CycleRepository repo;
  late FakeNotificationScheduler scheduler;
  late FakeBackupService backup;
  late FakeUrlLauncher launcher;
  final realLauncher = UrlLauncherPlatform.instance;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CycleRepository(db);
    scheduler = FakeNotificationScheduler();
    backup = FakeBackupService(repo);
    launcher = FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  tearDown(() => UrlLauncherPlatform.instance = realLauncher);

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        repository: repo,
        scheduler: scheduler,
        backupService: backup,
        fileGateway: FakeBackupFileGateway(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('no pide permiso solo por abrir la pantalla', (tester) async {
    await pumpScreen(tester);
    expect(scheduler.requestPermissionCallCount, 0);
    await db.close();
  });

  testWidgets('pide permiso exactamente al activar el interruptor general',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Notificaciones'));
    await tester.pumpAndSettle();

    expect(scheduler.requestPermissionCallCount, 1);
    expect(await repo.getNotificationsEnabled(), isTrue);

    await db.close();
  });

  testWidgets(
      'si el permiso es denegado, el interruptor vuelve a apagado y queda '
      'persistido en false', (tester) async {
    scheduler.permissionGranted = false;
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Notificaciones'));
    await tester.pumpAndSettle();

    final switchWidget = tester
        .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Notificaciones'));
    expect(switchWidget.value, isFalse);
    expect(await repo.getNotificationsEnabled(), isFalse);

    await db.close();
  });

  testWidgets(
      'los sub-interruptores estan deshabilitados mientras el general esta '
      'apagado', (tester) async {
    await pumpScreen(tester);

    final periodoSwitch = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Recordatorio de período'));
    expect(periodoSwitch.onChanged, isNull);

    await db.close();
  });

  testWidgets('activar el recordatorio de ventana fertil lo persiste',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Notificaciones'));
    await tester.pumpAndSettle();

    // HU-05: el interruptor de Tu ciclo lo dejo mas abajo.
    await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Ventana fértil'), 200);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Ventana fértil'));
    await tester.pumpAndSettle();

    final settings = await repo.getNotificationSettings();
    expect(settings.fertileWindowRemindersEnabled, isTrue);

    await db.close();
  });

  testWidgets('el subtitulo de ventana fertil menciona el disclaimer',
      (tester) async {
    await pumpScreen(tester);
    await tester.scrollUntilVisible(
        find.textContaining('estimación, no método anticonceptivo'), 200);
    expect(
      find.textContaining('estimación, no método anticonceptivo'),
      findsOneWidget,
    );
    await db.close();
  });

  testWidgets(
      'el subtitulo de mostrar detalles advierte sobre dispositivos '
      'conectados', (tester) async {
    await pumpScreen(tester);
    await tester.scrollUntilVisible(
        find.textContaining('relojes u otros dispositivos'), 200);
    expect(
      find.textContaining('relojes u otros dispositivos'),
      findsOneWidget,
    );
    await db.close();
  });

  testWidgets('ya no hay boton de notificacion de prueba', (tester) async {
    await pumpScreen(tester);
    await tester.scrollUntilVisible(
        find.text('Versión $appVersionName • Aura 🌸'), 200);
    expect(find.textContaining('notificación de prueba'), findsNothing);
    await db.close();
  });

  group('Política de privacidad', () {
    const fallo = 'No se pudo abrir el enlace. Puedes abrirlo desde un '
        'navegador: $privacyPolicyUrl';

    Future<void> tocarEnlace(WidgetTester tester) async {
      final enlace = find.text('Política de privacidad');
      await tester.scrollUntilVisible(enlace, 200);
      await tester.tap(enlace);
      await tester.pumpAndSettle();
    }

    testWidgets('esta junto a la version, al pie de Ajustes', (tester) async {
      await pumpScreen(tester);
      final enlace = find.text('Política de privacidad');
      final version = find.text('Versión $appVersionName • Aura 🌸');
      await tester.scrollUntilVisible(version, 200);
      expect(enlace, findsOneWidget);
      // Debajo de "Borrar todos los datos" y justo encima de la version.
      final borrar = find.text('Borrar todos los datos');
      expect(tester.getTopLeft(enlace).dy,
          greaterThan(tester.getTopLeft(borrar).dy));
      expect(tester.getTopLeft(enlace).dy,
          lessThan(tester.getTopLeft(version).dy));
      expect(launcher.launchedUrls, isEmpty); // no abre nada solo
      await db.close();
    });

    testWidgets('abre la direccion en una app externa (el navegador)',
        (tester) async {
      await pumpScreen(tester);
      await tocarEnlace(tester);

      expect(privacyPolicyUrl, 'https://soofiaa.github.io/Aura/privacy.html');
      expect(launcher.launchedUrls, [privacyPolicyUrl]);
      expect(launcher.launchedModes,
          [PreferredLaunchMode.externalApplication]);
      expect(find.text(fallo), findsNothing);
      await db.close();
    });

    testWidgets('si ninguna app puede abrirla, muestra la direccion',
        (tester) async {
      launcher.result = false;
      await pumpScreen(tester);
      await tocarEnlace(tester);

      expect(launcher.launchedUrls, [privacyPolicyUrl]);
      expect(find.text(fallo), findsOneWidget);
      await db.close();
    });

    testWidgets('si la plataforma falla, muestra la direccion sin romperse',
        (tester) async {
      launcher.error = PlatformException(code: 'ACTIVITY_NOT_FOUND');
      await pumpScreen(tester);
      await tocarEnlace(tester);

      expect(find.text(fallo), findsOneWidget);
      expect(tester.takeException(), isNull);
      await db.close();
    });
  });

  testWidgets('muestra la version de la constante unica', (tester) async {
    await pumpScreen(tester);
    await tester.scrollUntilVisible(
        find.text('Versión $appVersionName • Aura 🌸'), 200);
    expect(find.text('Versión $appVersionName • Aura 🌸'), findsOneWidget);
    expect(find.textContaining('1.0.0'), findsNothing);
    await db.close();
  });

  testWidgets(
      'los interruptores se actualizan solos cuando los ajustes cambian por '
      'fuera de la pantalla (importar un respaldo)', (tester) async {
    await repo.setNotificationsEnabled(true);
    // Pantalla alta: el test mira todos los interruptores a la vez.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpScreen(tester);
    SwitchListTile switchDe(String titulo) => tester
        .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, titulo));
    expect(switchDe('Recordatorio de período').value, isTrue);
    expect(switchDe('Ventana fértil').value, isFalse);

    await repo.replaceAllWithBackup(const BackupData(
      schemaVersion: currentBackupSchemaVersion,
      appVersion: '1.0.1',
      exportedAt: '2026-10-04T10:15:00-03:00',
      days: [],
      settings: BackupSettings(
        onboardingSeen: true,
        notificationsEnabled: false,
        periodReminderEnabled: false,
        fertileWindowRemindersEnabled: true,
        showDetailsEnabled: true,
        reminderHour: 21,
        reminderMinute: 30,
      ),
    ));
    await tester.pumpAndSettle();

    expect(switchDe('Notificaciones').value, isTrue,
        reason: 'el interruptor general no se importa');
    expect(switchDe('Recordatorio de período').value, isFalse);
    expect(switchDe('Ventana fértil').value, isTrue);
    expect(switchDe('Mostrar detalles en la notificación').value, isTrue);
    expect(find.text('21:30'), findsOneWidget);

    await db.close();
  });

  testWidgets(
      'Borrar todos los datos pasa por BackupService (que tambien borra la '
      'copia previa y los temporales) y reinicia los interruptores',
      (tester) async {
    await repo.setNotificationsEnabled(true);
    await repo.setReminderTime(hour: 21, minute: 30);
    await repo.markPeriodDay('2026-01-01');
    await pumpScreen(tester);

    await tester.scrollUntilVisible(find.text('Borrar todos los datos'), 200);
    await tester.ensureVisible(find.text('Borrar todos los datos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrar todos los datos'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('la copia guardada antes de la última importación'),
        findsOneWidget);
    await tester.tap(find.text('Borrar todo'));
    await tester.pumpAndSettle();

    expect(backup.deleteAllDataCallCount, 1);
    expect(await repo.countDays(), 0);
    expect(find.text('Datos borrados correctamente 💧'), findsOneWidget);

    await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Notificaciones'), -200);
    expect(
        tester
            .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, 'Notificaciones'))
            .value,
        isFalse);
    expect(find.text('09:00'), findsOneWidget);

    await db.close();
  });

  testWidgets('si borrar falla, el mensaje no muestra el detalle del error',
      (tester) async {
    backup.failOnDelete = true;
    await pumpScreen(tester);

    await tester.scrollUntilVisible(find.text('Borrar todos los datos'), 200);
    await tester.ensureVisible(find.text('Borrar todos los datos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrar todos los datos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Borrar todo'));
    await tester.pumpAndSettle();

    expect(
        find.text('No se pudieron borrar todos los datos. Inténtalo de nuevo.'),
        findsOneWidget);
    expect(find.textContaining('detalle interno'), findsNothing);
    expect(find.text('Datos borrados correctamente 💧'), findsNothing);

    await db.close();
  });

  group('Tu ciclo: duracion habitual del periodo (HU-01)', () {
    final menos = find.byKey(const Key('duracion_menos'));
    final mas = find.byKey(const Key('duracion_mas'));
    final valor = find.byKey(const Key('duracion_valor'));

    String valorEnPantalla(WidgetTester tester) =>
        tester.widget<Text>(valor).data!;
    bool habilitado(WidgetTester tester, Finder boton) =>
        tester.widget<IconButton>(boton).onPressed != null;

    testWidgets('muestra la seccion arriba de Notificaciones con 5 dias por '
        'defecto y el texto que explica para que sirve', (tester) async {
      await pumpScreen(tester);

      expect(find.text('Tu ciclo'), findsOneWidget);
      expect(find.text('Duración habitual del período'), findsOneWidget);
      expect(valorEnPantalla(tester), '5 días');
      expect(
          find.text('Aura la usa para estimar cuántos días dura tu período '
              'mientras todavía no tienes períodos terminados registrados; '
              'después usa el promedio de los tuyos. Cambiarla no modifica '
              'tus registros.'),
          findsOneWidget);
      expect(tester.getTopLeft(find.text('Tu ciclo')).dy,
          lessThan(tester.getTopLeft(find.text('Notificaciones').first).dy));
      await db.close();
    });

    testWidgets('muestra el valor guardado', (tester) async {
      await repo.setTypicalPeriodLength(7);
      await pumpScreen(tester);
      expect(valorEnPantalla(tester), '7 días');
      await db.close();
    });

    testWidgets('+ y - cambian el valor y lo guardan al instante',
        (tester) async {
      await pumpScreen(tester);

      await tester.tap(mas);
      await tester.pumpAndSettle();
      await tester.tap(mas);
      await tester.pumpAndSettle();
      expect(valorEnPantalla(tester), '7 días');
      expect(await repo.getTypicalPeriodLength(), 7);

      await tester.tap(menos);
      await tester.pumpAndSettle();
      expect(valorEnPantalla(tester), '6 días');
      expect(await repo.getTypicalPeriodLength(), 6);
      await db.close();
    });

    testWidgets('tope en 1: "-" se deshabilita y dice "1 dia"',
        (tester) async {
      await repo.setTypicalPeriodLength(2);
      await pumpScreen(tester);
      expect(habilitado(tester, menos), isTrue);

      await tester.tap(menos);
      await tester.pumpAndSettle();

      expect(valorEnPantalla(tester), '1 día');
      expect(habilitado(tester, menos), isFalse);
      expect(habilitado(tester, mas), isTrue);
      await tester.tap(menos, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(await repo.getTypicalPeriodLength(), 1);
      await db.close();
    });

    testWidgets('tope en 15: "+" se deshabilita', (tester) async {
      await repo.setTypicalPeriodLength(14);
      await pumpScreen(tester);

      await tester.tap(mas);
      await tester.pumpAndSettle();

      expect(valorEnPantalla(tester), '15 días');
      expect(habilitado(tester, mas), isFalse);
      expect(habilitado(tester, menos), isTrue);
      await tester.tap(mas, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(await repo.getTypicalPeriodLength(), 15);
      await db.close();
    });

    testWidgets('el valor sigue al reabrir la pantalla', (tester) async {
      await pumpScreen(tester);
      await tester.tap(menos);
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await pumpScreen(tester);

      expect(valorEnPantalla(tester), '4 días');
      await db.close();
    });

    testWidgets('cambiarla no modifica ningun registro (criterio 3)',
        (tester) async {
      await repo.markPeriodDays(['2026-01-01', '2026-01-02']);
      final antes = await repo.getDerivedCycles();
      await pumpScreen(tester);

      await tester.tap(mas);
      await tester.pumpAndSettle();

      expect(await repo.countDays(), 2);
      expect(await repo.getDerivedCycles(), antes);
      await db.close();
    });

    testWidgets('se actualiza sola si cambia por fuera (importar un respaldo)',
        (tester) async {
      await pumpScreen(tester);

      await repo.replaceAllWithBackup(const BackupData(
        schemaVersion: currentBackupSchemaVersion,
        appVersion: '1.0.1',
        exportedAt: '2026-10-04T10:15:00-03:00',
        days: [],
        settings: BackupSettings(
          onboardingSeen: true,
          notificationsEnabled: false,
          periodReminderEnabled: true,
          fertileWindowRemindersEnabled: false,
          showDetailsEnabled: false,
          reminderHour: 9,
          reminderMinute: 0,
          typicalPeriodLength: 9,
        ),
      ));
      await tester.pumpAndSettle();

      expect(valorEnPantalla(tester), '9 días');
      await db.close();
    });

    testWidgets('etiquetas para lector de pantalla y area tactil de 48 dp',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester);

      expect(find.bySemanticsLabel('Disminuir duración'), findsOneWidget);
      expect(find.bySemanticsLabel('Aumentar duración'), findsOneWidget);
      expect(
          find.bySemanticsLabel('Duración habitual del período: 5 días'),
          findsOneWidget);
      for (final boton in [menos, mas]) {
        final size = tester.getSize(boton);
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }

      await tester.tap(mas);
      await tester.pumpAndSettle();
      expect(
          find.bySemanticsLabel('Duración habitual del período: 6 días'),
          findsOneWidget);

      semantics.dispose();
      await db.close();
    });
  });

  // HU-05, CP5b: "Mostrar ovulacion y ventana fertil" (H5-3, relacion A).
  group('Tu ciclo: mostrar ovulacion y ventana fertil (HU-05)', () {
    const titulo = 'Mostrar ovulación y ventana fértil';
    const subtitulo = 'Son estimaciones, no un método anticonceptivo. Si lo '
        'apagas, no se muestran en Inicio ni en el Calendario.';
    const ventanaEncendido = 'Aviso opcional al comenzar tu ventana de mayor '
        'fertilidad (estimación, no método anticonceptivo). Solo se envía '
        'cuando tu estimación es confiable.';
    const ventanaApagado = 'Aviso opcional al comenzar tu ventana de mayor '
        'fertilidad (estimación, no método anticonceptivo).';
    const ayuda = 'Para usarlo, activa «Mostrar ovulación y ventana fértil» '
        'en Tu ciclo.';

    final mostrar = find.widgetWithText(SwitchListTile, titulo);
    final ventana = find.widgetWithText(SwitchListTile, 'Ventana fértil');

    // Pantalla alta: todos los interruptores construidos sin desplazar.
    Future<void> pumpTall(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpScreen(tester);
    }

    testWidgets('por defecto encendido, con su subtitulo, y "Ventana fertil" '
        'dice que solo se envia con una estimacion confiable', (tester) async {
      await repo.setNotificationsEnabled(true);
      await pumpTall(tester);

      expect(tester.widget<SwitchListTile>(mostrar).value, isTrue);
      expect(find.text(subtitulo), findsOneWidget);
      expect(find.text(ventanaEncendido), findsOneWidget);
      expect(find.text(ayuda), findsNothing);
      expect(tester.widget<SwitchListTile>(ventana).onChanged, isNotNull);
      // Dentro de Tu ciclo: arriba de Notificaciones.
      expect(tester.getTopLeft(mostrar).dy,
          lessThan(tester.getTopLeft(find.text('Notificaciones').first).dy));
      await db.close();
    });

    testWidgets('al apagarlo se guarda y "Ventana fertil" queda deshabilitado '
        'con la ayuda en gris', (tester) async {
      await repo.setNotificationsEnabled(true);
      await repo.setFertileWindowRemindersEnabled(true);
      await pumpTall(tester);

      await tester.tap(mostrar);
      await tester.pumpAndSettle();

      expect(await repo.getShowFertileWindow(), isFalse);
      expect(tester.widget<SwitchListTile>(mostrar).value, isFalse);
      final v = tester.widget<SwitchListTile>(ventana);
      expect(v.onChanged, isNull);
      expect(v.value, isFalse);
      expect(find.text(ayuda), findsOneWidget);
      expect(find.text(ventanaApagado), findsOneWidget);
      expect(find.text(ventanaEncendido), findsNothing);
      final estilo = tester.widget<Text>(find.text(ayuda)).style!;
      expect(estilo.fontSize, 13);
      expect(estilo.color, Colors.grey[700]);
      // El valor guardado de "Ventana fertil" no cambia.
      expect((await repo.getNotificationSettings())
          .fertileWindowRemindersEnabled, isTrue);
      await db.close();
    });

    for (final previo in [true, false]) {
      testWidgets('al volver a encenderlo, "Ventana fertil" recupera '
          'exactamente su valor previo ($previo)', (tester) async {
        await repo.setNotificationsEnabled(true);
        await repo.setFertileWindowRemindersEnabled(previo);
        await pumpTall(tester);
        expect(tester.widget<SwitchListTile>(ventana).value, previo);

        await tester.tap(mostrar);
        await tester.pumpAndSettle();
        expect((await repo.getNotificationSettings())
            .fertileWindowRemindersEnabled, previo);

        await tester.tap(mostrar);
        await tester.pumpAndSettle();
        expect(await repo.getShowFertileWindow(), isTrue);
        final v = tester.widget<SwitchListTile>(ventana);
        expect(v.value, previo);
        expect(v.onChanged, isNotNull);
        expect((await repo.getNotificationSettings())
            .fertileWindowRemindersEnabled, previo);
        expect(find.text(ayuda), findsNothing);
        await db.close();
      });
    }

    testWidgets('con el general apagado, "Ventana fertil" sigue '
        'deshabilitado aunque el interruptor nuevo este encendido',
        (tester) async {
      await pumpTall(tester);
      expect(tester.widget<SwitchListTile>(ventana).onChanged, isNull);
      expect(find.text(ayuda), findsNothing);
      // El interruptor nuevo no depende del general.
      expect(tester.widget<SwitchListTile>(mostrar).onChanged, isNotNull);
      await db.close();
    });

    testWidgets('sigue el valor guardado si cambia por fuera (importar un '
        'respaldo)', (tester) async {
      await pumpTall(tester);
      await repo.setShowFertileWindow(false);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(mostrar).value, isFalse);
      await db.close();
    });
  });
}
