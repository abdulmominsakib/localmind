---
name: shadcn_ui-resizable
description: Build resizable panel layouts with ShadResizablePanelGroup and ShadResizablePanel; horizontal/vertical axis, defaultSize, minSize, maxSize, showHandle. Use when adding resizable split panes or panel groups in a Flutter shadcn_ui app.
---

# Shadcn UI — Resizable

## Instructions

`ShadResizablePanelGroup` contains `ShadResizablePanel` children. Each panel has `id`, `defaultSize` (fraction 0–1), optional `minSize` and `maxSize`, and `child`. Use `axis: Axis.vertical` for vertical splits. Nest `ShadResizablePanelGroup` inside a panel for nested layouts. Set `showHandle: true` to show the resize handle; optional `handleIcon` or `handleIconSrc` to customize. Double-click the handle to reset to default size.

### Basic horizontal

```dart
ShadResizablePanelGroup(
  children: [
    ShadResizablePanel(
      id: 0,
      defaultSize: .5,
      minSize: .2,
      maxSize: .8,
      child: Center(child: Text('One', style: theme.textTheme.large)),
    ),
    ShadResizablePanel(
      id: 1,
      defaultSize: .5,
      child: ShadResizablePanelGroup(
        axis: Axis.vertical,
        children: [
          ShadResizablePanel(
            id: 0,
            defaultSize: .3,
            child: Center(child: Text('Two', style: theme.textTheme.large)),
          ),
          ShadResizablePanel(
            id: 1,
            defaultSize: .7,
            child: Align(child: Text('Three', style: theme.textTheme.large)),
          ),
        ],
      ),
    ),
  ],
)
```

### Vertical

```dart
ShadResizablePanelGroup(
  axis: Axis.vertical,
  children: [
    ShadResizablePanel(
      id: 0,
      defaultSize: 0.3,
      minSize: 0.1,
      child: Center(child: Text('Header', style: theme.textTheme.large)),
    ),
    ShadResizablePanel(
      id: 1,
      defaultSize: 0.7,
      minSize: 0.1,
      child: Center(child: Text('Footer', style: theme.textTheme.large)),
    ),
  ],
)
```

### With visible handle

```dart
ShadResizablePanelGroup(
  showHandle: true,
  children: [
    ShadResizablePanel(id: 0, defaultSize: .5, minSize: .2, child: ...),
    ShadResizablePanel(id: 1, defaultSize: .5, minSize: .2, child: ...),
  ],
)
```

Wrap the group in a bordered container (e.g. `DecoratedBox` + `ClipRRect` with `theme.radius`) for a clean look.
