import 'package:flutter/material.dart';

/// Brand palette. Green and red echo the flag of Bangladesh.
abstract final class AppColors {
  static const brand = Color(0xFF006A4E);
  static const brandDark = Color(0xFF004D38);
  static const brandLight = Color(0xFFE3F2EC);
  static const accent = Color(0xFFF42A41);
  static const gold = Color(0xFFF2A900);

  static const success = Color(0xFF1E9E5A);
  static const warning = Color(0xFFE8A317);
  static const danger = Color(0xFFD7263D);
  static const info = Color(0xFF2F6FDE);

  static const lightBackground = Color(0xFFF6F8F7);
  static const darkBackground = Color(0xFF0F1513);
  static const darkSurface = Color(0xFF17201D);

  /// Parses `#RRGGBB` strings coming from the database (subject colours …).
  static Color fromHex(String? hex, {Color fallback = brand}) {
    if (hex == null || hex.length < 7) return fallback;
    final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
    return value == null ? fallback : Color(0xFF000000 | value);
  }
}
