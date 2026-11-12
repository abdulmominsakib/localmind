---
name: llamadart-web
description: >-
  Use when running llamadart in a browser or Flutter Web app: adding and
  pinning the WebGPU bridge assets in web/index.html (dart run
  llamadart:web_setup), setting COOP/COEP
  cross-origin isolation headers, loading GGUF models by URL with WebGPU or
  WebAssembly CPU fallback, sizing models for memory64, browser model caching,
  running .litertlm models through @litert-lm/core, or gating web features on
  capability probes and bridge asset versions.
---

# llamadart on the web

On the web, GGUF models run through an app-loaded JavaScript bridge that wraps
llama.cpp (WebGPU, or WebAssembly CPU), and `.litertlm` models run through
`@litert-lm/core`. The web runtime is experimental. Loading and chat basics are
in the llamadart-getting-started and llamadart-chat-streaming skills.

## Guidelines

- Catch `LlamaArgumentException` for WebGPU request argument rejections,
  `LlamaUnsupportedException` for unavailable capabilities, and
  `LlamaInferenceException` for runtime inference failures. `scoreNextToken`
  vocabulary and int32 bounds retain `RangeError`; LoRA fetch failures remain
  `LlamaModelException`.

- Run `dart run llamadart:web_setup` from the app root: it downloads the
  bridge assets the installed llamadart pins into `web/webgpu_bridge/`,
  verifies each against the pinned release manifest, and adds a marked
  bootstrap block to `web/index.html`. Rerun it after upgrading llamadart;
  `--check` verifies without network access of its own (exit `1` lists
  problems; `dart run` may still run native build hooks that download on a
  cold pub cache) and `--no-index-html` leaves the page alone. Do not
  hand-edit the generated block. When switching from a hand-written loader,
  remove it first: the tool refuses a page that already imports
  `llama_webgpu_bridge.js` or assigns `LlamaWebGpuBridge` outside its block.
- llamadart never injects the bridge. Load it in `web/index.html` before
  `flutter_bootstrap.js` (or your compiled script) and assign
  `window.LlamaWebGpuBridge`. At model load llamadart waits up to 12 seconds
  for it, stopping early if `window.__llamadartBridgeLoadError` is set, then
  throws `LlamaUnsupportedException` with `Web bridge is unavailable...`.
- Serve the bridge assets from the app origin (for example
  `web/webgpu_bridge/`), pinned to one tag of
  `leehack/llama-web-bridge-assets`. A cross-origin isolated page cannot start
  the core's worker threads from a CDN URL, so hosted builds must ship the
  core `.js`/`.wasm` files locally even if the bridge module comes from a CDN.
  Do not track a moving tag in production.
- Set `window.__llamadartBridgeCoreModuleUrlMem64` to the local
  `llama_webgpu_core_mem64.js`; without it only the 32-bit core (4 GiB address
  space, shared with the KV cache) loads.
  Assets v0.1.81+ improve large known-size wasm32 model writes, but do not
  increase that address space. Continue to select memory64 for larger models.
- Serve from a secure context (`https://`, `http://localhost` or
  `http://127.0.0.1`) and send `Cross-Origin-Opener-Policy: same-origin` with
  `Cross-Origin-Embedder-Policy: require-corp` (`credentialless` isolates only
  in Chromium-based browsers). Without
  isolation (`window.crossOriginIsolated == false`) the bridge caps inference
  at one thread (`threads_capped_no_coi` in its notes) and large single-file
  GGUF loads become unreliable.
- Treat WebGPU as a runtime capability. A supported browser (Chrome/Edge 128+,
  Firefox 129+, Safari 17.4+) can still lack an adapter, features or memory.
  Prove a first load with a small quantized GGUF, `contextSize: 2048` or less
  and `gpuLayers: 0`, then raise GPU offload.
- `device: ComputeDevice.gpu` requires a WebGPU adapter and active GPU layers
  after load. The bridge ignores negative `mainGpu` values, including with
  `splitMode: ModelSplitMode.none`; use `device: ComputeDevice.cpu` to select
  WebAssembly CPU execution.
- Expect automatic fallback: a failed GPU load retries on CPU, then at smaller
  context sizes, then on the other core (wasm32/wasm64) for memory-pressure
  failures. Safari with assets that lack the adaptive GPU probe is forced to
  CPU. Log `engine.getBackendName()` after load; do not assume GPU ran.
- Models, projectors, draft models, LoRA adapters and n-gram caches are URLs
  on the web, which the runtime fetches itself. Use
  `ModelSource.parse('https://...')` for a remote model or projector; a
  `ModelSource.path` for one is a URL relative to the document, or a `blob:`
  URL. Leave `download:` at `ModelLoadOptions.defaults`: options that need
  the native download manager (bearer tokens or headers, `sha256`,
  `cancelToken`, `cacheDirectory`, `resume: false`, or a cache policy other
  than `preferCached`) throw `LlamaUnsupportedException`. `onProgress`
  reports only the model's fetch; with a projector that fetch fills the first
  half, and progress reaches 1 once the projector has loaded. The model URL must be fetchable from the page (CORS).
