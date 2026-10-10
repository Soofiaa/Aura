import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aura/data/backup/backup_reminder_store.dart';
import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/notifications/notification_reconciler.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/screens/backup_create_flow.dart';
import 'package:aura/screens/home_screen.dart';
import 'package:aura/utils/day_key.dart';

import '../support/fake_backup.dart';
import '../support/fake_notification_scheduler.dart';

/// CP5b: tarjeta del recordatorio de respaldo en Inicio. Hoy es el
/// 09/10/2026 (reloj de HomeScreen). Datos inventados: periodos de 5 dias
/// desde el 09/07, 05/08 y 03/09 de 2026; con la tarjeta del periodo,
/// ademas uno abierto desde el 01/10 con sangrado el 08/10.
void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  late AppDatabase db;
  late CycleRepository repo;
  late FakeBackupService backup;
  late FakeBackupFileGateway gateway;

  const tituloSin = 'Guarda una copia de tus registros';
  const textoSin = 'Aura guarda todo solo en este teléfono. Si lo pierdes o '
      'se daña, tus registros no se pueden recuperar. Un respaldo crea una '
      'copia en el lugar que elijas.';
  const tarjetaPeriodo = '¿Sigue tu período hoy?';
  const aviso = 'Esta es una estimación, no un método anticonceptivo.';
  const hoy = '2026-10-09';
  final fecha = DateTime(2026, 10, 9, 11, 20);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CycleRepository(db);
    backup = FakeBackupService(repo);
    gateway = FakeBackupFileGateway();
  });

  FakeBackupReminderStore almacen({
    String primerUso = '2026-08-01',
    String? ultimo,
    String? pospuesto,
    bool activado = true,
  }) =>
      FakeBackupReminderStore(
        clock: () => fecha,
        initial: BackupReminderState(
          primerUso: primerUso,
          ultimoRespaldo: ultimo,
          pospuestoHasta: pospuesto,
          activado: activado,
        ),
      );

  Future<void> periodo(String inicio, {bool cerrar = true}) async {
    final fechas = [for (var i = 0; i < 5; i++) DayKey.addDays(inicio, i)];
    await repo.markPeriodDays(fechas);
    if (cerrar) {
      await repo.closePeriod(inicio, fechas.last, today: fechas.last);
    }
  }

  Future<void> datos({bool conTarjetaPeriodo = false}) async {
    for (final inicio in ['2026-07-09', '2026-08-05', '2026-09-03']) {
      await periodo(inicio);
    }
    if (conTarjetaPeriodo) {
      await periodo('2026-10-01', cerrar: false);
      await repo.markPeriodDay('2026-10-08');
    }
  }

  Future<void> pumpInicio(
    WidgetTester tester,
    BackupReminderStore store, {
    Size tamano = const Size(800, 2400),
    double escala = 1.0,
    ValueNotifier<bool>? busy,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = escala;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    Widget inicio = HomeScreen(
      repository: repo,
      clock: () => fecha,
      reconciler: NotificationReconciler(repo, FakeNotificationScheduler(),
          clock: () => fecha),
      reminderStore: store,
      backupService: backup,
      fileGateway: gateway,
    );
    if (busy != null) inicio = BackupBusyScope(busy: busy, child: inicio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: inicio,
        bottomNavigationBar: NavigationBar(
          selectedIndex: 0,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home), label: 'Inicio'),
            NavigationDestination(
                icon: Icon(Icons.calendar_month), label: 'Calendario'),
            NavigationDestination(
                icon: Icon(Icons.show_chart), label: 'Estadísticas'),
            NavigationDestination(
                icon: Icon(Icons.settings), label: 'Ajustes'),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('cuando aparece', () {
    testWidgets('sin respaldo previo: titulo, texto e icono de guardar',
        (tester) async {
      await datos();
      await pumpInicio(tester, almacen());
      expect(find.text(tituloSin), findsOneWidget);
      expect(find.text(textoSin), findsOneWidget);
      expect(find.byIcon(Icons.save_outlined), findsOneWidget);
      expect(find.byIcon(Icons.cloud_outlined), findsNothing);
      expect(find.byIcon(Icons.cloud_upload_outlined), findsNothing);
      await db.close();
    });

    testWidgets('con respaldo previo: dias desde el ultimo y su fecha',
        (tester) async {
      await datos();
      await pumpInicio(tester, almacen(ultimo: '2026-09-01'));
      expect(find.text('Hace 38 días que no creas un respaldo'),
          findsOneWidget);
      expect(
          find.text('Tu último respaldo es del 1 de septiembre. Lo que '
              'registraste después está solo en este teléfono.'),
          findsOneWidget);
      expect(find.text(tituloSin), findsNothing);
      await db.close();
    });

    testWidgets('con respaldo de otro ano: la fecha lleva el ano',
        (tester) async {
      await datos();
      await pumpInicio(tester, almacen(ultimo: '2025-12-28'));
      expect(find.textContaining('del 28 de diciembre de 2025.'),
          findsOneWidget);
      await db.close();
    });

    testWidgets('justo a los 30 dias aparece; a los 29 no', (tester) async {
      await datos();
      await pumpInicio(tester, almacen(ultimo: DayKey.addDays(hoy, -30)));
      expect(find.text('Hace 30 días que no creas un respaldo'),
          findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await pumpInicio(tester, almacen(ultimo: DayKey.addDays(hoy, -29)));
      expect(find.textContaining('que no creas un respaldo'), findsNothing);
      await db.close();
    });

    final noAparece = <String, FakeBackupReminderStore Function()>{
      'en los 7 dias de gracia desde primerUso': () =>
          almacen(primerUso: DayKey.addDays(hoy, -6)),
      'con el interruptor apagado': () => almacen(activado: false),
      'pospuesta con "Ahora no"': () =>
          almacen(pospuesto: DayKey.addDays(hoy, 1)),
      'si no se puede leer el estado': () =>
          almacen()..readError = StateError('sin acceso'),
    };
    noAparece.forEach((caso, store) {
      testWidgets('no aparece $caso', (tester) async {
        await datos();
        await pumpInicio(tester, store());
        expect(find.text(tituloSin), findsNothing);
        expect(find.byIcon(Icons.save_outlined), findsNothing);
        expect(tester.takeException(), isNull);
        await db.close();
      });
    });

    testWidgets('sin registros no aparece; con el primer dia registrado si',
        (tester) async {
      await pumpInicio(tester, almacen());
      expect(find.text(tituloSin), findsNothing);

      await tester.runAsync(() => repo.markPeriodDays(['2026-10-02']));
      await tester.pumpAndSettle();
      expect(find.text(tituloSin), findsOneWidget);
      await db.close();
    });

    testWidgets('el dia en que vence el "Ahora no" vuelve a aparecer',
        (tester) async {
      await datos();
      await pumpInicio(tester, almacen(pospuesto: hoy));
      expect(find.text(tituloSin), findsOneWidget);
      await db.close();
    });
  });

  group('botones', () {
    testWidgets('"Ahora no" la oculta y pospone 7 dias', (tester) async {
      await datos();
      final store = almacen();
      await pumpInicio(tester, store);
      await tester.tap(find.text('Ahora no'));
      await tester.pumpAndSettle();

      expect(find.text(tituloSin), findsNothing);
      expect(store.current!.pospuestoHasta, '2026-10-16');
      expect(store.current!.activado, isTrue);
      await db.close();
    });

    testWidgets('"No recordármelo más" apaga el interruptor y avisa donde '
        'volver a activarlo', (tester) async {
      await datos();
      final store = almacen();
      await pumpInicio(tester, store);
      await tester.tap(find.text('No recordármelo más'));
      await tester.pumpAndSettle();

      expect(find.text(tituloSin), findsNothing);
      expect(store.current!.activado, isFalse);
      expect(find.text('Puedes volver a activarlo en Ajustes.'),
          findsOneWidget);
      await db.close();
    });

    testWidgets('si no se puede guardar el cambio: avisa y sigue visible',
        (tester) async {
      await datos();
      final store = almacen()..writeError = StateError('detalle interno');
      await pumpInicio(tester, store);
      for (final boton in ['Ahora no', 'No recordármelo más']) {
        await tester.tap(find.text(boton));
        await tester.pumpAndSettle();
        expect(find.text('No se pudo guardar el cambio. Inténtalo de nuevo.'),
            findsOneWidget);
        expect(find.text('Puedes volver a activarlo en Ajustes.'),
            findsNothing);
        expect(find.text(tituloSin), findsOneWidget);
      }
      await db.close();
    });

    testWidgets('"Crear respaldo" abre el mismo dialogo de datos de salud',
        (tester) async {
      await datos();
      await pumpInicio(tester, almacen());
      await tester.tap(find.widgetWithText(ElevatedButton, 'Crear respaldo'));
      await tester.pumpAndSettle();

      expect(find.text('Tu respaldo tiene datos de salud'), findsOneWidget);
      expect(find.text('Guardar en el teléfono'), findsOneWidget);
      expect(find.text('Compartir'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text(tituloSin), findsOneWidget);
      await db.close();
    });

    testWidgets('tras guardar un respaldo, la tarjeta se va sola y el aviso '
        'de exito se ve', (tester) async {
      await datos();
      final store = almacen(ultimo: '2026-09-01');
      await pumpInicio(tester, store);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Crear respaldo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar en el teléfono'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar sin contraseña'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog).last,
        matching: find.text('Continuar sin contraseña'),
      ));
      await tester.pumpAndSettle();

      expect(gateway.savedFileName, 'aura_respaldo_2026-10-04.json');
      expect(store.current!.ultimoRespaldo, hoy);
      expect(find.textContaining('que no creas un respaldo'), findsNothing);
      expect(find.text('Respaldo guardado.'), findsOneWidget);
      await db.close();
    });

    testWidgets('cancelar el "Guardar como" no la oculta', (tester) async {
      await datos();
      gateway.saveResult = false;
      final store = almacen();
      await pumpInicio(tester, store);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Crear respaldo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar en el teléfono'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar sin contraseña'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog).last,
        matching: find.text('Continuar sin contraseña'),
      ));
      await tester.pumpAndSettle();

      expect(store.recordCount, 0);
      expect(find.text(tituloSin), findsOneWidget);
      await db.close();
    });

    testWidgets('con otra operacion de respaldo en curso (Ajustes), "Crear '
        'respaldo" queda deshabilitado', (tester) async {
      await datos();
      final busy = ValueNotifier<bool>(true);
      await pumpInicio(tester, almacen(), busy: busy);
      final boton = find.widgetWithText(ElevatedButton, 'Crear respaldo');
      expect(tester.widget<ElevatedButton>(boton).onPressed, isNull);

      busy.value = false;
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(boton).onPressed, isNotNull);
      await db.close();
    });
  });

  group('posicion y accesibilidad', () {
    testWidgets('debajo de la tarjeta del ciclo y de "¿Sigue tu período '
        'hoy?", antes del aviso del pie, dentro del scroll', (tester) async {
      await datos(conTarjetaPeriodo: true);
      await pumpInicio(tester, almacen());
      final titulo = find.text(tituloSin);
      expect(find.text(tarjetaPeriodo), findsOneWidget);
      expect(tester.getTopLeft(titulo).dy,
          greaterThan(tester.getTopLeft(find.text('Sigue')).dy));
      expect(tester.getTopLeft(titulo).dy,
          lessThan(tester.getTopLeft(find.text(aviso)).dy));
      expect(
          find.ancestor(
              of: titulo, matching: find.byType(SingleChildScrollView)),
          findsOneWidget);
      // Los botones fijos de #17 siguen fuera del scroll.
      expect(
          find.ancestor(
              of: find.widgetWithText(ElevatedButton, 'Registrar día'),
              matching: find.byType(Scrollable)),
          findsNothing);
      await db.close();
    });

    testWidgets('titulo como encabezado, botones de 48 dp y orden de lectura',
        (tester) async {
      final handle = tester.ensureSemantics();
      await datos(conTarjetaPeriodo: true);
      await pumpInicio(tester, almacen());

      expect(tester.getSemantics(find.text(tituloSin)),
          isSemantics(label: tituloSin, isHeader: true));
      for (final boton in [
        find.widgetWithText(ElevatedButton, 'Crear respaldo'),
        find.widgetWithText(OutlinedButton, 'Ahora no'),
        find.widgetWithText(TextButton, 'No recordármelo más'),
      ]) {
        final tamano = tester.getSize(boton);
        expect(tamano.height, greaterThanOrEqualTo(48));
        expect(tamano.width, greaterThanOrEqualTo(48));
        expect(tester.getSemantics(boton),
            isSemantics(isButton: true, hasTapAction: true));
      }

      // Orden de lectura: periodo, tarjeta (titulo, texto, botones), pie.
      final etiquetas = <String>[];
      void visitar(SemanticsNode nodo) {
        if (nodo.label.isNotEmpty) etiquetas.add(nodo.label);
        for (final hijo in nodo.debugListChildrenInOrder(
            DebugSemanticsDumpOrder.traversalOrder)) {
          visitar(hijo);
        }
      }

      visitar(tester.getSemantics(find.byType(HomeScreen)));
      int indice(String texto) =>
          etiquetas.indexWhere((e) => e.contains(texto));
      final orden = [
        indice(tarjetaPeriodo),
        indice(tituloSin),
        indice(textoSin),
        indice('Crear respaldo'),
        indice('Ahora no'),
        indice('No recordármelo más'),
        indice(aviso),
      ];
      expect(orden, everyElement(greaterThanOrEqualTo(0)));
      expect(orden, orderedEquals([...orden]..sort()));

      // Sin liveRegion: no interrumpe al abrir Inicio.
      for (final texto in [tituloSin, textoSin]) {
        expect(tester.getSemantics(find.text(texto)),
            isSemantics(isLiveRegion: false));
      }
      handle.dispose();
      await db.close();
    });
  });

  group('360 x 640 con la tarjeta del periodo abierta a la vez', () {
    for (final escala in [1.0, 1.3, 1.5, 2.0]) {
      for (final ultimo in [null, '2025-12-28']) {
        testWidgets(
            'texto $escala, ${ultimo == null ? 'sin' : 'con'} respaldo previo: '
            'sin desbordes y el area desplazable sobre 200 dp',
            (tester) async {
          await datos(conTarjetaPeriodo: true);
          await pumpInicio(tester, almacen(ultimo: ultimo),
              tamano: const Size(360, 640), escala: escala);
          expect(tester.takeException(), isNull);
          expect(find.text(tarjetaPeriodo), findsOneWidget);

          final alto =
              tester.getSize(find.byType(SingleChildScrollView)).height;
          expect(alto, greaterThan(200));

          for (final texto in [
            ultimo == null ? tituloSin : 'Hace 285 días que no creas un respaldo',
            'Crear respaldo',
            'Ahora no',
            'No recordármelo más',
            aviso,
          ]) {
            final finder = find.text(texto);
            await tester.scrollUntilVisible(finder, 150,
                scrollable: find.byType(Scrollable).first);
            await tester.ensureVisible(finder);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: texto);
            final rect = tester.getRect(finder);
            expect(rect.left, greaterThanOrEqualTo(0), reason: texto);
            expect(rect.right, lessThanOrEqualTo(360), reason: texto);
          }
          await db.close();
        });
      }
    }
  });
}
