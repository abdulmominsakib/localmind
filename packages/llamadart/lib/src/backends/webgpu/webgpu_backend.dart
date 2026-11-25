import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart';

import '../../core/engine/engine_observer.dart';
import '../../core/models/chat/content_part.dart';
import '../../core/exceptions.dart';
import '../../core/models/config/compute_device.dart';
import '../../core/models/config/gpu_backend.dart';
import '../../core/models/config/llama_cpp_param_values.dart';
import '../../core/models/config/log_level.dart';
import '../../core/models/inference/embedding.dart';
import '../../core/models/inference/generation_params.dart';
import '../../core/models/inference/generation_usage.dart';
import '../../core/models/inference/gpu_layer_count.dart';
import '../../core/models/inference/model_params.dart';
import '../../core/models/inference/model_params_runtime_support.dart';
import '../../core/models/inference/next_token_scores.dart';
import '../../core/template/media_placeholders.dart';
import '../../core/template/resolved_thinking_budget.dart';
import '../../core/template/tool_call_grammar_utils.dart';
import '../backend.dart';
import '../model_params_loras.dart';
import '../web/webgpu_adapter_probe.dart';
import 'interop.dart';
import 'webgpu_decision.dart';
import 'webgpu_errors.dart';
import 'webgpu_load_retry_policy.dart';
import 'webgpu_lora.dart';
import 'webgpu_url.dart';
import 'webgpu_speculative.dart';

@JS('Object.keys')
external JSArray _objectKeys(JSObject obj);

@JS('WebAssembly.Memory')
extension type _WasmMemory._(JSObject _) implements JSObject {
  external _WasmMemory(JSObject descriptor);
}

/// Optional `createCompletion` options the loaded bridge core applies, as its
/// `getCompletionCapabilities()` reports them.
typedef _WebGpuCompletionCapabilities = ({
  bool presencePenalty,
  bool minP,
  bool thinkingBudget,
  bool thinkingBudgetPauseGrammar,
  bool thinkingBudgetMultiEnd,
  bool penaltyPromptTokens,
  bool penaltyPromptTokensWithGrammar,
  bool lazyGrammar,
  Set<SpeculativeDecodingStrategy> speculativeDecoding,
});

const String _webTtsStreamingUnsupportedReason =
    'Streaming text-to-speech is not available on Web: the WebGPU bridge '
    'returns complete PCM only.';

/// Why Web text-to-speech cannot drive [model], or null for Qwen3-TTS.
String? webTextToSpeechModelUnsupportedReason(BackendTextToSpeechModel model) =>
    model == BackendTextToSpeechModel.qwen3Tts
    ? null
    : 'Web text-to-speech drives Qwen3-TTS only; load this model with a '
          'native llama.cpp runtime.';

