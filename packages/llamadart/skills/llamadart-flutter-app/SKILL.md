---
name: llamadart-flutter-app
description: >-
  Use when integrating llamadart into a Flutter app: deciding where the
  LlamaEngine lives and when to dispose it, keeping the UI responsive while
  streaming, showing model download progress and managing the model cache,
  iOS and macOS deployment targets, the llamadart_llama_cpp_flutter and
  llamadart_litert_lm_flutter companion packages, Android and web setup, or
  trimming bundled native runtimes with hooks.user_defines.
---

# Flutter apps with llamadart

Wire a llamadart engine into a Flutter app without leaking it, blocking the UI
or shipping runtimes the app does not use.

## Guidelines

- Own the engine in a long-lived object (a service, a `ChangeNotifier`, a
  provider, or a `State`), never in `build()`. Create it once, load in
  `initState` or a start method, and dispose it with the owner: cancel any
  download token and `engine.cancelGeneration()`, then `engine.dispose()`.
  `State.dispose` is synchronous, so wrap the call in `unawaited(...)`.
  `dispose()` waits for an in-flight load or unload, then unloads the model
  and releases the backend; that load then throws `LlamaStateException`.
  It immediately marks the engine disposed, even inside logging or backend
  hooks. Every call shares one future, including a failed teardown; disposal
  does not retry cleanup after failure.
  Model unload, replacement, and disposal also cancel active chat-session
  requests: partial replies stay in history, while requests stopped before
  output roll back and throw `LlamaStateException`. Tool loops report
  `LlamaToolLoopStopReason.cancelled`, wait for running handlers, and roll back
  unfinished tool turns before another model request.
- Quitting a desktop app (Cmd-Q, closing the last window) does not run
  `State.dispose`. Also dispose `LlamaEngine`, `DecisionEngine` and
  `ImageGenerationEngine` instances from
  `AppLifecycleListener(onExitRequested: ...)`, awaiting them before
  returning `AppExitResponse.exit` (from `dart:ui`). A Flutter macOS app
  that quits without disposing (Quit menu item, last window,
  `exitApplication`) still exits cleanly: Flutter shuts the isolates down
  first, so llamadart frees the models they hold, and the llama.cpp runtime
  (`llamadart-native` `v0.5.0-2` and later) and the stable_diffusion runtime
  (`stable-diffusion-native` `v0.2.0-1` and later) free a model the quit
  caught mid-load. Dispose anyway: the quit waits for a native call that is
  still running, so for the rest of an image generation. Linux hosts must
  explicitly dispose their Flutter engines before process exit: quitting
  `GApplication` detaches windows but does not guarantee engine cleanup.
  Preserve the chat example's native Runner cleanup when adapting it. Active
  llama.cpp load/generation checks cover Linux arm64 CPU with that Runner;
  image workers, other GPU devices and Windows need separate qualification.
  When the engine's owner can be disposed before quit (a
  pushed route), its listener goes with it: make one app-level exit listener
  await every engine's disposal, including one its owner already started.
  llama.cpp and image-worker disposal wait for actual worker exit. A native
  host must also stop and join other native workers and shut down its Dart
  isolates or Flutter engine before C `exit()`; killing an isolate alone
  cannot interrupt a synchronous native call.
- Keep inference state out of widgets. Put a plain Dart controller between
  the engine and the UI (example below) and adapt it to `ChangeNotifier`,
  `ValueNotifier`, BLoC or Riverpod. Loading, chat history and streaming
  basics are in the llamadart-getting-started and llamadart-chat-streaming
  skills.
- Stream through a `StreamSubscription` stored on the owner so Stop and
  dispose can reach it. For Stop, call `engine.cancelGeneration()`: the stream
  ends normally with a partial reply on native backends, but `ChatSession`
  throws `LlamaStateException` and rolls back if cancelled before any reply
  content. A partial reply stays in history only if that session has not
  reset; WebGPU cancellation can also surface a generation error. In `dispose`, also cancel the subscription.
- Do not call `setState` or `notifyListeners` per token. Append deltas to a
  `StringBuffer` and flush on a short timer (the example chat app notifies
  about every 16 ms), and flush once more on done or error. Check `mounted`
  before any `setState` after an `await`.
- Disable Send while a generation runs: one engine runs one generation at a
  time, and a second request throws `LlamaStateException`.
