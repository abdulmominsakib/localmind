@JS()
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:web/web.dart';

import '../../core/models/chat/content_part.dart';
import '../../core/cache_policy.dart';
import '../../core/models/config/flash_attention.dart';
import '../../core/models/config/gpu_backend.dart';
import '../../core/models/config/kv_cache_type.dart';
import '../../core/models/config/log_level.dart';
import '../../core/models/inference/generation_params.dart';
import '../../core/models/inference/model_params.dart';
import '../backend.dart';

/// Web LiteRT-LM backend for `.litertlm` models.
///
/// This backend wraps the official `@litert-lm/core` browser API. Apps can
/// preload the package and expose `window.LiteRtLmEngine = module.Engine`, or
/// set `window.__llamadartLiteRtLmModuleUrl` to a module URL such as
/// `https://cdn.jsdelivr.net/npm/@litert-lm/core@0.15.0/+esm`.
class LiteRtLmBackend
    implements
        LlamaBackend,
        BackendAvailability,
        BackendGrammarConstraintsSupport,
        BackendEmbeddings,
        BackendEmbeddingsSupport,
        BackendStatePersistence,
        BackendStatePersistenceSupport {
  static const Duration _engineReadyTimeout = Duration(seconds: 12);
  static const Duration _enginePollInterval = Duration(milliseconds: 100);
  static const String _defaultModelCacheName =
      'llamadart-webgpu-model-cache-v1';
  // The current @litert-lm/core web API accepts one string prompt and applies
  // the model's chat wrapper internally. Until the JS API exposes structured
  // messages/tools, keep the Dart template intentionally single-turn.
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
  LlamaLogLevel _logLevel = LlamaLogLevel.warn;
  bool _isReady = false;
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
  String? _chatTemplate;

  /// Creates a web LiteRT-LM backend.
  ///
  /// [initialSendPort] is accepted for API compatibility with the native
  /// backend and ignored on web.
  LiteRtLmBackend({
    Object? initialSendPort,
    String? preferredBackend,
    String? moduleUrl,
    Duration? readyTimeout,
  }) : _moduleUrl = moduleUrl,
       _readyTimeout = readyTimeout ?? _engineReadyTimeout,
       _preferredBackend = _normalizeBackendOverride(preferredBackend);

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
    _validateLiteRtLmSource(url);
    _validateModelParams(params);
    final backend = _resolveBackendName(params);

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
      _modelHandle = _nextModelHandle++;
      _isReady = true;
      onProgress?.call(1);
      return _modelHandle!;
    } catch (error) {
      _isReady = false;
      _modelHandle = null;
      _contextHandle = null;
      _modelUrl = null;
      _modelSource = null;
      _modelCacheState = null;
      _modelParams = null;
      _chatTemplate = null;
      _activeBackend = null;
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
    _hasContext = false;
    _contextHandle = null;
    final conversation = _activeConversation;
    _activeConversation = null;
    if (conversation != null) {
      await _deleteConversation(conversation);
    }
  }

  @override
  Future<int> getContextSize(int contextHandle) async {
    _requireContextHandle(contextHandle);
    return _modelParams?.contextSize ?? 0;
  }

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async* {
    final engine = _requireContextHandle(contextHandle);
    if (_hasMediaParts(parts)) {
      throw UnsupportedError(
        'LiteRtLmBackend web does not support media parts.',
      );
    }
    _validateGenerationParams(params);
    if (params.maxTokens <= 0) {
      return;
    }
    if (_activeConversation != null) {
      throw StateError('LiteRT-LM web generation is already in progress.');
    }

    _cancelRequested = false;
    final conversation = await engine
        .createConversation(_createConversationConfig(params))
        .toDart;
    _activeConversation = conversation;

    final stopSequences = params.stopSequences
        .where((sequence) => sequence.isNotEmpty)
        .toList(growable: false);
    try {
      final stream = _withScopedConsoleGuardedStream(
        _streamConversation(conversation, prompt),
      );
      await for (final chunk in _applyStopSequences(
        stream,
        stopSequences,
        onStop: cancelGeneration,
      )) {
        if (_cancelRequested) {
          break;
        }
        yield chunk;
      }
    } finally {
      if (identical(_activeConversation, conversation)) {
        _activeConversation = null;
      }
      await _deleteConversation(conversation);
    }
  }

  @override
  void cancelGeneration() {
    _cancelRequested = true;
    try {
      _activeConversation?.cancel();
    } catch (_) {
      // Preserve the caller-visible generation error, if any.
    }
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
      'llamadart.litert_lm_web.chat_scope': 'single-turn-text',
      'llamadart.litert_lm_web.structured_chat': 'false',
      'tokenizer.chat_template':
          _chatTemplate ?? _passthroughLatestMessageTemplate,
    };
    if (modelUrl != null) {
      final modelName = Uri.tryParse(modelUrl)?.pathSegments.last;
      if (modelName != null && modelName.isNotEmpty) {
        metadata['general.name'] = Uri.decodeComponent(modelName);
      }
      metadata['litert_lm.model_url'] = modelUrl;
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
  Future<void> setLoraAdapter(int contextHandle, String path, double scale) {
    _requireContextHandle(contextHandle);
    throw UnsupportedError(
      'LiteRtLmBackend web does not support LoRA adapters.',
    );
  }

  @override
  Future<void> removeLoraAdapter(int contextHandle, String path) {
    _requireContextHandle(contextHandle);
    throw UnsupportedError(
      'LiteRtLmBackend web does not support LoRA adapters.',
    );
  }

  @override
  Future<void> clearLoraAdapters(int contextHandle) {
    _requireContextHandle(contextHandle);
    throw UnsupportedError(
      'LiteRtLmBackend web does not support LoRA adapters.',
    );
  }

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
  Future<int?> multimodalContextCreate(int modelHandle, String mmProjPath) {
    _requireModelHandle(modelHandle);
    throw UnsupportedError(
      'LiteRtLmBackend web does not support multimodal input.',
    );
  }

  @override
  Future<void> multimodalContextFree(int mmContextHandle) {
    throw UnsupportedError(
      'LiteRtLmBackend web does not support multimodal input.',
    );
  }

  @override
  Future<bool> supportsVision(int mmContextHandle) {
    throw UnsupportedError(
      'LiteRtLmBackend web does not support multimodal input.',
    );
  }

  @override
  Future<bool> supportsAudio(int mmContextHandle) {
    throw UnsupportedError(
      'LiteRtLmBackend web does not support multimodal input.',
    );
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
    if (customTemplate != null && customTemplate.isNotEmpty) {
      throw UnsupportedError(
        'LiteRtLmBackend web does not apply custom chat templates directly.',
      );
    }

    if (messages.isEmpty) {
      return '';
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

    throw StateError(
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
              StateError('LiteRT-LM web module load failed: $err'),
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
            StateError('Failed to load LiteRT-LM web module script'),
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
    settings.setProperty('backend'.toJS, _backendValueFor(backend).toJS);

    final executorSettings = JSObject();
    executorSettings.setProperty('maxNumTokens'.toJS, params.contextSize.toJS);
    settings.setProperty('mainExecutorSettings'.toJS, executorSettings);
    return settings;
  }

  JSObject _createConversationConfig(GenerationParams params) {
    final samplerParams = JSObject();
    samplerParams.setProperty('k'.toJS, params.topK.toJS);
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
      _backendValueFor(_activeBackend ?? 'gpu').toJS,
    );

    final config = JSObject();
    config.setProperty('sessionConfig'.toJS, sessionConfig);
    return config;
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
    String prompt,
  ) async* {
    final reader = conversation.sendMessageStreaming(prompt).getReader();
    try {
      while (!_cancelRequested) {
        final result = await reader.read().toDart;
        if (result.done) {
          break;
        }

        final text = _extractTextChunk(result.value);
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

  String _extractTextChunk(JSAny? value) {
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

    final content = obj.getProperty('content'.toJS);
    if (content == null || !content.isA<JSArray>()) {
      return '';
    }

    final buffer = StringBuffer();
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
    return buffer.toString();
  }

  bool _hasMediaParts(List<LlamaContentPart>? parts) {
    if (parts == null) {
      return false;
    }
    return parts.any(
      (part) => part is LlamaImageContent || part is LlamaAudioContent,
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
        throw UnsupportedError(
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
            throw UnsupportedError(
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
    final conversation = _activeConversation;
    _activeConversation = null;
    if (conversation != null) {
      await _deleteConversation(conversation);
    }

    final engine = _engine;
    _engine = null;
    _isReady = false;
    _hasContext = false;
    _modelHandle = null;
    _contextHandle = null;
    _modelUrl = null;
    _modelSource = null;
    _modelCacheState = null;
    _modelParams = null;
    _chatTemplate = null;
    _activeBackend = null;
    if (engine != null) {
      final result = engine.deleteEngine();
      if (result != null) {
        await result.toDart;
      }
    }
  }

  Future<void> _deleteConversation(
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
    params.validate();
    final unsupported = <String>[];
    if (params.contextSize <= 0) {
      unsupported.add('contextSize=${params.contextSize}');
    }
    if (params.gpuLayers > 0 && params.gpuLayers != ModelParams.maxGpuLayers) {
      unsupported.add('gpuLayers=${params.gpuLayers}');
    }
    if (params.splitMode != ModelSplitMode.layer) {
      unsupported.add('splitMode');
    }
    if (params.mainGpu != 0) {
      unsupported.add('mainGpu');
    }
    if (params.loras.isNotEmpty) {
      unsupported.add('loras');
    }
    if (params.liteRtLmActivationDataType != null) {
      unsupported.add('liteRtLmActivationDataType');
    }
    if (params.liteRtLmPrefillChunkSize != null) {
      unsupported.add('liteRtLmPrefillChunkSize');
    }
    if (params.liteRtLmParallelFileSectionLoading != null) {
      unsupported.add('liteRtLmParallelFileSectionLoading');
    }
    if (params.liteRtLmDispatchLibDir != null) {
      unsupported.add('liteRtLmDispatchLibDir');
    }
    if (params.numberOfThreads != 0) {
      unsupported.add('numberOfThreads');
    }
    if (params.numberOfThreadsBatch != 0) {
      unsupported.add('numberOfThreadsBatch');
    }
    if (params.batchSize > 0) {
      unsupported.add('batchSize');
    }
    if (params.microBatchSize > 0) {
      unsupported.add('microBatchSize');
    }
    if (params.maxParallelSequences != 1) {
      unsupported.add('maxParallelSequences');
    }
    if (!params.useMmap) {
      unsupported.add('useMmap=false');
    }
    if (params.useMlock) {
      unsupported.add('useMlock');
    }
    if (params.flashAttention != FlashAttention.auto) {
      unsupported.add('flashAttention');
    }
    if (params.cacheTypeK != KvCacheType.f16) {
      unsupported.add('cacheTypeK');
    }
    if (params.cacheTypeV != KvCacheType.f16) {
      unsupported.add('cacheTypeV');
    }
    if (params.kvUnified != null) {
      unsupported.add('kvUnified');
    }
    if (params.ropeFrequencyBase != null) {
      unsupported.add('ropeFrequencyBase');
    }
    if (params.ropeFrequencyScale != null) {
      unsupported.add('ropeFrequencyScale');
    }

    if (unsupported.isEmpty) {
      return;
    }
    throw ArgumentError(
      'LiteRtLmBackend web does not support these native or '
      'llama.cpp-specific ModelParams: '
      '${unsupported.join(', ')}. Supported LiteRT-LM web load options are '
      'contextSize, chatTemplate, preferredBackend, all-or-CPU gpuLayers '
      'hints, and liteRtLmBackend CPU/GPU selection.',
    );
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
    throw UnsupportedError(
      'LiteRtLmBackend web does not support llama.cpp-specific '
      'GenerationParams: ${unsupported.join(', ')}. Supported LiteRT-LM web '
      'generation options are maxTokens, temp, topK, topP, seed, and '
      'stopSequences.',
    );
  }

  String _resolveBackendName(ModelParams params) {
    final explicit = _preferredBackend ?? params.liteRtLmBackend.nativeName;
    if (explicit != null) {
      if (explicit == 'npu') {
        throw UnsupportedError('LiteRT-LM web does not support NPU backend.');
      }
      return explicit;
    }
    if (params.gpuLayers <= 0) {
      return 'cpu';
    }
    return _backendNameForGpuPreference(params.preferredBackend);
  }

  String? _explicitBackendName(ModelParams params) {
    final explicit = params.liteRtLmBackend.nativeName;
    if (explicit != null) {
      return explicit;
    }
    if (params.gpuLayers <= 0) {
      return 'cpu';
    }
    if (params.preferredBackend != GpuBackend.auto) {
      return _backendNameForGpuPreference(params.preferredBackend);
    }
    return null;
  }

  String _backendNameForGpuPreference(GpuBackend backend) {
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

  int _backendValueFor(String backend) {
    final moduleBackend = _backendValueFromGlobalEnum(backend);
    if (moduleBackend != null) {
      return moduleBackend;
    }
    return switch (backend) {
      'cpu' => _backendCpu,
      // @litert-lm/core web bundles default to GPU_ARTISAN for streaming
      // browser execution. The Gemma 4 web bundle only loads through that path.
      'gpu' => _backendGpuArtisan,
      _ => _backendGpuArtisan,
    };
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
  external _LiteRtLmReadableStream sendMessageStreaming(String message);

  external void cancel();

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
