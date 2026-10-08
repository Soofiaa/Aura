import 'package:flutter_test/flutter_test.dart';
import 'package:aura/domain/cycle_deriver.dart';
import 'package:aura/domain/cycle_predictor.dart';
import 'package:aura/domain/notification_planner.dart';

ActivePrediction _prediction({
  String nextPeriodEarliestDate = '2026-04-21',
  String fertileWindowStartDate = '2026-04-04',
  PredictionConfidence confidence = PredictionConfidence.high,
}) {
  return ActivePrediction(
    lastPeriodStartDate: '2026-03-26',
    daysSinceLastPeriodStart: 10,
    averageCycleLengthDays: 28,
    cycleLengthStdDevDays: 0,
    averagePeriodLengthDays: 5,
    completeCyclesConsidered: 4,
    excludedCyclesCount: 0,
    nextPeriodEarliestDate: nextPeriodEarliestDate,
    nextPeriodExpectedDate: '2026-04-23',
    nextPeriodLatestDate: '2026-04-25',
    estimatedOvulationDate: '2026-04-09',
    fertileWindowStartDate: fertileWindowStartDate,
    fertileWindowEndDate: '2026-04-09',
    currentPhase: CyclePhase.lutea,
    isPeriodLate: false,
    daysLate: 0,
    confidence: confidence,
    confidenceReasons: const [],
  );
}

const _settingsBase = NotificationSettings(
  notificationsEnabled: true,
  periodReminderEnabled: true,
  fertileWindowRemindersEnabled: true,
  showDetailsEnabled: false,
  reminderHour: 9,
  reminderMinute: 0,
);

