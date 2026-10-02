/// Enums compartidos entre el esquema drift y la UI. Los nombres de los
/// valores (`.name`) son los que drift persiste como texto en la base de
/// datos via textEnum(), por lo que renombrar un valor es una migracion.
enum Flow { ligero, moderado, abundante }

extension FlowLabel on Flow {
  String get label => switch (this) {
        Flow.ligero => 'Ligero',
        Flow.moderado => 'Moderado',
        Flow.abundante => 'Abundante',
      };

  /// Peso usado para calcular el flujo promedio (coincide con la escala
  /// que ya usaba stats_screen.dart: Ligero=1, Moderado=2, Abundante=3).
  int get weight => switch (this) {
        Flow.ligero => 1,
        Flow.moderado => 2,
        Flow.abundante => 3,
      };
}

enum Mood { feliz, triste, irritable, cansada, normal }

extension MoodLabel on Mood {
  String get label => switch (this) {
        Mood.feliz => 'Feliz',
        Mood.triste => 'Triste',
        Mood.irritable => 'Irritable',
        Mood.cansada => 'Cansada',
        Mood.normal => 'Normal',
      };
}

enum Symptom {
  dolorAbdominal,
  dolorDeCabeza,
  cansancio,
  antojos,
  cambiosDeHumor,
  hinchazon,
  acne,
  dolorDeEspalda,
}

extension SymptomLabel on Symptom {
  String get label => switch (this) {
        Symptom.dolorAbdominal => 'Dolor abdominal',
        Symptom.dolorDeCabeza => 'Dolor de cabeza',
        Symptom.cansancio => 'Cansancio',
        Symptom.antojos => 'Antojos',
        Symptom.cambiosDeHumor => 'Cambios de humor',
        Symptom.hinchazon => 'Hinchazón',
        Symptom.acne => 'Acné',
        Symptom.dolorDeEspalda => 'Dolor de espalda',
      };
}
