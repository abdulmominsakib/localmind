# Riverpod Providers — Reference

## Provider type summary

- **Provider** — sync, unmodifiable. Return type `T`.
- **FutureProvider** — async, unmodifiable. Return type `Future<T>`.
- **StreamProvider** — stream, unmodifiable. Return type `Stream<T>`.
- **NotifierProvider** — sync, modifiable. Notifier extends `Notifier<T>`, `build()` returns `T`.
- **AsyncNotifierProvider** — async, modifiable. Notifier extends `AsyncNotifier<T>`, `build()` returns `Future<T>`.
- **StreamNotifierProvider** — stream, modifiable. Notifier extends `StreamNotifier<T>`, `build()` returns `Stream<T>`.

## Modifiers

- **autoDispose** — Cache is cleared when the provider has no listeners. Use with family to avoid memory leaks. Disable with `@Riverpod(keepAlive: true)` in codegen.
- **family** — Pass parameters to the provider (e.g. `provider(id)`). See riverpod-family.

## Notifier rules

- Do not put logic in the Notifier constructor; `ref` and `state` are not ready. Put initialization in `build()`.
- `build()` is called by the framework; do not call it directly.
- Consumers modify state by calling methods on the notifier: `ref.read(myProvider.notifier).myMethod()`.

## Multiple providers, same type

Riverpod allows multiple providers that expose the same type (e.g. two different `Provider<String>`). They are independent; no conflict.

## Links to other concepts

- Ref (read, watch, listen, invalidate): riverpod-refs
- Containers / ProviderScope: riverpod-containers
- Auto-dispose: riverpod-auto-dispose
- Family: riverpod-family
- Overrides (testing): riverpod-overrides
- Consumers (widgets): riverpod-consumers
