# Migration: 0.13.x → 0.14.x

- In **0.14.0** the way **StateNotifierProvider** and state/notifier reading work changed.

## Changes

1. **StateNotifierProvider** gets an extra type parameter: the **state** type.
   - Before: `StateNotifierProvider<MyStateNotifier>(...)`
   - After: `StateNotifierProvider<MyStateNotifier, MyModel>(...)`

2. **Reading the notifier**
   - Before: `watch(provider)` returned the StateNotifier.
   - After: use **provider.notifier**: `watch(provider.notifier)` to get the StateNotifier.

3. **Reading the state**
   - Before: `watch(provider.state)` for the state.
   - After: `watch(provider)` returns the state directly.

## CLI migration

- Install: `dart pub global activate riverpod_cli`
- In the project (do **not** upgrade Riverpod first): run **riverpod migrate**.
- The tool will suggest edits (e.g. `watch(provider.state)` → `watch(provider)`). Accept with `y` or reject with `n`.
