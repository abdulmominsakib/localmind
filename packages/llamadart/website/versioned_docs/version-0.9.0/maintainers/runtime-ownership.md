---
title: Runtime ownership boundaries
description: Understand which repository owns native runtime code, web bridge behavior, and Dart integration changes.
---

`llamadart` consumes its native and web runtimes; it never patches them. This
page is the single list of which repository owns which change.

## Where changes go

| Change | Owning repository |
| --- | --- |
| llama.cpp native wrapper, runtime bundles, Apple SPM-compatible artifacts | `leehack/llamadart-native` |
| LiteRT-LM native wrapper, runtime bundles, Apple SPM-compatible artifacts | `leehack/litert-lm-native` |
| Web bridge runtime source and build | `leehack/llama-web-bridge` |
| Published bridge assets | `leehack/llama-web-bridge-assets` |
| Flutter Apple SPM package manifests | `packages/llamadart_llama_cpp_flutter` and `packages/llamadart_litert_lm_flutter` in this repo |
| Dart API, runtime selection, hook wiring, pins, docs, tests | `llamadart` (this repo) |

## Rules

- Do not patch upstream llama.cpp, LiteRT-LM or bridge sources in this repo.
- Do not add native build graph changes that belong in `llamadart-native` or
  `litert-lm-native`.
- Keep Apple SPM runtime binaries and Flutter plugin manifests out of the core
  package root; they live in the companion packages under `packages/`.
- Commit, push and release a runtime change in its owning repository first,
  then update pins, hooks, docs and tests here; see
  [Native and web sync](./native-and-web-sync).

Clear boundaries keep the publishing pipelines, the runtime contracts and the
consumer-facing Dart API from drifting apart, and keep this repo focused on
integration correctness.