- Models are cached in browser Cache Storage keyed by URL, subject to quota and
  private-mode policy. URLs with userinfo, a fragment, or credential-like query
  keys (`token`, `sig`, `key`, `X-Amz-*`, ...) are loaded without a persistent
  cache entry. Projector loads do not use the model cache.
- Pass `ModelParams.modelBytesHint` (web-only) when the size is known: at 2 GiB
  or more llamadart picks the memory64 core up front instead of retrying after
  an out-of-memory failure. `preferMemory64: true`/`false` forces the choice.
  Both are GGUF-on-Web only: native and LiteRT-LM loads throw
  `LlamaUnsupportedException` when either is set, so set them only under
  `kIsWeb` for a GGUF model.
- Gate optional features on probes, not on the browser or the asset tag
  (the tag floors below are for diagnosing old assets only):
  - `await engine.capabilities` for `supportsPresencePenalty`,
    `supportsMinP`, `supportsThinkingBudget` and
    `speculativeDecodingStrategies` (WebGPU rejects
    `SpeculativeDecodingConfig.draftMicroBatchSize`), and for what
    LiteRT-LM web lacks: `supportsPenalty` and `supportsGrammar` are false
    there, and `supportsMultiTurnChat` and `supportsToolCalling` are false
    unless `withTextHistory()` is used and the loaded runtime supports them. Unreported
    controls throw `LlamaUnsupportedException`; `engine.runtime` names the
    runtime, so never sniff the `.litertlm` extension after loading.
  - `engine.supportsNextTokenScoring` and
    `engine.supportsStatePersistence`.
  - Runtime LoRA calls, and loads with `ModelParams.loras`, throw
    `LlamaUnsupportedException` unless the assets report LoRA support.
  - Media embeddings need assets with an API-version-1 embedding
    capability probe and a compatible embedding model/projector. Use encoded
    image/audio bytes or mono 16 kHz Float32 audio PCM; paths and image URLs
    throw `LlamaUnsupportedException`. EmbeddingGemma-2 is qualified on Chrome
    CPU wasm memory64 against native CPU/Metal; repeated media batches are
    qualified only on memory64 (wasm32 is unqualified). Hardware WebGPU is unqualified; default assets include
    the API. Text content preserves legacy unpooled support. Image bytes are
    encoded; embedding calls ignore width/height. Cancelled content calls discard
    late successful bridge results with `LlamaInferenceException`; await the
    future before reuse because synchronous WASM cancellation is cooperative.
  - Qwen3-ASR also needs `window.__llamadartBridgeSpeechToTextSupported =
    true`; Qwen3-TTS needs memory64.
  - For diagnosing old assets, the tag floors are listed once in the docs'
    WebGPU bridge page, "Older bridge assets".
- With the bridge's `supportsCompletionUsage` probe, a runtime
  `length` signal becomes `LlamaFinishReason.length`; `sendWithTools` returns
  `truncated` and rolls back the turn. Normal stop, cancellation and missing
  reasons do not imply a limit. A Web speech transcript that reaches a cap
  throws `LlamaSpeechTranscriptTruncatedException` with
  `LlamaSpeechTranscriptLimit.runtime`: the bridge cannot distinguish output,
  context and media caps. Older bridges cannot report this truncation.
- LFM2 automatic Python tool grammar needs v0.1.82+ loaded-core
  `lazyGrammar` and `penaltyPromptTokensWithGrammar` probes. This route is
  text-only; missing/false capabilities reject before inference. Required/none
  and existing generic auto routing retain their separate behavior.
- WebGPU lazy grammars and custom `grammarRoot` need the loaded core to report
  `lazyGrammar` (`llama-web-bridge-assets` v0.1.75+). Check
  `(await engine.capabilities).supportsLazyGrammar`; an unsupported explicit
  request throws `LlamaUnsupportedException`. Older cores retain best-effort
  auto tool parsing without a lazy grammar. State files live in
  the bridge's WASMFS and are lost on reload; loading a
  missing one throws `LlamaStateException` and the runtime stays usable.
  `getPerformanceContext()` returns null.
- LiteRT-LM on the web: preload `@litert-lm/core` and set
  `window.LiteRtLmEngine = module.Engine`, or set
  `window.__llamadartLiteRtLmModuleUrl` to its module URL. Otherwise the load
  throws `LlamaModelException` whose details say `LiteRT-LM web runtime is not
  loaded`. It needs a `.litertlm` URL and supports CPU or GPU (NPU is
  rejected); any other `ModelParams` field, such as `batchSize`, throws
  `LlamaUnsupportedException`. GPU loads keep the runtime's default backend,
  so `@litert-lm/core@0.19.0` runs `-web.litertlm` bundles and can load
  standard bundles on WebGPU; Gemma 4 bundles do not load on CPU.
