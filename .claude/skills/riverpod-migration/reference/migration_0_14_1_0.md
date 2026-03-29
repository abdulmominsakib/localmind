# Migration: 0.14.x → 1.0

- **1.0** unifies the API for reading providers and changes some types.

## CLI migration

- Install: `dart pub global activate riverpod_cli`
- **Do not** upgrade to 1.0 before running the tool; stay on 0.14.x.
- Run **riverpod migrate** in the project; it will suggest changes and can upgrade the dependency.

## Syntax unification

- **Single syntax**: **ref.watch(provider)** (and ref.read). **useProvider**, **watch(provider)** without ref, and **context.read** are removed.

- **ConsumerWidget / Consumer**
  - Before: `build(BuildContext context, ScopedReader watch)` and `watch(provider)`.
  - After: `build(BuildContext context, WidgetRef ref)` and **ref.watch(provider)**.
  - Consumer: `builder: (context, watch, child)` → `builder: (context, ref, child)` and use **ref.watch(provider)**.

- **HookWidget**
  - **useProvider(provider)** is removed. Use **HookConsumerWidget** and **ref.watch(provider)** in build.

- **context.read**
  - Use **ConsumerWidget** (or Consumer) and **ref.read(provider)** instead of **context.read**.

## StateProvider

- **ref.watch(StateProvider)** used to return a **StateController**; in 1.0 it returns the **state** value only.
  - If you only displayed the value: change to **ref.watch(provider)** and use the value directly.
  - If you need the controller: use **ref.watch(provider.state)** to keep the old behavior (StateController).
