# Feature 08 — Design System

> **Phase:** 0–1  
> **Status:** Pending  
> **Depends on:** `00_project_setup`  

---

## Goal

Define the visual language and reusable components for LocalMind using ShadCN-inspired principles. Ensure a premium, dark-first, and highly polished user experience.

---

## Location

Design system components live in the `core/` layer since they are shared across all features:

```
core/
├── theme/
│   ├── app_theme.dart
│   ├── colors.dart
│   └── typography.dart
└── components/
    ├── app_button.dart
    ├── app_card.dart
    ├── app_text_field.dart
    ├── app_sheet.dart
    ├── app_dialog.dart
    └── app_loading_indicator.dart
```

---

## Core Principles

1. **High Contrast & Legibility**: Text must be readable against backgrounds. Use neutral grays, not pure black.
2. **Density**: Compact enough for information density, spacious enough for touch targets.
3. **Feedback**: Every interaction should have visual (hover, press) and tactile (haptic) feedback.
4. **Consistency**: Use the same spacing, border radius, and typography scales everywhere.
5. **ShadCN Aesthetic**: Clean borders, subtle surfaces, neutral colors with a single vibrant accent.

---

## Color Tokens

Location: `core/theme/colors.dart`

```dart
class AppColors {
  // --- Dark Theme (Default) ---
  static const Color darkBackground = Color(0xFF0A0A0A);
  static const Color darkSurface = Color(0xFF171717);
  static const Color darkBorder = Color(0xFF262626);
  static const Color darkPrimaryText = Color(0xFFFAFAFA);
  static const Color darkMutedText = Color(0xFFA1A1AA);
  static const Color darkAccent = Color(0xFF3B82F6);
  static const Color darkError = Color(0xFFEF4444);
  static const Color darkSuccess = Color(0xFF22C55E);

  // --- Light Theme ---
  static const Color lightBackground = Color(0xFFFAFAFA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE5E5E5);
  static const Color lightPrimaryText = Color(0xFF0A0A0A);
  static const Color lightMutedText = Color(0xFF71717A);
  static const Color lightAccent = Color(0xFF2563EB);
  static const Color lightError = Color(0xFFDC2626);
  static const Color lightSuccess = Color(0xFF16A34A);
}
```

---

## Typography

Location: `core/theme/typography.dart`

Font Family: `Inter`
Code Font: `Fira Code` or `JetBrains Mono`

```dart
class AppTypography {
  static const String fontFamily = 'Inter';
  static const String codeFontFamily = 'FiraCode';

  // Text styles using Flutter's TextTheme
  static TextTheme get textTheme => TextTheme(
    displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
    displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
    displaySmall: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
    headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
    titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
    bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.normal),
    bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
    bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
  );
}
```

---

## Theme Data

Location: `core/theme/app_theme.dart`

```dart
class AppTheme {
  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.darkBackground,
    colorScheme: ColorScheme.dark(
      surface: AppColors.darkSurface,
      primary: AppColors.darkAccent,
      error: AppColors.darkError,
    ),
    textTheme: AppTypography.textTheme.apply(
      bodyColor: AppColors.darkPrimaryText,
      displayColor: AppColors.darkPrimaryText,
    ),
    cardTheme: CardTheme(
      color: AppColors.darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppColors.darkBorder),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.darkBorder),
      ),
      filled: true,
      fillColor: AppColors.darkSurface,
    ),
    dividerTheme: DividerThemeData(
      color: AppColors.darkBorder,
      thickness: 1,
    ),
  );

  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.lightBackground,
    colorScheme: ColorScheme.light(
      surface: AppColors.lightSurface,
      primary: AppColors.lightAccent,
      error: AppColors.lightError,
    ),
    textTheme: AppTypography.textTheme.apply(
      bodyColor: AppColors.lightPrimaryText,
      displayColor: AppColors.lightPrimaryText,
    ),
    cardTheme: CardTheme(
      color: AppColors.lightSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppColors.lightBorder),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.lightBorder),
      ),
      filled: true,
      fillColor: AppColors.lightSurface,
    ),
    dividerTheme: DividerThemeData(
      color: AppColors.lightBorder,
      thickness: 1,
    ),
  );
}
```

---

## Components

Location: `core/components/`

### `app_button.dart`

```dart
enum AppButtonVariant { primary, outline, ghost, destructive }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.variant = AppButtonVariant.primary,
    this.isLoading = false,
    this.icon,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final AppButtonVariant variant;
  final bool isLoading;
  final Widget? icon;
}
```

**Variants:**
- **Primary**: Filled background (accent color), white text
- **Outline**: Transparent background, border, text color
- **Ghost**: Transparent, text only, hover state shows surface tone
- **Destructive**: Red accent for dangerous actions

### `app_card.dart`

```dart
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
}
```

- Background: `darkSurface`
- Border: `darkBorder`
- Border radius: `8px`
- Optional tap handler with ripple

### `app_text_field.dart`

```dart
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.hint,
    this.label,
    this.error,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.onSubmitted,
    this.obscureText = false,
    this.maxLines = 1,
  });

  final TextEditingController? controller;
  final String? hint;
  final String? label;
  final String? error;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool obscureText;
  final int maxLines;
}
```

- Border: `darkBorder`
- Background: transparent or `darkSurface` (focused)
- Error text below when provided

### `app_sheet.dart`

Bottom sheet wrapper with drag handle, padding, and standard close button.

### `app_dialog.dart`

Dialog wrapper with title, description, actions, and standard padding/radius.

### `app_loading_indicator.dart`

Minimalist circular progress indicator, accent color.

---

## Haptic Feedback

**Triggers:**
- **Light impact**: Toggling switches, expanding sections
- **Medium impact**: Sending message, deleting, saving
- **Success impact**: Successful server test, saving persona
- **Error impact**: Connection failure, invalid input

---

## Animations

Location: `core/utils/animations.dart` (or inline)

1. **Page Transitions**: `CupertinoPageRoute` or `FadeUpwardsPageTransitionsBuilder`
2. **Loading Spinners**: Minimalist circular, accent color
3. **Typing Indicator**: 3 bouncing dots
4. **Blinking Cursor**: For streaming text
5. **Hover States**: Scale `1.02x` or opacity change

---

## Spacing & Radius Constants

```dart
class AppSizes {
  static const double paddingXs = 4;
  static const double paddingSm = 8;
  static const double paddingMd = 16;
  static const double paddingLg = 24;
  static const double paddingXl = 32;

  static const double radiusSm = 4;
  static const double radiusMd = 8;
  static const double radiusLg = 12;
  static const double radiusXl = 16;

  static const double iconSm = 16;
  static const double iconMd = 24;
  static const double iconLg = 32;
}
```

---

## Acceptance Criteria

- [ ] `AppColors` and typography defined and integrated into `ThemeData`.
- [ ] Core components (Buttons, Inputs, Cards) created and used consistently.
- [ ] Haptic feedback map defined and applied to key interactions.
- [ ] Transitions and loading states feel premium and responsive.
- [ ] Dark and Light mode fully supported and verifiable via system toggle.
