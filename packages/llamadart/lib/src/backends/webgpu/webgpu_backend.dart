import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart';

import '../../core/models/chat/content_part.dart';
import '../../core/cache_policy.dart';
import '../../core/models/config/gpu_backend.dart';
import '../../core/models/config/llama_cpp_param_values.dart';
import '../../core/models/config/log_level.dart';
import '../../core/models/inference/generation_params.dart';
import '../../core/models/inference/model_params.dart';
import '../backend.dart';
import 'interop.dart';

@JS('Object.keys')
external JSArray _objectKeys(JSObject obj);

/// Web backend backed by the llama.cpp bridge runtime.
class WebGpuLlamaBackend
    implements
        LlamaBackend,
        BackendAvailability,
        BackendBatchEmbeddings,
        BackendStatePersistence,
        BackendStatePersistenceSupport {
  static const Duration _bridgeReadyTimeout = Duration(seconds: 12);
  static const Duration _bridgePollInterval = Duration(milliseconds: 100);
  static const int _defaultRemoteFetchChunkBytes = 4 * 1024 * 1024;
  static const int _minRemoteFetchChunkBytes = 4 * 1024;
  static const int _maxRemoteFetchChunkBytes = 16 * 1024 * 1024;
  static const int _qwen35SmallSafeWebGpuLayers = 2;
  static const int _gpuMultimodalMaxImagePixels = 1048576;
  static const int _gpuMultimodalMaxImageEdge = 1280;
  static const Duration _webGpuMultimodalWarmupTimeout = Duration(seconds: 12);
  static const String _defaultModelCacheName =
      'llamadart-webgpu-model-cache-v1';
  static const String _runtimeLoraUnsupportedMessage =
      'WebGPU LoRA runtime updates are not supported by the current bridge. '
      'Use a native llama.cpp backend when runtime LoRA adapter changes are '
      'required.';
  static final Uint8List _webGpuWarmupRgbBytes = Uint8List.fromList(const <int>[
    0,
    0,
    0,
  ]);

  final String? _bridgeScriptUrl;
  final String? _bridgeWasmUrl;
  final String? _bridgeWorkerUrl;
  final LlamaWebGpuBridge Function([WebGpuBridgeConfig? config])?
  _bridgeFactory;

  LlamaWebGpuBridge? _bridge;
  bool _usingBridge = false;
  bool _isReady = false;
  LlamaLogLevel _logLevel = LlamaLogLevel.info;
  AbortController? _abortController;
  int? _lastNCtx;
  bool _mmContextActive = false;
  bool _webGpuMultimodalWarmupDone = false;
  bool _webGpuMultimodalWarmupAttempted = false;
  bool? _preferMemory64Override;
  bool? _forceRemoteFetchBackendOverride;

  /// Creates a bridge-backed web backend.
  WebGpuLlamaBackend({
    String? bridgeScriptUrl,
    String? wasmUrl,
    String? workerUrl,
    LlamaWebGpuBridge Function([WebGpuBridgeConfig? config])? bridgeFactory,
  }) : _bridgeScriptUrl = bridgeScriptUrl,
       _bridgeWasmUrl = wasmUrl,
       _bridgeWorkerUrl = workerUrl,
       _bridgeFactory = bridgeFactory;

  @override
  bool get isReady => _isReady;

  @override
  bool get supportsStatePersistence {
    final bridge = _bridge;
    return _usingBridge &&
        bridge != null &&
        _hasBridgeFunction(bridge, 'stateSaveFile') &&
        _hasBridgeFunction(bridge, 'stateLoadFile');
  }

  bool _hasBridgeFunction(LlamaWebGpuBridge bridge, String name) {
    final value = bridge.getProperty(name.toJS);
    return value.isA<JSFunction>();
  }

  Future<void> _loadBridgeScript() async {
    final scriptUrl = _bridgeScriptUrl;
    if (scriptUrl == null || scriptUrl.isEmpty) {
      return;
    }

    if (globalContext.has('LlamaWebGpuBridge')) {
      return;
    }

    final completer = Completer<void>();
    const callbackName = '__llamadart_webgpu_init';

    globalContext.setProperty(
      callbackName.toJS,
      (JSAny? err) {
        if (err != null) {
          if (!completer.isCompleted) {
            completer.completeError(
              Exception('WebGPU bridge init failed: $err'),
            );
          }
          return;
        }

        if (!completer.isCompleted) {
          completer.complete();
        }
      }.toJS,
    );

    final script = HTMLScriptElement();
    script.type = 'module';
    script.text =
        '''
      import("$scriptUrl").then(mod => {
        if (mod?.LlamaWebGpuBridge) {
          window.LlamaWebGpuBridge = mod.LlamaWebGpuBridge;
        }
        if (window.$callbackName) {
          window.$callbackName();
        }
      }).catch(e => {
        if (window.$callbackName) {
          window.$callbackName(e);
        }
      });
    ''';

    script.addEventListener(
      'error',
      ((Event _) {
        if (!completer.isCompleted) {
          completer.completeError(
            Exception('Failed to load WebGPU bridge script'),
          );
        }
      }).toJS,
    );

    document.head?.append(script);

    try {
      await completer.future.timeout(const Duration(seconds: 12));
    } finally {
      globalContext.delete(callbackName.toJS);
    }
  }

  WebGpuBridgeConfig _createBridgeConfig() {
    final logger = JSObject();
    logger.setProperty(
      'debug'.toJS,
      (JSAny? msg) {
        _emitConsole(LlamaLogLevel.debug, msg);
      }.toJS,
    );
    logger.setProperty(
      'log'.toJS,
      (JSAny? msg) {
        _emitConsole(LlamaLogLevel.info, msg);
      }.toJS,
    );
    logger.setProperty(
      'warn'.toJS,
      (JSAny? msg) {
        _emitConsole(LlamaLogLevel.warn, msg);
      }.toJS,
    );
    logger.setProperty(
      'error'.toJS,
      (JSAny? msg) {
        _emitConsole(LlamaLogLevel.error, msg);
      }.toJS,
    );

    final coreModuleUrl = _getGlobalString('__llamadartBridgeCoreModuleUrl');
    final coreModuleUrlMem64 = _getGlobalString(
      '__llamadartBridgeCoreModuleUrlMem64',
    );
    final wasmUrl =
        _bridgeWasmUrl ?? _getGlobalString('__llamadartBridgeWasmUrl');
    final wasmUrlMem64 = _getGlobalString('__llamadartBridgeWasmUrlMem64');
    final workerModuleUrl =
        _bridgeWorkerUrl ?? _getGlobalString('__llamadartBridgeWorkerUrl');
    final preferMemory64 =
        _preferMemory64Override ??
        _getGlobalOptionalBool('__llamadartBridgePreferMemory64');
    final threadPoolSizeHint = _getGlobalPositiveInt(
      '__llamadartBridgeThreadPoolSize',
    );
    // Keep bridge remote-fetch loading opt-in until malformed responses can be
    // rejected without risking an unrecoverable core abort. Forced mode is an
    // explicit opt-in and must enable the bridge capability end to end.
    final allowAutoRemoteFetchBackend = _isRemoteFetchBackendOptedIn();

    return WebGpuBridgeConfig(
      wasmUrl: wasmUrl?.toJS,
      wasmUrlMem64: wasmUrlMem64?.toJS,
      workerUrl: workerModuleUrl?.toJS,
      coreModuleUrl: coreModuleUrl?.toJS,
      coreModuleUrlMem64: coreModuleUrlMem64?.toJS,
      preferMemory64: preferMemory64,
      threadPoolSize: threadPoolSizeHint,
      allowAutoRemoteFetchBackend: allowAutoRemoteFetchBackend,
      remoteFetchChunkBytes: _resolveRemoteFetchChunkBytes(),
      logLevel: _logLevel.index,
      logger: logger,
    );
  }

  Future<void> _waitForPreloadedBridge() async {
    if (globalContext.has('LlamaWebGpuBridge')) {
      return;
    }

    final deadline = DateTime.now().add(_bridgeReadyTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (globalContext.has('LlamaWebGpuBridge')) {
        return;
      }

      if (_getBridgeLoadError() != null) {
        return;
      }

      await Future<void>.delayed(_bridgePollInterval);
    }
  }

  Future<bool> _ensureBridge() async {
    if (_bridge != null) {
      return true;
    }

    if (_bridgeFactory != null) {
      _bridge = _bridgeFactory(_createBridgeConfig());
      return true;
    }

    if (!globalContext.has('LlamaWebGpuBridge')) {
      final scriptUrl = _bridgeScriptUrl;
      if (scriptUrl != null && scriptUrl.isNotEmpty) {
        await _loadBridgeScript();
      } else {
        await _waitForPreloadedBridge();
      }
    }

    if (!globalContext.has('LlamaWebGpuBridge')) {
      return false;
    }

    _bridge = LlamaWebGpuBridge(_createBridgeConfig());
    return true;
  }

  Future<void> _safeDisposeBridge() async {
    final bridge = _bridge;
    final abortController = _abortController;
    _bridge = null;
    _abortController = null;
    abortController?.abort();
    bridge?.cancel();
    if (bridge == null) {
      return;
    }

    final disposePromise = bridge.dispose();
    if (disposePromise != null) {
      await disposePromise.toDart;
    }
    _usingBridge = false;
    _isReady = false;
    _mmContextActive = false;
    _resetWebGpuMultimodalWarmupState();
  }

  void _resetWebGpuMultimodalWarmupState() {
    _webGpuMultimodalWarmupDone = false;
    _webGpuMultimodalWarmupAttempted = false;
  }

  Future<void> _activateBridge() async {
    if (_usingBridge && _bridge != null) {
      return;
    }

    final ready = await _ensureBridge();
    if (!ready || _bridge == null) {
      final loadError = _getBridgeLoadError();
      final message = _buildBridgeUnavailableMessage(loadError);
      throw UnsupportedError(message);
    }

    _usingBridge = true;
    _syncBridgeLogLevel();
  }

  bool _shouldEmitConsole(LlamaLogLevel level) {
    if (_logLevel == LlamaLogLevel.none) {
      return false;
    }
    return _logLevel.index <= level.index;
  }

  void _emitConsole(LlamaLogLevel level, JSAny? message) {
    if (!_shouldEmitConsole(level)) {
      return;
    }

    switch (level) {
      case LlamaLogLevel.debug:
        console.debug(message);
        return;
      case LlamaLogLevel.info:
        console.log(message);
        return;
      case LlamaLogLevel.warn:
        console.warn(message);
        return;
      case LlamaLogLevel.error:
        console.error(message);
        return;
      case LlamaLogLevel.none:
        return;
    }
  }

  void _emitConsoleText(LlamaLogLevel level, String message) {
    _emitConsole(level, message.toJS);
  }

  void _syncBridgeLogLevel() {
    final bridge = _bridge;
    if (bridge == null) {
      return;
    }

    try {
      bridge.setLogLevel(_logLevel.index);
    } catch (_) {
      // Older bridge bundles may not expose runtime log-level updates.
    }
  }

  String _buildBridgeUnavailableMessage(String? loadError) {
    final source = _getGlobalString('__llamadartBridgeAssetSource');
    final moduleUrl = _getGlobalString('__llamadartBridgeModuleUrl');

    final locationParts = <String>[];
    if (source != null) {
      locationParts.add('source=$source');
    }
    if (moduleUrl != null) {
      locationParts.add('module=$moduleUrl');
    }

    final locationSuffix = locationParts.isEmpty
        ? ''
        : ' [${locationParts.join(', ')}]';

    final safariHint =
        loadError != null &&
            loadError.contains('compiled without support for Safari browser')
        ? ' Use bridge assets built with Safari support '
              '(MIN_SAFARI_VERSION universal build).'
        : '';

    final base = loadError == null
        ? 'Web bridge is unavailable. Ensure LlamaWebGpuBridge assets are loaded and reachable.'
        : 'Web bridge is unavailable: $loadError';

    return '$base$safariHint$locationSuffix';
  }

  String? _getGlobalString(String propertyName) {
    final raw = globalContext.getProperty(propertyName.toJS);
    if (raw.isA<JSString>()) {
      final value = (raw as JSString).toDart.trim();
      return value.isEmpty ? null : value;
    }

    final asText = raw.toString();
    if (asText == 'undefined' || asText == 'null' || asText.isEmpty) {
      return null;
    }

    return asText;
  }

  String? _getBridgeLoadError() {
    return _getGlobalString('__llamadartBridgeLoadError');
  }

  int? _getGlobalPositiveInt(String propertyName) {
    final raw = globalContext.getProperty(propertyName.toJS);
    if (raw.isA<JSNumber>()) {
      final value = (raw as JSNumber).toDartInt;
      return value > 0 ? value : null;
    }

    final parsed = int.tryParse(raw.toString().trim());
    if (parsed == null || parsed <= 0) {
      return null;
    }
    return parsed;
  }

  int _resolveRemoteFetchChunkBytes() {
    final override = _getGlobalPositiveInt(
      '__llamadartBridgeRemoteFetchChunkBytes',
    );
    final chunkBytes = override ?? _defaultRemoteFetchChunkBytes;
    return chunkBytes
        .clamp(_minRemoteFetchChunkBytes, _maxRemoteFetchChunkBytes)
        .toInt();
  }

  bool _getGlobalBool(String propertyName) {
    final raw = globalContext.getProperty(propertyName.toJS);
    if (raw.isA<JSBoolean>()) {
      return (raw as JSBoolean).toDart;
    }

    final text = raw.toString().trim().toLowerCase();
    return text == 'true' || text == '1' || text == 'yes' || text == 'on';
  }

  bool? _getGlobalOptionalBool(String propertyName) {
    final raw = globalContext.getProperty(propertyName.toJS);
    if (raw.isA<JSBoolean>()) {
      return (raw as JSBoolean).toDart;
    }

    final text = raw.toString().trim().toLowerCase();
    if (text == 'undefined' || text == 'null' || text.isEmpty) {
      return null;
    }

    if (text == 'true' || text == '1' || text == 'yes' || text == 'on') {
      return true;
    }
    if (text == 'false' || text == '0' || text == 'no' || text == 'off') {
      return false;
    }

    return null;
  }

  bool _isRemoteFetchBackendOptedIn() {
    return _getGlobalOptionalBool(
              '__llamadartBridgeAllowAutoRemoteFetchBackend',
            ) ==
            true ||
        _getGlobalBool('__llamadartBridgeForceRemoteFetchBackend');
  }

  bool _runtimeNotesIndicateModelFsWriteFailure(String runtimeNotes) {
    return runtimeNotes.contains('model_response_nostream') ||
        runtimeNotes.contains('model_fs_write_bigint_error') ||
        runtimeNotes.contains('model_fs_write_abort') ||
        runtimeNotes.contains('model_fs_write_arraybuffer_oom') ||
        runtimeNotes.contains('model_fs_write_failed');
  }

  String? _getBridgeUserAgent() {
    final override = _getGlobalString('__llamadartBridgeUserAgent');
    if (override != null) {
      return override;
    }

    final navigator = globalContext.getProperty('navigator'.toJS);
    if (!navigator.isA<JSObject>()) {
      return null;
    }

    final userAgent = (navigator as JSObject).getProperty('userAgent'.toJS);
    if (userAgent.isA<JSString>()) {
      final value = (userAgent as JSString).toDart.trim();
      return value.isEmpty ? null : value;
    }

    final text = userAgent.toString();
    if (text == 'undefined' || text == 'null' || text.isEmpty) {
      return null;
    }

    return text;
  }

  bool _isSafariBrowser() {
    final userAgent = _getBridgeUserAgent();
    if (userAgent == null || userAgent.isEmpty) {
      return false;
    }

    final hasSafariToken = userAgent.contains('Safari/');
    final hasOtherBrowserToken =
        userAgent.contains('Chrome/') ||
        userAgent.contains('Chromium/') ||
        userAgent.contains('CriOS/') ||
        userAgent.contains('Edg/') ||
        userAgent.contains('OPR/') ||
        userAgent.contains('Firefox/') ||
        userAgent.contains('FxiOS/');

    return hasSafariToken && !hasOtherBrowserToken;
  }

  bool _allowSafariWebGpu() {
    return _getGlobalBool('__llamadartAllowSafariWebGpu');
  }

  bool _bridgeSupportsAdaptiveSafariGpu() {
    return _getGlobalBool('__llamadartBridgeAdaptiveSafariGpu');
  }

  String _errorText(Object error) {
    final values = <String>{error.toString()};

    JSObject? jsError;
    try {
      jsError = error as JSObject;
    } catch (_) {
      jsError = null;
    }

    if (jsError != null) {
      final nestedError = jsError.getProperty('error'.toJS);
      final nestedMessage = jsError.getProperty('message'.toJS);
      final nestedStack = jsError.getProperty('stack'.toJS);

      for (final candidate in <JSAny?>[
        nestedError,
        nestedMessage,
        nestedStack,
      ]) {
        if (candidate == null) {
          continue;
        }

        final text = candidate.toString();
        if (text == 'undefined' || text == 'null' || text.isEmpty) {
          continue;
        }

        values.add(text);
      }
    }

    return values.join(' | ');
  }

  bool _isLikelyMemoryPressureError(Object error) {
    final lowered = _errorText(error).toLowerCase();
    return lowered.contains('array buffer allocation failed') ||
        lowered.contains('out of memory') ||
        lowered.contains('memory access out of bounds') ||
        lowered.contains('bad_alloc') ||
        lowered.contains('aborted(native code called abort())');
  }

  bool _isBigIntInteropError(Object error) {
    final lowered = _errorText(error).toLowerCase();
    return lowered.contains('cannot convert') && lowered.contains('bigint');
  }

  bool _isThreadConstructorFailure(Object error) {
    final lowered = _errorText(error).toLowerCase();
    return lowered.contains('thread constructor failed') ||
        lowered.contains('error 138');
  }

  List<({int contextSize, int gpuLayers})> _buildLoadAttempts({
    required int requestedContextSize,
    required int requestedGpuLayers,
  }) {
    final contextCandidates = <int>[
      requestedContextSize,
      2048,
      1024,
      768,
      512,
      256,
    ];
    final contexts = <int>[];
    for (final candidate in contextCandidates) {
      if (candidate <= requestedContextSize) {
        contexts.add(candidate);
      }
    }

    final attempts = <({int contextSize, int gpuLayers})>[];
    final seen = <String>{};

    for (final context in contexts) {
      final normalizedContext = context.clamp(512, 32768);
      final key = '$normalizedContext|$requestedGpuLayers';
      if (seen.add(key)) {
        attempts.add((
          contextSize: normalizedContext,
          gpuLayers: requestedGpuLayers,
        ));
      }

      if (requestedGpuLayers > 0) {
        final cpuKey = '$normalizedContext|0';
        if (seen.add(cpuKey)) {
          attempts.add((contextSize: normalizedContext, gpuLayers: 0));
        }
      }
    }

    return attempts;
  }

  ({int? nBatch, int? nUbatch}) _resolveWebBatchSizes({
    required String url,
    required ModelParams params,
    required int contextSize,
    required int gpuLayers,
  }) {
    final normalizedUrl = url.toLowerCase();
    final isQwen35Small =
        normalizedUrl.contains('qwen3.5-0.8b') ||
        normalizedUrl.contains('qwen_qwen3.5-0.8b');
    final isGemma4 = normalizedUrl.contains('gemma-4');
    final isLargeWebModel =
        isGemma4 ||
        (params.modelBytesHint ?? 0) >= _wasm32SafeModelCeilingBytes;
    final hasExplicitBatchSize = params.batchSize > 0;
    final hasExplicitMicroBatchSize = params.microBatchSize > 0;
    final hasExplicitBatchSizes =
        hasExplicitBatchSize || hasExplicitMicroBatchSize;
    final shouldUseWebGpuDefaults =
        !hasExplicitBatchSizes &&
        params.preferredBackend != GpuBackend.cpu &&
        gpuLayers != 0;
    final shouldUseQwen35SmallTuning = shouldUseWebGpuDefaults && isQwen35Small;

    if (shouldUseQwen35SmallTuning) {
      return (nBatch: 32, nUbatch: 8);
    }

    if (!hasExplicitBatchSize && isLargeWebModel) {
      final cappedBatch = math.min(contextSize, 512);
      final cappedMicroBatch = hasExplicitMicroBatchSize
          ? math.min(params.microBatchSize, cappedBatch)
          : cappedBatch;
      return (nBatch: cappedBatch, nUbatch: cappedMicroBatch);
    }

    // The bridge creates the context before Dart can inspect model
    // architecture. Preserve full-context automatic batching here so
    // non-causal encoder models do not regress to first-embedding aborts.
    // Decoder-focused web callers can still request 2048/512 explicitly.
    final resolved = resolveModelContextBatchSizes(
      params,
      contextSize,
      useFullContextDefaults: true,
    );
    return (nBatch: resolved.batchSize, nUbatch: resolved.microBatchSize);
  }

  // Approximate wasm32 linear-memory ceiling under which a model + KV cache can
  // be expected to fit. Models at or above this should load into the mem64 core
  // up front. wasm32 caps at 4 GiB; ~2 GiB leaves headroom for the KV cache and
  // intermediate buffers.
  static const int _wasm32SafeModelCeilingBytes = 2 * 1024 * 1024 * 1024;

  /// Resolves the effective mem64 preference for a load.
  ///
  /// Size-driven, not model-name based: an explicit [ModelParams.preferMemory64]
  /// wins; otherwise a [ModelParams.modelBytesHint] at/above the wasm32-safe
  /// ceiling opts in; otherwise `null` (let the bridge / reactive escalation
  /// decide). Callers that know a model is large should pass `modelBytesHint`
  /// (or set `preferMemory64`) rather than relying on a hardcoded name list.
  bool? _resolvePreferMemory64(ModelParams params) {
    if (params.preferMemory64 != null) {
      return params.preferMemory64;
    }
    final hint = params.modelBytesHint ?? 0;
    if (hint >= _wasm32SafeModelCeilingBytes) {
      return true;
    }
    return null;
  }

  int _webGpuFlashAttentionValue(ModelParams params) {
    return llamaFlashAttentionTypeValueFor(
      resolveFlashAttention(
        requested: params.flashAttention,
        cacheTypeK: params.cacheTypeK,
        cacheTypeV: params.cacheTypeV,
      ),
    );
  }

  bool? _webGpuKvUnifiedValue(ModelParams params) {
    return params.kvUnified ?? (params.maxParallelSequences > 1 ? true : null);
  }

  int _resolveSafeRequestedGpuLayers({
    required String url,
    required ModelParams params,
    required int requestedGpuLayers,
  }) {
    if (requestedGpuLayers <= 0 || params.preferredBackend == GpuBackend.cpu) {
      return requestedGpuLayers;
    }

    final normalizedUrl = url.toLowerCase();
    final isQwen35Small =
        normalizedUrl.contains('qwen3.5-0.8b') ||
        normalizedUrl.contains('qwen_qwen3.5-0.8b');
    if (!isQwen35Small) {
      return requestedGpuLayers;
    }

    if (requestedGpuLayers < 0) {
      return _qwen35SmallSafeWebGpuLayers;
    }

    return math.min(requestedGpuLayers, _qwen35SmallSafeWebGpuLayers);
  }

  Map<String, String> _collectBridgeRuntimeHints(LlamaWebGpuBridge bridge) {
    final metadata = bridge.getModelMetadata();
    if (metadata == null) {
      return const <String, String>{};
    }

    final out = <String, String>{};
    final keys = _objectKeys(metadata);
    for (int i = 0; i < keys.length; i++) {
      final key = (keys.getProperty(i.toJS) as JSString).toDart;
      if (!key.startsWith('llamadart.webgpu.')) {
        continue;
      }

      final value = metadata.getProperty(key.toJS);
      if (value.isA<JSString>()) {
        out[key] = (value as JSString).toDart;
      } else if (value.isA<JSNumber>()) {
        out[key] = (value as JSNumber).toDartDouble.toString();
      } else {
        out[key] = value.toString();
      }
    }

    return out;
  }

  UnsupportedError? _normalizeBridgeRuntimeError(
    Object error, {
    Map<String, String>? runtimeHints,
    required bool remoteFetchBackendOptedIn,
  }) {
    final text = _errorText(error);
    final loweredText = text.toLowerCase();
    if (text.contains('JSPI not supported by current environment')) {
      final source = _getGlobalString('__llamadartBridgeAssetSource');
      final moduleUrl = _getGlobalString('__llamadartBridgeModuleUrl');

      final location = <String>[];
      if (source != null) {
        location.add('source=$source');
      }
      if (moduleUrl != null) {
        location.add('module=$moduleUrl');
      }

      final suffix = location.isEmpty ? '' : ' [${location.join(', ')}]';

      return UnsupportedError(
        'Bridge runtime requires JSPI, which is unavailable in this browser. '
        'Use browser-compatible bridge assets built without JSPI '
        '(Asyncify/wasm32), or enable JSPI experimental browser flags.$suffix',
      );
    }

    final runtimeNotes = runtimeHints?['llamadart.webgpu.runtime_notes'] ?? '';
    if (_runtimeNotesIndicateModelFsWriteFailure(runtimeNotes) &&
        !remoteFetchBackendOptedIn) {
      return UnsupportedError(
        'Web model staging failed before the GGUF could be loaded safely. '
        'Automatic fetch-backed loading is disabled by default because an '
        'invalid remote response can abort the WebAssembly core. Try a '
        'smaller or sharded GGUF, reduce browser memory pressure, or use the '
        'native runtime. For a controlled origin that serves valid GGUF byte '
        'ranges, explicitly set '
        'window.__llamadartBridgeAllowAutoRemoteFetchBackend = true or '
        'window.__llamadartBridgeForceRemoteFetchBackend = true before '
        'loading.',
      );
    }
    final threadConstructorFailure =
        runtimeNotes.contains('threads_capped_no_coi') ||
        runtimeNotes.contains('thread_constructor_failed') ||
        loweredText.contains('thread constructor failed');

    if (threadConstructorFailure) {
      final workerFallbackReason = _getGlobalString(
        '__llamadartBridgeWorkerFallbackReason',
      );
      final workerSuffix =
          workerFallbackReason == null || workerFallbackReason.isEmpty
          ? ''
          : ' Worker fallback reason: $workerFallbackReason.';

      final hintParts = <String>[];
      final coreVariant = runtimeHints?['llamadart.webgpu.core_variant'];
      if (coreVariant != null && coreVariant.isNotEmpty) {
        hintParts.add('core=$coreVariant');
      }
      final modelSource = runtimeHints?['llamadart.webgpu.model_source'];
      if (modelSource != null && modelSource.isNotEmpty) {
        hintParts.add('source=$modelSource');
      }
      final nThreads = runtimeHints?['llamadart.webgpu.n_threads'];
      if (nThreads != null && nThreads.isNotEmpty) {
        hintParts.add('nThreads=$nThreads');
      }
      final nGpuLayers = runtimeHints?['llamadart.webgpu.n_gpu_layers'];
      if (nGpuLayers != null && nGpuLayers.isNotEmpty) {
        hintParts.add('nGpuLayers=$nGpuLayers');
      }
      final modelCacheState =
          runtimeHints?['llamadart.webgpu.model_cache_state'];
      if (modelCacheState != null && modelCacheState.isNotEmpty) {
        hintParts.add('cache=$modelCacheState');
      }
      if (runtimeNotes.isNotEmpty) {
        hintParts.add('notes=$runtimeNotes');
      }
      final hintSuffix = hintParts.isEmpty
          ? ''
          : ' Runtime hints: ${hintParts.join(', ')}.';

      return UnsupportedError(
        'Browser runtime blocked worker thread creation required by the '
        'fetch-backed web model loader. Enable cross-origin isolation '
        '(COOP/COEP) for your app origin, or use a smaller/sharded model '
        'that can be staged with standard streamed loading.$workerSuffix$hintSuffix',
      );
    }

    if (_isLikelyMemoryPressureError(error)) {
      final workerFallbackReason = _getGlobalString(
        '__llamadartBridgeWorkerFallbackReason',
      );
      final workerSuffix =
          workerFallbackReason == null || workerFallbackReason.isEmpty
          ? ''
          : ' Worker fallback reason: $workerFallbackReason.';

      final hintParts = <String>[];
      final coreVariant = runtimeHints?['llamadart.webgpu.core_variant'];
      if (coreVariant != null && coreVariant.isNotEmpty) {
        hintParts.add('core=$coreVariant');
      }
      final modelSource = runtimeHints?['llamadart.webgpu.model_source'];
      if (modelSource != null && modelSource.isNotEmpty) {
        hintParts.add('source=$modelSource');
      }
      final nThreads = runtimeHints?['llamadart.webgpu.n_threads'];
      if (nThreads != null && nThreads.isNotEmpty) {
        hintParts.add('nThreads=$nThreads');
      }
      final nGpuLayers = runtimeHints?['llamadart.webgpu.n_gpu_layers'];
      if (nGpuLayers != null && nGpuLayers.isNotEmpty) {
        hintParts.add('nGpuLayers=$nGpuLayers');
      }
      final modelCacheState =
          runtimeHints?['llamadart.webgpu.model_cache_state'];
      if (modelCacheState != null && modelCacheState.isNotEmpty) {
        hintParts.add('cache=$modelCacheState');
      }
      if (runtimeNotes.isNotEmpty) {
        hintParts.add('notes=$runtimeNotes');
      }
      final hintSuffix = hintParts.isEmpty
          ? ''
          : ' Runtime hints: ${hintParts.join(', ')}.';

      return UnsupportedError(
        'Model loading exceeded browser memory limits. '
        'This model may be too large for current WebAssembly/browser constraints. '
        'Try a smaller GGUF quantization, reduce context size, close other tabs, '
        'or use native runtime for very large models.$workerSuffix$hintSuffix',
      );
    }

    return null;
  }

  LlamaWebGpuBridge _requireBridge() {
    final bridge = _bridge;
    if (!_usingBridge || bridge == null) {
      throw StateError(
        'Web bridge is not active. Call loadModelFromUrl first.',
      );
    }
    return bridge;
  }

  @override
  Future<int> modelLoad(String path, ModelParams params) {
    return modelLoadFromUrl(path, params);
  }

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    Function(double progress)? onProgress,
  }) async {
    params.validate();
    // Seed the mem64 preference from the public ModelParams (explicit flag or a
    // size hint at/above the wasm32 ceiling) so large models load into the
    // 64-bit core up front instead of relying on a post-OOM retry. The reactive
    // escalation paths below can still flip this to true as a last resort.
    _preferMemory64Override = _resolvePreferMemory64(params);
    _forceRemoteFetchBackendOverride = null;
    final remoteFetchBackendOptedIn = _isRemoteFetchBackendOptedIn();

    final requestedThreads = params.numberOfThreads > 0
        ? params.numberOfThreads
        : null;
    var requestedGpuLayers = params.preferredBackend == GpuBackend.cpu
        ? 0
        : params.gpuLayers;

    if (requestedGpuLayers > 0 &&
        _isSafariBrowser() &&
        !_allowSafariWebGpu() &&
        !_bridgeSupportsAdaptiveSafariGpu()) {
      requestedGpuLayers = 0;
      _emitConsoleText(
        LlamaLogLevel.warn,
        'WebGpuLlamaBackend: Safari WebGPU generation is unstable for legacy bridge assets; forcing CPU fallback. '
        'Use bridge assets with adaptive Safari GPU probe support, or set '
        'window.__llamadartAllowSafariWebGpu = true to bypass this safeguard.',
      );
    }

    final resolvedGpuLayers = _resolveSafeRequestedGpuLayers(
      url: url,
      params: params,
      requestedGpuLayers: requestedGpuLayers,
    );
    if (resolvedGpuLayers != requestedGpuLayers) {
      _emitConsoleText(
        LlamaLogLevel.info,
        'WebGpuLlamaBackend: Capping Qwen3.5-0.8B WebGPU layers '
        'from $requestedGpuLayers to $resolvedGpuLayers for stable browser output.',
      );
      requestedGpuLayers = resolvedGpuLayers;
    }

    final progressCallback = onProgress == null
        ? null
        : (JSAny p) {
            if (p.isA<JSObject>()) {
              final obj = p as JSObject;
              final loaded = obj.getProperty('loaded'.toJS);
              final total = obj.getProperty('total'.toJS);
              if (loaded.isA<JSNumber>() && total.isA<JSNumber>()) {
                final l = (loaded as JSNumber).toDartDouble;
                final t = (total as JSNumber).toDartDouble;
                if (t > 0) {
                  onProgress(l / t);
                  return;
                }
              }
            }

            if (p.isA<JSNumber>()) {
              onProgress((p as JSNumber).toDartDouble);
            }
          }.toJS;

    final loadAttempts = _buildLoadAttempts(
      requestedContextSize: params.contextSize,
      requestedGpuLayers: requestedGpuLayers,
    );
    final cachedWebModel = await _isModelResponseCachedForUrl(url);
    Object? lastError;
    Map<String, String> lastRuntimeHints = const <String, String>{};
    var retriedWithWasm32 = false;
    var retriedWithWasm64 = false;
    var retriedWithoutRemoteFetchBackend = false;
    var remoteFetchChunkRetryCount = 0;
    var retriedAfterFsWriteFailureWithRemote = false;
    var remoteFetchBackendKnownUnstable = false;
    var wasm64InteropKnownBroken = false;
    var remoteFetchChunkBytesOverride = _resolveRemoteFetchChunkBytes();
    for (var index = 0; index < loadAttempts.length; index += 1) {
      final attempt = loadAttempts[index];
      _lastNCtx = attempt.contextSize;
      final batchSizes = _resolveWebBatchSizes(
        url: url,
        params: params,
        contextSize: attempt.contextSize,
        gpuLayers: attempt.gpuLayers,
      );
      LlamaWebGpuBridge? bridgeForAttempt;
      bool? forceRemoteFetchBackend;
      final attemptThreads = switch (index) {
        0 => requestedThreads,
        1 || 2 => requestedThreads == null ? 4 : math.min(requestedThreads, 4),
        3 ||
        4 ||
        5 ||
        6 => requestedThreads == null ? 2 : math.min(requestedThreads, 2),
        _ => 1,
      };

      try {
        await _activateBridge();
        final bridge = _requireBridge();
        bridgeForAttempt = bridge;

        if (_forceRemoteFetchBackendOverride != null) {
          forceRemoteFetchBackend = _forceRemoteFetchBackendOverride;
        } else if (_getGlobalBool('__llamadartBridgeForceRemoteFetchBackend')) {
          forceRemoteFetchBackend = true;
        } else if (cachedWebModel) {
          forceRemoteFetchBackend = false;
        }

        final loadPromise = bridge.loadModelFromUrl(
          url,
          WebGpuLoadModelOptions(
            nCtx: attempt.contextSize,
            nThreads: attemptThreads,
            nThreadsBatch: params.numberOfThreadsBatch > 0
                ? params.numberOfThreadsBatch
                : null,
            nBatch: batchSizes.nBatch,
            nUbatch: batchSizes.nUbatch,
            nGpuLayers: attempt.gpuLayers,
            nSeqMax: math.max(1, params.maxParallelSequences),
            flashAttention: _webGpuFlashAttentionValue(params),
            cacheTypeK: ggmlTypeValueFor(params.cacheTypeK),
            cacheTypeV: ggmlTypeValueFor(params.cacheTypeV),
            kvUnified: _webGpuKvUnifiedValue(params),
            ropeFrequencyBase: params.ropeFrequencyBase,
            ropeFrequencyScale: params.ropeFrequencyScale,
            splitMode: params.splitMode.llamaCppValue,
            mainGpu: params.mainGpu,
            useCache: !hasPersistentCacheSensitiveUrlParts(url),
            forceRemoteFetchBackend: forceRemoteFetchBackend,
            remoteFetchChunkBytes: remoteFetchChunkBytesOverride,
            modelBytesHint: params.modelBytesHint,
            progressCallback: progressCallback,
          ),
        );

        if (loadPromise != null) {
          await loadPromise.toDart;
        }

        if (index > 0) {
          _emitConsoleText(
            LlamaLogLevel.warn,
            'WebGpuLlamaBackend: model loaded after fallback '
            '(nCtx=${attempt.contextSize}, nGpuLayers=${attempt.gpuLayers}, '
            'nThreads=${attemptThreads ?? 'auto'})',
          );
        }

        _isReady = true;
        _mmContextActive = false;
        _resetWebGpuMultimodalWarmupState();
        return 1;
      } catch (e) {
        lastError = e;
        Map<String, String> runtimeHints = const <String, String>{};
        if (bridgeForAttempt != null) {
          try {
            runtimeHints = _collectBridgeRuntimeHints(bridgeForAttempt);
          } catch (_) {
            runtimeHints = const <String, String>{};
          }
        }
        lastRuntimeHints = runtimeHints;

        _emitConsoleText(
          LlamaLogLevel.error,
          'WebGpuLlamaBackend: Bridge model load failed: $e',
        );
        if (runtimeHints.isNotEmpty) {
          _emitConsoleText(
            LlamaLogLevel.warn,
            'WebGpuLlamaBackend: bridge runtime hints $runtimeHints',
          );
        }

        final coreVariant = runtimeHints['llamadart.webgpu.core_variant'];
        final runtimeNotes =
            runtimeHints['llamadart.webgpu.runtime_notes'] ?? '';
        final fsWriteFailed = _runtimeNotesIndicateModelFsWriteFailure(
          runtimeNotes,
        );
        final bigIntInteropError = _isBigIntInteropError(e);
        final remoteFetchAttempted = runtimeNotes.contains(
          'model_fetch_backend_attempt',
        );
        final remoteFetchAborted =
            runtimeNotes.contains('model_fetch_backend_abort') ||
            (remoteFetchAttempted && runtimeNotes.contains('core_abort')) ||
            (remoteFetchAttempted &&
                _errorText(e).toLowerCase().contains(
                  'aborted(native code called abort())',
                ));
        final threadConstructorFailure =
            _isThreadConstructorFailure(e) ||
            runtimeNotes.contains('thread_constructor_failed') ||
            runtimeNotes.contains('threads_capped_no_coi');
        final wasm32ModelStagingFailed =
            coreVariant == 'wasm32' && fsWriteFailed;
        final memoryPressureFailure =
            _isLikelyMemoryPressureError(e) || wasm32ModelStagingFailed;
        final forceRemoteFetchRequested = forceRemoteFetchBackend == true;

        if (remoteFetchAborted) {
          remoteFetchBackendKnownUnstable = true;
          if (!forceRemoteFetchRequested) {
            _forceRemoteFetchBackendOverride = false;
          }
        }

        final shouldRetryWithoutRemoteFetchBackend =
            !retriedWithoutRemoteFetchBackend &&
            !forceRemoteFetchRequested &&
            remoteFetchAttempted &&
            remoteFetchAborted;
        final shouldRetryWithSmallerRemoteFetchChunks =
            remoteFetchChunkRetryCount < 10 &&
            remoteFetchBackendOptedIn &&
            remoteFetchAttempted &&
            remoteFetchAborted &&
            forceRemoteFetchRequested &&
            !threadConstructorFailure &&
            remoteFetchChunkBytesOverride > _minRemoteFetchChunkBytes;
        final shouldRetryWithWasm32 =
            !retriedWithWasm32 &&
            coreVariant == 'wasm64' &&
            (bigIntInteropError ||
                runtimeNotes.contains('model_fetch_backend_skipped_small'));

        final shouldRetryWithWasm64 =
            !retriedWithWasm64 &&
            !wasm64InteropKnownBroken &&
            coreVariant == 'wasm32' &&
            memoryPressureFailure &&
            !runtimeNotes.contains('model_fetch_backend_skipped_small');

        final canRetry =
            index < loadAttempts.length - 1 &&
            memoryPressureFailure &&
            !(fsWriteFailed && coreVariant == 'wasm64');

        await _safeDisposeBridge();

        if (shouldRetryWithSmallerRemoteFetchChunks) {
          remoteFetchChunkRetryCount += 1;
          remoteFetchChunkBytesOverride = math.max(
            _minRemoteFetchChunkBytes,
            remoteFetchChunkBytesOverride ~/ 2,
          );
          _forceRemoteFetchBackendOverride = true;
          index = -1;
          _emitConsoleText(
            LlamaLogLevel.warn,
            'WebGpuLlamaBackend: fetch-backed model loading aborted; '
            'retrying with smaller fetch chunks '
            '(${remoteFetchChunkBytesOverride ~/ 1024} KiB, '
            'attempt #$remoteFetchChunkRetryCount).',
          );
          continue;
        }

        if (shouldRetryWithoutRemoteFetchBackend) {
          retriedWithoutRemoteFetchBackend = true;
          _forceRemoteFetchBackendOverride = false;

          if (coreVariant == 'wasm32') {
            _preferMemory64Override = true;
          }

          index = -1;
          _emitConsoleText(
            LlamaLogLevel.warn,
            coreVariant == 'wasm32'
                ? 'WebGpuLlamaBackend: fetch-backed model loading aborted on '
                      'wasm32; retrying with wasm64 core and streamed '
                      'network loading.'
                : 'WebGpuLlamaBackend: fetch-backed model loading aborted; '
                      'retrying with streamed network loading.',
          );
          continue;
        }

        if (shouldRetryWithWasm32) {
          retriedWithWasm32 = true;
          if (bigIntInteropError) {
            wasm64InteropKnownBroken = true;
          }
          _preferMemory64Override = false;
          _forceRemoteFetchBackendOverride = false;
          index = -1;
          _emitConsoleText(
            LlamaLogLevel.warn,
            'WebGpuLlamaBackend: wasm64 BigInt interop failure detected; '
            'retrying with wasm32 core.',
          );
          continue;
        }

        if (shouldRetryWithWasm64) {
          retriedWithWasm64 = true;
          _preferMemory64Override = true;
          final retryWithRemoteFetchBackend =
              remoteFetchBackendOptedIn &&
              !remoteFetchAttempted &&
              !remoteFetchBackendKnownUnstable;
          _forceRemoteFetchBackendOverride = retryWithRemoteFetchBackend;
          index = -1;
          _emitConsoleText(
            LlamaLogLevel.warn,
            retryWithRemoteFetchBackend
                ? 'WebGpuLlamaBackend: wasm32 memory pressure detected; '
                      'retrying with wasm64 core and explicitly enabled '
                      'fetch-backed loading.'
                : remoteFetchAttempted
                ? 'WebGpuLlamaBackend: wasm32 memory pressure detected after '
                      'fetch-backed loading; retrying with wasm64 core and '
                      'streamed network loading.'
                : 'WebGpuLlamaBackend: wasm32 memory pressure detected; '
                      'retrying with wasm64 core and streamed network loading.',
          );
          continue;
        }

        if (fsWriteFailed && coreVariant == 'wasm64') {
          if (remoteFetchBackendOptedIn &&
              !retriedAfterFsWriteFailureWithRemote) {
            retriedAfterFsWriteFailureWithRemote = true;
            _forceRemoteFetchBackendOverride = true;
            remoteFetchChunkBytesOverride = math.min(
              remoteFetchChunkBytesOverride,
              128 * 1024,
            );
            index = -1;
            _emitConsoleText(
              LlamaLogLevel.warn,
              'WebGpuLlamaBackend: wasm64 model staging failed; retrying '
              'with forced fetch-backed loading and '
              '${remoteFetchChunkBytesOverride ~/ 1024} KiB chunks.',
            );
            continue;
          }

          _emitConsoleText(
            LlamaLogLevel.warn,
            remoteFetchBackendOptedIn
                ? 'WebGpuLlamaBackend: wasm64 model staging failed; skipping '
                      'fallback ladder because additional nCtx/GPU/thread '
                      'reductions are unlikely to recover FS write failures.'
                : 'WebGpuLlamaBackend: wasm64 model staging failed; '
                      'fetch-backed recovery requires explicit opt-in, so no '
                      'unsafe remote-fetch retry will be attempted.',
          );
        }

        if (canRetry) {
          final nextAttempt = loadAttempts[index + 1];
          _emitConsoleText(
            LlamaLogLevel.warn,
            'WebGpuLlamaBackend: retrying web model load with reduced '
            'settings (nCtx=${nextAttempt.contextSize}, '
            'nGpuLayers=${nextAttempt.gpuLayers}, '
            'nThreads=${switch (index + 1) {
                  0 => requestedThreads,
                  1 || 2 => requestedThreads == null ? 4 : math.min(requestedThreads, 4),
                  3 || 4 || 5 || 6 => requestedThreads == null ? 2 : math.min(requestedThreads, 2),
                  _ => 1,
                } ?? 'auto'})',
          );
          continue;
        }

        final normalized = _normalizeBridgeRuntimeError(
          e,
          runtimeHints: runtimeHints,
          remoteFetchBackendOptedIn: remoteFetchBackendOptedIn,
        );
        if (normalized != null) {
          throw normalized;
        }
        rethrow;
      }
    }

    if (lastError != null) {
      final normalized = _normalizeBridgeRuntimeError(
        lastError,
        runtimeHints: lastRuntimeHints,
        remoteFetchBackendOptedIn: remoteFetchBackendOptedIn,
      );
      if (normalized != null) {
        throw normalized;
      }
      throw lastError;
    }

    throw StateError('WebGpuLlamaBackend: model load failed unexpectedly');
  }

  @override
  Future<void> modelFree(int modelHandle) async {
    await _safeDisposeBridge();
  }

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async {
    _requireBridge();
    return 1;
  }

  @override
  Future<void> contextFree(int contextHandle) async {}

  @override
  Future<int> getContextSize(int contextHandle) async {
    final bridge = _requireBridge();
    try {
      final n = bridge.getContextSize();
      if (n != null && n > 0) {
        return n;
      }
    } catch (_) {
      // Fall through to requested context size.
    }
    return _lastNCtx ?? 0;
  }

  List<int> _pieceToBytes(JSAny? piece) {
    if (piece == null) {
      return const <int>[];
    }

    if (piece.isA<JSString>()) {
      return utf8.encode((piece as JSString).toDart);
    }

    if (piece.isA<JSUint8Array>()) {
      return (piece as JSUint8Array).toDart;
    }

    if (piece.isA<JSArray>()) {
      final arr = piece as JSArray;
      final out = <int>[];
      for (int i = 0; i < arr.length; i++) {
        final item = arr.getProperty(i.toJS);
        if (item.isA<JSNumber>()) {
          out.add((item as JSNumber).toDartInt);
        }
      }
      return out;
    }

    return const <int>[];
  }

  int _findEarliestStopSequenceIndex(
    String text,
    List<String> stopSequences,
    int startIndex,
  ) {
    var earliestIndex = -1;
    final normalizedStartIndex = math.max(0, startIndex);

    for (final stop in stopSequences) {
      final matchIndex = text.indexOf(stop, normalizedStartIndex);
      if (matchIndex != -1 &&
          (earliestIndex == -1 || matchIndex < earliestIndex)) {
        earliestIndex = matchIndex;
      }
    }

    return earliestIndex;
  }

  List<double> _parseEmbeddingVector(JSAny? value) {
    if (value == null) {
      return const <double>[];
    }

    if (value.isA<JSFloat32Array>()) {
      return List<double>.from(
        (value as JSFloat32Array).toDart,
        growable: false,
      );
    }

    if (value.isA<JSFloat64Array>()) {
      return List<double>.from(
        (value as JSFloat64Array).toDart,
        growable: false,
      );
    }

    if (value.isA<JSArray>()) {
      final arr = value as JSArray;
      final out = <double>[];
      for (int i = 0; i < arr.length; i++) {
        final item = arr.getProperty(i.toJS);
        if (item.isA<JSNumber>()) {
          out.add((item as JSNumber).toDartDouble);
        }
      }
      return out;
    }

    return const <double>[];
  }

  List<List<double>> _parseEmbeddingBatch(JSAny? value) {
    if (value == null || !value.isA<JSArray>()) {
      return const <List<double>>[];
    }

    final arr = value as JSArray;
    final out = <List<double>>[];
    for (int i = 0; i < arr.length; i++) {
      out.add(_parseEmbeddingVector(arr.getProperty(i.toJS)));
    }
    return out;
  }

  bool _isEmbeddingMethodUnavailableError(Object error) {
    final lowered = _errorText(error).toLowerCase();
    return lowered.contains('embed is not a function') ||
        lowered.contains('embedbatch is not a function') ||
        lowered.contains('bridge.embed is not a function') ||
        lowered.contains('bridge.embedbatch is not a function') ||
        lowered.contains('llamadart_webgpu_embed_to_json') ||
        lowered.contains('unknown function') &&
            lowered.contains('embed_to_json');
  }

  JSArray? _buildMultimodalParts(List<LlamaContentPart>? parts) {
    if (parts == null || parts.isEmpty) {
      return null;
    }

    final jsParts = JSArray();
    var index = 0;

    for (final part in parts) {
      if (part is LlamaImageContent) {
        final jsPart = JSObject();
        jsPart.setProperty('type'.toJS, 'image'.toJS);

        if (part.bytes != null && part.bytes!.isNotEmpty) {
          jsPart.setProperty('bytes'.toJS, part.bytes!.toJS);
          if (part.width != null && part.width! > 0) {
            jsPart.setProperty('width'.toJS, part.width!.toJS);
          }
          if (part.height != null && part.height! > 0) {
            jsPart.setProperty('height'.toJS, part.height!.toJS);
          }
        } else {
          final url = part.url ?? part.path;
          if (url == null || url.isEmpty) {
            continue;
          }
          jsPart.setProperty('url'.toJS, url.toJS);
        }

        jsParts.setProperty(index.toJS, jsPart);
        index += 1;
        continue;
      }

      if (part is LlamaAudioContent) {
        final jsPart = JSObject();
        jsPart.setProperty('type'.toJS, 'audio'.toJS);

        if (part.samples != null && part.samples!.isNotEmpty) {
          jsPart.setProperty('samples'.toJS, part.samples!.toJS);
        } else if (part.bytes != null && part.bytes!.isNotEmpty) {
          jsPart.setProperty('bytes'.toJS, part.bytes!.toJS);
        } else {
          final url = part.path;
          if (url == null || url.isEmpty) {
            continue;
          }
          jsPart.setProperty('url'.toJS, url.toJS);
        }

        jsParts.setProperty(index.toJS, jsPart);
        index += 1;
      }
    }

    return index == 0 ? null : jsParts;
  }

  bool _isCpuRuntimeForMultimodal(LlamaWebGpuBridge bridge) {
    try {
      final metadata = bridge.getModelMetadata();
      if (metadata != null) {
        final raw = metadata.getProperty('llamadart.webgpu.n_gpu_layers'.toJS);
        final parsed = int.tryParse(_jsValueAsString(raw) ?? '');
        if (parsed != null) {
          return parsed == 0;
        }
      }
    } catch (_) {
      // Fall through to runtime GPU-active probe.
    }

    final gpuActive = bridge.isGpuActive();
    if (gpuActive != null) {
      return !gpuActive;
    }

    return false;
  }

  int? _parsePositiveMetadataInt(JSAny? value) {
    final asText = _jsValueAsString(value);
    if (asText == null) {
      return null;
    }

    final normalized = asText.trim();
    final asInt = int.tryParse(normalized);
    if (asInt != null) {
      return asInt > 0 ? asInt : null;
    }

    final asDouble = double.tryParse(normalized);
    if (asDouble == null || !asDouble.isFinite) {
      return null;
    }

    final rounded = asDouble.round();
    return rounded > 0 ? rounded : null;
  }

  int? _resolveRuntimeThreadCountForMultimodal(LlamaWebGpuBridge bridge) {
    final metadata = bridge.getModelMetadata();
    if (metadata == null) {
      return null;
    }

    final candidates = <String>[
      'llamadart.webgpu.n_threads',
      'llamadart.webgpu.thread_pool_size',
      'llamadart.webgpu.n_threads_batch',
    ];

    for (final key in candidates) {
      final parsed = _parsePositiveMetadataInt(metadata.getProperty(key.toJS));
      if (parsed != null) {
        return parsed;
      }
    }

    return null;
  }

  ({int mediaMaxPredict, int mediaMaxImagePixels, int mediaMaxImageEdge})
  _resolveCpuMultimodalLimits(
    LlamaWebGpuBridge bridge,
    GenerationParams params,
  ) {
    final runtimeThreads = _resolveRuntimeThreadCountForMultimodal(bridge) ?? 2;
    final profile = switch (runtimeThreads) {
      <= 1 => (
        mediaMaxPredict: 128,
        mediaMaxImagePixels: 196608,
        mediaMaxImageEdge: 640,
      ),
      <= 2 => (
        mediaMaxPredict: 160,
        mediaMaxImagePixels: 262144,
        mediaMaxImageEdge: 704,
      ),
      <= 4 => (
        mediaMaxPredict: 192,
        mediaMaxImagePixels: 307200,
        mediaMaxImageEdge: 768,
      ),
      <= 6 => (
        mediaMaxPredict: 224,
        mediaMaxImagePixels: 393216,
        mediaMaxImageEdge: 896,
      ),
      _ => (
        mediaMaxPredict: 256,
        mediaMaxImagePixels: 524288,
        mediaMaxImageEdge: 1024,
      ),
    };

    final requestedPredict = params.maxTokens > 0
        ? params.maxTokens
        : profile.mediaMaxPredict;

    return (
      mediaMaxPredict: math.max(
        32,
        math.min(requestedPredict, profile.mediaMaxPredict),
      ),
      mediaMaxImagePixels: profile.mediaMaxImagePixels,
      mediaMaxImageEdge: profile.mediaMaxImageEdge,
    );
  }

  JSArray _buildWebGpuWarmupParts() {
    final part = JSObject();
    part.setProperty('type'.toJS, 'image'.toJS);
    part.setProperty('bytes'.toJS, _webGpuWarmupRgbBytes.toJS);
    part.setProperty('width'.toJS, 1.toJS);
    part.setProperty('height'.toJS, 1.toJS);

    final parts = JSArray();
    parts.setProperty(0.toJS, part);
    return parts;
  }

  Future<void> _ensureWebGpuMultimodalWarmup(
    LlamaWebGpuBridge bridge, {
    required bool isCpuMultimodalRuntime,
  }) async {
    if (isCpuMultimodalRuntime || !_mmContextActive) {
      return;
    }
    if (_webGpuMultimodalWarmupDone || _webGpuMultimodalWarmupAttempted) {
      return;
    }

    _webGpuMultimodalWarmupAttempted = true;

    final warmupOptions = WebGpuCompletionOptions(
      nPredict: 1,
      mediaMaxPredict: 1,
      temp: 0.0,
      topK: 1,
      topP: 1.0,
      penalty: 1.0,
      seed: 1,
      mediaMaxImagePixels: 65536,
      mediaMaxImageEdge: 256,
      warmup: true,
      parts: _buildWebGpuWarmupParts(),
    );

    try {
      await _toFuture(
        bridge.createCompletion(
          'Describe this image in one word.',
          warmupOptions,
        ),
      ).timeout(_webGpuMultimodalWarmupTimeout);
      _webGpuMultimodalWarmupDone = true;
    } catch (error) {
      _emitConsoleText(
        LlamaLogLevel.debug,
        'WebGpuLlamaBackend: multimodal warmup skipped after failure: '
        '${_errorText(error)}',
      );
    }
  }

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) {
    if (params.presencePenalty != 0.0) {
      throw UnsupportedError('WebGPU presence penalty is not supported yet.');
    }
    if (params.thinkingBudget != null) {
      throw UnsupportedError(
        'WebGPU thinking-budget control is not supported yet.',
      );
    }
    if (params.isSpeculativeDecodingEnabled) {
      throw UnsupportedError(
        'WebGPU speculative decoding is not supported yet.',
      );
    }

    final mediaParts = _buildMultimodalParts(parts);
    if (mediaParts != null && !_mmContextActive) {
      throw StateError(
        'Multimodal input requires loadMultimodalProjector() before generate().',
      );
    }

    final bridge = _requireBridge();
    final isCpuMultimodalRuntime =
        mediaParts != null && _isCpuRuntimeForMultimodal(bridge);
    final isGpuMultimodalRuntime =
        mediaParts != null && !isCpuMultimodalRuntime;
    final cpuMultimodalLimits = isCpuMultimodalRuntime
        ? _resolveCpuMultimodalLimits(bridge, params)
        : null;
    final mediaMaxPredict = cpuMultimodalLimits?.mediaMaxPredict;
    final mediaMaxImagePixels = isCpuMultimodalRuntime
        ? cpuMultimodalLimits?.mediaMaxImagePixels
        : (isGpuMultimodalRuntime ? _gpuMultimodalMaxImagePixels : null);
    final mediaMaxImageEdge = isCpuMultimodalRuntime
        ? cpuMultimodalLimits?.mediaMaxImageEdge
        : (isGpuMultimodalRuntime ? _gpuMultimodalMaxImageEdge : null);

    final abortController = AbortController();
    late final StreamController<List<int>> controller;
    var canceledByCaller = false;
    controller = StreamController<List<int>>(
      onCancel: () {
        if (controller.isClosed) {
          return null;
        }
        canceledByCaller = true;
        if (identical(_abortController, abortController)) {
          _abortController = null;
        }
        abortController.abort();
        bridge.cancel();
        if (!controller.isClosed) {
          return controller.close();
        }
        return null;
      },
    );
    _abortController = abortController;
    var emittedLength = 0;
    var latestText = '';
    var stoppedBySequence = false;
    final stopSequences = params.stopSequences
        .where((stop) => stop.isNotEmpty)
        .toList(growable: false);
    final hasStopSequences = stopSequences.isNotEmpty;
    final maxStopSequenceLength = hasStopSequences
        ? stopSequences.map((stop) => stop.length).reduce(math.max)
        : 0;
    final tokenEventFlushMs = hasStopSequences
        ? 0
        : (mediaParts == null ? 28 : 12);
    final tokenEventFlushChars = hasStopSequences
        ? null
        : (mediaParts == null ? 48 : 24);

    void emitText(String text) {
      if (text.isEmpty || controller.isClosed) {
        return;
      }
      controller.add(utf8.encode(text));
    }

    final onToken = (JSAny? piece, JSAny? currentText) {
      if (hasStopSequences &&
          currentText != null &&
          currentText.isA<JSString>()) {
        final fullText = (currentText as JSString).toDart;
        latestText = fullText;
        if (fullText.length < emittedLength) {
          emittedLength = 0;
        }

        final stopIndex = _findEarliestStopSequenceIndex(
          fullText,
          stopSequences,
          emittedLength - maxStopSequenceLength + 1,
        );

        if (stopIndex != -1) {
          if (stopIndex > emittedLength) {
            emitText(fullText.substring(emittedLength, stopIndex));
          }
          emittedLength = stopIndex;
          stoppedBySequence = true;
          abortController.abort();
          return;
        }

        final safeEmitEnd = math.max(
          emittedLength,
          fullText.length - maxStopSequenceLength + 1,
        );
        if (safeEmitEnd > emittedLength) {
          emitText(fullText.substring(emittedLength, safeEmitEnd));
          emittedLength = safeEmitEnd;
        }

        return;
      }

      final bytes = _pieceToBytes(piece);
      if (bytes.isEmpty) {
        return;
      }

      if (!controller.isClosed) {
        controller.add(bytes);
      }
    }.toJS;

    final options = WebGpuCompletionOptions(
      nPredict: params.maxTokens,
      mediaMaxPredict: mediaMaxPredict,
      temp: params.temp,
      topK: params.topK,
      topP: params.topP,
      penalty: params.penalty,
      seed: params.seed ?? DateTime.now().millisecondsSinceEpoch,
      grammar: params.grammar,
      mediaMaxImagePixels: mediaMaxImagePixels,
      mediaMaxImageEdge: mediaMaxImageEdge,
      onToken: onToken as JSFunction,
      emitCurrentTextOnToken: hasStopSequences,
      tokenEventEncoding: 'bytes',
      tokenEventFlushMs: tokenEventFlushMs,
      tokenEventFlushChars: tokenEventFlushChars,
      parts: mediaParts,
      signal: _abortController?.signal,
    );

    unawaited(
      Future<void>(() async {
        await Future<void>.delayed(Duration.zero);
        try {
          if (mediaParts != null) {
            await _ensureWebGpuMultimodalWarmup(
              bridge,
              isCpuMultimodalRuntime: isCpuMultimodalRuntime,
            );
          }
          final normalizedPrompt = _normalizePromptForBridge(prompt, bridge);
          final completion = bridge.createCompletion(normalizedPrompt, options);
          await _toFuture(completion);

          if (hasStopSequences &&
              !stoppedBySequence &&
              latestText.length > emittedLength) {
            emitText(latestText.substring(emittedLength));
            emittedLength = latestText.length;
          }
        } catch (e, st) {
          if (!stoppedBySequence && !canceledByCaller && !controller.isClosed) {
            controller.addError(e, st);
          }
        } finally {
          if (identical(_abortController, abortController)) {
            _abortController = null;
          }
          if (!controller.isClosed) {
            await controller.close();
          }
        }
      }),
    );

    return controller.stream;
  }

  @override
  void cancelGeneration() {
    _abortController?.abort();
    _bridge?.cancel();
  }

  @override
  Future<List<double>> embed(
    int contextHandle,
    String text, {
    bool normalize = true,
  }) async {
    final bridge = _requireBridge();
    try {
      final result = await _toFuture(
        bridge.embed(text, WebGpuEmbeddingOptions(normalize: normalize)),
      );
      return _parseEmbeddingVector(result);
    } catch (error) {
      if (_isEmbeddingMethodUnavailableError(error)) {
        throw UnsupportedError(
          'Web embeddings require bridge assets with embedding support '
          '(v0.1.7 or newer).',
        );
      }
      rethrow;
    }
  }

  @override
  Future<List<List<double>>> embedBatch(
    int contextHandle,
    List<String> texts, {
    bool normalize = true,
  }) async {
    if (texts.isEmpty) {
      return const <List<double>>[];
    }

    final bridge = _requireBridge();
    final jsTexts = texts.map((text) => text.toJS).toList(growable: false).toJS;
    try {
      final result = await _toFuture(
        bridge.embedBatch(
          jsTexts,
          WebGpuEmbeddingOptions(normalize: normalize),
        ),
      );
      return _parseEmbeddingBatch(result);
    } catch (error) {
      if (_isEmbeddingMethodUnavailableError(error)) {
        final vectors = <List<double>>[];
        for (final text in texts) {
          vectors.add(await embed(contextHandle, text, normalize: normalize));
        }
        return vectors;
      }
      rethrow;
    }
  }

  Future<JSAny?> _toFuture(JSAny? value) async {
    if (value == null) {
      return null;
    }

    if (value.isA<JSPromise>()) {
      return (value as JSPromise<JSAny?>).toDart;
    }

    return value;
  }

  String _normalizePromptForBridge(String prompt, LlamaWebGpuBridge bridge) {
    final metadata = bridge.getModelMetadata();
    if (metadata == null) {
      return _stripLeadingKnownBosToken(prompt);
    }

    final addBosValue = _jsValueAsString(
      metadata.getProperty('tokenizer.ggml.add_bos_token'.toJS),
    );
    final shouldBridgeAddBos = _parseBool(addBosValue, defaultValue: true);
    if (!shouldBridgeAddBos) {
      return prompt;
    }

    final bosToken = _jsValueAsString(
      metadata.getProperty('tokenizer.ggml.bos_token'.toJS),
    );

    final candidates = <String>[
      if (bosToken != null && bosToken.isNotEmpty) bosToken,
      ..._knownBosTokens,
    ];
    return _stripLeadingToken(prompt, candidates);
  }

  String? _jsValueAsString(JSAny? value) {
    if (value == null) {
      return null;
    }
    if (value.isA<JSString>()) {
      return (value as JSString).toDart;
    }
    if (value.isA<JSBoolean>()) {
      return (value as JSBoolean).toDart ? 'true' : 'false';
    }
    if (value.isA<JSNumber>()) {
      return (value as JSNumber).toDartDouble.toString();
    }
    return value.toString();
  }

  bool _parseBool(String? value, {required bool defaultValue}) {
    if (value == null) {
      return defaultValue;
    }

    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
    return defaultValue;
  }

  String _stripLeadingKnownBosToken(String prompt) {
    return _stripLeadingToken(prompt, _knownBosTokens);
  }

  String _stripLeadingToken(String prompt, List<String> candidates) {
    final trimmed = prompt.trimLeft();
    final leadingWhitespaceLength = prompt.length - trimmed.length;
    var body = trimmed;
    var changed = false;

    for (var i = 0; i < 8; i++) {
      String? matched;
      for (final token in candidates) {
        if (token.isEmpty || !body.startsWith(token)) {
          continue;
        }
        matched = token;
        break;
      }

      if (matched == null) {
        break;
      }

      body = body.substring(matched.length).trimLeft();
      changed = true;
    }

    if (!changed) {
      return prompt;
    }

    return prompt.substring(0, leadingWhitespaceLength) + body;
  }

  static const List<String> _knownBosTokens = <String>[
    '<s>',
    '<bos>',
    '<|begin_of_text|>',
    '<|begin_of_sentence|>',
    '<|start_of_text|>',
    '<｜begin▁of▁sentence｜>',
    '[gMASK]<sop>',
  ];

  List<int> _parseTokenList(JSAny? value) {
    if (value == null) {
      return const <int>[];
    }

    if (value.isA<JSUint32Array>()) {
      return (value as JSUint32Array).toDart.cast<int>().toList();
    }

    if (value.isA<JSInt32Array>()) {
      return (value as JSInt32Array).toDart.cast<int>().toList();
    }

    if (value.isA<JSArray>()) {
      final arr = value as JSArray;
      final tokens = <int>[];
      for (int i = 0; i < arr.length; i++) {
        final item = arr.getProperty(i.toJS);
        if (item.isA<JSNumber>()) {
          tokens.add((item as JSNumber).toDartInt);
        }
      }
      return tokens;
    }

    return const <int>[];
  }

  bool _isStatePersistenceMethodUnavailableError(Object error) {
    final lowered = _errorText(error).toLowerCase();
    return lowered.contains('statesavefile is not a function') ||
        lowered.contains('stateloadfile is not a function') ||
        lowered.contains('bridge.statesavefile is not a function') ||
        lowered.contains('bridge.stateloadfile is not a function') ||
        lowered.contains('llamadart_webgpu_state_save_file') ||
        lowered.contains('llamadart_webgpu_state_load_file') ||
        lowered.contains('unknown function') && lowered.contains('state_');
  }

  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async {
    final bridge = _requireBridge();
    final normalizedText = addSpecial
        ? _normalizePromptForBridge(text, bridge)
        : text;
    final result = await _toFuture(bridge.tokenize(normalizedText, addSpecial));
    return _parseTokenList(result);
  }

  @override
  Future<String> detokenize(
    int modelHandle,
    List<int> tokens, {
    bool special = false,
  }) async {
    final bridge = _requireBridge();
    final jsTokens = tokens.map((t) => t.toJS).toList().toJS;
    final result = await _toFuture(bridge.detokenize(jsTokens, special));
    return (result as JSString?)?.toDart ?? '';
  }

  @override
  Future<bool> stateSaveFile(
    int contextHandle,
    String path,
    List<int> tokens,
  ) async {
    final bridge = _requireBridge();
    if (!supportsStatePersistence) {
      throw UnsupportedError(
        'Web state persistence requires bridge assets with state support '
        '(v0.1.15 or newer).',
      );
    }
    final jsTokens = tokens.map((token) => token.toJS).toList().toJS;
    try {
      final result = await _toFuture(bridge.stateSaveFile(path, jsTokens));
      if (result == null) {
        return true;
      }
      if (result.isA<JSBoolean>()) {
        return (result as JSBoolean).toDart;
      }
      return true;
    } catch (error) {
      if (_isStatePersistenceMethodUnavailableError(error)) {
        throw UnsupportedError(
          'Web state persistence requires bridge assets with state support '
          '(v0.1.15 or newer).',
        );
      }
      rethrow;
    }
  }

  @override
  Future<StateLoadResult> stateLoadFile(
    int contextHandle,
    String path,
    int tokenCapacity,
  ) async {
    final bridge = _requireBridge();
    if (!supportsStatePersistence) {
      throw UnsupportedError(
        'Web state persistence requires bridge assets with state support '
        '(v0.1.15 or newer).',
      );
    }
    try {
      final result = await _toFuture(bridge.stateLoadFile(path, tokenCapacity));
      JSAny? rawTokens;
      if (result != null &&
          result.isA<JSObject>() &&
          !result.isA<JSArray>() &&
          !result.isA<JSUint32Array>() &&
          !result.isA<JSInt32Array>()) {
        rawTokens = (result as JSObject).getProperty('tokens'.toJS);
      } else {
        rawTokens = result;
      }
      return StateLoadResult(tokens: _parseTokenList(rawTokens));
    } catch (error) {
      if (_isStatePersistenceMethodUnavailableError(error)) {
        throw UnsupportedError(
          'Web state persistence requires bridge assets with state support '
          '(v0.1.15 or newer).',
        );
      }
      rethrow;
    }
  }

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async {
    final bridge = _requireBridge();
    final metadata = bridge.getModelMetadata();
    if (metadata == null) {
      return <String, String>{};
    }

    final out = <String, String>{};
    final keys = _objectKeys(metadata);
    for (int i = 0; i < keys.length; i++) {
      final key = (keys.getProperty(i.toJS) as JSString).toDart;
      final value = metadata.getProperty(key.toJS);
      if (value.isA<JSString>()) {
        out[key] = (value as JSString).toDart;
      } else if (value.isA<JSNumber>()) {
        out[key] = (value as JSNumber).toDartInt.toString();
      } else {
        out[key] = value.toString();
      }
    }
    return out;
  }

  @override
  Future<void> setLoraAdapter(
    int contextHandle,
    String path,
    double scale,
  ) async {
    throw UnsupportedError(_runtimeLoraUnsupportedMessage);
  }

  @override
  Future<void> removeLoraAdapter(int contextHandle, String path) async {
    throw UnsupportedError(_runtimeLoraUnsupportedMessage);
  }

  @override
  Future<void> clearLoraAdapters(int contextHandle) async {
    throw UnsupportedError(_runtimeLoraUnsupportedMessage);
  }

  @override
  Future<String> getBackendName() async {
    if (_bridge != null) {
      final rawName = _bridge!.getBackendName();
      final name = rawName?.toDart;
      if (name != null && name.isNotEmpty) {
        return name;
      }
    }
    return _usingBridge ? 'WebGPU (Web)' : 'Web Bridge (not loaded)';
  }

  @override
  Future<String> getAvailableBackends() async {
    return getBackendName();
  }

  @override
  bool get supportsUrlLoading => true;

  @override
  Future<bool> isGpuSupported() async {
    if (_bridge == null) {
      return false;
    }
    final active = _bridge!.isGpuActive();
    if (active != null) {
      return active;
    }
    return false;
  }

  @override
  Future<void> setLogLevel(LlamaLogLevel level) {
    _logLevel = level;
    _syncBridgeLogLevel();
    return Future<void>.value();
  }

  @override
  Future<void> dispose() async {
    await _safeDisposeBridge();
  }

  @override
  Future<int?> multimodalContextCreate(
    int modelHandle,
    String mmProjPath,
  ) async {
    final bridge = _requireBridge();
    final cachedBlobUrl = await _cachedModelBlobUrlFor(mmProjPath);
    final projectorPath = cachedBlobUrl ?? mmProjPath;

    try {
      final result = await _toFuture(
        bridge.loadMultimodalProjector(projectorPath),
      );
      _mmContextActive = true;
      _resetWebGpuMultimodalWarmupState();
      await _ensureWebGpuMultimodalWarmup(
        bridge,
        isCpuMultimodalRuntime: _isCpuRuntimeForMultimodal(bridge),
      );

      if (result == null) {
        return 1;
      }

      if (result.isA<JSNumber>()) {
        return (result as JSNumber).toDartInt;
      }

      return 1;
    } finally {
      if (cachedBlobUrl != null) {
        URL.revokeObjectURL(cachedBlobUrl);
      }
    }
  }

  Future<String?> _cachedModelBlobUrlFor(String sourceUrl) async {
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    if (hasPersistentCacheSensitiveUrlParts(sourceUrl)) {
      return null;
    }

    try {
      final caches = globalContext.getProperty<JSAny?>('caches'.toJS);
      if (caches == null || !caches.isA<JSObject>()) {
        return null;
      }

      final cache = await window.caches.open(_defaultModelCacheName).toDart;
      final cachedResponse = await cache.match(sourceUrl.toJS).toDart;
      if (cachedResponse == null) {
        return null;
      }

      final blob = await cachedResponse.blob().toDart;
      return URL.createObjectURL(blob);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isModelResponseCachedForUrl(String sourceUrl) async {
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return false;
    }
    if (hasPersistentCacheSensitiveUrlParts(sourceUrl)) {
      return false;
    }

    try {
      final caches = globalContext.getProperty<JSAny?>('caches'.toJS);
      if (caches == null || !caches.isA<JSObject>()) {
        return false;
      }

      final cache = await window.caches.open(_defaultModelCacheName).toDart;
      final cachedResponse = await cache.match(sourceUrl.toJS).toDart;
      return cachedResponse != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> multimodalContextFree(int mmContextHandle) async {
    final bridge = _bridge;
    if (bridge == null || !_mmContextActive) {
      return;
    }

    await _toFuture(bridge.unloadMultimodalProjector());
    _mmContextActive = false;
    _resetWebGpuMultimodalWarmupState();
  }

  @override
  Future<bool> supportsVision(int mmContextHandle) async {
    if (!_mmContextActive) {
      return false;
    }

    final bridge = _bridge;
    if (bridge == null) {
      return false;
    }

    return bridge.supportsVision() ?? false;
  }

  @override
  Future<bool> supportsAudio(int mmContextHandle) async {
    if (!_mmContextActive) {
      return false;
    }

    final bridge = _bridge;
    if (bridge == null) {
      return false;
    }

    return bridge.supportsAudio() ?? false;
  }

  @override
  Future<({int total, int free})> getVramInfo() async => (total: 0, free: 0);

  @override
  Future<String> applyChatTemplate(
    int modelHandle,
    List<Map<String, dynamic>> messages, {
    String? customTemplate,
    bool addAssistant = true,
  }) async {
    if (!_usingBridge || _bridge == null) {
      final lines = messages
          .map(
            (msg) =>
                '${msg['role']?.toString() ?? 'user'}: ${msg['content']?.toString() ?? ''}',
          )
          .toList();
      if (addAssistant) {
        lines.add('assistant: ');
      }
      return lines.join('\n');
    }

    final bridge = _requireBridge();
    final jsMessages = JSArray();
    for (int i = 0; i < messages.length; i++) {
      final msg = messages[i];
      final jsMsg = JSObject();
      jsMsg.setProperty('role'.toJS, (msg['role']?.toString() ?? '').toJS);
      jsMsg.setProperty(
        'content'.toJS,
        (msg['content']?.toString() ?? '').toJS,
      );
      jsMessages.setProperty(i.toJS, jsMsg);
    }

    final result = bridge.applyChatTemplate(
      jsMessages,
      addAssistant,
      customTemplate,
    );
    if (result == null) {
      return '';
    }

    final jsValue = await result.toDart;
    return jsValue.toDart;
  }
}
