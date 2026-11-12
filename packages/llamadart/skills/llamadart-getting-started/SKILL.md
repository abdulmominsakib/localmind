---
name: llamadart-getting-started
description: >-
  Use when adding llamadart to a Dart or Flutter app, choosing between GGUF
  (llama.cpp) and .litertlm (LiteRT-LM) models, loading or switching a model,
  or owning a LlamaEngine's lifecycle.
---

# Getting started with llamadart

llamadart runs local LLMs in Dart and Flutter: GGUF models through llama.cpp
and `.litertlm` bundles through LiteRT-LM, on Android, iOS, macOS, Windows,
Linux and web. Full docs: https://llamadart.leehack.com

## Shared lifecycle

All five engine types implement `LlamadartEngine<C extends EngineCapabilities>`.
Use `List<LlamadartEngine<EngineCapabilities>>` for mixed engine ownership, or
retain a concrete capability type for its fields. Await `dispose()` in reverse
dependency order: attached speech/decision engines before the text engine they
borrow. `isDisposed` becomes true at the first disposal call; repeated calls
share its future. Loading and inference use each concrete engine's API. The
interface does not establish backend/model support; read `await engine.capabilities`.

## Guidelines

- Use the pinned native LiteRT-LM v0.19.1-4 runtime. Direct calls, service
  probes and speech share ABI-aware discovery. Public selection admits legacy
  runtimes and C API 1.0.x; unknown/future versions are refused before engine
  calls. The pin is published native v0.19.1-4 (owner `5da99205`, upstream
  `7a03724c`). The selected loader requires macOS 14+ even for legacy
  libraries and custom paths. Web uses `@litert-lm/core@0.19.0`.

- For a model-free macOS/Linux/Windows setup snapshot, use
  `dart run llamadart:doctor [--json]` or
  `await collectLlamaRuntimeSetupReport()`. It reports pinned publication policy
  and only set/unset native override names. Exit 0 means a report was produced;
  loading, emitted assets, GPU/backend and model capabilities remain unchecked.
  The collector performs no native initialization or network work, but `dart run`
  can prepare/download native assets or fail in its build hook before main.
  Web/mobile throw `LlamaUnsupportedException`; a Dart CLI report does not
  validate a Flutter app/device/browser. Keep `web_setup --check` as separate
  offline asset advice and use loaded-model capabilities for feature decisions.

- For an opt-in native artifact check, use
  `dart run llamadart:doctor_native --runtime llama_cpp --json`, or explicitly
  choose `litert_lm` / `stable_diffusion`. It opens local manifest declarations
  (or, for undeclared macOS LiteRT-LM, the build hook cache the runtime loads,
  reported as `target_source: build_hook_cache`) in an isolated child and
  checks selected symbols/static ABI markers. Native
  constructors can run; no engine/model/device probe is started. Result codes
  are fixed and raw child output is discarded. Exit 0 means a report, including
  failed checks. Keep loaded release identity, emitted app assets, production
  loader behavior, GPU and inference unknown/unchecked; no path or expected pin
  proves the loaded release. This source-CLI check does not validate Flutter
  apps, devices or browsers. The default collector remains metadata-only.
  It requires regular local manifest/IPC files and refuses their symlinks or
  special files. Its 30-second coordinator budget has a three-second cleanup
  reserve; arbitrary stalled filesystem operations remain outside the contract.

- In custom backends and fakes, declare URL-load callbacks as
  `void Function(double progress)? onProgress` (0.14+), including
  `BackendModelFormatRouting.modelLoadFromUrlAs`. Forward progress fractions
  unchanged; return values do not control or cancel loading. Native FFI `bool`
  callbacks keep their separate contract.

