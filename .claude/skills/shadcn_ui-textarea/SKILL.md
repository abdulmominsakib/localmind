---
name: shadcn_ui-textarea
description: Use ShadTextarea for multi-line text input; placeholder. ShadTextareaFormField for forms with validation. Use when adding multi-line text fields or bio/description inputs in a Flutter shadcn_ui app.
---

# Shadcn UI — Textarea

## Instructions

`ShadTextarea` displays a multi-line form field or textarea-like component. Use `placeholder` and optional `initialValue`. For forms use `ShadTextareaFormField` with `id`, `label`, `placeholder`, `description`, and `validator`.

### Standalone

```dart
const ShadTextarea(
  placeholder: Text('Type your message here'),
)
```

### Form field

```dart
ShadTextareaFormField(
  id: 'bio',
  label: const Text('Bio'),
  placeholder: const Text('Tell us a little bit about yourself'),
  description: const Text(
    'You can @mention other users and organizations.'),
  validator: (v) {
    if (v.length < 10) return 'Bio must be at least 10 characters.';
    return null;
  },
)
```
