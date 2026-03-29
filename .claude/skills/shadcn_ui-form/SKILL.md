---
name: shadcn_ui-form
description: Build forms with ShadForm, validation, and form field values; use ShadInputFormField, ShadCheckboxFormField, ShadSelectFormField, ShadDatePickerFormField, etc. Use when building validated forms, getting form values, or using dot notation for nested fields in a Flutter shadcn_ui app.
---

# Shadcn UI — Form

## Instructions

`ShadForm` provides centralized form state, a single `Map<String, dynamic>` for all field values, and no need to manage individual controllers. Use a `GlobalKey<ShadFormState>` to call `saveAndValidate()` and read `value`. Give each form field an `id`; use `Shad*FormField` widgets (e.g. `ShadInputFormField`, `ShadCheckboxFormField`, `ShadSelectFormField`, `ShadDatePickerFormField`, `ShadTimePickerFormField`, `ShadRadioGroupFormField`) inside `ShadForm`.

### Basic form

```dart
final formKey = GlobalKey<ShadFormState>();

ShadForm(
  key: formKey,
  child: Column(
    children: [
      ShadInputFormField(
        id: 'username',
        label: const Text('Username'),
        placeholder: const Text('Enter your username'),
        description: const Text('This is your public display name.'),
        validator: (v) {
          if (v.length < 2) return 'Username must be at least 2 characters.';
          return null;
        },
      ),
      const SizedBox(height: 16),
      ShadButton(
        child: const Text('Submit'),
        onPressed: () {
          if (formKey.currentState!.saveAndValidate()) {
            print('value: ${formKey.currentState!.value}');
          } else {
            print('validation failed');
          }
        },
      ),
    ],
  ),
)
```

### Submit and get value

```dart
ShadButton(
  child: const Text('Submit'),
  onPressed: () {
    final formState = formKey.currentState!;
    if (!formState.saveAndValidate()) return;
    print('Form value: ${formState.value}');
  },
),
```

### Initial value

Set default values with `initialValue` on `ShadForm`:

```dart
ShadForm(
  initialValue: {
    'username': 'john_doe',
    'email': 'john_doe@example.com',
  },
  child: // form fields with matching ids
)
```

### Set field or full value

- Single field: `formKey.currentState!.setFieldValue('username', 'new_username');` (use `notifyField: false` to skip updating the field UI).
- Entire form: `formKey.currentState!.setValue({...});` (use `notifyFields: false` to skip updating fields).

### Value transformers

Use `fromValueTransformer` and `toValueTransformer` on form fields when the form value type differs from the field type (e.g. form stores string, field uses `DateTime`):

```dart
ShadDatePickerFormField(
  id: 'date',
  fromValueTransformer: (value) => DateTime.tryParse(value ?? ''),
  toValueTransformer: (date) =>
      date == null ? null : DateFormat('yyyy-MM-dd').format(date),
  ...
)
```

### Dot notation for nested values

Field IDs like `user.name` or `profile.settings.theme` produce nested maps in `formKey.currentState!.value`, e.g. `{'user': {'name': '...', 'email': '...'}}`. Provide `initialValue` as a nested map (not dot-notation keys). Customize separator with `fieldIdSeparator` (e.g. `'/'`); set `fieldIdSeparator: null` to disable nesting and keep flat keys.

## Additional resources

- Full details on initial value, setFieldValue/setValue, value transformers, and dot notation: [reference.md](reference.md)
- Form field examples: Checkbox, Switch, Input, Select, RadioGroup, DatePicker, TimePicker component docs/skills.
