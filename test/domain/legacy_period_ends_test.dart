import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aura/data/models/day_enums.dart';
import 'package:aura/domain/backup_codec.dart';
import 'package:aura/domain/legacy_period_ends.dart';

/// Regla D-2 (docs/ESPECIFICACION_v1.1.md, seccion 10) y casos borde de la
/// tabla 2.3 de la Etapa A de la migracion v4. "Hoy" siempre fijo.
const _today = '2026-10-07';

List<LegacyPeriodAssessment> _assess(
  List<String> periodDays, {
  List<String> explicitNonPeriodDays = const [],
  Map<String, PeriodEndSource> periodEnds = const {},
  String today = _today,
}) =>
    assessLegacyPeriods(
      periodDays: periodDays,
      explicitNonPeriodDays: explicitNonPeriodDays,
      periodEnds: periodEnds,
      today: today,
    );

List<String> _infer(
  List<String> periodDays, {
  List<String> explicitNonPeriodDays = const [],
  Map<String, PeriodEndSource> periodEnds = const {},
  String today = _today,
}) =>
    inferLegacyPeriodEnds(
      periodDays: periodDays,
      explicitNonPeriodDays: explicitNonPeriodDays,
      periodEnds: periodEnds,
      today: today,
    );

void main() {
  group('casos borde (tabla 2.3 de la Etapa A)', () {
    test('base vacia: no hay periodos ni cierres', () {
      expect(_assess([]), isEmpty);
      expect(_infer([]), isEmpty);
    });

    test(
        'dia con sintomas sin sangrado dentro del periodo (1, 2, sintomas el '
        '3, 4): cuenta como hueco de 1 dia y cierra en el 4', () {
      final result = _assess(['2026-08-01', '2026-08-02', '2026-08-04']);
      expect(result.single.outcome, LegacyPeriodOutcome.inferred);
      expect(result.single.lastDate, '2026-08-04');
      expect(result.single.maxInternalGapDays, 1);
      expect(_infer(['2026-08-01', '2026-08-02', '2026-08-04']),
          ['2026-08-04']);
    });

    test('dia suelto antiguo (1 solo dia marcado): abierto', () {
      final result = _assess(['2026-06-01', '2026-07-01', '2026-07-02']);
      expect(result.first.markedDays, 1);
      expect(result.first.outcome, LegacyPeriodOutcome.singleDay);
      expect(_infer(['2026-06-01', '2026-07-01', '2026-07-02']),
          ['2026-07-02']);
    });

    test('hueco de 1 dia (1, 2, 4, 5): cerrado, duracion 5', () {
      final result =
          _assess(['2026-08-01', '2026-08-02', '2026-08-04', '2026-08-05']);
      expect(result.single.outcome, LegacyPeriodOutcome.inferred);
      expect(result.single.periodLengthDays, 5);
      expect(result.single.markedDays, 4);
      expect(result.single.maxInternalGapDays, 1);
    });

    test('hueco de 2 dias (1, 2, 5, 6): abierto', () {
      final result =
          _assess(['2026-08-01', '2026-08-02', '2026-08-05', '2026-08-06']);
      expect(result.single.outcome, LegacyPeriodOutcome.gapTooLarge);
      expect(result.single.maxInternalGapDays, 2);
      expect(
          _infer(['2026-08-01', '2026-08-02', '2026-08-05', '2026-08-06']),
          isEmpty);
    });

    test('hueco de 3 a 7 dias (1 y 7): abierto', () {
      final result = _assess(['2026-08-01', '2026-08-07']);
      expect(result.single.outcome, LegacyPeriodOutcome.gapTooLarge);
      expect(result.single.maxInternalGapDays, 5);
    });

    test('hueco de 8 o mas dias: dos periodos que se evaluan por separado',
        () {
      final result = _assess([
        '2026-08-01', '2026-08-02', // primer periodo
        '2026-08-11', '2026-08-12', // 9 dias despues: otro periodo
        '2026-08-15', // 3 dias despues: hueco de 2 dentro del segundo
      ]);
      expect(result, hasLength(2));
      expect(result[0].outcome, LegacyPeriodOutcome.inferred);
      expect(result[0].lastDate, '2026-08-02');
      expect(result[1].outcome, LegacyPeriodOutcome.gapTooLarge);
    });

    test(
        'un "no" explicito dentro del periodo (1, 2, "no" el 3, 4, 5): no lo '
        'cierra por la regla del "no"; D-2 lo cierra en el 5', () {
      final result = _assess(
        ['2026-08-01', '2026-08-02', '2026-08-04', '2026-08-05'],
        explicitNonPeriodDays: ['2026-08-03'],
      );
      expect(result.single.outcome, LegacyPeriodOutcome.inferred);
      expect(result.single.lastDate, '2026-08-05');
    });

    test('periodo ya cerrado por un "no" explicito: no se escribe nada', () {
      final result = _assess(
        ['2026-08-28', '2026-08-29', '2026-08-30', '2026-08-31'],
        explicitNonPeriodDays: ['2026-09-01'],
      );
      expect(result.single.outcome, LegacyPeriodOutcome.closedByExplicitNo);
      expect(result.single.isClosed, isTrue);
      expect(
        _infer(
          ['2026-08-28', '2026-08-29', '2026-08-30', '2026-08-31'],
          explicitNonPeriodDays: ['2026-09-01'],
        ),
        isEmpty,
      );
    });

    test('periodo muy largo (20 dias seguidos): cerrado (D-2 no pone tope)',
        () {
      final days = [
        for (var d = 1; d <= 20; d++)
          '2026-07-${d.toString().padLeft(2, '0')}',
      ];
      final result = _assess(days);
      expect(result.single.periodLengthDays, 20);
      expect(result.single.outcome, LegacyPeriodOutcome.inferred);
      expect(_infer(days), ['2026-07-20']);
    });

    test('periodo en curso hoy (el mas reciente termina hoy): abierto', () {
      final result = _assess(['2026-10-05', '2026-10-06', _today]);
      expect(result.single.outcome, LegacyPeriodOutcome.mayContinue);
    });

    test(
        'el mas reciente termino hace exactamente 7 dias: sigue abierto '
        '(limite)', () {
      final result = _assess(['2026-09-29', '2026-09-30']); // 7 dias antes
      expect(result.single.outcome, LegacyPeriodOutcome.mayContinue);
    });

    test('el mas reciente termino hace mas de 7 dias, con 2 o mas dias: '
        'cerrado', () {
      final result = _assess(['2026-09-28', '2026-09-29']); // 8 dias antes
      expect(result.single.outcome, LegacyPeriodOutcome.inferred);
      expect(_infer(['2026-09-28', '2026-09-29']), ['2026-09-29']);
    });

    test('el mas reciente es de 1 solo dia, de hace mas de 7 dias: abierto',
        () {
      final result = _assess(['2026-09-01']);
      expect(result.single.outcome, LegacyPeriodOutcome.singleDay);
    });

    test(
        'dias con fecha futura (formulario v1.0): el periodo que los tiene es '
        'el mas reciente y queda abierto', () {
      final result = _assess([
        '2026-08-01', '2026-08-02', // antiguo, se cierra
        '2027-03-10', '2027-03-11', // futuro
      ]);
      expect(result, hasLength(2));
      expect(result[0].outcome, LegacyPeriodOutcome.inferred);
      expect(result[1].outcome, LegacyPeriodOutcome.mayContinue);
    });

    test(
        'un dia con "si" explicito cuenta como dia marcado normal (llega en '
        'periodDays, no como "no")', () {
      // 2026-08-02 tiene is_period_day = 1 y period_day_explicit = 1.
      final result = _assess(['2026-08-01', '2026-08-02']);
      expect(result.single.markedDays, 2);
      expect(result.single.outcome, LegacyPeriodOutcome.inferred);
    });

    test(
        'ultimo dia que ya tiene period_end (base pasada por una app v3, H-4): '
        'no se vuelve a escribir', () {
      final result = _assess(
        ['2026-08-01', '2026-08-02'],
        periodEnds: {'2026-08-02': PeriodEndSource.inferred},
      );
      expect(result.single.outcome, LegacyPeriodOutcome.alreadyHasEnd);
      expect(result.single.isClosed, isTrue);
      expect(
        _infer(['2026-08-01', '2026-08-02'],
            periodEnds: {'2026-08-02': PeriodEndSource.declared}),
        isEmpty,
      );
    });

    test(
        'period_end en un dia interior no cuenta (R-4): el periodo se evalua '
        'y se cierra en su ultimo dia', () {
      final result = _assess(
        ['2026-08-01', '2026-08-02', '2026-08-03'],
        periodEnds: {'2026-08-02': PeriodEndSource.declared},
      );
      expect(result.single.outcome, LegacyPeriodOutcome.inferred);
      expect(result.single.lastDate, '2026-08-03');
    });

    test('dias repetidos y desordenados dan el mismo resultado', () {
      expect(
        _infer(['2026-08-05', '2026-08-01', '2026-08-02', '2026-08-01',
            '2026-08-04']),
        ['2026-08-05'],
      );
    });
  });

  group('casos de la regla D-2 (tabla de la seccion 10)', () {
    test('1 dia marcado (ciclo completo): abierto, no entra', () {
      final result = _assess(['2026-01-01', '2026-01-29', '2026-01-30']);
      expect(result.first.outcome, LegacyPeriodOutcome.singleDay);
      expect(result.first.isClosed, isFalse);
    });

    test('2 o mas dias seguidos (01-01 a 01-05): cerrado, duracion 5', () {
      final result = _assess([
        '2026-01-01',
        '2026-01-02',
        '2026-01-03',
        '2026-01-04',
        '2026-01-05',
      ]);
      expect(result.single.outcome, LegacyPeriodOutcome.inferred);
      expect(result.single.periodLengthDays, 5);
      expect(result.single.lastDate, '2026-01-05');
    });

    test('rango con 1 dia sin marcar (1, 2, 4, 5): cerrado, duracion 5', () {
      final result =
          _assess(['2026-01-01', '2026-01-02', '2026-01-04', '2026-01-05']);
      expect(result.single.outcome, LegacyPeriodOutcome.inferred);
      expect(result.single.periodLengthDays, 5);
    });

    test('rango con hueco de mas de 1 dia (dias 1 y 7): abierto', () {
      final result = _assess(['2026-01-01', '2026-01-07']);
      expect(result.single.outcome, LegacyPeriodOutcome.gapTooLarge);
      expect(result.single.isClosed, isFalse);
    });

    test('periodo que ya tiene un "no" explicito: ya cerrado, no se escribe',
        () {
      final result = _assess(
        ['2026-01-01', '2026-01-02', '2026-01-03'],
        explicitNonPeriodDays: ['2026-01-04'],
      );
      expect(result.single.outcome, LegacyPeriodOutcome.closedByExplicitNo);
      expect(
        _infer(['2026-01-01', '2026-01-02', '2026-01-03'],
            explicitNonPeriodDays: ['2026-01-04']),
        isEmpty,
      );
    });

    test('periodo mas reciente que termino hace 7 dias o menos: abierto', () {
      final result = _assess(['2026-10-01', '2026-10-02', '2026-10-03']);
      expect(result.single.outcome, LegacyPeriodOutcome.mayContinue);
    });

    test(
        'periodo mas reciente que termino hace mas de 7 dias, con 2 o mas '
        'dias: cerrado', () {
      final result = _assess(['2026-09-20', '2026-09-21', '2026-09-22']);
      expect(result.single.outcome, LegacyPeriodOutcome.inferred);
      expect(result.single.periodLengthDays, 3);
    });

    test('periodo mas reciente de 1 solo dia, de hace mas de 7 dias: abierto',
        () {
      final result = _assess(['2026-09-20']);
      expect(result.single.outcome, LegacyPeriodOutcome.singleDay);
    });
  });

  group('varios periodos mezclados', () {
    test(
        'cerrado por "no", cerrado por D-2, abierto por hueco, abierto de 1 '
        'dia y en curso: solo se infiere el que corresponde', () {
      final result = _assess(
        [
          '2026-05-01', '2026-05-02', '2026-05-03', // "no" el 05-04
          '2026-05-29', '2026-05-30', '2026-05-31', // D-2
          '2026-06-26', '2026-06-30', // hueco de 3
          '2026-07-24', // 1 dia
          '2026-08-21', // 1 dia
          '2026-10-02', '2026-10-03', // en curso
        ],
        explicitNonPeriodDays: ['2026-05-04'],
      );
      expect(result.map((r) => r.outcome), [
        LegacyPeriodOutcome.closedByExplicitNo,
        LegacyPeriodOutcome.inferred,
        LegacyPeriodOutcome.gapTooLarge,
        LegacyPeriodOutcome.singleDay,
        LegacyPeriodOutcome.singleDay,
        LegacyPeriodOutcome.mayContinue,
      ]);
      expect(
        _infer(
          [
            '2026-05-01', '2026-05-02', '2026-05-03',
            '2026-05-29', '2026-05-30', '2026-05-31',
            '2026-06-26', '2026-06-30',
            '2026-07-24',
            '2026-08-21',
            '2026-10-02', '2026-10-03',
          ],
          explicitNonPeriodDays: ['2026-05-04'],
        ),
        ['2026-05-31'],
      );
    });
  });

  test(
      'fixture backup_v3.json: no ejercita D-2, no se infiere ningun cierre '
      '(H-5)', () {
    final result = decodeBackup(
        File('test/fixtures/backup_v3.json').readAsBytesSync());
    final data = (result as BackupParseSuccess).data;
    final periodDays = [
      for (final d in data.days) if (d.isPeriodDay) d.date,
    ];
    final explicitNo = [
      for (final d in data.days)
        if (!d.isPeriodDay && d.periodDayExplicit) d.date,
    ];

    final assessed = _assess(periodDays,
        explicitNonPeriodDays: explicitNo, today: '2026-10-04');
    expect(assessed.map((r) => r.outcome), [
      LegacyPeriodOutcome.closedByExplicitNo, // 08-28 a 08-31, "no" el 09-01
      LegacyPeriodOutcome.singleDay, // 09-25
    ]);
    expect(
      _infer(periodDays, explicitNonPeriodDays: explicitNo, today: '2026-10-04'),
      isEmpty,
    );
  });
}