- Create one engine per loaded model with
  `LlamaEngine.load(LlamaModel(source))`, or with `LlamaEngine(LlamaBackend())`
  and `setModel` when the engine must exist before the load, and always
  `await engine.dispose()` when its owner goes away, in a `finally` block for
  scripts. A `LlamaEngine.load` that throws has already disposed its engine,
  so start the `try` after it returns. In Flutter, create the engine in a
  long-lived owner (service, provider or `State`), never in `build()`.
  `dispose()` is final: a later load or request throws `LlamaStateException`,
  so use `setModel` to switch models and a new engine after `dispose()`.
  Disposal promptly rejects a running `setModel` or deprecated
  `loadModelSource` and cancels its package-managed model/LoRA downloads.
  Caller-owned cancel tokens remain unchanged; transfers stop cooperatively
  at their next checkpoint. Custom resolvers/managers must poll the linked
  token they receive, even though disposal no longer waits for their work.
- Await `dispose()` before host shutdown. Killing a worker is not cooperative
  cancellation. Reclaiming models/contexts created during a forced kill needs
  owner API v1, supplied by the pinned `v0.9.0` runtime. Custom runtimes
  without it retain that gap. Other raw allocations have separate limits.
- `LlamaBackend()` routes by model format: LiteRT-LM bundles run on LiteRT-LM
  and GGUF on llama.cpp. Native targets read the file header, so extensionless
  files load; a header contradicting the extension throws
  `LlamaModelFormatException`. Web routes by URL extension: for a URL without
  one, pass `ModelSource.url(uri, format: ModelFormat.liteRtLm)`. The formats
  are not interchangeable.
- To learn before any download whether a model and `ModelParams` can load
  here, call `await engine.checkLoad(model, params: params)`. It runs the
  checks `setModel` runs before resolving files, starts no runtime, and
  reports `unsupported` exactly when the load would throw (with `error` and
  `reason`), `deferred` when only the file header gives the format, `unknown`
  for a backend that cannot tell, such as `LlamaEngine(LiteRtLmBackend())`, or
  `supported` with the `runtime` and `device` it would use. `supported` is
  policy, not proof the load succeeds: LoRA limits, download options
  (`ModelLoadOptions`) and the file are checked by the load, and
  `engine.capabilities` still describes only a loaded model.
- Prefer GGUF / llama.cpp unless the model only ships as `.litertlm`. Only
  llama.cpp supports embeddings, grammar-constrained and structured JSON output,
  runtime LoRA, KV-cache state persistence, next-token scores and external
  multimodal projectors. LiteRT-LM throws `LlamaUnsupportedException` for
  llama.cpp-only options; do not catch and ignore it. After a load,
  `engine.runtime` names the runtime and `await engine.capabilities` reports
  every option it applies; gate features on these, never on the file
  extension or `getBackendName()` text. Native thinking-budget support requires
  the runtime's reasoning-budget export. Native `mtp` stays advertised for
  external drafts; in-file MTP needs an MTP head and `loadMtp: true`. Other
  draft strategies need `draftModel` or throw `LlamaArgumentException` at start.
- KV-state save/load is not an exact generation checkpoint. On native
  llama.cpp, an exact restored prompt with prefix reuse re-evaluates its final
  token; scores and continuation may differ from full-prompt evaluation. The
  contract is numerical tolerance, not bit-exactness: with automatic prompt
  batching, probabilities may differ slightly and greedy output can change. Live
  logits and sampler/RNG state are not restored. If the caller explicitly
  chooses full prompt evaluation, use `reusePromptPrefix: false`; do not promise
  exact resume or silently replace KV reuse with full prompt evaluation.
  Use a `tokenCapacity` within 1..context size and large enough for the saved
  tokens. On a ready, idle native llama.cpp context, capacity outside those
  bounds throws `LlamaArgumentException` without invalidating the context.
