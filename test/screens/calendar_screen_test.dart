import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/domain/backup_codec.dart';
import 'package:aura/screens/calendar_screen.dart';

Future<void> _tapDay(WidgetTester tester, int day) async {
  await tester.tap(find.text('$day').first);
  await tester.pumpAndSettle();
}

/// Pantalla alta: el boton "Me llego hoy" y la leyenda empujan el
/// panel del dia fuera de los 800x600 del test.
Future<void> _pumpCalendar(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: CalendarScreen()));
}

/// Retrocede [times] meses en el calendario tocando la flecha izquierda
/// del encabezado, para operar siempre sobre un mes completamente en el
/// pasado respecto a "hoy" sin importar en que dia del mes corra el test.
Future<void> _irAMesAnterior(WidgetTester tester, [int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
  }
}

String _clave(DateTime base, int day) {
  return '${base.year.toString().padLeft(4, '0')}-'
      '${base.month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  late AppDatabase db;
  late CycleRepository repo;

  // Mes de referencia (2 meses atras) para elegir dias de prueba que
  // nunca caigan en el futuro, sea cual sea la fecha real de ejecucion.
  final mesPasado = DateTime(DateTime.now().year, DateTime.now().month - 2, 1);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CycleRepository(db);
    cycleRepository = repo;
  });

  testWidgets('seleccionar un dia y registrarlo lo marca como menstruacion',
      (tester) async {
    await _pumpCalendar(tester);
    await tester.pumpAndSettle();
    await _irAMesAnterior(tester, 2);

    await _tapDay(tester, 10);
    await tester.tap(find.text('Registrar día de menstruación'));
    await tester.pumpAndSettle();

    expect(find.text('Quitar marca'), findsOneWidget);

    await db.close();
  });

  testWidgets(
      'Quitar marca sobre un dia marcado lo desmarca y Deshacer lo recupera',
      (tester) async {
    final key = _clave(mesPasado, 10);
    await repo.markPeriodDay(key);

    await _pumpCalendar(tester);
    await tester.pumpAndSettle();
    await _irAMesAnterior(tester, 2);

    await _tapDay(tester, 10);
    expect(find.text('Quitar marca'), findsOneWidget);

    await tester.tap(find.text('Quitar marca'));
    await tester.pumpAndSettle();

    final despues = await repo.getDay(key);
    expect(despues!.isPeriodDay, isFalse);
    expect(despues.periodDayExplicit, isTrue);
    expect(find.text('Registrar día de menstruación'), findsOneWidget);

    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();

    final trasDeshacer = await repo.getDay(key);
    expect(trasDeshacer!.isPeriodDay, isTrue);

    await db.close();
  });

  testWidgets('el aviso "Marca quitada" con Deshacer se cierra solo a los '
      '8 segundos', (tester) async {
    await repo.markPeriodDay(_clave(mesPasado, 10));

    await _pumpCalendar(tester);
    await tester.pumpAndSettle();
    await _irAMesAnterior(tester, 2);
    await _tapDay(tester, 10);

    await tester.tap(find.text('Quitar marca'));
    await tester.pumpAndSettle();
    expect(find.text('Marca quitada'), findsOneWidget);

    await tester.pump(const Duration(seconds: 7));
    expect(find.text('Marca quitada'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Marca quitada'), findsNothing);

    await db.close();
  });

  testWidgets('seleccionar un rango y confirmarlo marca todos los dias',
      (tester) async {
    await _pumpCalendar(tester);
    await tester.pumpAndSettle();
    await _irAMesAnterior(tester, 2);

    await tester.tap(find.text('Elegir varios días'));
    await tester.pumpAndSettle();

    await _tapDay(tester, 5);
    await _tapDay(tester, 8);

    expect(find.textContaining('· 4 días'), findsOneWidget);

    await tester.tap(find.text('Marcar período'));
    await tester.pumpAndSettle();

    for (final day in [5, 6, 7, 8]) {
      final row = await repo.getDay(_clave(mesPasado, day));
      expect(row?.isPeriodDay, isTrue, reason: 'dia $day');
    }

    await db.close();
  });

  testWidgets('un rango de mas de 10 dias pide confirmacion extra',
      (tester) async {
    await _pumpCalendar(tester);
    await tester.pumpAndSettle();
    await _irAMesAnterior(tester, 2);

    await tester.tap(find.text('Elegir varios días'));
    await tester.pumpAndSettle();

    await _tapDay(tester, 1);
    await _tapDay(tester, 15);

    await tester.tap(find.text('Marcar período'));
    await tester.pumpAndSettle();

    expect(find.text('Confirmar rango largo'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(await repo.getPeriodDayDates(), isEmpty);

    await db.close();
  });

  testWidgets('los dias futuros no se pueden seleccionar', (tester) async {
    await _pumpCalendar(tester);
    await tester.pumpAndSettle();

    final calendar = tester.widget<TableCalendar>(find.byType(TableCalendar));
    final manana = DateTime.now().add(const Duration(days: 1));
    expect(calendar.enabledDayPredicate!(manana), isFalse);

    await db.close();
  });

  testWidgets(
      'un cambio hecho fuera del calendario (importar un respaldo) se ve sin '
      'volver a abrir la pantalla', (tester) async {
    await _pumpCalendar(tester);
    await tester.pumpAndSettle();
    await _irAMesAnterior(tester, 2);
    await _tapDay(tester, 10);
    expect(find.text('Registrar día de menstruación'), findsOneWidget);

    await repo.replaceAllWithBackup(BackupData(
      schemaVersion: currentBackupSchemaVersion,
      appVersion: '1.0.1',
      exportedAt: '2026-10-04T10:15:00-03:00',
      days: [
        BackupDay(
          date: _clave(mesPasado, 10),
          isPeriodDay: true,
          periodDayExplicit: false,
        ),
      ],
      settings: const BackupSettings(
        onboardingSeen: true,
        notificationsEnabled: false,
        periodReminderEnabled: true,
        fertileWindowRemindersEnabled: false,
        showDetailsEnabled: false,
        reminderHour: 9,
        reminderMinute: 0,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Quitar marca'), findsOneWidget);

    await db.close();
  });
}
