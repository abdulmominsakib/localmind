---
name: shadcn_ui-theme
description: Configure Shadcn UI theme and color schemes (ShadThemeData, ShadColorScheme), override colors, use ShadColorScheme.fromName for theme switchers, and add custom colors. Use when theming a Flutter shadcn_ui app, changing color scheme, or adding custom theme colors.
---

# Shadcn UI — Theme Data

## Instructions

Theme and color scheme are defined by `ShadThemeData` and `ShadColorScheme`. Supported scheme names: blue, gray, green, neutral, orange, red, rose, slate, stone, violet, yellow, zinc.

### Basic usage

```dart
import 'package:shadcn_ui/shadcn_ui.dart';

return ShadApp(
  darkTheme: ShadThemeData(
    brightness: Brightness.dark,
    colorScheme: const ShadSlateColorScheme.dark(),
  ),
  child: ...,
);
```

### Override theme properties

Override specific properties of the color scheme or component themes:

```dart
ShadApp(
  darkTheme: ShadThemeData(
    brightness: Brightness.dark,
    colorScheme: const ShadSlateColorScheme.dark(
      background: Colors.blue,
    ),
    primaryButtonTheme: const ShadButtonTheme(
      backgroundColor: Colors.cyan,
    ),
  ),
  ...
);
```

For fully custom schemes, extend `ShadColorScheme` and pass all required properties.

### Theme switcher with ShadColorScheme.fromName

Use `ShadColorScheme.fromName` to let users change the color scheme:

```dart
final shadThemeColors = [
  'blue', 'gray', 'green', 'neutral', 'orange', 'red', 'rose',
  'slate', 'stone', 'violet', 'yellow', 'zinc',
];

final lightColorScheme = ShadColorScheme.fromName('blue');
final darkColorScheme = ShadColorScheme.fromName('slate', brightness: Brightness.dark);
```

Use a `ShadSelect<String>` (or similar) with these names and rebuild the app with the chosen scheme via your state management.

### Custom colors

Add custom colors via the `custom` parameter on the color scheme:

```dart
return ShadApp(
  theme: ShadThemeData(
    colorScheme: const ShadZincColorScheme.light(
      custom: {
        'myCustomColor': Color.fromARGB(255, 177, 4, 196),
      },
    ),
  ),
);
```

Access: `ShadTheme.of(context).colorScheme.custom['myCustomColor']!`

Or add an extension:

```dart
extension CustomColorExtension on ShadColorScheme {
  Color get myCustomColor => custom['myCustomColor']!;
}
```

Then use: `ShadTheme.of(context).colorScheme.myCustomColor`
