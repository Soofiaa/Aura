import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/notifications/notification_reconciler.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/screens/home_screen.dart';
import 'package:aura/utils/day_key.dart';

import '../support/fake_notification_scheduler.dart';

/// #17: los botones de accion de Inicio quedan fijos abajo, fuera del
/// scroll. Se mide a 360 x 640 dentro de una barra inferior como la de
/// MainNavigationScreen (NavigationBar de Material 3). Datos inventados:
/// periodos de 5 dias desde el 09/07, 05/08 y 03/09 de 2026.
void main() {
  late AppDatabase db;
  late CycleRepository repo;

  const tarjeta = '¿Sigue tu período hoy?';
  const aviso = 'Esta es una estimación, no un método anticonceptivo.';
  final registrar = find.widgetWithText(ElevatedButton, 'Registrar día');
  final meLlego = find.widgetWithText(ElevatedButton, 'Me llegó hoy');

  setUpAll(() async {
    await initializeDateFormatting();
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CycleRepository(db);
  });

  Future<void> periodo(String inicio, {bool cerrar = true}) async {
    final fechas = [for (var i = 0; i < 5; i++) DayKey.addDays(inicio, i)];
    await repo.markPeriodDays(fechas);
    if (cerrar) {
      await repo.closePeriod(inicio, fechas.last, today: fechas.last);
    }
  }

  /// Sin tarjeta: periodos cerrados, Inicio muestra "Me llego hoy" y
  /// "Registrar dia". Con tarjeta: periodo abierto del 01/10 con sangrado
  /// el 08/10, hoy 09/10; solo "Registrar dia".
  Future<void> datos({required bool conTarjeta}) async {
    for (final inicio in ['2026-07-09', '2026-08-05', '2026-09-03']) {
      await periodo(inicio);
    }
    if (conTarjeta) {
      await periodo('2026-10-01', cerrar: false);
      await repo.markPeriodDay('2026-10-08');
    }
  }

  Future<void> pumpInicio(WidgetTester tester, double escala,
      {EdgeInsets sistema = EdgeInsets.zero}) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(
        top: sistema.top, bottom: sistema.bottom);
    tester.platformDispatcher.textScaleFactorTestValue = escala;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final fecha = DateTime.parse('2026-10-09');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeScreen(
          repository: repo,
          clock: () => fecha,
          reconciler: NotificationReconciler(
              repo, FakeNotificationScheduler(),
              clock: () => fecha),
        ),
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

  double altoDesplazable(WidgetTester tester) =>
      tester.getSize(find.byType(SingleChildScrollView)).height;

  for (final conTarjeta in [false, true]) {
    final caso = conTarjeta ? 'con la tarjeta' : 'sin la tarjeta';

    testWidgets('$caso: los botones no estan dentro del scroll',
        (tester) async {
      await datos(conTarjeta: conTarjeta);
      await pumpInicio(tester, 1.0);
      expect(find.text(tarjeta), conTarjeta ? findsOneWidget : findsNothing);
      expect(meLlego, conTarjeta ? findsNothing : findsOneWidget);
      expect(find.ancestor(of: registrar, matching: find.byType(Scrollable)),
          findsNothing);
      await db.close();
    });

    for (final escala in [1.0, 1.3, 1.5, 2.0]) {
      testWidgets(
          '$caso, texto $escala: botones a la vista sobre la barra, sin '
          'desbordes y el aviso termina sobre ellos', (tester) async {
        await datos(conTarjeta: conTarjeta);
        await pumpInicio(tester, escala);
        expect(tester.takeException(), isNull);

        final barra = tester.getRect(find.byType(NavigationBar));
        final rectRegistrar = tester.getRect(registrar);
        expect(rectRegistrar.bottom, lessThanOrEqualTo(barra.top));
        final area = tester.getRect(find.byType(SingleChildScrollView));
        final primerBoton = conTarjeta ? registrar : meLlego;
        expect(area.bottom, lessThanOrEqualTo(tester.getRect(primerBoton).top));

        // Al final del scroll el aviso queda entero sobre los botones.
        await tester.drag(find.byType(SingleChildScrollView),
            const Offset(0, -5000));
        await tester.pumpAndSettle();
        expect(tester.getRect(find.text(aviso)).bottom,
            lessThanOrEqualTo(area.bottom));
        expect(tester.getRect(registrar), rectRegistrar);

        // Condicion de #17: el area desplazable no baja de ~200 dp con
        // texto 1,0 y 1,3.
        if (escala <= 1.3) {
          expect(altoDesplazable(tester), greaterThanOrEqualTo(200));
        }
        await db.close();
      });
    }

    // Con barras del sistema tipicas (estado 24 dp, navegacion de tres
    // botones 48 dp) dentro de los mismos 640 dp.
    for (final escala in [1.0, 1.3]) {
      testWidgets('$caso, texto $escala, con barras del sistema: el area '
          'desplazable no baja de 200 dp', (tester) async {
        await datos(conTarjeta: conTarjeta);
        await pumpInicio(tester, escala,
            sistema: const EdgeInsets.only(top: 24, bottom: 48));
        expect(tester.takeException(), isNull);
        expect(altoDesplazable(tester), greaterThanOrEqualTo(200));
        await db.close();
      });
    }
  }
}
