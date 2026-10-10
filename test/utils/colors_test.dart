import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/main.dart';
import 'package:aura/utils/colors.dart';

import '../support/contrast.dart';

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

  // Auditoria de UI (commit 6 de fix/accesibilidad-contraste): pares
  // minimos con los colores reales del codigo. Texto 4,5:1; graficos,
  // bordes e iconos 3:1 (WCAG 1.4.3 y 1.4.11).
  group('contraste de la paleta', () {
    const fondo = AppColors.background;
    const blanco = Colors.white;
    Color tinte(Color base, double alfa) =>
        Color.alphaBlend(base.withValues(alpha: alfa), blanco);
    final tema = auraTheme().colorScheme;

    void minimo(String nombre, Color a, Color b, double razon) {
      test('$nombre: al menos $razon:1', () {
        expect(contrastRatio(a, b), greaterThanOrEqualTo(razon));
      });
    }

    // Texto (4,5:1).
    minimo('textSecondary sobre el fondo', AppColors.textSecondary, fondo, 4.5);
    minimo('textSecondary sobre blanco', AppColors.textSecondary, blanco, 4.5);
    // Inicio: el tinte del chip sale del color original (Colors.*) al 15 %.
    minimo('"Confianza: Alta" sobre su tinte', AppColors.confidenceHighText,
        tinte(Colors.green, 0.15), 4.5);
    minimo('"Confianza: Media" sobre su tinte',
        AppColors.confidenceMediumText, tinte(Colors.blueGrey, 0.15), 4.5);
    minimo('"Confianza: Baja" sobre su tinte', AppColors.confidenceLowText,
        tinte(Colors.orange, 0.15), 4.5);
    minimo('"Periodo atrasado" sobre su tinte', AppColors.lateText,
        tinte(Colors.red, 0.10), 4.5);
    minimo('"Borrar todos los datos" (error del tema) sobre el fondo',
        tema.error, fondo, 4.5);

    // Graficos, bordes e iconos (3:1).
    minimo('acento fuerte sobre el fondo', AppColors.accentStrong, fondo, 3);
    minimo('acento fuerte sobre blanco', AppColors.accentStrong, blanco, 3);
    minimo('icono del chip marcado sobre su relleno', AppColors.chipCheckIcon,
        AppColors.secondary, 3);
    minimo('borde de la pildora sobre la barra inferior',
        AppColors.navIndicatorBorder, tema.surfaceContainer, 3);
    minimo('ventana fertil sobre la barra inferior', AppColors.fertile,
        tema.surfaceContainer, 3);

    test('los rellenos y botones pastel no cambiaron', () {
      expect(AppColors.primary, const Color(0xFFA8D8EA));
      expect(AppColors.secondary, const Color(0xFFFAD4D8));
      expect(AppColors.accent, const Color(0xFFEE8CA7));
      expect(AppColors.background, const Color(0xFFF8FAFB));
      expect(AppColors.accentStrong, isNot(AppColors.accent));
    });

    test('bordes finos de 1,5', () {
      expect(AppColors.thinBorderWidth, 1.5);
    });
  });
}
