---
name: shadcn_ui-progress
description: Show progress with ShadProgress; determinate (value 0–1) or indeterminate. Use when displaying task completion or loading progress in a Flutter shadcn_ui app.
---

# Shadcn UI — Progress

## Instructions

`ShadProgress` displays completion progress, typically as a progress bar. Use determinate mode with a `value` (0.0–1.0); omit `value` for indeterminate (animated) progress.

### Determinate

```dart
ConstrainedBox(
  constraints: BoxConstraints(
    maxWidth: MediaQuery.sizeOf(context).width * 0.6,
  ),
  child: const ShadProgress(value: 0.5),
)
```

### Indeterminate

```dart
const ShadProgress()
```

Constrain width with `ConstrainedBox` or parent layout as needed.
