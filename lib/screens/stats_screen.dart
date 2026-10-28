import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../data/backup/backup_file_gateway.dart';
import '../data/doctor_report.dart';
import '../data/models/day_enums.dart';
import '../data/repositories/cycle_repository.dart';
import '../domain/cycle_deriver.dart' show CycleSummary;
import '../domain/cycle_predictor.dart';
import '../domain/symptom_ranking.dart';
import '../utils/app_snackbar.dart';
import '../utils/aura_localizations.dart';
import '../utils/colors.dart';
import '../utils/day_key.dart';
import '../utils/period_end_messages.dart' show dayMonthLabel;

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  // Stream en vez de una carga unica en initState: se recalcula solo
  // cuando cambia algo en daily_logs, sin importar si volvimos a esta
  // pestana despues de registrar un dia o marcar el calendario.
  late final Stream<StatsSnapshot> _statsStream = cycleRepository.watchStats();

  // "Tus ciclos" usa las mismas entradas que la prediccion de Inicio (y
  // se recalcula igual, con cada cambio en los dias o los ajustes).
  late final Stream<PredictionInputs> _inputsStream =
      cycleRepository.watchPredictionInputs();

  bool _creandoPdf = false;

  Future<void> _compartirResumen() async {
    setState(() => _creandoPdf = true);
    try {
      await backupFileGateway.shareFile(await writeDoctorReport(),
          mimeType: 'application/pdf');
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context,
            tr('No se pudo crear el resumen.', 'Could not create the summary.'));
      }
    } finally {
      if (mounted) setState(() => _creandoPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr("Estadísticas", "Stats")),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: tr('Resumen en PDF para tu consulta',
                'PDF summary for your doctor'),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _creandoPdf ? null : _compartirResumen,
          ),
        ],
      ),
      body: StreamBuilder<StatsSnapshot>(
        stream: _statsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  tr("No se pudieron cargar las estadísticas.",
                      "Couldn't load your stats."),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final stats = snapshot.data!;
          // Ya filtrados (conteo > 0) y ordenados de mayor a menor.
          final sintomas = rankSymptoms(stats.symptomFrequency);
          final promedioFlujo = stats.averageFlow;

          if (!stats.hasAnyLog) {
            return Center(
              child: Text(
                tr("Aún no hay registros guardados", "No entries saved yet"),
                style: const TextStyle(fontSize: 18),
              ),
            );
          }

          final animos = stats.moodFrequency.entries
              .where((e) => e.value > 0)
              .toList()
            ..sort((a, b) {
              final c = b.value.compareTo(a.value);
              return c != 0 ? c : a.key.label.compareTo(b.key.label);
            });
          final totalAnimos = animos.fold<int>(0, (a, e) => a + e.value);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                StreamBuilder<PredictionInputs>(
                  stream: _inputsStream,
                  builder: (context, inputs) {
                    if (!inputs.hasData || inputs.data!.cycles.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _CyclesSection(inputs: inputs.data!),
                    );
                  },
                ),
                _StatCard(
                  label: tr("Promedio de flujo", "Average flow"),
                  value: promedioFlujo == 0
                      ? tr("Sin datos", "No data")
                      : promedioFlujo < 1.5
                      ? tr("Ligero", "Light")
                      : promedioFlujo < 2.5
                      ? tr("Moderado", "Moderate")
                      : tr("Abundante", "Heavy"),
                ),
                const SizedBox(height: 30),

                if (sintomas.isNotEmpty) ...[
                  _SectionTitle(
                      tr("Síntomas más frecuentes", "Most frequent symptoms")),
                  _Bars(
                    rows: [
                      for (final e in sintomas)
                        (
                          key: 'sintoma-${e.key.name}',
                          label: e.key.label,
                          shown: '${e.value}',
                          fraction: e.value / sintomas.first.value,
                          semantics: '${e.key.label}: ${e.value} '
                              '${e.value == 1 ? tr('día', 'day') : tr('días', 'days')}',
                          color: null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 30),
                ],

                if (animos.isNotEmpty) ...[
                  _SectionTitle(
                      tr("Estados de ánimo registrados", "Logged moods")),
                  // Ancho segun el porcentaje del total, no del mayor.
                  _Bars(
                    rows: [
                      for (final e in animos)
                        (
                          key: 'animo-${e.key.name}',
                          label: e.key.label,
                          shown: '${_percent(e.value / totalAnimos)}'
                              '${tr(' %', '%')}',
                          fraction: e.value / totalAnimos,
                          semantics: '${e.key.label}: '
                              '${_percent(e.value / totalAnimos)}${tr(' %', '%')}',
                          color: moodChartColors[e.key],
                        ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          text,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      );
}

/// Un dato con su nombre arriba, como tarjeta. El lector de pantalla lee
/// [semanticLabel] (por defecto "nombre: dato") como una sola frase; el
/// boton (i), si hay [info], va aparte.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    this.note,
    this.semanticLabel,
    this.info,
  });

  final String label;
  final String value;
  final String? note;
  final String? semanticLabel;
  final String? info;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      decoration: BoxDecoration(
        color: context.aura.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Semantics(
              container: true,
              excludeSemantics: true,
              label: semanticLabel ?? '$label: $value',
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 13, color: context.aura.textSecondary)),
                    const SizedBox(height: 4),
                    Text(value,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: context.aura.textPrimary)),
                    if (note != null) ...[
                      const SizedBox(height: 2),
                      Text(note!,
                          style: TextStyle(
                              fontSize: 12,
                              color: context.aura.textSecondary)),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (info != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: tr('Qué significa "$label"', 'What "$label" means'),
              icon: Icon(Icons.info_outline,
                  size: 20, color: context.aura.textSecondary),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(label),
                  content: Text(info!),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(tr('Entendido', 'Got it')),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Barras horizontales: el nombre a la izquierda (puede ocupar dos lineas,
/// nunca se pisa con el vecino), la barra con el ancho [fraction] y el
/// numero a la derecha. Sin [color], el estilo rosado de los sintomas.
class _Bars extends StatelessWidget {
  final List<
      ({
        String key,
        String label,
        String shown,
        double fraction,
        String semantics,
        Color? color,
      })> rows;

  const _Bars({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in rows)
          Semantics(
            key: ValueKey(row.key),
            container: true,
            excludeSemantics: true,
            label: row.semantics,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      row.label,
                      style: TextStyle(
                          fontSize: 14, color: context.aura.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: row.fraction,
                        child: Container(
                          height: 18,
                          decoration: BoxDecoration(
                            color: row.color ?? AppColors.secondary,
                            border: row.color != null
                                ? null
                                : Border.all(
                                    color: AppColors.accentStrong,
                                    width: AppColors.thinBorderWidth,
                                  ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 44,
                    child: Text(
                      row.shown,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.aura.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Porcentaje redondeado de las barras de animo.
String _percent(double fraction) => (fraction * 100).toStringAsFixed(0);

/// Un color fijo por estado de animo para sus barras (oscuros: antes
/// llevaban texto blanco encima, en el grafico de torta).
const Map<Mood, Color> moodChartColors = {
  Mood.feliz: Color(0xFFB0480F),
  Mood.triste: Color(0xFF2F6690),
  Mood.irritable: Color(0xFFB3261E),
  Mood.cansada: Color(0xFF6A4C93),
  Mood.normal: Color(0xFF3E7A4A),
};

/// "Tus ciclos": tarjetas con la duracion tipica del ciclo (el mismo
/// numero que usa la prediccion, ver [estimateCycleLength]), regularidad,
/// duracion tipica del periodo (ver [estimatePeriodLength]) y el proximo
/// periodo; debajo, el grafico de los ultimos ciclos.
class _CyclesSection extends StatelessWidget {
  const _CyclesSection({required this.inputs});

  final PredictionInputs inputs;

  static String _dias(int n) =>
      n == 1 ? tr("1 día", "1 day") : tr("$n días", "$n days");

  static String _corta(String day) =>
      DateFormat(auraIsEnglish ? 'MMM d' : 'd MMM', auraLanguage)
          .format(DateTime.parse(day));

  @override
  Widget build(BuildContext context) {
    final config = inputs.config;
    final ciclo = estimateCycleLength(cycles: inputs.cycles, config: config);
    final periodo = estimatePeriodLength(cycles: inputs.cycles, config: config);
    final ciclosCompletos = ciclo.consideredCount + ciclo.excludedCount;
    final regularidad = cycleRegularity(ciclo, config: config);
    final prediccion = inputs.predictionsPaused
        ? null
        : predictCycle(
            cycles: inputs.cycles, today: DayKey.today(), config: config);
    final gris = TextStyle(fontSize: 13, color: context.aura.textSecondary);
    final recientes = tr(' (los más recientes)', ' (the most recent)');
    final tope = ciclo.consideredCount == config.maxCyclesConsidered;

    final tarjetas = <Widget>[
      if (ciclosCompletos > 0)
        _StatCard(
          label: tr("Ciclos considerados", "Cycles considered"),
          value: '${ciclo.consideredCount}',
          note: tope ? tr("Los más recientes", "The most recent") : null,
          semanticLabel: tr(
              "Ciclos considerados: ${ciclo.consideredCount}${tope ? recientes : ''}",
              "Cycles considered: ${ciclo.consideredCount}${tope ? recientes : ''}"),
          info: tr(
              "Son los ciclos completos (de un período al siguiente) que usamos "
                  "para los cálculos: los ${config.maxCyclesConsidered} más "
                  "recientes, sin contar los que duran menos de "
                  "${config.minValidCycleLengthDays} o más de "
                  "${config.maxValidCycleLengthDays} días.",
              "These are the complete cycles (from one period to the next) "
                  "used for the calculations: the ${config.maxCyclesConsidered} "
                  "most recent, leaving out any shorter than "
                  "${config.minValidCycleLengthDays} or longer than "
                  "${config.maxValidCycleLengthDays} days."),
        ),
      if (regularidad != null) ...[
        _StatCard(
          label: tr("Duración típica del ciclo", "Typical cycle length"),
          value: _dias(ciclo.days!),
        ),
        _StatCard(
          label: tr("Más corto y más largo", "Shortest and longest"),
          value: ciclo.shortestDays == ciclo.longestDays
              ? _dias(ciclo.shortestDays!)
              : tr("${ciclo.shortestDays} a ${_dias(ciclo.longestDays!)}",
                  "${ciclo.shortestDays} to ${_dias(ciclo.longestDays!)}"),
        ),
        _StatCard(
          label: tr("Regularidad", "Regularity"),
          value: regularidad.label,
          info: tr(
              "Compara cuánto cambia la duración de tus ciclos. Regular: "
                  "suelen durar casi lo mismo. Algo variable o muy variable: "
                  "cambian más de un ciclo a otro, y las estimaciones son "
                  "menos precisas.",
              "Compares how much your cycle length changes. Regular: they "
                  "usually last about the same. Somewhat or very variable: "
                  "they change more from one cycle to the next, and estimates "
                  "are less precise."),
        ),
      ],
      _StatCard(
        label: tr("Duración típica del período", "Typical period length"),
        value: _dias(periodo.days),
        note: periodo.source == PeriodLengthSource.ownPeriods
            ? tr("Según tus períodos", "Based on your periods")
            : tr("Según tu ajuste", "Based on your setting"),
        semanticLabel: tr(
            "Duración típica del período: ${_dias(periodo.days)} "
                "${periodo.source == PeriodLengthSource.ownPeriods ? '(según tus períodos)' : '(según tu ajuste)'}",
            "Typical period length: ${_dias(periodo.days)} "
                "${periodo.source == PeriodLengthSource.ownPeriods ? '(based on your periods)' : '(based on your setting)'}"),
      ),
      if (inputs.predictionsPaused)
        _StatCard(
          label: tr("Próximo período", "Next period"),
          value: tr("En pausa", "Paused"),
        )
      else if (prediccion case final ActivePrediction p)
        _StatCard(
          label: tr("Próximo período", "Next period"),
          value: '${_corta(p.nextPeriodEarliestDate)} – '
              '${_corta(p.nextPeriodLatestDate)}',
          note: tr("Estimación", "Estimate"),
          semanticLabel: '${tr("Próximo período", "Next period")}: '
              '${dayMonthLabel(p.nextPeriodEarliestDate)} – '
              '${dayMonthLabel(p.nextPeriodLatestDate)}',
        ),
    ];

    final excluidos = ciclo.excludedCount;
    return Column(
      children: [
        _SectionTitle(tr("Tus ciclos", "Your cycles")),
        if (ciclosCompletos == 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              tr("Registra al menos dos períodos para ver tus ciclos.",
                  "Log at least two periods to see your cycles."),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
          ),
        // Dos columnas, misma altura por fila; la impar del final ocupa su mitad.
        for (var i = 0; i < tarjetas.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: tarjetas[i]),
                  const SizedBox(width: 12),
                  Expanded(
                      child: i + 1 < tarjetas.length
                          ? tarjetas[i + 1]
                          : const SizedBox.shrink()),
                ],
              ),
            ),
          ),
        if (ciclosCompletos > 0 && regularidad == null) ...[
          const SizedBox(height: 12),
          if (ciclo.consideredCount == 1)
            Text(
              tr("Tu único ciclo completo: ${_dias(ciclo.consideredLengthsDays.single)}",
                  "Your only complete cycle: ${_dias(ciclo.consideredLengthsDays.single)}"),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
          Text(
            tr("Con dos ciclos o más calculamos tu duración típica y tu "
                "regularidad.",
                "With two or more cycles we can calculate your typical length "
                "and regularity."),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15),
          ),
        ],
        if (excluidos > 0) ...[
          const SizedBox(height: 8),
          Text(
            tr("${excluidos == 1 ? '1 ciclo no se cuenta' : '$excluidos ciclos no se cuentan'} "
            "por durar menos de ${config.minValidCycleLengthDays} o más de "
            "${config.maxValidCycleLengthDays} días.",
                "${excluidos == 1 ? "1 cycle isn't counted" : "$excluidos cycles aren't counted"} "
                "(shorter than ${config.minValidCycleLengthDays} or longer than "
                "${config.maxValidCycleLengthDays} days)."),
            textAlign: TextAlign.center,
            style: gris,
          ),
        ],
        if (ciclosCompletos >= 2) ...[
          const SizedBox(height: 24),
          _CycleChart(
              cycles: inputs.cycles,
              typical: regularidad != null ? ciclo.days : null),
        ],
      ],
    );
  }
}

/// Duracion de los ultimos 12 ciclos completos (tambien los que no cuentan,
/// que asi se ven), con una linea punteada en la duracion tipica.
class _CycleChart extends StatelessWidget {
  const _CycleChart({required this.cycles, required this.typical});

  final List<CycleSummary> cycles;
  final int? typical;

  static const _maxBars = 12;

  @override
  Widget build(BuildContext context) {
    final completos = [
      for (final c in [...cycles]
        ..sort((a, b) => DayKey.compare(a.startDate, b.startDate)))
        if (c.cycleLengthDays != null) c,
    ];
    final barras = completos.length > _maxBars
        ? completos.sublist(completos.length - _maxBars)
        : completos;
    final largos = [for (final c in barras) c.cycleLengthDays!];
    final maxY =
        ([...largos, typical ?? 0].reduce((a, b) => a > b ? a : b) * 1.15)
            .ceilToDouble();
    final fecha = DateFormat(auraIsEnglish ? 'MMM d' : 'd MMM', auraLanguage);
    final gris = TextStyle(fontSize: 11, color: context.aura.textSecondary);
    // Con muchas barras, una fecha si y una no (no caben todas).
    final paso = barras.length > 6 ? 2 : 1;

    final resumen = tr(
        "Duración de tus últimos ciclos: ${largos.join(', ')} días."
            "${typical != null ? ' Duración típica: $typical días.' : ''}",
        "Your recent cycle lengths: ${largos.join(', ')} days."
            "${typical != null ? ' Typical length: $typical days.' : ''}");

    return Column(
      children: [
        _SectionTitle(
            tr("Duración de tus últimos ciclos", "Your recent cycle lengths")),
        Semantics(
          container: true,
          label: resumen,
          excludeSemantics: true,
          child: SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(enabled: false),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                extraLinesData: ExtraLinesData(horizontalLines: [
                  if (typical != null)
                    HorizontalLine(
                      y: typical!.toDouble(),
                      color: context.aura.textSecondary,
                      strokeWidth: 1,
                      dashArray: [6, 4],
                    ),
                ]),
                titlesData: FlTitlesData(
                  leftTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 20,
                      getTitlesWidget: (x, meta) => Text(
                        '${largos[x.toInt()]}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.aura.textPrimary),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (x, meta) {
                        final i = x.toInt();
                        // La ultima siempre lleva fecha.
                        if ((barras.length - 1 - i) % paso != 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                              fecha.format(
                                  DateTime.parse(barras[i].startDate)),
                              style: gris),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < largos.length; i++)
                    BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: largos[i].toDouble(),
                        width: 16,
                        color: AppColors.accentStrong,
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ]),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (typical != null)
          ExcludeSemantics(
            child: Text(
              tr("La línea punteada es tu duración típica ($typical días). "
                  "Debajo de cada barra, el día en que empezó el ciclo.",
                  "The dashed line is your typical length ($typical days). "
                  "Below each bar, the day the cycle started."),
              textAlign: TextAlign.center,
              style: gris,
            ),
          ),
      ],
    );
  }
}
