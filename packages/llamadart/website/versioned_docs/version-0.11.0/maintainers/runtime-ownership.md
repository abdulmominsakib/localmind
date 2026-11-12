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
| stable-diffusion.cpp runtime bundles, Apple SPM-compatible artifacts and exported `stable-diffusion.h` API (opt-in `stable_diffusion` runtime) | `leehack/stable-diffusion-native` |
| Web bridge runtime source and build | `leehack/llama-web-bridge` |
| Published bridge assets | `leehack/llama-web-bridge-assets` |
| Flutter Apple SPM package manifests | `packages/llamadart_llama_cpp_flutter`, `packages/llamadart_litert_lm_flutter` and `packages/llamadart_stable_diffusion_flutter` in this repo |
| Dart API, runtime selection, hook wiring, pins, docs, tests | `llamadart` (this repo) |

## Rules

- Do not patch upstream llama.cpp, LiteRT-LM, stable-diffusion.cpp or bridge
  sources in this repo.
- Do not add native build graph changes that belong in `llamadart-native`,
  `litert-lm-native` or `stable-diffusion-native`.
- Keep Apple SPM runtime binaries and Flutter plugin manifests out of the core
  package root; they live in the companion packages under `packages/`.
- Commit, push and release a runtime change in its owning repository first,
  then update pins, hooks, docs and tests here; see
  [Native and web sync](./native-and-web-sync).

Clear boundaries keep the publishing pipelines, the runtime contracts and the
consumer-facing Dart API from drifting apart, and keep this repo focused on
integration correctness.

## LiteRT-LM termination reporting

The consumer safety gate leaves
[#919](https://github.com/leehack/llamadart/issues/919) open for reliable runtime
reporting. The pinned native `v0.17.0-8` and Web `@litert-lm/core@0.15.0` do
not expose a cause that distinguishes EOS from per-request output exhaustion.
They cannot safely drive automatic tool loops. Plain completion remains
available; its `stop` value is an unverified termination reason on those pins.

Verified source chain for the native artifact:

- [Owner release `v0.17.0-8`](https://github.com/leehack/litert-lm-native/releases/tag/v0.17.0-8)
  records owner `e486b51bf9f06ec6df3c3d5e8e782f24957a1724` and upstream
  `e9fd8c53ff968071774206163027dd84bedfe925`.
- [Upstream decode](https://github.com/google-ai-edge/LiteRT-LM/blob/e9fd8c53ff968071774206163027dd84bedfe925/runtime/core/tasks.cc)
  checks EOS before context and output budgets in `ShouldStop`, but discards
  which branch stopped decoding. Output-limit and EOS termination both return
  `TaskState::kDone`; recovering a cause from counts changes this precedence.
- [Conversation callback](https://github.com/google-ai-edge/LiteRT-LM/blob/e9fd8c53ff968071774206163027dd84bedfe925/runtime/conversation/internal_callback_util.cc)
  collapses ordinary terminal states to an empty message. The
  [C callback](https://github.com/google-ai-edge/LiteRT-LM/blob/e9fd8c53ff968071774206163027dd84bedfe925/c/conversation.cc)
  maps that message to a final chunk with no text or error. The
  [owner proxy](https://github.com/leehack/litert-lm-native/blob/e486b51bf9f06ec6df3c3d5e8e782f24957a1724/native/bridge/litert_lm_bridge.c)
  forwards only text, final and error, so a proxy-only change cannot recover
  the discarded cause.
- The official pinned
  [Web conversation implementation](https://cdn.jsdelivr.net/npm/@litert-lm/core@0.15.0/dist/conversation.js)
  streams messages and closes after `waitUntilDone`. It exposes no terminal
  cause; native artifact publication alone does not repair the browser package.

The owner fix must preserve the actual selected decode branch through the
response, conversation and versioned C/proxy APIs, including streaming,
blocking/NPU and speculative paths. EOS, stop sequences, benchmark limits,
context limits, output limits, cancellation and errors must stay distinct.
Publish and qualify owner artifacts before adopting a consumer pin. Web
requires the same cause through a qualified JS/WASM package or official
upstream release. Do not implement runtime source patches in `llamadart`.

Qualification must compare genuine budget termination with normal EOS at the
same output count, then exercise public completion and automatic loops with
partial thinking, incomplete tool JSON and complete calls followed by a
cutoff. Cutoff replies must run no tools and roll back the turn; cancellation
must win over a captured limit. Older or unknown runtimes keep the explicit
unsupported loop path. Use existing Qwen3/Gemma 4 artifacts where available;
output length alone is never a termination classifier.
