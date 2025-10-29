import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFFA8D8EA);
  static const Color secondary = Color(0xFFFAD4D8);
  static const Color accent = Color(0xFFEE8CA7);
  static const Color background = Color(0xFFF8FAFB);
  static const Color textPrimary = Color(0xFF333333);
  static const Color textSecondary = Color(0xFF777777);

  static const Color menstrual = Color(0xFFF5B7B1);
  static const Color folicular = Color(0xFFAED6F1);
  static const Color ovulatoria = Color(0xFFF9E79F);
  static const Color lutea = Color(0xFFD2B4DE);

  static const LinearGradient auraGradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
