import 'package:flutter/foundation.dart' show setEquals;
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

  /// Si la fecha elegida ya tenia una fila en daily_logs al cargarla. Un
  /// dia que no la tenia y se guarda vacio no se escribe (hallazgo #11).
  bool _teniaRegistro = false;

  /// Foto de lo que se cargo para la fecha elegida, con los mismos valores
  /// efectivos que se guardarian. Si el formulario difiere de ella, hay
  /// cambios sin guardar y salir o cambiar de fecha pregunta (hallazgo #3).
  _DatosDelDia _cargado = _DatosDelDia.vacio;

  @override
  void initState() {
    super.initState();
    // Escribir en las notas no pasa por setState: se reconstruye para que
    // PopScope sepa si hay cambios sin guardar.
    _notasController.addListener(_alCambiarNotas);
    _cargarDia(_selectedDate);
  }

  void _alCambiarNotas() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _notasController.removeListener(_alCambiarNotas);
    _notasController.dispose();
    super.dispose();
  }

  /// Prellena el formulario con lo que ya existe para [date], o lo
  /// resetea a los valores por defecto si no hay nada registrado.
  Future<void> _cargarDia(DateTime date) async {
    final dateKey = DayKey.fromDate(date);
    final existing = await cycleRepository.getDay(dateKey);
    final symptoms = await cycleRepository.getSymptomsForDay(dateKey);

    if (!mounted) return;
    setState(() {
      _teniaRegistro = existing != null;
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
      // En el mismo setState: la foto y el formulario nunca quedan
      // desfasados.
      _cargado = _datosDelFormulario;
    });
  }

  _DatosDelDia get _datosDelFormulario => _DatosDelDia(
        sangrado: _esDiaDeSangrado,
        // Con el sangrado apagado el flujo no se guarda: no es un cambio.
        flujo: _esDiaDeSangrado ? _flujo : null,
        animo: _estadoAnimo,
        notas: _notasController.text.trim(),
        sintomas: _selectedSymptoms.toSet(),
      );

  bool get _hayCambios => !_datosDelFormulario.igualA(_cargado);

  /// Pregunta si se descartan los cambios. Devuelve true solo si la
  /// usuaria elige "Descartar".
  Future<bool> _confirmarDescarte() async {
    final descartar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("¿Descartar los cambios?"),
        content: const Text(
            "No guardaste los cambios de este día. Si sales ahora, se pierden."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Seguir editando"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Descartar"),
          ),
        ],
      ),
    );
    return descartar ?? false;
  }

  /// Atras del sistema o flecha de la barra con cambios sin guardar.
  Future<void> _alIntentarSalir(bool didPop, Object? result) async {
    if (didPop) return;
    if (await _confirmarDescarte() && mounted) {
      // Navigator.pop no pasa por PopScope: sale aunque canPop sea false.
      Navigator.pop(context);
    }
  }

  Future<void> _elegirFecha() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (pickedDate == null || !mounted) return;
    if (DayKey.fromDate(pickedDate) == DayKey.fromDate(_selectedDate)) return;
    // Cambiar de fecha recarga el formulario: con cambios sin guardar
    // pregunta igual que al salir; "Descartar" carga la otra fecha.
    if (_hayCambios && !await _confirmarDescarte()) return;
    if (!mounted) return;
    setState(() => _selectedDate = pickedDate);
    await _cargarDia(pickedDate);
  }

  /// Registro vacio: sangrado apagado, animo sin registrar, notas vacias
  /// (tras trim) y ningun sintoma, en un dia que no tenia fila. El flujo
  /// no cuenta: con el sangrado apagado no se guarda aunque se haya
  /// elegido antes de apagarlo. Un dia que ya tenia fila se guarda
  /// siempre (por ejemplo, un "no hubo sangrado" explicito o datos que la
  /// usuaria borro a proposito).
  bool get _registroVacio =>
      !_teniaRegistro &&
      !_esDiaDeSangrado &&
      _estadoAnimo == null &&
      _notasController.text.trim().isEmpty &&
      _selectedSymptoms.isEmpty;

  Future<void> _guardarRegistro() async {
    if (_registroVacio) {
      // No se crea una fila vacia: Estadisticas seguiria mostrando datos
      // y el respaldo contaria un "dia con registro" que no lo es.
      showAppSnackBar(context, "No había nada para guardar.");
      Navigator.pop(context);
      return;
    }
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
      showAppSnackBar(context, "Registro guardado correctamente.");

      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !_hayCambios,
      onPopInvokedWithResult: _alIntentarSalir,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Registrar día"),
          backgroundColor: const Color(0xFFA8D8EA),
          centerTitle: true,
        ),
        // #10: "Guardar registro" queda fijo abajo, fuera del scroll. El
        // Scaffold achica el cuerpo con el teclado abierto, asi que el boton
        // queda encima del teclado; el formulario termina sobre el boton y
        // ningun campo queda tapado.
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
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
                        onTap: _elegirFecha,
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
                              Flexible(
                                child: Text(
                                  "${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}",
                                  style: const TextStyle(fontSize: 16),
                                ),
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
                          // isExpanded: el texto elegido se ajusta al ancho (con
                          // "..." si no entra) en vez de desbordar.
                          isExpanded: true,
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
                        isExpanded: true,
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
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
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
            ),
          ],
        ),
      ),
    );
  }
}

/// Valores de un dia tal como se guardarian.
class _DatosDelDia {
  final bool sangrado;
  final FlowIntensity? flujo;
  final Mood? animo;
  final String notas;
  final Set<String> sintomas;

  const _DatosDelDia({
    required this.sangrado,
    required this.flujo,
    required this.animo,
    required this.notas,
    required this.sintomas,
  });

  static const vacio = _DatosDelDia(
      sangrado: false, flujo: null, animo: null, notas: '', sintomas: {});

  bool igualA(_DatosDelDia otro) =>
      sangrado == otro.sangrado &&
      flujo == otro.flujo &&
      animo == otro.animo &&
      notas == otro.notas &&
      setEquals(sintomas, otro.sintomas);
}
