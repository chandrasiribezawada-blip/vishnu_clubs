import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFF4B3FD8); // deep indigo
  static const Color primaryLight = Color(0xFF7C6CFF); // soft violet
  static const Color accent = Color(0xFFFF6B6B); // coral
  static const Color gold = Color(0xFFFFB84D); // warm amber

  // Surfaces
  static const Color background = Color(0xFFF6F5FC);
  static const Color surface = Colors.white;

  // Text
  static const Color textDark = Color(0xFF1C1A3D);
  static const Color textMuted = Color(0xFF7A7896);

  // Status
  static const Color success = Color(0xFF22C58B);
  static const Color warning = Color(0xFFFFB84D);
  static const Color error = Color(0xFFE5484D);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient sunsetGradient = LinearGradient(
    colors: [accent, gold],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}