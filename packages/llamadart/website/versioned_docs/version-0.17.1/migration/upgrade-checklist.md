---
title: Upgrade checklist
description: "A step-by-step checklist for upgrading llamadart: release notes, migration guides, version-specific behavior changes, runtime checks, templates and pins."
---

Use this checklist when upgrading `llamadart` across minor or major versions.

## 1. Read release notes first

- Start with [Recent releases](../changelog/recent-releases).
- Then review the full `CHANGELOG.md`.

## 2. Review migration guides

- Upgrading from 0.16.x: [Upgrade to 0.17](./upgrade-to-0-17).
- Older upgrades, including 0.4.x to 0.6.x: every path is in
  [`MIGRATION.md`](https://github.com/leehack/llamadart/blob/main/MIGRATION.md).
- Behavior changes without an API break: see
  [Version-specific notes](#version-specific-notes).

## 3. Validate build and runtime behavior

- Run `dart analyze` and `dart test`.
- Run platform smoke checks for each deployment target.

## 4. Validate template and tool-calling behavior

- Re-run your critical prompt and tool scenarios with production settings.
- Recheck any custom chat template or `chatTemplateKwargs` against the
  thinking defaults in [Upgrade to 0.17](./upgrade-to-0-17).

## 5. Validate deployment and runtime pins

- Upgrade core and every Apple companion to the same `MAJOR.MINOR` together;
  see [Installation](../getting-started/installation).
- Confirm the native runtime bundle and the web bridge asset tag your app
  ships match the release you installed.

## Version-specific notes

### 0.17.x: optional backend capabilities

Follow [Upgrade to 0.17](./upgrade-to-0-17). Custom backends implement
`BackendLoraSupport` and `BackendMultimodalSupport` for LoRA and projector
members, which `LlamaBackend` no longer declares.

### 0.16.x: runtime-specific parameters

For the 0.15-to-0.16 changes, follow the
[0.16 migration guide](https://github.com/leehack/llamadart/blob/main/MIGRATION.md#015x-to-0160-upgrade-guide).
`ModelParams` fields the model's runtime would ignore now throw
`LlamaUnsupportedException`; move LiteRT-LM options to `LiteRtLmModelParams`.

### 0.15.x: media embeddings

For the breaking 0.14-to-0.15 changes, follow the
[0.15 migration guide](https://github.com/leehack/llamadart/blob/main/MIGRATION.md#014x-to-0150-upgrade-guide).
Use `embeddingCapabilities` for ordered media embeddings; chat media support
does not establish embedding support. Check the
[embedding guide](../guides/embeddings) for qualified model/backend pairs, and
[Image generation memory and limits](../guides/image-generation-memory-and-limits) for the physical-device limits.

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