- Show download progress from `setModel(onProgress: ...)` (or
  `LlamaEngine.load(onProgress: ...)`).
  `ModelDownloadProgress.fraction` is `null` while the total size is unknown;
  pass it straight to `LinearProgressIndicator(value: ...)` to get an
  indeterminate bar. A cancelled `ModelDownloadCancelToken` makes the load
  throw `LlamaStateException`; treat that as a cancel, not an error.
- Web backends download through the browser and reject a cancel token (and
  checksums, auth headers and non-default cache policies) with
  `LlamaUnsupportedException`. Pass `ModelLoadOptions(cancelToken: ...)` only
  when `!kIsWeb`, otherwise `ModelLoadOptions.defaults`.
- For a download screen with stages, cancel and retry, use
  `ModelDownloadController`, which has no Flutter dependency. It owns
  cancellation: call `controller.cancel()` and never put a `cancelToken` in
  the options you pass to `start` (it throws `LlamaArgumentException`). Then
  `engine.setModel(LlamaModel(ModelSource.path(entry.filePath)))`, or pass
  the original `ModelSource`: the load reuses the cached file.
- On Android and iOS the default cache is already `llamadart/models` in the
  app's cache directory (what `getApplicationCacheDirectory()` returns), which
  survives app updates; no `path_provider` setup is needed. To move every
  default download, for example to `getApplicationSupportDirectory()`, set
  `DefaultModelDownloadManager.globalCacheDirectory` at startup before the
  first load, in every isolate that creates engines. A manager you build yourself goes to
  `LlamaEngine(..., modelDownloadManager:)` too, so loads and cache inspection
  agree. Resolve OS-provided directories on every launch: an iOS update can
  move the app container. Persist the `ModelSource`, rather than a cache root
  or `entry.filePath`. Native `list()`/`get()` report retained entries at their
  current paths before any load, without rewriting metadata. For verified
  offline reuse, call `ensureModel(source, options:
  ModelLoadOptions(cachePolicy: ModelCachePolicy.cacheOnly))` on that manager;
  it checks the retained file's recorded length and any stored or supplied
  SHA-256. On web the default manager's operations throw
  `LlamaUnsupportedException`.
- Do not cancel downloads on every app pause or screen lock. Downloads are
  foreground Dart HTTP requests; a later session resumes from the `.part`
  file when the server allows it. Background downloads need a custom
  `ModelDownloadManager`.
- Apps, isolates and extensions sharing one cache root (`sharedCache()`,
  `userSelected(...)`, `appGroup(...)`) take a cross-process file lock per
  entry, so a second caller waits and reuses the download. Processes on
  llamadart 0.16 or older do not take the lock; sharing a root with them can
  repeat a download, never corrupt the entry. `remove` and `clear` skip
  entries in use there and then throw `ModelCacheEntryInUseException`;
  `prune` skips them.
  In an iOS App Group container, finish or cancel a download (or hold a
  background task) before the app is suspended: iOS kills apps suspended while
  holding a lock there (`0xdead10cc`).