- `stateLoadFile` checks the llama.cpp session version and KV layout, not the
  runtime build or RoPE settings. Before loading a state file another process
  saved, compare the `LlamaStateIdentity` stored with it to
  `await engine.stateIdentity()` with `matches`, and compare a digest of the
  model file, adapters and projector you store yourself; on a mismatch, or a
  `LlamaStateException` from a matching file, evaluate the prompt again. Native llama.cpp needs `llamadart-native`
  `v0.7.0-3`+; other runtimes throw `LlamaUnsupportedException`.
- Name the model with `ModelSource.parse(...)` (`hf://owner/repo/file.gguf`,
  an HTTP(S) URL, or a local path) and pass `params:` (`ModelParams`),
  `download:` (`ModelLoadOptions`) and `onProgress:` to `LlamaEngine.load` or
  `setModel`. Native targets download once into a cache and reuse it: a
  per-user cache on desktop, the app's cache directory on Android and iOS (no
  `path_provider` needed). On web the runtime fetches the file itself and a
  local path is a URL relative to the document.
- `setModel` replaces the loaded model; do not call `unloadModel()` first.
  `unloadModel()` only frees the model without loading another. Neither
  queues: while a `setModel` runs, another `setModel` or an `unloadModel`
  throws `LlamaStateException`. Serialize model switches in app code, or stop
  the running load with `ModelLoadOptions.cancelToken`.
- Check `engine.isReady` before inference. Log `engine.getBackendName()` in
  diagnostics so reports name the runtime actually used.
  Native llama.cpp with `device: ComputeDevice.auto`,
  `splitMode: ModelSplitMode.none` and a negative `mainGpu` reports `CPU`
  in backend name/capabilities and `0` resolved GPU layers. Layer and row
  splits do not disable GPUs this way; explicit `gpu` / `npu` rejects the
  single-device negative-index combination with `LlamaArgumentException`.
- `ModelParams(device: ComputeDevice.cpu)` forces the CPU on every runtime.
  Native llama.cpp `auto` already runs on the CPU on Android, an iOS
  simulator and macOS x86_64 (Rosetta included). An explicit
  `ComputeDevice.gpu` or `npu` runs on that GPU or NPU or throws
  `LlamaUnsupportedException`, never on another device; native LiteRT-LM
  reports a GPU or NPU delegate that fails to start from the first
  generation or `tokenize`. Under `auto` it retries a GPU engine that fails
  to start on the CPU with a warning (`getBackendName()` then reports
  `LiteRT-LM cpu`) and throws the GPU error if the CPU fails too. If `auto`
  already selects CPU, an engine-create failure has no second attempt.
  On Linux, when every Vulkan device is software (llvmpipe, SwiftShader),
  LiteRT-LM GPU throws at load and a GPU hint under `auto` loads on the CPU.
  Backend-SPI context recreation preserves a successful CPU fallback when
  reusing the load's automatic GPU hints. Leave `device` at `auto` for each
  runtime's default.
  `ModelParams.liteRtLmBackend` and `LiteRtLmBackendPreference` are
  deprecated. Keep `contextSize` no larger than the app needs: memory grows
  with it.
- A load throws `LlamaUnsupportedException` naming every `ModelParams` field
  the model's runtime would ignore: `liteRtLm*` fields on a GGUF model,
  llama.cpp tuning such as `batchSize` or `loadMtp` on a `.litertlm` model,
  `preferMemory64` / `modelBytesHint` off the Web. Build one per runtime with
  `LlamaCppModelParams(...)` for GGUF or `LiteRtLmModelParams(...)` for
  `.litertlm` (LiteRT-LM options without the prefix: `cacheDir`,
  `dispatchLibDir`, `embeddingEngine`, ...); either one used for the other
  runtime throws. The `liteRtLm*` arguments of `ModelParams` are deprecated.
