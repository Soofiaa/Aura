import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../utils/colors.dart';

/// 📊 Widget genérico para mostrar gráficos de barras o pastel en Aura.
class ChartWidget extends StatelessWidget {
  final String titulo;
  final Map<String, num> datos;
  final ChartType tipo;

  const ChartWidget({
    super.key,
    required this.titulo,
    required this.datos,
    this.tipo = ChartType.bar,
  });

  @override
  Widget build(BuildContext context) {
    if (datos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          "Sin datos suficientes para mostrar $titulo",
          style: const TextStyle(fontSize: 16, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            if (tipo == ChartType.bar)
              _buildBarChart()
            else
              _buildPieChart(),
          ],
        ),
      ),
    );
  }

  /// 📊 Gráfico de barras
  Widget _buildBarChart() {
    final keys = datos.keys.toList();
    final values = datos.values.toList();

    return SizedBox(
      height: 250,
      child: BarChart(
        BarChartData(
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          alignment: BarChartAlignment.spaceAround,
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
                  if (index >= 0 && index < keys.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Text(
                        keys[index],
                        style: const TextStyle(fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
          barGroups: List.generate(
            keys.length,
                (i) => BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i].toDouble(),
                  color: AppColors.secondary,
                  width: 18,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 🥧 Gráfico de pastel
  Widget _buildPieChart() {
    return SizedBox(
      height: 230,
      child: PieChart(
        PieChartData(
          centerSpaceRadius: 40,
          sectionsSpace: 2,
          sections: datos.entries.map((entry) {
            final index = datos.keys.toList().indexOf(entry.key);
            final color = _PieColors._pieColors[index % _PieColors._pieColors.length];
            final total = datos.values.reduce((a, b) => a + b);
            final porcentaje = (entry.value / total * 100).toStringAsFixed(1);

            return PieChartSectionData(
              value: entry.value.toDouble(),
              title: "${entry.key}\n$porcentaje%",
              color: color,
              radius: 65,
              titleStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// Tipos de gráficos disponibles
enum ChartType { bar, pie }

/// Colores de pastel adicionales
extension _PieColors on AppColors {
  static const List<Color> _pieColors = [
    Color(0xFFA8D8EA),
    Color(0xFFFAD4D8),
    Color(0xFFF9E79F),
    Color(0xFFD2B4DE),
    Color(0xFFABEBC6),
    Color(0xFFF5B7B1),
  ];
}
