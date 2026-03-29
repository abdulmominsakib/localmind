---
name: shadcn_ui-breadcrumb
description: Build breadcrumb navigation with ShadBreadcrumb, ShadBreadcrumbLink, ShadBreadcrumbDropdown, custom separator. Use when showing navigation path, hierarchy of links, or dropdown breadcrumb in a Flutter shadcn_ui app.
---

# Shadcn UI — Breadcrumb

## Instructions

`ShadBreadcrumb` displays the path to the current resource using a hierarchy of links. Children can be `ShadBreadcrumbLink`, `ShadBreadcrumbDropdown`, or plain widgets (e.g. `Text` for current page).

### Basic breadcrumb

```dart
ShadBreadcrumb(
  children: [
    ShadBreadcrumbLink(
      onPressed: () => print('Navigating to Home'),
      child: const Text('Home'),
    ),
    ShadBreadcrumbDropdown(
      items: [
        ShadBreadcrumbDropMenuItem(
          onPressed: () => print('Navigating to Documentation'),
          child: const Text('Documentation'),
        ),
        ShadBreadcrumbDropMenuItem(
          onPressed: () => print('Navigating to Themes'),
          child: const Text('Themes'),
        ),
      ],
      showDropdownArrow: false,
      child: ShadBreadcrumbEllipsis(),
    ),
    Text('Components'),
    Text('Breadcrumb'),
  ],
)
```

### Custom separator

Default separator is `>`. Override with `separator`:

```dart
ShadBreadcrumb(
  separator: const Icon(LucideIcons.slash),
  children: [
    ShadBreadcrumbLink(onPressed: () {}, child: const Text('Home')),
    ShadBreadcrumbLink(onPressed: () {}, child: const Text('Components')),
    Text('Breadcrumb'),
  ],
)
```

### Dropdown in breadcrumb

Use `ShadBreadcrumbDropdown` with `items` (list of `ShadBreadcrumbDropMenuItem`) and `child` (trigger widget). Use `ShadBreadcrumbEllipsis()` for an ellipsis trigger.
