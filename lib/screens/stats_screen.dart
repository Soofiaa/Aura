import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../data/backup/backup_file_gateway.dart';
import '../data/doctor_report.dart';
import '../data/models/day_enums.dart';
import '../data/repositories/cycle_repository.dart';
import '../domain/cycle_predictor.dart';
import '../domain/symptom_ranking.dart';
import '../utils/app_snackbar.dart';
import '../utils/aura_localizations.dart';
import '../utils/colors.dart';

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
          final estadosAnimo = stats.moodFrequency;
          final promedioFlujo = stats.averageFlow;

          if (!stats.hasAnyLog) {
            return Center(
              child: Text(
                tr("Aún no hay registros guardados", "No entries saved yet"),
                style: const TextStyle(fontSize: 18),
              ),
            );
          }

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
                      padding: const EdgeInsets.only(bottom: 30),
                      child: _CyclesSection(inputs: inputs.data!),
                    );
                  },
                ),
                Text(
                  tr("Promedio de flujo", "Average flow"),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Text(
                  promedioFlujo == 0
                      ? tr("Sin datos", "No data")
                      : promedioFlujo < 1.5
                      ? tr("Ligero", "Light")
                      : promedioFlujo < 2.5
                      ? tr("Moderado", "Moderate")
                      : tr("Abundante", "Heavy"),
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.pinkAccent),
                ),
                const SizedBox(height: 30),

                // 🩹 Grafico de sintomas: barras horizontales
                if (sintomas.isNotEmpty) ...[
                  Text(
                    tr("Síntomas más frecuentes", "Most frequent symptoms"),
                    style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 15),
                  _SymptomBars(ranking: sintomas),
                ],
                const SizedBox(height: 30),

                // 😊 Gráfico de estados de ánimo
                if (estadosAnimo.isNotEmpty) ...[
                  Text(
                    tr("Estados de ánimo registrados", "Logged moods"),
                    style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 15),
                  // El grafico es solo dibujo: el lector de pantalla lee
                  // cada estado con el mismo porcentaje que se ve.
                  Semantics(
                    container: true,
                    label: _moodSummary(estadosAnimo),
                    excludeSemantics: true,
                    child: AspectRatio(
                    aspectRatio: 1.2,
                    child: PieChart(
                      PieChartData(
                        centerSpaceRadius: 40,
                        sections: estadosAnimo.entries.map((entry) {
                          final porcentaje = entry.value /
                              estadosAnimo.values
                                  .reduce((a, b) => a + b);
                          return PieChartSectionData(
                            value: entry.value.toDouble(),
                            color: moodChartColors[entry.key],
                            // En una porcion chica el texto se pisaba con
                            // el de al lado: ahi solo queda en la leyenda.
                            title: porcentaje < _minPercentForTitle
                                ? ''
                                : "${entry.key.label}\n${_percent(porcentaje)}%",
                            radius: 70,
                            titleStyle: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  ),
                  const SizedBox(height: 12),
                  ExcludeSemantics(child: _MoodLegend(moods: estadosAnimo)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// "Sintomas mas frecuentes" como barras horizontales: el nombre a la
/// izquierda (puede ocupar dos lineas, nunca se pisa con el vecino), la
/// barra proporcional al sintoma mas frecuente y el numero de dias a la
/// derecha. [ranking] ya viene filtrado y ordenado ([rankSymptoms]).
class _SymptomBars extends StatelessWidget {
  final List<MapEntry<Symptom, int>> ranking;

  const _SymptomBars({required this.ranking});

  @override
  Widget build(BuildContext context) {
    final maximo = ranking.first.value;
    return Column(
      children: [
        for (final entry in ranking)
          Semantics(
            key: ValueKey('sintoma-${entry.key.name}'),
            container: true,
            excludeSemantics: true,
            label: '${entry.key.label}: ${entry.value} '
                '${entry.value == 1 ? tr('día', 'day') : tr('días', 'days')}',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      entry.key.label,
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
                        widthFactor: entry.value / maximo,
                        child: Container(
                          height: 18,
                          decoration: BoxDecoration(
                            color: AppColors.secondary,
                            border: Border.all(
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
                    width: 32,
                    child: Text(
                      '${entry.value}',
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

/// Porcentaje redondeado que muestra el grafico de animo.
String _percent(double fraction) => (fraction * 100).toStringAsFixed(0);

/// Debajo de esta fraccion la porcion no lleva texto (ver la leyenda).
const double _minPercentForTitle = 0.08;

/// Un color fijo por estado de animo, oscuro para que el texto blanco de
/// las porciones llegue a 4,5:1 (antes Colors.primaries: amarillo, lima o
/// cian no llegaban a 2:1).
const Map<Mood, Color> moodChartColors = {
  Mood.feliz: Color(0xFFB0480F),
  Mood.triste: Color(0xFF2F6690),
  Mood.irritable: Color(0xFFB3261E),
  Mood.cansada: Color(0xFF6A4C93),
  Mood.normal: Color(0xFF3E7A4A),
};

/// Leyenda del grafico de animo: color, estado y porcentaje de cada
/// porcion (tambien las que no llevan texto). El lector de pantalla ya lee
/// el resumen del grafico.
class _MoodLegend extends StatelessWidget {
  const _MoodLegend({required this.moods});

  final Map<Mood, int> moods;

  @override
  Widget build(BuildContext context) {
    final total = moods.values.fold<int>(0, (a, b) => a + b);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 8,
      children: [
        for (final e in moods.entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: moodChartColors[e.key],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${e.key.label} ${_percent(e.value / total)}%',
                style: TextStyle(
                    fontSize: 14, color: context.aura.textPrimary),
              ),
            ],
          ),
      ],
    );
  }
}

/// Lo que lee el lector de pantalla del grafico de animo, en el mismo
/// orden que las porciones: "Estados de animo: Cansada: 31 %. ...".
String _moodSummary(Map<Mood, int> moods) {
  final total = moods.values.fold<int>(0, (a, b) => a + b);
  final partes = [
    for (final e in moods.entries)
      '${e.key.label}: ${_percent(e.value / total)}${tr(' %', '%')}',
  ];
  return tr('Estados de ánimo: ${partes.join('. ')}.',
      'Moods: ${partes.join('. ')}.');
}

/// "Tus ciclos": duracion tipica del ciclo (el mismo numero que usa la
/// prediccion, ver [estimateCycleLength]), regularidad y duracion tipica
/// del periodo (ver [estimatePeriodLength]).
class _CyclesSection extends StatelessWidget {
  const _CyclesSection({required this.inputs});

  final PredictionInputs inputs;

  static String _dias(int n) =>
      n == 1 ? tr("1 día", "1 day") : tr("$n días", "$n days");

  @override
  Widget build(BuildContext context) {
    final config = inputs.config;
    final ciclo = estimateCycleLength(cycles: inputs.cycles, config: config);
    final periodo = estimatePeriodLength(cycles: inputs.cycles, config: config);
    final ciclosCompletos = ciclo.consideredCount + ciclo.excludedCount;
    final regularidad = cycleRegularity(ciclo, config: config);

    final filas = <String>[
      if (ciclosCompletos == 0)
        tr("Registra al menos dos períodos para ver tus ciclos.",
            "Log at least two periods to see your cycles.")
      else ...[
        // Con el tope de ciclos alcanzado, aclara que hay mas registrados.
        tr("Ciclos considerados: ${ciclo.consideredCount}"
            "${ciclo.consideredCount == config.maxCyclesConsidered ? ' (los más recientes)' : ''}",
            "Cycles considered: ${ciclo.consideredCount}"
            "${ciclo.consideredCount == config.maxCyclesConsidered ? ' (the most recent)' : ''}"),
        if (regularidad != null) ...[
          tr("Duración típica del ciclo: ${_dias(ciclo.days!)}",
              "Typical cycle length: ${_dias(ciclo.days!)}"),
          ciclo.shortestDays == ciclo.longestDays
              ? tr("Más corto y más largo: ${_dias(ciclo.shortestDays!)}",
                  "Shortest and longest: ${_dias(ciclo.shortestDays!)}")
              : tr("Más corto y más largo: ${ciclo.shortestDays} a "
                  "${_dias(ciclo.longestDays!)}",
                  "Shortest and longest: ${ciclo.shortestDays} to "
                  "${_dias(ciclo.longestDays!)}"),
          tr("Regularidad: ${regularidad.label}",
              "Regularity: ${regularidad.label}"),
        ] else ...[
          if (ciclo.consideredCount == 1)
            tr("Tu único ciclo completo: ${_dias(ciclo.consideredLengthsDays.single)}",
                "Your only complete cycle: ${_dias(ciclo.consideredLengthsDays.single)}"),
          tr("Con dos ciclos o más calculamos tu duración típica y tu "
              "regularidad.",
              "With two or more cycles we can calculate your typical length "
              "and regularity."),
        ],
      ],
      tr("Duración típica del período: ${_dias(periodo.days)} "
          "${periodo.source == PeriodLengthSource.ownPeriods ? '(según tus períodos)' : '(según tu ajuste)'}",
          "Typical period length: ${_dias(periodo.days)} "
          "${periodo.source == PeriodLengthSource.ownPeriods ? '(based on your periods)' : '(based on your setting)'}"),
    ];

    final excluidos = ciclo.excludedCount;
    return Column(
      children: [
        Text(
          tr("Tus ciclos", "Your cycles"),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        for (final fila in filas)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              fila,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
          ),
        if (excluidos > 0)
          Text(
            tr("${excluidos == 1 ? '1 ciclo no se cuenta' : '$excluidos ciclos no se cuentan'} "
            "por durar menos de ${config.minValidCycleLengthDays} o más de "
            "${config.maxValidCycleLengthDays} días.",
                "${excluidos == 1 ? "1 cycle isn't counted" : "$excluidos cycles aren't counted"} "
                "(shorter than ${config.minValidCycleLengthDays} or longer than "
                "${config.maxValidCycleLengthDays} days)."),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: context.aura.textSecondary),
          ),
      ],
    );
  }
}
