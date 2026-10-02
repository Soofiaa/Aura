import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../data/models/day_enums.dart';
import '../data/repositories/cycle_repository.dart';

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
