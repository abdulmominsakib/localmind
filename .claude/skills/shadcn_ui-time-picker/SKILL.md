---
name: shadcn_ui-time-picker
description: Use ShadTimePicker and ShadTimePickerFormField for time selection; trailing widget, period variant. Use when adding time pickers or time form fields in a Flutter shadcn_ui app or ShadForm.
---

# Shadcn UI — Time Picker

## Instructions

`ShadTimePicker` is a time picker component. Optional `trailing` widget (e.g. icon). For forms use `ShadTimePickerFormField` with `label`, `description`, `onChanged`, and `validator`. Use `ShadTimePickerFormField.period` for AM/PM period selection.

### Standalone

```dart
const ShadTimePicker(
  trailing: Padding(
    padding: EdgeInsets.only(left: 8, top: 14),
    child: Icon(LucideIcons.clock4),
  ),
)
```

### Form field

```dart
ShadTimePickerFormField(
  label: const Text('Pick a time'),
  onChanged: print,
  description: const Text('The time of the day you want to pick'),
  validator: (v) => v == null ? 'A time is required' : null,
)
```

### Period (AM/PM)

```dart
ShadTimePickerFormField.period(
  label: const Text('Pick a time'),
  onChanged: print,
  description: const Text('The time of the day you want to pick'),
  validator: (v) => v == null ? 'A time is required' : null,
)
```
