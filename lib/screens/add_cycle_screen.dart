import 'package:flutter/material.dart';
import '../data/models/day_enums.dart';
import '../data/repositories/cycle_repository.dart';
import '../utils/day_key.dart';
import '../widgets/symptom_selector.dart';
import '../utils/app_snackbar.dart';

class AddCycleScreen extends StatefulWidget {
  const AddCycleScreen({super.key});

  @override
  State<AddCycleScreen> createState() => _AddCycleScreenState();
}

class _AddCycleScreenState extends State<AddCycleScreen> {
  final _formKey = GlobalKey<FormState>();

  DateTime _selectedDate = DateTime.now();

  // En un dia sin registro todo arranca vacio: el interruptor apagado,
  // flujo "Sin especificar" y animo "Sin registrar". Asi, registrar solo
  // sintomas no marca el dia como sangrado ni crea un periodo, y no se
  // guarda un flujo o animo que la usuaria no eligio (hallazgos B-1, B-2
  // y B-3). Apagarlo en un dia que era de sangrado guarda un "no"
  // explicito (ver CycleRepository.upsertDay).
  bool _esDiaDeSangrado = false;
  FlowIntensity? _flujo;
  Mood? _estadoAnimo;
  final TextEditingController _notasController = TextEditingController();
  List<String> _selectedSymptoms = [];

  @override
  void initState() {
    super.initState();
    _cargarDia(_selectedDate);
  }

  /// Prellena el formulario con lo que ya existe para [date], o lo
  /// resetea a los valores por defecto si no hay nada registrado.
  Future<void> _cargarDia(DateTime date) async {
    final dateKey = DayKey.fromDate(date);
    final existing = await cycleRepository.getDay(dateKey);
    final symptoms = await cycleRepository.getSymptomsForDay(dateKey);

    if (!mounted) return;
    setState(() {
      if (existing != null) {
        _esDiaDeSangrado = existing.isPeriodDay;
        _flujo = existing.flow;
        _estadoAnimo = existing.mood;
        _notasController.text = existing.notes ?? '';
        _selectedSymptoms = symptoms.map((s) => s.label).toList();
      } else {
        _esDiaDeSangrado = false;
        _flujo = null;
        _estadoAnimo = null;
        _notasController.text = '';
        _selectedSymptoms = [];
      }
    });
  }

  Future<void> _guardarRegistro() async {
    if (_formKey.currentState!.validate()) {
      final symptoms = _selectedSymptoms
          .map((label) => Symptom.values.firstWhere((s) => s.label == label))
          .toSet();

      await cycleRepository.upsertDay(
        date: DayKey.fromDate(_selectedDate),
        isPeriodDaySwitch: _esDiaDeSangrado,
        flow: _esDiaDeSangrado ? _flujo : null,
        mood: _estadoAnimo,
        notes: _notasController.text.trim(),
        symptoms: symptoms,
      );

      if (!mounted) return;
      showAppSnackBar(context, "Registro guardado correctamente ✅");

      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Registrar día"),
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
                    lastDate: DateTime.now(),
                  );
                  if (pickedDate != null) {
                    setState(() => _selectedDate = pickedDate);
                    await _cargarDia(pickedDate);
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  "Día de sangrado",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                value: _esDiaDeSangrado,
                onChanged: (v) => setState(() => _esDiaDeSangrado = v),
              ),

              if (_esDiaDeSangrado) ...[
                const SizedBox(height: 10),
                const Text(
                  "Flujo menstrual",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 5),
                DropdownButtonFormField<FlowIntensity?>(
                  initialValue: _flujo,
                  hint: const Text("Sin especificar"),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text("Sin especificar")),
                    ...FlowIntensity.values.map((f) =>
                        DropdownMenuItem(value: f, child: Text(f.label))),
                  ],
                  onChanged: (v) => setState(() => _flujo = v),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ],

              const SizedBox(height: 25),
              const Text(
                "Estado de ánimo",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 5),
              DropdownButtonFormField<Mood?>(
                initialValue: _estadoAnimo,
                hint: const Text("Sin registrar"),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text("Sin registrar")),
                  ...Mood.values.map((a) =>
                      DropdownMenuItem(value: a, child: Text(a.label))),
                ],
                onChanged: (v) => setState(() => _estadoAnimo = v),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),

              // 🔹 Sección de selección de síntomas
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
