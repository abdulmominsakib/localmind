---
title: Runtime Ownership Boundaries
description: Understand which repository owns native runtime code, web bridge behavior, and Dart integration changes.
unlisted: true
---

`llamadart` follows a zero-patch strategy for upstream runtime ownership.

## Rules

- Do not patch upstream `llama.cpp` sources in this repo.
- Do not add local native build graph changes that belong in
  `llamadart-native`.
- Do not add Apple SPM runtime binaries in this repo when they should be
  produced by `llamadart-native` or `litert-lm-native`.
- Do not treat bridge runtime internals as owned by this repo; those belong in
  `llama-web-bridge`.

## Where changes should go

- llama.cpp native wrapper/runtime behavior and Apple SPM-compatible artifacts:
  `llamadart-native`
- LiteRT-LM native wrapper/runtime behavior and Apple SPM-compatible artifacts:
  `litert-lm-native`
- Web bridge runtime behavior: `llama-web-bridge`
- Published bridge assets: `llama-web-bridge-assets`
- Dart API/runtime selection/docs/tests: `llamadart`

## Why this matters

Keeping ownership boundaries clear avoids drift between:

- bundle publishing pipelines,
- runtime contract implementations, and
- consumer-facing Dart APIs.

It also keeps this repo focused on integration correctness.