/// Web backend backed by the llama.cpp bridge runtime.
class WebGpuLlamaBackend
    implements
        BackendRuntimeIdentity,
        LlamaBackend,
        BackendAvailability,
        BackendLoraSupport,
        BackendMultimodalSupport,
        BackendBatchEmbeddings,
        BackendMultimodalEmbeddings,
        BackendPromptSpeechToTextSupport,
        BackendTextToSpeech,
        BackendTextToSpeechModelSupport,
        BackendDecision,
        BackendGenerationCapabilitiesSupport,
        BackendGenerationUsageReporting,
        BackendGenerationLimitReporting,
        BackendChatPromptGeneration,
        BackendPromptPenaltyGeneration,
        BackendNextTokenScoring,
        BackendNextTokenScoringSupport,
        BackendStatePersistence,
        BackendStatePersistenceSupport,
        BackendLazyGrammarSupport {
  static const Duration _bridgeReadyTimeout = Duration(seconds: 12);

  static const Duration _bridgePollInterval = Duration(milliseconds: 100);
  static const int _defaultRemoteFetchChunkBytes = 4 * 1024 * 1024;
  static const int _minRemoteFetchChunkBytes = minRemoteFetchChunkBytes;
  static const int _maxRemoteFetchChunkBytes = 16 * 1024 * 1024;
  static const int _qwen35SmallSafeWebGpuLayers = 2;
  static const int _gpuMultimodalMaxImagePixels = 1048576;
  static const int _gpuMultimodalMaxImageEdge = 1280;
  static const Duration _webGpuMultimodalWarmupTimeout = Duration(seconds: 12);
  static const String _defaultModelCacheName =
      'llamadart-webgpu-model-cache-v1';
  static const String _nextTokenScoringUnsupportedMessage =
      'Web next-token scoring requires llama-web-bridge-assets v0.1.52+.';
  static const String _singleThreadCoreFlag =
      '__llamadartBridgeAllowSingleThreadCore';
  static const String _singleThreadCoreWarningFlag =
      '__llamadartBridgeWarnedSingleThreadCore';
  static const String _singleThreadCoreUnavailable =
      'Single-thread GGUF loading needs llama-web-bridge-assets v0.1.93+ and '
      'matching single-thread core assets. Run dart run llamadart:web_setup '
      'or serve the page with cross-origin isolation (COOP/COEP).';
  static const int _maxInt32 = 0x7fffffff;
  static const _WebGpuCompletionCapabilities _noCompletionCapabilities = (
    presencePenalty: false,
    minP: false,
    thinkingBudget: false,
    thinkingBudgetPauseGrammar: false,
    thinkingBudgetMultiEnd: false,
    penaltyPromptTokens: false,
    penaltyPromptTokensWithGrammar: false,
    lazyGrammar: false,
    speculativeDecoding: <SpeculativeDecodingStrategy>{},
  );
  static const int _maxThinkingBudgetTokens = 0x7fffffff;
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
  final bool? _promptSpeechToTextSupportOverride;

  LlamaWebGpuBridge? _bridge;
  bool _usingBridge = false;
  bool? _activeJsBackedModelStaging;
  bool _isReady = false;
  int _embeddingCancelEpoch = 0;
  String? _chatTemplate;
  String? _singleThreadPreflightNotes;
  LlamaLogLevel _logLevel = LlamaLogLevel.info;
  _GenerationAbort? _generationAbort;
  AbortController? _textToSpeechAbortController;
  int? _lastNCtx;
  bool _mmContextActive = false;
  String? _cachedMmProjectorBlobUrl;
  bool _webGpuMultimodalWarmupDone = false;
  bool _webGpuMultimodalWarmupAttempted = false;
  bool? _preferMemory64Override;
  bool? _forceRemoteFetchBackendOverride;
  final WebGpuDecisionHeads _decisionHeads = WebGpuDecisionHeads();
  final WebGpuLoraAdapters _loraAdapters = WebGpuLoraAdapters();
  final WebGpuDraftModel _draftModel = WebGpuDraftModel();
  _WebGpuCompletionCapabilities _completionCapabilities =
      _noCompletionCapabilities;
  final Expando<LlamaGenerationUsage> _generationUsages =
      Expando<LlamaGenerationUsage>();

  final Expando<BackendGenerationLimit> _generationLimits =
      Expando<BackendGenerationLimit>();

  /// Creates a bridge-backed web backend.
  WebGpuLlamaBackend({
    String? bridgeScriptUrl,
    String? wasmUrl,
    String? workerUrl,
    LlamaWebGpuBridge Function([WebGpuBridgeConfig? config])? bridgeFactory,
    bool? promptSpeechToTextSupported,
  }) : _bridgeScriptUrl = bridgeScriptUrl,
       _bridgeWasmUrl = wasmUrl,
       _bridgeWorkerUrl = workerUrl,
       _bridgeFactory = bridgeFactory,
       _promptSpeechToTextSupportOverride = promptSpeechToTextSupported;

  @override
  bool get isReady => _isReady;

  /// Whether the loaded core reports lazy-grammar and custom-root support.
  @override
  bool get supportsLazyGrammar => _completionCapabilities.lazyGrammar;

  @override
  bool get supportsPromptPenaltiesWithGrammar =>
      _completionCapabilities.penaltyPromptTokensWithGrammar;

  @override
  bool get supportsStatePersistence {
    final bridge = _bridge;
    return _usingBridge &&
        bridge != null &&
        _hasBridgeFunction(bridge, 'stateSaveFile') &&
        _hasBridgeFunction(bridge, 'stateLoadFile');
  }

  @override
  bool get supportsNextTokenScoring {
    final bridge = _bridge;
    return _usingBridge &&
        bridge != null &&
        _hasBridgeFunction(bridge, 'scoreNextToken');
  }

  @override
  bool get supportsPromptSpeechToText =>
      _promptSpeechToTextSupportOverride ??
      _getGlobalOptionalBool('__llamadartBridgeSpeechToTextSupported') == true;

  @override
  String? get promptSpeechToTextUnsupportedReason => supportsPromptSpeechToText
      ? null
      : 'Web typed speech-to-text requires validated '
            'llama-web-bridge-assets v0.1.30 or newer and an explicit runtime '
            'capability opt-in.';

  bool _hasBridgeFunction(LlamaWebGpuBridge bridge, String name) {
    final value = bridge.getProperty(name.toJS);
    return value.isA<JSFunction>();
  }

  bool _bridgeSupportsCompletionUsage(LlamaWebGpuBridge bridge) {
    final constructor = bridge.getProperty('constructor'.toJS);
    return constructor.isA<JSFunction>() &&
        _jsBoolProperty(constructor as JSFunction, 'supportsCompletionUsage') ==
            true;
  }

  int? _jsIntProperty(JSObject object, String name) {
    final value = object.getProperty(name.toJS);
    return value.isA<JSNumber>() ? (value as JSNumber).toDartInt : null;
  }

  bool? _jsBoolProperty(JSObject object, String name) {
    final value = object.getProperty(name.toJS);
    return value.isA<JSBoolean>() ? (value as JSBoolean).toDart : null;
  }

  String? _jsStringProperty(JSObject object, String name) {
    final value = object.getProperty(name.toJS);
    return value.isA<JSString>() ? (value as JSString).toDart : null;
  }

  Duration? _jsMillisecondsProperty(JSObject object, String name) {
    final value = object.getProperty(name.toJS);
    if (!value.isA<JSNumber>()) {
      return null;
    }
    final milliseconds = (value as JSNumber).toDartDouble;
    return milliseconds.isFinite && milliseconds >= 0
        ? Duration(microseconds: (milliseconds * 1000).round())
        : null;
  }

  LlamaGenerationUsage? _generationUsageFromJs(JSAny? value) {
    if (value == null || !value.isA<JSObject>()) {
      return null;
    }
    final usage = value as JSObject;
    final promptTokens = _jsIntProperty(usage, 'promptTokens');
    final completionTokens = _jsIntProperty(usage, 'completionTokens');
    if (promptTokens == null || completionTokens == null) {
      return null;
    }
    return LlamaGenerationUsage(
      promptTokens: promptTokens,
      cachedPromptTokens: _jsIntProperty(usage, 'cachedPromptTokens'),
      completionTokens: completionTokens,
      timeToFirstToken: _jsMillisecondsProperty(usage, 'timeToFirstTokenMs'),
      duration: _jsMillisecondsProperty(usage, 'durationMs'),
    );
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

    // The injected script calls this with no argument on success; dart2js
    // rejects a call that omits a required parameter.
    globalContext.setProperty(
      callbackName.toJS,
      ([JSAny? err]) {
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

  WebGpuBridgeConfig _createBridgeConfig({
    required bool allowSingleThreadCore,
    required bool? jsBackedModelStaging,
  }) {
    final assetUrls = _bridgeAssetUrls(
      singleThread: allowSingleThreadCore,
    ).toList();
    void log(LlamaLogLevel level, JSAny? message) {
      if (!_shouldEmitConsole(level)) return;
      if (message.isA<JSString>() || message.isA<JSObject>()) {
        final text = message.isA<JSString>()
            ? (message as JSString).toDart
            : message as JSObject;
        _emitConsoleText(
          level,
          webGpuBridgeErrorText(text, sourceUrls: assetUrls),
        );
      } else {
        _emitConsole(level, message);
      }
    }

    final logger = JSObject();
    logger.setProperty(
      'debug'.toJS,
      (JSAny? msg) {
        log(LlamaLogLevel.debug, msg);
      }.toJS,
    );
    logger.setProperty(
      'log'.toJS,
      (JSAny? msg) {
        log(LlamaLogLevel.info, msg);
      }.toJS,
    );
    logger.setProperty(
      'warn'.toJS,
      (JSAny? msg) {
        log(LlamaLogLevel.warn, msg);
      }.toJS,
    );
    logger.setProperty(
      'error'.toJS,
      (JSAny? msg) {
        log(LlamaLogLevel.error, msg);
      }.toJS,
    );

    final coreSuffix = allowSingleThreadCore ? 'St' : '';
    final coreModuleUrl = _getGlobalString(
      '__llamadartBridgeCoreModuleUrl$coreSuffix',
    );
    if (allowSingleThreadCore && coreModuleUrl == null) {
      throw LlamaUnsupportedException(_singleThreadCoreUnavailable);
    }
    final coreModuleUrlMem64 = _getGlobalString(
      '__llamadartBridgeCoreModuleUrlMem64$coreSuffix',
    );
    final wasmUrl =
        (allowSingleThreadCore ? null : _bridgeWasmUrl) ??
        _getGlobalString('__llamadartBridgeWasmUrl$coreSuffix');
    final wasmUrlMem64 = _getGlobalString(
      '__llamadartBridgeWasmUrlMem64$coreSuffix',
    );
    final workerModuleUrl =
        _bridgeWorkerUrl ?? _getGlobalString('__llamadartBridgeWorkerUrl');
    final threadPoolSizeHint = _getGlobalPositiveInt(
      '__llamadartBridgeThreadPoolSize',
    );
    // Keep bridge remote-fetch loading opt-in until malformed responses can be
    // rejected without risking an unrecoverable core abort. Forced mode is an
    // explicit opt-in and must enable the bridge capability end to end.
    final allowAutoRemoteFetchBackend =
        !allowSingleThreadCore &&
        jsBackedModelStaging != true &&
        _isRemoteFetchBackendOptedIn();

    final config = WebGpuBridgeConfig(
      wasmUrl: wasmUrl?.toJS,
      wasmUrlMem64: wasmUrlMem64?.toJS,
      workerUrl: workerModuleUrl?.toJS,
      coreModuleUrl: coreModuleUrl?.toJS,
      coreModuleUrlMem64: coreModuleUrlMem64?.toJS,
      preferMemory64: _effectivePreferMemory64,
      allowSingleThreadCore: allowSingleThreadCore ? true : null,
      threadPoolSize: threadPoolSizeHint,
      allowAutoRemoteFetchBackend: allowAutoRemoteFetchBackend,
      remoteFetchChunkBytes: _resolveRemoteFetchChunkBytes(),
      logLevel: _logLevel.index,
      logger: logger,
    );
    if (jsBackedModelStaging != null) {
      config.jsBackedModelStaging = jsBackedModelStaging;
    }
    return config;
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

  Future<bool> _ensureBridge({
    required bool allowSingleThreadCore,
    required bool? jsBackedModelStaging,
    required Iterable<String> sourceUrls,
  }) async {
    if (_bridge != null) {
      return true;
    }

    final factory = _bridgeFactory;
    if (factory != null) {
      _bridge = factory(
        _createBridgeConfig(
          allowSingleThreadCore: allowSingleThreadCore,
          jsBackedModelStaging: jsBackedModelStaging,
        ),
      );
      if (jsBackedModelStaging == true &&
          !_constructorSupportsJsBackedModelStaging(_bridge!['constructor'])) {
        throw LlamaUnsupportedException(webGpuJsBackedStagingRequired);
      }
      return true;
    }

    await _ensureBridgeConstructor(
      allowSingleThreadCore: allowSingleThreadCore,
      requireStaging: jsBackedModelStaging == true,
      sourceUrls: sourceUrls,
    );
    if (!globalContext.has('LlamaWebGpuBridge')) {
      return false;
    }

    final constructor = globalContext['LlamaWebGpuBridge'];
    if (jsBackedModelStaging == true &&
        !_constructorSupportsJsBackedModelStaging(constructor)) {
      throw LlamaUnsupportedException(webGpuJsBackedStagingRequired);
    }
    if (allowSingleThreadCore && !_supportsCorePreflight(constructor)) {
      throw LlamaUnsupportedException(_singleThreadCoreUnavailable);
    }
    _bridge = LlamaWebGpuBridge(
      _createBridgeConfig(
        allowSingleThreadCore: allowSingleThreadCore,
        jsBackedModelStaging: jsBackedModelStaging,
      ),
    );
    return true;
  }

  Future<void> _ensureBridgeConstructor({
    required bool allowSingleThreadCore,
    required bool requireStaging,
    required Iterable<String> sourceUrls,
  }) async {
    if (globalContext.has('LlamaWebGpuBridge')) return;
    final scriptUrl = _bridgeScriptUrl;
    if (scriptUrl == null || scriptUrl.isEmpty) {
      await _waitForPreloadedBridge();
      return;
    }

    try {
      await _loadBridgeScript();
    } on Exception catch (error) {
      if (allowSingleThreadCore) {
        throw _singleThreadBridgeUnavailable(sourceUrls, importError: error);
      }
      if (requireStaging) {
        throw LlamaUnsupportedException(
          'The configured WebGPU bridge module could not be loaded. '
          '$webGpuJsBackedStagingRequired',
        );
      }
      rethrow;
    }
  }

  Future<void> _safeDisposeBridge() async {
    final bridge = _bridge;
    final abortController = _generationAbort?.controller;
    _bridge = null;
    _singleThreadPreflightNotes = null;
    _activeJsBackedModelStaging = null;
    _generationAbort = null;
    _chatTemplate = null;
    _decisionHeads.clear();
    _loraAdapters.forget();
    _completionCapabilities = _noCompletionCapabilities;
    abortController?.abort();
    bridge?.cancel();
    if (bridge == null) {
      _releaseCachedMmProjectorBlobUrl();
      return;
    }

    try {
      final disposePromise = bridge.dispose();
      if (disposePromise != null) {
        await disposePromise.toDart;
      }
    } finally {
      _releaseCachedMmProjectorBlobUrl();
      _usingBridge = false;
      _isReady = false;
      _mmContextActive = false;
      _resetWebGpuMultimodalWarmupState();
    }
  }

  void _resetWebGpuMultimodalWarmupState() {
    _webGpuMultimodalWarmupDone = false;
    _webGpuMultimodalWarmupAttempted = false;
  }

  Future<void> _activateBridge({
    required bool allowSingleThreadCore,
    required bool? jsBackedModelStaging,
    required Iterable<String> sourceUrls,
  }) async {
    if (_bridge != null &&
        _activeJsBackedModelStaging != jsBackedModelStaging) {
      await _safeDisposeBridge();
    }
    if (_usingBridge && _bridge != null) return;

    final ready = await _ensureBridge(
      allowSingleThreadCore: allowSingleThreadCore,
      jsBackedModelStaging: jsBackedModelStaging,
      sourceUrls: sourceUrls,
    );
    if (!ready || _bridge == null) {
      if (allowSingleThreadCore) {
        throw _singleThreadBridgeUnavailable(sourceUrls);
      }
      if (jsBackedModelStaging == true) {
        throw LlamaUnsupportedException(webGpuJsBackedStagingRequired);
      }
      final loadError = _getBridgeLoadError();
      final message = _buildBridgeUnavailableMessage(loadError);
      throw UnsupportedError(message);
    }

    _activeJsBackedModelStaging = jsBackedModelStaging;
    _usingBridge = true;
    _syncBridgeLogLevel();
  }

  Future<({String variant, String notes})?> _activateModelLoadBridge({
    required bool allowSingleThreadCore,
    required bool? requestedStaging,
    required bool tryAutomaticStaging,
    required int automaticStagingModelBytes,
    required Iterable<String> sourceUrls,
  }) async {
    final tryMemory64Staging =
        tryAutomaticStaging &&
        automaticStagingModelBytes <= _automaticStagingMaxModelBytes &&
        _effectivePreferMemory64 != false &&
        _isChromiumBrowser();
    final tryWasm32Staging =
        tryAutomaticStaging &&
        allowSingleThreadCore &&
        automaticStagingModelBytes > _wasm32DefaultStagingMaxModelBytes &&
        automaticStagingModelBytes <= _wasm32JsStagingMaxModelBytes;
    if ((tryMemory64Staging || tryWasm32Staging) &&
        await _canTryAutomaticStaging(
          allowSingleThreadCore: allowSingleThreadCore,
          sourceUrls: sourceUrls,
        )) {
      // Staging is a constructor option in the pinned bridge. Preflight this
      // bridge before it can stage any model bytes.
      try {
        await _activateBridge(
          allowSingleThreadCore: allowSingleThreadCore,
          jsBackedModelStaging: true,
          sourceUrls: sourceUrls,
        );
        final core = await _probeCore(
          _requireBridge(),
          singleThread: allowSingleThreadCore,
        );
        if (core?.variant == 'memory64' && tryMemory64Staging) return core;
        if (core?.variant == 'wasm32' && allowSingleThreadCore) {
          _checkWasm32StagingLimit(automaticStagingModelBytes);
          if (tryWasm32Staging) return core;
        }
      } on LlamaUnsupportedException catch (error) {
        if (error.message != webGpuJsBackedStagingRequired) rethrow;
        await _safeDisposeBridge();
      }
    }

    await _activateBridge(
      allowSingleThreadCore: allowSingleThreadCore,
      jsBackedModelStaging: requestedStaging,
      sourceUrls: sourceUrls,
    );
    if (!allowSingleThreadCore) return null;
    final core = await _probeCore(_requireBridge(), singleThread: true);
    if (core == null) {
      throw LlamaUnsupportedException(_singleThreadCoreUnavailable);
    }
    if (core.variant == 'wasm32') {
      _checkWasm32StagingLimit(automaticStagingModelBytes);
    }
    return core;
  }

  void _checkWasm32StagingLimit(int modelBytes) {
    if (modelBytes <= _wasm32JsStagingMaxModelBytes) return;
    throw LlamaUnsupportedException(
      'Automatic JS-backed model staging on the wasm32 single-thread core '
      'supports size hints up to 3.75 GiB. This GGUF size hint is $modelBytes '
      'bytes. Use a browser with memory64 or choose a smaller or sharded GGUF.',
    );
  }

  Future<bool> _canTryAutomaticStaging({
    required bool allowSingleThreadCore,
    required Iterable<String> sourceUrls,
  }) async {
    if (_bridgeFactory != null) {
      if (_bridge == null) {
        await _activateBridge(
          allowSingleThreadCore: allowSingleThreadCore,
          jsBackedModelStaging: null,
          sourceUrls: sourceUrls,
        );
      }
    } else {
      await _ensureBridgeConstructor(
        allowSingleThreadCore: allowSingleThreadCore,
        requireStaging: false,
        sourceUrls: sourceUrls,
      );
      if (!globalContext.has('LlamaWebGpuBridge')) {
        if (allowSingleThreadCore) {
          throw _singleThreadBridgeUnavailable(sourceUrls);
        }
        throw UnsupportedError(
          _buildBridgeUnavailableMessage(_getBridgeLoadError()),
        );
      }
    }
    final constructor =
        _bridge?['constructor'] ?? globalContext['LlamaWebGpuBridge'];
    return _constructorSupportsJsBackedModelStaging(constructor) &&
        _supportsCorePreflight(constructor);
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

  LlamaUnsupportedException _singleThreadBridgeUnavailable(
    Iterable<String> sourceUrls, {
    Object? importError,
  }) {
    final loadError = _getBridgeLoadError() ?? importError?.toString();
    return LlamaUnsupportedException(
      webGpuBridgeErrorText(
        _buildBridgeUnavailableMessage(loadError),
        sourceUrls: sourceUrls,
      ),
    );
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

  Iterable<String> _bridgeAssetUrls({required bool singleThread}) sync* {
    final suffix = singleThread ? 'St' : '';
    for (final url in [
      _bridgeScriptUrl,
      _bridgeWorkerUrl,
      if (!singleThread) _bridgeWasmUrl,
      _getGlobalString('__llamadartBridgeModuleUrl'),
      _getGlobalString('__llamadartBridgeAssetSource'),
      _getGlobalString('__llamadartBridgeWorkerUrl'),
      _getGlobalString('__llamadartBridgeCoreModuleUrl$suffix'),
      _getGlobalString('__llamadartBridgeCoreModuleUrlMem64$suffix'),
      _getGlobalString('__llamadartBridgeWasmUrl$suffix'),
      _getGlobalString('__llamadartBridgeWasmUrlMem64$suffix'),
    ]) {
      if (url != null) yield url;
    }
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

  bool get _isNonIsolatedPage {
    final isolated = globalContext['crossOriginIsolated'];
    return isolated.isA<JSBoolean>() && !(isolated as JSBoolean).toDart;
  }

  bool _canPostSharedMemory() {
    // Pthread startup posts a shared WebAssembly.Memory to a worker.
    MessageChannel? channel;
    try {
      final memory = _WasmMemory(
        JSObject()
          ..['initial'] = 1.toJS
          ..['maximum'] = 1.toJS
          ..['shared'] = true.toJS,
      );
      channel = MessageChannel();
      channel.port1.postMessage(memory);
      return true;
    } catch (_) {
      return false;
    } finally {
      channel?.port1.close();
      channel?.port2.close();
    }
  }

  void _warnAboutSingleThreadCore() {
    if (globalContext.has(_singleThreadCoreWarningFlag)) return;
    globalContext[_singleThreadCoreWarningFlag] = true.toJS;
    console.warn(
      'llamadart is using the single-thread GGUF core with lower performance '
              'because this page cannot share Wasm memory with workers. Serve '
              'Cross-Origin-Opener-Policy: same-origin and '
              'Cross-Origin-Embedder-Policy: require-corp (COOP/COEP) for the '
              'threaded core. '
              'Set window.$_singleThreadCoreFlag = false to opt out.'
          .toJS,
    );
  }

  bool _supportsCorePreflight(JSAny? constructor) {
    if (!constructor.isA<JSObject>()) return false;
    final flag = (constructor as WebGpuBridgeConstructor).supportsCorePreflight;
    return flag.isA<JSBoolean>() && (flag as JSBoolean).toDart;
  }

  Future<({String variant, String notes})?> _probeCore(
    LlamaWebGpuBridge bridge, {
    required bool singleThread,
  }) async {
    if (!_supportsCorePreflight(bridge['constructor']) ||
        !_hasBridgeFunction(bridge, 'preflightCore')) {
      return null;
    }

    final JSAny? raw;
    try {
      raw = await bridge.preflightCore()?.toDart;
    } catch (error) {
      if (webGpuCoreAssetError(error)?.code == 'CORE_PREFLIGHT_UNSUPPORTED') {
        return null;
      }
      rethrow;
    }
    if (!raw.isA<JSObject>()) return null;

    final result = raw as WebGpuCorePreflightResult;
    String? string(JSAny? value) =>
        value.isA<JSString>() ? (value as JSString).toDart : null;
    final variant = string(result.variant);
    final threading = string(result.threading);
    final fallback = result.fallback;
    final fallbackReason = result.fallbackReason;
    final reason = string(fallbackReason);
    if ((variant != 'wasm32' && variant != 'memory64') ||
        threading != (singleThread ? 'single-thread' : 'threaded') ||
        !fallback.isA<JSBoolean>() ||
        (fallbackReason != null &&
            !const {'unsupported', 'timeout', 'init_error'}.contains(reason))) {
      return null;
    }

    return (
      variant: variant!,
      notes: [
        'core_preflight_variant:$variant',
        'core_preflight_threading:$threading',
        'core_preflight_fallback:${(fallback as JSBoolean).toDart ? 1 : 0}',
        if (reason != null) 'core_preflight_fallback_reason:$reason',
      ].join(';'),
    );
  }

  bool _constructorSupportsJsBackedModelStaging(JSAny? constructor) {
    if (!constructor.isA<JSObject>()) return false;
    final flag =
        (constructor as WebGpuBridgeConstructor).supportsJsBackedModelStaging;
    return flag.isA<JSBoolean>() && (flag as JSBoolean).toDart;
  }

  LlamaUnsupportedException? _verifyJsBackedModelStaging(
    LlamaWebGpuBridge bridge, {
    required bool projector,
  }) {
    final requested = _activeJsBackedModelStaging;
    if (requested == null) return null;
    final metadata = _hasBridgeFunction(bridge, 'getModelMetadata')
        ? bridge.getModelMetadata()
        : null;
    final rawNotes = metadata?['llamadart.webgpu.runtime_notes'];
    final expected = projector
        ? 'mmproj_staging_js_backed'
        : 'model_staging_js_backed';
    final active =
        rawNotes.isA<JSString>() &&
        (rawNotes as JSString).toDart.split(';').contains(expected);
    if (active == requested) return null;
    if (requested) {
      return LlamaUnsupportedException(webGpuJsBackedStagingRequired);
    }
    final target = projector ? 'projector' : 'model';
    return LlamaUnsupportedException(
      'The loaded WebGPU bridge enabled JS-backed $target staging despite '
      'ModelParams.jsBackedModelStaging: false. Update to '
      'llama-web-bridge-assets v0.1.92+.',
    );
  }

  bool _isRemoteFetchBackendOptedIn() {
    return _getGlobalOptionalBool(
              '__llamadartBridgeAllowAutoRemoteFetchBackend',
            ) ==
            true ||
        _getGlobalBool('__llamadartBridgeForceRemoteFetchBackend');
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

  bool _isChromiumBrowser() {
    final userAgent = _getBridgeUserAgent() ?? '';
    return userAgent.contains('Chrome/') || userAgent.contains('Chromium/');
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

  bool _isLikelyMemoryPressureError(Object error) =>
      isMemoryPressureErrorText(_errorText(error).toLowerCase());

  List<({int contextSize, int gpuLayers})> _buildLoadAttempts({
    required int requestedContextSize,
    required int requestedGpuLayers,
    required bool allowCpuFallback,
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

      if (requestedGpuLayers > 0 && allowCpuFallback) {
        final cpuKey = '$normalizedContext|0';
        if (seen.add(cpuKey)) {
          attempts.add((contextSize: normalizedContext, gpuLayers: 0));
        }
      }
    }

    return attempts;
  }

  int? _resolveAttemptThreads(int index, int? requestedThreads) {
    return switch (index) {
      0 => requestedThreads,
      1 || 2 => requestedThreads == null ? 4 : math.min(requestedThreads, 4),
      3 ||
      4 ||
      5 ||
      6 => requestedThreads == null ? 2 : math.min(requestedThreads, 2),
      _ => 1,
    };
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
    final isCpuAttempt =
        params.preferredBackend == GpuBackend.cpu || gpuLayers == 0;
    final shouldUseQwen35SmallTuning =
        !hasExplicitBatchSizes && !isCpuAttempt && isQwen35Small;

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
    // architecture. Keep full-context automatic batching for unknown models:
    // non-causal encoders must process the whole input in one micro-batch.
    // Only the existing Qwen3.5-0.8B preset uses decoder defaults on CPU,
    // because its full-context micro-batch can exceed wasm32 memory.
    final resolved = resolveModelContextBatchSizes(
      params,
      contextSize,
      useFullContextDefaults: !(isCpuAttempt && isQwen35Small),
    );
    return (nBatch: resolved.batchSize, nUbatch: resolved.microBatchSize);
  }

  // Approximate wasm32 linear-memory ceiling under which a model + KV cache can
  // be expected to fit. Models at or above this should load into the mem64 core
  // up front. wasm32 caps at 4 GiB; ~2 GiB leaves headroom for the KV cache and
  // intermediate buffers.
  static const int _wasm32SafeModelCeilingBytes = 2 * 1024 * 1024 * 1024;

  // Older compatible cores can mmap a lazy tensor above 4 GiB and clamp
  // JS-backed WasmFS reads at INT32_MAX. Preflight does not identify the
  // newer read path. Without a size hint, keep the bridge policy.
  static const int _automaticStagingMaxModelBytes = 4 * 1024 * 1024 * 1024;

  // Without preallocation the released WasmFS writer failed above 1 GiB.
  static const int _wasm32DefaultStagingMaxModelBytes = 960 * 1024 * 1024;
  // Leave about 256 MiB below the largest verified JS-staged load (#2210).
  static const int _wasm32JsStagingMaxModelBytes = 3840 * 1024 * 1024;

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

  bool? get _effectivePreferMemory64 =>
      _preferMemory64Override ??
      _getGlobalOptionalBool('__llamadartBridgePreferMemory64');

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
    required bool allowSingleThreadCore,
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
    if (runtimeNotesIndicateModelFsWriteFailure(runtimeNotes) &&
        !remoteFetchBackendOptedIn) {
      if (allowSingleThreadCore) {
        return UnsupportedError(
          'Web model staging failed on the single-thread core. Try a smaller '
          'or sharded GGUF or use memory64 if supported. Fetch-backed loading '
          'requires a threaded core and cross-origin isolation (COOP/COEP).',
        );
      }
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
        runtimeNotes.contains('thread_constructor_failed') ||
        isThreadConstructorFailureText(loweredText);

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

  /// Returns the optional completion options [bridge] reports applying, or
  /// none when it lacks `getCompletionCapabilities` or the probe fails.
  Future<_WebGpuCompletionCapabilities> _probeCompletionCapabilities(
    LlamaWebGpuBridge bridge,
  ) async {
    if (!_hasBridgeFunction(bridge, 'getCompletionCapabilities')) {
      return _noCompletionCapabilities;
    }
    try {
      final raw = await _toFuture(bridge.getCompletionCapabilities());
      if (raw == null || !raw.isA<JSObject>()) {
        return _noCompletionCapabilities;
      }
      final capabilities = raw as WebGpuCompletionCapabilities;
      bool reported(JSAny? value) =>
          value != null &&
          value.isA<JSBoolean>() &&
          (value as JSBoolean).toDart;
      return (
        presencePenalty: reported(capabilities.presencePenalty),
        minP: reported(capabilities.minP),
        thinkingBudget: reported(capabilities.thinkingBudget),
        thinkingBudgetMultiEnd: reported(capabilities.thinkingBudgetMultiEnd),
        thinkingBudgetPauseGrammar: reported(
          capabilities.thinkingBudgetPauseGrammar,
        ),
        penaltyPromptTokens: reported(capabilities.penaltyPromptTokens),
        penaltyPromptTokensWithGrammar: reported(
          capabilities.penaltyPromptTokensWithGrammar,
        ),
        lazyGrammar: reported(capabilities.lazyGrammar),
        speculativeDecoding: webGpuSpeculativeStrategiesFrom(
          capabilities.speculativeDecoding,
          hasDraftModelApi:
              _hasBridgeFunction(bridge, 'loadDraftModel') &&
              _hasBridgeFunction(bridge, 'unloadDraftModel'),
        ),
      );
    } catch (error) {
      _emitConsoleText(
        LlamaLogLevel.warn,
        'WebGpuLlamaBackend: completion capability probe failed: '
        '${webGpuBridgeErrorText(error)}',
      );
      return _noCompletionCapabilities;
    }
  }

  LlamaWebGpuBridge _requireBridge() {
    final bridge = _bridge;
    if (!_usingBridge || bridge == null) {
      throw LlamaStateException(
        'Web bridge is not active. Load a model with LlamaEngine.load or '
        'setModel first.',
      );
    }
    return bridge;
  }

  @override
  Future<int> modelLoad(String path, ModelParams params) {
    return modelLoadFromUrl(path, params);
  }

  ({
    int requestedGpuLayers,
    int? requestedThreads,
    bool requireGpu,
    JSFunction? progressCallback,
  })
  _prepareUrlLoad(
    String url,
    ModelParams params,
    void Function(double progress)? onProgress,
  ) {
    params.validate();
    checkModelParamsTypeFor(params, LlamaRuntime.llamaCpp);
    if (params.liteRtLmEmbeddingEngine) {
      throw LlamaUnsupportedException(
        'ModelParams.liteRtLmEmbeddingEngine is LiteRT-LM-only; '
        'llama.cpp GGUF embeddings use the existing per-call mode.',
      );
    }
    if (params.device == ComputeDevice.npu) {
      throw LlamaUnsupportedException(
        'ComputeDevice.npu is not available for llama.cpp on the Web, which '
        'runs on WebGPU or the WebAssembly CPU runtime; only LiteRT-LM on '
        'Android has an NPU backend. Use ComputeDevice.auto, cpu or gpu.',
      );
    }
    checkModelParamsSupportedBy(params, LlamaRuntime.llamaCpp, web: true);
    final requireGpu = params.device == ComputeDevice.gpu;
    _preferMemory64Override = _resolvePreferMemory64(params);
    _forceRemoteFetchBackendOverride = null;

    final requestedThreads = params.numberOfThreads > 0
        ? params.numberOfThreads
        : null;
    var requestedGpuLayers =
        params.preferredBackend == GpuBackend.cpu ||
            params.device == ComputeDevice.cpu
        ? 0
        : resolveGpuLayerCount(params.gpuLayers);

    if (requestedGpuLayers > 0 &&
        _isSafariBrowser() &&
        !_allowSafariWebGpu() &&
        !_bridgeSupportsAdaptiveSafariGpu()) {
      if (requireGpu) {
        throw LlamaUnsupportedException(
          'ComputeDevice.gpu needs WebGPU for llama.cpp on the Web, but these '
          'bridge assets run Safari on the CPU. Use bridge assets with '
          'adaptive Safari GPU probe support, or ComputeDevice.auto.',
        );
      }
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

    return (
      requestedGpuLayers: requestedGpuLayers,
      requestedThreads: requestedThreads,
      requireGpu: requireGpu,
      progressCallback: progressCallback,
    );
  }

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    void Function(double progress)? onProgress,
  }) async {
    url = webGpuDocumentUrl(url);
    final cacheUrl = webGpuPersistentCacheUrl(url);
    final setup = _prepareUrlLoad(url, params, onProgress);
    final allowSingleThreadCore = _isNonIsolatedPage && !_canPostSharedMemory();
    final explicitSelection = _getGlobalOptionalBool(_singleThreadCoreFlag);
    if (allowSingleThreadCore && explicitSelection == false) {
      throw webGpuCrossOriginIsolationRequired();
    }
    final sourceUrls = <String>{
      url,
      ..._bridgeAssetUrls(singleThread: allowSingleThreadCore),
    };
    final forceRemoteFetch = _getGlobalBool(
      '__llamadartBridgeForceRemoteFetchBackend',
    );
    if (allowSingleThreadCore && forceRemoteFetch) {
      throw LlamaUnsupportedException(
        'The single-thread Web core does not support fetch-backed model '
        'loading, which requires a pthread core in a browser worker. Disable '
        '__llamadartBridgeForceRemoteFetchBackend for streamed staging.',
      );
    }
    final jsBackedModelStaging = params.jsBackedModelStaging;
    if (jsBackedModelStaging == true && forceRemoteFetch) {
      throw LlamaUnsupportedException(
        'JS-backed model staging cannot be combined with forced fetch-backed '
        'loading (__llamadartBridgeForceRemoteFetchBackend). Disable forced '
        'fetch-backed loading or omit ModelParams.jsBackedModelStaging.',
      );
    }
    final remoteFetchBackendOptedIn =
        !allowSingleThreadCore &&
        jsBackedModelStaging != true &&
        _isRemoteFetchBackendOptedIn();
    final automaticStagingModelBytes =
        jsBackedModelStaging == null && !remoteFetchBackendOptedIn
        ? params.modelBytesHint ?? 0
        : 0;
    var tryAutomaticStaging = automaticStagingModelBytes > 0;
    if (setup.requireGpu && !await webGpuAdapterAvailable()) {
      throw LlamaUnsupportedException(
        'ComputeDevice.gpu needs WebGPU for llama.cpp on the Web, but this '
        'browser grants no WebGPU adapter. Use ComputeDevice.auto or cpu, or '
        'a browser with WebGPU enabled.',
      );
    }
    _singleThreadPreflightNotes = null;
    _loraAdapters.forget();
    _completionCapabilities = _noCompletionCapabilities;
    final loadAttempts = _buildLoadAttempts(
      requestedContextSize: params.contextSize,
      requestedGpuLayers: setup.requestedGpuLayers,
      allowCpuFallback: !setup.requireGpu,
    );
    bool? cachedWebModel;
    Object? lastError;
    Map<String, String> lastRuntimeHints = const <String, String>{};
    var escalation = WebGpuLoadEscalation(
      remoteFetchChunkBytes: _resolveRemoteFetchChunkBytes(),
    );
    for (var index = 0; index < loadAttempts.length; index += 1) {
      final attempt = loadAttempts[index];
      _lastNCtx = attempt.contextSize;
      final batchSizes = _resolveWebBatchSizes(
        url: url,
        params: params,
        contextSize: attempt.contextSize,
        gpuLayers: attempt.gpuLayers,
      );
      bool? forceRemoteFetchBackend;
      final attemptThreads = _resolveAttemptThreads(
        index,
        setup.requestedThreads,
      );

      try {
        final preflight = await _activateModelLoadBridge(
          allowSingleThreadCore: allowSingleThreadCore,
          requestedStaging: jsBackedModelStaging,
          tryAutomaticStaging: tryAutomaticStaging,
          automaticStagingModelBytes: automaticStagingModelBytes,
          sourceUrls: sourceUrls,
        );
        final bridge = _requireBridge();
        if (allowSingleThreadCore && explicitSelection == null) {
          _warnAboutSingleThreadCore();
        }
        cachedWebModel ??= await _isModelResponseCachedForUrl(bridge, cacheUrl);

        if (_activeJsBackedModelStaging == true) {
          forceRemoteFetchBackend = false;
        } else if (_forceRemoteFetchBackendOverride != null) {
          forceRemoteFetchBackend = _forceRemoteFetchBackendOverride;
        } else if (forceRemoteFetch) {
          forceRemoteFetchBackend = true;
        } else if (cachedWebModel == true) {
          forceRemoteFetchBackend = false;
        }

        final loadPromise = bridge.loadModelFromUrl(
          cacheUrl ?? url,
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
            useCache: cacheUrl != null,
            forceRemoteFetchBackend: forceRemoteFetchBackend,
            remoteFetchChunkBytes: escalation.remoteFetchChunkBytes,
            modelBytesHint: params.modelBytesHint,
            loadMtp: params.loadMtp ? true : null,
            speculativeRollbackTokenMax: params.speculativeRollbackTokenMax > 0
                ? params.speculativeRollbackTokenMax
                : null,
            progressCallback: setup.progressCallback,
          ),
        );

        if (loadPromise != null) {
          await loadPromise.toDart;
        }
        if (tryAutomaticStaging &&
            _activeJsBackedModelStaging == true &&
            preflight?.variant != 'wasm32' &&
            _collectBridgeRuntimeHints(
                  bridge,
                )['llamadart.webgpu.core_variant'] ==
                'wasm32') {
          // The bridge can replace an unusable worker during the load.
          tryAutomaticStaging = false;
          await _safeDisposeBridge();
          index -= 1;
          continue;
        }
        final unverifiedStaging = _verifyJsBackedModelStaging(
          bridge,
          projector: false,
        );
        if (unverifiedStaging != null) throw unverifiedStaging;

        if (setup.requireGpu && bridge.isGpuActive() != true) {
          var gpuDetail = '';
          try {
            gpuDetail = webGpuUnavailableDetail(
              _collectBridgeRuntimeHints(
                    bridge,
                  )['llamadart.webgpu.runtime_notes'] ??
                  '',
            );
          } catch (_) {}
          throw LlamaUnsupportedException(
            'ComputeDevice.gpu needs WebGPU for llama.cpp on the Web, but the '
            'runtime loaded the model without GPU layers.'
            '${webGpuBridgeErrorText(gpuDetail, sourceUrls: sourceUrls)} Use '
            'ComputeDevice.auto or cpu.',
          );
        }

        if (index > 0) {
          _emitConsoleText(
            LlamaLogLevel.warn,
            'WebGpuLlamaBackend: model loaded after fallback '
            '(nCtx=${attempt.contextSize}, nGpuLayers=${attempt.gpuLayers}, '
            'nThreads=$attemptThreads)',
          );
        }

        _singleThreadPreflightNotes = allowSingleThreadCore
            ? preflight?.notes
            : null;
        _isReady = true;
        _chatTemplate = params.chatTemplate;
        _mmContextActive = false;
        _decisionHeads.clear();
        _resetWebGpuMultimodalWarmupState();
        _completionCapabilities = await _probeCompletionCapabilities(bridge);
        return 1;
      } on LlamaUnsupportedException {
        await _safeDisposeBridge();
        rethrow;
      } catch (e) {
        if (webGpuCoreAssetError(e) case (
          code: 'CORE_ASSET_UNAVAILABLE',
          :final asset,
        )) {
          await _safeDisposeBridge();
          if (allowSingleThreadCore) {
            throw LlamaUnsupportedException(_singleThreadCoreUnavailable);
          }
          final unavailable = switch (asset) {
            'loader' => 'core loader',
            'wasm' => 'core Wasm binary',
            'worker' => 'bridge worker',
            _ => 'core asset',
          };
          throw LlamaUnsupportedException(
            'The WebGPU $unavailable is unavailable. Run dart run '
            'llamadart:web_setup to install matching bridge assets.',
          );
        }
        final isolationError = webGpuCrossOriginIsolationError(e);
        if (isolationError != null) {
          await _safeDisposeBridge();
          throw isolationError;
        }
        final stagingError = webGpuModelStagingError(e, sourceUrls: sourceUrls);
        if (stagingError != null) {
          final retryWithoutStaging =
              tryAutomaticStaging &&
              _activeJsBackedModelStaging == true &&
              stagingError is WebGpuJsBackedStagingUnsupported;
          await _safeDisposeBridge();
          if (retryWithoutStaging) {
            tryAutomaticStaging = false;
            index -= 1;
            continue;
          }
          throw stagingError;
        }
        lastError = e;
        Map<String, String> runtimeHints = const <String, String>{};
        final bridgeForAttempt = _bridge;
        if (bridgeForAttempt != null) {
          try {
            runtimeHints = _collectBridgeRuntimeHints(bridgeForAttempt);
          } catch (_) {
            runtimeHints = const <String, String>{};
          }
        }
        lastRuntimeHints = runtimeHints;
        final coreVariant = runtimeHints['llamadart.webgpu.core_variant'];

        _emitConsoleText(
          LlamaLogLevel.error,
          'WebGpuLlamaBackend: Bridge model load failed: '
          '${webGpuBridgeErrorText(e, sourceUrls: sourceUrls)}',
        );
        if (runtimeHints.isNotEmpty) {
          _emitConsoleText(
            LlamaLogLevel.warn,
            webGpuBridgeErrorText(
              'WebGpuLlamaBackend: bridge runtime hints $runtimeHints',
              sourceUrls: sourceUrls,
            ),
          );
        }

        final decision = classifyWebGpuLoadFailure(
          WebGpuLoadFailure(
            attemptIndex: index,
            attemptCount: loadAttempts.length,
            errorText: _errorText(e).toLowerCase(),
            coreVariant: coreVariant,
            runtimeNotes: runtimeHints['llamadart.webgpu.runtime_notes'] ?? '',
            forceRemoteFetchRequested: forceRemoteFetchBackend == true,
            remoteFetchBackendOptedIn: remoteFetchBackendOptedIn,
          ),
          escalation,
        );
        escalation = decision.escalation;

        await _safeDisposeBridge();

        final preferMemory64 = decision.preferMemory64;
        if (preferMemory64 != null) {
          _preferMemory64Override = preferMemory64;
        }
        final forceRemoteFetch = decision.forceRemoteFetchBackend;
        if (forceRemoteFetch != null) {
          _forceRemoteFetchBackendOverride = forceRemoteFetch;
        }
        for (final message in decision.logMessages) {
          _emitConsoleText(LlamaLogLevel.warn, message);
        }

        switch (decision.action) {
          case WebGpuRetryAction.restart:
            index = -1;
            continue;
          case WebGpuRetryAction.advance:
            final nextAttempt = loadAttempts[index + 1];
            final nextThreads = _resolveAttemptThreads(
              index + 1,
              setup.requestedThreads,
            );
            _emitConsoleText(
              LlamaLogLevel.warn,
              'WebGpuLlamaBackend: retrying web model load with reduced '
              'settings (nCtx=${nextAttempt.contextSize}, '
              'nGpuLayers=${nextAttempt.gpuLayers}, '
              'nThreads=$nextThreads)',
            );
            continue;
          case WebGpuRetryAction.giveUp:
            break;
        }

        final normalized = _normalizeBridgeRuntimeError(
          e,
          runtimeHints: runtimeHints,
          remoteFetchBackendOptedIn: remoteFetchBackendOptedIn,
          allowSingleThreadCore: allowSingleThreadCore,
        );
        throw _redactedModelLoadError(normalized ?? e, sourceUrls);
      }
    }

    if (lastError != null) {
      final normalized = _normalizeBridgeRuntimeError(
        lastError,
        runtimeHints: lastRuntimeHints,
        remoteFetchBackendOptedIn: remoteFetchBackendOptedIn,
        allowSingleThreadCore: allowSingleThreadCore,
      );
      throw _redactedModelLoadError(normalized ?? lastError, sourceUrls);
    }

    throw StateError('WebGpuLlamaBackend: model load failed unexpectedly');
  }

  Object _redactedModelLoadError(Object error, Iterable<String> sourceUrls) {
    if (error is LlamaException) return error;
    if (error is UnsupportedError) {
      return UnsupportedError(
        webGpuBridgeErrorText(error.message ?? '', sourceUrls: sourceUrls),
      );
    }
    return LlamaModelException(
      'The Web runtime could not load the model.',
      webGpuBridgeErrorText(error, sourceUrls: sourceUrls),
    );
  }

  @override
  Future<void> modelFree(int modelHandle) async {
    await _safeDisposeBridge();
  }

  /// Applies [ModelParams.loras] through the runtime LoRA API, so non-empty
  /// `loras` need the bridge assets [setLoraAdapter] needs.
  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async {
    final bridge = _requireBridge();
    await applyModelParamsLoras(
      params.loras,
      apply: (lora) => _loraAdapters.set(bridge, lora.path, lora.scale),
      rollback: () => _loraAdapters.clear(bridge),
    );
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
      if (part is LlamaVideoContent) {
        throw LlamaUnsupportedException(
          'WebGPU video input is not supported through llamadart. Extract '
          'and send image frames instead.',
        );
      }

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
    if (isCpuMultimodalRuntime ||
        !_mmContextActive ||
        !(bridge.supportsVision() ?? false)) {
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
  Stream<List<int>> generateChatPrompt(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    required String mediaMarker,
    List<LlamaContentPart>? parts,
  }) => generate(
    contextHandle,
    chatPromptForMarkerRuntime(
      prompt,
      chatMarker: mediaMarker,
      marker: mtmdMediaMarker,
      runtimePlaceholders: webGpuBridgeMediaPlaceholders,
    ),
    params,
    parts: parts,
  );

  @override
  Stream<List<int>> generateWithPromptPenalties(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    String? mediaMarker,
    List<LlamaContentPart>? parts,
  }) => webGpuValidateArguments(
    () => _generate(
      contextHandle,
      mediaMarker == null
          ? prompt
          : chatPromptForMarkerRuntime(
              prompt,
              chatMarker: mediaMarker,
              marker: mtmdMediaMarker,
              runtimePlaceholders: webGpuBridgeMediaPlaceholders,
            ),
      params,
      parts: parts,
      countPromptTokensInPenalties: true,
    ),
  );

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) => webGpuValidateArguments(
    () => _generate(contextHandle, prompt, params, parts: parts),
  );

  Stream<List<int>> _generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
    bool countPromptTokensInPenalties = false,
  }) {
    final activeBridge = _activeBridge;
    if (activeBridge != null) webGpuThrowIfModelUnloaded(activeBridge);
    final capabilities = _completionCapabilities;
    if (countPromptTokensInPenalties &&
        !capabilities.penaltyPromptTokensWithGrammar) {
      throw LlamaUnsupportedException(
        'Web prompt penalties with grammar require bridge assets v0.1.82+ '
        'whose loaded core reports penaltyPromptTokensWithGrammar; '
        'the loaded core does not.',
      );
    }
    if (countPromptTokensInPenalties &&
        (params.grammar == null || isPromptExcludedFromPenalties(params))) {
      throw LlamaUnsupportedException(
        'Web prompt penalties with grammar require an attached grammar and '
        'cannot be combined with prompt-penalty exclusion.',
      );
    }
    if (params.presencePenalty != 0.0 && !capabilities.presencePenalty) {
      throw LlamaUnsupportedException(
        'WebGPU presence penalty needs bridge assets whose '
        'getCompletionCapabilities() reports presencePenalty; the loaded '
        'assets do not.',
      );
    }
    if (params.minP != 0.0 && !capabilities.minP) {
      throw LlamaUnsupportedException(
        'WebGPU Min-P needs bridge assets whose getCompletionCapabilities() '
        'reports minP; the loaded assets do not, so GenerationParams.minP '
        'must be 0.0.',
      );
    }
    final thinkingBudget = params.thinkingBudget;
    if (thinkingBudget is ResolvedThinkingBudget &&
        (!capabilities.thinkingBudgetMultiEnd ||
            !capabilities.thinkingBudget)) {
      throw LlamaUnsupportedException(webGpuThinkingBudgetMultiEndRequired);
    }
    if (thinkingBudget != null && !capabilities.thinkingBudget) {
      throw LlamaUnsupportedException(
        'WebGPU thinking-budget control needs bridge assets v0.1.54+ whose '
        'getCompletionCapabilities() reports thinkingBudget; the loaded '
        'assets do not.',
      );
    }
    final grammar = params.grammar;
    final keepGrammarApplied =
        thinkingBudget != null &&
        grammar != null &&
        !params.grammarLazy &&
        ToolCallGrammarUtils.keepsAppliedThroughThought(grammar);
    if (keepGrammarApplied && !capabilities.thinkingBudgetPauseGrammar) {
      throw LlamaUnsupportedException(
        'WebGPU thinking-budget control with an eager grammar rooted at '
        'think-body or seed-thought needs bridge assets v0.1.84+ whose '
        'getCompletionCapabilities() reports thinkingBudgetPauseGrammar; '
        'the loaded core pauses every grammar while the model reasons, so '
        'the reply would not be constrained.',
      );
    }
    final speculativeConfig = params.resolvedSpeculativeDecodingConfig;
    if (speculativeConfig != null) {
      requireWebGpuSpeculativeSupport(
        speculativeConfig,
        capabilities.speculativeDecoding,
      );
    }
    if (params.grammarLazy && !capabilities.lazyGrammar) {
      throw LlamaUnsupportedException(
        'WebGPU GenerationParams.grammarLazy requires bridge assets '
        'v0.1.75+ whose getCompletionCapabilities() reports lazyGrammar; '
        'the loaded core does not.',
      );
    }
    if (params.grammarRoot != const GenerationParams().grammarRoot &&
        !capabilities.lazyGrammar) {
      throw LlamaUnsupportedException(
        'WebGPU GenerationParams.grammarRoot other than "root" requires '
        'bridge assets v0.1.75+ whose getCompletionCapabilities() reports '
        'lazyGrammar; the loaded core does not.',
      );
    }
    final grammarTriggers = params.grammarLazy
        ? _bridgeGrammarTriggers(params.grammarTriggers)
        : null;

    if (countPromptTokensInPenalties &&
        (parts?.any(
              (part) =>
                  part is LlamaImageContent ||
                  part is LlamaAudioContent ||
                  part is LlamaVideoContent,
            ) ??
            false)) {
      throw LlamaUnsupportedException(
        'Web prompt penalties with grammar currently support text-only prompts.',
      );
    }
    final mediaParts = _buildMultimodalParts(parts);
    if (mediaParts != null && !_mmContextActive) {
      throw LlamaUnsupportedException(
        'Media input needs a multimodal projector on WebGPU, and none is '
        'loaded. Load the model with LlamaModel(source, projector: ...) '
        'before sending image or audio parts.',
      );
    }
    final bridgeThinkingBudget = thinkingBudget == null
        ? null
        : _bridgeThinkingBudget(
            thinkingBudget,
            params,
            hasMediaParts: mediaParts != null,
            pauseGrammar: !keepGrammarApplied,
          );
    final speculative = resolveWebGpuSpeculativeRequest(
      params,
      hasMediaParts: mediaParts != null,
    );

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

    final generationAbort = _GenerationAbort();
    final abortController = generationAbort.controller;
    late final StreamController<List<int>> controller;
    late final Stream<List<int>> generation;
    LlamaGenerationUsage? reportedUsage;
    var reportedLength = false;
    var failed = false;
    var canceledByCaller = false;
    controller = StreamController<List<int>>(
      onCancel: () {
        if (controller.isClosed) {
          return null;
        }
        canceledByCaller = true;
        if (identical(_generationAbort, generationAbort)) {
          _generationAbort = null;
        }
        // The signal names this request; cancel() could stop another request
        // that owns the bridge while this completion is still queued.
        abortController.abort();
        if (!controller.isClosed) {
          return controller.close();
        }
        return null;
      },
    );
    generation = controller.stream;
    _generationAbort = generationAbort;
    var emittedLength = 0;
    var latestText = '';
    var stoppedBySequence = false;
    final preservedTokens = params.preservedTokens.toSet();
    final stopSequences = params.stopSequences
        .where((stop) => stop.isNotEmpty && !preservedTokens.contains(stop))
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
    final emittedOutputBytes = hasStopSequences ? null : <int>[];

    void emitBytes(List<int> bytes) {
      if (bytes.isEmpty || controller.isClosed) {
        return;
      }
      emittedOutputBytes?.addAll(bytes);
      controller.add(bytes);
    }

    void emitText(String text) {
      emitBytes(utf8.encode(text));
    }

    void releaseHeldBackText() {
      if (latestText.length > emittedLength) {
        emitText(latestText.substring(emittedLength));
        emittedLength = latestText.length;
      }
    }

    bool emittedBytesArePrefixOf(List<int> bytes) {
      final emittedBytes = emittedOutputBytes;
      if (emittedBytes == null || emittedBytes.length > bytes.length) {
        return false;
      }
      for (int index = 0; index < emittedBytes.length; index++) {
        if (emittedBytes[index] != bytes[index]) {
          return false;
        }
      }
      return true;
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

      emitBytes(bytes);
    }.toJS;

    final options = WebGpuCompletionOptions(
      nPredict: params.maxTokens,
      mediaMaxPredict: mediaMaxPredict,
      temp: params.temp,
      topK: params.topK,
      topP: params.topP,
      minP: params.minP == 0.0 ? null : params.minP,
      penalty: params.penalty,
      presencePenalty: params.presencePenalty == 0.0
          ? null
          : params.presencePenalty,
      seed: params.seed ?? DateTime.now().millisecondsSinceEpoch,
      grammar: params.grammar,
      grammarLazy: capabilities.lazyGrammar ? params.grammarLazy : null,
      grammarRoot: capabilities.lazyGrammar ? params.grammarRoot : null,
      grammarTriggers: grammarTriggers,
      thinkingBudget: bridgeThinkingBudget,
      speculativeDecoding: speculative?.options,
      mediaMaxImagePixels: mediaMaxImagePixels,
      mediaMaxImageEdge: mediaMaxImageEdge,
      onToken: onToken as JSFunction,
      onUsage: _bridgeSupportsCompletionUsage(bridge)
          ? ((JSAny? usage) {
              reportedUsage = _generationUsageFromJs(usage);
              // Usage counts cannot distinguish nPredict, context exhaustion
              // and the bridge's media cap. Trust only the explicit reason.
              reportedLength =
                  usage.isA<JSObject>() &&
                  _jsStringProperty(usage as JSObject, 'finishReason') ==
                      'length';
            }).toJS
          : null,
      emitCurrentTextOnToken: hasStopSequences,
      tokenEventEncoding: 'bytes',
      tokenEventFlushMs: tokenEventFlushMs,
      tokenEventFlushChars: tokenEventFlushChars,
      parts: mediaParts,
      signal: abortController.signal,
    );
    if (countPromptTokensInPenalties) {
      options.penaltyPromptTokensWithGrammar = true;
    }
    // A core without the capability never counts the prompt, so there the
    // mark needs no option.
    if (capabilities.penaltyPromptTokens &&
        isPromptExcludedFromPenalties(params)) {
      options.penaltyPromptTokens = false;
    }

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
          final draftModelUrl = speculative?.draftModelUrl;
          if (draftModelUrl != null) {
            try {
              await _draftModel.prepare(
                bridge,
                draftModelUrl,
                speculative!.draftStrategy!,
                signal: abortController.signal,
              );
            } on Object {
              if (abortController.signal.aborted) return;
              rethrow;
            }
          }
          // The bridge rejects an already-aborted signal with an AbortError
          // (v0.1.36 ignored it on its worker path), so end the stream here
          // without starting the generation.
          if (abortController.signal.aborted) {
            return;
          }
          final normalizedPrompt = _normalizePromptForBridge(prompt, bridge);
          final completion = bridge.createCompletion(normalizedPrompt, options);
          final completionResult = await _toFuture(completion);

          if (hasStopSequences && !stoppedBySequence) {
            releaseHeldBackText();
          } else if (!hasStopSequences) {
            final emittedBytes = emittedOutputBytes!;
            final completionText = _jsValueAsString(completionResult);
            final finalBytes = utf8.encode(completionText ?? '');
            if (emittedBytesArePrefixOf(finalBytes) &&
                emittedBytes.length < finalBytes.length) {
              emitBytes(finalBytes.sublist(emittedBytes.length));
            }
          }
        } catch (e, st) {
          if (generationAbort.cancelRequested && _isAbortError(e)) {
            // The worker path of the bridge rejects with an AbortError once
            // cancelGeneration aborts the signal, where the direct path and
            // native llama.cpp end normally with the text held back for stop
            // sequences.
            if (!stoppedBySequence) releaseHeldBackText();
          } else if (!stoppedBySequence &&
              !canceledByCaller &&
              !controller.isClosed) {
            failed = true;
            controller.addError(
              speculative == null
                  ? webGpuBridgeRequestError(e) ??
                        LlamaInferenceException(
                          'WebGPU generation failed.',
                          webGpuBridgeErrorText(e),
                        )
                  : webGpuSpeculativeCompletionError(e, speculative.sourceUrls),
              st,
            );
          }
        } finally {
          if (identical(_generationAbort, generationAbort)) {
            _generationAbort = null;
          }
          if (!failed && reportedUsage != null) {
            _generationUsages[generation] = reportedUsage;
          }
          if (!failed &&
              reportedLength &&
              !stoppedBySequence &&
              !canceledByCaller &&
              !abortController.signal.aborted) {
            _generationLimits[generation] = BackendGenerationLimit.runtime;
          }
          if (!controller.isClosed) {
            await controller.close();
          }
        }
      }),
    );

    return generation;
  }

  // The bridge accepts names, not Dart's word/token wire integers.
  JSArray<WebGpuGrammarTrigger> _bridgeGrammarTriggers(
    List<GenerationGrammarTrigger> triggers,
  ) {
    return triggers
        .map((trigger) {
          switch (trigger.triggerType) {
            case GrammarTriggerType.word:
              return WebGpuGrammarTrigger(type: 'word', value: trigger.value);
            case GrammarTriggerType.token:
              final token = trigger.token ?? int.tryParse(trigger.value);
              if (token == null || token < 0 || token > _maxInt32) {
                throw LlamaArgumentException(
                  'Web lazy-grammar token triggers need an integer token id '
                  'from 0 to $_maxInt32 in token or value.',
                );
              }
              return WebGpuGrammarTrigger(type: 'token', token: token);
            case GrammarTriggerType.pattern:
              return WebGpuGrammarTrigger(
                type: 'pattern',
                value: trigger.value,
              );
            case GrammarTriggerType.patternFull:
              // Native interprets the empty whole-output pattern as ^$.
              return WebGpuGrammarTrigger(
                type: 'pattern-full',
                value: trigger.value.isEmpty ? r'^$' : trigger.value,
              );
          }
        })
        .toList(growable: false)
        .toJS;
  }

  /// Validates [budget] as native llama.cpp generation does and converts it
  /// for the bridge.
  WebGpuThinkingBudgetOptions _bridgeThinkingBudget(
    ThinkingBudget budget,
    GenerationParams params, {
    required bool hasMediaParts,
    required bool pauseGrammar,
  }) {
    if (budget.maxTokens < 0 || budget.maxTokens > _maxThinkingBudgetTokens) {
      throw RangeError.range(
        budget.maxTokens,
        0,
        _maxThinkingBudgetTokens,
        'thinkingBudget.maxTokens',
        'must fit the signed 32-bit llama.cpp reasoning-budget limit',
      );
    }
    if (hasMediaParts) {
      throw LlamaUnsupportedException(
        'WebGPU thinking-budget control supports text-only generation: the '
        'bridge inspects the prompt tokens to find an open reasoning block.',
      );
    }
    final startTag = budget.startTag;
    final endTag = budget.endTag;
    if (startTag == null ||
        startTag.trim().isEmpty ||
        endTag == null ||
        endTag.trim().isEmpty) {
      throw ArgumentError(
        'GenerationParams.thinkingBudget requires non-empty startTag and '
        'endTag for raw generation. LlamaEngine.create fills them from the '
        'selected chat template automatically.',
      );
    }
    final options = WebGpuThinkingBudgetOptions(
      maxTokens: budget.maxTokens,
      startTag: startTag,
      endTag: endTag,
      forcedMessage: budget.forcedMessage ?? '',
    );
    if (budget is ResolvedThinkingBudget) {
      options.naturalEndTags = budget.naturalEndTags
          .map((tag) => tag.toJS)
          .toList(growable: false)
          .toJS;
      final replayIndex = budget.replayEndIndexFor(params);
      if (pauseGrammar && replayIndex != null) {
        options.grammarReplayEndIndex = replayIndex;
      }
    }
    // Sent only to keep a grammar applied, so every other request is
    // unchanged on the wire.
    if (!pauseGrammar) options.pauseGrammar = false;
    return options;
  }

  @override
  void cancelGeneration() {
    _embeddingCancelEpoch++;
    final generationAbort = _generationAbort;
    if (generationAbort != null) {
      generationAbort.cancelRequested = true;
      generationAbort.controller.abort();
    }
    _bridge?.cancel();
  }

  @override
  LlamaGenerationUsage? generationUsageOf(Stream<List<int>> generation) =>
      _generationUsages[generation];

  @override
  BackendGenerationLimit? generationLimitOf(Stream<List<int>> generation) =>
      _generationLimits[generation];

  @override
  Future<String?> textToSpeechModelUnsupportedReason(
    BackendTextToSpeechModel model,
  ) async => webTextToSpeechModelUnsupportedReason(model);

  @override
  Future<BackendTextToSpeechCapabilities> textToSpeechCapabilities(
    int contextHandle,
    int mmContextHandle,
  ) async {
    final bridge = _requireBridge();
    webGpuThrowIfModelUnloaded(bridge);
    if (!_mmContextActive) {
      return const BackendTextToSpeechCapabilities(
        isSupported: false,
        unsupportedReason: 'Load a text-to-speech multimodal projector first.',
      );
    }
    if (!_hasBridgeFunction(bridge, 'getTextToSpeechCapabilities') ||
        !_hasBridgeFunction(bridge, 'synthesizeSpeech')) {
      return const BackendTextToSpeechCapabilities(
        isSupported: false,
        unsupportedReason:
            'Web text-to-speech requires llama-web-bridge-assets v0.1.33 '
            'or newer.',
      );
    }

    try {
      final raw = await _toFuture(bridge.getTextToSpeechCapabilities());
      webGpuThrowIfModelUnloaded(bridge);
      if (raw == null || !raw.isA<JSObject>()) {
        return const BackendTextToSpeechCapabilities(
          isSupported: false,
          unsupportedReason:
              'The Web text-to-speech capability response is invalid.',
        );
      }
      final value = raw as JSObject;
      final apiVersion = _jsIntProperty(value, 'apiVersion') ?? 0;
      if (apiVersion != 1) {
        return BackendTextToSpeechCapabilities(
          isSupported: false,
          unsupportedReason:
              'The Web text-to-speech API version is unsupported '
              '(received $apiVersion, expected 1).',
        );
      }
      if (_jsBoolProperty(value, 'supported') != true) {
        return BackendTextToSpeechCapabilities(
          isSupported: false,
          unsupportedReason:
              _jsStringProperty(value, 'reason') ??
              'The loaded Web model/projector does not support text-to-speech.',
        );
      }
      if (_jsIntProperty(value, 'modelType') != 1) {
        return const BackendTextToSpeechCapabilities(
          isSupported: false,
          unsupportedReason:
              'The loaded Web projector is not a supported Qwen3-TTS '
              'projector. Web text-to-speech drives Qwen3-TTS only.',
        );
      }
      final sampleRate = _jsIntProperty(value, 'sampleRate');
      final channels = _jsIntProperty(value, 'channels');
      if (sampleRate == null ||
          sampleRate <= 0 ||
          channels == null ||
          channels <= 0) {
        return const BackendTextToSpeechCapabilities(
          isSupported: false,
          unsupportedReason:
              'The Web text-to-speech runtime reported an invalid audio '
              'format.',
        );
      }
      return BackendTextToSpeechCapabilities(
        isSupported: true,
        model: BackendTextToSpeechModel.qwen3Tts,
        sampleRateHz: sampleRate,
        channelCount: channels,
        supportsLanguage: _jsBoolProperty(value, 'supportsLanguage') == true,
        supportsSpeakerReference:
            _jsBoolProperty(value, 'supportsSpeakerReference') == true,
        supportsCancellation: true,
        incrementalAudioUnsupportedReason: _webTtsStreamingUnsupportedReason,
      );
    } on LlamaModelUnloadedException {
      rethrow;
    } catch (error) {
      return BackendTextToSpeechCapabilities(
        isSupported: false,
        unsupportedReason:
            'The Web text-to-speech capability probe failed: $error',
      );
    }
  }

  @override
  Future<BackendTextToSpeechResult> synthesizeTextToSpeech(
    int contextHandle,
    int mmContextHandle,
    BackendTextToSpeechRequest request, {
    void Function(BackendTextToSpeechProgress progress)? onProgress,
  }) async {
    if (request.streamAudio) {
      throw LlamaUnsupportedException(_webTtsStreamingUnsupportedReason);
    }
    if (request.speakerAudioPath != null) {
      throw LlamaUnsupportedException(
        'Web text-to-speech speaker references require encoded bytes; '
        'browser runtimes cannot read local file paths.',
      );
    }
    if (_textToSpeechAbortController != null) {
      throw LlamaStateException(
        'Text-to-speech synthesis is already active in this Web runtime.',
      );
    }

    // Claimed before the first await so a cancel arriving during the
    // capability probe aborts this synthesis instead of being dropped.
    final abortController = AbortController();
    _textToSpeechAbortController = abortController;
    try {
      final bridge = _requireBridge();
      final capabilities = await textToSpeechCapabilities(
        contextHandle,
        mmContextHandle,
      );
      if (!capabilities.isSupported) {
        throw LlamaUnsupportedException(
          capabilities.unsupportedReason ??
              'Web text-to-speech is not supported by the active runtime.',
        );
      }
      if (abortController.signal.aborted) {
        throw LlamaTextToSpeechException(
          'Text-to-speech synthesis was cancelled.',
        );
      }

      final onProgressCallback = (JSAny? raw) {
        if (raw == null || !raw.isA<JSObject>()) {
          return;
        }
        final value = raw as JSObject;
        onProgress?.call(
          BackendTextToSpeechProgress(
            phase: _jsIntProperty(value, 'state') == 1
                ? BackendTextToSpeechPhase.processingPrompt
                : BackendTextToSpeechPhase.generating,
            promptTokensRemaining:
                _jsIntProperty(value, 'promptTokensRemaining') ?? 0,
            framesGenerated: _jsIntProperty(value, 'framesGenerated') ?? 0,
            truncated: _jsBoolProperty(value, 'truncated') == true,
          ),
        );
      }.toJS;

      final raw = await _toFuture(
        bridge.synthesizeSpeech(
          WebGpuTextToSpeechOptions(
            text: request.text,
            language: request.language,
            speakerAudio: request.speakerAudioBytes?.toJS,
            promptBatchSize: request.promptBatchSize,
            maxFrames: request.maxFrames,
            topK: request.topK,
            topP: request.topP,
            minP: request.minP,
            temperature: request.temperature,
            seed: request.seed,
            signal: abortController.signal,
            onProgress: onProgressCallback as JSFunction,
          ),
        ),
      );
      if (raw == null || !raw.isA<JSObject>()) {
        throw LlamaTextToSpeechException(
          'The Web text-to-speech runtime returned an invalid result.',
        );
      }
      final value = raw as JSObject;
      final rawPcm = value.getProperty('pcm'.toJS);
      if (!rawPcm.isA<JSFloat32Array>()) {
        throw LlamaTextToSpeechException(
          'The Web text-to-speech runtime returned invalid PCM audio.',
        );
      }
      final samples = (rawPcm as JSFloat32Array).toDart;
      final sampleRate = _jsIntProperty(value, 'sampleRate') ?? 0;
      final channels = _jsIntProperty(value, 'channels') ?? 0;
      if (samples.isEmpty || sampleRate <= 0 || channels <= 0) {
        throw LlamaTextToSpeechException(
          'The Web text-to-speech runtime returned empty or malformed audio.',
        );
      }
      return BackendTextToSpeechResult(
        samples: samples,
        sampleRateHz: sampleRate,
        channelCount: channels,
        framesGenerated: _jsIntProperty(value, 'framesGenerated') ?? 0,
        truncated: _jsBoolProperty(value, 'truncated') == true,
      );
    } catch (error) {
      if (abortController.signal.aborted) {
        throw LlamaTextToSpeechException(
          'Text-to-speech synthesis was cancelled.',
          error,
        );
      }
      if (error is LlamaException) {
        rethrow;
      }
      throw LlamaTextToSpeechException(
        'Web text-to-speech synthesis failed.',
        error,
      );
    } finally {
      if (identical(_textToSpeechAbortController, abortController)) {
        _textToSpeechAbortController = null;
      }
    }
  }

  @override
  void cancelTextToSpeech() {
    final controller = _textToSpeechAbortController;
    if (controller == null) {
      return;
    }
    // Startup can still be awaiting a queued capability probe while another
    // operation owns the bridge; its global cancel would stop that operation.
    controller.abort();
  }

  /// Reports the options that the loaded bridge assets'
  /// `getCompletionCapabilities()` reported after the model load; none before
  /// a load or when the probe is missing or failed. Every bridge applies
  /// [GenerationParams.penalty] to a loaded model and ignores the stream
  /// batching thresholds.
  ///
  /// Speculative strategies follow [webGpuSpeculativeStrategiesFrom]: a
  /// draft-model strategy counts when the assets have `loadDraftModel()`,
  /// since generation loads the draft.
  @override
  Future<BackendGenerationCapabilities> generationCapabilities() async {
    final capabilities = _completionCapabilities;
    return BackendGenerationCapabilities(
      penalty: _isReady,
      presencePenalty: capabilities.presencePenalty,
      minP: capabilities.minP,
      thinkingBudget: capabilities.thinkingBudget,
      speculativeDecodingStrategies: capabilities.speculativeDecoding,
    );
  }

  /// Probes the active bridge for decision heads.
  ///
  /// Reports unsupported without an active bridge, and for bridge assets
  /// without the decision API or with a decision API version other than 1.
  @override
  Future<BackendDecisionCapabilities> decisionCapabilities(int modelHandle) {
    return _decisionHeads.capabilities(_activeBridge);
  }

  /// Loads a decision head into the active bridge.
  ///
  /// [headPath] and [configPath] are URLs that resolve against the document
  /// base URL. The config is fetched here and passed to the bridge as text;
  /// the bridge fetches the head.
  @override
  Future<BackendDecisionHeadInfo> decisionHeadLoad(
    int modelHandle,
    String headPath, {
    String? configPath,
  }) {
    return _decisionHeads.load(_activeBridge, headPath, configUrl: configPath);
  }

  @override
  Future<List<BackendDecisionOutput>> decisionRun(
    int headHandle,
    List<BackendDecisionSequence> sequences,
  ) {
    return _decisionHeads.run(_activeBridge, headHandle, sequences);
  }

  @override
  Future<void> decisionHeadFree(int headHandle) {
    return _decisionHeads.free(_activeBridge, headHandle);
  }

  LlamaWebGpuBridge? get _activeBridge => _usingBridge ? _bridge : null;

  static const String _mediaEmbeddingRequirement =
      'Web media embeddings require llama-web-bridge-assets v0.1.64+ '
      'with embedding capability API version 1 and a compatible loaded '
      'embedding model/projector.';

  @override
  Future<LlamaEmbeddingCapabilities> getEmbeddingCapabilities(
    int contextHandle,
  ) async {
    if (!_isReady || _activeBridge == null || contextHandle != 1) {
      return const LlamaEmbeddingCapabilities();
    }
    const legacy = LlamaEmbeddingCapabilities(
      text: true,
      mediaUnsupportedReason: _mediaEmbeddingRequirement,
    );
    final bridge = _bridge!;
    webGpuThrowIfModelUnloaded(bridge);
    final epoch = _embeddingCancelEpoch;
    void checkCancelled() {
      if (!identical(bridge, _activeBridge) || epoch != _embeddingCancelEpoch) {
        throw LlamaInferenceException('Web embedding operation was cancelled.');
      }
    }

    final JSAny? value;
    try {
      // A missing facade method is an old asset, not a runtime failure.
      if (!bridge
          .getProperty<JSAny?>('getEmbeddingCapabilities'.toJS)
          .isA<JSFunction>()) {
        return legacy;
      }
      value = await bridge.getEmbeddingCapabilities()?.toDart;
    } catch (error) {
      checkCancelled();
      final code = _embeddingBridgeCode(error);
      final message = webGpuBridgeErrorText(error);
      if (code == 'EMBEDDING_CAPABILITY_UNAVAILABLE' ||
          message == 'bridge[method] is not a function') {
        return legacy;
      }
      throw _mediaEmbeddingError(error);
    }
    checkCancelled();
    webGpuThrowIfModelUnloaded(bridge);
    if (!value.isA<JSObject>()) return legacy;
    final object = value as JSObject;
    final version = object.getProperty<JSAny?>('apiVersion'.toJS)?.dartify();
    final text = object.getProperty<JSAny?>('text'.toJS)?.dartify();
    final image = object.getProperty<JSAny?>('image'.toJS)?.dartify();
    final audio = object.getProperty<JSAny?>('audio'.toJS)?.dartify();
    if (version != 1 || text is! bool || image is! bool || audio is! bool) {
      return legacy;
    }
    final missing = [if (!image) 'image', if (!audio) 'audio'];
    return LlamaEmbeddingCapabilities(
      // The probe's text flag means pooled parts, excluding legacy last-token
      // embeddings on pooling NONE. Only its media flags govern content support.
      text: legacy.text,
      image: image,
      audio: audio,
      mediaUnsupportedReason: missing.isEmpty
          ? null
          : 'The loaded Web model/projector lacks ${missing.join(' and ')} '
                'embedding support (compatible pooling and modality encoder required).',
    );
  }

  @override
  Future<List<List<double>>> embedContentBatch(
    int contextHandle,
    List<LlamaEmbeddingInput> inputs, {
    bool normalize = true,
  }) async {
    if (inputs.isEmpty) return const <List<double>>[];
    final bridge = _requireBridge();
    final epoch = _embeddingCancelEpoch;
    void checkCancelled() {
      if (!identical(bridge, _activeBridge) || epoch != _embeddingCancelEpoch) {
        throw LlamaInferenceException('Web embedding operation was cancelled.');
      }
    }

    final snapshot = List<LlamaEmbeddingInput>.of(inputs);
    final mapped = snapshot.map(_embeddingInput).toList(growable: false);
    final capabilities = await getEmbeddingCapabilities(contextHandle);
    checkCancelled();
    for (final input in snapshot) {
      for (final kind in input.partKinds) {
        if (!capabilities.supports(kind)) {
          throw LlamaUnsupportedException(
            '${kind.name} embeddings are unavailable. ${capabilities.mediaUnsupportedReason}',
          );
        }
      }
    }
    if (snapshot.every(
      (input) =>
          input.partKinds.every((kind) => kind == LlamaEmbeddingModality.text),
    )) {
      final result = await embedBatch(contextHandle, [
        for (final input in snapshot)
          input.parts.cast<LlamaTextContent>().map((part) => part.text).join(),
      ], normalize: normalize);
      checkCancelled();
      return result;
    }
    try {
      final result = await _toFuture(
        bridge.embedBatch(
          mapped.toJS,
          WebGpuEmbeddingOptions(normalize: normalize),
        ),
      );
      checkCancelled();
      return _parseEmbeddingBatch(result);
    } catch (error) {
      throw _mediaEmbeddingError(error);
    }
  }

  JSAny _embeddingInput(LlamaEmbeddingInput input) {
    if (input.parts.every((part) => part is LlamaTextContent)) {
      return input.parts
          .cast<LlamaTextContent>()
          .map((part) => part.text)
          .join()
          .toJS;
    }
    final parts = <JSObject>[];
    for (var index = 0; index < input.parts.length; index++) {
      final object = JSObject();
      switch (input.partKinds[index]) {
        case LlamaEmbeddingModality.text:
          final part = input.parts[index] as LlamaTextContent;
          if (parts.isNotEmpty &&
              parts.last.getProperty<JSString>('type'.toJS).toDart == 'text') {
            final previous = parts.last
                .getProperty<JSString>('text'.toJS)
                .toDart;
            parts.last.setProperty('text'.toJS, (previous + part.text).toJS);
            continue;
          }
          object.setProperty('type'.toJS, 'text'.toJS);
          object.setProperty('text'.toJS, part.text.toJS);
        case LlamaEmbeddingModality.image:
          final part = input.parts[index] as LlamaImageContent;
          if (part.path != null || part.url != null) {
            throw LlamaUnsupportedException(
              'Web image embeddings require bytes; filesystem paths and image URLs are unsupported.',
            );
          }
          object.setProperty('type'.toJS, 'image'.toJS);
          // Dimensions would make the bridge infer raw RGB when encoded byte
          // length happens to match, violating LlamaImageContent.bytes.
          object.setProperty('bytes'.toJS, part.bytes?.toJS);
        case LlamaEmbeddingModality.audio:
          final part = input.parts[index] as LlamaAudioContent;
          if (part.path != null) {
            throw LlamaUnsupportedException(
              'Web audio embeddings require encoded bytes or mono 16 kHz PCM; filesystem paths are unsupported.',
            );
          }
          object.setProperty('type'.toJS, 'audio'.toJS);
          object.setProperty('bytes'.toJS, part.bytes?.toJS);
          object.setProperty('samples'.toJS, part.samples?.toJS);
      }
      parts.add(object);
    }
    for (final part in parts) {
      if (part.getProperty<JSString>('type'.toJS).toDart == 'text' &&
          part
              .getProperty<JSString>('text'.toJS)
              .toDart
              .contains('<__media__>')) {
        throw LlamaUnsupportedException(
          'Embedding text contains the reserved native media marker.',
        );
      }
    }
    return parts.toJS;
  }

  static String? _embeddingBridgeCode(Object error) {
    try {
      final value = (error as JSObject).getProperty<JSAny?>('code'.toJS);
      if (value.isA<JSString>()) return (value as JSString).toDart;
    } catch (_) {
      // Primitive and Dart rejections carry no bridge error code.
    }
    return null;
  }

  static LlamaException _mediaEmbeddingError(Object error) {
    final unloaded = webGpuModelUnloadedError(error);
    if (unloaded != null) return unloaded;
    final code = _embeddingBridgeCode(error);
    // Only known stable codes cross this boundary; diagnostics may carry media,
    // paths or URLs. Unknown codes are untrusted input too.
    const knownCodes = {
      'INVALID_EMBEDDING_INPUT',
      'EMBEDDING_CAPABILITY_UNAVAILABLE',
      'MODEL_NOT_EMBEDDING',
      'EMBEDDING_PROJECTOR_MISSING',
      'EMBEDDING_MODALITY_UNSUPPORTED',
      'EMBEDDING_INPUT_TOO_LARGE',
      'EMBEDDING_FAILED',
      'aborted',
    };
    final message = webGpuBridgeErrorText(error).toLowerCase();
    final stableCode = knownCodes.contains(code)
        ? ' ($code)'
        : message.startsWith('runtimeerror: aborted(') ||
              message.startsWith('aborted(')
        ? ' (aborted)'
        : '';
    return switch (code) {
      'INVALID_EMBEDDING_INPUT' => LlamaArgumentException(
        'Web embedding input is invalid$stableCode; check media sources and part shapes.',
      ),
      'EMBEDDING_CAPABILITY_UNAVAILABLE' => LlamaUnsupportedException(
        '$_mediaEmbeddingRequirement$stableCode',
      ),
      'MODEL_NOT_EMBEDDING' ||
      'EMBEDDING_PROJECTOR_MISSING' ||
      'EMBEDDING_MODALITY_UNSUPPORTED' => LlamaUnsupportedException(
        'The loaded Web model/projector lacks the requested embedding capability$stableCode.',
      ),
      _ => LlamaInferenceException(
        'The Web runtime could not compute media embeddings$stableCode; the operation '
        'may have been cancelled or exceeded the allocated input capacity.',
      ),
    };
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
        bridge.embed(text.toJS, WebGpuEmbeddingOptions(normalize: normalize)),
      );
      return _parseEmbeddingVector(result);
    } catch (error) {
      if (_isEmbeddingMethodUnavailableError(error)) {
        throw UnsupportedError(
          'Web embeddings require bridge assets with embedding support '
          '(v0.1.7 or newer).',
        );
      }
      throw _embeddingError(error);
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
      throw _embeddingError(error);
    }
  }

  // The string embed path has no stable error code, so the v0.1.73+ rejections
  // (llama-web-bridge#194) are matched on the core's exact message.
  static final RegExp _rankPooledEmbedding = RegExp(
    r'^Embedding generation failed: Embeddings are not supported for '
    r'rank-pooled models such as rerankers: ',
  );
  static final RegExp _embeddingPassTooLong = RegExp(
    r'^Embedding generation failed: The embedding input has (\d+) tokens, '
    r'but this model embeds its input in one pass of at most (\d+) tokens '
    r'\(n_ubatch\)\.',
  );

  static LlamaException _embeddingError(Object error) {
    final requestError = webGpuBridgeRequestError(error);
    if (requestError != null) return requestError;
    final message = webGpuBridgeErrorText(error);
    if (_rankPooledEmbedding.hasMatch(message)) {
      return LlamaUnsupportedException(
        'Embeddings are not supported for rank-pooled models such as '
        'rerankers: llama.cpp returns classifier scores, not an embedding, '
        'for pooling type RANK. Reranking is tracked in '
        'https://github.com/leehack/llamadart/issues/323.',
      );
    }
    final tooLong = _embeddingPassTooLong.firstMatch(message);
    final actualTokens = int.tryParse(tooLong?.group(1) ?? '');
    final maxInputTokens = int.tryParse(tooLong?.group(2) ?? '');
    if (actualTokens != null && maxInputTokens != null && maxInputTokens > 0) {
      return LlamaEmbeddingInputTooLongException(
        'The embedding input has $actualTokens tokens, but this model '
        'embeds its input in one pass of at most $maxInputTokens tokens '
        '(n_ubatch). Shorten the input or raise ModelParams.microBatchSize '
        'and ModelParams.batchSize.',
        maxInputTokens: maxInputTokens,
        actualTokens: actualTokens,
      );
    }
    return LlamaInferenceException(
      'The Web runtime could not compute embeddings.',
      message,
    );
  }

  @override
  Future<LlamaNextTokenScores> scoreNextToken(
    int contextHandle,
    String prompt, {
    required List<int> candidates,
    required int topK,
    required bool reusePromptPrefix,
  }) async {
    final bridge = _requireBridge();
    if (!supportsNextTokenScoring) {
      throw UnsupportedError(_nextTokenScoringUnsupportedMessage);
    }
    for (final token in candidates) {
      RangeError.checkValueInInterval(token, 0, _maxInt32, 'candidates');
    }
    RangeError.checkValueInInterval(topK, 0, _maxInt32, 'topK');
    final JSAny? result;
    try {
      result = await _toFuture(
        bridge.scoreNextToken(
          _normalizePromptForBridge(prompt, bridge),
          WebGpuNextTokenScoreOptions(
            candidates: candidates.map((token) => token.toJS).toList().toJS,
            topK: topK,
            reusePromptPrefix: reusePromptPrefix,
          ),
        ),
      );
    } catch (error) {
      final classified = webGpuBridgeRequestError(error);
      if (classified != null) throw classified;
      final message = _errorMessage(error);
      if (message.contains('is outside the vocabulary')) {
        throw RangeError(message);
      }
      if (message.contains('needs a decoder-only model')) {
        throw LlamaUnsupportedException(message);
      }
      throw LlamaInferenceException(
        'The Web runtime could not score the next token.',
        webGpuBridgeErrorText(error),
      );
    }
    if (result == null || !result.isA<JSObject>()) {
      throw LlamaInferenceException(
        'The Web bridge returned no next-token scores.',
      );
    }
    final scores = result as JSObject;
    final promptTokens = scores.getProperty<JSAny?>('promptTokens'.toJS);
    return LlamaNextTokenScores(
      candidates: _parseTokenLogprobs(scores.getProperty('candidates'.toJS)),
      top: _parseTokenLogprobs(scores.getProperty('top'.toJS)),
      promptTokens: promptTokens.isA<JSNumber>()
          ? (promptTokens as JSNumber).toDartInt
          : 0,
    );
  }

  List<LlamaTokenLogprob> _parseTokenLogprobs(JSAny? value) {
    if (value == null || !value.isA<JSArray>()) {
      return const <LlamaTokenLogprob>[];
    }
    final entries = value as JSArray;
    final out = <LlamaTokenLogprob>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries.getProperty<JSObject>(i.toJS);
      final bytes = entry.getProperty<JSAny?>('bytes'.toJS);
      final logprob = entry.getProperty<JSAny?>('logprob'.toJS);
      out.add(
        LlamaTokenLogprob(
          token: entry.getProperty<JSNumber>('token'.toJS).toDartInt,
          bytes: bytes.isA<JSUint8Array>()
              ? (bytes as JSUint8Array).toDart
              : const <int>[],
          logprob: logprob.isA<JSNumber>()
              ? (logprob as JSNumber).toDartDouble
              : double.negativeInfinity,
        ),
      );
    }
    return out;
  }

  bool _isAbortError(Object error) {
    try {
      final name = (error as JSObject).getProperty<JSAny?>('name'.toJS);
      return name.isA<JSString>() && (name as JSString).toDart == 'AbortError';
    } catch (_) {
      return false;
    }
  }

  String _errorMessage(Object error) {
    JSAny? message;
    try {
      message = (error as JSObject).getProperty<JSAny?>('message'.toJS);
    } catch (_) {
      message = null;
    }
    return message.isA<JSString>()
        ? (message as JSString).toDart
        : error.toString();
  }

  Future<JSAny?> _toFuture(JSAny? value) async {
    if (value == null) {
      return null;
    }

    if (value.isA<JSPromise>()) {
      try {
        return await (value as JSPromise<JSAny?>).toDart;
      } catch (error) {
        final unloaded = webGpuModelUnloadedError(error);
        if (unloaded != null) throw unloaded;
        rethrow;
      }
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
      throw _stateError('save', error, path);
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
      throw _stateError('load', error, path);
    }
  }

  static LlamaStateException _stateError(
    String action,
    Object error,
    String path,
  ) =>
      webGpuModelUnloadedError(error) ??
      LlamaStateException(
        'The Web runtime could not $action the state.',
        webGpuBridgeErrorText(error, sourceUrls: <String>[path]),
      );

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async {
    final bridge = _requireBridge();
    final metadata = bridge.getModelMetadata();
    final out = <String, String>{};
    final assetUrls = _bridgeAssetUrls(
      singleThread: _singleThreadPreflightNotes != null,
    ).toList();
    if (metadata != null) {
      final keys = _objectKeys(metadata);
      for (int i = 0; i < keys.length; i++) {
        final key = (keys.getProperty(i.toJS) as JSString).toDart;
        final value = metadata.getProperty(key.toJS);
        final text = value.isA<JSString>()
            ? (value as JSString).toDart
            : value.isA<JSNumber>()
            ? (value as JSNumber).toDartInt.toString()
            : value.toString();
        out[key] = key.startsWith('llamadart.webgpu.')
            ? webGpuBridgeErrorText(text, sourceUrls: assetUrls)
            : text;
      }
    }

    final preflightNotes = _singleThreadPreflightNotes;
    if (preflightNotes != null) {
      const key = 'llamadart.webgpu.runtime_notes';
      final notes = out[key];
      out[key] = notes == null || notes.isEmpty
          ? preflightNotes
          : '$notes;$preflightNotes';
    }
    return out;
  }

  /// Applies the LoRA adapter at the URL [path] at [scale].
  ///
  /// Needs bridge assets whose `getLoraAdapterCapabilities()` reports support;
  /// see [WebGpuLoraAdapters.set] for the errors.
  @override
  Future<void> setLoraAdapter(int contextHandle, String path, double scale) =>
      _loraAdapters.set(_usingBridge ? _bridge : null, path, scale);

  @override
  Future<void> removeLoraAdapter(int contextHandle, String path) =>
      _loraAdapters.remove(_usingBridge ? _bridge : null, path);

  @override
  Future<void> clearLoraAdapters(int contextHandle) =>
      _loraAdapters.clear(_usingBridge ? _bridge : null);

  @override
  LlamaRuntime get runtime => LlamaRuntime.llamaCpp;

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
    cancelTextToSpeech();
    await _safeDisposeBridge();
  }

  @override
  Future<int?> multimodalContextCreate(
    int modelHandle,
    String mmProjPath,
  ) async {
    final bridge = _requireBridge();
    mmProjPath = webGpuDocumentUrl(mmProjPath);
    final supportsCacheQuery = _supportsModelCacheQuery(bridge);
    final cacheUrl = webGpuPersistentCacheUrl(mmProjPath);
    final cachedBlobUrl = supportsCacheQuery
        ? null
        : await _cachedModelBlobUrlFor(cacheUrl);
    var retainedCachedBlobUrl = false;

    try {
      final JSAny? result;
      try {
        final load = supportsCacheQuery
            ? bridge.loadMultimodalProjector(
                cacheUrl ?? mmProjPath,
                WebGpuProjectorLoadOptions(
                  useCache: cacheUrl != null,
                  cacheName: _defaultModelCacheName,
                ),
              )
            : bridge.loadMultimodalProjector(cachedBlobUrl ?? mmProjPath);
        result = await _toFuture(load);
      } catch (error) {
        final unloaded = webGpuModelUnloadedError(error);
        if (unloaded != null) throw unloaded;
        final stagingError = webGpuModelStagingError(
          error,
          sourceUrls: [mmProjPath],
        );
        if (stagingError != null) throw stagingError;
        throw LlamaModelException(
          'The Web runtime could not load the multimodal projector.',
          webGpuBridgeErrorText(error, sourceUrls: <String>[mmProjPath]),
        );
      }
      final unverifiedStaging = _verifyJsBackedModelStaging(
        bridge,
        projector: true,
      );
      if (unverifiedStaging != null) {
        _mmContextActive = true;
        try {
          await multimodalContextFree(1);
        } catch (_) {
          // Keep the staging mismatch when projector cleanup also fails.
        }
        throw unverifiedStaging;
      }
      _releaseCachedMmProjectorBlobUrl();
      if (cachedBlobUrl != null) {
        _cachedMmProjectorBlobUrl = cachedBlobUrl;
        retainedCachedBlobUrl = true;
      }
      _mmContextActive = true;
      _resetWebGpuMultimodalWarmupState();
      if ((bridge.supportsVision() ?? false) &&
          !await _projectorEmbedsMedia()) {
        await _ensureWebGpuMultimodalWarmup(
          bridge,
          isCpuMultimodalRuntime: _isCpuRuntimeForMultimodal(bridge),
        );
      }

      if (result == null) {
        return 1;
      }

      if (result.isA<JSNumber>()) {
        return (result as JSNumber).toDartInt;
      }

      return 1;
    } finally {
      if (cachedBlobUrl != null && !retainedCachedBlobUrl) {
        URL.revokeObjectURL(cachedBlobUrl);
      }
    }
  }

  // The warmup completion leaves llama.cpp's causal attention enabled, which
  // the bridge reports as media embeddings being unsupported (#1971).
  Future<bool> _projectorEmbedsMedia() async {
    try {
      final capabilities = await getEmbeddingCapabilities(1);
      return capabilities.image || capabilities.audio;
    } catch (_) {
      return false;
    }
  }

  void _releaseCachedMmProjectorBlobUrl() {
    final blobUrl = _cachedMmProjectorBlobUrl;
    _cachedMmProjectorBlobUrl = null;
    if (blobUrl != null) {
      URL.revokeObjectURL(blobUrl);
    }
  }

  bool _supportsModelCacheQuery(LlamaWebGpuBridge bridge) {
    final constructor = bridge.getProperty<JSAny?>('constructor'.toJS);
    if (!constructor.isA<JSObject>()) return false;
    final flag =
        (constructor as WebGpuBridgeConstructor).supportsModelCacheQuery;
    return flag.isA<JSBoolean>() && (flag as JSBoolean).toDart;
  }

  Future<String?> _cachedModelBlobUrlFor(String? sourceUrl) async {
    if (sourceUrl == null) return null;

    try {
      final caches = globalContext.getProperty<JSAny?>('caches'.toJS);
      if (caches == null || !caches.isA<JSObject>()) {
        return null;
      }

      final cache = await window.caches.open(_defaultModelCacheName).toDart;
      final cachedResponse = await cache.match(sourceUrl.toJS).toDart;
      if (cachedResponse == null ||
          !cachedResponse.ok ||
          cachedResponse.status == 204) {
        return null;
      }

      final blob = await cachedResponse.blob().toDart;
      return URL.createObjectURL(blob);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isModelResponseCachedForUrl(
    LlamaWebGpuBridge bridge,
    String? sourceUrl,
  ) async {
    if (sourceUrl == null) return false;

    try {
      if (_supportsModelCacheQuery(bridge)) {
        final hit = await bridge
            .isModelCached(
              sourceUrl,
              WebGpuCacheQueryOptions(cacheName: _defaultModelCacheName),
            )
            .toDart;
        return hit.toDart;
      }
      final caches = globalContext.getProperty<JSAny?>('caches'.toJS);
      if (caches == null || !caches.isA<JSObject>()) {
        return false;
      }

      final cache = await window.caches.open(_defaultModelCacheName).toDart;
      final cachedResponse = await cache.match(sourceUrl.toJS).toDart;
      return cachedResponse != null &&
          cachedResponse.ok &&
          cachedResponse.status != 204;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> multimodalContextFree(int mmContextHandle) async {
    final bridge = _bridge;
    if (bridge == null || !_mmContextActive) {
      _releaseCachedMmProjectorBlobUrl();
      return;
    }

    try {
      await _toFuture(bridge.unloadMultimodalProjector());
    } finally {
      _releaseCachedMmProjectorBlobUrl();
      _mmContextActive = false;
      _resetWebGpuMultimodalWarmupState();
    }
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

    webGpuThrowIfModelUnloaded(bridge);
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

    webGpuThrowIfModelUnloaded(bridge);
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
    if (customTemplate != null || (_chatTemplate?.isNotEmpty ?? false)) {
      throw LlamaUnsupportedException(
        'The WebGPU backend applyChatTemplate cannot render a custom chat '
        'template (customTemplate or ModelParams.chatTemplate): the web '
        'bridge formats messages without Jinja. Use LlamaEngine.chatTemplate '
        'or LlamaEngine.create, which render it in Dart.',
      );
    }
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

/// The abort controller of one generation.
final class _GenerationAbort {
  final AbortController controller = AbortController();

  /// Whether [WebGpuLlamaBackend.cancelGeneration] aborted [controller].
  bool cancelRequested = false;
}
