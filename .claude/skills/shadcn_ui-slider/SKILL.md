---
name: shadcn_ui-slider
description: Use ShadSlider for numeric input within a range; initialValue, max (and min). Use when adding range sliders or numeric selection in a Flutter shadcn_ui app.
---

# Shadcn UI — Slider

## Instructions

`ShadSlider` lets the user select a value from a range. Set `initialValue` and `max` (and optionally `min`). Use with state or a controller if you need to read the value on change.

### Basic

```dart
ShadSlider(
  initialValue: 33,
  max: 100,
)
```

Use callbacks or state management to react to value changes when needed.
