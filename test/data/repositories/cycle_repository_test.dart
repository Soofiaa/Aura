import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura/data/database/app_database.dart';
import 'package:aura/data/models/day_enums.dart';
import 'package:aura/data/repositories/cycle_repository.dart';

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

  group('getDay / upsertDay basico', () {
    test('un dia inexistente devuelve null', () async {
      expect(await repo.getDay('2026-01-01'), isNull);
    });

    test('interruptor encendido crea dia de periodo con flow', () async {
      await repo.upsertDay(
        date: '2026-01-01',
        isPeriodDaySwitch: true,
        flow: FlowIntensity.moderado,
        mood: Mood.normal,
        notes: 'ok',
        symptoms: {Symptom.cansancio},
      );

      final day = await repo.getDay('2026-01-01');
      expect(day!.isPeriodDay, isTrue);
      expect(day.flow, FlowIntensity.moderado);
      expect(day.mood, Mood.normal);
      expect(day.notes, 'ok');
      expect(await repo.getSymptomsForDay('2026-01-01'), {Symptom.cansancio});
    });

    test(
        'interruptor apagado sin dia previo: no es dia de periodo Y NO '
        'produce una negacion explicita (hallazgo de la auditoria: el '
        'formulario general no es una declaracion)', () async {
      await repo.upsertDay(
        date: '2026-01-02',
        isPeriodDaySwitch: false,
        mood: Mood.feliz,
        symptoms: {Symptom.antojos},
      );

      final day = await repo.getDay('2026-01-02');
      expect(day!.isPeriodDay, isFalse);
      expect(day.flow, isNull);
      expect(day.mood, Mood.feliz);
      expect(day.periodDayExplicit, isFalse);
    });

    test(
        'interruptor apagado sobre un dia que YA era false: tampoco toca '
        'period_day_explicit si ya era true (negacion explicita previa)',
        () async {
      await repo.setPeriodDayExplicitly('2026-01-03', isPeriodDay: false);
      await repo.upsertDay(
        date: '2026-01-03',
        isPeriodDaySwitch: false,
        mood: Mood.feliz,
      );

      final day = await repo.getDay('2026-01-03');
      expect(day!.isPeriodDay, isFalse);
      expect(day.periodDayExplicit, isTrue,
          reason: 'la negacion explicita previa no se pierde');
      expect(day.mood, Mood.feliz);
    });
  });

  group('markPeriodDay (calendar_screen)', () {
    test('marca un dia nuevo y devuelve true', () async {
      final result = await repo.markPeriodDay('2026-02-01');
      expect(result, isTrue);
      expect((await repo.getDay('2026-02-01'))!.isPeriodDay, isTrue);
    });

    test('marcar un dia ya marcado devuelve false y no lo toca', () async {
      await repo.markPeriodDay('2026-02-01');
      final result = await repo.markPeriodDay('2026-02-01');
      expect(result, isFalse);
    });
  });

  group(
      'upsertDay con interruptor prellenado: apagarlo es una correccion '
      'deliberada (revisado tras la fase de registro rapido de fin de '
      'periodo)', () {
    test(
        'dia marcado desde el calendario, luego el formulario se abre '
        '(prellena el interruptor en "si") y la usuaria lo apaga a '
        'proposito: SI desmarca, y queda como negacion explicita', () async {
      // 1) El dia se marca como periodo desde el calendario (sin flow).
      await repo.markPeriodDay('2026-03-05');
      var day = await repo.getDay('2026-03-05');
      expect(day!.isPeriodDay, isTrue);
      expect(day.periodDayExplicit, isFalse);

      // 2) add_cycle_screen abre ese dia: el interruptor se prellena en
      // "si" (porque is_period_day ya era true) y la usuaria lo apaga a
      // proposito antes de guardar -- unica forma de que isPeriodDaySwitch
      // llegue en false para un dia que ya estaba en true.
      await repo.upsertDay(
        date: '2026-03-05',
        isPeriodDaySwitch: false,
        mood: Mood.cansada,
        notes: 'dolor de cabeza leve',
        symptoms: {Symptom.dolorDeCabeza},
      );

      day = await repo.getDay('2026-03-05');
      expect(day!.isPeriodDay, isFalse,
          reason: 'apagar un interruptor prellenado es una correccion '
              'deliberada, equivalente a "Quitar marca"');
      expect(day.flow, isNull);
      expect(day.periodDayExplicit, isTrue);
      expect(day.mood, Mood.cansada);
      expect(day.notes, 'dolor de cabeza leve');
      expect(
        await repo.getSymptomsForDay('2026-03-05'),
        {Symptom.dolorDeCabeza},
      );

      // 3) Si despues se guarda con el interruptor encendido y flow, se
      // fija el flow y se limpia la negacion explicita (un "si" ya no es
      // una negacion).
      await repo.upsertDay(
        date: '2026-03-05',
        isPeriodDaySwitch: true,
        flow: FlowIntensity.abundante,
        mood: Mood.cansada,
      );
      day = await repo.getDay('2026-03-05');
      expect(day!.isPeriodDay, isTrue);
      expect(day.flow, FlowIntensity.abundante);
      expect(day.periodDayExplicit, isFalse);
    });
  });

  group('setPeriodDayExplicitly', () {
    test('confirmar "si" marca is_period_day y period_day_explicit en true',
        () async {
      await repo.setPeriodDayExplicitly('2026-05-01', isPeriodDay: true);
      final day = await repo.getDay('2026-05-01');
      expect(day!.isPeriodDay, isTrue);
      expect(day.periodDayExplicit, isTrue);
    });

    test('confirmar "no" sobre un dia sin fila previa lo crea en false',
        () async {
      await repo.setPeriodDayExplicitly('2026-05-02', isPeriodDay: false);
      final day = await repo.getDay('2026-05-02');
      expect(day!.isPeriodDay, isFalse);
      expect(day.periodDayExplicit, isTrue);
    });

    test('confirmar "no" sobre un dia marcado true lo baja a false y '
        'limpia el flow (el CHECK de la tabla lo exige)', () async {
      await repo.markPeriodDay('2026-05-03');
      await repo.upsertDay(
        date: '2026-05-03',
        isPeriodDaySwitch: true,
        flow: FlowIntensity.abundante,
      );

      await repo.setPeriodDayExplicitly('2026-05-03', isPeriodDay: false);

      final day = await repo.getDay('2026-05-03');
      expect(day!.isPeriodDay, isFalse);
      expect(day.flow, isNull);
      expect(day.periodDayExplicit, isTrue);
    });

    test('no toca mood/notes/sintomas existentes', () async {
      await repo.upsertDay(
        date: '2026-05-04',
        isPeriodDaySwitch: true,
        mood: Mood.triste,
        notes: 'nota',
        symptoms: {Symptom.acne},
      );

      await repo.setPeriodDayExplicitly('2026-05-04', isPeriodDay: false);

      final day = await repo.getDay('2026-05-04');
      expect(day!.mood, Mood.triste);
      expect(day.notes, 'nota');
      expect(await repo.getSymptomsForDay('2026-05-04'), {Symptom.acne});
    });
  });

  group('watchDay', () {
    test('emite de nuevo cuando cambia la fila de esa fecha', () async {
      final emissions = <bool?>[];
      final sub = repo
          .watchDay('2026-07-05')
          .map((row) => row?.isPeriodDay)
          .listen(emissions.add);

      await Future<void>.delayed(Duration.zero);
      await repo.setPeriodDayExplicitly('2026-07-05', isPeriodDay: true);
      await Future<void>.delayed(Duration.zero);

      await sub.cancel();
      expect(emissions, [null, true]);
    });
  });

  group('eliminar un dia borra sus sintomas en cascada', () {
    test('ON DELETE CASCADE limpia daily_log_symptoms', () async {
      await repo.upsertDay(
        date: '2026-04-01',
        isPeriodDaySwitch: true,
        flow: FlowIntensity.ligero,
        symptoms: {Symptom.acne, Symptom.hinchazon},
      );
      expect(await repo.getSymptomsForDay('2026-04-01'), hasLength(2));

      await (db.delete(db.dailyLogs)..where((t) => t.date.equals('2026-04-01')))
          .go();

      expect(await repo.getSymptomsForDay('2026-04-01'), isEmpty);
    });
  });

  group('getDerivedCycles', () {
    test('usa solo los dias marcados como periodo', () async {
      await repo.markPeriodDay('2026-05-01');
      await repo.markPeriodDay('2026-05-02');
      await repo.upsertDay(date: '2026-05-15', isPeriodDaySwitch: false);

      final cycles = await repo.getDerivedCycles();
      expect(cycles, hasLength(1));
      expect(cycles.single.startDate, '2026-05-01');
      expect(cycles.single.periodLengthDays, 2);
    });

    test(
        'un dia confirmado explicitamente como "sin sangrado" via '
        'setPeriodDayExplicitly llega a periodConfirmedEnded', () async {
      await repo.markPeriodDay('2026-05-20');
      await repo.markPeriodDay('2026-05-21');
      await repo.setPeriodDayExplicitly('2026-05-22', isPeriodDay: false);

      final cycles = await repo.getDerivedCycles();
      expect(cycles.single.periodConfirmedEnded, isTrue);
    });

    test(
        'un dia con is_period_day=false del formulario general (sin '
        'period_day_explicit) NO llega a periodConfirmedEnded', () async {
      await repo.markPeriodDay('2026-05-25');
      await repo.markPeriodDay('2026-05-26');
      // Registro de sintomas comun, sin fila previa, interruptor apagado:
      // exactamente el hallazgo de la auditoria.
      await repo.upsertDay(date: '2026-05-27', isPeriodDaySwitch: false);

      final cycles = await repo.getDerivedCycles();
      expect(cycles.single.periodConfirmedEnded, isFalse);
    });

    test('watchDerivedCycles tambien refleja la confirmacion explicita',
        () async {
      await repo.markPeriodDay('2026-06-10');
      final emissions = <bool>[];
      final sub = repo
          .watchDerivedCycles()
          .map((cycles) => cycles.single.periodConfirmedEnded)
          .listen(emissions.add);

      await Future<void>.delayed(Duration.zero);
      await repo.setPeriodDayExplicitly('2026-06-11', isPeriodDay: false);
      await Future<void>.delayed(Duration.zero);

      await sub.cancel();
      expect(emissions, [false, true]);
    });
  });

  group('estadisticas', () {
    setUp(() async {
      await repo.upsertDay(
        date: '2026-06-01',
        isPeriodDaySwitch: true,
        flow: FlowIntensity.ligero,
        mood: Mood.feliz,
        symptoms: {Symptom.cansancio, Symptom.antojos},
      );
      await repo.upsertDay(
        date: '2026-06-02',
        isPeriodDaySwitch: true,
        flow: FlowIntensity.abundante,
        mood: Mood.feliz,
        symptoms: {Symptom.cansancio},
      );
      // Dia marcado solo desde el calendario: sin flow ni mood, no debe
      // contaminar las estadisticas de animo ni de flujo.
      await repo.markPeriodDay('2026-06-03');
    });

    test('frecuencia de sintomas', () async {
      final freq = await repo.getSymptomFrequency();
      expect(freq[Symptom.cansancio], 2);
      expect(freq[Symptom.antojos], 1);
    });

    test('frecuencia de animo ignora dias sin mood', () async {
      final freq = await repo.getMoodFrequency();
      expect(freq[Mood.feliz], 2);
      expect(freq.containsKey(null), isFalse);
    });

    test('promedio de flujo (ligero=1, abundante=3) ignora dias sin flow',
        () async {
      final avg = await repo.getAverageFlow();
      expect(avg, closeTo(2.0, 0.001)); // (1 + 3) / 2
    });

    test('promedio de flujo es 0 sin datos', () async {
      final emptyDb =
          AppDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
      final emptyRepo = CycleRepository(emptyDb);
      expect(await emptyRepo.getAverageFlow(), 0);
      await emptyDb.close();
    });
  });

  group('app_settings (fila unica)', () {
    test('valores por defecto antes de escribir nada', () async {
      expect(await repo.getOnboardingSeen(), isFalse);
      // Opt-in, no opt-out (fase 4): las notificaciones arrancan apagadas.
      expect(await repo.getNotificationsEnabled(), isFalse);
    });

    test('setOnboardingSeen no pisa notificationsEnabled', () async {
      await repo.setNotificationsEnabled(false);
      await repo.setOnboardingSeen(true);

      expect(await repo.getOnboardingSeen(), isTrue);
      expect(await repo.getNotificationsEnabled(), isFalse);
    });

    test('getNotificationSettings: defaults correctos', () async {
      final settings = await repo.getNotificationSettings();
      expect(settings.notificationsEnabled, isFalse);
      expect(settings.periodReminderEnabled, isTrue);
      expect(settings.fertileWindowRemindersEnabled, isFalse);
      expect(settings.showDetailsEnabled, isFalse);
      expect(settings.reminderHour, 9);
      expect(settings.reminderMinute, 0);
    });

    test('los setters de notificaciones no se pisan entre si', () async {
      await repo.setNotificationsEnabled(true);
      await repo.setPeriodReminderEnabled(false);
      await repo.setFertileWindowRemindersEnabled(true);
      await repo.setShowDetailsEnabled(true);
      await repo.setReminderTime(hour: 20, minute: 30);

      final settings = await repo.getNotificationSettings();
      expect(settings.notificationsEnabled, isTrue);
      expect(settings.periodReminderEnabled, isFalse);
      expect(settings.fertileWindowRemindersEnabled, isTrue);
      expect(settings.showDetailsEnabled, isTrue);
      expect(settings.reminderHour, 20);
      expect(settings.reminderMinute, 30);
    });

    test('watchNotificationSettings emite de nuevo al cambiar un toggle',
        () async {
      // Pre-crea la fila: si el stream tuviera que crearla el solo en su
      // primera emision, esa misma escritura dispara una emision extra.
      await repo.getNotificationSettings();

      final emissions = <bool>[];
      final sub = repo
          .watchNotificationSettings()
          .map((s) => s.fertileWindowRemindersEnabled)
          .listen(emissions.add);

      await Future<void>.delayed(Duration.zero);
      await repo.setFertileWindowRemindersEnabled(true);
      await Future<void>.delayed(Duration.zero);

      await sub.cancel();
      expect(emissions, [false, true]);
    });
  });

  group('deleteAllData', () {
    test('borra daily_logs, daily_log_symptoms y app_settings', () async {
      await repo.upsertDay(
        date: '2026-07-01',
        isPeriodDaySwitch: true,
        flow: FlowIntensity.ligero,
        symptoms: {Symptom.acne},
      );
      await repo.setOnboardingSeen(true);

      await repo.deleteAllData();

      expect(await repo.getDay('2026-07-01'), isNull);
      expect(await repo.getSymptomsForDay('2026-07-01'), isEmpty);
      // app_settings tambien se borra por completo: onboarding vuelve a
      // su default (false) hasta que algo la vuelva a crear.
      expect(await repo.getOnboardingSeen(), isFalse);
    });
  });
  group('periodo cerrado (v4): period_end y su CHECK', () {
    /// Periodo de 3 dias cerrado en su ultimo dia, como lo deja la
    /// migracion (o, en la v1.1, "Termino hoy").
    Future<void> closedPeriod(PeriodEndSource source) async {
      await repo.markPeriodDays(['2026-03-01', '2026-03-02']);
      await db.into(db.dailyLogs).insert(DailyLogsCompanion.insert(
            date: '2026-03-03',
            isPeriodDay: const Value(true),
            periodEnd: Value(source),
          ));
    }

    test('getDerivedCycles entrega periodEnd del ultimo dia', () async {
      await closedPeriod(PeriodEndSource.inferred);
      final cycle = (await repo.getDerivedCycles()).single;
      expect(cycle.periodEnd, PeriodEndSource.inferred);
      expect(cycle.isClosed, isTrue);
    });

    test(
        '"Quitar marca" sobre el dia con period_end no choca con el CHECK: '
        'lo limpia y el periodo sigue cerrado por el "no"', () async {
      await closedPeriod(PeriodEndSource.declared);

      await repo.setPeriodDayExplicitly('2026-03-03', isPeriodDay: false);

      final day = await repo.getDay('2026-03-03');
      expect(day!.isPeriodDay, isFalse);
      expect(day.periodEnd, isNull);
      final cycle = (await repo.getDerivedCycles()).single;
      expect(cycle.periodLengthDays, 2);
      expect(cycle.periodConfirmedEnded, isTrue);
      expect(cycle.isClosed, isTrue);
    });

    test(
        'confirmar "si" sobre el dia con period_end no lo borra', () async {
      await closedPeriod(PeriodEndSource.declared);
      await repo.setPeriodDayExplicitly('2026-03-03', isPeriodDay: true);
      expect((await repo.getDay('2026-03-03'))!.periodEnd,
          PeriodEndSource.declared);
    });

    test(
        'apagar el interruptor del formulario sobre el dia con period_end '
        'no choca con el CHECK y el periodo sigue cerrado', () async {
      await closedPeriod(PeriodEndSource.inferred);

      await repo.upsertDay(date: '2026-03-03', isPeriodDaySwitch: false);

      final day = await repo.getDay('2026-03-03');
      expect(day!.isPeriodDay, isFalse);
      expect(day.periodEnd, isNull);
      expect(day.periodDayExplicit, isTrue);
      expect((await repo.getDerivedCycles()).single.isClosed, isTrue);
    });

    test('guardar el formulario con el interruptor encendido conserva '
        'period_end', () async {
      await closedPeriod(PeriodEndSource.declared);
      await repo.upsertDay(
          date: '2026-03-03', isPeriodDaySwitch: true, mood: Mood.feliz);
      expect((await repo.getDay('2026-03-03'))!.periodEnd,
          PeriodEndSource.declared);
    });

    test(
        'marcar el dia siguiente al fin reabre el periodo sin borrar la marca; '
        'quitarlo lo vuelve a cerrar (R-4)', () async {
      await closedPeriod(PeriodEndSource.declared);

      await repo.markPeriodDay('2026-03-04');
      expect((await repo.getDay('2026-03-03'))!.periodEnd,
          PeriodEndSource.declared);
      expect((await repo.getDerivedCycles()).single.isClosed, isFalse);

      await (db.delete(db.dailyLogs)
            ..where((t) => t.date.equals('2026-03-04')))
          .go();
      expect((await repo.getDerivedCycles()).single.isClosed, isTrue);
    });

    test('marcar un rango encima del fin no toca period_end', () async {
      await closedPeriod(PeriodEndSource.inferred);
      await repo.markPeriodDays(['2026-03-02', '2026-03-03']);
      expect((await repo.getDay('2026-03-03'))!.periodEnd,
          PeriodEndSource.inferred);
    });
  });

  group('duracion habitual del periodo (typical_period_length)', () {
    test('vale 5 por defecto', () async {
      expect(await repo.getTypicalPeriodLength(), 5);
    });

    test('se guarda entre 1 y 15', () async {
      await repo.setTypicalPeriodLength(1);
      expect(await repo.getTypicalPeriodLength(), 1);
      await repo.setTypicalPeriodLength(15);
      expect(await repo.getTypicalPeriodLength(), 15);
    });

    test('fuera de 1 a 15 lanza ArgumentError y no cambia nada', () async {
      await repo.setTypicalPeriodLength(7);
      expect(() => repo.setTypicalPeriodLength(0), throwsArgumentError);
      expect(() => repo.setTypicalPeriodLength(16), throwsArgumentError);
      expect(await repo.getTypicalPeriodLength(), 7);
    });

    test('no cambia ningun otro ajuste', () async {
      await repo.setReminderTime(hour: 21, minute: 30);
      await repo.setTypicalPeriodLength(4);
      final settings = await repo.getNotificationSettings();
      expect(settings.reminderHour, 21);
      expect(settings.reminderMinute, 30);
    });

    test('"Borrar todos los datos" la vuelve a 5 (HU-01, criterio 4)',
        () async {
      await repo.setTypicalPeriodLength(9);
      await repo.deleteAllData();
      expect(await repo.getTypicalPeriodLength(), 5);
    });
  });

  group('watchPredictionInputs', () {
    test('entrega los ciclos y la duracion habitual (5 sin ajustes)',
        () async {
      await repo.markPeriodDays(['2026-03-01', '2026-03-02']);
      final inputs = await repo.watchPredictionInputs().first;
      expect(inputs.cycles.single.startDate, '2026-03-01');
      expect(inputs.typicalPeriodLengthDays, 5);
      expect(inputs.config.typicalPeriodLengthDays, 5);
    });

    test('emite de nuevo cuando cambia un ajuste (sin tocar los dias)',
        () async {
      final values = repo
          .watchPredictionInputs()
          .map((i) => i.typicalPeriodLengthDays)
          .distinct();
      final expectation = expectLater(values, emitsInOrder([5, 8]));
      await Future<void>.delayed(Duration.zero);
      await repo.setTypicalPeriodLength(8);
      await expectation;
    });

    test('emite de nuevo cuando cambian los dias', () async {
      final counts =
          repo.watchPredictionInputs().map((i) => i.cycles.length).distinct();
      final expectation = expectLater(counts, emitsInOrder([0, 1]));
      await Future<void>.delayed(Duration.zero);
      await repo.markPeriodDay('2026-03-01');
      await expectation;
    });
  });
}
