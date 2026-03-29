---
name: shadcn_ui-card
description: Build cards with ShadCard; title, description, footer, and child content. Use when creating content cards, project cards, or notification panels in a Flutter shadcn_ui app.
---

# Shadcn UI — Card

## Instructions

`ShadCard` displays a card with optional header (title, description), body (`child`), and footer. Use `width` to constrain width.

### Basic card

```dart
final theme = ShadTheme.of(context);
ShadCard(
  width: 350,
  title: Text('Create project', style: theme.textTheme.h4),
  description: const Text('Deploy your new project in one-click.'),
  footer: Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      ShadButton.outline(child: const Text('Cancel'), onPressed: () {}),
      ShadButton(child: const Text('Deploy'), onPressed: () {}),
    ],
  ),
  child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Name'),
        const SizedBox(height: 6),
        const ShadInput(placeholder: Text('Name of your project')),
        const SizedBox(height: 16),
        const Text('Framework'),
        const SizedBox(height: 6),
        ShadSelect<String>(
          placeholder: const Text('Select'),
          options: frameworks.entries
              .map((e) => ShadOption(value: e.key, child: Text(e.value)))
              .toList(),
          selectedOptionBuilder: (context, value) => Text(frameworks[value]!),
          onChanged: (value) {},
        ),
      ],
    ),
  ),
)
```

Title and description are optional. Footer can be any widget (e.g. buttons). Put main content in `child`.
