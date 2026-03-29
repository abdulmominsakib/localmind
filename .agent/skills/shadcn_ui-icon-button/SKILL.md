---
name: shadcn_ui-icon-button
description: Use ShadIconButton and variants (primary, secondary, destructive, outline, ghost); loading state, gradient and shadow. Use when adding icon-only buttons or icon CTAs in a Flutter shadcn_ui app.
---

# Shadcn UI — Icon Button

## Instructions

`ShadIconButton` displays an icon button. Variants: default (primary), `ShadIconButton.secondary`, `ShadIconButton.destructive`, `ShadIconButton.outline`, `ShadIconButton.ghost`. Use `icon` and `onPressed`; optional `iconSize`, `padding`; support gradient and shadows.

### Variants

```dart
ShadIconButton(
  onPressed: () => print('Primary'),
  icon: const Icon(LucideIcons.rocket),
)

ShadIconButton.secondary(icon: const Icon(LucideIcons.rocket), onPressed: () {})

ShadIconButton.destructive(icon: const Icon(LucideIcons.rocket), onPressed: () {})

ShadIconButton.outline(icon: const Icon(LucideIcons.rocket), onPressed: () {})

ShadIconButton.ghost(icon: const Icon(LucideIcons.rocket), onPressed: () {})
```

### Loading

Use a small `CircularProgressIndicator` as `icon`:

```dart
ShadIconButton(
  icon: SizedBox.square(
    dimension: 16,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: ShadTheme.of(context).colorScheme.primaryForeground,
    ),
  ),
)
```

### Gradient and shadow

```dart
ShadIconButton(
  gradient: const LinearGradient(colors: [Colors.cyan, Colors.indigo]),
  shadows: [
    BoxShadow(
      color: Colors.blue.withValues(alpha: .4),
      spreadRadius: 4,
      blurRadius: 10,
      offset: const Offset(0, 2),
    ),
  ],
  icon: const Icon(LucideIcons.rocket),
)
```
