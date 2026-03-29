---
name: shadcn_ui-radio-group
description: Use ShadRadioGroup and ShadRadio for single-choice options; ShadRadioGroupFormField for forms. Use when adding radio buttons or single-select options in a Flutter shadcn_ui app or ShadForm.
---

# Shadcn UI — Radio Group

## Instructions

`ShadRadioGroup<T>` is a set of radio buttons where at most one can be selected. Provide `items` as a list of `ShadRadio<T>` with `value` and `label`. Use `ShadRadioGroupFormField<T>` inside `ShadForm` with `id`, `label`, `items`, and `validator`.

### Standalone

```dart
ShadRadioGroup<String>(
  items: [
    ShadRadio(label: Text('Default'), value: 'default'),
    ShadRadio(label: Text('Comfortable'), value: 'comfortable'),
    ShadRadio(label: Text('Nothing'), value: 'nothing'),
  ],
)
```

### Form field

```dart
enum NotifyAbout { all, mentions, nothing; }

ShadRadioGroupFormField<NotifyAbout>(
  label: const Text('Notify me about'),
  items: NotifyAbout.values.map(
    (e) => ShadRadio(
      value: e,
      label: Text(e.message),
    ),
  ),
  validator: (v) {
    if (v == null) return 'You need to select a notification type.';
    return null;
  },
)
```
