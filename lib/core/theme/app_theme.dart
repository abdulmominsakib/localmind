import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'colors.dart';
import 'typography.dart';

enum AppThemeType {
  system,
  light,
  dark,
  claude
}

class AppTheme {
  static ShadThemeData get darkShadTheme => ShadThemeData(
    brightness: Brightness.dark,
    colorScheme: const ShadSlateColorScheme.dark(
      background: AppColors.darkBackground,
      primary: AppColors.darkAccent,
      primaryForeground: AppColors.darkBackground,
      secondary: AppColors.darkSurface,
      secondaryForeground: AppColors.darkPrimaryText,
      border: AppColors.darkBorder,
      card: AppColors.darkSurface,
      cardForeground: AppColors.darkPrimaryText,
      muted: AppColors.darkSurface,
      mutedForeground: AppColors.darkMutedText,
    ),
  );

  static ShadThemeData get lightShadTheme => ShadThemeData(
    brightness: Brightness.light,
    colorScheme: const ShadSlateColorScheme.light(
      background: AppColors.lightBackground,
      primary: AppColors.lightAccent,
      primaryForeground: Colors.white,
      secondary: AppColors.lightSurface,
      secondaryForeground: AppColors.lightPrimaryText,
      border: AppColors.lightBorder,
      card: AppColors.lightSurface,
      cardForeground: AppColors.lightPrimaryText,
      muted: AppColors.lightSurface,
      mutedForeground: AppColors.lightMutedText,
    ),
  );

  static ShadThemeData get claudeShadTheme => ShadThemeData(
    brightness: Brightness.light,
    colorScheme: const ShadSlateColorScheme.light(
      background: AppColors.claudeBackground,
      primary: AppColors.claudeAccent,
      primaryForeground: Colors.white,
      secondary: AppColors.claudeSurface,
      secondaryForeground: AppColors.claudePrimaryText,
      border: AppColors.claudeBorder,
      card: AppColors.claudeSurface,
      cardForeground: AppColors.claudePrimaryText,
      muted: AppColors.claudeSurface,
      mutedForeground: AppColors.claudeMutedText,
    ),
    radius: const BorderRadius.all(Radius.circular(12)),
  );

  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.darkBackground,
    colorScheme: const ColorScheme.dark(
      surface: AppColors.darkSurface,
      primary: AppColors.darkAccent,
      onPrimary: AppColors.darkBackground, // White accent, black text
      secondary: AppColors.darkAccent,
      onSecondary: AppColors.darkBackground,
      error: AppColors.error,
      onSurface: AppColors.darkPrimaryText,
      outline: AppColors.darkBorder,
    ),
    textTheme: AppTypography.darkTextTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkBackground,
      foregroundColor: AppColors.darkPrimaryText,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: AppColors.darkSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.darkBorder),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.darkBorder,
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.darkBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.darkAccent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.darkAccent,
        foregroundColor: AppColors.darkBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.darkPrimaryText,
        side: const BorderSide(color: AppColors.darkBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.darkPrimaryText,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.darkSurface,
      contentTextStyle: AppTypography.darkTextTheme.bodyMedium,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.darkBackground,
      indicatorColor: AppColors.darkSurface,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(color: AppColors.darkPrimaryText, fontSize: 12, fontWeight: FontWeight.w600);
        }
        return const TextStyle(color: AppColors.darkMutedText, fontSize: 12, fontWeight: FontWeight.w500);
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColors.darkPrimaryText);
        }
        return const IconThemeData(color: AppColors.darkMutedText);
      }),
    ),
  );

  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.lightBackground,
    colorScheme: const ColorScheme.light(
      surface: AppColors.lightSurface,
      primary: AppColors.lightAccent,
      onPrimary: Colors.white,
      secondary: AppColors.lightAccent,
      onSecondary: Colors.white,
      error: AppColors.error,
      onSurface: AppColors.lightPrimaryText,
      outline: AppColors.lightBorder,
    ),
    textTheme: AppTypography.lightTextTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.lightBackground,
      foregroundColor: AppColors.lightPrimaryText,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: AppColors.lightSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.lightBorder),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.lightBorder,
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.lightSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.lightBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.lightBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.lightAccent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.lightAccent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.lightPrimaryText,
        side: const BorderSide(color: AppColors.lightBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.lightSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.lightSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.lightBackground,
      indicatorColor: AppColors.lightSurface,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(color: AppColors.lightPrimaryText, fontSize: 12, fontWeight: FontWeight.w600);
        }
        return const TextStyle(color: AppColors.lightMutedText, fontSize: 12, fontWeight: FontWeight.w500);
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColors.lightPrimaryText);
        }
        return const IconThemeData(color: AppColors.lightMutedText);
      }),
    ),
  );

  static ThemeData get claudeTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.claudeBackground,
    colorScheme: const ColorScheme.light(
      surface: AppColors.claudeSurface,
      primary: AppColors.claudeAccent,
      onPrimary: Colors.white,
      secondary: AppColors.claudeAccent,
      onSecondary: Colors.white,
      error: AppColors.error,
      onSurface: AppColors.claudePrimaryText,
      outline: AppColors.claudeBorder,
    ),
    textTheme: AppTypography.claudeTextTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.claudeBackground,
      foregroundColor: AppColors.claudePrimaryText,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: AppColors.claudeSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.claudeBorder),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.claudeBorder,
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.claudeSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.claudeBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.claudeBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.claudeAccent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.claudeAccent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.claudePrimaryText,
        side: const BorderSide(color: AppColors.claudeBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8), // Secondary buttons are less rounded
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.claudeSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.claudeSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.claudeBackground,
      indicatorColor: AppColors.claudeSurface,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(color: AppColors.claudePrimaryText, fontSize: 12, fontWeight: FontWeight.w600);
        }
        return const TextStyle(color: AppColors.claudeSecondaryText, fontSize: 12, fontWeight: FontWeight.w500);
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColors.claudePrimaryText);
        }
        return const IconThemeData(color: AppColors.claudeSecondaryText);
      }),
    ),
  );

}
