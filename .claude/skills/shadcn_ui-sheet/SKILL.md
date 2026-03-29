---
name: shadcn_ui-sheet
description: Show slide-out panels with showShadSheet and ShadSheet; side (top, right, bottom, left), title, description, actions, child. Use when adding side panels, drawers, or slide-over content in a Flutter shadcn_ui app.
---

# Shadcn UI — Sheet

## Instructions

Sheets extend the dialog pattern to display content from an edge of the screen. Use `showShadSheet(context: context, side: ShadSheetSide.*, builder: (context) => ShadSheet(...))`. `side` can be `ShadSheetSide.top`, `ShadSheetSide.right`, `ShadSheetSide.bottom`, or `ShadSheetSide.left`. Return a `ShadSheet` with optional `title`, `description`, `child` (body), and `actions`. Use `constraints` (e.g. `BoxConstraints(maxWidth: 512)` for left/right) to limit width or height.

### Basic (right side)

```dart
showShadSheet(
  side: ShadSheetSide.right,
  context: context,
  builder: (context) => ShadSheet(
    constraints: const BoxConstraints(maxWidth: 512),
    title: const Text('Edit Profile'),
    description: const Text(
      "Make changes to your profile here. Click save when you're done",
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    flex: 5,
                    child: ShadInput(initialValue: p.value),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    ),
    actions: const [
      ShadButton(child: Text('Save changes')),
    ],
  ),
);
```

### All sides

Use `side: ShadSheetSide.top`, `ShadSheetSide.bottom`, `ShadSheetSide.left`, or `ShadSheetSide.right` in `showShadSheet`. For left/right sheets pass `constraints: const BoxConstraints(maxWidth: 512)` to the `ShadSheet` so content doesn’t stretch full width.
