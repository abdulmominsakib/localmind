# WebGPU Bridge Contract (Experimental)

This document owns the bridge internals: the JavaScript contract
`WebGpuLlamaBackend` expects, the chat app bootstrap, pinned asset provenance,
and hosting details. App-facing setup (requirements, adding the bridge,
memory64, fallback, troubleshooting) is on the docs site:
[WebGPU bridge](https://llamadart.leehack.com/docs/platforms/webgpu-bridge).

## Ownership

Bridge source and build CI live in `leehack/llama-web-bridge`; published CDN
assets in `leehack/llama-web-bridge-assets`. `llamadart` only consumes them;
see `website/docs/maintainers/runtime-ownership.md`.

## Chat app bootstrap

`example/chat_app/web/index.html` builds two bridge URLs:

- CDN: `https://cdn.jsdelivr.net/gh/<repo>@<tag>/llama_webgpu_bridge.js`
- Local: `./webgpu_bridge/llama_webgpu_bridge.js?v=<tag>-local-<llama.cpp tag>`

It prefers the local runtime, then falls back to the CDN, when the page is
served from `localhost` or `127.0.0.1`, or when
`window.__llamadartPreferLocalBridgeRuntime === true`. Otherwise it tries the
CDN first and falls back to local assets.

When the bridge module comes from the CDN, the bootstrap still derives the core
module, `.wasm` files and worker from the local `./webgpu_bridge/` directory.
A cross-origin isolated page cannot start the core's pthread workers from a
CDN script URL, so hosted builds must ship the local assets too.

The bootstrap then sets the globals `WebGpuLlamaBackend` reads
(`__llamadartBridgeCoreModuleUrl`, `...Mem64`, `__llamadartBridgeWasmUrl`,
`...Mem64`, `__llamadartBridgeWorkerUrl`, `__llamadartBridgePreferMemory64`,
`__llamadartBridgeAdaptiveSafariGpu`) and records the source in
`__llamadartBridgeAssetSource` (`cdn`, `local` or `mock`) and
`__llamadartBridgeModuleUrl`.

### Readiness signal

- `window.__llamadartBridgeReadyPromise` resolves once the bridge loads and
  rejects when both sources fail or after a 30 second timeout.
- `window.__llamadartBridgeReady` is `true` only after a successful load.
- `window.__llamadartBridgeLoadError` holds the failure detail.

The chat app awaits the promise before Cache Storage prefetch, so an early
**Download** tap cannot report success before `prefetchModelToCache(...)`
exists. Custom code that calls bridge methods directly should do the same.
Independently, `WebGpuLlamaBackend` polls up to 12 seconds for
`window.LlamaWebGpuBridge` at model load and stops early once
`__llamadartBridgeLoadError` is set.

### Bootstrap knobs

These are read by the chat app `index.html`, not by `llamadart`. Set them in
an earlier `<script>`:

| Global | Effect |
| --- | --- |
| `__llamadartBridgeAssetsRepo`, `__llamadartBridgeAssetsTag` | CDN source; defaults to `leehack/llama-web-bridge-assets` at the pinned tag |
| `__llamadartPreferLocalBridgeRuntime` | `true` loads local assets first off `localhost` |
| `__llamadartBridgeEnableMem64` | `true` sets `__llamadartBridgePreferMemory64`; default off |
| `__llamadartBridgeThreadPoolSize` | Thread hint; default 1 without cross-origin isolation, else `hardwareConcurrency` clamped to 2..4 |
| `__llamadartBridgeSpeechToTextSupported` | Defaults to `true` only for the official repository at `v0.1.30` or newer |
| `__llamadartLiteRtLmModuleUrl` | `@litert-lm/core` module; default `@litert-lm/core@0.19.0` from jsDelivr |
| `__llamadartBridgeBootstrapVerbose` | `true` enables bootstrap `console.*` logs |

## Pinned assets

Default pinned tag in the example is `v0.1.83`.
Vendor the pinned assets into the chat app with:

```bash
WEBGPU_BRIDGE_ASSETS_TAG=v0.1.83 ./scripts/fetch_webgpu_bridge_assets.sh
```

`WEBGPU_BRIDGE_OUT_DIR` changes the destination. The script verifies
`sha256sums.txt` when the release provides it.

Apps use `dart run llamadart:web_setup` (`bin/web_setup.dart`) instead. It
pins the tag and the manifest SHA-256 in
`lib/src/web_setup/web_bridge_setup.dart`, verifies every runtime file against
that manifest's `files` digests and sizes before replacing anything, and keeps
a marked bootstrap block in the app's `index.html`. Unlike the chat app
bootstrap it loads only the local assets, with no CDN fallback.
`tool/testing/check_webgpu_bridge_tag.dart` registers its tag as a pin and
reads its manifest SHA-256, so a repin cannot leave it behind. To load another CDN release in
the chat app, set the bootstrap globals before the bootstrap runs:

```html
<script>
  window.__llamadartBridgeAssetsRepo = 'leehack/llama-web-bridge-assets';
  window.__llamadartBridgeAssetsTag = 'v0.1.83';
</script>
```

That release embeds llama.cpp `v0.9.0`, matching the `hook/build.dart` native pin
(`v0.9.0`, both built from upstream llama.cpp `v0.9.0@cd959bae99ff4bed22bef2604f45241c09bbb8c8`)
even though the bridge asset tag `v0.1.83` differs from the native runtime tag
`v0.9.0`. Provenance for this immutable consumer artifact: release `438242670`,
tag commit `44aa84a8a51701dc9c4f82c21e6ee3e774919c20`, bridge source
`cb6383fbe7e903764a89f5c80c7f81c219f99769`, and manifest SHA-256
`ae6f488408672f9ba28d8f9e664a2b85f4e12048f290e259e18dd0b750c038e5`.
They expose the API-version-1 media embedding contract. State and extraction
qualification covers wasm32 and memory64 through direct and worker runtimes. Existing decision,
scoring, sampling, LoRA, speculative decoding and speech APIs remain available.

Published release qualification covers CPU/WASM state persistence, multimodal
input, ASR and TTS. It does not establish hardware WebGPU acceleration,
physical playback, intelligibility or speaker-reference fidelity.

### Asset capability history

- `v0.1.7+`: embedding APIs.
- `v0.1.12+`: forward native-compatible `ModelParams` load tuning:
  multi-sequence slots, KV cache type, flash attention, RoPE overrides, split
  mode and main GPU.
- `v0.1.13+`: keep control-token output for parser consumers; narrow
  multimodal CPU fallback to recovery paths.
- `v0.1.14+`: cap automatically selected threads to the compiled pthread pool,
  so BERT-style embedding models no longer abort on hosts with more cores than
  the pool.
- `v0.1.15+`: `stateSaveFile` / `stateLoadFile` on WASMFS virtual paths, not
  durable across reloads.
- `v0.1.30+`: typed Qwen3-ASR whole-file transcription of encoded audio
  bytes, with a loaded projector whose audio probe is positive.
- `v0.1.32+`: recover short Qwen3-ASR speech when the model first emits only
  its end token; silence still returns an empty transcript.
- `v0.1.33+`: Qwen3-TTS capability discovery, float32 PCM generation,
  byte-backed speaker references, progress and cancellation in direct and
  worker runtimes. The pinned roughly 1.48 GB model pair needs memory64;
  wasm32 TTS is unsupported.
- `v0.1.34+`: retry a failed worker WebGPU TTS synthesis once in a CPU
  main-thread runtime with the cached model and projector; certain worker
  timeouts keep GPU offload on that retry.
- `v0.1.39+`: compatibility floor for bridge asset capabilities.
- `v0.1.47+`: decision API (apiVersion 1) for `DecisionEngine`; older assets
  report decision models as unsupported.
- `v0.1.52+`: next-token scoring (`scoreNextToken`).
- `v0.1.54+`: `presencePenalty`, `minP` and `thinkingBudget`, runtime LoRA
  adapters and speculative decoding, which llamadart gates on the bridge's
  capability probes rather than on this tag, and the bridge's
  `supportsCompletionUsage` flag for per-request usage.
- `v0.1.67+`: a state file the core cannot open rejects instead of aborting
  the runtime; media URLs resolve against `document.baseURI` before reaching
  the worker; teardown awaits the WebGPU model free and shutdown.
- `v0.1.69+`: loading a truncated or mismatched state snapshot rejects and
  keeps the current context state instead of aborting the runtime.
- `v0.1.70+`: streamed completion pieces and `detokenize` decode UTF-8 from
  the core's bytes. A character split across tokens, including at the start of
  a response, streams once complete and no longer comes out as a wrong
  character; `onToken`'s `currentText` leaves out the held-back tail. Invalid
  bytes and a tail still incomplete when generation ends become U+FFFD,
  `detokenize` keeps a leading U+FEFF (Dart's streamed text still drops it),
  and output after a NUL byte is delivered. Older assets keep the previous
  string reads
  ([llama-web-bridge#177](https://github.com/leehack/llama-web-bridge/pull/177)).
- `v0.1.71+`: in worker mode, `cancel()` right after a call starts stops it
  instead of letting it run to the end, because each cancel names the
  operation it targets; a bare `cancel()` streams the pieces generated before
  the worker yields, so they add up to the returned text. Older assets can run
  such a completion to the end
  ([llama-web-bridge#179](https://github.com/leehack/llama-web-bridge/pull/179),
  [#181](https://github.com/leehack/llama-web-bridge/pull/181)).
- `v0.1.72+`: repeat and presence penalties count a text prompt without a
  grammar, and the probe reports `penaltyPromptTokens: true`; text containing
  U+0000 is no longer truncated in tokenize, embed, score and prompts, and
  speech text containing U+0000 is rejected. Older assets count only generated
  tokens and truncate at the NUL
  ([llama-web-bridge#187](https://github.com/leehack/llama-web-bridge/pull/187),
  [#184](https://github.com/leehack/llama-web-bridge/pull/184),
  [#190](https://github.com/leehack/llama-web-bridge/pull/190)).
- `v0.1.73+`: string `embed`/`embedBatch` reject a rank-pooled model, which
  llamadart maps to `LlamaUnsupportedException`, and input that must fit one
  micro-batch but exceeds `nUbatch`, mapped to
  `LlamaEmbeddingInputTooLongException` with both counts. Older assets return
  an invalid vector built from classifier scores, embed only part of the input or abort
  the runtime
  ([llama-web-bridge#194](https://github.com/leehack/llama-web-bridge/pull/194)).
- `v0.1.74+`: on a model cache miss, load progress follows the download
  instead of arriving once the whole file is cached, and a cancelled or failed
  load leaves nothing cached
  ([llama-web-bridge#195](https://github.com/leehack/llama-web-bridge/pull/195)).
- `v0.1.75+`: a speculative draft context that cannot be allocated, such as an
  EAGLE3 draft at `nBatch`/`nUbatch` 2048 on wasm32, is freed and its
  generation throws `LlamaUnsupportedException` naming smaller batches or
  memory64, instead of leaking until the runtime aborts; a model whose context
  does not fit rejects its load instead of aborting
  ([llama-web-bridge#198](https://github.com/leehack/llama-web-bridge/pull/198)).
  The bridge also accepts `grammarLazy`, `grammarTriggers` and `grammarRoot`
  behind a `lazyGrammar` probe
  ([#199](https://github.com/leehack/llama-web-bridge/pull/199)); llamadart
  forwards them when that probe is true and reports it as `supportsLazyGrammar`.
- `v0.1.76+`: the projector GGUF is freed once loaded, removing the retained
  copy behind the repeated wasm32 media batch abort; wasm32 stays unqualified
  ([#1189](https://github.com/leehack/llamadart/issues/1189)) and larger
  contexts can still exhaust its heap
  ([llama-web-bridge#200](https://github.com/leehack/llama-web-bridge/pull/200)).
- `v0.1.79+`: llama.cpp `v0.8.0`. A worker `embed`/`embedBatch` with image or
  audio parts has a 10-minute budget instead of the generic two minutes, and
  `embedBatch` restarts it after each finished input, so the budget bounds one
  input rather than the batch. `workerRequestTimeoutMs` still overrides it
  ([llama-web-bridge#203](https://github.com/leehack/llama-web-bridge/pull/203)).
- `v0.1.83+`: llama.cpp `v0.9.0`. The TTS talker sampler applies the GGUF's
  suppress tokens, so Qwen3-TTS no longer fails with `code out of range` when it
  samples a codec control token
  ([llama-web-bridge#211](https://github.com/leehack/llama-web-bridge/pull/211)).

### Media embeddings

Assets v0.1.64+ expose `getEmbeddingCapabilities()` with `apiVersion: 1` and
boolean `text`, `image`, `audio` flags. The Dart backend probes each request,
including after projector changes and worker restoration; generation's media
flags do not enable embeddings. Unknown/missing APIs preserve legacy string embeddings and disable media with
a v0.1.64+ requirement diagnostic. Runtime probe failures, cancellation and
disposal remain typed inference errors. Present APIs explain missing loaded
model/projector modalities. The bridge's pooled `text` flag does not gate the
legacy last-token string route, including text-only content on pooling NONE.
The default pinned assets include this API.

`embedContentBatch` sends strings for text-only inputs and ordered parts arrays
for mixed/media inputs. Adjacent text is concatenated verbatim. Image/audio bytes
and mono 16 kHz Float32 PCM are forwarded without transfer/detachment; browser
filesystem paths and image URLs are rejected. The bridge validates the complete
batch before inference. Stable `EmbeddingError.code` values map to typed Dart
argument, unsupported or inference errors; arbitrary media diagnostics are never
included. Cancellation forwards to `cancel()` and disposal awaits `dispose()`;
the bridge owns settling queued/active operations before freeing its runtime.
Await cancelled embedding futures before reuse.

Chrome CPU wasm memory64 media vectors were qualified against native CPU/Metal;
hardware WebGPU was not exercised. Repeated media batches are qualified only on
memory64; `v0.1.76+` removes the projector copy behind the wasm32 abort (unqualified). See
[multimodal embedding qualification](multimodal_embeddings_web.md).

### Per-request cancellation

A generation subscription cancel, including `SpeechToTextTask.cancel()`, aborts
only the signal passed to that bridge completion. It must not also call the
bridge's global `cancel()`: a cancelled queued completion may not own the active
operation. TTS task cancellation follows the same rule: its controller is
claimed before the backend capability probe, which may still be queued behind
another active request. The signal prevents synthesis after that probe returns.
Engine-wide `cancelGeneration()` retains its global behavior.

The `web-speech-task-cancel` scenario exercises real typed STT/TTS cancellation
and reuse against pinned assets in direct and worker runtimes. Its CPU/Wasm
results do not establish hardware WebGPU acceleration or cancellation latency.
The TTS recipe uses explicit batch 512 and micro-batch 256; it does not qualify
the default context-sized batch profile. See [the test matrix](testing_matrix.md#web-speech-task-cancellation)
for the bounded controls and the non-isolated test harness's larger-batch
observation.

### Completion termination

With `supportsCompletionUsage`, the backend consumes `onUsage.finishReason`
in both direct and worker runtimes. Only the literal `length` reports a
runtime generation limit. Public completions end with `length` and tool loops
return `truncated`, rolling back the turn. `stop`, `cancelled`, missing or
unrecognized reasons do not establish a limit; errors, local stop sequences
and cancellation suppress limit metadata. Older bridges without the usage
probe receive no callback and retain their existing stop behavior.

The pinned bridge combines `nPredict`, context exhaustion and its
`mediaMaxPredict` cap under `length`; token counts cannot reliably identify the
cause. The backend reports `BackendGenerationLimit.runtime` rather than guessing
`maxTokens` or `contextSize`. Typed Web speech recognition raises
`LlamaSpeechTranscriptTruncatedException` with `LlamaSpeechTranscriptLimit.runtime`
and the partial transcript when this signal arrives.

## Safari compatibility

The fetch script and `example/chat_app/web/index.html` no longer patch bridge
assets for Safari; the bridge assets own the Safari gate and stream chunk
handling.

`WebGpuLlamaBackend` forces CPU on Safari when GPU layers are requested and the
assets lack the adaptive Safari probe (`__llamadartBridgeAdaptiveSafariGpu`).
Adaptive assets keep GPU enabled, run a short generation probe, and cap GPU
layers or fall back to CPU when output looks unstable.
`window.__llamadartAllowSafariWebGpu = true` bypasses the safeguard.

## Browser compatibility targets

- Chrome 128+
- Firefox 129+
- Safari 17.4+

WebGPU availability still depends on the device and browser settings; CPU runs
through the same bridge.

## Model caching

Bridge model fetches use browser Cache Storage by default (`useCache: true` in
web backend load options).

- The first load of a model URL fetches from the network and stores it in the
  cache; later loads of the same URL can come from the cache.
- Model URLs with userinfo, a fragment or a credential-like query key (such as
  `token`, `key`, `sig`, `signature`, `expires`, `session`, or any `x-amz-*` or
  `x-goog-*` key) are treated as credential-sensitive: `llamadart` passes
  `useCache: false`, so the bridge loads them with no persistent Cache Storage
  key. Other query strings, such as Hugging Face's `?download=true`, keep the
  cache; `hasPersistentCacheSensitiveUrlParts` applies the rule.
- Multimodal projector loads are direct bridge fetches and do not use the
  model cache.
- Cache availability depends on browser storage quota and private-mode policy.
  Chromium keeps Cache Storage in memory in Incognito windows and other
  off-the-record profiles, including Playwright's `browser.new_context()`, and
  rejects any entry of 256 MiB or more with `Failed to execute 'put' on
  'Cache': Unexpected internal error.` The bridge then logs `Model was not
  cached`, reports `model_cache_state` `store_failed` and still loads the
  model; the next load fetches it again
  ([#1675](https://github.com/leehack/llamadart/issues/1675)).

## Hosting headers

Large single-file GGUF loads are only reliable when the page is cross-origin
isolated (`Cross-Origin-Opener-Policy: same-origin`,
`Cross-Origin-Embedder-Policy: require-corp`; `credentialless` isolates only in
Chromium-based browsers, see
[#1025](https://github.com/leehack/llamadart/issues/1025)). Without it
the bridge caps threads to one, and fetch-backed loading fails with
thread-constructor errors.

For Hugging Face Spaces with `sdk: static`, set the headers in the Space
README frontmatter; keys and values must be lowercase:

```yaml
custom_headers:
  cross-origin-embedder-policy: require-corp
  cross-origin-opener-policy: same-origin
  cross-origin-resource-policy: cross-origin
```

`.github/workflows/chat_app_hf_static_deploy.yml` injects these into the
generated Space README.

## Smoke tests

```bash
dart run tool/testing/run_local_e2e.dart --scenario chat-app-web-mock-smoke

dart run tool/testing/run_local_e2e.dart --scenario chat-app-web-real-model-smoke \
  --model-url http://127.0.0.1:7358/example/llamadart_server/models/Qwen3.5-0.8B-Q4_K_M.gguf \
  --allow-any-response
```

The runner builds the chat app with `scripts/build_chat_app_web.sh` (matching
`--base-href`, pinned bridge assets), serves the repo root with COOP/COEP
headers through `tool/testing/serve_static_with_headers.py`, and runs the
Playwright helper. When running helpers by hand, keep `--base-href` aligned
with the URL path.

The real-model smoke also requires `getCompletionCapabilities()` to report
`penaltyPromptTokens: true` and a plain chat call to carry no
`penaltyPromptTokens` option. `chat-app-web-tool-penalty-smoke` runs a
`ToolChoice.auto` chat on a tool-capable `--model-url` and requires the
`lazyGrammar` probe, a lazy grammar with triggers and no `penaltyPromptTokens`
override on the completion.

On macOS headless Chromium, keep the smoke script's default
`--browser-angle auto` or pass `--browser-angle metal`. Without Metal ANGLE the
adapter can lack `shader-f16`, and llama.cpp may abort in `ggml-webgpu` even on
`gpuLayers = 0` runs.

## Expected global

```js
window.LlamaWebGpuBridge = class LlamaWebGpuBridge {
  constructor(config) {}
};
```

## Required methods

`WebGpuLlamaBackend` can use these methods if present:

- `loadModelFromUrl(url, { nCtx, nThreads, nThreadsBatch, nBatch, nUbatch, nGpuLayers, nSeqMax, flashAttention, cacheTypeK, cacheTypeV, kvUnified, ropeFrequencyBase, ropeFrequencyScale, splitMode, mainGpu, useCache, forceRemoteFetchBackend, remoteFetchChunkBytes, loadMtp, speculativeRollbackTokenMax, progressCallback })`
- `prefetchModelToCache(url, { useCache, force, cacheName, progressCallback })`
- `evictModelFromCache(url, { cacheName })`
- `loadMultimodalProjector(url)`
- `unloadMultimodalProjector()`
- `supportsVision()`
- `supportsAudio()`
- `createCompletion(prompt, { nPredict, temp, topK, topP, minP, penalty, presencePenalty, penaltyPromptTokens, seed, grammar, grammarLazy, grammarTriggers, grammarRoot, thinkingBudget, speculativeDecoding, onToken, parts, signal })`
- `getCompletionCapabilities()`
- `loadDraftModel(url, { useCache, signal })`
- `unloadDraftModel()`
- `getLoraAdapterCapabilities()`
- `loadLoraAdapter(url, { useCache })`
- `setLoraAdapter(handle, scale)`
- `removeLoraAdapter(handle)`
- `clearLoraAdapters()`
- `tokenize(text, addSpecial)`
- `detokenize(tokens, special)`
- `stateSaveFile(path, tokens)`
- `stateLoadFile(path, tokenCapacity)`
- `getEmbeddingCapabilities()` (API version 1, assets v0.1.64+)
- `embed(input, { normalize })` (string or ordered content parts)
- `embedBatch(inputs, { normalize })`
- `getModelMetadata()`
- `getContextSize()`
- `cancel()`
- `dispose()`
- `applyChatTemplate(messages, addAssistant, customTemplate)`
- `getDecisionCapabilities()`
- `loadDecisionHead(url, { configJson })`
- `runDecision(handle, sequences)`
- `freeDecisionHead(handle)`
- `isGpuActive()`
- `getBackendName()`

## Capability gates

`WebGpuLlamaBackend` gates these options on runtime probes, not on an asset
tag:

- After each model load it calls `getCompletionCapabilities()` once. It sends
  a non-zero `minP` or `presencePenalty`, or a `thinkingBudget`, only when the
  probe reports that flag `true`; otherwise `generate` throws before calling
  the bridge. A missing method, a failed probe or a non-boolean flag counts as
  unsupported. Default values are sent as `null`, which older assets ignore.
  `generationCapabilities()`, read through `LlamaEngine.capabilities`,
  reports the same flags.
  Source: [llama-web-bridge#140](https://github.com/leehack/llama-web-bridge/pull/140)
  and [#144](https://github.com/leehack/llama-web-bridge/pull/144).
- Lazy grammars and custom grammar roots require `lazyGrammar: true` from the
  same strict per-load probe (`v0.1.75+` assets). Missing/failed probes and
  non-boolean flags mean unsupported. `supportsLazyGrammar` reports the same
  result. Explicit lazy/custom-root requests reject before bridge dispatch on
  unsupported cores. Supported cores receive `grammarLazy`, `grammarRoot` and
  string-named `word`, `token`, `pattern`, `pattern-full` triggers in both direct
  and worker modes. Dart's word/token wire integers differ from the bridge's
  core integers, so they are never forwarded directly. Token triggers accept
  `token` or a numeric `value`; invalid/missing token ids reject as arguments.
  Empty whole-output patterns become `^$`, as native does. Empty word/pattern
  values and NUL text reject through the bridge's typed validators.
  With a supported lazy template grammar, the planner keeps its grammar,
  triggers and preserved tokens and sends no penalty prompt override. Older
  cores retain generic best-effort auto parsing and the existing override.
  A post-probe core capability rejection remains `LlamaUnsupportedException`.
  `web-lazy-grammar` checks real CPU Wasm activation and recovery in both
  runtimes. It does not qualify hardware WebGPU or LFM2 auto grammar (#1715).
- A core whose probe reports `penaltyPromptTokens: true` counts a text
  prompt without a `grammar` in the `penalty` and `presencePenalty` window, as
  native does. When `ToolChoice.auto` drops a lazy tool-call grammar, the
  engine marks the request and the backend sends `penaltyPromptTokens: false`,
  because native keeps that grammar and so never counts the prompt. On cores
  without the flag it sends nothing: they never count the prompt and never
  reject. `grammar` passes through unchanged; an empty string counts as a
  grammar there, so it is never normalized to `null`. No public capability
  reports this. Source:
  [llama-web-bridge#187](https://github.com/leehack/llama-web-bridge/pull/187).
- Assets v0.1.82+ can report `penaltyPromptTokensWithGrammar: true`.
  `BackendPromptPenaltyGeneration` uses that loaded-core probe and sends the
  matching opt-in only on its explicit text-only, attached-grammar route.
  The prompt seeds the penalty sampler without activating lazy grammar or
  reasoning. Missing, false and non-boolean probes, media, absent grammar and
  conflicting prompt exclusion reject before dispatch. Ordinary generation
  omits the new option; grammar defaults stay unchanged. A subsequent core
  capability refusal remains a typed `LlamaUnsupportedException`.
- Every `setLoraAdapter`, `removeLoraAdapter` and `clearLoraAdapters` call
  first checks that all five LoRA methods exist and that
  `getLoraAdapterCapabilities()` reports `apiVersion: 1` and
  `supported: true`; otherwise it throws `UnsupportedError`, which
  `LlamaEngine` reports as `LlamaUnsupportedException`. Each path is loaded
  once per model load and mapped to its bridge handle. `contextCreate`
  applies `ModelParams.loras` through the same calls after the model loads;
  when one fails it clears the adapters and throws, and `LlamaEngine` then
  frees the model. Source:
  [llama-web-bridge#142](https://github.com/leehack/llama-web-bridge/pull/142).
- Speculative decoding reads `speculativeDecoding` from the same probe, a map
  from llama.cpp strategy name to boolean. With no n-gram strategy `true`, no
  strategy is supported. Otherwise the n-gram strategies and `draft-mtp` count
  when `true`, `backendDefault` when `ngram-mod` does, and `draft-simple`,
  `draft-eagle3`, `draft-dflash` and `draft-dspark` when present as booleans
  and `loadDraftModel` and `unloadDraftModel` exist: the bridge reports them
  `true` only while a matching draft is loaded, and generation loads it. A
  request with another strategy throws `UnsupportedError` before calling the
  bridge. Before a draft-model generation the backend loads the draft URL
  unless it is loaded and the probe still reports the strategy, then probes
  again; if the strategy is still unreported it unloads the draft and throws
  `LlamaUnsupportedException`, as it does when `loadDraftModel` rejects a
  draft for the target's hidden size. `ModelParams.loadMtp` and a positive
  `speculativeRollbackTokenMax` are sent as load options. Source:
  [llama-web-bridge#153](https://github.com/leehack/llama-web-bridge/pull/153).

`test/e2e/webgpu/generation_features_e2e_test.dart` (local-only) checks these
gates against real assets and models; its header lists the setup.
`test/e2e/webgpu/bridge_runtime_fixes_e2e_test.dart` (local-only) checks the
`v0.1.67+` state-file, relative-URL and reload behavior, the `v0.1.69+`
truncated-snapshot rejection and the `v0.1.73+` string embedding rejections,
in both runtimes.

## Notes

- The web backend is GGUF URL-based (`modelLoadFromUrl`). If the bridge does
  not activate, model loading fails; there is no alternate web backend for
  GGUF.
- The bridge comes from a preloaded `window.LlamaWebGpuBridge`, or from the
  internal `WebGpuLlamaBackend(bridgeScriptUrl: ...)` constructor, which is not
  exported from `package:llamadart`.
- Large model URL loads can use a worker-thread fetch-backed path to reduce
  contiguous `ArrayBuffer` pressure, but only after an explicit opt-in.
- With media parts the bridge reads its marker `<__media__>` and the
  placeholders it rewrites to it (`<image>`, `[IMG]`, `<|image|>`, `<img>`,
  `<|img|>`, `<|vision_start|><|image_pad|><|vision_end|>` and its
  `video_pad` form, `<audio>`, `<|audio|>`, `<|image_N|>`, `<|audio_N|>`) as
  a part wherever they are in the prompt, and the pinned assets have no
  option that turns this off. For a prompt that `LlamaEngine.create` rendered,
  `WebGpuLlamaBackend` writes `<__media__>` where each part was and puts a
  zero-width space after the first character of any such string in the rest,
  so a message that quotes one is not read as media. A prompt passed to
  `generate` goes to the bridge as written. A bridge option that takes the
  marker with the request would make the zero-width space unnecessary.
- Bridge runtimes can provide `llama_webgpu_core_mem64.js/.wasm`. When the
  page sets `__llamadartBridgeCoreModuleUrlMem64` and memory64 is preferred,
  the bridge tries the wasm64 core first and falls back to wasm32.

## Runtime globals read by `llamadart`

- `window.__llamadartBridgeAllowAutoRemoteFetchBackend`: default `false`;
  streamed staging stays the default. `true` only for a controlled origin that
  serves valid GGUF byte ranges; it also lets Dart recovery paths retry with
  fetch-backed loading after a streamed staging failure.
- `window.__llamadartBridgeForceRemoteFetchBackend`: default `false`. `true`
  forces fetch-backed loading from the first attempt, for diagnostics only.
- `window.__llamadartBridgeRemoteFetchChunkBytes`: positive integer bytes;
  default `4 * 1024 * 1024`, clamped to 4 KiB..16 MiB. Applies to fetch-backed
  loading.
- `window.__llamadartBridgeThreadPoolSize`: positive thread-count hint used to
  avoid pthread pool exhaustion; match the bridge build's `PTHREAD_POOL_SIZE`.
- `window.__llamadartBridgePreferMemory64`: memory64 preference when neither
  `ModelParams.preferMemory64` nor `ModelParams.modelBytesHint` decides.
- `window.__llamadartBridgeSpeechToTextSupported`: `true` enables typed
  Qwen3-ASR; required even for validated `v0.1.30+` assets.
- `window.__llamadartAllowSafariWebGpu`,
  `window.__llamadartBridgeAdaptiveSafariGpu`: see
  [Safari compatibility](#safari-compatibility).

## Request errors

Invalid WebGPU request arguments surface as `LlamaArgumentException`;
capability rejections remain `LlamaUnsupportedException`. `scoreNextToken`
keeps `RangeError` for int32 bounds and vocabulary errors, matching the
engine/native contract. Generation, embedding and scoring runtime failures
remain `LlamaInferenceException`; LoRA fetch failures remain `LlamaModelException`.

JS `TypeError` and `RangeError` alone cannot identify argument failures:
network/CORS fetches reject with `TypeError`, and stack/allocation failures can
be `RangeError`. The classifier requires an anchored validator message from the
pinned bridge and a JS error name of `TypeError`, `RangeError` or `Error` on
both direct and worker paths. Unknown messages retain the operation's fallback.
The allowlist covers these TypeError/RangeError emissions in the
[original validator JavaScript](https://github.com/leehack/llama-web-bridge-assets/blob/c1665e3c9a38b78c553806f590f7948b36c8d148/llama_webgpu_bridge.js):

| Lines | Validator prefixes / fields |
| --- | --- |
| [46–81](https://github.com/leehack/llama-web-bridge-assets/blob/c1665e3c9a38b78c553806f590f7948b36c8d148/llama_webgpu_bridge.js#L46-L81) | `CompletionOptions.minP`, `presencePenalty`; `thinkingBudget` object, `maxTokens`, `startTag`, `endTag`, `forcedMessage` |
| [86–149](https://github.com/leehack/llama-web-bridge-assets/blob/c1665e3c9a38b78c553806f590f7948b36c8d148/llama_webgpu_bridge.js#L86-L149) | `CompletionOptions.speculativeDecoding` object/strategies; integer fields `draftTokenMax`, `draftTokenMin`, `ngramSizeN`, `ngramSizeM`, `ngramMinHits`, `ngramMatch`, `ngramTokenMin`, `ngramTokenMax`; probabilities `minProbability`, `draftSplitProbability`; cache source/type/empty validators `ngramCacheStatic`, `ngramCacheDynamic` |
| [180–205](https://github.com/leehack/llama-web-bridge-assets/blob/c1665e3c9a38b78c553806f590f7948b36c8d148/llama_webgpu_bridge.js#L180-L205) | `ngramTokenMin` / `draftTokenMin` must-not-exceed limits |
| [471–483](https://github.com/leehack/llama-web-bridge-assets/blob/c1665e3c9a38b78c553806f590f7948b36c8d148/llama_webgpu_bridge.js#L471-L483) | `LoRA adapter handle`, `LoRA adapter scale` finite/float32 |
| [3728](https://github.com/leehack/llama-web-bridge-assets/blob/c1665e3c9a38b78c553806f590f7948b36c8d148/llama_webgpu_bridge.js#L3728), [7052](https://github.com/leehack/llama-web-bridge-assets/blob/c1665e3c9a38b78c553806f590f7948b36c8d148/llama_webgpu_bridge.js#L7052) | `LoRA adapter source` type |
| [1001–1014](https://github.com/leehack/llama-web-bridge-assets/blob/c1665e3c9a38b78c553806f590f7948b36c8d148/llama_webgpu_bridge.js#L1001-L1014), [4389–4400](https://github.com/leehack/llama-web-bridge-assets/blob/c1665e3c9a38b78c553806f590f7948b36c8d148/llama_webgpu_bridge.js#L4389-L4400) | `Next-token candidates` shape/int32, `Next-token scoring prompt`, `Next-token topK` int32 |

Completion sampling validation happens in the facade before routing
([line 6153](https://github.com/leehack/llama-web-bridge-assets/blob/c1665e3c9a38b78c553806f590f7948b36c8d148/llama_webgpu_bridge.js#L6153));
LoRA scale validation does too
([lines 7078–7079](https://github.com/leehack/llama-web-bridge-assets/blob/c1665e3c9a38b78c553806f590f7948b36c8d148/llama_webgpu_bridge.js#L7078-L7079)).
Runtime-side validators such as next-token candidate checks can pass through
`serializeWorkerError`, which sends only `error.message`
([lines 4558–4573](https://github.com/leehack/llama-web-bridge-assets/blob/c1665e3c9a38b78c553806f590f7948b36c8d148/llama_webgpu_bridge.js#L4558-L4573));
`BridgeWorkerProxy` reconstructs an ordinary `Error`
([lines 4705–4714](https://github.com/leehack/llama-web-bridge-assets/blob/c1665e3c9a38b78c553806f590f7948b36c8d148/llama_webgpu_bridge.js#L4705-L4714)).
The shared message allowlist preserves classification across that transport;
it does not infer argument provenance from a JS error name alone.

The classifier is separate from operation fallbacks. Media embeddings map the
pinned API's stable `EmbeddingError.code` values to argument, unsupported and
inference exceptions, preserving known codes (including `EMBEDDING_INPUT_TOO_LARGE`
and `EMBEDDING_FAILED`) and the `aborted` runtime label without copying diagnostic
payloads. Unknown codes are omitted. The string path has no stable code, so
its v0.1.73+ rank-pooling and one-pass overflow rejections are matched on the
core's exact message, prefix included; any other message stays an inference
error. Reserved mixed-input media markers are
rejected as unsupported before dispatch, matching native.

Lazy-grammar option validators in the pinned facade
(`llama_webgpu_bridge.js`, `grammarTrigger` / `grammarOptions`) use the same
anchored argument allowlist in both runtimes. The core's exact invalid-grammar
and rejected-trigger messages map to `LlamaInferenceException`, matching native
grammar initialization failures. Worker transport retains these messages and
does not retry deterministic grammar errors on the main thread.
