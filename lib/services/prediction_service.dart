import 'package:hive_flutter/hive_flutter.dart';
import '../data/database/hive_boxes.dart';

class PredictionService {
  final Box ciclosBox = HiveBoxes.getCiclosBox();

  Map<String, dynamic>? getUltimoCiclo() {
    final ciclos = ciclosBox.get('listaCiclos', defaultValue: []);
    if (ciclos.isEmpty) return null;
    return Map<String, dynamic>.from(ciclos.last);
  }

  double getDuracionPromedio() {
    final ciclos = ciclosBox.get('listaCiclos', defaultValue: []);
    if (ciclos.isEmpty) return 28;
    final duraciones = ciclos.map((c) => (c['duracionCiclo'] ?? 28) as int).toList();
    final suma = duraciones.reduce((a, b) => a + b);
    return suma / duraciones.length;
  }

  DateTime? getProximoPeriodo() {
    final ultimo = getUltimoCiclo();
    if (ultimo == null) return null;
    final fechaInicio = DateTime.parse(ultimo['fechaInicio']);
    final duracion = ultimo['duracionCiclo'] ?? 28;
    return fechaInicio.add(Duration(days: duracion));
  }

  String getFaseActual() {
    final ultimo = getUltimoCiclo();
    if (ultimo == null) return "Sin datos";
    final fechaInicio = DateTime.parse(ultimo['fechaInicio']);
    final duracionCiclo = ultimo['duracionCiclo'] ?? 28;
    final diasDesdeInicio = DateTime.now().difference(fechaInicio).inDays;

    if (diasDesdeInicio < 0) return "Sin datos";
    if (diasDesdeInicio <= 5) return "Fase menstrual 🩸";
    if (diasDesdeInicio <= 13) return "Fase folicular 🌱";
    if (diasDesdeInicio <= 16) return "Fase ovulatoria 💕";
    if (diasDesdeInicio <= duracionCiclo) return "Fase lútea 🌙";
    return "Nuevo ciclo por comenzar 💧";
  }

  Map<String, DateTime>? getVentanaFertil() {
    final ultimo = getUltimoCiclo();
    if (ultimo == null) return null;
    final fechaInicio = DateTime.parse(ultimo['fechaInicio']);
    final inicioFertil = fechaInicio.add(const Duration(days: 12));
    final finFertil = fechaInicio.add(const Duration(days: 16));
    return {"inicio": inicioFertil, "fin": finFertil};
  }
}
