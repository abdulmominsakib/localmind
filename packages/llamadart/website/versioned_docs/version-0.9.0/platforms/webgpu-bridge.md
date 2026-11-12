---
title: WebGPU bridge for browser inference
sidebar_label: WebGPU bridge
description: Add the llamadart WebGPU bridge to a Flutter Web app, check browser readiness, size models for memory64, and read fallback and troubleshooting behavior.
---

On the web, `llamadart` runs GGUF models through an external JavaScript
bridge that wraps llama.cpp. The bridge uses WebGPU when the browser and device
support it and runs on the WebAssembly CPU path otherwise. `.litertlm` models
use `@litert-lm/core` instead; see
[Support matrix](./support-matrix#features-by-runtime).

:::warning Experimental web runtime
Treat WebGPU as a runtime capability, not a compile-time promise: a browser can
load the app and still lack an adapter, device features, memory headroom or
compatible bridge assets for a given model.
:::

## Requirements

| Browser | Minimum | Notes |
| --- | --- | --- |
| Chrome, Chromium, Edge | 128 | Best-supported path. |
| Firefox | 129 | WebGPU can depend on browser configuration. |
| Safari | 17.4 | GPU generation can be unstable with older bridge assets. |

- **Secure context**: serve from `https://`, `http://localhost` or
  `http://127.0.0.1`. WebGPU is unavailable on other insecure origins.
- **Cross-origin isolation**: send these headers from the app origin so the
  bridge can run worker threads:

  ```http
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Embedder-Policy: require-corp
  ```

  `Cross-Origin-Embedder-Policy: credentialless` also works. Without isolation
  (`window.crossOriginIsolated === false`) the bridge caps inference at one
  thread and records `threads_capped_no_coi` in its runtime notes.

A supported browser version does not guarantee that a GGUF loads with WebGPU
offload; the GPU, driver, OS, flags and memory pressure all matter.

## Add the bridge to your app

`llamadart` does not inject the bridge script. The app must load it in
`web/index.html` before the first model load. Serve the bridge assets from the
app origin: the bridge core starts its worker threads from its own URL, and a
cross-origin isolated page cannot start workers from a CDN URL.

Download the assets into `web/webgpu_bridge/`, with `TAG` set to the tag in
[Pinned bridge assets](#pinned-bridge-assets):

```bash
TAG=vX.Y.Z
mkdir -p web/webgpu_bridge
for f in llama_webgpu_bridge.js llama_webgpu_bridge_worker.js \
         llama_webgpu_core.js llama_webgpu_core.wasm \
         llama_webgpu_core_mem64.js llama_webgpu_core_mem64.wasm; do
  curl -fL -o "web/webgpu_bridge/$f" \
    "https://cdn.jsdelivr.net/gh/leehack/llama-web-bridge-assets@$TAG/$f"
done
```

In a llamadart checkout, `scripts/fetch_webgpu_bridge_assets.sh` with
`WEBGPU_BRIDGE_OUT_DIR=<app>/web/webgpu_bridge` does the same and verifies
checksums.

Then load the bridge in `web/index.html`, before `flutter_bootstrap.js`:

```html
<script type="module">
  try {
    const base = new URL('webgpu_bridge/', document.baseURI);
    window.__llamadartBridgeCoreModuleUrlMem64 =
      new URL('llama_webgpu_core_mem64.js', base).href;
    window.__llamadartBridgeSpeechToTextSupported = true;
    const mod = await import(new URL('llama_webgpu_bridge.js', base).href);
    window.__llamadartBridgeAdaptiveSafariGpu =
      mod.LlamaWebGpuBridge.supportsSafariAdaptiveGpu === true;
    window.LlamaWebGpuBridge = mod.LlamaWebGpuBridge;
  } catch (error) {
    window.__llamadartBridgeLoadError = String(error);
  }
</script>
<script src="flutter_bootstrap.js" async></script>
```

- `__llamadartBridgeCoreModuleUrlMem64` enables the memory64 core; without it
  only the 32-bit core loads.
- `__llamadartBridgeSpeechToTextSupported` opts into Qwen3-ASR; set it only
  for official assets `v0.1.30` or newer.
- `__llamadartBridgeAdaptiveSafariGpu` lets Safari keep GPU layers when the
  assets support the adaptive probe.

At model load, `llamadart` waits up to 12 seconds for
`window.LlamaWebGpuBridge`, and stops early once `__llamadartBridgeLoadError`
is set. If the bridge never appears, the load throws `LlamaUnsupportedException`
whose message contains
`Web bridge is unavailable. Ensure LlamaWebGpuBridge assets are loaded and reachable.`
or `Web bridge is unavailable: <load error>`.

`example/chat_app/web/index.html` is a fuller bootstrap: CDN-first loading with
local fallback, Safari patching and a readiness promise; see
[`doc/webgpu_bridge.md`](https://github.com/leehack/llamadart/blob/main/doc/webgpu_bridge.md).

## Check readiness

Paste this into the browser console of the running app:

```js
const adapter = await navigator.gpu?.requestAdapter();
console.table({
  secureContext: window.isSecureContext,
  crossOriginIsolated: window.crossOriginIsolated,
  hasAdapter: !!adapter,
  adapterFeatures: adapter ? [...adapter.features].join(', ') : '',
  bridgeLoaded: typeof window.LlamaWebGpuBridge === 'function',
  bridgeLoadError: window.__llamadartBridgeLoadError || '',
  mem64CoreUrl: window.__llamadartBridgeCoreModuleUrlMem64 || '',
  workerFallbackReason: window.__llamadartBridgeWorkerFallbackReason || '',
});
```

The page is ready when it is a secure context, `bridgeLoaded` is `true`,
`bridgeLoadError` is empty, and an adapter exists. Without an adapter, load
with `gpuLayers: 0` or switch browsers. Large single-file models also need
`crossOriginIsolated`.
For a first load, use a small quantized GGUF, `contextSize` of `2048` or less,
and `gpuLayers: 0` to prove CPU loading before raising GPU offload.

## Model size and memory64

The 32-bit core has a 4 GiB address space, which must also hold the KV cache
and intermediate buffers. `llamadart` selects the 64-bit (memory64) core when
`ModelParams.preferMemory64` is `true`, or when it is `null` and
`ModelParams.modelBytesHint` is at least 2 GiB. `false` selects the 32-bit
core, though a load that aborts or runs out of memory on it is retried on
memory64. Otherwise, the pinned bridge starts on memory64 whenever
`__llamadartBridgeCoreModuleUrlMem64` is set, as in the snippet above; set
`window.__llamadartBridgePreferMemory64 = false` to start on the 32-bit core
instead. Pass the model size when you know it:

```dart
await engine.loadModelFromUrl(
  modelUrl,
  modelParams: const ModelParams(
    modelBytesHint: 3043927168,
    contextSize: 2048,
  ),
);
```

Pass the size up front: the retry from wasm32 to wasm64 after an out-of-memory
failure is slower and best-effort. Both fields apply only on the web and need
the memory64 core URL from
[Add the bridge to your app](#add-the-bridge-to-your-app). Qwen3-TTS needs
memory64.

## What differs from native

The feature-by-runtime table is in the
[support matrix](./support-matrix#features-by-runtime). On WebGPU:

- `grammar` applies from the first token, starting at `root`.
  `GenerationParams.grammarLazy` and any other `grammarRoot` throw
  `LlamaUnsupportedException`; `ToolChoice.auto` skips the lazy tool-call
  grammar ([Tool calling](../guides/tool-calling#tool-choice-semantics)).
- Speculative decoding needs bridge assets whose
  `getCompletionCapabilities()` reports `speculativeDecoding` strategies:
  bridge assets `v0.1.54+`, the default pin among them
  ([llama-web-bridge#153](https://github.com/leehack/llama-web-bridge/pull/153)).
  A strategy the loaded assets do not report, and every strategy on older
  assets, throws `LlamaUnsupportedException`. With such assets:
  - Each strategy runs llama.cpp's `--spec-type` of the same name, validated
    as on native. `backendDefault` and `speculativeDecoding: true` run
    `ngram-mod`, as on native.
  - `draftModelPath` is a URL. The bridge holds one draft model: the first
    generation that needs it loads it, through Cache Storage unless the URL
    carries credentials, and it stays loaded until another draft replaces it
    or a model loads. Cancelling the generation cancels the load. A draft
    that cannot run the requested strategy, or an EAGLE3 or DFlash draft
    built for another hidden size, is not kept and throws
    `LlamaUnsupportedException`; one the bridge cannot fetch or load throws
    `LlamaModelException`.
  - `mtp` runs the model's own MTP layers, so load the model with
    `ModelParams(loadMtp: true)`; an MTP `draftModelPath` throws
    `LlamaUnsupportedException`.
  - The n-gram cache paths are URLs, sent only with `ngram-cache`, as native
    uses them only there. The bridge never writes the dynamic cache back.
  - A model with recurrent state, such as Qwen3.5, needs
    `ModelParams.speculativeRollbackTokenMax` of at least the draft length for
    `mtp` and the draft-model strategies. N-gram strategies need none: the
    bridge replays accepted tokens after a rejection.
  - N-gram sizes above 65535 throw `RangeError`.
  - The draft and acceptance counts are not reported:
    `LlamaEngine.getPerformanceContext()` returns null on WebGPU.
- `presencePenalty`, `minP` and `thinkingBudget` need bridge assets whose
  `getCompletionCapabilities()` reports them; runtime LoRA (`setLora`,
  `removeLora`, `clearLoras`) needs assets whose
  `getLoraAdapterCapabilities()` reports support: bridge assets `v0.1.54+`,
  the default pin among them. On older assets a non-zero `presencePenalty` or
  `minP`, any `thinkingBudget` and every LoRA call throw
  `LlamaUnsupportedException`.
  `LlamaEngine.backendGenerationCapabilities` reports the completion
  capabilities of the loaded assets. The capabilities come from
  [llama-web-bridge#140](https://github.com/leehack/llama-web-bridge/pull/140),
  [#144](https://github.com/leehack/llama-web-bridge/pull/144) and
  [#142](https://github.com/leehack/llama-web-bridge/pull/142).
- The bridge's repeat and presence penalties see only the tokens generated by
  the current request; native llama.cpp also counts the prompt when no grammar
  is set, so seeded output can differ. A thinking budget is text-only. A LoRA path is a URL that the bridge downloads once per model
  load, through Cache Storage unless the URL carries credentials; reload
  adapters after loading another model. An aLoRA adapter throws
  `LlamaUnsupportedException`, and an adapter the bridge cannot load, such as
  one made for another base model, throws `LlamaModelException`.
- A stop sequence equal to a `preservedTokens` entry is ignored, as on native
  llama.cpp.
- State files live in the bridge's WASMFS virtual filesystem and do not
  survive a page reload.
- Model and projector loads take URLs; local file paths are native-only.
- `LlamaEngine.scoreNextToken(...)` needs bridge assets `v0.1.52+`; older
  assets report `supportsNextTokenScoring == false`.

## Fallback behavior

Before failing a load, the web backend retries with safer settings:

- If GPU layers were requested, it retries on CPU (`nGpuLayers = 0`), first at
  the same context size, then at smaller ones.
- It steps the context size down through bounded candidates when the browser
  cannot fit the requested context.
- Qwen3.5-0.8B WebGPU loads are capped to a small GPU-layer count unless CPU is
  requested.
- With older Safari bridge assets, it forces CPU unless the assets support the
  adaptive Safari GPU probe or `window.__llamadartAllowSafariWebGpu = true`.
- It retries on the other core (wasm32 or wasm64) when bridge metadata points
  to an interop or memory-pressure failure. A large wasm32 staging abort is
  treated as memory pressure and retried on wasm64 when available.
- Fetch-backed loading is off by default and never used for retries unless the
  page opts in (see [Advanced overrides](#advanced-overrides)).
- Qwen3-TTS on bridge assets `v0.1.34+` retries a failed worker WebGPU
  synthesis once on the main thread with the cached model and projector bytes.
  Eligible WebGPU errors and generic worker timeouts retry with CPU-only
  settings; the exact `worker request timeout` and `worker init timeout`
  errors keep the original GPU offload. Models already on CPU are not retried,
  cancellation wins over recovery, and other errors propagate unchanged. The
  retry is slower, does not loop, and does not make up for too little browser
  memory; see the
  [bridge recovery contract](https://github.com/leehack/llama-web-bridge/blob/65622b297b83513db597a760fa067867755010b4/docs/api.md#synthesizespeechoptions).

When retries run out, the load throws an error with runtime hints such as
`core`, `source`, `nThreads`, `nGpuLayers`, `cache` and bridge `notes`.

## Troubleshooting map

| Symptom | Likely class | Next check |
| --- | --- | --- |
| `Web bridge is unavailable` | Bridge not loaded | [Add the bridge to your app](#add-the-bridge-to-your-app); check `window.__llamadartBridgeLoadError` and asset URLs. |
| `navigator.gpu` missing or no adapter | Browser or device | Use a secure context, update browser and drivers, or run CPU or native. |
| `thread constructor failed`, `error 138`, or `Browser runtime blocked worker thread creation` | Cross-origin isolation | Send COOP/COEP headers and check `window.crossOriginIsolated`, or use a smaller or sharded model. |
| Memory, OOM, `bad_alloc` or abort during load | Model or config pressure | Reduce model size, context, threads or GPU layers; use memory64. |
| Safari forces CPU | Safari safeguard | Set `__llamadartBridgeAdaptiveSafariGpu` from the loaded assets, or `__llamadartAllowSafariWebGpu` for testing. |
| Works on `localhost` but not hosted | Deployment | Check base href, asset paths, COOP/COEP headers and service-worker cache. |
| GPU output unstable, CPU fine | Adapter, feature or driver | Check adapter features such as `shader-f16`; lower GPU layers. |

More cases: [Troubleshooting](../troubleshooting/common-issues#web).

## Advanced overrides

`llamadart` reads these globals when it creates the bridge. Set them before the
first model load, for diagnosis or controlled deployments:

| Global | Effect |
| --- | --- |
| `__llamadartBridgeCoreModuleUrl`, `__llamadartBridgeWasmUrl` | wasm32 core module and `.wasm` URLs; default next to the bridge module |
| `__llamadartBridgeCoreModuleUrlMem64`, `__llamadartBridgeWasmUrlMem64` | memory64 core module and `.wasm` URLs |
| `__llamadartBridgeWorkerUrl` | Dedicated worker module URL |
| `__llamadartBridgePreferMemory64` | memory64 preference when neither `preferMemory64` nor `modelBytesHint` decides |
| `__llamadartBridgeThreadPoolSize` | Thread-count hint; match the bridge build's pthread pool |
| `__llamadartBridgeAllowAutoRemoteFetchBackend` | `true` enables fetch-backed loading and its retries, for an origin that serves valid GGUF byte ranges |
| `__llamadartBridgeForceRemoteFetchBackend` | `true` forces fetch-backed loading from the first attempt; diagnostics only |
| `__llamadartBridgeRemoteFetchChunkBytes` | Fetch-backed chunk size; default 4 MiB, clamped to 4 KiB to 16 MiB |
| `__llamadartAllowSafariWebGpu` | `true` bypasses the Safari CPU safeguard |

## Pinned bridge assets

The example currently pins bridge assets to `v0.1.54`, with local vendored assets
identified as `v0.1.54-local-v0.5.0`.

- The pinned `v0.1.54` bridge assets embed llama.cpp `v0.5.0`, matching the native runtime
  (`v0.5.0`, both built from upstream `v0.5.0@7fe450e19305b828c199d602c23a8337aaa1f03b`)
  even though the bridge asset tag `v0.1.54` differs from the native runtime tag
  `v0.5.0`. Pinned artifact provenance: release `397350529`, tag commit
  `e161182a09ac560d45ad5e65bb499574f913a466`, bridge source
  `65622b297b83513db597a760fa067867755010b4`, manifest SHA-256
  `8a9f83c15035eeb034a6563e6f753382d7d7f9be81503ef76902138da7841176`.

In a llamadart checkout, vendor the pinned assets into the chat app with:

```bash
WEBGPU_BRIDGE_ASSETS_TAG=v0.1.54 ./scripts/fetch_webgpu_bridge_assets.sh
```

The chat app bootstrap takes its CDN source from these globals:

```html
<script>
  window.__llamadartBridgeAssetsRepo = 'leehack/llama-web-bridge-assets';
  window.__llamadartBridgeAssetsTag = 'v0.1.54';
</script>
```

Pin a known bridge asset tag in production and check the loaded module URL
before reporting runtime behavior. The bridge JavaScript contract, the chat
app's bootstrap knobs and hosting headers for Hugging Face Spaces are in
[`doc/webgpu_bridge.md`](https://github.com/leehack/llamadart/blob/main/doc/webgpu_bridge.md).
Which repository owns bridge changes:
[Runtime ownership](../maintainers/runtime-ownership).
