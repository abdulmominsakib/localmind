# Riverpod Refs — Reference

## ref.watch

Subscribes to the provider; the current widget/provider rebuilds when the value changes. Use in build. Providers can watch other providers to compose state.

## ref.read

Returns current value without subscribing. Use in event handlers (onPressed, callbacks). Do not use read instead of watch to "optimize" — use watch or use select to limit rebuilds.

## ref.listen

Registers a one-off listener for side effects (navigation, dialogs, logging). Signature: `(previous, next) => ...`. Safe in build. For listening outside build (e.g. initState), use **ref.listenManual** and store the subscription to cancel later.

## ref.invalidate / ref.refresh

- **invalidate(provider)** — Discard state; next read will recompute.
- **refresh(provider)** — invalidate + read in one call; returns the new value.

## ref.select

Reduce rebuilds by watching only a part of the state: `ref.watch(provider.select((value) => value.someField))`. Rebuilds only when the selected value changes (by ==).

## WidgetRef.listenManual

When you need to listen from initState or outside build, use listenManual and call the returned subscription's `close()` in dispose.

## Ref vs WidgetRef

Ref is used inside providers; WidgetRef is used inside widgets. There is no shared interface by design — keep logic in providers and call notifier methods from the UI so only Ref is needed in business logic.
