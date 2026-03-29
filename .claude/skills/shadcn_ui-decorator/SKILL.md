---
name: shadcn_ui-decorator
description: Configure ShadDecoration and ShadDecorator for shadcn_ui components; customize secondary border and disableSecondaryBorder. Use when styling form controls, focus rings, or component borders in Flutter shadcn_ui.
---

# Shadcn UI — Decorator

## Instructions

Most shadcn_ui components use a `ShadDecoration` handled by `ShadDecorator` for borders, focus state, labels, and error/description styles.

### Default decoration

Default includes secondary border, focused ring, label/error/description styles and padding:

```dart
ShadDecoration(
  secondaryBorder: ShadBorder.all(
    padding: const EdgeInsets.all(4),
    width: 0,
  ),
  secondaryFocusedBorder: ShadBorder.all(
    width: 2,
    color: colorScheme.ring,
    radius: radius.add(radius / 2),
    padding: const EdgeInsets.all(2),
  ),
  labelStyle: textTheme.muted.copyWith(
    fontWeight: FontWeight.w500,
    color: colorScheme.foreground,
  ),
  errorStyle: textTheme.muted.copyWith(
    fontWeight: FontWeight.w500,
    color: colorScheme.destructive,
  ),
  labelPadding: const EdgeInsets.only(bottom: 8),
  descriptionStyle: textTheme.muted,
  descriptionPadding: const EdgeInsets.only(top: 8),
  errorPadding: const EdgeInsets.only(top: 8),
  errorLabelStyle: textTheme.muted.copyWith(
    fontWeight: FontWeight.w500,
    color: colorScheme.destructive,
  ),
);
```

### Disable secondary border

By default a secondary border is drawn around focusable components. To disable it and rely on a bolder primary border:

```dart
ShadThemeData(
  disableSecondaryBorder: true,
),
```

**Note:** Disabling the secondary border is not recommended; it can hurt accessibility because the focus ring helps users see which component is focused.
