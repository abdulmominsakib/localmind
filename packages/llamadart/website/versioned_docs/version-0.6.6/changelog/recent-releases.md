---
title: Recent Releases
description: Review recent llamadart release highlights and jump to the canonical changelog for full release notes.
---

For canonical full release notes, use:

- [`CHANGELOG.md`](https://github.com/leehack/llamadart/blob/main/CHANGELOG.md)

## 0.6.6

- Synced native hook pin to `leehack/llamadart-native@b8216`.
- Updated default web bridge asset pinning to
  `leehack/llama-web-bridge-assets@v0.1.10` (llama.cpp `b8216`).
- Switched bundled Qwen3.5 example presets to Unsloth `Q4_K_M` GGUFs.
- Added native perf diagnostics chips in the chat app (`p_eval`, `eval`,
  `sample`, `reuse`) and Android-specific Qwen tuning guidance.
- Restored a targeted Android Vulkan fast path for local Qwen3.5 `0.8B` / `2B`
  / `4B` models while keeping CPU as the recommended Android preset for
  `0.8B` / `2B`.
- Fixed local web chat app bridge/runtime handling for Qwen prompt streaming and
  multimodal fallback behavior.
- Compatibility note: no public API breaking changes in `0.6.6`.

## 0.6.5

- Added embedding APIs: `LlamaEngine.embed(...)` and
  `LlamaEngine.embedBatch(...)`.
- Added backend embedding capability interfaces for custom backend
  implementations.
- Added multi-sequence embedding batching support via
  `ModelParams.maxParallelSequences` (`n_seq_max`).
- Added native embedding benchmark tooling:
  `tool/testing/native_embedding_benchmark.dart` and
  `tool/testing/native_embedding_sweep.dart`.
- Added website docs for embeddings and updated basic-app docs with embedding
  examples.
- Added a Basic App SQLite vector retrieval example using
  `bin/llamadart_sqlite_vector_example.dart`.
- Updated default WebGPU bridge asset pinning to
  `leehack/llama-web-bridge-assets@v0.1.8`.
- Improved WebGPU runtime stability/tuning in chat app flows (backend switching,
  streaming smoothness, and multimodal regression gating).
- Added GPU-path multimodal image-size capping to reduce memory/runtime pressure
  on larger image inputs.
- Compatibility note: no public API breaking changes in `0.6.5`.

## 0.6.4

- Aligned multimodal projector offload with effective model-load settings,
  including CPU-only configurations.
- Added safer backend selection/discovery APIs and improved runtime backend
  status plus GPU-layer diagnostics accuracy.
- Improved web large-model handling with cache-prefetch download UX, bridge
  worker fallback paths, memory-pressure retries, and wasm64-core fallback
  wiring.
- Synced native hook tag to `b8157` and added Android arm64 CPU-profile and
  variant policy support with loader hardening.

## 0.6.3

- Synced native runtime to llama.cpp `b8138` and picked up Android arm64
  crash/compatibility hardening.
- Example app performance/UX polish and web model handling improvements.
- Added `example/tui_coding_agent`, a terminal coding agent example with
  default stable text-protocol tool mode.
- Added persisted settings log-level fallback handling with regression tests.

## 0.6.2

- Native inference performance improvements (request overhead, stream batching,
  and prompt-prefix reuse with parity-safe fallback).
- Added native benchmark and prompt-reuse parity tooling, plus CI parity
  coverage.

## 0.6.1

- Publishing compatibility fix for hook backend-config code paths.
- Continued parity hardening around template/parser behavior.

## 0.6.x line highlights

- Expanded llama.cpp template and parser parity.
- Stronger handling for tool payload fidelity.
- More deterministic behavior around template routing and fallback removal.

## 0.5.x line highlights

- Public API tightening and migration cleanup.
- Split Dart/native log controls.
- Example/runtime reliability improvements.

## Release usage guidance

- For upgrade planning, combine this page with
  [Upgrade Checklist](../migration/upgrade-checklist).
- For breaking changes, always validate against the exact release tag notes.
