---
name: shadcn_ui-separator
description: Visually separate content with ShadSeparator.horizontal and ShadSeparator.vertical; thickness, margin, radius. Use when adding dividers or visual separation in a Flutter shadcn_ui app.
---

# Shadcn UI — Separator

## Instructions

`ShadSeparator` visually or semantically separates content. Use `ShadSeparator.horizontal` for a horizontal line (e.g. between rows); use `ShadSeparator.vertical` for a vertical line (e.g. between columns). Optional: `thickness`, `margin`, `radius`, `color`.

### Horizontal

```dart
const ShadSeparator.horizontal(
  thickness: 4,
  margin: EdgeInsets.symmetric(horizontal: 20),
  radius: BorderRadius.all(Radius.circular(4)),
)
```

### Vertical

```dart
const ShadSeparator.vertical(
  thickness: 4,
  margin: EdgeInsets.symmetric(vertical: 20),
  radius: BorderRadius.all(Radius.circular(4)),
)
```