- LiteRT-LM web is single-turn text by default: it sends only the last
  message's text, so `ChatSession` history, system prompts and tools are not
  forwarded. `LlamaBackend.withTextHistory()` (or
  `LiteRtLmBackend.withTextHistory()`) opts into ordered system/user/assistant
  text and manual tool calling: `create` returns the runtime's tool calls, and
  you add a tool result message per call before the next `create`.
  `supportsMultiTurnChat` and `supportsToolCalling` report what the loaded
  runtime forwards. A reply cut off at `maxTokens` or the context ends with
  `length` (inferred from the runtime's token counts, after a load probe), so
  `sendWithTools` runs and returns `truncated` for a cut-off reply; a reply
  ending exactly at `maxTokens` also counts as cut off. `ToolChoice.required`
  and `parallelToolCalls` still throw.
  It rejects media parts, grammar, `penalty`, `minP`, `presencePenalty`,
  `thinkingBudget` and speculative decoding; generation honors only
  `maxTokens`, `temp`, `topK`, `topP`, `seed` and `stopSequences`. It has no
  embeddings, tokenizer, LoRA, state or usage. Use GGUF for anything more.
- `flutter build web` only copies what is in `web/`: run the setup tool (or
  commit `web/webgpu_bridge/`) before building, and set the COOP/COEP headers on the
  production host too, not only on the dev server.

## Examples

Set up a Flutter Web app (assets plus `index.html` bootstrap):

```bash
dart run llamadart:web_setup
dart run llamadart:web_setup --check  # in CI, before flutter build web
```

Or fetch the pinned assets by hand, without checksum verification:

```bash
TAG=vX.Y.Z # the tag pinned in the WebGPU bridge docs for your llamadart version
mkdir -p web/webgpu_bridge
for f in llama_webgpu_bridge.js llama_webgpu_bridge_worker.js \
         llama_webgpu_core.js llama_webgpu_core.wasm \
         llama_webgpu_core_mem64.js llama_webgpu_core_mem64.wasm; do
  curl -fL -o "web/webgpu_bridge/$f" \
    "https://cdn.jsdelivr.net/gh/leehack/llama-web-bridge-assets@$TAG/$f"
done
```

Without the tool, load the bridge (and optionally LiteRT-LM) in
`web/index.html`:

```html
<script type="module">
  try {
    const base = new URL('webgpu_bridge/', document.baseURI);
    window.__llamadartBridgeCoreModuleUrlMem64 =
      new URL('llama_webgpu_core_mem64.js', base).href;
    const mod = await import(new URL('llama_webgpu_bridge.js', base).href);
    window.__llamadartBridgeAdaptiveSafariGpu =
      mod.LlamaWebGpuBridge.supportsSafariAdaptiveGpu === true;
    window.LlamaWebGpuBridge = mod.LlamaWebGpuBridge;
  } catch (error) {
    window.__llamadartBridgeLoadError = String(error);
  }
  window.__llamadartLiteRtLmModuleUrl =
    'https://cdn.jsdelivr.net/npm/@litert-lm/core@0.19.0/+esm';
</script>
<script src="flutter_bootstrap.js" async></script>
```

The snippet covers text generation. Qwen3-ASR also needs
`window.__llamadartBridgeSpeechToTextSupported = true`.

Load a GGUF by URL and pick sampling options from the capability probe:

```dart
import 'package:llamadart/llamadart.dart';

Future<LlamaEngine> loadWebModel(String modelUrl, int modelBytes) async {
  final LlamaEngine engine;
  try {
    engine = await LlamaEngine.load(
      LlamaModel(ModelSource.parse(modelUrl)),
      params: ModelParams(contextSize: 2048, modelBytesHint: modelBytes),
      onProgress: (ModelDownloadProgress progress) {
        final double? fraction = progress.fraction;
        if (fraction != null) print('Loading ${(fraction * 100).round()}%');
      },
    );
  } on LlamaUnsupportedException catch (error) {
    // A failed LlamaEngine.load has already disposed its engine.
    print('Web runtime unavailable: ${error.message}');
    rethrow;
  }
  print('Runtime: ${await engine.getBackendName()}');
  return engine;
}

Future<GenerationParams> webSamplingParams(LlamaEngine engine) async {
  final LlamaEngineCapabilities caps = await engine.capabilities;
  return GenerationParams(
    maxTokens: 256,
    minP: caps.supportsMinP ? 0.05 : 0.0,
    presencePenalty: caps.supportsPresencePenalty ? 0.5 : 0.0,
    penalty: caps.supportsPenalty ? 1.1 : const GenerationParams().penalty,
  );
}
```

Single-turn prompt on LiteRT-LM web with only supported parameters:

```dart
import 'package:llamadart/llamadart.dart';

Future<String> askLiteRtLmWeb(LlamaEngine engine, String prompt) async {
  return engine.create(
    [LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt)],
    params: const GenerationParams(maxTokens: 256, temp: 0.7, topK: 40),
  ).text();
}
```

## More

- WebGPU bridge: https://llamadart.leehack.com/docs/platforms/webgpu-bridge
- Support matrix: https://llamadart.leehack.com/docs/platforms/support-matrix
- llama.cpp or LiteRT-LM: https://llamadart.leehack.com/docs/guides/backend-selection
- Troubleshooting (web): https://llamadart.leehack.com/docs/troubleshooting/common-issues
