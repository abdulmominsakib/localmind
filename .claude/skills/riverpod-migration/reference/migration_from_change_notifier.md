# Migration: From ChangeNotifier to AsyncNotifier

- For apps already on Riverpod using **ChangeNotifierProvider**, this guide moves to **AsyncNotifier** (and **Notifier** where state is sync).

## Why migrate

- ChangeNotifier leads to **isLoading** / **hasError** flags and lots of **try/catch/finally** and **notifyListeners()**.
- AsyncNotifier uses a single **state** and **AsyncValue**; Riverpod handles loading/error; less boilerplate and fewer inconsistent states.

## Steps

1. **Choose the notifier type**
   - Side effects (methods that change state)? → Class-based (Notifier or AsyncNotifier).
   - Async load (e.g. network)? → **AsyncNotifier<T>**.
   - Parameters? → Add them to the notifier (e.g. constructor + field) and use family/provider that passes them.

2. **Declaration**
   - Replace **ChangeNotifierProvider** with **AsyncNotifierProvider** (or NotifierProvider if sync).
   - State type: e.g. **AsyncNotifier<List<Todo>>**; no separate **todos** / **isLoading** / **hasError**—just **state** and AsyncValue.

3. **Initialization**
   - Move init from a custom method (e.g. **init**) into **build**.
   - **build** returns **Future<List<Todo>>**; Riverpod exposes **AsyncValue<List<Todo>>** to the UI. No manual try/catch in build.

4. **Mutations**
   - Replace flag updates and notifyListeners with **state = newValue** (and **state = AsyncValue.data(...)** or **AsyncValue.error(...)** if you construct explicitly). Use **ref** for dependencies (ref.watch, ref.read) inside methods.

5. **Consumers**
   - **ref.watch(provider)** now gets **AsyncValue<T>**; handle loading/error/data in the UI. Use **ref.read(provider.notifier)** to call methods.

## Summary

- Init in **build**; no **todos**/isLoading/hasError.
- No try-catch-finally in build; return the Future.
- Side effects: reassign **state**; use **ref** for other providers.
- See riverpod-providers and riverpod-refs for Notifier/AsyncNotifier and Ref APIs.
