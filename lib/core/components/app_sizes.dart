import 'package:flutter/material.dart';

class AppSizes {
  AppSizes._();

  // Spacing
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  // Radius
  static const double radiusSm = 4;
  static const double radiusMd = 8;
  static const double radiusLg = 12;
  static const double radiusXl = 16;
  static const double radiusRound = 999;

  // Icon sizes
  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double iconLg = 24;
  static const double iconXl = 32;
  static const double iconXxl = 48;

  // Text sizes
  static const double textXs = 11;
  static const double textSm = 12;
  static const double textMd = 14;
  static const double textLg = 16;
  static const double textXl = 20;
  static const double textXxl = 24;
  static const double textXxxl = 28;

  // Layout
  static const double sidebarWidth = 300;
  static const double inputBarHeight = 64;
  static const double appBarHeight = 56;
  static const double cardMinHeight = 80;
  static const double sheetMaxHeight = 0.7;
  static const double chatBubbleMaxWidth = 0.75;
}

class AppColors {
  AppColors._();

  static const Color darkAccent = Color(0xFF3B82F6);
  static const Color lightAccent = Color(0xFF2563EB);
  static const Color error = Color(0xFFEF4444);
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);

  static Color darkSurface = const Color(0xFF1F1F1F);
  static Color darkBorder = const Color(0xFF2A2A2A);
  static Color darkMuted = const Color(0xFF666666);

  static Color lightSurface = const Color(0xFFF5F5F5);
  static Color lightBorder = const Color(0xFFE5E5E5);
  static Color lightMuted = const Color(0xFF999999);

  static Color accentForDark(bool isDark) => isDark ? darkAccent : lightAccent;
  static Color surfaceForDark(bool isDark) =>
      isDark ? darkSurface : lightSurface;
  static Color borderForDark(bool isDark) => isDark ? darkBorder : lightBorder;
  static Color mutedForDark(bool isDark) => isDark ? darkMuted : lightMuted;
  static Color primaryTextForDark(bool isDark) =>
      isDark ? Colors.white : Colors.black;
}
