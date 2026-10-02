import 'package:flutter/material.dart';
import '../utils/colors.dart';
import '../utils/date_utils.dart';

class CycleCard extends StatelessWidget {
  final DateTime fechaInicio;
  final int duracionCiclo;
  final String faseActual;
  final VoidCallback? onTap;

  const CycleCard({
    super.key,
    required this.fechaInicio,
    required this.duracionCiclo,
    required this.faseActual,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final proximoInicio = fechaInicio.add(Duration(days: duracionCiclo));
    final diasHastaProximo = DateUtilsAura.diasHasta(proximoInicio);
    final fechaFormateada = DateUtilsAura.formatFechaLarga(fechaInicio);

    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: AppColors.background,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Ciclo actual",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getColorPorFase(faseActual).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      faseActual,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _getColorPorFase(faseActual),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text("Inicio: $fechaFormateada",
                  style: const TextStyle(fontSize: 15, color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              Text("Duración promedio: $duracionCiclo días",
                  style: const TextStyle(fontSize: 15, color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              Text(
                diasHastaProximo > 0
                    ? "Próximo período en $diasHastaProximo días"
                    : diasHastaProximo == 0
                    ? "Tu período comienza hoy 🩸"
                    : "Nuevo ciclo en curso 💧",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: diasHastaProximo <= 2
                      ? AppColors.menstrual
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getColorPorFase(String fase) {
    if (fase.contains("menstrual")) return AppColors.menstrual;
    if (fase.contains("folicular")) return AppColors.folicular;
    if (fase.contains("ovulatoria")) return AppColors.ovulatoria;
    if (fase.contains("lútea")) return AppColors.lutea;
    return AppColors.accent;
  }
}
