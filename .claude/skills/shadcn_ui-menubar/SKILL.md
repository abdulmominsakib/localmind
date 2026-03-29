---
name: shadcn_ui-menubar
description: Build desktop-style menubars with ShadMenubar and ShadMenubarItem; nested items, ShadContextMenuItem, dividers. Use when adding a persistent top menu (File, Edit, View, etc.) in a Flutter shadcn_ui app.
---

# Shadcn UI — Menubar

## Instructions

`ShadMenubar` is a visually persistent menu (e.g. File, Edit, View). Each top-level entry is a `ShadMenubarItem` with `child` (label) and `items` (list of menu entries). Use `ShadContextMenuItem` and `ShadContextMenuItem.inset` for entries; use `ShadSeparator.horizontal` or `Divider(height: 8)` for dividers. Nest `ShadContextMenuItem` with `items` for submenus; use `trailing: Icon(LucideIcons.chevronRight)` on parent. Set `enabled: false` to disable an item.

### Structure

```dart
ShadMenubar(
  items: [
    ShadMenubarItem(
      items: [
        const ShadContextMenuItem(child: Text('New Tab')),
        const ShadContextMenuItem(child: Text('New Window')),
        const ShadContextMenuItem(
          enabled: false,
          child: Text('New Incognito Window'),
        ),
        divider,
        const ShadContextMenuItem(
          trailing: Icon(LucideIcons.chevronRight),
          items: [
            ShadContextMenuItem(child: Text('Email Link')),
            ShadContextMenuItem(child: Text('Messages')),
          ],
          child: Text('Share'),
        ),
        divider,
        const ShadContextMenuItem(child: Text('Print...')),
      ],
      child: const Text('File'),
    ),
    ShadMenubarItem(
      items: [
        const ShadContextMenuItem(child: Text('Undo')),
        const ShadContextMenuItem(child: Text('Redo')),
        divider,
        ShadContextMenuItem(
          trailing: const Icon(LucideIcons.chevronRight),
          items: [
            const ShadContextMenuItem(child: Text('Find...')),
            const ShadContextMenuItem(child: Text('Find Next')),
          ],
          child: const Text('Find'),
        ),
        divider,
        const ShadContextMenuItem(child: Text('Cut')),
        const ShadContextMenuItem(child: Text('Copy')),
        const ShadContextMenuItem(child: Text('Paste')),
      ],
      child: const Text('Edit'),
    ),
    ShadMenubarItem(
      items: [
        const ShadContextMenuItem.inset(child: Text('Reload')),
        const ShadContextMenuItem.inset(child: Text('Toggle Full Screen')),
      ],
      child: const Text('View'),
    ),
  ],
)
```

Create a reusable `divider` with `ShadSeparator.horizontal(margin: const EdgeInsets.symmetric(vertical: 4), color: theme.colorScheme.muted)`.
