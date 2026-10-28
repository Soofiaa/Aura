import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/contraceptive.dart';
import '../domain/cycle_deriver.dart' show CycleSummary;
import '../domain/cycle_predictor.dart';
import '../domain/symptom_ranking.dart';
import '../utils/aura_localizations.dart';
import '../utils/date_labels.dart';
import '../utils/day_key.dart';
import '../utils/period_end_messages.dart' show dayMonthLabel;
import 'database/app_database.dart' show PregnancyRow;
import 'device_settings_store.dart';
import 'models/day_enums.dart';
import 'repositories/cycle_repository.dart';

/// Carpeta del directorio temporal con el PDF a compartir; se limpia al
/// abrir la app (BackupService.temporaryDirNames).
const doctorReportDirName = 'resumen_pdf';

const _primary = PdfColor.fromInt(0xFFA8D8EA);
const _primarySoft = PdfColor.fromInt(0xFFEAF6FA);
const _accent = PdfColor.fromInt(0xFFE76085);
const _accentSoft = PdfColor.fromInt(0xFFFCE8EE);
const _text = PdfColor.fromInt(0xFF333333);
const _muted = PdfColor.fromInt(0xFF717171);
const _line = PdfColor.fromInt(0xFFDDE3E6);

/// Junta los datos, arma el PDF y lo deja en el directorio temporal.
Future<File> writeDoctorReport() async {
  final repo = cycleRepository;
  final bytes = await buildDoctorReport(
    inputs: await repo.getPredictionInputs(),
    symptoms: await repo.getSymptomFrequency(),
    moods: await repo.getMoodFrequency(),
    averageFlow: await repo.getAverageFlow(),
    pregnancies: await repo.getPregnancies(),
    contraceptive: (await deviceSettingsStore.read()).anticonceptivo,
    today: DayKey.today(),
    regular: pw.Font.ttf(await rootBundle.load('assets/fonts/Lato-Regular.ttf')),
    bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Lato-Bold.ttf')),
  );
  final dir = Directory(
      p.join((await getTemporaryDirectory()).path, doctorReportDirName));
  await dir.create(recursive: true);
  final file = File(p.join(dir.path,
      '${tr('resumen_aura', 'aura_summary')}_${DayKey.today()}.pdf'));
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

String _days(int n) => n == 1 ? tr('1 día', '1 day') : tr('$n días', '$n days');

String _flowLabel(double avg) => avg == 0
    ? tr('Sin datos', 'No data')
    : avg < 1.5
        ? FlowIntensity.ligero.label
        : avg < 2.5
            ? FlowIntensity.moderado.label
            : FlowIntensity.abundante.label;

String _outcomeLabel(PregnancyOutcome o) => switch (o) {
      PregnancyOutcome.nacimiento => tr('Nacimiento', 'Birth'),
      PregnancyOutcome.perdida => tr('Pérdida', 'Loss'),
      PregnancyOutcome.sinEspecificar => tr('No especificado', 'Not specified'),
    };

/// El resumen para la consulta, en A4. Funcion pura salvo por las fuentes:
/// las de serie del paquete pdf no tienen tildes fuera de Latin-1.
Future<Uint8List> buildDoctorReport({
  required PredictionInputs inputs,
  required Map<Symptom, int> symptoms,
  required Map<Mood, int> moods,
  required double averageFlow,
  required List<PregnancyRow> pregnancies,
  required ContraceptiveReminder? contraceptive,
  required String today,
  required pw.Font regular,
  required pw.Font bold,
}) {
  final config = inputs.config;
  final cycles = [...inputs.cycles]
    ..sort((a, b) => DayKey.compare(a.startDate, b.startDate));
  final cycle = estimateCycleLength(cycles: cycles, config: config);
  final period = estimatePeriodLength(cycles: cycles, config: config);
  final regularity = cycleRegularity(cycle, config: config);
  final prediction = cycles.isEmpty || inputs.predictionsPaused
      ? null
      : predictCycle(cycles: cycles, today: today, config: config);
  final active = pregnancies.isNotEmpty && pregnancies.last.endDate == null
      ? pregnancies.last
      : null;
  final ended = [for (final p in pregnancies) if (p.endDate != null) p];
  final topSymptoms = rankSymptoms(symptoms).take(8).toList();
  final moodTotal = moods.values.fold<int>(0, (a, b) => a + b);
  final recent =
      cycles.length > 12 ? cycles.sublist(cycles.length - 12) : cycles;
  // Ciclo que abarca un embarazo: su duracion no es la de un ciclo.
  bool embarazo(CycleSummary c) =>
      c.cycleLengthDays != null &&
      cycleOverlapsPregnancy(c, config.pregnancies);
  final chart = [
    for (final c in recent)
      if (c.cycleLengthDays != null && !embarazo(c)) c,
  ];

  final small = pw.TextStyle(fontSize: 9, color: _muted);

  // Inseparable: un titulo nunca queda solo al pie de una pagina. Cada
  // seccion cabe en una (como mucho 12 filas).
  pw.Widget section(String title, List<pw.Widget> children) =>
      pw.Inseparable(child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 18),
          pw.Row(children: [
            pw.Container(width: 4, height: 14, color: _accent),
            pw.SizedBox(width: 6),
            pw.Text(title,
                style: pw.TextStyle(
                    font: bold, fontSize: 13, color: _text)),
          ]),
          pw.SizedBox(height: 8),
          ...children,
        ],
      ));

  pw.Widget card(String label, String value, {String? note}) => pw.Container(
        width: 167,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: _primarySoft,
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: small),
            pw.SizedBox(height: 3),
            pw.Text(value,
                style: pw.TextStyle(font: bold, fontSize: 14, color: _text)),
            if (note != null) ...[
              pw.SizedBox(height: 2),
              pw.Text(note, style: small),
            ],
          ],
        ),
      );

  pw.Widget table(List<String> headers, List<List<String>> rows) =>
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: rows,
        border: const pw.TableBorder(
            horizontalInside: pw.BorderSide(color: _line, width: 0.5)),
        headerDecoration: const pw.BoxDecoration(color: _primary),
        headerStyle: pw.TextStyle(font: bold, fontSize: 10, color: _text),
        headerAlignment: pw.Alignment.centerLeft,
        cellStyle: const pw.TextStyle(fontSize: 10, color: _text),
        oddRowDecoration: const pw.BoxDecoration(color: _primarySoft),
        cellPadding:
            const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      );

  final cards = <pw.Widget>[
    if (cycle.days != null)
      card(tr('Duración típica del ciclo', 'Typical cycle length'),
          _days(cycle.days!),
          note: cycle.shortestDays == cycle.longestDays
              ? null
              : tr('Entre ${cycle.shortestDays} y ${cycle.longestDays} días',
                  'Between ${cycle.shortestDays} and ${cycle.longestDays} days')),
    if (regularity != null)
      card(tr('Regularidad', 'Regularity'), regularity.label),
    card(tr('Duración típica del período', 'Typical period length'),
        _days(period.days),
        note: period.source == PeriodLengthSource.ownPeriods
            ? tr('Según sus períodos', 'Based on logged periods')
            : tr('Según su ajuste', 'Based on the setting')),
    if (cycles.isNotEmpty)
      card(tr('Último período', 'Last period'),
          fullDateLabel(cycles.last.startDate)),
    if (active == null)
      card(
          tr('Próximo período estimado', 'Next estimated period'),
          inputs.predictionsPaused
              ? tr('En pausa', 'Paused')
              : prediction is! ActivePrediction
                  ? tr('Sin datos recientes', 'No recent data')
                  : '${dayMonthLabel(prediction.nextPeriodEarliestDate)} – '
                      '${dayMonthLabel(prediction.nextPeriodLatestDate)}'),
    card(tr('Ciclos considerados', 'Cycles considered'),
        '${cycle.consideredCount}',
        note: cycle.excludedCount == 0
            ? null
            : tr('${cycle.excludedCount} fuera de rango',
                '${cycle.excludedCount} out of range')),
  ];

  final maxLen = chart.isEmpty
      ? 1
      : chart.map((c) => c.cycleLengthDays!).reduce((a, b) => a > b ? a : b);
  final monthFormat = DateFormat(auraIsEnglish ? 'MMM d' : 'd MMM', auraLanguage);

  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
    title: tr('Resumen del ciclo', 'Cycle summary'),
    creator: 'Aura',
  );
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
    footer: (context) => pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _line, width: 0.5))),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(child: pw.Text(
              tr('Datos registrados por la paciente en Aura. Las estimaciones '
                  'no reemplazan una evaluación médica.',
                  'Data logged by the patient in Aura. Estimates do not '
                  'replace a medical evaluation.'),
              style: small)),
          pw.SizedBox(width: 12),
          pw.Text('${context.pageNumber} / ${context.pagesCount}',
              style: small),
        ],
      ),
    ),
    build: (context) => [
      pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: pw.BoxDecoration(
          gradient: const pw.LinearGradient(colors: [_primary, _accentSoft]),
          borderRadius: pw.BorderRadius.circular(10),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(tr('Resumen del ciclo', 'Cycle summary'),
                    style:
                        pw.TextStyle(font: bold, fontSize: 22, color: _text)),
                pw.SizedBox(height: 2),
                pw.Text(tr('Para la consulta médica', 'For the medical visit'),
                    style: const pw.TextStyle(fontSize: 11, color: _text)),
              ],
            ),
            pw.Text(tr('Generado el ${fullDateLabel(today)}',
                    'Generated on ${fullDateLabel(today)}'),
                style: const pw.TextStyle(fontSize: 10, color: _text)),
          ],
        ),
      ),
      if (active != null)
        section(tr('Embarazo en curso', 'Current pregnancy'), [
          pw.Wrap(spacing: 10, runSpacing: 10, children: [
            card(
                tr('Edad gestacional', 'Gestational age'),
                () {
                  final d = DayKey.diffInDays(active.startDate, today);
                  return tr('${d ~/ 7} sem. y ${d % 7} d',
                      '${d ~/ 7} wk ${d % 7} d');
                }()),
            card(tr('FUR', 'LMP'), fullDateLabel(active.startDate)),
            card(tr('Fecha probable de parto', 'Estimated due date'),
                fullDateLabel(DayKey.addDays(active.startDate, 280))),
          ]),
        ]),
      section(tr('Ciclo', 'Cycle'), [
        if (cycles.isEmpty)
          pw.Text(tr('Aún no hay períodos registrados.',
              'No periods logged yet.'))
        else
          pw.Wrap(spacing: 10, runSpacing: 10, children: cards),
      ]),
      if (chart.length >= 2)
        section(tr('Duración de los últimos ciclos', 'Recent cycle lengths'), [
          pw.Container(
            height: 130,
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                for (final c in chart)
                  pw.Expanded(
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 4),
                      child: pw.Column(
                        mainAxisAlignment: pw.MainAxisAlignment.end,
                        children: [
                          pw.Text('${c.cycleLengthDays}',
                              style: pw.TextStyle(font: bold, fontSize: 9)),
                          pw.SizedBox(height: 2),
                          pw.Container(
                            width: 26,
                            height: 90 * c.cycleLengthDays! / maxLen,
                            decoration: pw.BoxDecoration(
                              color: _accent,
                              borderRadius: const pw.BorderRadius.vertical(
                                  top: pw.Radius.circular(3)),
                            ),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                              monthFormat
                                  .format(DateTime.parse(c.startDate)),
                              style: small),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      if (cycles.isNotEmpty)
        section(tr('Historial de períodos', 'Period history'), [
          table([
            tr('Inicio', 'Start'),
            tr('Duración del período', 'Period length'),
            tr('Duración del ciclo', 'Cycle length'),
          ], [
            for (final c in recent.reversed)
              [
                fullDateLabel(c.startDate),
                _days(c.periodLengthDays),
                c.cycleLengthDays == null
                    ? tr('En curso', 'Ongoing')
                    : embarazo(c)
                        ? tr('Embarazo', 'Pregnancy')
                        : _days(c.cycleLengthDays!),
              ],
          ]),
        ]),
      section(tr('Síntomas y estado de ánimo', 'Symptoms and mood'), [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 250,
              child: topSymptoms.isEmpty
                  ? pw.Text(tr('Sin síntomas registrados.', 'No symptoms logged.'),
                      style: small)
                  : table([
                      tr('Síntoma', 'Symptom'),
                      tr('Días', 'Days'),
                    ], [
                      for (final s in topSymptoms) [s.key.label, '${s.value}'],
                    ]),
            ),
            pw.SizedBox(width: 16),
            pw.SizedBox(
              width: 250,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  card(tr('Flujo promedio', 'Average flow'),
                      _flowLabel(averageFlow)),
                  pw.SizedBox(height: 10),
                  if (moodTotal == 0)
                    pw.Text(tr('Sin estados de ánimo registrados.',
                        'No moods logged.'), style: small)
                  else
                    for (final m in moods.entries.toList()
                      ..sort((a, b) => b.value.compareTo(a.value)))
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 5),
                        child: pw.Row(children: [
                          pw.SizedBox(
                              width: 70,
                              child: pw.Text(m.key.label,
                                  style: const pw.TextStyle(fontSize: 10))),
                          pw.Expanded(
                            child: pw.Stack(children: [
                              pw.Container(height: 8, color: _accentSoft),
                              pw.Container(
                                height: 8,
                                width: 140 * m.value / moodTotal,
                                color: _accent,
                              ),
                            ]),
                          ),
                          pw.SizedBox(
                              width: 34,
                              child: pw.Text(
                                  '${(100 * m.value / moodTotal).round()} %',
                                  textAlign: pw.TextAlign.right,
                                  style: const pw.TextStyle(fontSize: 10))),
                        ]),
                      ),
                ],
              ),
            ),
          ],
        ),
      ]),
      if (contraceptive != null)
        section(tr('Anticonceptivo', 'Birth control'), [
          pw.Text(contraceptive.method.label,
              style: const pw.TextStyle(fontSize: 11)),
        ]),
      if (ended.isNotEmpty)
        section(tr('Embarazos anteriores', 'Previous pregnancies'), [
          table([
            tr('FUR', 'LMP'),
            tr('Fin', 'End'),
            tr('Resultado', 'Outcome'),
          ], [
            for (final p in ended.reversed)
              [
                fullDateLabel(p.startDate),
                fullDateLabel(p.endDate!),
                _outcomeLabel(p.outcome!),
              ],
          ]),
        ]),
    ],
  ));
  return doc.save();
}
