import 'package:flutter/material.dart';

class AppColors {
  // Brand Colors
  static const Color darkBlue = Color(0xFF001F3F);
  static const Color primaryBlue = Color(0xFF0D47A1);
  static const Color secondaryBlue = Color(0xFF1565C0);
  
  static const Color primaryOrange = Color(0xFFFF851B);
  static const Color accentOrange = Color(0xFFFF9800);
  
  static const Color white = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF5F5F5);
  static const Color surface = Color(0xFFFFFFFF);
  
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  
  static const Color success = Color(0xFF4CAF50);
  static const Color error = Color(0xFFE53935);
  static const Color pending = Color(0xFFFF9800);
  static const Color accepted = Color(0xFF1E88E5);
  static const Color completed = Color(0xFF43A047);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryBlue, secondaryBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient orangeGradient = LinearGradient(
    colors: [primaryOrange, accentOrange],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
