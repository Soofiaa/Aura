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

    test('interruptor apagado sin dia previo: no es dia de periodo', () async {
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
      'upsert no destructivo: dia marcado desde el calendario, luego '
      'registro de sintomas con el interruptor apagado', () {
    test(
        'conserva is_period_day=true y el flow existente (no desmarca por '
        'accidente); mood/notes/sintomas se actualizan con lo nuevo', () async {
      // 1) El dia se marca como periodo desde el calendario (sin flow).
      await repo.markPeriodDay('2026-03-05');
      var day = await repo.getDay('2026-03-05');
      expect(day!.isPeriodDay, isTrue);
      expect(day.flow, isNull);

      // 2) Se guarda un registro de sintomas ese mismo dia con el
      // interruptor de "dia de sangrado" APAGADO (p.ej. la usuaria solo
      // quiere anotar un sintoma, sin tocar el estado de sangrado).
      await repo.upsertDay(
        date: '2026-03-05',
        isPeriodDaySwitch: false,
        mood: Mood.cansada,
        notes: 'dolor de cabeza leve',
        symptoms: {Symptom.dolorDeCabeza},
      );

      // Comportamiento definido: is_period_day sigue true (no se
      // desmarca), flow sigue null (no se inventa uno), y mood/notes/
      // sintomas se actualizan con el nuevo registro.
      day = await repo.getDay('2026-03-05');
      expect(day!.isPeriodDay, isTrue);
      expect(day.flow, isNull);
      expect(day.mood, Mood.cansada);
      expect(day.notes, 'dolor de cabeza leve');
      expect(
        await repo.getSymptomsForDay('2026-03-05'),
        {Symptom.dolorDeCabeza},
      );

      // 3) Si despues se guarda con el interruptor encendido y flow,
      // ahi si se fija el flow (edicion explicita).
      await repo.upsertDay(
        date: '2026-03-05',
        isPeriodDaySwitch: true,
        flow: FlowIntensity.abundante,
        mood: Mood.cansada,
      );
      day = await repo.getDay('2026-03-05');
      expect(day!.isPeriodDay, isTrue);
      expect(day.flow, FlowIntensity.abundante);
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
}
