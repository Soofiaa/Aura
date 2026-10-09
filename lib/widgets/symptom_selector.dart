import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _allSymptoms.map((symptom) {
        final isSelected = selectedSymptoms.contains(symptom);
        return GestureDetector(
          onTap: () => _toggleSymptom(symptom),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFFAD4D8)
                  : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFFEE8CA7)
                    : Colors.grey.shade300,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSelected ? Icons.check_circle : Icons.circle_outlined,
                  size: 18,
                  color:
                  isSelected ? const Color(0xFFEE8CA7) : Colors.grey[600],
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
        );
      }).toList(),
    );
  }
}
