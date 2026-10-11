import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// La orientacion vertical se fija en el manifest (no con SystemChrome):
/// este test evita que el atributo se pierda en un cambio futuro.
void main() {
  test('FlutterActivity declara screenOrientation="portrait"', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    // [^>]* abarca saltos de linea (\r\n incluido): toma la etiqueta de
    // apertura completa de cada <activity>.
    final activities = RegExp(r'<activity\b[^>]*>')
        .allMatches(manifest)
        .map((m) => m.group(0)!)
        .where((tag) => RegExp(
                r'android:name\s*=\s*"io\.flutter\.embedding\.android\.FlutterActivity"')
            .hasMatch(tag))
        .toList();

    expect(activities, hasLength(1),
        reason: 'el manifest debe tener una sola FlutterActivity');
    expect(
        RegExp(r'android:screenOrientation\s*=\s*"portrait"')
            .hasMatch(activities.single),
        isTrue,
        reason: 'FlutterActivity sin android:screenOrientation="portrait"');
  });
}
