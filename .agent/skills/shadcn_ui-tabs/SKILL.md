---
name: shadcn_ui-tabs
description: Build tabbed UIs with ShadTabs and ShadTab; value, tabs (content + child label), tabBarConstraints, contentConstraints. Use when adding tab panels or layered sections in a Flutter shadcn_ui app.
---

# Shadcn UI — Tabs

## Instructions

`ShadTabs<T>` displays layered sections (tab panels) one at a time. Provide `value` (currently selected tab value), `tabs` (list of `ShadTab<T>`), and optional `tabBarConstraints` and `contentConstraints`. Each `ShadTab` has `value`, `child` (tab label), and `content` (panel widget).

### Basic

```dart
ShadTabs<String>(
  value: 'account',
  tabBarConstraints: const BoxConstraints(maxWidth: 400),
  contentConstraints: const BoxConstraints(maxWidth: 400),
  tabs: [
    ShadTab(
      value: 'account',
      content: ShadCard(
        title: const Text('Account'),
        description: const Text(
          "Make changes to your account here. Click save when you're done."),
        footer: const ShadButton(child: Text('Save changes')),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            ShadInputFormField(label: const Text('Name'), initialValue: 'Ale'),
            const SizedBox(height: 8),
            ShadInputFormField(label: const Text('Username'), initialValue: 'nank1ro'),
            const SizedBox(height: 16),
          ],
        ),
      ),
      child: const Text('Account'),
    ),
    ShadTab(
      value: 'password',
      content: ShadCard(
        title: const Text('Password'),
        description: const Text(
          "Change your password here. After saving, you'll be logged out."),
        footer: const ShadButton(child: Text('Save password')),
        child: Column(
          children: [
            const SizedBox(height: 16),
            ShadInputFormField(label: const Text('Current password'), obscureText: true),
            const SizedBox(height: 8),
            ShadInputFormField(label: const Text('New password'), obscureText: true),
            const SizedBox(height: 16),
          ],
        ),
      ),
      child: const Text('Password'),
    ),
  ],
)
```

Use state or a controller to change `value` when the user switches tabs if needed.
