---
name: shadcn_ui-alert
description: Show callout alerts with ShadAlert and ShadAlert.destructive; icon, title, description. Use when displaying warnings, errors, or important messages in a Flutter shadcn_ui app.
---

# Shadcn UI — Alert

## Instructions

`ShadAlert` displays a callout for user attention. Use default constructor for standard alerts, `ShadAlert.destructive` for errors or destructive actions.

### Primary / default

```dart
ShadAlert(
  icon: Icon(LucideIcons.terminal),
  title: Text('Heads up!'),
  description: Text('You can add components to your app using the cli.'),
)
```

### Destructive

```dart
ShadAlert.destructive(
  icon: Icon(LucideIcons.circleAlert),
  title: Text('Error'),
  description: Text('Your session has expired. Please log in again.'),
)
```
