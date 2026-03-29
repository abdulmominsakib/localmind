---
name: shadcn_ui-toast
description: Show toasts with ShadToaster.of(context).show(ShadToast); title, description, action, ShadToast.destructive. Use when displaying temporary messages or feedback in a Flutter shadcn_ui app.
---

# Shadcn UI — Toast

## Instructions

Toasts are succinct temporary messages. Ensure a toaster is in the tree (e.g. `ShadToaster`). Get it with `ShadToaster.of(context)`. Call `toaster.show(ShadToast(...))` to show a toast; use `toaster.hide()` to dismiss (e.g. from an action button). Use `ShadToast` with optional `title`, `description`, and `action`. Use `ShadToast.destructive` for error-style toasts with a destructive action button (use `ShadDecoration` to style the action border).

### Simple

```dart
ShadToaster.of(context).show(
  const ShadToast(
    description: Text('Your message has been sent.'),
  ),
);
```

### With title

```dart
ShadToaster.of(context).show(
  const ShadToast(
    title: Text('Uh oh! Something went wrong'),
    description: Text('There was a problem with your request'),
  ),
);
```

### With action

```dart
ShadToaster.of(context).show(
  ShadToast(
    title: const Text('Uh oh! Something went wrong'),
    description: const Text('There was a problem with your request'),
    action: ShadButton.outline(
      child: const Text('Try again'),
      onPressed: () => ShadToaster.of(context).hide(),
    ),
  ),
);
```

### Destructive

```dart
final theme = ShadTheme.of(context);
ShadToaster.of(context).show(
  ShadToast.destructive(
    title: const Text('Uh oh! Something went wrong'),
    description: const Text('There was a problem with your request'),
    action: ShadButton.destructive(
      child: const Text('Try again'),
      decoration: ShadDecoration(
        border: ShadBorder.all(
          color: theme.colorScheme.destructiveForeground,
          width: 1,
        ),
      ),
      onPressed: () => ShadToaster.of(context).hide(),
    ),
  ),
);
```
