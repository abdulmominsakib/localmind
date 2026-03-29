---
name: shadcn_ui-checkbox
description: Add checkboxes with ShadCheckbox and ShadCheckboxFormField; label, sublabel, form validation. Use when adding boolean toggles or terms acceptance in a Flutter shadcn_ui app or ShadForm.
---

# Shadcn UI — Checkbox

## Instructions

`ShadCheckbox` is a control that toggles between checked and unchecked. Use `value` and `onChanged`; optional `label` and `sublabel`. For forms use `ShadCheckboxFormField` with `id`, `validator`, and form state.

### Standalone

```dart
ShadCheckbox(
  value: value,
  onChanged: (v) => setState(() => value = v),
  label: const Text('Accept terms and conditions'),
  sublabel: const Text(
    'You agree to our Terms of Service and Privacy Policy.',
  ),
)
```

### Form field

```dart
ShadCheckboxFormField(
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
