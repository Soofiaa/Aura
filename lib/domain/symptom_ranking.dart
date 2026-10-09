import '../data/models/day_enums.dart';

/// Orden del grafico "Sintomas mas frecuentes" de Estadisticas: solo los
/// sintomas con conteo mayor a 0, de mayor a menor, y a igual conteo por
/// nombre (orden alfabetico de la etiqueta, para que sea estable). La
/// consulta de frecuencias no ordena; el orden vive aca, en dominio puro.
List<MapEntry<Symptom, int>> rankSymptoms(Map<Symptom, int> frequency) {
  final ranked = [
    for (final entry in frequency.entries)
      if (entry.value > 0) entry,
  ];
  ranked.sort((a, b) {
    final byCount = b.value.compareTo(a.value);
    if (byCount != 0) return byCount;
    return a.key.label.compareTo(b.key.label);
  });
  return ranked;
}
