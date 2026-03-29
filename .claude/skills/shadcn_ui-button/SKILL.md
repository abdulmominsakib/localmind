---
name: shadcn_ui-button
description: Use Shadcn UI buttons (ShadButton variants: primary, secondary, destructive, outline, ghost, link); leading icon, loading state, gradient and shadow. Use when adding buttons, CTAs, or button-style widgets in a Flutter shadcn_ui app.
---

# Shadcn UI — Button

## Instructions

`ShadButton` displays a button or component that looks like a button. Variants: default (primary), `ShadButton.secondary`, `ShadButton.destructive`, `ShadButton.outline`, `ShadButton.ghost`, `ShadButton.link`. Use `leading` (and optionally `trailing`) for icons; support gradient and shadows for custom styling.

### Variants

```dart
ShadButton(child: const Text('Primary'), onPressed: () {})

ShadButton.secondary(child: const Text('Secondary'), onPressed: () {})

ShadButton.destructive(child: const Text('Destructive'), onPressed: () {})

ShadButton.outline(child: const Text('Outline'), onPressed: () {})

ShadButton.ghost(child: const Text('Ghost'), onPressed: () {})

ShadButton.link(child: const Text('Link'), onPressed: () {})
```

### Text and icon

```dart
ShadButton(
  onPressed: () {},
  leading: const Icon(LucideIcons.mail),
  child: const Text('Login with Email'),
)
```

### Loading state

Use `leading` with a small `CircularProgressIndicator`:

```dart
ShadButton(
  onPressed: () {},
  leading: SizedBox.square(
    dimension: 16,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: ShadTheme.of(context).colorScheme.primaryForeground,
    ),
  ),
  child: const Text('Please wait'),
)
```

### Gradient and shadow

```dart
ShadButton(
  onPressed: () {},
  gradient: const LinearGradient(colors: [Colors.cyan, Colors.indigo]),
  shadows: [
    BoxShadow(
      color: Colors.blue.withValues(alpha:.4),
      spreadRadius: 4,
      blurRadius: 10,
      offset: const Offset(0, 2),
    ),
  ],
  child: const Text('Gradient with Shadow'),
)
```
