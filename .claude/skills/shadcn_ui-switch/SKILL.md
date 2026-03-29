---
name: shadcn_ui-switch
description: Add toggle switches with ShadSwitch and ShadSwitchFormField; label, form validation. Use when adding on/off toggles or switch form fields in a Flutter shadcn_ui app or ShadForm.
---

# Shadcn UI — Switch

## Instructions

`ShadSwitch` is a control that toggles between checked and unchecked. Use `value` and `onChanged`; optional `label`. For forms use `ShadSwitchFormField` with `id`, `initialValue`, `inputLabel`, `inputSublabel`, `validator`.

### Standalone

```dart
ShadSwitch(
  value: value,
  onChanged: (v) => setState(() => value = v),
  label: const Text('Airplane Mode'),
)
```

### Form field

```dart
ShadSwitchFormField(
  id: 'terms',
  initialValue: false,
  inputLabel: const Text('I accept the terms and conditions'),
  onChanged: (v) {},
  inputSublabel: const Text('You agree to our Terms and Conditions'),
  validator: (v) {
    if (!v) return 'You must accept the terms and conditions';
    return null;
  },
)
```
