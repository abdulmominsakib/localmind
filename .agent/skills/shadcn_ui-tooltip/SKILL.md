---
name: shadcn_ui-tooltip
description: Show tooltips on hover or focus with ShadTooltip; builder returns tooltip content, child is trigger. Use when adding hover/focus tooltips in a Flutter shadcn_ui app. Child must use ShadGestureDetector for hover (e.g. ShadButton).
---

# Shadcn UI — Tooltip

## Instructions

`ShadTooltip` shows a popup when the element receives keyboard focus or the mouse hovers over it. Use `builder: (context) => ...` to build the tooltip content (e.g. `Text('Add to library')`) and `child` for the trigger widget. Hover works only if the child uses a `ShadGestureDetector`; `ShadButton` and similar components implement it. For a plain widget (e.g. image), wrap the child with `ShadGestureDetector` so the tooltip shows on hover.

### Basic

```dart
ShadTooltip(
  builder: (context) => const Text('Add to library'),
  child: ShadButton.outline(
    child: const Text('Hover/Focus'),
    onPressed: () {},
  ),
)
```

For a non-interactive child (e.g. `Image`), wrap with `ShadGestureDetector`:

```dart
ShadTooltip(
  builder: (context) => const Text('Description'),
  child: ShadGestureDetector(
    child: Image.network('...'),
  ),
)
```
