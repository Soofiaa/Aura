import 'package:flutter_test/flutter_test.dart';

import 'package:aura/data/models/day_enums.dart';
import 'package:aura/domain/symptom_ranking.dart';

List<String> _nombres(List<MapEntry<Symptom, int>> ranking) =>
    [for (final e in ranking) '${e.key.label}=${e.value}'];

void main() {
  test('ordena de mayor a menor conteo', () {
    final ranking = rankSymptoms({
      Symptom.acne: 1,
      Symptom.cansancio: 5,
      Symptom.antojos: 3,
    });
    expect(_nombres(ranking), ['Cansancio=5', 'Antojos=3', 'Acné=1']);
  });

  test('deja fuera los sintomas con conteo 0', () {
    final ranking = rankSymptoms({
      Symptom.hinchazon: 0,
      Symptom.dolorDeEspalda: 2,
      Symptom.acne: 0,
    });
    expect(_nombres(ranking), ['Dolor de espalda=2']);
  });

  test('a igual conteo, desempata por nombre (orden estable)', () {
    // El orden de entrada no importa: el resultado es siempre el mismo.
    final a = rankSymptoms({
      Symptom.hinchazon: 2,
      Symptom.dolorDeCabeza: 2,
      Symptom.dolorAbdominal: 2,
      Symptom.antojos: 4,
    });
    final b = rankSymptoms({
      Symptom.dolorAbdominal: 2,
      Symptom.antojos: 4,
      Symptom.hinchazon: 2,
      Symptom.dolorDeCabeza: 2,
    });
    const esperado = [
      'Antojos=4',
      'Dolor abdominal=2',
      'Dolor de cabeza=2',
      'Hinchazón=2',
    ];
    expect(_nombres(a), esperado);
    expect(_nombres(b), esperado);
  });

  test('sin datos o solo ceros: lista vacia', () {
    expect(rankSymptoms({}), isEmpty);
    expect(rankSymptoms({Symptom.acne: 0}), isEmpty);
  });
}
