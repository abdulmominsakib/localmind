import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

class AppTypography {
  static const String fontFamily = 'Inter';
  static const String codeFontFamily = 'FiraCode';

  static TextTheme get darkTextTheme {
    return GoogleFonts.interTextTheme(
      const TextTheme(
        displayLarge: TextStyle(color: AppColors.darkPrimaryText),
        displayMedium: TextStyle(color: AppColors.darkPrimaryText),
        displaySmall: TextStyle(color: AppColors.darkPrimaryText),
        headlineLarge: TextStyle(color: AppColors.darkPrimaryText),
        headlineMedium: TextStyle(color: AppColors.darkPrimaryText),
        headlineSmall: TextStyle(color: AppColors.darkPrimaryText),
        titleLarge: TextStyle(color: AppColors.darkPrimaryText),
        titleMedium: TextStyle(color: AppColors.darkPrimaryText),
        titleSmall: TextStyle(color: AppColors.darkPrimaryText),
        bodyLarge: TextStyle(color: AppColors.darkPrimaryText),
        bodyMedium: TextStyle(color: AppColors.darkPrimaryText),
        bodySmall: TextStyle(color: AppColors.darkMutedText),
        labelLarge: TextStyle(color: AppColors.darkPrimaryText),
        labelMedium: TextStyle(color: AppColors.darkPrimaryText),
        labelSmall: TextStyle(color: AppColors.darkMutedText),
      ),
    );
  }

  static TextTheme get lightTextTheme {
    return GoogleFonts.interTextTheme(
      const TextTheme(
        displayLarge: TextStyle(color: AppColors.lightPrimaryText),
        displayMedium: TextStyle(color: AppColors.lightPrimaryText),
        displaySmall: TextStyle(color: AppColors.lightPrimaryText),
        headlineLarge: TextStyle(color: AppColors.lightPrimaryText),
        headlineMedium: TextStyle(color: AppColors.lightPrimaryText),
        headlineSmall: TextStyle(color: AppColors.lightPrimaryText),
        titleLarge: TextStyle(color: AppColors.lightPrimaryText),
        titleMedium: TextStyle(color: AppColors.lightPrimaryText),
        titleSmall: TextStyle(color: AppColors.lightPrimaryText),
        bodyLarge: TextStyle(color: AppColors.lightPrimaryText),
        bodyMedium: TextStyle(color: AppColors.lightPrimaryText),
        bodySmall: TextStyle(color: AppColors.lightMutedText),
        labelLarge: TextStyle(color: AppColors.lightPrimaryText),
        labelMedium: TextStyle(color: AppColors.lightPrimaryText),
        labelSmall: TextStyle(color: AppColors.lightMutedText),
      ),
    );
  }
}
