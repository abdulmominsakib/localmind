---
name: shadcn_ui-popover
description: Show rich content in a popover with ShadPopover, ShadPopoverController; trigger button, toggle. Use when adding popovers, floating panels, or button-triggered overlay content in a Flutter shadcn_ui app.
---

# Shadcn UI — Popover

## Instructions

`ShadPopover` displays rich content in a portal, triggered by a button (or other trigger). Use a `ShadPopoverController()` to control open/close; call `popoverController.toggle` from the trigger. Pass `popover: (context) => ...` returning the overlay widget (e.g. a `SizedBox` with form fields); `child` is the trigger widget.

### Basic usage

```dart
final popoverController = ShadPopoverController();

// dispose: popoverController.dispose();

ShadPopover(
  controller: popoverController,
  popover: (context) => SizedBox(
    width: 288,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Dimensions', style: textTheme.h4),
        Text('Set the dimensions for the layer.', style: textTheme.p),
        const SizedBox(height: 4),
        // ... form rows with ShadInput, etc.
      ],
    ),
  ),
  child: ShadButton.outline(
    onPressed: popoverController.toggle,
    child: const Text('Open popover'),
  ),
)
```

Dispose the controller in `State.dispose`.
