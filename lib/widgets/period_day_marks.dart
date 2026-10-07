import 'package:flutter/material.dart';

import '../utils/colors.dart';

/// Radio de las marcas de dia del calendario (igual al relleno de los
/// dias registrados).
const double periodDayMarkRadius = 8;

/// Borde punteado redondeado de un dia estimado (E-1): sin relleno, en
/// AppColors.accent.
class DashedBorderPainter extends CustomPainter {
  const DashedBorderPainter({
    this.color = AppColors.accent,
    this.radius = periodDayMarkRadius,
    this.strokeWidth = 1.5,
    this.dash = 4,
    this.gap = 3,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final rect = Offset.zero & size;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          rect.deflate(strokeWidth / 2), Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
            metric.extractPath(distance, distance + dash), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.dash != dash ||
      oldDelegate.gap != gap;
}

/// Leyenda del calendario (HU-04 crit. 2 y 3, decision 9B): solo lo que
/// el calendario muestra, registrado y estimado.
class CalendarLegend extends StatelessWidget {
  const CalendarLegend({super.key});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 14, color: AppColors.textPrimary);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 20,
      runSpacing: 8,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(periodDayMarkRadius / 2),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text('Período registrado', style: style),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ExcludeSemantics(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CustomPaint(
                  painter: DashedBorderPainter(radius: periodDayMarkRadius / 2),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text('Estimado sin confirmar', style: style),
          ],
        ),
      ],
    );
  }
}
