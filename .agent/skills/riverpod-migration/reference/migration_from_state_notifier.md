# Migration: From StateNotifier to Notifier / AsyncNotifier

- **StateNotifier** is deprecated in favor of **Notifier** and **AsyncNotifier** (Riverpod 2.0+).

## Main differences

- Dependencies: in StateNotifier they were in the provider; in Notifier they go in **build** via **ref.watch**.
- Initialization: StateNotifier split between provider and constructor; Notifier uses a single **build** method; no logic in the constructor.
- Lifecycle: StateNotifier had **dispose** on the class. Notifier/AsyncNotifier use **ref.onDispose** (and ref.onCancel) in build, like any other provider. Only internal state is disposed on rebuild; the notifier type itself is not disposed the same way.
- **mounted**: Notifier/AsyncNotifier do not have **mounted**. Use cancellation (Completer, Dio CancelToken, etc.) instead of checking mounted after async work.

## Sync: StateNotifier → Notifier

- Replace **StateNotifierProvider** with **NotifierProvider**.
- Move reactive dependencies from the provider into **build** with **ref.watch**.
- Put all init logic in **build**; leave constructor minimal.
- Use **ref.onDispose** in build for cleanup (no override of dispose).

## Async: StateNotifier → AsyncNotifier

- Replace **StateNotifierProvider** with **AsyncNotifierProvider**.
- Move async init into **build** returning **Future<T>**; remove AsyncValue.guard / try-catch in build.
- Use **future** and **update** on AsyncNotifier for simpler async flows.
- Migrating from **StateNotifier<AsyncValue<T>>** to **AsyncNotifier<T>**: put init in build, remove manual try/catch and AsyncValue handling in build.

## Family and autoDispose

- With Notifier/AsyncNotifier, family parameters are passed into the class (e.g. constructor + field) and are available in build; no separate “family” type.
- AutoDispose is expressed the same as other providers (e.g. ref.onDispose in build).

## Consumers and mutations

- **Consumers do not change**: ref.watch(provider), ref.read(provider.notifier), and calling notifier methods stay the same.
- **ref.listen** replaces StateNotifier’s **.addListener** / **.stream**: use **ref.listen(provider, (prev, next) { ... })**.

## Tests

- **.debugState** is gone. Use **ref.read(provider)** or **ref.read(provider.notifier)** to get the notifier/state in tests; do not instantiate Notifier/AsyncNotifier by hand (ref and family args would be unset).

## StateProvider

- **StateProvider** is deprecated with StateNotifierProvider. Migrate to **Notifier**: one Notifier with **build** returning the initial value and methods that set **state**.
