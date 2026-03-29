---
name: shadcn_ui-badge
description: Display badges with ShadBadge; primary, secondary, destructive, outline variants. Use when showing tags, status labels, or count indicators in a Flutter shadcn_ui app.
---

# Shadcn UI — Badge

## Instructions

`ShadBadge` displays a badge or badge-like component. Variants: default (primary), `ShadBadge.secondary`, `ShadBadge.destructive`, `ShadBadge.outline`.

### Variants

```dart
ShadBadge(child: const Text('Primary'))

ShadBadge.secondary(child: const Text('Secondary'))

ShadBadge.destructive(child: const Text('Destructive'))

ShadBadge.outline(child: const Text('Outline'))
```

Wrap any `child` (typically `Text`) with the desired constructor.
