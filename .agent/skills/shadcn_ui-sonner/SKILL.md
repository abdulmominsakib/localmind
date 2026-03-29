---
name: shadcn_ui-sonner
description: Show toasts with ShadSonner and ShadToast; ShadSonner.of(context), show/hide, title, description, action. Use when showing toast notifications or ephemeral feedback in a Flutter shadcn_ui app.
---

# Shadcn UI — Sonner

## Instructions

Sonner is an opinionated toast component. Ensure `ShadSonner` is in the widget tree (e.g. in app builder). Get the controller with `ShadSonner.of(context)`. Call `sonner.show(ShadToast(...))` to show a toast; use `sonner.hide(id)` to dismiss. Each toast can have `id`, `title`, `description`, and optional `action` (e.g. an Undo button).

### Show toast

```dart
ShadButton.outline(
  child: const Text('Show Toast'),
  onPressed: () {
    final sonner = ShadSonner.of(context);
    final id = Random().nextInt(1000);
    final now = DateTime.now();
    sonner.show(
      ShadToast(
        id: id,
        title: const Text('Event has been created'),
        description: Text(DateFormat.yMd().add_jms().format(now)),
        action: ShadButton(
          child: const Text('Undo'),
          onPressed: () => sonner.hide(id),
        ),
      ),
    );
  },
)
```

Use a unique `id` per toast so you can hide it from the action button or elsewhere.