- Import only `package:llamadart/llamadart.dart` in app code. Custom
  backends and backend test fakes (`implements LlamaBackend,
  BackendTextToSpeech`, ...) and direct LiteRT-LM runtime access also import
  `package:llamadart/backend.dart`; its `LlamaEngineBackendHooks` are
  extension members, so call them on a `LlamaEngine`-typed value, never
  through `dynamic`. Runtime LoRA and multimodal projectors are the optional
  `BackendLoraSupport` and `BackendMultimodalSupport`; `LlamaEngine` throws
  `LlamaUnsupportedException` for a backend without them. New LFM2 automatic
  Python tool grammar additionally needs `BackendPromptPenaltyGeneration` with
  a truthful loaded-runtime getter; missing or false support rejects before
  generation. Ordinary explicit grammar dispatch keeps its existing defaults. Avoid
  `package:llamadart/llama_cpp_bindings.dart`: the raw FFI is native-only
  and can change in any release.
- Catch the `LlamaException` hierarchy (`LlamaModelException`,
  `LlamaStateException`, `LlamaUnsupportedException`, ...) rather than
  `Exception`.
- If a fresh Flutter 3.47.1 macOS SwiftPM build reports generated macOS 12.0
  beside a companion requiring 14.0, use the
  [consumer bootstrap](https://llamadart.leehack.com/docs/platforms/apple-setup#fresh-macos-swiftpm-bootstrap):
  `flutter pub get`, raise only the generated package floor, then build with
  `--no-pub`. Repeat after regeneration; preserve Runner's 14.0+ target and
  companion manifests, native URLs and checksums.
- llama.cpp automatic bundles and runtime fallbacks use
  `.dart_tool/llamadart/native_bundles_v2`; older `native_bundles` caches are
  left untouched and are not reused. Compatible explicit tag/repository and
  local-archive overrides use the new namespace too. Keep manual overrides
  ABI- and symbol-compatible with the pinned runtime; remove a mismatched
  override or upgrade the consumer/runtime together. Apple companions must
  match the qualified tag and exact XCFramework checksum.
- Platform setup the code cannot do for you:
  - Flutter iOS needs deployment target 16.4+, macOS 14.0+.
  - Windows llama.cpp: replace the complete runtime through the build-hook
    `llamadart_native_path`. `LLAMADART_NATIVE_LIB_DIR` and
    `LLAMADART_BACKEND_MODULE_DIR` select backend modules only; ggml registry
    bindings stay with the hook assets used by model loading. Do not rely on
    `PATH` to replace those assets. An unavailable ggml code asset or missing
    `ggml_backend_reg_count` export throws `LlamaUnsupportedException`.
  - Windows: llama.cpp and LiteRT-LM bundle the Visual C++ runtime DLLs
    they need. Machines that run the opt-in `stable_diffusion` runtime need
    the latest Microsoft Visual C++ v14 Redistributable (x64); stock Windows
    Server lacks it.
  - Web apps must add the WebGPU bridge script to `web/index.html`; the package
    does not inject it. `dart run llamadart:web_setup` vendors the pinned,
    checksum-verified assets and adds it.
  - To ship one runtime family only, set
    `hooks.user_defines.llamadart.llamadart_native_runtimes` in `pubspec.yaml`.
- Native runtimes are fetched by the build hook on first build; no C++
  toolchain is needed. Do not vendor llama.cpp or LiteRT-LM into the app.

## Examples

Load a model from Hugging Face and run one stateless completion:

```dart
import 'package:llamadart/llamadart.dart';

Future<void> main() async {
  final LlamaEngine engine = await LlamaEngine.load(
    LlamaModel(
      ModelSource.parse(
        'hf://unsloth/SmolLM2-135M-Instruct-GGUF/'
        'SmolLM2-135M-Instruct-Q2_K.gguf',
      ),
    ),
    params: const ModelParams(contextSize: 1024, gpuLayers: 0),
    onProgress: (progress) {
      final double? fraction = progress.fraction;
      if (fraction != null) {
        print('download ${(fraction * 100).toStringAsFixed(1)}%');
      }
    },
  );
  try {
    print('runtime: ${await engine.getBackendName()}');

    final String output = await engine.create(const [
      LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: 'Say hello in five words.',
      ),
    ], params: const GenerationParams(maxTokens: 32)).text();
    print(output);
  } finally {
    await engine.dispose();
  }
}
```

Load a GGUF model on two of a host's GPUs, three quarters on the first
(native llama.cpp only; the Web and LiteRT-LM throw
`LlamaUnsupportedException`, as do indices the host lacks):
Keep `tensorSplit` proportions within `ModelParams`' documented float32 limits;
direct native llama.cpp calls also reject a non-finite sum before loading.

```dart
import 'package:llamadart/llamadart.dart';

Future<LlamaEngine> loadOnTwoGpus(String path) async {
  final LlamaEngine engine = LlamaEngine(LlamaBackend());
  // mainGpu counts the devices of one backend, so keep only CUDA devices.
  final List<GpuDeviceInfo> gpus = [
    for (final GpuDeviceInfo gpu in await engine.listGpuDevices(
      probeBackends: const [GpuBackend.cuda],
    ))
      if (gpu.backend == GpuBackend.cuda) gpu,
  ];
  await engine.loadModel(
    path,
    modelParams: LlamaCppModelParams(
      preferredBackend: GpuBackend.cuda,
      gpuDevices: [gpus[0].mainGpu, gpus[1].mainGpu],
      tensorSplit: const [3, 1],
    ),
  );
  return engine;
}
```

Check a model and device before downloading, then load it:

```dart
import 'package:llamadart/llamadart.dart';

Future<void> loadIfSupported(LlamaEngine engine, LlamaModel model) async {
  const ModelParams params = ModelParams(device: ComputeDevice.gpu);
  final LlamaLoadCheckReport check = await engine.checkLoad(
    model,
    params: params,
  );
  if (check.status == LlamaLoadCheckStatus.unsupported) {
    print('Cannot load here: ${check.reason}');
    return;
  }
  await engine.setModel(model, params: params);
}
```

Switch models on one engine, and load a LiteRT-LM bundle on GPU:

```dart
import 'package:llamadart/llamadart.dart';

Future<void> switchToLiteRtLm(LlamaEngine engine, String bundlePath) async {
  final LlamaModel model = LlamaModel(ModelSource.path(bundlePath));
  try {
    // setModel replaces the model the engine holds.
    await engine.setModel(
      model,
      params: const ModelParams(device: ComputeDevice.gpu),
    );
    // Native LiteRT-LM starts the GPU delegate on its first use.
    await engine.tokenize('warm up');
  } on LlamaUnsupportedException catch (error) {
    print('No LiteRT-LM GPU here, loading on the CPU: $error');
    await engine.setModel(
      model,
      params: const ModelParams(device: ComputeDevice.cpu),
    );
  }
}
```

Keep a Mixture-of-Experts GGUF's experts in host memory and cache the recently
used ones on a CUDA or Metal GPU (native llama.cpp only). A budget on Vulkan,
other backends or tensor split throws `LlamaUnsupportedException`, as do both
fields on the Web and LiteRT-LM; `cpuMoeLayers` alone runs on any backend.
Validated on Metal only, where the cache only adds copies; CUDA has no
hardware evidence yet:

```dart
import 'package:llamadart/llamadart.dart';

Future<LlamaEngine> loadMoeWithExpertCache(String path) {
  return LlamaEngine.load(
    LlamaModel(ModelSource.path(path)),
    params: const LlamaCppModelParams(
      cpuMoeLayers: -1, // every layer's experts stay in host memory
      moeCacheBytes: 4 << 30, // up to 4 GiB of experts on the GPU
    ),
  );
}
```

## More

- Installation and platform setup: https://llamadart.leehack.com/docs/getting-started/installation
- llama.cpp or LiteRT-LM: https://llamadart.leehack.com/docs/guides/backend-selection
- Model lifecycle and downloads: https://llamadart.leehack.com/docs/guides/model-lifecycle
