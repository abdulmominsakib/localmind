---
name: shadcn_ui-dialog
description: Show modal dialogs with showShadDialog, ShadDialog and ShadDialog.alert; title, description, actions, child content. Use when adding modals, confirmations, or alert dialogs in a Flutter shadcn_ui app.
---

# Shadcn UI — Dialog

## Instructions

A modal dialog that interrupts the user. Use `showShadDialog(context: context, builder: ...)` and return a `ShadDialog` or `ShadDialog.alert`. Provide `title`, optional `description`, optional `actions` (list of widgets, e.g. buttons), and optional `child` for body content. Dismiss with `Navigator.of(context).pop(...)`.

### Standard dialog

```dart
showShadDialog(
  context: context,
  builder: (context) => ShadDialog(
    title: const Text('Edit Profile'),
    description: const Text(
      "Make changes to your profile here. Click save when you're done",
    ),
    actions: const [ShadButton(child: Text('Save changes'))],
    child: Container(
      width: 375,
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        spacing: 16,
        children: profile
            .map(
              (p) => Row(
                children: [
                  Expanded(
                    child: Text(
                      p.title,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.small,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 3,
                    child: ShadInput(initialValue: p.value),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    ),
  ),
);
```

### Alert dialog

Use `ShadDialog.alert` for confirmations; pass `actions` with Cancel and Continue (or similar) that call `Navigator.of(context).pop(false)` and `Navigator.of(context).pop(true)`.

```dart
showShadDialog(
  context: context,
  builder: (context) => ShadDialog.alert(
    title: const Text('Are you absolutely sure?'),
    description: const Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Text(
        'This action cannot be undone. This will permanently delete your account and remove your data from our servers.',
      ),
    ),
    actions: [
      ShadButton.outline(
        child: const Text('Cancel'),
        onPressed: () => Navigator.of(context).pop(false),
      ),
      ShadButton(
        child: const Text('Continue'),
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  ),
);
```
