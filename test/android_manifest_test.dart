import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// La orientacion vertical se fija en el manifest (no con SystemChrome):
/// este test evita que el atributo se pierda en un cambio futuro.
void main() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  test('MainActivity declara screenOrientation="portrait"', () {
    // [^>]* abarca saltos de linea (\r\n incluido): toma la etiqueta de
    // apertura completa de cada <activity>.
    final activities = RegExp(r'<activity\b[^>]*>')
        .allMatches(manifest)
        .map((m) => m.group(0)!)
        .where((tag) =>
            RegExp(r'android:name\s*=\s*"\.MainActivity"').hasMatch(tag))
        .toList();

    expect(activities, hasLength(1),
        reason: 'el manifest debe tener una sola MainActivity');
    expect(
        RegExp(r'android:screenOrientation\s*=\s*"portrait"')
            .hasMatch(activities.single),
        isTrue,
        reason: 'MainActivity sin android:screenOrientation="portrait"');
  });

  test('sin respaldo en la nube ni transferencia entre telefonos (RR-6)', () {
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml')
        .readAsStringSync();
    for (final section in ['cloud-backup', 'device-transfer']) {
      final body = RegExp('<$section>([\\s\\S]*?)</$section>')
          .firstMatch(rules)
          ?.group(1);
      expect(body, isNotNull, reason: section);
      for (final domain in ['root', 'file', 'database', 'sharedpref']) {
        expect(body, contains('<exclude domain="$domain" path="." />'),
            reason: '$section / $domain');
      }
    }
  });

  test('MainActivity activa FLAG_SECURE antes de dibujar', () {
    final activity = File(
            'android/app/src/main/kotlin/com/soofiaa/aura/MainActivity.kt')
        .readAsStringSync();
    final onCreate = RegExp(r'override fun onCreate[\s\S]*?super\.onCreate')
        .firstMatch(activity)
        ?.group(0);
    expect(onCreate, contains('FLAG_SECURE'));
  });

  // HU-09: sin INTERNET, la compilacion de release (que Flutter no le agrega
  // el permiso) no puede subir el respaldo cifrado a Google Drive. El
  // respaldo es de la app y opt-in; el backup automatico del sistema sigue
  // apagado en el test de RR-6 de arriba.
  test('permiso INTERNET declarado para el respaldo en Drive (HU-09)', () {
    expect(manifest, contains('android.permission.INTERNET'));
  });
}
