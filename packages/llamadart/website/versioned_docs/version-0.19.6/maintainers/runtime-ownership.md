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

Native runtimes from `v0.18.0-3`
([litert-lm-native#80](https://github.com/leehack/litert-lm-native/pull/80))
report why a conversation stream turn ended, and llamadart reads it
([#919](https://github.com/leehack/llamadart/issues/919)):

- `LiteRtLmRuntimeClient.supportsFinishReasons` is true only when
  `stream_proxy_finish_reason_abi_version` returns 1 and
  `stream_proxy_get_finish_reason` resolves. A missing export, version 0 or an
  unknown version keeps the explicit unsupported loop path.
- The final stream callback, including the cancellation error, reads
  `stream_proxy_get_finish_reason` before `stream_proxy_delete`. Wire values:
  0 unknown, 1 stop token or stop sequence, 2 output budget, 3 context full,
  4 cancelled, 5 error. The blocking send path and Session-API streams report
  none.
- The service maps 2 to `BackendGenerationLimit.maxTokens` and 3 to
  `contextSize` (both `length`); every other value is no limit. Cancellation,
  including a Dart stop sequence, which cancels the native turn, wins over a
  reported limit, as on llama.cpp. A reporting runtime returns 0 for a
  finished turn only when another message races it on the same conversation,
  which the worker's one-generation-at-a-time rule prevents.
- The worker probes support at model load and returns it with the handle, so
  `generationLimitUnsupportedReason` is null only after a load on a reporting
  runtime.

Web `@litert-lm/core@0.19.0` exposes no cause, but its counts bound one.
`withTextHistory()` loads set `benchmarkEnabled`, and after each turn
`litert_lm_backend_web.dart` reads `getBenchmarkInfo().lastDecodeTokenCount`
(the turn's decode steps, end-of-turn token included) and `getTokenCount()`
(the conversation's tokens). Upstream `ShouldStop` stops on a stop token, at
`current_step >= max_num_tokens` or at `num_decoded_steps >=
max_output_tokens`, so fewer steps than `maxOutputTokens` and fewer tokens
than the executor's `max_num_tokens` prove a stop-token end; anything else
reports `contextSize` or `maxTokens`, and unreadable counts report
`runtime`. A stop exactly at the budget is indistinguishable and reports
`maxTokens`. Cancellation and Dart stop sequences win.

`engine.settings.mainExecutorSettings.maxNumTokens` is the engine's copy of
the request, not the limit: a static-KV executor clamps its own copy to its
cache (`ClampMaxNumTokens` in `llm_litert_compiled_model_executor.cc`), and
`ShouldStop` uses that copy. Qwen3 0.6B on WASM CPU requested at 65536 stops
at 4096 while the settings say 65536. `JsBenchmarkInfo` does not expose the
benchmark's `max_num_tokens`, so the load reads the executor's limit from
`Prefill`'s rejection of an input of at least that many tokens: `Input token
ids are too long. Exceeding the maximum number of tokens allowed: N >= M`.
The probe sends `4 × requested + 64` pseudo-random digits, which Gemma, Qwen
and Llama 3 tokenize at one to three digits per token, and is rejected before
any model work (about 20-125 ms at 65536 on Qwen3 0.6B CPU). It also runs a
one-token turn that must report a decode count of 1 and a context count below `M`. Any other
outcome, including an accepted prompt or another error text, leaves
`generationLimitUnsupportedReason` set. Requalify with `litert-lm-web-truncation` whenever the
`@litert-lm/core` pin changes: a new stop condition in `ShouldStop` breaks
the inference.

Why the cause needs the owner patch, from upstream `v0.18.0`:

- [Owner release `v0.18.0`](https://github.com/leehack/litert-lm-native/releases/tag/v0.18.0)
  records owner `29537be97949ef4eca8da793c4df4fb487f3993c` and upstream
  `b2f686e2ed4718fb84ec398a61dd59ca0f0aff27`.
- [Upstream decode](https://github.com/google-ai-edge/LiteRT-LM/blob/b2f686e2ed4718fb84ec398a61dd59ca0f0aff27/runtime/core/tasks.cc)
  checks EOS before context and output budgets in `ShouldStop`, but discards
  which branch stopped decoding. Output-limit and EOS termination both return
  `TaskState::kDone`; recovering a cause from counts changes this precedence.
- [Conversation callback](https://github.com/google-ai-edge/LiteRT-LM/blob/b2f686e2ed4718fb84ec398a61dd59ca0f0aff27/runtime/conversation/internal_callback_util.cc)
  collapses ordinary terminal states to an empty message. The
  [C callback](https://github.com/google-ai-edge/LiteRT-LM/blob/b2f686e2ed4718fb84ec398a61dd59ca0f0aff27/c/conversation.cc)
  maps that message to a final chunk with no text or error. The
  [owner proxy](https://github.com/leehack/litert-lm-native/blob/29537be97949ef4eca8da793c4df4fb487f3993c/native/bridge/litert_lm_bridge.c)
  forwards only text, final and error, so a proxy-only change cannot recover
  the discarded cause.
- The official pinned
  [Web conversation implementation](https://cdn.jsdelivr.net/npm/@litert-lm/core@0.19.0/dist/conversation.js)
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
