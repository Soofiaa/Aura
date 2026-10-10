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
