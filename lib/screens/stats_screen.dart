import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../data/models/day_enums.dart';
import '../data/repositories/cycle_repository.dart';
import '../domain/cycle_predictor.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Estadísticas"),
        backgroundColor: const Color(0xFFA8D8EA),
        centerTitle: true,
      ),
      body: StreamBuilder<StatsSnapshot>(
        stream: _statsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final stats = snapshot.data!;
          final sintomas = stats.symptomFrequency;
          final estadosAnimo = stats.moodFrequency;
          final promedioFlujo = stats.averageFlow;

          if (!stats.hasAnyLog) {
            return const Center(
              child: Text(
                "Aún no hay registros guardados 🩷",
                style: TextStyle(fontSize: 18),
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
                const Text(
                  "Promedio de flujo",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Text(
                  promedioFlujo == 0
                      ? "Sin datos"
                      : promedioFlujo < 1.5
                      ? "Ligero"
                      : promedioFlujo < 2.5
                      ? "Moderado"
                      : "Abundante",
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.pinkAccent),
                ),
                const SizedBox(height: 30),

                // 🩹 Gráfico de síntomas
                if (sintomas.isNotEmpty) ...[
                  const Text(
                    "Síntomas más frecuentes",
                    style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 15),
                  AspectRatio(
                    aspectRatio: 1.3,
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        borderData: FlBorderData(show: false),
                        gridData: const FlGridData(show: false),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();
                                final keys = sintomas.keys.toList();
                                if (index < keys.length) {
                                  return Padding(
                                    padding:
                                    const EdgeInsets.only(top: 8.0),
                                    child: Text(
                                      keys[index].label,
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.black),
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
                        ),
                        barGroups: List.generate(
                          sintomas.length,
                              (i) => BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: sintomas.values.elementAt(i).toDouble(),
                                color: const Color(0xFFFAD4D8),
                                width: 18,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 30),

                // 😊 Gráfico de estados de ánimo
                if (estadosAnimo.isNotEmpty) ...[
                  const Text(
                    "Estados de ánimo registrados",
                    style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 15),
                  AspectRatio(
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
                            color: Colors.primaries[
                            estadosAnimo.keys.toList().indexOf(entry.key) %
                                Colors.primaries.length],
                            title:
                            "${entry.key.label}\n${(porcentaje * 100).toStringAsFixed(0)}%",
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
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// "Tus ciclos": duracion tipica del ciclo (el mismo numero que usa la
/// prediccion, ver [estimateCycleLength]), regularidad y duracion tipica
/// del periodo (ver [estimatePeriodLength]).
class _CyclesSection extends StatelessWidget {
  const _CyclesSection({required this.inputs});

  final PredictionInputs inputs;

  static String _dias(int n) => n == 1 ? "1 día" : "$n días";

  @override
  Widget build(BuildContext context) {
    final config = inputs.config;
    final ciclo = estimateCycleLength(cycles: inputs.cycles, config: config);
    final periodo = estimatePeriodLength(cycles: inputs.cycles, config: config);
    final ciclosCompletos = ciclo.consideredCount + ciclo.excludedCount;
    final regularidad = cycleRegularity(ciclo, config: config);

    final filas = <String>[
      if (ciclosCompletos == 0)
        "Registra al menos dos períodos para ver tus ciclos."
      else ...[
        // Con el tope de ciclos alcanzado, aclara que hay mas registrados.
        "Ciclos considerados: ${ciclo.consideredCount}"
            "${ciclo.consideredCount == config.maxCyclesConsidered ? ' (los más recientes)' : ''}",
        if (regularidad != null) ...[
          "Duración típica del ciclo: ${_dias(ciclo.days!)}",
          ciclo.shortestDays == ciclo.longestDays
              ? "Más corto y más largo: ${_dias(ciclo.shortestDays!)}"
              : "Más corto y más largo: ${ciclo.shortestDays} a "
                  "${_dias(ciclo.longestDays!)}",
          "Regularidad: ${regularidad.label}",
        ] else ...[
          if (ciclo.consideredCount == 1)
            "Tu único ciclo completo: ${_dias(ciclo.consideredLengthsDays.single)}",
          "Con dos ciclos o más calculamos tu duración típica y tu "
              "regularidad.",
        ],
      ],
      "Duración típica del período: ${_dias(periodo.days)} "
          "${periodo.source == PeriodLengthSource.ownPeriods ? '(según tus períodos)' : '(según tu ajuste)'}",
    ];

    final excluidos = ciclo.excludedCount;
    return Column(
      children: [
        const Text(
          "Tus ciclos",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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
            "${excluidos == 1 ? '1 ciclo no se cuenta' : '$excluidos ciclos no se cuentan'} "
            "por durar menos de ${config.minValidCycleLengthDays} o más de "
            "${config.maxValidCycleLengthDays} días.",
            textAlign: TextAlign.center,
            // grey[700] (#616161): 6,2:1 sobre blanco y 5,9:1 sobre el
            // fondo de la app.
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
      ],
    );
  }
}
