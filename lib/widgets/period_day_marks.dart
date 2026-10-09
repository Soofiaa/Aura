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

/// Marca de un dia de la ventana fertil estimada (HU-05, CP5d-2): barra
/// solida corta abajo, en AppColors.fertile. En el dia de la ovulacion
/// ([ovulation]) ademas un punto relleno arriba, para que no dependa
/// solo del color. [inset] separa la barra y el punto del borde: en la
/// celda (52 de alto) quedan por debajo y por encima del numero, sin
/// tocarlo, con el texto a 1,0 y a 1,5.
class FertileDayMark extends StatelessWidget {
  const FertileDayMark({
    super.key,
    required this.ovulation,
    this.inset = 3,
    this.barWidth = 18,
  });

  final bool ovulation;
  final double inset;
  final double barWidth;

  static const double barHeight = 4;
  static const double dotDiameter = 6;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: inset,
          child: Center(
            child: Container(
              key: const ValueKey('fertile-bar'),
              width: barWidth,
              height: barHeight,
              decoration: BoxDecoration(
                color: AppColors.fertile,
                borderRadius: BorderRadius.circular(barHeight / 2),
              ),
            ),
          ),
        ),
        if (ovulation)
          Positioned(
            left: 0,
            right: 0,
            top: inset,
            child: Center(
              child: Container(
                key: const ValueKey('ovulation-dot'),
                width: dotDiameter,
                height: dotDiameter,
                decoration: const BoxDecoration(
                  color: AppColors.fertile,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Leyenda del calendario (HU-04 crit. 2 y 3, decision 9B): solo lo que
/// el calendario muestra. "Periodo registrado" va siempre; "Estimado sin
/// confirmar" solo con [showEstimated] (hay dias estimados, E-1). Con
/// [showFertile] (hay marcas de ventana fertil, CP5d-2) agrega la
/// ventana, la ovulacion y el aviso de que no es un metodo
/// anticonceptivo. Los textos son Flexible: con texto grande se parten
/// en vez de desbordar.
class CalendarLegend extends StatelessWidget {
  const CalendarLegend({
    super.key,
    this.showEstimated = false,
    this.showFertile = false,
  });

  final bool showEstimated;
  final bool showFertile;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 14, color: AppColors.textPrimary);
    final entradas = Wrap(
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
            const Flexible(child: Text('Período registrado', style: style)),
          ],
        ),
        if (showEstimated)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ExcludeSemantics(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CustomPaint(
                    painter:
                        DashedBorderPainter(radius: periodDayMarkRadius / 2),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Flexible(
                  child: Text('Estimado sin confirmar', style: style)),
            ],
          ),
        if (showFertile) ...[
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: FertileDayMark(
                      ovulation: false, inset: 2, barWidth: 16),
                ),
              ),
              SizedBox(width: 8),
              Flexible(child: Text('Ventana fértil estimada', style: style)),
            ],
          ),
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: FertileDayMark(
                      ovulation: true, inset: 2, barWidth: 16),
                ),
              ),
              SizedBox(width: 8),
              Flexible(child: Text('Ovulación estimada', style: style)),
            ],
          ),
        ],
      ],
    );
    if (!showFertile) return entradas;
    return Column(
      children: [
        entradas,
        const SizedBox(height: 8),
        Text(
          'Estimación; no es un método anticonceptivo.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}
