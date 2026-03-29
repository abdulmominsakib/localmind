---
name: shadcn_ui-input
description: Use ShadInput for text fields; placeholder, leading/trailing widgets, obscureText; ShadInputFormField for forms with validation. Use when adding text inputs, email/password fields, or form input fields in a Flutter shadcn_ui app.
---

# Shadcn UI — Input

## Instructions

`ShadInput` displays a form input or input-like component. Use `placeholder`, `initialValue`, `keyboardType`, `obscureText`; optional `leading` and `trailing` widgets. For forms use `ShadInputFormField` with `id`, `label`, `description`, `validator`.

### Basic

```dart
const ShadInput(
  placeholder: Text('Email'),
  keyboardType: TextInputType.emailAddress,
)
```

### With leading and trailing

Example: password with toggle visibility:

```dart
ShadInput(
  placeholder: const Text('Password'),
  obscureText: obscure,
  leading: Icon(LucideIcons.lock),
  trailing: SizedBox.square(
    dimension: 24,
    child: OverflowBox(
      maxWidth: 28,
      maxHeight: 28,
      child: ShadIconButton(
        iconSize: 20,
        padding: EdgeInsets.all(2),
        icon: Icon(obscure ? LucideIcons.eyeOff : LucideIcons.eye),
        onPressed: () => setState(() => obscure = !obscure),
      ),
    ),
  ),
)
```

### Form field

```dart
ShadInputFormField(
  id: 'username',
  label: const Text('Username'),
  placeholder: const Text('Enter your username'),
  description: const Text('This is your public display name.'),
  validator: (v) {
    if (v.length < 2) return 'Username must be at least 2 characters.';
    return null;
  },
)
```
