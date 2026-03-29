---
name: shadcn_ui-responsive
description: Use Shadcn UI breakpoints and responsive layout with ShadBreakpoints, ShadResponsiveBuilder, and context.breakpoint. Use when building responsive Flutter shadcn_ui layouts, adapting UI to screen size, or checking current breakpoint (tn, sm, md, lg, xl, xxl).
---

# Shadcn UI — Responsive

## Instructions

Responsiveness is built into shadcn_ui via `ShadThemeData.breakpoints`. Use `ShadResponsiveBuilder` or `context.breakpoint` to branch on the current breakpoint.

### Default breakpoints

```dart
ShadThemeData(
  breakpoints: ShadBreakpoints(
    tn: 0,    // tiny
    sm: 640,  // small
    md: 768,  // medium
    lg: 1024, // large
    xl: 1280, // extra large
    xxl: 1536, // extra extra large
  ),
);
```

### Current breakpoint

**With ShadResponsiveBuilder:**

```dart
ShadResponsiveBuilder(
  builder: (context, breakpoint) {
    final sm = breakpoint >= ShadTheme.of(context).breakpoints.sm;
    // ...
  },
),
```

**With context (equivalent):**

```dart
final sm = context.breakpoint >= ShadTheme.of(context).breakpoints.sm;
```

Use `>=` so that e.g. "sm" applies to small and larger viewports (Tailwind-style). Use `==` only when you need to match a single breakpoint.

### Sealed class switch

The breakpoint is a sealed type; you can switch on it:

```dart
ShadResponsiveBuilder(
  builder: (context, breakpoint) {
    return switch (breakpoint) {
      ShadBreakpointTN() => const Text('Tiny'),
      ShadBreakpointSM() => const Text('Small'),
      ShadBreakpointMD() => const Text('Medium'),
      ShadBreakpointLG() => const Text('Large'),
      ShadBreakpointXL() => const Text('Extra Large'),
      ShadBreakpointXXL() => const Text('Extra Extra Large'),
    };
  },
),
```