void main() {
  group('planNotifications - casos base', () {
    test('predice ambos avisos con todo activado y tiempo de sobra', () {
      final plan = planNotifications(
        prediction: _prediction(),
        settings: _settingsBase,
        today: '2026-04-01',
        nowMinutesOfDay: 8 * 60,
      );

      expect(plan, hasLength(2));
      expect(plan[0].kind, NotificationKind.fertileWindowReminder);
      expect(plan[0].date, '2026-04-04');
      expect(plan[1].kind, NotificationKind.periodReminder);
      expect(plan[1].date, '2026-04-20'); // extremo temprano - 1
      expect(plan[1].hour, 9);
      expect(plan[1].minute, 0);
    });

    test('interruptor general apagado: nada, aunque los demas esten prendidos',
        () {
      final plan = planNotifications(
        prediction: _prediction(),
        settings: const NotificationSettings(
          notificationsEnabled: false,
          periodReminderEnabled: true,
          fertileWindowRemindersEnabled: true,
          showDetailsEnabled: false,
          reminderHour: 9,
          reminderMinute: 0,
        ),
        today: '2026-04-01',
        nowMinutesOfDay: 8 * 60,
      );
      expect(plan, isEmpty);
    });

    test('recordatorio de periodo desactivado: solo queda el fertil', () {
      final plan = planNotifications(
        prediction: _prediction(),
        settings: const NotificationSettings(
          notificationsEnabled: true,
          periodReminderEnabled: false,
          fertileWindowRemindersEnabled: true,
          showDetailsEnabled: false,
          reminderHour: 9,
          reminderMinute: 0,
        ),
        today: '2026-04-01',
        nowMinutesOfDay: 8 * 60,
      );
      expect(plan, hasLength(1));
      expect(plan.single.kind, NotificationKind.fertileWindowReminder);
    });

    test('ventana fertil desactivada (default): solo el recordatorio de periodo',
        () {
      final plan = planNotifications(
        prediction: _prediction(),
        settings: const NotificationSettings(
          notificationsEnabled: true,
          periodReminderEnabled: true,
          fertileWindowRemindersEnabled: false,
          showDetailsEnabled: false,
          reminderHour: 9,
          reminderMinute: 0,
        ),
        today: '2026-04-01',
        nowMinutesOfDay: 8 * 60,
      );
      expect(plan, hasLength(1));
      expect(plan.single.kind, NotificationKind.periodReminder);
    });
  });

  group('planNotifications - hora del dia (evita programar en el pasado)', () {
    test('hoy es el dia del aviso, antes de la hora: se incluye', () {
      final plan = planNotifications(
        prediction: _prediction(nextPeriodEarliestDate: '2026-04-21'),
        settings: _settingsBase, // 9:00
        today: '2026-04-20', // == fecha del aviso de periodo
        nowMinutesOfDay: 8 * 60 + 30, // 8:30, antes de las 9:00
      );
      expect(
        plan.any((n) => n.kind == NotificationKind.periodReminder),
        isTrue,
      );
    });

    test('hoy es el dia del aviso, despues de la hora: se omite (ya paso)',
        () {
      final plan = planNotifications(
        prediction: _prediction(nextPeriodEarliestDate: '2026-04-21'),
        settings: _settingsBase, // 9:00
        today: '2026-04-20',
        nowMinutesOfDay: 15 * 60 + 37, // 15:37, ya paso
      );
      expect(
        plan.any((n) => n.kind == NotificationKind.periodReminder),
        isFalse,
      );
    });

    test('hoy es el dia del aviso, exactamente a la hora: se omite', () {
      final plan = planNotifications(
        prediction: _prediction(nextPeriodEarliestDate: '2026-04-21'),
        settings: _settingsBase,
        today: '2026-04-20',
        nowMinutesOfDay: 9 * 60, // exactamente 9:00
      );
      expect(
        plan.any((n) => n.kind == NotificationKind.periodReminder),
        isFalse,
      );
    });

    test('fecha de aviso ya quedo en el pasado respecto a hoy: se omite', () {
      final plan = planNotifications(
        prediction: _prediction(nextPeriodEarliestDate: '2026-04-21'),
        settings: _settingsBase,
        today: '2026-04-25', // el aviso hubiera sido el 2026-04-20
        nowMinutesOfDay: 0,
      );
      expect(
        plan.any((n) => n.kind == NotificationKind.periodReminder),
        isFalse,
      );
    });

    test('fecha de aviso en el futuro: se incluye sin importar la hora actual',
        () {
      final plan = planNotifications(
        prediction: _prediction(nextPeriodEarliestDate: '2026-04-21'),
        settings: _settingsBase,
        today: '2026-04-01', // el aviso es el 2026-04-20, todavia lejos
        nowMinutesOfDay: 23 * 60 + 59,
      );
      expect(
        plan.any((n) => n.kind == NotificationKind.periodReminder),
        isTrue,
      );
    });
  });

  group('planNotifications - prediccion nula u obsoleta', () {
    test('prediccion nula: lista vacia', () {
      final plan = planNotifications(
        prediction: null,
        settings: _settingsBase,
        today: '2026-04-01',
        nowMinutesOfDay: 8 * 60,
      );
      expect(plan, isEmpty);
    });

    test('datos desactualizados (StaleDataPrediction): lista vacia', () {
      final plan = planNotifications(
        prediction: const StaleDataPrediction(
          lastPeriodStartDate: '2026-01-01',
          daysSinceLastPeriodStart: 90,
        ),
        settings: _settingsBase,
        today: '2026-04-01',
        nowMinutesOfDay: 8 * 60,
      );
      expect(plan, isEmpty);
    });
  });

  group('planNotifications - confianza baja suprime el aviso fertil', () {
    test('confianza baja: el aviso fertil NO se planifica aunque este activado',
        () {
      final plan = planNotifications(
        prediction: _prediction(confidence: PredictionConfidence.low),
        settings: _settingsBase,
        today: '2026-04-01',
        nowMinutesOfDay: 8 * 60,
      );
      expect(
        plan.any((n) => n.kind == NotificationKind.fertileWindowReminder),
        isFalse,
      );
      // el recordatorio de periodo no depende de la confianza.
      expect(
        plan.any((n) => n.kind == NotificationKind.periodReminder),
        isTrue,
      );
    });

    test('confianza media/alta: el aviso fertil si se planifica', () {
      for (final confidence in [
        PredictionConfidence.medium,
        PredictionConfidence.high,
      ]) {
        final plan = planNotifications(
          prediction: _prediction(confidence: confidence),
          settings: _settingsBase,
          today: '2026-04-01',
          nowMinutesOfDay: 8 * 60,
        );
        expect(
          plan.any((n) => n.kind == NotificationKind.fertileWindowReminder),
          isTrue,
          reason: 'confianza $confidence',
        );
      }
    });
  });

  group('planNotifications - texto discreto vs detallado', () {
    test('discreto por defecto: sin mencionar periodo ni fertilidad', () {
      final plan = planNotifications(
        prediction: _prediction(),
        settings: _settingsBase, // showDetailsEnabled: false
        today: '2026-04-01',
        nowMinutesOfDay: 8 * 60,
      );
      for (final n in plan) {
        expect(n.title, 'Aura: recordatorio');
        expect(n.body.toLowerCase(), isNot(contains('período')));
        expect(n.body.toLowerCase(), isNot(contains('fertil')));
      }
    });

    test('con mostrar detalles activado, el texto incluye "estimación"', () {
      final detailedSettings = const NotificationSettings(
        notificationsEnabled: true,
        periodReminderEnabled: true,
        fertileWindowRemindersEnabled: true,
        showDetailsEnabled: true,
        reminderHour: 9,
        reminderMinute: 0,
      );
      final plan = planNotifications(
        prediction: _prediction(),
        settings: detailedSettings,
        today: '2026-04-01',
        nowMinutesOfDay: 8 * 60,
      );
      for (final n in plan) {
        expect(n.title, isNot('Aura: recordatorio'));
        expect(n.body.toLowerCase(), contains('estimación'));
      }
    });
  });

  group('HU-05 CP3 - textos exactos del aviso fertil', () {
    PlannedNotification fertil(bool detalles,
        {PredictionConfidence confidence = PredictionConfidence.high}) {
      final plan = planNotifications(
        prediction: _prediction(confidence: confidence),
        settings: NotificationSettings(
          notificationsEnabled: true,
          periodReminderEnabled: false,
          fertileWindowRemindersEnabled: true,
          showDetailsEnabled: detalles,
          reminderHour: 9,
          reminderMinute: 0,
        ),
        today: '2026-04-01',
        nowMinutesOfDay: 8 * 60,
      );
      return plan.singleWhere(
          (n) => n.kind == NotificationKind.fertileWindowReminder);
    }

    test('con detalles: aclara que no es un metodo anticonceptivo', () {
      final n = fertil(true);
      expect(n.title, 'Ventana de mayor fertilidad (estimación)');
      expect(
          n.body,
          'Según la estimación de tu ciclo, hoy comienza tu ventana de mayor '
          'probabilidad de fertilidad. No es un método anticonceptivo.');
    });

    test('sin detalles: "Abre la app" (sin voseo)', () {
      final n = fertil(false);
      expect(n.title, 'Aura: recordatorio');
      expect(n.body, 'Abre la app para ver el detalle.');
    });

    test('recordatorio de periodo sin detalles: "Abre la app" (sin voseo)',
        () {
      final plan = planNotifications(
        prediction: _prediction(),
        settings: const NotificationSettings(
          notificationsEnabled: true,
          periodReminderEnabled: true,
          fertileWindowRemindersEnabled: false,
          showDetailsEnabled: false,
          reminderHour: 9,
          reminderMinute: 0,
        ),
        today: '2026-04-01',
        nowMinutesOfDay: 8 * 60,
      );
      final n = plan
          .singleWhere((n) => n.kind == NotificationKind.periodReminder);
      expect(n.title, 'Aura: recordatorio');
      expect(n.body, 'Abre la app para ver el detalle.');
    });

    test('con confianza baja sigue sin planificarse, con y sin detalles', () {
      for (final detalles in [true, false]) {
        final plan = planNotifications(
          prediction: _prediction(confidence: PredictionConfidence.low),
          settings: NotificationSettings(
            notificationsEnabled: true,
            periodReminderEnabled: false,
            fertileWindowRemindersEnabled: true,
            showDetailsEnabled: detalles,
            reminderHour: 9,
            reminderMinute: 0,
          ),
          today: '2026-04-01',
          nowMinutesOfDay: 8 * 60,
        );
        expect(plan, isEmpty, reason: 'detalles: $detalles');
      }
    });
  });

  test('ids estables por tipo (reprogramar reemplaza, no acumula)', () {
    final plan = planNotifications(
      prediction: _prediction(),
      settings: _settingsBase,
      today: '2026-04-01',
      nowMinutesOfDay: 8 * 60,
    );
    final period =
        plan.firstWhere((n) => n.kind == NotificationKind.periodReminder);
    final fertile = plan
        .firstWhere((n) => n.kind == NotificationKind.fertileWindowReminder);
    expect(period.id, 100);
    expect(fertile.id, 101);
  });

  // HU-05, CP5b: "Mostrar ovulacion y ventana fertil" (H5-3, relacion A).
  group('HU-05 CP5b - interruptor showFertileWindow', () {
    List<PlannedNotification> plan(
      bool mostrar, {
      bool fertil = true,
      bool periodo = true,
      bool detalles = false,
      PredictionConfidence confidence = PredictionConfidence.high,
    }) =>
        planNotifications(
          prediction: _prediction(confidence: confidence),
          settings: NotificationSettings(
            notificationsEnabled: true,
            periodReminderEnabled: periodo,
            fertileWindowRemindersEnabled: fertil,
            showDetailsEnabled: detalles,
            reminderHour: 9,
            reminderMinute: 0,
            showFertileWindow: mostrar,
          ),
          today: '2026-04-01',
          nowMinutesOfDay: 8 * 60,
        );

    bool tieneFertil(List<PlannedNotification> p) =>
        p.any((n) => n.kind == NotificationKind.fertileWindowReminder);

    test('apagado + confianza alta + recordatorio fertil activo: no '
        'planifica el fertil (con y sin detalles)', () {
      for (final detalles in [true, false]) {
        expect(tieneFertil(plan(false, detalles: detalles)), isFalse,
            reason: 'detalles: $detalles');
      }
    });

    test('encendido: igual que hoy (alta y media planifican, baja no)', () {
      expect(tieneFertil(plan(true)), isTrue);
      expect(
          tieneFertil(plan(true, confidence: PredictionConfidence.medium)),
          isTrue);
      expect(tieneFertil(plan(true, confidence: PredictionConfidence.low)),
          isFalse);
      expect(tieneFertil(plan(true, fertil: false)), isFalse);
    });

    test('el recordatorio de periodo no cambia con el interruptor', () {
      PlannedNotification periodo(bool mostrar) => plan(mostrar)
          .singleWhere((n) => n.kind == NotificationKind.periodReminder);
      final on = periodo(true);
      final off = periodo(false);
      expect((off.id, off.date, off.hour, off.minute, off.title, off.body),
          (on.id, on.date, on.hour, on.minute, on.title, on.body));
      expect(plan(false, periodo: false), isEmpty);
    });
  });

  // HU-05, CP5d-1: con el periodo atrasado Inicio ya no muestra la
  // ventana. El planificador no cambia: la ventana empieza antes del
  // extremo tardio del rango, asi que ya paso (_isStillPending).
  group('HU-05 CP5d-1 - periodo atrasado', () {
    test('confianza alta, interruptor y recordatorio fertil encendidos: no '
        'planifica el fertil (su fecha ya paso)', () {
      // 4 ciclos de 28; ultimo inicio 26/03; rango 21/04 - 25/04; el
      // 26/04 es 1 dia de atraso. Ventana desde el 04/04.
      final prediction = predictCycle(
        cycles: [
          for (final (start, length) in [
            ('2025-12-04', 28),
            ('2026-01-01', 28),
            ('2026-01-29', 28),
            ('2026-02-26', 28),
            ('2026-03-26', null),
          ])
            CycleSummary(
              startDate: start,
              periodLengthDays: 5,
              cycleLengthDays: length,
            ),
        ],
        today: '2026-04-26',
      ) as ActivePrediction;
      expect(prediction.isPeriodLate, isTrue);
      expect(prediction.confidence, PredictionConfidence.high);
      expect(prediction.fertileWindowStartDate, '2026-04-04');

      for (final detalles in [true, false]) {
        final plan = planNotifications(
          prediction: prediction,
          settings: NotificationSettings(
            notificationsEnabled: true,
            periodReminderEnabled: true,
            fertileWindowRemindersEnabled: true,
            showDetailsEnabled: detalles,
            reminderHour: 9,
            reminderMinute: 0,
            showFertileWindow: true,
          ),
          today: '2026-04-26',
          nowMinutesOfDay: 8 * 60,
        );
        expect(
            plan.any((n) => n.kind == NotificationKind.fertileWindowReminder),
            isFalse,
            reason: 'detalles: $detalles');
      }
    });
  });
}
