@JS()
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:web/web.dart';

import '../../core/engine/chat_template_renderer.dart';
import '../../core/engine/engine_observer.dart';
import '../../core/models/chat/content_part.dart';
import '../../core/models/chat/chat_message.dart';
import '../../core/models/chat/completion_chunk.dart';
import '../../core/models/inference/tool_choice.dart';
import '../../core/models/tools/tool_definition.dart';
import '../../core/cache_policy.dart';
import '../../core/exceptions.dart';
import '../../core/models/config/compute_device.dart';
import '../../core/models/config/gpu_backend.dart';
import '../../core/models/config/log_level.dart';
import '../../core/models/inference/generation_params.dart';
import '../../core/models/inference/gpu_layer_count.dart';
import '../../core/models/inference/model_params.dart';
import '../../core/models/inference/model_params_runtime_support.dart';
import '../../core/models/model_format.dart';
import '../../core/url_redaction.dart';
import '../backend.dart';
import '../web/webgpu_adapter_probe.dart';
import 'litert_lm_sampler_params.dart';
import 'litert_lm_templates.dart';

/// Web LiteRT-LM backend for `.litertlm` models.
///
/// This backend wraps the official `@litert-lm/core` browser API. Apps can
/// preload the package and expose `window.LiteRtLmEngine = module.Engine`, or
/// set `window.__llamadartLiteRtLmModuleUrl` to a module URL such as
/// `https://cdn.jsdelivr.net/npm/@litert-lm/core@0.19.0/+esm`.
///
/// [LiteRtLmBackend.withTextHistory] opts into ordered system/user/assistant
/// text and manual tool calling through a probed conversation preface. The
/// original constructor retains single-user-text dispatch and existing
/// subclass generation overrides. Media, custom templates and explicit
/// thinking/template controls are unavailable. Raw [generate] sends one user
/// text.
class LiteRtLmBackend
    implements
        BackendRuntimeIdentity,
        BackendModelFormatRouting,
        LlamaBackend,
        BackendAvailability,
        BackendChatScope,
        BackendGenerationLimitSupport,
        BackendGrammarConstraintsSupport,
        BackendEmbeddings,
        BackendEmbeddingsSupport,
        BackendStatePersistence,
        BackendStatePersistenceSupport {
  static const Duration _engineReadyTimeout = Duration(seconds: 12);
  static const Duration _enginePollInterval = Duration(milliseconds: 100);
  static const String _defaultModelCacheName =
      'llamadart-webgpu-model-cache-v1';
  // Supplies parser metadata; the opted-in private subtype sends the original
  // messages through a preface. Raw generation remains one user turn.
  static const String _passthroughLatestMessageTemplate =
      '{% for message in messages %}'
      '{% if loop.last %}{{ message["content"] }}{% endif %}'
      '{% endfor %}';

  static const int _backendGpuArtisan = 2;
  static const int _backendCpu = 3;

  final String? _moduleUrl;
  final Duration _readyTimeout;
  final String? _preferredBackend;

  _LiteRtLmWebEngine? _engine;
  _LiteRtLmWebConversation? _activeConversation;
  _LiteRtLmWebRun? _activeRun;
  _LiteRtLmWebRun? _queuedRun;
  final Expando<Future<void>> _conversationDeletes = Expando<Future<void>>();
  final _LiteRtLmWebRuntimeToolCalls _runtimeToolCalls =
      _LiteRtLmWebRuntimeToolCalls();
  final _LiteRtLmWebGenerationLimits _generationLimits =
      _LiteRtLmWebGenerationLimits();
  LlamaLogLevel _logLevel = LlamaLogLevel.warn;
  bool _isReady = false;
  bool _supportsTextHistory = false;
  bool _supportsToolDeclarations = false;
  // The context size the loaded engine's executor enforces, once the load
  // probe showed its runtime reports per-turn decode and context token counts.
  int? _reportedContextTokens;
  bool _hasContext = false;
  bool _cancelRequested = false;
  int _nextModelHandle = 1;
  int _nextContextHandle = 1;
  int? _modelHandle;
  int? _contextHandle;
  ModelParams? _modelParams;
  String? _modelUrl;
  String? _modelSource;
  String? _modelCacheState;
  String? _activeBackend;
  int? _engineBackendValue;
  String? _chatTemplate;

  /// Creates a web LiteRT-LM backend.
  ///
  /// [initialSendPort] is accepted for API compatibility with the native
  /// backend and ignored on web. [preferredBackend] (`cpu` or `gpu`) is
  /// deprecated: set `ModelParams.device` instead. A load whose
  /// `ModelParams.device` is not auto throws `LlamaUnsupportedException` when
  /// [preferredBackend] is set.
  LiteRtLmBackend({
    Object? initialSendPort,
    @Deprecated('Use ModelParams.device. This will be removed in 1.0.')
    String? preferredBackend,
    String? moduleUrl,
    Duration? readyTimeout,
  }) : _moduleUrl = moduleUrl,
       _readyTimeout = readyTimeout ?? _engineReadyTimeout,
       _preferredBackend = _normalizeBackendOverride(preferredBackend) {
    registerRuntimeToolCallReporter(this, _runtimeToolCalls);
    registerGenerationLimitReporter(this, _generationLimits);
  }

  /// Creates a backend with ordered system/user/assistant text history.
  ///
  /// Requires the loaded runtime to consume `preface` and expose `getHistory`.
  /// The final message must be user text or tool results. Tools are declared
  /// through `preface.tools` when the loaded runtime reads it, which
  /// `supportsToolCalling` reports; the model's calls come back as
  /// [LlamaToolCallContent]. A load probe checks that the runtime reports
  /// each turn's decode and context token counts; a reply that reaches
  /// `maxTokens` or fills the context then ends with finish reason `length`,
  /// and automatic tool loops run. A reply whose end-of-turn token is its
  /// `maxTokens`-th token also ends with `length`: the runtime does not say
  /// which of the two ended it. `ToolChoice.required`, parallel tool calls,
  /// media and template/thinking controls throw
  /// [LlamaUnsupportedException]. The original constructor's
  /// subclass dispatch contract remains unchanged. Session budgets use a
  /// full-transcript UTF-8 estimate; exact JS tokenization is unavailable.
  factory LiteRtLmBackend.withTextHistory({
    Object? initialSendPort,
    @Deprecated('Use ModelParams.device. This will be removed in 1.0.')
    String? preferredBackend,
    String? moduleUrl,
    Duration? readyTimeout,
  }) => _TextHistoryLiteRtLmBackend(
    initialSendPort: initialSendPort,
    preferredBackend: preferredBackend,
    moduleUrl: moduleUrl,
    readyTimeout: readyTimeout,
  );

  bool get _textHistoryEnabled => false;

  /// Null once a [LiteRtLmBackend.withTextHistory] load has shown that its
  /// runtime reports each turn's decode and context token counts; otherwise,
  /// and before a load, why automatic tool loops cannot run.
  @override
  String? get generationLimitUnsupportedReason => !_textHistoryEnabled
      ? 'LiteRT-LM Web reports token-limit truncation only through '
            'LlamaBackend.withTextHistory() or LiteRtLmBackend.withTextHistory(). '
            'Use ChatSession.create or LlamaEngine.create for manual completion.'
      : _isReady && _reportedContextTokens != null
      ? null
      : 'The loaded LiteRT-LM Web runtime did not report the decode and '
            'context token counts of a turn (benchmarkEnabled, '
            'getBenchmarkInfo and getTokenCount) and the context size its '
            'executor enforces, so a reply cut off at maxTokens or the '
            'context size cannot be told from a finished one. '
            '@litert-lm/core@0.19.0 reports them. Use ChatSession.create or '
            'LlamaEngine.create for manual completion.';

  @override
  bool get isReady => _isReady;

  @override
  bool get supportsUrlLoading => true;

  @override
  bool get supportsEmbeddings => false;

  @override
  bool get supportsStatePersistence => false;

  @override
  bool get supportsGrammarConstraints => false;

  /// False for this legacy single-user-text constructor.
  /// [LiteRtLmBackend.withTextHistory] probes the loaded runtime's preface and
  /// history API before reporting system/user/assistant text support.
  @override
  bool get supportsMultiTurnChat => false;

  /// False for this legacy single-user-text constructor.
  /// [LiteRtLmBackend.withTextHistory] probes whether the loaded runtime reads
  /// `preface.tools`.
  @override
  bool get supportsToolCalling => false;

  @override
  Future<int> modelLoad(String path, ModelParams params) {
    return modelLoadFromUrl(path, params);
  }

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    void Function(double progress)? onProgress,
  }) async {
    _validateLiteRtLmSource(url);
    return _load(url, params, onProgress: onProgress);
  }

  @override
  Future<int> modelLoadAs(String path, ModelParams params, ModelFormat format) {
    return modelLoadFromUrlAs(path, params, format);
  }

  /// Loads [url] without requiring a `.litertlm` extension, for a URL the
  /// caller declared a LiteRT-LM bundle.
  @override
  Future<int> modelLoadFromUrlAs(
    String url,
    ModelParams params,
    ModelFormat format, {
    void Function(double progress)? onProgress,
  }) async {
    if (format != ModelFormat.liteRtLm) {
      throw LlamaUnsupportedException(
        'The Web LiteRT-LM backend cannot load ModelFormat.${format.name}. '
        'Use LlamaBackend(), which picks the runtime per model.',
      );
    }
    return _load(url, params, onProgress: onProgress);
  }

  Future<int> _load(
    String url,
    ModelParams params, {
    void Function(double progress)? onProgress,
  }) async {
    liteRtLmWebCheckLoad(params, preferredBackend: _preferredBackend);
    _validateModelParams(params);
    final backend = _resolveBackendName(params);
    if (params.device == ComputeDevice.gpu && !await webGpuAdapterAvailable()) {
      throw LlamaUnsupportedException(
        'ComputeDevice.gpu needs WebGPU for LiteRT-LM on the Web, but this '
        'browser grants no WebGPU adapter. Use ComputeDevice.auto or cpu, or '
        'a browser with WebGPU enabled.',
      );
    }

    onProgress?.call(0);
    final constructor = await _ensureEngineConstructor();
    final cachedModelBlob = await _cachedModelBlobFor(url);
    final modelValue = cachedModelBlob ?? url.toJS;
    final settings = _createEngineSettings(
      model: modelValue,
      params: params,
      backend: backend,
    );

    await _disposeEngine();
    _modelUrl = url;
    _modelSource = cachedModelBlob == null ? 'network' : 'cache';
    _modelCacheState = cachedModelBlob == null ? 'miss' : 'hit';
    _modelParams = params;
    _chatTemplate = params.chatTemplate;
    _activeBackend = backend;
    _hasContext = false;

    _setLiteRtLmConsoleLogLevel();
    final consoleGuard = _installScopedConsoleGuard();
    try {
      _engine = await constructor.create(settings).toDart;
      _engineBackendValue =
          _reportedBackendValue(_engine!) ?? _backendValueFor(backend);
      _supportsTextHistory =
          _textHistoryEnabled && await _probeTextHistory(_engine!);
      _supportsToolDeclarations =
          _supportsTextHistory && await _probeToolDeclarations(_engine!);
      _reportedContextTokens = _supportsTextHistory
          ? await _probeGenerationLimits(_engine!)
          : null;
      _modelHandle = _nextModelHandle++;
      _isReady = true;
      onProgress?.call(1);
      return _modelHandle!;
    } catch (error) {
      _isReady = false;
      _supportsTextHistory = false;
      _supportsToolDeclarations = false;
      _reportedContextTokens = null;
      _modelHandle = null;
      _contextHandle = null;
      _modelUrl = null;
      _modelSource = null;
      _modelCacheState = null;
      _modelParams = null;
      _chatTemplate = null;
      _activeBackend = null;
      _engineBackendValue = null;
      throw StateError('LiteRT-LM web engine creation failed: $error');
    } finally {
      consoleGuard?.restore();
    }
  }

  @override
  Future<void> modelFree(int modelHandle) async {
    _requireModelHandle(modelHandle);
    await _disposeEngine();
  }

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async {
    _requireModelHandle(modelHandle);
    _validateModelParams(params);
    _validateContextParams(params);
    _contextHandle = _nextContextHandle++;
    _hasContext = true;
    return _contextHandle!;
  }

  @override
  Future<void> contextFree(int contextHandle) async {
    _requireContextHandle(contextHandle);
    _cancelActiveRun();
    _hasContext = false;
    _contextHandle = null;
    _closeQueuedRun();
    final conversation = _activeConversation;
    _activeConversation = null;
    if (conversation != null) {
      await _deleteConversation(conversation);
    }
  }

  @override
  Future<int> getContextSize(int contextHandle) async {
    _requireContextHandle(contextHandle);
    return _reportedContextTokens ?? _modelParams?.contextSize ?? 0;
  }

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) => _generateWithHistory(contextHandle, prompt.toJS, params, parts: parts);

  /// Streams one reply to [message], a user text string or a `Message`
  /// object, after the [history] and [tools] preface.
  Stream<List<int>> _generateWithHistory(
    int contextHandle,
    JSAny message,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
    List<Map<String, Object?>> history = const [],
    List<Map<String, dynamic>> tools = const [],
  }) {
    // Calls to declared tools go to the engine beside the text; any other
    // runtime call stays literal JSON text.
    final run = _LiteRtLmWebRun(reportsToolCalls: tools.isNotEmpty);
    late final StreamController<List<int>> controller;
    // The engine looks calls up by the identity of the stream it was given.
    late final Stream<List<int>> stream = controller.stream;
    StreamSubscription<List<int>>? subscription;
    controller = StreamController<List<int>>(
      onListen: () {
        if (_activeRun == null) {
          _startRun(run);
        } else if (_cancelRequested && _queuedRun == null) {
          _queuedRun = run;
        } else {
          controller
            ..addError(
              LlamaStateException(
                'LiteRT-LM web generation is already in progress. Cancel it '
                'or wait for its stream to end before starting another.',
              ),
            )
            ..close();
          return;
        }
        subscription =
            _generateRun(
              run,
              contextHandle,
              message,
              params,
              parts,
              history,
              tools,
            ).listen(
              controller.add,
              onError: controller.addError,
              onDone: () {
                if (run.toolCalls.isNotEmpty) {
                  _runtimeToolCalls.calls[stream] = List.unmodifiable(
                    run.toolCalls,
                  );
                }
                _generationLimits.limits[stream] = run.limit;
                _finishRun(run);
                unawaited(controller.close());
              },
            );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        if (identical(_queuedRun, run)) {
          _closeQueuedRun();
        } else if (identical(_activeRun, run)) {
          // Cancels only this run, so a generation queued behind it still
          // starts once it ends.
          _cancelActiveRun();
        }
        // Nobody listens any more, so an error the cancelled run ends with
        // has no caller to reach.
        return subscription
            ?.cancel()
            .catchError((Object _) {})
            .whenComplete(() => _finishRun(run));
      },
    );
    return stream;
  }

  /// Runs one generation for [generate].
  ///
  /// A queued [run] waits until the cancelled run ahead of it ends.
  Stream<List<int>> _generateRun(
    _LiteRtLmWebRun run,
    int contextHandle,
    JSAny message,
    GenerationParams params,
    List<LlamaContentPart>? parts,
    List<Map<String, Object?>> history,
    List<Map<String, dynamic>> tools,
  ) async* {
    final engine = _requireContextHandle(contextHandle);
    if (parts?.any((part) => part is LlamaVideoContent) ?? false) {
      _throwChatUnsupported(
        'LiteRT-LM Web video input is not supported through llamadart. '
        'Extract and send image frames instead.',
      );
    }
    if (_hasMediaParts(parts)) {
      _throwChatUnsupported(
        'LiteRtLmBackend web does not support media parts.',
      );
    }
    _validateGenerationParams(params);
    if (params.maxTokens <= 0) {
      return;
    }
    if (!identical(_activeRun, run) && !await run.admission.future) {
      return;
    }

    final conversation = await engine
        .createConversation(
          _createConversationConfig(params, history: history, tools: tools),
        )
        .toDart;
    _activeConversation = conversation;

    final stopSequences = params.stopSequences
        .where((sequence) => sequence.isNotEmpty)
        .toList(growable: false);
    try {
      if (_cancelRequested ||
          !identical(engine, _engine) ||
          contextHandle != _contextHandle ||
          !_hasContext) {
        return;
      }
      final stream = _withScopedConsoleGuardedStream(
        _streamConversation(conversation, message, run),
      );
      await for (final chunk in _applyStopSequences(
        stream,
        stopSequences,
        onStop: _cancelActiveRun,
      )) {
        if (_cancelRequested) {
          break;
        }
        yield chunk;
      }
      final contextTokens = _reportedContextTokens;
      if (!_cancelRequested && contextTokens != null) {
        final limit = await _generationLimitOf(
          conversation,
          maxTokens: params.maxTokens,
          contextTokens: contextTokens,
        );
        // A cancel or stop sequence wins over a limit reached meanwhile.
        if (!_cancelRequested) run.limit = limit;
      }
    } finally {
      if (identical(_activeConversation, conversation)) {
        _activeConversation = null;
      }
      await _deleteConversation(conversation);
    }
  }

  void _startRun(_LiteRtLmWebRun run) {
    _activeRun = run;
    _cancelRequested = false;
  }

  /// Ends [run] and starts the generation queued behind it.
  void _finishRun(_LiteRtLmWebRun run) {
    if (identical(_queuedRun, run)) {
      _queuedRun = null;
    }
    if (!identical(_activeRun, run)) {
      return;
    }
    _activeRun = null;
    final queued = _queuedRun;
    if (queued == null) {
      return;
    }
    _queuedRun = null;
    _startRun(queued);
    queued.admission.complete(true);
  }

  /// Ends the generation waiting for a cancelled run without starting it.
  void _closeQueuedRun() {
    final queued = _queuedRun;
    _queuedRun = null;
    queued?.admission.complete(false);
  }

  void _cancelActiveRun() {
    _cancelRequested = true;
    try {
      _activeConversation?.cancel();
    } catch (_) {
      // Preserve the caller-visible generation error, if any.
    }
  }

  @override
  void cancelGeneration() {
    _cancelActiveRun();
    _closeQueuedRun();
  }

  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async {
    _requireModelHandle(modelHandle);
    throw UnsupportedError(
      'LiteRtLmBackend web does not expose tokenizer operations yet.',
    );
  }

  @override
  Future<String> detokenize(
    int modelHandle,
    List<int> tokens, {
    bool special = false,
  }) async {
    _requireModelHandle(modelHandle);
    throw UnsupportedError(
      'LiteRtLmBackend web does not expose tokenizer operations yet.',
    );
  }

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async {
    _requireModelHandle(modelHandle);
    final modelUrl = _modelUrl;
    final metadata = <String, String>{
      'general.architecture': 'litert-lm',
      'general.file_type': 'litertlm',
      'llamadart.backend': 'LiteRT-LM web',
      'llamadart.litert_lm_web.chat_scope': supportsMultiTurnChat
          ? 'system-user-assistant-text'
          : 'single-turn-text',
      'llamadart.litert_lm_web.structured_chat': '$supportsMultiTurnChat',
      'tokenizer.chat_template':
          _chatTemplate ?? _passthroughLatestMessageTemplate,
    };
    if (modelUrl != null) {
      if (_modelUrlName(modelUrl) case final modelName?) {
        metadata['general.name'] = modelName;
      }
      metadata['litert_lm.model_url'] = _modelUrlDisplay(modelUrl);
    }
    if (_modelParams case final params?) {
      metadata['llm.context_length'] = params.contextSize.toString();
    }
    if (_modelSource case final source?) {
      metadata['llamadart.litert_lm_web.model_source'] = source;
    }
    if (_modelCacheState case final state?) {
      metadata['llamadart.litert_lm_web.model_cache_state'] = state;
    }
    final activeBackend = _activeBackend;
    if (activeBackend != null) {
      metadata['litert_lm.backend'] = activeBackend;
    }
    return metadata;
  }

  @override
  LlamaRuntime get runtime => LlamaRuntime.liteRtLm;

  @override
  Future<String> getBackendName() async {
    final backend = _activeBackend ?? _preferredBackend ?? 'auto';
    return 'LiteRT-LM web $backend';
  }

  @override
  Future<String> getAvailableBackends() async => 'cpu, gpu';

  @override
  Future<bool> isGpuSupported() async {
    final navigator = globalContext.getProperty('navigator'.toJS);
    if (navigator == null || !navigator.isA<JSObject>()) {
      return false;
    }
    return (navigator as JSObject).getProperty('gpu'.toJS) != null;
  }

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {
    _logLevel = level;
    _setLiteRtLmConsoleLogLevel();
  }

  @override
  Future<void> dispose() async {
    await _disposeEngine();
  }

  @override
  Future<({int total, int free})> getVramInfo() async {
    return (total: 0, free: 0);
  }

  @override
  Future<String> applyChatTemplate(
    int modelHandle,
    List<Map<String, dynamic>> messages, {
    String? customTemplate,
    bool addAssistant = true,
  }) async {
    _requireModelHandle(modelHandle);
    if (customTemplate != null &&
        (_textHistoryEnabled || customTemplate.isNotEmpty)) {
      _throwChatUnsupported(
        'LiteRtLmBackend web does not apply custom chat templates directly.',
      );
    }

    if (messages.isEmpty) {
      return '';
    }
    if (_textHistoryEnabled &&
        (messages.length != 1 || messages.single['role'] != 'user')) {
      throw LlamaUnsupportedException(
        'LiteRT-LM Web applyChatTemplate cannot represent structured history '
        'as a prompt string. Use LlamaEngine.create or ChatSession.create '
        'with system/user/assistant text messages.',
      );
    }
    return _contentTextFromTemplateMap(messages.last['content']);
  }

  @override
  Future<List<double>> embed(
    int contextHandle,
    String text, {
    bool normalize = true,
  }) async {
    _requireContextHandle(contextHandle);
    throw UnsupportedError('LiteRtLmBackend web does not support embeddings.');
  }

  @override
  Future<bool> stateSaveFile(int contextHandle, String path, List<int> tokens) {
    _requireContextHandle(contextHandle);
    throw UnsupportedError(
      'LiteRtLmBackend web does not support state persistence.',
    );
  }

  @override
  Future<StateLoadResult> stateLoadFile(
    int contextHandle,
    String path,
    int tokenCapacity,
  ) {
    _requireContextHandle(contextHandle);
    throw UnsupportedError(
      'LiteRtLmBackend web does not support state persistence.',
    );
  }

  Future<_LiteRtLmEngineConstructor> _ensureEngineConstructor() async {
    if (!globalContext.has('LiteRtLmEngine')) {
      final moduleUrl =
          _moduleUrl ?? _getGlobalString('__llamadartLiteRtLmModuleUrl');
      if (moduleUrl != null && moduleUrl.isNotEmpty) {
        await _loadModuleScript(moduleUrl);
      } else {
        await _waitForPreloadedEngine();
      }
    }

    final raw = globalContext.getProperty('LiteRtLmEngine'.toJS);
    if (raw != null && raw.isA<JSObject>()) {
      return _LiteRtLmEngineConstructor._(raw as JSObject);
    }

    throw LlamaBackendInitializationException(
      'LiteRT-LM web runtime is not loaded. Preload @litert-lm/core and set '
      'window.LiteRtLmEngine = module.Engine, or set '
      'window.__llamadartLiteRtLmModuleUrl to the @litert-lm/core module URL.',
    );
  }

  Future<void> _loadModuleScript(String moduleUrl) async {
    if (globalContext.has('LiteRtLmEngine')) {
      return;
    }

    final completer = Completer<void>();
    const callbackName = '__llamadart_litert_lm_init';
    globalContext.setProperty(
      callbackName.toJS,
      (JSAny? err) {
        if (err != null) {
          if (!completer.isCompleted) {
            completer.completeError(
              LlamaBackendInitializationException(
                'LiteRT-LM web module load failed: $err',
              ),
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
      import(${jsonEncode(moduleUrl)}).then(mod => {
        if (mod?.Engine) {
          window.LiteRtLmEngine = mod.Engine;
        }
        if (mod?.Backend) {
          window.LiteRtLmBackendEnum = mod.Backend;
        }
        window.__llamadartLiteRtLmModule = mod;
        if (window.$callbackName) {
          window.$callbackName(null);
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
            LlamaBackendInitializationException(
              'Failed to load LiteRT-LM web module script',
            ),
          );
        }
      }).toJS,
    );

    document.head?.append(script);
    try {
      await completer.future.timeout(_readyTimeout);
    } finally {
      globalContext.delete(callbackName.toJS);
    }
  }

  Future<void> _waitForPreloadedEngine() async {
    final deadline = DateTime.now().add(_readyTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (globalContext.has('LiteRtLmEngine')) {
        return;
      }
      await Future<void>.delayed(_enginePollInterval);
    }
  }

  JSObject _createEngineSettings({
    required JSAny model,
    required ModelParams params,
    required String backend,
  }) {
    final settings = JSObject();
    settings.setProperty('model'.toJS, model);
    // GPU loads keep the runtime's default backend. @litert-lm/core@0.19.0
    // resolves it to GPU_ARTISAN for Web bundles and GPU for other bundles;
    // 0.18.0, which apps may still preload, defaults to GPU_ARTISAN and fails
    // Web bundles on GPU. No single explicit value loads on both.
    if (backend == 'cpu') {
      settings.setProperty('backend'.toJS, _backendValueFor(backend).toJS);
    }

    final executorSettings = JSObject();
    executorSettings.setProperty('maxNumTokens'.toJS, params.contextSize.toJS);
    settings.setProperty('mainExecutorSettings'.toJS, executorSettings);
    // Per-turn decode token counts come only from the benchmark record.
    if (_textHistoryEnabled) {
      settings.setProperty('benchmarkEnabled'.toJS, true.toJS);
    }
    return settings;
  }

  JSObject _createConversationConfig(
    GenerationParams params, {
    List<Map<String, Object?>> history = const [],
    List<Map<String, dynamic>> tools = const [],
  }) {
    final samplerParams = JSObject();
    samplerParams.setProperty(
      'k'.toJS,
      liteRtLmEffectiveTopK(temperature: params.temp, topK: params.topK).toJS,
    );
    samplerParams.setProperty('p'.toJS, params.topP.toJS);
    samplerParams.setProperty('temperature'.toJS, params.temp.toJS);
    samplerParams.setProperty(
      'seed'.toJS,
      (params.seed ?? _defaultSamplerSeed()).toJS,
    );

    final sessionConfig = JSObject();
    sessionConfig.setProperty('maxOutputTokens'.toJS, params.maxTokens.toJS);
    sessionConfig.setProperty('samplerParams'.toJS, samplerParams);
    sessionConfig.setProperty(
      'samplerBackend'.toJS,
      (_engineBackendValue ?? _backendValueFor(_activeBackend ?? 'gpu')).toJS,
    );

    final config = JSObject();
    config.setProperty('sessionConfig'.toJS, sessionConfig);
    if (history.isNotEmpty || tools.isNotEmpty) {
      config.setProperty(
        'preface'.toJS,
        {
          if (history.isNotEmpty) 'messages': history,
          if (tools.isNotEmpty) 'tools': tools,
        }.jsify(),
      );
    }
    return config;
  }

  Future<bool> _probeTextHistory(_LiteRtLmWebEngine engine) async {
    _LiteRtLmWebConversation? conversation;
    var consumedPreface = false;
    // getHistory omits the preface. Observe option consumption separately so
    // legacy runtimes cannot silently accept and ignore the history option.
    try {
      final preface = <String, Object>{'messages': <Object>[]}.jsify();
      final config = _createConversationConfig(const GenerationParams());
      final descriptor = JSObject()
        ..setProperty(
          'get'.toJS,
          (() {
            consumedPreface = true;
            return preface;
          }).toJS,
        );
      globalContext
          .getProperty<JSObject>('Object'.toJS)
          .callMethod<JSAny?>(
            'defineProperty'.toJS,
            config,
            'preface'.toJS,
            descriptor,
          );
      conversation = await engine.createConversation(config).toDart;
      final history = await conversation
          .callMethod<JSPromise<JSAny?>>('getHistory'.toJS)
          .toDart;
      return consumedPreface && history != null && history.isA<JSArray>();
    } catch (_) {
      return false;
    } finally {
      if (conversation != null) await _deleteConversation(conversation);
    }
  }

  /// Whether creating a conversation reads `preface.tools`, so tool
  /// declarations reach the runtime rather than being dropped.
  Future<bool> _probeToolDeclarations(_LiteRtLmWebEngine engine) async {
    _LiteRtLmWebConversation? conversation;
    var consumedTools = false;
    try {
      final tools = <Object>[
        <String, Object>{
          'type': 'function',
          'function': <String, Object>{
            'name': 'llamadart_probe',
            'description': '',
            'parameters': <String, Object>{
              'type': 'object',
              'properties': <String, Object>{},
            },
          },
        },
      ].jsify();
      final preface = <String, Object>{'messages': <Object>[]}.jsify()!;
      // Enumerable, so a runtime that serializes the preface reads it.
      final descriptor = JSObject()
        ..setProperty('enumerable'.toJS, true.toJS)
        ..setProperty(
          'get'.toJS,
          (() {
            consumedTools = true;
            return tools;
          }).toJS,
        );
      globalContext
          .getProperty<JSObject>('Object'.toJS)
          .callMethod<JSAny?>(
            'defineProperty'.toJS,
            preface,
            'tools'.toJS,
            descriptor,
          );
      final config = _createConversationConfig(const GenerationParams())
        ..setProperty('preface'.toJS, preface);
      conversation = await engine.createConversation(config).toDart;
      return consumedTools;
    } catch (_) {
      return false;
    } finally {
      if (conversation != null) await _deleteConversation(conversation);
    }
  }

  /// The context size [engine]'s executor enforces, when its runtime reports
  /// the decode and context token counts of a turn and names that size; else
  /// null.
  Future<int?> _probeGenerationLimits(_LiteRtLmWebEngine engine) async {
    final resolved = _resolvedContextTokens(engine);
    if (resolved == null) return null;
    final total = await _probeOneTokenTurn(engine);
    if (total == null) return null;
    final contextTokens = await _probeExecutorContextTokens(engine, resolved);
    return contextTokens != null && total < contextTokens
        ? contextTokens
        : null;
  }

  /// The tokens a one-token turn leaves in its conversation, or null when the
  /// runtime does not count that turn.
  ///
  /// At `maxOutputTokens` 1 a turn decodes exactly one token, so a runtime
  /// that keeps no benchmark record or counts another turn fails.
  Future<int?> _probeOneTokenTurn(_LiteRtLmWebEngine engine) async {
    _LiteRtLmWebConversation? conversation;
    try {
      conversation = await engine
          .createConversation(
            _createConversationConfig(const GenerationParams(maxTokens: 1)),
          )
          .toDart;
      if (!conversation.has('getBenchmarkInfo') ||
          !conversation.has('getTokenCount')) {
        return null;
      }
      final reader = conversation.sendMessageStreaming('Hi'.toJS).getReader();
      while (!(await reader.read().toDart).done) {}
      final counts = await _tokenCounts(conversation);
      return counts != null && counts.decoded == 1 ? counts.total : null;
    } catch (_) {
      return null;
    } finally {
      if (conversation != null) await _deleteConversation(conversation);
    }
  }

  static final RegExp _inputTooLong = RegExp(
    r'^Input token ids are too long\. Exceeding the maximum number of '
    r'tokens allowed: (\d+) >= (\d+)$',
  );

  /// The `maxNumTokens` [engine]'s executor enforces, from its rejection of a
  /// prompt longer than [resolved] tokens, or null.
  ///
  /// `engine.settings` repeats the requested size, but an executor with a
  /// fixed KV cache clamps its own copy to the cache, and decoding stops at
  /// that copy. Prefill rejects an input of at least that many tokens before
  /// running the model and names the limit. Tokenizers give digits a token
  /// each or per three (Gemma, Qwen, Llama 3); one that merges more lets the
  /// prompt through, which costs a long prefill and fails the probe.
  Future<int?> _probeExecutorContextTokens(
    _LiteRtLmWebEngine engine,
    int resolved,
  ) async {
    _LiteRtLmWebConversation? conversation;
    try {
      conversation = await engine
          .createConversation(
            _createConversationConfig(const GenerationParams(maxTokens: 1)),
          )
          .toDart;
      // Varied digits, which tokenizers merge least.
      final digits = StringBuffer();
      var seed = 1;
      for (var i = 0; i < resolved * 4 + 64; i++) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        digits.write(seed % 10);
      }
      final reader = conversation
          .sendMessageStreaming(digits.toString().toJS)
          .getReader();
      try {
        while (!(await reader.read().toDart).done) {}
      } catch (error) {
        final match = _inputTooLong.firstMatch(_errorMessage(error) ?? '');
        if (match == null) return null;
        final input = int.parse(match[1]!);
        final limit = int.parse(match[2]!);
        return limit > 1 && input >= limit ? limit : null;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      if (conversation != null) await _deleteConversation(conversation);
    }
  }

  static String? _errorMessage(Object error) {
    try {
      final message = (error as JSObject).getProperty<JSAny?>('message'.toJS);
      return message.isA<JSString>() ? (message as JSString).toDart : null;
    } catch (_) {
      return null;
    }
  }

  /// The `maxNumTokens` [engine] resolved at creation: the requested size,
  /// which bounds the executor's.
  int? _resolvedContextTokens(_LiteRtLmWebEngine engine) {
    try {
      final settings = engine.getProperty<JSAny?>('settings'.toJS);
      if (settings == null || !settings.isA<JSObject>()) return null;
      final executor = (settings as JSObject).getProperty<JSAny?>(
        'mainExecutorSettings'.toJS,
      );
      if (executor == null || !executor.isA<JSObject>()) return null;
      return _positiveInt(
        (executor as JSObject).getProperty<JSAny?>('maxNumTokens'.toJS),
      );
    } catch (_) {
      return null;
    }
  }

  /// Why the turn [conversation] just finished ended, from its token counts.
  ///
  /// `@litert-lm/core@0.19.0` ends a turn at a stop token, once its decode
  /// steps reach `maxOutputTokens`, or once the conversation's tokens reach
  /// the executor's `maxNumTokens` ([contextTokens]), and reports none of
  /// these causes. Fewer decode steps than [maxTokens] and fewer tokens than
  /// [contextTokens] rule both budgets out, so only then is the turn
  /// finished. A turn at a budget is cut off even if its last token was a
  /// stop token: the counts cannot tell the two apart.
  Future<BackendGenerationLimit?> _generationLimitOf(
    _LiteRtLmWebConversation conversation, {
    required int maxTokens,
    required int contextTokens,
  }) async {
    final counts = await _tokenCounts(conversation);
    return counts == null
        ? BackendGenerationLimit.runtime
        : counts.total >= contextTokens
        ? BackendGenerationLimit.contextSize
        : counts.decoded >= maxTokens
        ? BackendGenerationLimit.maxTokens
        : null;
  }

  /// The tokens [conversation]'s last turn decoded and the tokens it holds,
  /// or null when the runtime does not report them consistently.
  Future<({int decoded, int total})?> _tokenCounts(
    _LiteRtLmWebConversation conversation,
  ) async {
    try {
      final info = await conversation.getBenchmarkInfo().toDart;
      final decoded = info != null && info.isA<JSObject>()
          ? _positiveInt(
              (info as JSObject).getProperty<JSAny?>(
                'lastDecodeTokenCount'.toJS,
              ),
            )
          : null;
      final total = _positiveInt(await conversation.getTokenCount().toDart);
      // A turn prefills at least one token before it decodes.
      if (decoded == null || total == null || total <= decoded) return null;
      return (decoded: decoded, total: total);
    } catch (_) {
      return null;
    }
  }

  static int? _positiveInt(JSAny? value) {
    if (value == null || !value.isA<JSNumber>()) return null;
    final number = (value as JSNumber).toDartDouble;
    return number.isFinite && number >= 1 && number == number.truncate()
        ? number.toInt()
        : null;
  }

  _LiteRtLmWebEngine _requireEngine() {
    final engine = _engine;
    if (engine == null || !_isReady) {
      throw StateError('No LiteRT-LM web model is loaded.');
    }
    return engine;
  }

  _LiteRtLmWebEngine _requireModelHandle(int modelHandle) {
    final engine = _requireEngine();
    if (modelHandle != _modelHandle) {
      throw StateError('Invalid LiteRT-LM web model handle: $modelHandle');
    }
    return engine;
  }

  _LiteRtLmWebEngine _requireContextHandle(int contextHandle) {
    final engine = _requireEngine();
    if (contextHandle != _contextHandle || !_hasContext) {
      throw StateError('Invalid LiteRT-LM web context handle: $contextHandle');
    }
    return engine;
  }

  Stream<String> _streamConversation(
    _LiteRtLmWebConversation conversation,
    JSAny message,
    _LiteRtLmWebRun run,
  ) async* {
    final reader = conversation.sendMessageStreaming(message).getReader();
    try {
      while (!_cancelRequested) {
        final _LiteRtLmStreamReadResult result;
        try {
          result = await reader.read().toDart;
        } catch (error) {
          // @litert-lm/core@0.19.0 forwards the cancelled status message as a
          // plain Error. Other failures racing cancellation must still surface.
          if (_cancelRequested && _isCancellationError(error)) break;
          rethrow;
        }
        if (result.done) {
          break;
        }

        final text = _extractTextChunk(result.value, run);
        if (text.isNotEmpty) {
          yield text;
        }
      }
    } finally {
      if (_cancelRequested) {
        try {
          final cancel = reader.cancel();
          if (cancel != null) {
            await cancel.toDart;
          }
        } catch (_) {
          // The conversation cancel path above is the authoritative signal.
        }
      }
      try {
        reader.releaseLock();
      } catch (_) {
        // Some stream implementations auto-release after completion/cancel.
      }
    }
  }

  bool _isCancellationError(Object error) {
    try {
      final message = (error as JSObject).getProperty<JSAny?>('message'.toJS);
      return message.isA<JSString>() &&
          (message as JSString).toDart == 'Task cancelled';
    } catch (_) {
      return false;
    }
  }

  Stream<List<int>> _applyStopSequences(
    Stream<String> source,
    List<String> stopSequences, {
    required void Function() onStop,
  }) async* {
    if (stopSequences.isEmpty) {
      await for (final chunk in source) {
        if (chunk.isNotEmpty) {
          yield utf8.encode(chunk);
        }
      }
      return;
    }

    final keepChars =
        stopSequences.map((sequence) => sequence.length).reduce(math.max) - 1;
    var pending = '';
    var stopped = false;

    await for (final chunk in source) {
      pending += chunk;
      final stopIndex = _firstStopIndex(pending, stopSequences);
      if (stopIndex >= 0) {
        final allowed = pending.substring(0, stopIndex);
        if (allowed.isNotEmpty) {
          yield utf8.encode(allowed);
        }
        stopped = true;
        onStop();
        break;
      }

      final emitLength = pending.length - keepChars;
      if (emitLength > 0) {
        final allowed = pending.substring(0, emitLength);
        pending = pending.substring(emitLength);
        if (allowed.isNotEmpty) {
          yield utf8.encode(allowed);
        }
      }
    }

    if (!stopped && pending.isNotEmpty) {
      yield utf8.encode(pending);
    }
  }

  int _firstStopIndex(String text, List<String> stopSequences) {
    var stopIndex = -1;
    for (final stop in stopSequences) {
      final index = text.indexOf(stop);
      if (index >= 0 && (stopIndex < 0 || index < stopIndex)) {
        stopIndex = index;
      }
    }
    return stopIndex;
  }

  /// The text of the streamed message [value]. Its runtime-parsed tool calls
  /// go to [run] when it reports them, otherwise into the text as JSON.
  String _extractTextChunk(JSAny? value, _LiteRtLmWebRun run) {
    if (value == null) {
      return '';
    }
    if (value.isA<JSString>()) {
      return (value as JSString).toDart;
    }
    if (!value.isA<JSObject>()) {
      return '';
    }

    final obj = value as JSObject;
    final directText = obj.getProperty('text'.toJS);
    if (directText != null && directText.isA<JSString>()) {
      return (directText as JSString).toDart;
    }

    final buffer = StringBuffer();
    final content = obj.getProperty('content'.toJS);
    if (content != null && content.isA<JSArray>()) {
      final items = content as JSArray;
      for (var i = 0; i < items.length; i += 1) {
        final item = items.getProperty(i.toJS);
        if (item == null || !item.isA<JSObject>()) {
          continue;
        }
        final text = (item as JSObject).getProperty('text'.toJS);
        if (text != null && text.isA<JSString>()) {
          buffer.write((text as JSString).toDart);
        }
      }
    }
    final toolCalls = obj.getProperty<JSAny?>('tool_calls'.toJS);
    if (toolCalls != null &&
        toolCalls.isA<JSArray>() &&
        (toolCalls as JSArray).toDart.isNotEmpty) {
      final calls = toolCalls.dartify()! as List<Object?>;
      if (run.reportsToolCalls) {
        for (final call in calls) {
          run.toolCalls.add(_runtimeToolCall(call, run.toolCalls.length));
        }
      } else {
        buffer.write(jsonEncode({'tool_calls': calls}));
      }
    }
    return buffer.toString();
  }

  /// [call], a runtime `ToolCall`, as the [index]th call of a reply.
  LlamaCompletionChunkToolCall _runtimeToolCall(Object? call, int index) {
    final map = call is Map ? call : const {};
    final function = map['function'] is Map ? map['function'] as Map : const {};
    final arguments = function['arguments'];
    return LlamaCompletionChunkToolCall(
      index: index,
      id: map['id'] is String ? map['id'] as String : null,
      type: 'function',
      function: LlamaCompletionChunkFunction(
        name: function['name'] is String ? function['name'] as String : null,
        arguments: arguments is String
            ? arguments
            : jsonEncode(arguments ?? const {}),
      ),
    );
  }

  bool _hasMediaParts(List<LlamaContentPart>? parts) {
    if (parts == null) {
      return false;
    }
    return parts.any(
      (part) =>
          part is LlamaImageContent ||
          part is LlamaAudioContent ||
          part is LlamaVideoContent,
    );
  }

  String _contentTextFromTemplateMap(Object? content) {
    if (content == null) {
      return '';
    }
    if (content is String) {
      return content;
    }
    if (content is Map) {
      if (_isUnsupportedTemplateContentPart(content)) {
        _throwChatUnsupported(
          'LiteRtLmBackend web does not support multimodal chat-template '
          'content.',
        );
      }
      if (content['type']?.toString() == 'text' && content['text'] != null) {
        return content['text'].toString();
      }
      return content.toString();
    }
    if (content is Iterable) {
      final buffer = StringBuffer();
      for (final part in content) {
        if (part is Map) {
          if (_isUnsupportedTemplateContentPart(part)) {
            _throwChatUnsupported(
              'LiteRtLmBackend web does not support multimodal chat-template '
              'content.',
            );
          }
          final type = part['type']?.toString();
          if (type == 'text' && part['text'] != null) {
            buffer.write(part['text']);
            continue;
          }
        }
        buffer.write(part);
      }
      return buffer.toString();
    }
    return content.toString();
  }

  bool _isUnsupportedTemplateContentPart(Map<dynamic, dynamic> part) {
    final type = part['type']?.toString().toLowerCase();
    if (type == 'image' ||
        type == 'image_url' ||
        type == 'input_image' ||
        type == 'audio' ||
        type == 'input_audio' ||
        type == 'video' ||
        type == 'input_video') {
      return true;
    }
    return part.containsKey('image') ||
        part.containsKey('image_url') ||
        part.containsKey('input_audio') ||
        part.containsKey('audio') ||
        part.containsKey('video');
  }

  Future<void> _disposeEngine() async {
    _cancelActiveRun();
    _closeQueuedRun();
    final conversation = _activeConversation;
    _activeConversation = null;
    if (conversation != null) {
      await _deleteConversation(conversation);
    }

    final engine = _engine;
    _engine = null;
    _isReady = false;
    _supportsTextHistory = false;
    _supportsToolDeclarations = false;
    _reportedContextTokens = null;
    _hasContext = false;
    _modelHandle = null;
    _contextHandle = null;
    _modelUrl = null;
    _modelSource = null;
    _modelCacheState = null;
    _modelParams = null;
    _chatTemplate = null;
    _activeBackend = null;
    _engineBackendValue = null;
    if (engine != null) {
      final result = engine.deleteEngine();
      if (result != null) {
        await result.toDart;
      }
    }
  }

  Future<void> _deleteConversation(_LiteRtLmWebConversation conversation) =>
      _conversationDeletes[conversation] ??= _deleteConversationOnce(
        conversation,
      );

  Future<void> _deleteConversationOnce(
    _LiteRtLmWebConversation conversation,
  ) async {
    try {
      final result = conversation.deleteConversation();
      if (result != null) {
        await result.toDart;
      }
    } catch (_) {
      // Best-effort cleanup; callers should see the primary load/generate error.
    }
  }

  void _validateLiteRtLmSource(String source) {
    final path = _sourcePath(source).toLowerCase();
    if (!path.endsWith('.litertlm')) {
      throw ArgumentError(
        'LiteRtLmBackend web expects a .litertlm model URL/path; got $source',
      );
    }
  }

  Future<Blob?> _cachedModelBlobFor(String sourceUrl) async {
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
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

      return await cachedResponse.blob().toDart;
    } catch (_) {
      return null;
    }
  }

  Stream<String> _withScopedConsoleGuardedStream(Stream<String> source) async* {
    _setLiteRtLmConsoleLogLevel();
    final consoleGuard = _installScopedConsoleGuard();
    try {
      await for (final chunk in source) {
        yield chunk;
      }
    } finally {
      consoleGuard?.restore();
    }
  }

  void _setLiteRtLmConsoleLogLevel() {
    globalContext.setProperty(
      '__llamadartLiteRtLmLogLevel'.toJS,
      _logLevel.index.toJS,
    );
  }

  _LiteRtLmConsoleGuard? _installScopedConsoleGuard() {
    _ensureConsoleGuardInstaller();
    final rawInstaller = globalContext.getProperty<JSAny?>(
      '__llamadartInstallLiteRtLmConsoleGuard'.toJS,
    );
    if (rawInstaller == null || !rawInstaller.isA<JSFunction>()) {
      return null;
    }

    try {
      final rawGuard = (rawInstaller as JSFunction).callAsFunction(null);
      if (rawGuard != null && rawGuard.isA<JSObject>()) {
        return _LiteRtLmConsoleGuard._(rawGuard as JSObject);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  void _ensureConsoleGuardInstaller() {
    if (globalContext.has('__llamadartInstallLiteRtLmConsoleGuard')) {
      return;
    }

    final script = HTMLScriptElement();
    script.text = r'''
(() => {
  if (window.__llamadartInstallLiteRtLmConsoleGuard) {
    return;
  }

  window.__llamadartLiteRtLmLogLevel =
    Number.isFinite(Number(window.__llamadartLiteRtLmLogLevel))
      ? Number(window.__llamadartLiteRtLmLogLevel)
      : 0;

  const methods = ['debug', 'log', 'info', 'warn', 'error'];
  const methodLevels = { debug: 1, log: 2, info: 2, warn: 3, error: 4 };

  window.__llamadartInstallLiteRtLmConsoleGuard = function () {
    if (typeof console === 'undefined') {
      return { restore() {} };
    }

    const originals = {};
    const wrappers = {};
    for (const method of methods) {
      originals[method] = console[method];
    }

    function targetFor(method) {
      const candidate =
        originals[method] ||
        (method === 'info' ? originals.log : undefined) ||
        originals.log ||
        originals.error ||
        originals.warn ||
        originals.debug;
      return typeof candidate === 'function' ? candidate : null;
    }

    for (const method of methods) {
      const original = originals[method];
      if (typeof original !== 'function') {
        continue;
      }
      wrappers[method] = function (...args) {
        const configured = Number(window.__llamadartLiteRtLmLogLevel ?? 0);
        const threshold = Number.isFinite(configured) ? configured : 0;
        if (threshold === 0 || threshold > methodLevels[method]) {
          return;
        }
        const target = targetFor(method);
        if (target) {
          target.apply(console, args);
        }
      };
      console[method] = wrappers[method];
    }

    return {
      restore() {
        for (const method of methods) {
          if (wrappers[method] && console[method] === wrappers[method]) {
            console[method] = originals[method];
          }
        }
      },
    };
  };
})();
''';
    document.head?.append(script);
    script.remove();
  }

  String _sourcePath(String source) {
    final uri = Uri.tryParse(source);
    if (uri != null && uri.path.isNotEmpty) {
      return uri.path;
    }
    final queryIndex = source.indexOf('?');
    return queryIndex < 0 ? source : source.substring(0, queryIndex);
  }

  void _validateModelParams(ModelParams params) {
    if (params.chatTemplate?.trimLeft().startsWith(
          liteRtLmQwen3ChatTemplate.trim(),
        ) ??
        false) {
      throw LlamaUnsupportedException(
        'Qwen3 chatTemplate overrides require a conversation-template setter, '
        'which LiteRT-LM Web @litert-lm/core@0.19.0 does not expose. '
        'Use native LiteRT-LM with liteRtLmQwen3ChatTemplate to control '
        'enableThinking on renamed Qwen3 text bundles.',
      );
    }

    if (_textHistoryEnabled && params.chatTemplate != null) {
      throw LlamaUnsupportedException(
        'LiteRT-LM Web @litert-lm/core@0.19.0 has no custom chat-template '
        'setter. Use the model-provided template or native LiteRT-LM.',
      );
    }
    params.validate();
    checkModelParamsSupportedBy(params, LlamaRuntime.liteRtLm, web: true);
  }

  void _validateContextParams(ModelParams params) {
    final requested = _explicitBackendName(params);
    if (requested == 'npu') {
      throw UnsupportedError('LiteRT-LM web does not support NPU backend.');
    }
    if (requested != null && requested != _activeBackend) {
      throw ArgumentError(
        'LiteRtLmBackend web contextCreate cannot change the loaded backend '
        'from $_activeBackend to $requested.',
      );
    }
  }

  Never _throwChatUnsupported(String message) {
    if (_textHistoryEnabled) throw LlamaUnsupportedException(message);
    throw UnsupportedError(message);
  }

  void _validateGenerationParams(GenerationParams params) {
    const defaults = GenerationParams();
    final unsupported = <String>[];
    if (params.minP != defaults.minP) {
      unsupported.add('minP');
    }
    if (params.penalty != defaults.penalty) {
      unsupported.add('penalty');
    }
    if (params.presencePenalty != defaults.presencePenalty) {
      unsupported.add('presencePenalty');
    }
    if (params.grammar != null) {
      unsupported.add('grammar');
    }
    if (params.grammarLazy) {
      unsupported.add('grammarLazy');
    }
    if (params.thinkingBudget != null) {
      unsupported.add('thinkingBudget');
    }
    if (params.grammarTriggers.isNotEmpty) {
      unsupported.add('grammarTriggers');
    }
    if (params.preservedTokens.isNotEmpty) {
      unsupported.add('preservedTokens');
    }
    if (params.grammarRoot != defaults.grammarRoot) {
      unsupported.add('grammarRoot');
    }
    if (params.speculativeDecoding) {
      unsupported.add('speculativeDecoding');
    }
    if (params.speculativeDecodingConfig != null) {
      unsupported.add('speculativeDecodingConfig');
    }
    if (params.streamBatchTokenThreshold !=
        defaults.streamBatchTokenThreshold) {
      unsupported.add('streamBatchTokenThreshold');
    }
    if (params.streamBatchByteThreshold != defaults.streamBatchByteThreshold) {
      unsupported.add('streamBatchByteThreshold');
    }

    if (unsupported.isEmpty) {
      return;
    }
    _throwChatUnsupported(
      'LiteRtLmBackend web does not support llama.cpp-specific '
      'GenerationParams: ${unsupported.join(', ')}. Supported LiteRT-LM web '
      'generation options are maxTokens, temp, topK, topP, seed, and '
      'stopSequences.',
    );
  }

  String _resolveBackendName(ModelParams params) =>
      liteRtLmWebBackendName(params, preferredBackend: _preferredBackend);

  /// The backend an explicit [ModelParams.device] requires, or null for
  /// [ComputeDevice.auto].
  String? _deviceBackendName(ModelParams params) =>
      _liteRtLmWebDeviceBackendName(params, _preferredBackend);

  String? _explicitBackendName(ModelParams params) {
    final device = _deviceBackendName(params);
    if (device != null) {
      return device;
    }
    final explicit = params.liteRtLmBackend.nativeName;
    if (explicit != null) {
      return explicit;
    }
    if (resolveGpuLayerCount(params.gpuLayers) == 0) {
      return 'cpu';
    }
    if (params.preferredBackend != GpuBackend.auto) {
      return _backendNameForGpuPreference(params.preferredBackend);
    }
    return null;
  }

  String _backendNameForGpuPreference(GpuBackend backend) =>
      _liteRtLmWebBackendForGpuPreference(backend);

  int _backendValueFor(String backend) {
    final moduleBackend = _backendValueFromGlobalEnum(backend);
    if (moduleBackend != null) {
      return moduleBackend;
    }
    return switch (backend) {
      'cpu' => _backendCpu,
      // Only for an engine that reports no backend: GPU_ARTISAN was the GPU
      // default before @litert-lm/core@0.19.0.
      'gpu' => _backendGpuArtisan,
      _ => _backendGpuArtisan,
    };
  }

  /// The backend [engine] runs on, as its `settings.backend` reports it once
  /// the runtime has resolved its default.
  int? _reportedBackendValue(_LiteRtLmWebEngine engine) {
    try {
      final settings = engine.getProperty<JSAny?>('settings'.toJS);
      if (settings == null || !settings.isA<JSObject>()) return null;
      final value = (settings as JSObject).getProperty<JSAny?>('backend'.toJS);
      return value != null && value.isA<JSNumber>()
          ? (value as JSNumber).toDartInt
          : null;
    } catch (_) {
      return null;
    }
  }

  int? _backendValueFromGlobalEnum(String backend) {
    final raw = globalContext.getProperty('LiteRtLmBackendEnum'.toJS);
    if (raw == null || !raw.isA<JSObject>()) {
      return null;
    }
    final keys = switch (backend) {
      'cpu' => const ['CPU'],
      'gpu' => const ['GPU_ARTISAN', 'GPU'],
      _ => const <String>[],
    };
    final enumObject = raw as JSObject;
    for (final key in keys) {
      final value = enumObject.getProperty(key.toJS);
      if (value != null && value.isA<JSNumber>()) {
        return (value as JSNumber).toDartInt;
      }
    }
    return null;
  }

  int _defaultSamplerSeed() {
    return DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
  }

  String? _getGlobalString(String propertyName) {
    final raw = globalContext.getProperty(propertyName.toJS);
    if (raw != null && raw.isA<JSString>()) {
      final value = (raw as JSString).toDart.trim();
      return value.isEmpty ? null : value;
    }
    return null;
  }

  static String? _normalizeBackendOverride(String? backend) {
    if (backend == null) {
      return null;
    }
    final normalized = backend.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    if (normalized == 'cpu' || normalized == 'gpu' || normalized == 'npu') {
      return normalized;
    }
    throw ArgumentError(
      'LiteRtLmBackend backend must be cpu, gpu, or npu; got $backend',
    );
  }
}

// Only the additive factory creates this SPI subtype. Existing subclasses of
// the public generative constructor keep dispatch through their public hooks.
final class _TextHistoryLiteRtLmBackend extends LiteRtLmBackend
    implements BackendNativeChatGeneration, BackendChatMessageValidation {
  _TextHistoryLiteRtLmBackend({
    super.initialSendPort,
    super.preferredBackend,
    super.moduleUrl,
    super.readyTimeout,
  });

  // The runtime owns its tokenizer/template. Dart's budget fallback must see
  // every turn, while generation still receives the original structured input.
  // The engine parses with the text-only form and counts the session budget
  // from the plain render of the full form, which adds what the preface
  // carries for tools: their declarations and each assistant call.
  static const String _accountingTemplate =
      '[{% for message in messages %}'
      '{"role":{{ message["role"] | tojson }},'
      '"content":{{ (message["content"] or "") | tojson }}}'
      '{% if not loop.last %},{% endif %}'
      '{% endfor %}]';
  static const String _toolAccountingTemplate =
      '[{% if tools %}{"tools":{{ tools | tojson }}},{% endif %}'
      '{% for message in messages %}'
      '{"role":{{ message["role"] | tojson }},'
      '"content":{{ (message["content"] or "") | tojson }}'
      '{% if message["tool_calls"] %}'
      '{% if message["reasoning_content"] %}'
      ',"reasoning_content":{{ message["reasoning_content"] | tojson }}'
      '{% endif %}'
      ',"tool_calls":{{ message["tool_calls"] | tojson }}'
      '{% endif %}'
      '{% if message["name"] %},"name":{{ message["name"] | tojson }}{% endif %}'
      '}'
      '{% if not loop.last %},{% endif %}'
      '{% endfor %}]';

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async {
    final metadata = await super.modelMetadata(modelHandle);
    metadata[parsingChatTemplateMetadataKey] = _accountingTemplate;
    metadata['tokenizer.chat_template'] = _toolAccountingTemplate;
    if (supportsToolCalling) {
      metadata['llamadart.litert_lm_web.chat_scope'] =
          'system-user-assistant-text-and-tools';
    }
    metadata['llamadart.litert_lm_web.prompt_accounting'] =
        'utf8-byte-estimate';
    return metadata;
  }

  @override
  bool get _textHistoryEnabled => true;

  @override
  bool get supportsMultiTurnChat => _isReady && _supportsTextHistory;

  @override
  bool get supportsNativeChatGeneration => isReady;

  /// True once the loaded runtime has passed the history probe and reads
  /// `preface.tools` when it creates a conversation.
  @override
  bool get supportsToolCalling => _isReady && _supportsToolDeclarations;

  @override
  bool get requiresStructuredChatInput => true;

  @override
  void validateChatMessages(List<LlamaChatMessage> messages) {
    _wireMessages(messages);
  }

  static const String _runtime = 'LiteRT-LM Web @litert-lm/core@0.19.0';

  /// [messages] as `@litert-lm/core@0.19.0` `Message` objects, in the shape
  /// native LiteRT-LM sends: assistant calls in `tool_calls`, results as
  /// `tool_response` parts of one `tool` message.
  List<Map<String, Object?>> _wireMessages(List<LlamaChatMessage> messages) {
    if (messages.isEmpty) {
      throw LlamaUnsupportedException(
        '$_runtime needs a final user text or tool result message.',
      );
    }
    final wire = <Map<String, Object?>>[];
    var carriesTools = false;
    for (final message in messages) {
      final role = message.roleEnum?.name ?? message.roleString;
      bool allowed(LlamaContentPart part) => switch (role) {
        'system' || 'user' => part is LlamaTextContent,
        'assistant' =>
          part is LlamaTextContent ||
              part is LlamaThinkingContent ||
              part is LlamaToolCallContent,
        'tool' => part is LlamaToolResultContent,
        _ => false,
      };
      if (!const ['system', 'user', 'assistant', 'tool'].contains(role) ||
          !message.parts.every(allowed)) {
        throw LlamaUnsupportedException(
          '$_runtime supports system/user/assistant text, assistant tool '
          'calls and tool results; media, user/system thinking content and '
          'text in a tool message are unavailable.',
        );
      }
      final calls = message.parts.whereType<LlamaToolCallContent>();
      if (role == 'tool') {
        final results = message.parts.cast<LlamaToolResultContent>();
        if (results.isEmpty) {
          throw LlamaUnsupportedException(
            '$_runtime needs a LlamaToolResultContent in a tool message.',
          );
        }
        if (results.any((result) => result.content.isNotEmpty)) {
          throw LlamaUnsupportedException(
            '$_runtime does not take LlamaToolResultContent.content. Return '
            'the tool output as its result.',
          );
        }
        carriesTools = true;
        wire.add({
          'role': 'tool',
          'content': [
            for (final result in results)
              {
                'type': 'tool_response',
                'name': result.name,
                'response': result.result,
              },
          ],
        });
      } else if (calls.isNotEmpty) {
        carriesTools = true;
        final thinking = message.parts.whereType<LlamaThinkingContent>();
        wire.add({
          'role': 'assistant',
          // Text only: `content` would repeat each call's raw JSON.
          'content': message.parts
              .whereType<LlamaTextContent>()
              .map((part) => part.text)
              .join(),
          if (thinking.isNotEmpty)
            'reasoning_content': thinking
                .map((part) => part.thinking)
                .join('\n'),
          'tool_calls': [
            for (final call in calls)
              {
                'type': 'function',
                'function': {'name': call.name, 'arguments': call.arguments},
              },
          ],
        });
      } else {
        wire.add({'role': role, 'content': message.content});
      }
    }
    if (!const ['user', 'tool'].contains(wire.last['role'])) {
      throw LlamaUnsupportedException(
        '$_runtime chat needs a final user or tool result message; assistant '
        'continuation and system-only generation are unavailable.',
      );
    }
    if (wire.length > 1 && !supportsMultiTurnChat) {
      throw LlamaUnsupportedException(
        'The loaded LiteRT-LM Web runtime did not consume preface.messages '
        'or expose getHistory. Text history and system prompts require '
        'the published @litert-lm/core@0.19.0 conversation APIs.',
      );
    }
    if (carriesTools && !supportsToolCalling) throw _toolsUnavailable();
    return wire;
  }

  LlamaUnsupportedException _toolsUnavailable() => LlamaUnsupportedException(
    'The loaded LiteRT-LM Web runtime did not read preface.tools when it '
    'created a conversation, so tool calling is unavailable. It requires '
    'the published @litert-lm/core@0.19.0 conversation tools and a backend '
    'from LlamaBackend.withTextHistory().',
  );

  @override
  Stream<List<int>> generateChat(
    int contextHandle,
    List<LlamaChatMessage> messages,
    GenerationParams params, {
    List<ToolDefinition>? tools,
    ToolChoice toolChoice = ToolChoice.auto,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? chatTemplateKwargs,
    String? sourceLangCode,
    String? targetLangCode,
    DateTime? templateNow,
  }) {
    final List<Map<String, Object?>> wire;
    final List<Map<String, dynamic>> declarations;
    try {
      if (toolChoice == ToolChoice.required || parallelToolCalls) {
        throw LlamaUnsupportedException(
          '$_runtime exposes neither ToolChoice.required enforcement nor a '
          'parallel tool-call switch. Use ToolChoice.auto with '
          'parallelToolCalls false, or a grammar-capable runtime such as '
          'llama.cpp.',
        );
      }
      if (!enableThinking ||
          (chatTemplateKwargs?.isNotEmpty ?? false) ||
          sourceLangCode != null ||
          targetLangCode != null ||
          templateNow != null) {
        throw LlamaUnsupportedException(
          '$_runtime chat does not expose thinking, template kwargs, '
          'language or template-clock controls. Use the model defaults.',
        );
      }
      // As on native LiteRT-LM, ToolChoice.none declares no tools.
      declarations = toolChoice == ToolChoice.none
          ? const []
          : [
              for (final tool in tools ?? const <ToolDefinition>[])
                tool.toJson(),
            ];
      if (declarations.isNotEmpty && !supportsToolCalling) {
        throw _toolsUnavailable();
      }
      wire = _wireMessages(messages);
    } on LlamaException catch (error, stackTrace) {
      return Stream.error(error, stackTrace);
    }
    final last = wire.last;
    return _generateWithHistory(
      contextHandle,
      last['role'] == 'user' ? (last['content'] as String).toJS : last.jsify()!,
      params,
      history: wire.sublist(0, wire.length - 1),
      tools: declarations,
    );
  }
}

/// One [LiteRtLmBackend.generate] call.
final class _LiteRtLmWebRun {
  _LiteRtLmWebRun({this.reportsToolCalls = false});

  /// Whether runtime-parsed tool calls go to [toolCalls] rather than into the
  /// text.
  final bool reportsToolCalls;

  /// The runtime-parsed tool calls so far, in order.
  final List<LlamaCompletionChunkToolCall> toolCalls = [];

  /// The budget that ended this run, or null when it finished, was cancelled
  /// or stopped at a stop sequence.
  BackendGenerationLimit? limit;

  /// Completes with true when a queued run may start, or false when it ends
  /// without starting.
  final Completer<bool> admission = Completer<bool>();
}

/// The runtime-parsed tool calls of each finished generation stream.
final class _LiteRtLmWebRuntimeToolCalls implements BackendRuntimeToolCalls {
  final Expando<List<LlamaCompletionChunkToolCall>> calls =
      Expando<List<LlamaCompletionChunkToolCall>>();

  @override
  List<LlamaCompletionChunkToolCall>? runtimeToolCallsOf(
    Stream<List<int>> generation,
  ) => calls[generation];
}

/// The token budget that ended each finished generation stream.
final class _LiteRtLmWebGenerationLimits
    implements BackendGenerationLimitReporting {
  final Expando<BackendGenerationLimit> limits =
      Expando<BackendGenerationLimit>();

  @override
  BackendGenerationLimit? generationLimitOf(Stream<List<int>> generation) =>
      limits[generation];
}

@JS()
extension type _LiteRtLmConsoleGuard._(JSObject _) implements JSObject {
  external void restore();
}

@JS()
extension type _LiteRtLmEngineConstructor._(JSObject _) implements JSObject {
  external JSPromise<_LiteRtLmWebEngine> create(JSObject settings);
}

@JS()
extension type _LiteRtLmWebEngine._(JSObject _) implements JSObject {
  external JSPromise<_LiteRtLmWebConversation> createConversation([
    JSObject? config,
  ]);

  @JS('delete')
  external JSPromise<JSAny?>? deleteEngine();
}

@JS()
extension type _LiteRtLmWebConversation._(JSObject _) implements JSObject {
  external _LiteRtLmReadableStream sendMessageStreaming(JSAny message);

  external void cancel();

  external JSPromise<JSAny?> getBenchmarkInfo();

  external JSPromise<JSAny?> getTokenCount();

  @JS('delete')
  external JSPromise<JSAny?>? deleteConversation();
}

@JS()
extension type _LiteRtLmReadableStream._(JSObject _) implements JSObject {
  external _LiteRtLmReadableStreamReader getReader();
}

@JS()
extension type _LiteRtLmReadableStreamReader._(JSObject _) implements JSObject {
  external JSPromise<_LiteRtLmStreamReadResult> read();

  external JSPromise<JSAny?>? cancel();

  external void releaseLock();
}

@JS()
extension type _LiteRtLmStreamReadResult._(JSObject _) implements JSObject {
  external bool get done;

  external JSAny? get value;
}

/// Throws [LlamaUnsupportedException] for what a LiteRT-LM Web load rejects
/// from [params] alone, before it fetches the model: an NPU, and the
/// embedding engine, unqualified on `@litert-lm/core@0.19.0`.
/// [preferredBackend] is the backend's deprecated preferred backend.
void liteRtLmWebCheckLoad(ModelParams params, {String? preferredBackend}) {
  if (params.liteRtLmEmbeddingEngine) {
    throw LlamaUnsupportedException(
      liteRtLmWebBackendName(params, preferredBackend: preferredBackend) ==
              'cpu'
          ? 'LiteRT-LM Web CPU embeddings are unavailable in @litert-lm/core@0.19.0: upstream streams text-encoder weights only for WebGPU (Failed to get external weight).'
          : 'LiteRT-LM WebGPU embeddings are unavailable in @litert-lm/core@0.19.0: EmbeddingGemma-2 qualification missed native CPU parity (cosine >= 0.9998 and relative L2 < 2%). A qualified runtime is required.',
    );
  }
  _liteRtLmWebDeviceBackendName(params, preferredBackend);
}

/// The LiteRT-LM Web backend, `cpu` or `gpu`, that [params] selects on a
/// backend with the deprecated [preferredBackend].
String liteRtLmWebBackendName(ModelParams params, {String? preferredBackend}) {
  final device = _liteRtLmWebDeviceBackendName(params, preferredBackend);
  if (device != null) {
    return device;
  }
  final explicit = preferredBackend ?? params.liteRtLmBackend.nativeName;
  if (explicit != null) {
    if (explicit == 'npu') {
      throw LlamaUnsupportedException(
        'LiteRtLmBackendPreference.npu is not available for LiteRT-LM on the '
        'Web, which runs on the CPU or WebGPU; only LiteRT-LM on Android has '
        'an NPU backend. Use ModelParams.device auto, cpu or gpu.',
      );
    }
    return explicit;
  }
  if (resolveGpuLayerCount(params.gpuLayers) == 0) {
    return 'cpu';
  }
  return _liteRtLmWebBackendForGpuPreference(params.preferredBackend);
}

/// The LiteRT-LM Web backend an explicit [ModelParams.device] of [params]
/// requires, or null for [ComputeDevice.auto]; throws for an NPU, or a
/// device combined with the deprecated [preferredBackend].
String? _liteRtLmWebDeviceBackendName(
  ModelParams params,
  String? preferredBackend,
) {
  final device = params.device;
  if (device == ComputeDevice.auto) {
    return null;
  }
  if (preferredBackend != null) {
    throw LlamaUnsupportedException(
      'ModelParams.device ${device.name} cannot be combined with the '
      'deprecated LiteRtLmBackend(preferredBackend: $preferredBackend). '
      'Set only ModelParams.device.',
    );
  }
  return switch (device) {
    ComputeDevice.cpu => 'cpu',
    ComputeDevice.gpu => 'gpu',
    ComputeDevice.npu => throw LlamaUnsupportedException(
      'ComputeDevice.npu is not available for LiteRT-LM on the Web, which '
      'runs on the CPU or WebGPU; only LiteRT-LM on Android has an NPU '
      'backend. Use ComputeDevice.auto, cpu or gpu.',
    ),
    ComputeDevice.auto => null,
  };
}

/// The LiteRT-LM Web backend a [ModelParams.preferredBackend] selects.
String _liteRtLmWebBackendForGpuPreference(GpuBackend backend) {
  return switch (backend) {
    GpuBackend.cpu || GpuBackend.blas => 'cpu',
    GpuBackend.auto ||
    GpuBackend.vulkan ||
    GpuBackend.metal ||
    GpuBackend.cuda ||
    GpuBackend.opencl ||
    GpuBackend.hip => 'gpu',
  };
}

/// The percent-decoded last path segment of [url], or null when it is empty
/// or not valid UTF-8 once decoded, contains URL delimiters, or repeats a
/// userinfo credential of [url].
String? _modelUrlName(String url) {
  final String? name;
  try {
    name = Uri.tryParse(url)?.pathSegments.lastOrNull;
  } on FormatException {
    return null;
  }
  if (name == null || name.isEmpty || RegExp(r'[/\\?#@;&=]').hasMatch(name)) {
    return null;
  }
  return _urlCredentials(url).any(name.contains) ? null : name;
}

/// The userinfo and password of [url] as the browser parses it, as written
/// and percent-decoded. A protocol-relative [url] is read with an `https:`
/// scheme.
Set<String> _urlCredentials(String url) {
  final parsed = _parsedUrl(url.startsWith('//') ? 'https:$url' : url);
  if (parsed == null) return const <String>{};
  final password = parsed.password;
  return <String>{
    for (final secret in <String>[
      password.isEmpty ? parsed.username : '${parsed.username}:$password',
      password,
    ])
      if (secret.isNotEmpty) ...<String>{
        secret,
        ?_percentDecodedOrNull(secret),
      },
  };
}

// `URL.parse` is missing from Safari before 18.
URL? _parsedUrl(String url) {
  try {
    return URL(url);
  } catch (_) {
    return null;
  }
}

String? _percentDecodedOrNull(String text) {
  try {
    return Uri.decodeComponent(text);
  } on ArgumentError {
    return null;
  } on FormatException {
    return null;
  }
}

/// [url] without userinfo, query or fragment.
///
/// An absolute [url] is shown as the browser parses it, which also strips the
/// userinfo of forms such as `https:user:pass@host/m` that have no `//`
/// before the authority, and without its host and path when they repeat a
/// userinfo credential. An opaque URL such as `blob:` or `data:` shows only
/// its scheme, since its path can hold a whole URL. A relative [url] is shown
/// as given, not resolved against the page.
String _modelUrlDisplay(String url) {
  final parsed = _parsedUrl(url);
  if (parsed == null) return sourceUrlDisplay(url);
  final protocol = parsed.protocol;
  if (!parsed.href.startsWith('$protocol//')) return protocol;
  final credentials = _urlCredentials(url);
  parsed
    ..username = ''
    ..password = ''
    ..search = ''
    ..hash = '';
  final display = parsed.href;
  return credentials.any(display.contains) ? '$protocol//' : display;
}