- If a fresh Flutter 3.47.1 macOS SwiftPM build reports generated macOS 12.0
  beside a companion requiring 14.0, use the
  [consumer bootstrap](https://llamadart.leehack.com/docs/platforms/apple-setup#fresh-macos-swiftpm-bootstrap):
  `flutter pub get`, raise only the generated package floor, then build with
  `--no-pub`. Repeat after regeneration; preserve Runner's 14.0+ target and
  companion manifests, native URLs and checksums.
- Platform setup the package cannot do:
  - iOS deployment target 16.4+ (`IPHONEOS_DEPLOYMENT_TARGET`, and
    `platform :ios, '16.4'` in a CocoaPods Podfile); macOS 14.0+
    (`MACOSX_DEPLOYMENT_TARGET`).
  - macOS apps that download models need the
    `com.apple.security.network.client` entitlement in both
    `DebugProfile.entitlements` and `Release.entitlements`.
  - Android release builds need the `INTERNET` permission in
    `AndroidManifest.xml`.
  - Windows: llama.cpp and LiteRT-LM bundle the Visual C++ runtime DLLs
    they need. Machines that run the opt-in `stable_diffusion` runtime need
    the latest Microsoft Visual C++ v14 Redistributable (x64); stock Windows
    Server lacks it.
  - Web needs the WebGPU bridge script in `web/index.html`; the package does
    not inject it (`dart run llamadart:web_setup` adds it). LiteRT-LM on web is single-turn text only (no
    `ChatSession`).
- Apple SwiftPM linking uses the companion packages:
  `llamadart_llama_cpp_flutter` (llama.cpp XCFrameworks),
  `llamadart_litert_lm_flutter` (LiteRT-LM iOS and macOS XCFrameworks) and
  `llamadart_stable_diffusion_flutter` (image generation). Use the companion
  version the llamadart README pairs with your core version. The build
  verifies the companion's runtime pin and fails on a mismatch; fix the
  version and rerun `flutter pub get`. Flutter macOS LiteRT-LM needs the
  LiteRT-LM companion to put the runtime in the app bundle; without it a
  sandboxed or distributed macOS app cannot load LiteRT-LM.
- LiteRT-LM on iOS: 16.4 is the declared deployment floor, not a tested one.
  On a device it has run only on an iPhone 16 Pro with iOS 18.3.2, so test
  older iOS versions before supporting them.
- App Store builds should use the companion for each runtime they ship: a
  companion's XCFramework carries the Apple privacy manifest, and hook-bundled
  dylibs do not. When llama.cpp or stable_diffusion runs on the hook path, or
  the embedded `llama.framework` or `stable_diffusion.framework` has no
  `PrivacyInfo.xcprivacy`, add `NSPrivacyAccessedAPICategoryFileTimestamp` to
  the app's own `PrivacyInfo.xcprivacy` with reason `C617.1`, plus `3B52.1`
  only when it ships stable_diffusion. When LiteRT-LM runs on the hook path, or
  its embedded frameworks have no `PrivacyInfo.xcprivacy`, add File Timestamp
  (`C617.1`, `3B52.1`) and System Boot Time (`35F9.1`) to the app's own
  manifest.
- When the llama.cpp or LiteRT-LM companion is present, the installed
  companions pick those Apple runtime families and `llamadart_native_runtimes`
  is otherwise ignored with a warning; the tag, repository, path and backend
  user-defines do not change SwiftPM binaries either. The stable_diffusion
  companion is independent: it selects image generation on iOS and macOS and
  leaves llama.cpp and LiteRT-LM where they were.
- Image generation (`ImageGenerationEngine`) needs the `stable_diffusion`
  runtime, which is never bundled by default. Set `llamadart_native_runtimes`
  to `all`, or to a list naming `stable_diffusion`; a list replaces the
  default `llama_cpp` and `litert_lm`. On iOS and macOS add
  `llamadart_stable_diffusion_flutter`: without it `all` leaves the image
  runtime out there, and App Store Connect rejects the iOS framework the hook
  bundles when `stable_diffusion` is named. Details are in the
  llamadart-image-generation skill.
- Native runtimes are downloaded by the build hook on the first
  `flutter run` or `flutter build` for each target; no C++ toolchain is
  needed. Expect a slower first build. After changing any
  `hooks.user_defines.llamadart` key, run `flutter clean` once so stale native
  assets are not reused.
- Trim app size with `hooks.user_defines.llamadart`:
  `llamadart_native_runtimes` ships one model format, and
  `llamadart_native_backends` picks llama.cpp modules per platform (Android
  arm64 also takes `cpu_profile: compact`). A backend list that names a
  module the bundle lacks is discarded whole with a warning and the defaults
  (`cpu`, `vulkan`) are bundled. Windows x64 downloads the CUDA runtime, a
  separate archive of about 688 MiB, only when `cuda` is selected. Apple
  llama.cpp is one consolidated CPU and Metal runtime and is not configurable.
- macOS x86_64, Rosetta included: llama.cpp `ComputeDevice.auto` and
  `GpuBackend.auto` run on the CPU with 0 GPU layers, because Metal returns
  garbled output on Intel Macs with AMD GPUs. `GpuBackend.metal` or
  `ComputeDevice.gpu` still loads on Metal and logs a warning; use it only
  on Macs the app has validated. arm64 macOS keeps Metal.
- Selecting `litert_lm` by name fails the build on targets without a
  LiteRT-LM runtime, such as the iOS x86_64 simulator. Apps that include
  LiteRT-LM must exclude that simulator architecture.
- Android: llama.cpp ships `cpu` and `vulkan` by default; `opencl` is opt-in
  through `llamadart_native_backends`. llama.cpp `ComputeDevice.auto` stays
  on the CPU there; Vulkan is experimental and device-dependent, so request
  `ComputeDevice.gpu` only on devices the app has validated. Adreno 750
  driver `2150604839` is excluded: an explicit GPU request throws; automatic
  selection with a Vulkan preference falls back to CPU with a warning.
  A shader-compiler workaround alone does not qualify quantized output. Leave
  `ModelParams.microBatchSize` unset on Android Vulkan: its eight-token
  prompt calls were faster on the Mali GPU measured. With a llama.cpp runtime
  older than ggml `0.28.0` (llamadart-native `v0.8.0`), native `qwen35`
  (Qwen3.5) on such GPUs accepts only unset or `1..8`, and media,
  speculation and embeddings throw `LlamaUnsupportedException` (#948). On
  any runtime, a Qwen3.5 image encoder stays on the CPU on those GPUs.
  LiteRT-LM attempts GPU on Android under `ComputeDevice.auto`. On Android
  12+ with target API 31+, add `<uses-native-library
  android:name="libOpenCL.so" android:required="false"/>` inside the app's
  manifest `<application>` so vendor OpenCL is accessible. Keep it optional.
  This does not qualify the driver or model: WebGPU's 128 MiB binding limit
  on Adreno 750 can reject larger weight buffers. Failed GPU creation under
  `auto` retries on CPU with a warning; explicit `ComputeDevice.gpu` fails.
  Check the active backend, and use `ModelParams(device: ComputeDevice.cpu)`
  to skip the GPU attempt. Native v0.19.0 has accepted corrected-model
  default-service OpenCL evidence only on SC-51E/API36/DEBUG: 20 cases, six
  closed lifetimes, eight full-graph placement proofs, cancellation and reload.
  Preserve the legacy FP32 artifact's four unqualified semantic failures and
  the unchanged collector FAIL; 15 exact sidecars were forensically extracted
  from the retained journal, not independently downloaded. This does not
  qualify every Qwen artifact/device or release profile; see
  [the platform limits](../../website/docs/platforms/known-platform-issues.md#android)
  and #1677 / litert-lm-native#51. `ComputeDevice.npu` needs a
  supporting SoC and bundle, and throws `LlamaUnsupportedException` without
  one.
- Budget memory for phones: 1B-3B parameter models, a `contextSize` no larger
  than the app needs, and one loaded model at a time.

## Examples

`pubspec.yaml` for a GGUF-only app that links the Apple companion and trims
Android (on Apple targets the companion, not `llamadart_native_runtimes`,
picks the runtime):

```yaml
dependencies:
  llamadart: ^<core version>
  llamadart_llama_cpp_flutter: ^<companion version paired in the README>
  path_provider: ^2.1.5

hooks:
  user_defines:
    llamadart:
      llamadart_native_runtimes: [llama_cpp]
      llamadart_native_backends:
        platforms:
          android-arm64:
            backends: [vulkan]
            cpu_profile: compact
```

A Flutter-free chat controller the widget layer owns. A `State` or
`ChangeNotifier` creates it in `initState`, calls `load()`, rebuilds from
`onChanged`, wires Send to `send`, Stop to `stop`, calls
`unawaited(controller.dispose())` from its own `dispose`, and awaits
`controller.dispose()` in `onExitRequested`:

```dart
import 'dart:async';

import 'package:llamadart/llamadart.dart';

class ChatController {
  ChatController({
    required this.modelUri,
    required this.onChanged,
    required this.isWeb,
    ModelDownloadManager? downloadManager,
  }) : _engine = LlamaEngine(
         LlamaBackend(),
         modelDownloadManager: downloadManager,
       );

  final String modelUri;
  final void Function() onChanged;
  final bool isWeb;

  final LlamaEngine _engine;
  final ModelDownloadCancelToken _downloadCancel = ModelDownloadCancelToken();
  final StringBuffer _pending = StringBuffer();

  ChatSession? _session;
  StreamSubscription<LlamaCompletionChunk>? _generation;
  Timer? _flushTimer;
  bool _disposed = false;

  double? downloadFraction;
  String status = 'Idle';
  String reply = '';

  bool get isReady => _session != null;
  bool get isGenerating => _generation != null;

  Future<void> load() async {
    status = 'Downloading model';
    onChanged();
    try {
      await _engine.setModel(
        LlamaModel(ModelSource.parse(modelUri)),
        params: const ModelParams(contextSize: 2048),
        download: isWeb
            ? ModelLoadOptions.defaults
            : ModelLoadOptions(cancelToken: _downloadCancel),
        onProgress: (ModelDownloadProgress progress) {
          if (_disposed) return;
          downloadFraction = progress.fraction;
          onChanged();
        },
      );
      if (_disposed) return;
      _session = ChatSession(_engine, systemPrompt: 'Be concise.');
      status = 'Ready';
    } on LlamaException catch (error) {
      if (_disposed) return;
      status = _downloadCancel.isCancelled
          ? 'Download cancelled'
          : 'Load failed: ${error.message}';
    }
    onChanged();
  }

  void send(String text) {
    final ChatSession? session = _session;
    if (session == null || isGenerating || text.trim().isEmpty) return;
    reply = '';
    _generation = session
        .create(
          <LlamaContentPart>[LlamaTextContent(text)],
          params: const GenerationParams(maxTokens: 512),
        )
        .listen(
          (LlamaCompletionChunk chunk) {
            if (chunk.text.isEmpty) return;
            _pending.write(chunk.text);
            _flushTimer ??= Timer(const Duration(milliseconds: 32), _flush);
          },
          onError: (Object error) {
            _pending.write('\n[error: $error]');
            _finish();
          },
          onDone: _finish,
          cancelOnError: true,
        );
    onChanged();
  }

  void stop() => _engine.cancelGeneration();

  void _flush() {
    _flushTimer = null;
    if (_disposed || _pending.isEmpty) return;
    reply += _pending.toString();
    _pending.clear();
    onChanged();
  }

  void _finish() {
    _flushTimer?.cancel();
    _generation = null;
    _flush();
    if (!_disposed) onChanged();
  }

  Future<void> dispose() async {
    _disposed = true;
    _flushTimer?.cancel();
    _downloadCancel.cancel();
    _engine.cancelGeneration();
    await _generation?.cancel();
    await _engine.dispose();
  }
}
```

A download screen with stages, cancel and retry, using an app-private cache
directory the Flutter layer resolved with `getApplicationCacheDirectory()`:

```dart
import 'dart:async';

import 'package:llamadart/llamadart.dart';

class ModelDownloadScreenModel {
  ModelDownloadScreenModel(String appCacheDirectory, this.onSnapshot)
    : manager = DefaultModelDownloadManager.auto(
        appPrivateCacheDirectory: appCacheDirectory,
      ) {
    controller = ModelDownloadController(manager: manager);
    _subscription = controller.snapshots.listen(onSnapshot);
  }

  final ModelDownloadManager manager;
  final void Function(ModelDownloadTaskSnapshot snapshot) onSnapshot;
  late final ModelDownloadController controller;
  late final StreamSubscription<ModelDownloadTaskSnapshot> _subscription;

  Future<String?> fetch(String uri) async {
    try {
      final ModelCacheEntry entry = await controller.start(
        ModelSource.parse(uri),
      );
      return entry.filePath;
    } on Exception {
      return null;
    }
  }

  void cancel() => controller.cancel();

  Future<String?> retry() async {
    if (!controller.snapshot.canRetry) return null;
    try {
      return (await controller.retry()).filePath;
    } on Exception {
      return null;
    }
  }

  Future<void> removeCached(String uri) async {
    final ModelCacheEntry? entry = await manager.get(
      ModelSource.parse(uri).cacheKey,
    );
    if (entry == null) return;
    try {
      await manager.remove(entry.cacheKey);
    } on ModelCacheEntryInUseException {
      // Another isolate or app is downloading it; retry later.
    }
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await controller.dispose();
  }
}
```

Render `snapshot.stage` (`resolving`, `checkingCache`, `downloading`,
`verifying`, `ready`, `failed`, `cancelled`), `snapshot.fraction` and the
redacted `snapshot.errorMessage`; source and redirect URL credentials are
removed from failure diagnostics and cancellation messages, including known
secrets repeated in the model filename. Transient I/O failures retain retry behavior.
Load the returned path with
`engine.setModel(LlamaModel(ModelSource.path(path)))`.

## More

- Flutter chat app tutorial: https://llamadart.leehack.com/docs/tutorials/flutter-chat-app
- Installation: https://llamadart.leehack.com/docs/getting-started/installation
- Apple setup: https://llamadart.leehack.com/docs/platforms/apple-setup
- Native runtime configuration: https://llamadart.leehack.com/docs/platforms/native-build-hooks
- Download and cache models: https://llamadart.leehack.com/docs/guides/model-downloads
- Full chat app example: https://llamadart.leehack.com/docs/examples/chat-app
