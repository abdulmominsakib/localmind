---
title: Upgrade checklist
description: "A step-by-step checklist for upgrading llamadart: release notes, migration guides, version-specific behavior changes, runtime checks, templates and pins."
---

Use this checklist when upgrading `llamadart` across minor or major versions.

## 1. Read release notes first

- Start with [Recent releases](../changelog/recent-releases).
- Then review the full `CHANGELOG.md`.

## 2. Review migration guides

- Every migration path in one file:
  [`MIGRATION.md`](https://github.com/leehack/llamadart/blob/main/MIGRATION.md).
- 0.4.x to 0.5.x: [Migration (0.4.x to 0.5.x)](./0-4-to-0-5).
- 0.5.x to 0.6.x: [Migration (0.5.x to 0.6.x)](./0-5-to-0-6).
- Behavior changes without an API break: see
  [Version-specific notes](#version-specific-notes).

## 3. Validate build and runtime behavior

- Run `dart analyze`.
- Run `dart test`.
- Run platform smoke checks for your deployment targets.

## 4. Validate template and tool-calling behavior

- Re-run critical prompt and tool scenarios with production-like settings.
- Confirm any custom template assumptions still apply.

## 5. Validate deployment and runtime pins

- Confirm native runtime bundle expectations.
- Confirm web bridge asset tags and compatibility rules.

## 6. Update docs for your team or app

- Capture changed defaults, removed APIs and new flags.
- Link internal runbooks to the exact release tag.

## Version-specific notes

### 0.16.x: runtime-specific parameters and Apple companions

For the 0.15-to-0.16 changes, follow the
[0.16 migration guide](https://github.com/leehack/llamadart/blob/main/MIGRATION.md#015x-to-0160-upgrade-guide).
`ModelParams` fields the model's runtime would ignore now throw
`LlamaUnsupportedException`; move LiteRT-LM options to `LiteRtLmModelParams`.
Upgrade core and every Apple companion to `0.16.x` together: companions
`0.16.0` require `>=0.16.0 <0.17.0`, and core `0.16.x` accepts no earlier
stable_diffusion companion.

### 0.15.x: media embeddings and Apple companions

For the breaking 0.14-to-0.15 changes, follow the
[0.15 migration guide](https://github.com/leehack/llamadart/blob/main/MIGRATION.md#014x-to-0150-upgrade-guide).
Use `embeddingCapabilities` for ordered media embeddings; chat media support
does not establish embedding support. Check the
[embedding guide](../guides/embeddings) for qualified model/backend pairs.

For the SD native error guard, use core `0.15.2` and SD companion `0.15.2`
together. The companion requires `>=0.15.2 <0.16.0`. Locked SD companions
`0.15.0`/`0.15.1` retain their older native runtime with an upgrade warning;
updating core alone does not replace that payload. Core `0.15.6` pairs with
llama.cpp and LiteRT-LM companions `0.15.2`, which require
`>=0.15.6 <0.16.0`; locked `0.15.0`/`0.15.1` companions keep their older
native runtime with an upgrade warning. See [Installation](../getting-started/installation)
for the current package combination and
[Image generation](../guides/image-generation) for the physical-device limits.

### 0.14: unsupported options and structured output

Review the
[0.14 migration guide](https://github.com/leehack/llamadart/blob/main/MIGRATION.md#013x---0140-llamacpp-v070-abi-qwen3-overrides-and-load-callbacks)
for typed capability refusals, schema validation and callback changes. Keep
error handling for unsupported model/runtime combinations and unavailable
performance counters; a successful load does not qualify every operation.

### 0.8.10: model download and cache defaults

No source change is required, but two runtime defaults changed:

- `DefaultModelDownloadManager()` on desktop and server now uses the per-user
  platform cache (for example `$HOME/Library/Caches/llamadart/models` on
  macOS) instead of the process temporary directory. Without a home or cache
  environment it falls back to `Directory.systemTemp/llamadart/models`.
- `DefaultModelDownloadManager.auto()` on Android and iOS without a mobile
  directory no longer throws; it falls back to
  `Directory.systemTemp/llamadart/models`. Pass an app-private directory for
  large durable model files.

To keep the old desktop behavior, pass `defaultCacheDirectory` explicitly.
Tests that expected the old temporary path or the mobile
`LlamaUnsupportedException` need updating. Details:
[`MIGRATION.md`](https://github.com/leehack/llamadart/blob/main/MIGRATION.md)
and [Download and cache models](../guides/model-downloads).

### 0.6.4: Android arm64 CPU profile

Shorthand `android-arm64: [vulkan]` now uses the default `cpu_profile: full`.
Set `cpu_profile: compact` for baseline-only, smaller packaging.
