import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/utils/colors.dart';

/// Razon de contraste WCAG 2.x entre dos colores opacos.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (claro, oscuro) = la > lb ? (la, lb) : (lb, la);
  return (claro + 0.05) / (oscuro + 0.05);
}

void main() {
  test('la formula da los valores conocidos (blanco/negro 21:1)', () {
    expect(contrastRatio(Colors.white, Colors.black), closeTo(21, 0.001));
    expect(contrastRatio(Colors.white, Colors.white), closeTo(1, 0.001));
  });

  // HU-05, CP5d-2: las marcas de ventana fertil y ovulacion son graficos
  // (WCAG 1.4.11): al menos 3:1 sobre el fondo de la app y sobre blanco
  // (el fondo de los tests).
  group('AppColors.fertile', () {
    test('al menos 3:1 sobre AppColors.background', () {
      expect(
        contrastRatio(AppColors.fertile, AppColors.background),
        greaterThanOrEqualTo(3.0),
      );
    });

    test('al menos 3:1 sobre blanco', () {
      expect(
        contrastRatio(AppColors.fertile, Colors.white),
        greaterThanOrEqualTo(3.0),
      );
    });
  });
}
