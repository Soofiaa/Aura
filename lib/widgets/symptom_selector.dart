import 'package:flutter/material.dart';

class SymptomSelector extends StatefulWidget {
  final List<String> selectedSymptoms;
  final Function(List<String>) onSelectionChanged;

  const SymptomSelector({
    super.key,
    required this.selectedSymptoms,
    required this.onSelectionChanged,
  });

  @override
  State<SymptomSelector> createState() => _SymptomSelectorState();
}

class _SymptomSelectorState extends State<SymptomSelector> {
  final List<String> _allSymptoms = [
    'Dolor abdominal',
    'Dolor de cabeza',
    'Cansancio',
    'Antojos',
    'Cambios de humor',
    'Hinchazón',
    'Acné',
    'Dolor de espalda',
  ];

  late List<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.selectedSymptoms);
  }

  void _toggleSymptom(String symptom) {
    setState(() {
      if (_selected.contains(symptom)) {
        _selected.remove(symptom);
      } else {
        _selected.add(symptom);
      }
    });
    widget.onSelectionChanged(_selected);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _allSymptoms.map((symptom) {
        final isSelected = _selected.contains(symptom);
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
