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

  static TextTheme get claudeTextTheme {
    return GoogleFonts.loraTextTheme(
      const TextTheme(
        displayLarge: TextStyle(
          color: AppColors.claudePrimaryText,
          fontSize: 64,
          fontWeight: FontWeight.w500,
          height: 1.1,
        ),
        displayMedium: TextStyle(
          color: AppColors.claudePrimaryText,
          fontSize: 52,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
        displaySmall: TextStyle(
          color: AppColors.claudePrimaryText,
          fontSize: 36,
          fontWeight: FontWeight.w500,
          height: 1.3,
        ),
        headlineLarge: TextStyle(
          color: AppColors.claudePrimaryText,
          fontSize: 32,
          fontWeight: FontWeight.w500,
          height: 1.1,
        ),
        headlineMedium: TextStyle(
          color: AppColors.claudePrimaryText,
          fontSize: 25,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
        headlineSmall: TextStyle(
          color: AppColors.claudePrimaryText,
          fontSize: 20,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
        titleLarge: TextStyle(
          color: AppColors.claudePrimaryText,
          fontSize: 17,
          fontWeight: FontWeight.w500,
          height: 1.1,
        ),
      ),
    ).copyWith(
      bodyLarge: GoogleFonts.inter(
        color: AppColors.claudePrimaryText,
        fontSize: 17,
        fontWeight: FontWeight.w400,
        height: 1.6,
      ),
      bodyMedium: GoogleFonts.inter(
        color: AppColors.claudePrimaryText,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.6,
      ),
      bodySmall: GoogleFonts.inter(
        color: AppColors.claudeSecondaryText,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.6,
      ),
      labelLarge: GoogleFonts.inter(
        color: AppColors.claudePrimaryText,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.4,
      ),
      labelMedium: GoogleFonts.inter(
        color: AppColors.claudeSecondaryText,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.4,
        letterSpacing: 0.12,
      ),
      labelSmall: GoogleFonts.inter(
        color: AppColors.claudeMutedText,
        fontSize: 10,
        fontWeight: FontWeight.w500,
        height: 1.6,
        letterSpacing: 0.5,
      ),
    );
  }
}
