import '../../utils/aura_localizations.dart';

/// Enums compartidos entre el esquema drift y la UI. Los nombres de los
/// valores (`.name`) son los que drift persiste como texto en la base de
/// datos via textEnum(), por lo que renombrar un valor es una migracion.
// Nombrado FlowIntensity (no "Flow") porque Flow ya es un widget de
// Flutter (package:flutter/widgets/basic.dart) y choca con ese import.
enum FlowIntensity { ligero, moderado, abundante }

extension FlowIntensityLabel on FlowIntensity {
  String get label => switch (this) {
        FlowIntensity.ligero => tr('Ligero', 'Light'),
        FlowIntensity.moderado => tr('Moderado', 'Moderate'),
        FlowIntensity.abundante => tr('Abundante', 'Heavy'),
      };

  /// Peso usado para calcular el flujo promedio (coincide con la escala
  /// que ya usaba stats_screen.dart: Ligero=1, Moderado=2, Abundante=3).
  int get weight => switch (this) {
        FlowIntensity.ligero => 1,
        FlowIntensity.moderado => 2,
        FlowIntensity.abundante => 3,
      };
}

enum Mood { feliz, triste, irritable, cansada, normal }

extension MoodLabel on Mood {
  String get label => switch (this) {
        Mood.feliz => tr('Feliz', 'Happy'),
        Mood.triste => tr('Triste', 'Sad'),
        Mood.irritable => tr('Irritable', 'Irritable'),
        Mood.cansada => tr('Cansada', 'Tired'),
        Mood.normal => tr('Normal', 'Okay'),
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
        Symptom.dolorAbdominal => tr('Dolor abdominal', 'Cramps'),
        Symptom.dolorDeCabeza => tr('Dolor de cabeza', 'Headache'),
        Symptom.cansancio => tr('Cansancio', 'Fatigue'),
        Symptom.antojos => tr('Antojos', 'Cravings'),
        Symptom.cambiosDeHumor => tr('Cambios de humor', 'Mood swings'),
        Symptom.hinchazon => tr('Hinchazón', 'Bloating'),
        Symptom.acne => tr('Acné', 'Acne'),
        Symptom.dolorDeEspalda => tr('Dolor de espalda', 'Back pain'),
      };
}

/// Origen del fin de un periodo (columna period_end de daily_logs, decision
/// D-1). Se guarda solo en el ULTIMO dia de sangrado del periodo.
/// - declared: la usuaria dijo que termino.
/// - inferred: lo escribio la migracion a v4 (o la conversion de un
///   respaldo v3) aplicando la regla D-2; se puede revertir sin tocar las
///   declaraciones reales.
enum PeriodEndSource { declared, inferred }

/// Duracion habitual del periodo (HU-01, columna typical_period_length de
/// app_settings): valores admitidos y valor por defecto.
const int minTypicalPeriodLength = 1;
const int maxTypicalPeriodLength = 15;
const int defaultTypicalPeriodLength = 5;
