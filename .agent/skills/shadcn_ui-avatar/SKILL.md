---
name: shadcn_ui-avatar
description: Display user avatars with ShadAvatar; image URL with optional placeholder. Use when showing user profile images or fallback initials in a Flutter shadcn_ui app.
---

# Shadcn UI — Avatar

## Instructions

`ShadAvatar` is an image with a placeholder for representing the user. Uses the `universal_image` package for multiple image formats.

### Basic usage

```dart
ShadAvatar(
  'https://example.com/avatar.png',
  placeholder: Text('CN'),
)
```

Pass the image URL as the first argument; `placeholder` is shown while loading or if the image fails (e.g. initials).
