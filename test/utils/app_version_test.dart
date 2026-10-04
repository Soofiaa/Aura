import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aura/utils/app_version.dart';

void main() {
  test('la constante de version coincide con version: de pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*([0-9.]+)\+(\d+)\s*$', multiLine: true)
        .firstMatch(pubspec);

    expect(match, isNotNull, reason: 'pubspec.yaml sin version: X.Y.Z+N');
    expect(appVersionName, match!.group(1));
    expect(appBuildNumber, int.parse(match.group(2)!));
  });
}
