import 'package:flutter/material.dart';

import '../utils/colors.dart';

/// Chips de sintomas. Es un widget controlado: muestra siempre
/// [selectedSymptoms] tal como llega y cada toque entrega una lista
/// nueva por [onSelectionChanged]; quien lo usa guarda esa lista y la
/// vuelve a pasar. Antes copiaba la lista solo al crearse, asi que los
/// sintomas de un dia guardado (que el formulario carga despues, de
/// forma asincrona) no aparecian marcados.
class SymptomSelector extends StatelessWidget {
  final List<String> selectedSymptoms;
  final Function(List<String>) onSelectionChanged;

  const SymptomSelector({
    super.key,
    required this.selectedSymptoms,
    required this.onSelectionChanged,
  });

  static const List<String> _allSymptoms = [
    'Dolor abdominal',
    'Dolor de cabeza',
    'Cansancio',
    'Antojos',
    'Cambios de humor',
    'Hinchazón',
    'Acné',
    'Dolor de espalda',
  ];

  // Lista nueva en cada cambio: nunca se modifica la que llego.
  void _toggleSymptom(String symptom) {
    final updated = List<String>.from(selectedSymptoms);
    if (!updated.remove(symptom)) updated.add(symptom);
    onSelectionChanged(updated);
  }

  /// Alto minimo del area tactil de cada chip (pautas de Android y
  /// Material). El chip visible sigue midiendo lo mismo: el resto es
  /// margen transparente que tambien responde al toque.
  static const double minTapHeight = 48;

  @override
  Widget build(BuildContext context) {
    // El icono crece con el tamano de texto del sistema, igual que la
    // etiqueta.
    final iconSize = MediaQuery.textScalerOf(context).scale(18);
    return Wrap(
      spacing: 8,
      // 3 + 2 + 3: con el margen vertical de cada chip, la separacion
      // visible entre filas sigue siendo de 8.
      runSpacing: 2,
      children: _allSymptoms.map((symptom) {
        final isSelected = selectedSymptoms.contains(symptom);
        return Semantics(
          container: true,
          checked: isSelected,
          label: symptom,
          onTap: () => _toggleSymptom(symptom),
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _toggleSymptom(symptom),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: minTapHeight),
              child: Align(
                widthFactor: 1,
                heightFactor: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFFAD4D8)
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.accentStrong
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          size: iconSize,
                          color: isSelected
                              ? AppColors.chipCheckIcon
                              : Colors.grey[600],
                        ),
                        const SizedBox(width: 6),
                        Text(
                          symptom,
                          style: TextStyle(
                            color: isSelected ? Colors.black : Colors.grey[800],
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
