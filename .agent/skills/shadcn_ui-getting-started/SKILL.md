---
name: shadcn_ui-getting-started
description: Install and set up Flutter Shadcn UI (shadcn_ui), configure ShadApp with Material or Cupertino, and use bundled packages. Use when starting a Flutter project with shadcn_ui, adding shadcn_ui dependency, or integrating Shadcn with MaterialApp/CupertinoApp.
---

# Shadcn UI for Flutter — Getting Started

## Instructions

### Installation

From the project root:

```bash
flutter pub add shadcn_ui
```

Or add to `pubspec.yaml`:

```yaml
dependencies:
  shadcn_ui: ^0.2.4  # use latest version
```

### Shadcn only (pure)

Use `ShadApp` for apps that use only Shadcn UI components (no Material/Cupertino):

```dart
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ShadApp();
  }
}
```

For declarative routing use `ShadApp.router`.

### Shadcn + Material

Use `ShadApp.custom` with `appBuilder` to wrap `MaterialApp` and use shadcn and Material together. Wrap the app with `ShadAppBuilder` in the builder:

```dart
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter/material.dart';

return ShadApp.custom(
  themeMode: ThemeMode.dark,
  darkTheme: ShadThemeData(
    brightness: Brightness.dark,
    colorScheme: const ShadSlateColorScheme.dark(),
  ),
  appBuilder: (context) {
    return MaterialApp(
      theme: Theme.of(context),
      builder: (context, child) {
        return ShadAppBuilder(child: child!);
      },
    );
  },
);
```

Use `MaterialApp.router` when using the Router API.

ShadApp builds a default Material `ThemeData` from `ShadThemeData` (fontFamily, extensions, colorScheme mapping, dividerTheme, textSelectionTheme, iconTheme, scrollbarTheme). Override with `Theme.of(context).copyWith(...)` without losing shadcn defaults.

### Shadcn + Cupertino

Use `CupertinoApp` inside `appBuilder` for Cupertino + shadcn:

```dart
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

return ShadApp.custom(
  themeMode: ThemeMode.dark,
  darkTheme: ShadThemeData(
    brightness: Brightness.dark,
    colorScheme: const ShadSlateColorScheme.dark(),
  ),
  appBuilder: (context) {
    return CupertinoApp(
      theme: CupertinoTheme.of(context),
      localizationsDelegates: const [
        DefaultMaterialLocalizations.delegate,
        DefaultCupertinoLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      builder: (context, child) {
        return ShadAppBuilder(child: child!);
      },
    );
  },
);
```

Use `CupertinoApp.router` for Router-based navigation. Override Cupertino theme with `CupertinoTheme.of(context).copyWith(...)`.

### Bundled packages

Shadcn UI re-exports these packages; no extra imports needed:

- **flutter_animate** — Animations; components accept `List<Effect>` for customization.
- **lucide_icons_flutter** — Icons via `LucideIcons` (e.g. `LucideIcons.activity`). Browse at https://lucide.dev/icons/
- **two_dimensional_scrollables** — Used by `ShadTable`.
- **intl** — i18n and message translation.
- **universal_image** — Multiple image formats; used by `ShadAvatar`.

### Submit your app

To add your app to the showcase: [open the GitHub template](https://github.com/nank1ro/flutter-shadcn-ui/issues/new?template=docs-add-app.yaml) and fill the form.
