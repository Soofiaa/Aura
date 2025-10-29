import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import '../data/database/hive_boxes.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late Box _box;
  List<dynamic> registros = [];

  @override
  void initState() {
    super.initState();
    _box = HiveBoxes.getDiasBox();
    registros = _box.get('registros', defaultValue: []);
  }

  /// Contar frecuencia de síntomas
  Map<String, int> getFrecuenciaSintomas() {
    final Map<String, int> conteo = {};
    for (var reg in registros) {
      if (reg['sintomas'] != null) {
        for (var s in reg['sintomas']) {
          conteo[s] = (conteo[s] ?? 0) + 1;
        }
      }
    }
    return conteo;
  }

  /// Contar frecuencia de estado de ánimo
  Map<String, int> getFrecuenciaAnimo() {
    final Map<String, int> conteo = {};
    for (var reg in registros) {
      final estado = reg['estado_animo'] ?? 'Sin dato';
      conteo[estado] = (conteo[estado] ?? 0) + 1;
    }
    return conteo;
  }

  /// Calcular promedio de flujo
  double getPromedioFlujo() {
    if (registros.isEmpty) return 0;
    final Map<String, int> valores = {
      'Ligero': 1,
      'Moderado': 2,
      'Abundante': 3,
    };
    double total = 0;
    for (var reg in registros) {
      total += valores[reg['flujo']]?.toDouble() ?? 0;
    }
    return total / registros.length;
  }

  @override
  Widget build(BuildContext context) {
    final sintomas = getFrecuenciaSintomas();
    final estadosAnimo = getFrecuenciaAnimo();
    final promedioFlujo = getPromedioFlujo();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Estadísticas"),
        backgroundColor: const Color(0xFFA8D8EA),
        centerTitle: true,
      ),
      body: registros.isEmpty
          ? const Center(
        child: Text(
          "Aún no hay registros guardados 🩷",
          style: TextStyle(fontSize: 18),
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              "Promedio de flujo",
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600),
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
                            if (index < sintomas.keys.length) {
                              return Padding(
                                padding:
                                const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  sintomas.keys.elementAt(index),
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
                        "${entry.key}\n${(porcentaje * 100).toStringAsFixed(0)}%",
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
      ),
    );
  }
}
