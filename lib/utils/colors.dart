import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFFA8D8EA);
  static const Color secondary = Color(0xFFFAD4D8);
  static const Color accent = Color(0xFFEE8CA7);
  static const Color background = Color(0xFFF8FAFB);
  static const Color textPrimary = Color(0xFF333333);
  /// Texto secundario: 4,66:1 sobre [background] y 4,88:1 sobre blanco
  /// (antes #777777, 4,28:1).
  static const Color textSecondary = Color(0xFF717171);

  /// Acento fuerte: SOLO bordes, iconos y contornos (hoy, estimados,
  /// menos/mas, chip marcado, periodo registrado, rango, barras de
  /// sintomas). Misma familia que [accent], mas profundo: 3,13:1 sobre
  /// [background] y 3,28:1 sobre blanco. No reemplaza a [accent] ni a
  /// los rellenos pastel.
  static const Color accentStrong = Color(0xFFE76085);

  /// Icono del chip de sintoma marcado: 3,10:1 sobre su relleno
  /// [secondary].
  static const Color chipCheckIcon = Color(0xFFE23866);

  /// Texto de "Confianza: ..." (Inicio). El fondo sigue siendo el tinte al
  /// 15 % del color original (Colors.green, blueGrey, orange); solo el
  /// texto es mas oscuro para llegar a 4,5:1 sobre ese tinte.
  static const Color confidenceHighText = Color(0xFF347837);
  static const Color confidenceMediumText = Color(0xFF536D79);
  static const Color confidenceLowText = Color(0xFF9E5E00);

  /// Texto de "Periodo atrasado" sobre el tinte rojo al 10 %.
  static const Color lateText = Color(0xFFD4190C);

  /// Marcas de ventana fertil y ovulacion del Calendario (HU-05, CP5d-2):
  /// azul de la familia de [primary] (mismo tono, mas oscuro) con
  /// contraste de al menos 3:1 sobre [background] y sobre blanco (ver
  /// test/utils/colors_test.dart).
  static const Color fertile = Color(0xFF3A8BAA);

  /// Borde de la pildora de la pestaña seleccionada (barra inferior):
  /// el azul de [fertile], 3,32:1 sobre el fondo de la barra. El relleno
  /// de la pildora no cambia.
  static const Color navIndicatorBorder = fertile;

  /// Grosor de los bordes finos (periodo registrado, rango elegido,
  /// barras de sintomas).
  static const double thinBorderWidth = 1.5;
}

/// Los colores que cambian con el tema oscuro. El claro son los mismos de
/// [AppColors]; los pasteles y acentos no cambian, y el texto sobre un
/// relleno pastel sigue siendo [AppColors.textPrimary] en los dos temas.
/// Contrastes en test/utils/colors_test.dart.
@immutable
class AuraColors extends ThemeExtension<AuraColors> {
  const AuraColors({
    required this.background,
    required this.card,
    required this.textPrimary,
    required this.textSecondary,
    required this.chip,
    required this.chipBorder,
    required this.confidenceHighText,
    required this.confidenceMediumText,
    required this.confidenceLowText,
    required this.lateText,
  });

  final Color background;

  /// Tarjetas, campos de texto y la barra de los graficos (blanco en el
  /// tema claro).
  final Color card;
  final Color textPrimary;
  final Color textSecondary;

  /// Relleno y borde de un chip de sintoma sin marcar.
  final Color chip;
  final Color chipBorder;
  final Color confidenceHighText;
  final Color confidenceMediumText;
  final Color confidenceLowText;
  final Color lateText;

  static const light = AuraColors(
    background: AppColors.background,
    card: Colors.white,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    chip: Color(0xFFEEEEEE),
    chipBorder: Color(0xFFE0E0E0),
    confidenceHighText: AppColors.confidenceHighText,
    confidenceMediumText: AppColors.confidenceMediumText,
    confidenceLowText: AppColors.confidenceLowText,
    lateText: AppColors.lateText,
  );

  static const dark = AuraColors(
    background: Color(0xFF15181B),
    card: Color(0xFF23272B),
    textPrimary: Color(0xFFE6E6E6),
    textSecondary: Color(0xFFADB3B8),
    chip: Color(0xFF2E3337),
    chipBorder: Color(0xFF454B50),
    confidenceHighText: Color(0xFF8BD18E),
    confidenceMediumText: Color(0xFFB4C6CF),
    confidenceLowText: Color(0xFFFFB75E),
    lateText: Color(0xFFFF8A80),
  );

  @override
  AuraColors copyWith() => this;

  @override
  AuraColors lerp(AuraColors? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

extension AuraColorsContext on BuildContext {
  /// Colores del tema actual; sin [auraTheme] (algunos tests), los claros.
  AuraColors get aura =>
      Theme.of(this).extension<AuraColors>() ?? AuraColors.light;
}
