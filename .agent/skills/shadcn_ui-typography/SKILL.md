---
name: shadcn_ui-typography
description: Apply Shadcn UI text styles (h1, h2, p, lead, muted, etc.), set custom font family or Google Fonts, and extend ShadTextTheme with custom styles. Use when styling text, headings, or paragraphs in a Flutter shadcn_ui app or when changing the default font.
---

# Shadcn UI — Typography

## Instructions

Use `ShadTheme.of(context).textTheme` for consistent text styles. Default font family is Geist.

### Text style names

- **h1Large**, **h1**, **h2**, **h3**, **h4** — Headings
- **p** — Body paragraph
- **blockquote** — Quote style
- **table** — Table header/cell text
- **list** — List item text
- **lead** — Lead/subtitle
- **large** — Large body
- **small** — Small/caption
- **muted** — Muted/secondary text

### Examples

```dart
Text(
  'Taxing Laughter: The Joke Tax Chronicles',
  style: ShadTheme.of(context).textTheme.h1,
)

Text(
  'The king, seeing how much happier his subjects were...',
  style: ShadTheme.of(context).textTheme.p,
)

Text(
  'Email address',
  style: ShadTheme.of(context).textTheme.small,
)

Text(
  'Enter your email address.',
  style: ShadTheme.of(context).textTheme.muted,
)
```

### Custom font family

1. Add font assets (e.g. under `/fonts`) and register in `pubspec.yaml`:

```yaml
flutter:
  fonts:
    - family: UbuntuMono
      fonts:
        - asset: fonts/UbuntuMono-Regular.ttf
        - asset: fonts/UbuntuMono-Italic.ttf
          style: italic
        - asset: fonts/UbuntuMono-Bold.ttf
          weight: 700
```

2. Set `ShadTextTheme` in `ShadThemeData`:

```dart
return ShadApp(
  theme: ShadThemeData(
    brightness: Brightness.light,
    colorScheme: const ShadZincColorScheme.light(),
    textTheme: ShadTextTheme(
      colorScheme: const ShadZincColorScheme.light(),
      family: 'UbuntuMono',
    ),
  ),
  ...
);
```

### Google Fonts

Install `google_fonts`, then:

```dart
theme: ShadThemeData(
  brightness: Brightness.light,
  colorScheme: const ShadZincColorScheme.light(),
  textTheme: ShadTextTheme.fromGoogleFont(GoogleFonts.poppins),
),
```

### Custom text styles

Extend `ShadTextTheme` with the `custom` parameter:

```dart
textTheme: ShadTextTheme(
  custom: {
    'myCustomStyle': const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: Colors.blue,
    ),
  },
),
```

Access: `ShadTheme.of(context).textTheme.custom['myCustomStyle']!`

Or define an extension on `ShadTextTheme` and use `ShadTheme.of(context).textTheme.myCustomStyle`.
