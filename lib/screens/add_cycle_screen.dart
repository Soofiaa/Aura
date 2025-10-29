import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../data/database/hive_boxes.dart';
import '../widgets/symptom_selector.dart';

class AddCycleScreen extends StatefulWidget {
  const AddCycleScreen({super.key});

  @override
  State<AddCycleScreen> createState() => _AddCycleScreenState();
}

class _AddCycleScreenState extends State<AddCycleScreen> {
  final _formKey = GlobalKey<FormState>();

  DateTime _selectedDate = DateTime.now();
  String _flujo = 'Ligero';
  String _estadoAnimo = 'Normal';
  final TextEditingController _notasController = TextEditingController();

  // Nuevo: lista de síntomas seleccionados
  List<String> _selectedSymptoms = [];

  final List<String> _opcionesFlujo = ['Ligero', 'Moderado', 'Abundante'];
  final List<String> _opcionesAnimo = [
    'Feliz',
    'Triste',
    'Irritable',
    'Cansada',
    'Normal'
  ];

  void _guardarRegistro() {
    if (_formKey.currentState!.validate()) {
      final box = HiveBoxes.getDiasBox(); // 👈 usa el método, no el string

      final registro = {
        "fecha": _selectedDate.toIso8601String(),
        "flujo": _flujo,
        "estado_animo": _estadoAnimo,
        "sintomas": _selectedSymptoms,
        "notas": _notasController.text.trim(),
      };

      final List registros = box.get('registros', defaultValue: []);
      registros.add(registro);
      box.put('registros', registros);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Registro guardado correctamente ✅")),
      );

      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Registrar síntomas"),
        backgroundColor: const Color(0xFFA8D8EA),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Fecha del registro",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 5),
              GestureDetector(
                onTap: () async {
                  final pickedDate = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (pickedDate != null) {
                    setState(() => _selectedDate = pickedDate);
                  }
                },
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 15),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}",
                        style: const TextStyle(fontSize: 16),
                      ),
                      const Icon(Icons.calendar_today, color: Colors.grey),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 25),
              const Text(
                "Flujo menstrual",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 5),
              DropdownButtonFormField<String>(
                value: _flujo,
                items: _opcionesFlujo
                    .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                    .toList(),
                onChanged: (v) => setState(() => _flujo = v!),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),

              const SizedBox(height: 25),
              const Text(
                "Estado de ánimo",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 5),
              DropdownButtonFormField<String>(
                value: _estadoAnimo,
                items: _opcionesAnimo
                    .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                    .toList(),
                onChanged: (v) => setState(() => _estadoAnimo = v!),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),

              // 🔹 Nueva sección de selección de síntomas
              const SizedBox(height: 25),
              const Text(
                "Síntomas",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              SymptomSelector(
                selectedSymptoms: _selectedSymptoms,
                onSelectionChanged: (newList) {
                  setState(() => _selectedSymptoms = newList);
                },
              ),

              const SizedBox(height: 25),
              const Text(
                "Notas adicionales",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 5),
              TextFormField(
                controller: _notasController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: "Ej: Dolor abdominal fuerte, cansancio, antojos...",
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),

              const SizedBox(height: 30),
              Center(
                child: ElevatedButton.icon(
                  onPressed: _guardarRegistro,
                  icon: const Icon(Icons.save),
                  label: const Text("Guardar registro"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA8D8EA),
                    foregroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
