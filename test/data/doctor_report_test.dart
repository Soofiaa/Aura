import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:aura/data/database/app_database.dart' show PregnancyRow;
import 'package:aura/data/doctor_report.dart';
import 'package:aura/data/models/day_enums.dart';
import 'package:aura/data/repositories/cycle_repository.dart';
import 'package:aura/domain/contraceptive.dart';
import 'package:aura/domain/cycle_deriver.dart';

pw.Font _font(String name) => pw.Font.ttf(
    File('assets/fonts/$name.ttf').readAsBytesSync().buffer.asByteData());

CycleSummary _c(String start, int? length) => CycleSummary(
    startDate: start, periodLengthDays: 5, cycleLengthDays: length);

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  Future<String> build(PredictionInputs inputs,
          {List<PregnancyRow> pregnancies = const []}) async =>
      String.fromCharCodes((await buildDoctorReport(
        inputs: inputs,
        symptoms: {Symptom.values.first: 4},
        moods: {Mood.feliz: 3, Mood.cansada: 1},
        averageFlow: 2,
        pregnancies: pregnancies,
        contraceptive: const ContraceptiveReminder(
            method: ContraceptiveMethod.pill, hour: 21, minute: 0),
        today: '2026-10-27',
        regular: _font('Lato-Regular'),
        bold: _font('Lato-Bold'),
      ))
          .take(5));

  test('con ciclos, sin datos y en embarazo arma un PDF', () async {
    final ciclos = [
      _c('2026-07-01', 28),
      _c('2026-07-29', 30),
      _c('2026-08-28', 27),
      _c('2026-09-24', null),
    ];
    expect(
        await build(PredictionInputs(
            cycles: ciclos, typicalPeriodLengthDays: 5)),
        '%PDF-');
    expect(
        await build(const PredictionInputs(
            cycles: [], typicalPeriodLengthDays: 5)),
        '%PDF-');
    expect(
        await build(
            PredictionInputs(
                cycles: ciclos,
                typicalPeriodLengthDays: 5,
                pregnancies: [
                  (start: '2025-01-01', end: '2025-03-01'),
                  (start: '2026-09-24', end: null),
                ]),
            pregnancies: const [
              PregnancyRow(
                  startDate: '2025-01-01',
                  endDate: '2025-03-01',
                  outcome: PregnancyOutcome.perdida),
              PregnancyRow(startDate: '2026-09-24'),
            ]),
        '%PDF-');
  });
}
