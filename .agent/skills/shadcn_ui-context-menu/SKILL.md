---
name: shadcn_ui-context-menu
description: Show context menus on right-click with ShadContextMenuRegion, ShadContextMenuItem, submenus, dividers. Use when adding right-click menus, actions, or nested menu items in a Flutter shadcn_ui app.
---

# Shadcn UI — Context Menu

## Instructions

`ShadContextMenuRegion` wraps a `child` and shows a menu on right-click. Set `items` to a list of `ShadContextMenuItem` or `ShadContextMenuItem.inset`. Use `ShadContextMenuItem` with `items` for submenus; use `Divider(height: 8)` and `Padding` for sections and labels.

### Basic usage

```dart
ShadContextMenuRegion(
  constraints: const BoxConstraints(minWidth: 300),
  items: [
    const ShadContextMenuItem.inset(child: Text('Back')),
    const ShadContextMenuItem.inset(
      enabled: false,
      child: Text('Forward'),
    ),
    const ShadContextMenuItem.inset(child: Text('Reload')),
    const ShadContextMenuItem.inset(
      trailing: Icon(LucideIcons.chevronRight),
      items: [
        ShadContextMenuItem(child: Text('Save Page As...')),
        ShadContextMenuItem(child: Text('Create Shortcut...')),
        ShadContextMenuItem(child: Text('Developer Tools')),
        Divider(height: 8),
        ShadContextMenuItem(child: Text('Developer Tools')),
      ],
      child: Text('More Tools'),
    ),
    const Divider(height: 8),
    const ShadContextMenuItem(
      leading: Icon(LucideIcons.check),
      child: Text('Show Bookmarks Bar'),
    ),
    const ShadContextMenuItem.inset(child: Text('Show Full URLs')),
    const Divider(height: 8),
    Padding(
      padding: const EdgeInsets.fromLTRB(36, 8, 8, 8),
      child: Text('People', style: theme.textTheme.small),
    ),
    ShadContextMenuItem(
      leading: /* avatar or icon */,
      child: const Text('Pedro Duarte'),
    ),
    const ShadContextMenuItem.inset(child: Text('Colm Tuite')),
  ],
  child: Container(
    width: 300,
    height: 200,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      border: Border.all(color: theme.colorScheme.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Text('Right click here'),
  ),
)
```

Use `ShadContextMenuItem` for items with leading/trailing; `ShadContextMenuItem.inset` for indented items. Nest `items` for submenus.
