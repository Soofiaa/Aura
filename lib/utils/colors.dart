import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFFA8D8EA);
  static const Color secondary = Color(0xFFFAD4D8);
  static const Color accent = Color(0xFFEE8CA7);
  static const Color background = Color(0xFFF8FAFB);
  static const Color textPrimary = Color(0xFF333333);
  static const Color textSecondary = Color(0xFF777777);

  /// Marcas de ventana fertil y ovulacion del Calendario (HU-05, CP5d-2):
  /// azul de la familia de [primary] (mismo tono, mas oscuro) con
  /// contraste de al menos 3:1 sobre [background] y sobre blanco (ver
  /// test/utils/colors_test.dart).
  static const Color fertile = Color(0xFF3A8BAA);
}
