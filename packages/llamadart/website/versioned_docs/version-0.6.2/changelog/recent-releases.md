---
title: Recent Releases
---

For canonical full release notes, use:

- [`CHANGELOG.md`](https://github.com/leehack/llamadart/blob/main/CHANGELOG.md)

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
