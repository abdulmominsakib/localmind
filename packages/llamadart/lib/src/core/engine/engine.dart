import 'dart:async';
import 'dart:convert';

import '../../backends/backend.dart';
import 'chat_completion_request_planner.dart';
import 'chat_completion_stream_parser.dart';
import 'chat_template_renderer.dart';
import '../exceptions.dart';
import '../models/config/gpu_backend.dart';
import '../models/config/gpu_device_info.dart';
import '../models/config/log_level.dart';
import '../models/diagnostics/model_file_type.dart';
import '../models/chat/chat_message.dart';
import '../models/chat/completion_chunk.dart';
import '../models/chat/content_part.dart';
import '../models/chat/chat_template_result.dart';
import '../llama_logger.dart';

import '../models/inference/model_params.dart';
import '../models/inference/generation_params.dart';
import '../models/inference/structured_output.dart';
import '../models/inference/tool_choice.dart';
import '../models/model_load_options.dart';
import '../models/model_resolver.dart';
import '../models/model_source.dart';
import '../models/download/model_download_manager.dart';
import '../models/tools/tool_definition.dart';

/// Stateless chat completions engine (like OpenAI's Chat Completions API).
///
/// [LlamaEngine] is the primary API for chat-based inference. Each call to
/// [create] is stateless - you must pass the full conversation history.
/// For automatic history management, use [ChatSession] instead.
///
/// Example (OpenAI-style stateless usage):
/// ```dart
/// final engine = LlamaEngine(LlamaBackend());
/// await engine.loadModel('path/to/model.gguf'); // or model.litertlm on native
///
/// // Build messages array (you manage history)
/// final messages = [
///   LlamaChatMessage.fromText(role: LlamaChatRole.system, text: 'You are helpful.'),
///   LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hello!'),
/// ];
///
/// // Create completion
/// final response = StringBuffer();
/// await for (final chunk in engine.create(messages)) {
///   final text = chunk.choices.first.delta.content;
///   if (text != null) {
///     response.write(text);
///   }
/// }
///
/// // Append response and continue conversation
/// messages.add(
///   LlamaChatMessage.fromText(
///     role: LlamaChatRole.assistant,
///     text: response.toString(),
///   ),
/// );
/// messages.add(LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Follow up?'));
/// final response2 = StringBuffer();
/// await for (final chunk in engine.create(messages)) {
///   final text = chunk.choices.first.delta.content;
///   if (text != null) {
///     response2.write(text);
///   }
/// }
/// ```
class LlamaEngine {
  /// The backend implementation used for inference.
  final LlamaBackend backend;

  /// Resolves source-aware model loading requests.
  final ModelResolver modelResolver;

  /// Downloads and caches remote model sources for native/file-backed backends.
  final ModelDownloadManager modelDownloadManager;
  int? _modelHandle;
  int? _contextHandle;
  int? _mmContextHandle;
  // Serializes multimodal projector load/unload so concurrent calls cannot
  // race the native create/free (which could leak or double-free the context).
  Future<void> _mmLifecycle = Future<void>.value();
  Future<void>? _modelLifecycleOperation;
  bool _isReady = false;
  String? _modelPath;
  Map<String, String>? _cachedModelMetadata;
  LlamaLogLevel _dartLogLevel = LlamaLogLevel.none;
  LlamaLogLevel _nativeLogLevel = LlamaLogLevel.none;

  /// Configures logging for the library.
  ///
  /// [level] determines which logs are output.
  /// [handler] is an optional custom callback. If null and level != none,
  /// logs are printed to stdout.
  static void configureLogging({
    LlamaLogLevel level = LlamaLogLevel.none,
    LlamaLogHandler? handler,
  }) {
    LlamaLogger.instance.setLevel(level);
    LlamaLogger.instance.setHandler(handler);
  }

  /// Creates a new [LlamaEngine] instance with the given [backend].
  LlamaEngine(
    this.backend, {
    ModelResolver? modelResolver,
    ModelDownloadManager? modelDownloadManager,
  }) : modelResolver = modelResolver ?? const DefaultModelResolver(),
       modelDownloadManager =
           modelDownloadManager ?? DefaultModelDownloadManager();

  /// Sets both Dart and native log levels to [level].
  ///
  /// For independent control, use [setDartLogLevel] and [setNativeLogLevel].
  Future<void> setLogLevel(LlamaLogLevel level) async {
    await setDartLogLevel(level);
    await setNativeLogLevel(level);
  }

  /// Sets only the Dart-side logger level.
  Future<void> setDartLogLevel(LlamaLogLevel level) async {
    _dartLogLevel = level;
    LlamaLogger.instance.setLevel(level);
  }

  /// Sets only the native backend logger level.
  Future<void> setNativeLogLevel(LlamaLogLevel level) async {
    _nativeLogLevel = level;
    await backend.setLogLevel(level);
  }

  /// Current Dart-side logger level.
  LlamaLogLevel get dartLogLevel => _dartLogLevel;

  /// Current native backend logger level.
  LlamaLogLevel get nativeLogLevel => _nativeLogLevel;

  // ============================================================
  // MODEL LIFECYCLE
  // ============================================================

  /// Whether the engine is initialized and ready for inference.
  bool get isReady => _isReady;

  /// Loads a model from a local [path].
  ///
  /// Optionally provide [ModelParams] to configure context size, GPU offloading,
  /// and more.
  Future<void> loadModel(
    String path, {
    ModelParams modelParams = const ModelParams(),
  }) {
    return _withModelLifecycle(
      'load a model',
      () => _loadModel(path, modelParams: modelParams),
    );
  }

  Future<void> _loadModel(
    String path, {
    ModelParams modelParams = const ModelParams(),
  }) async {
    _ensureNotReady();
    final modelName = _displayNameForSource(path);
    LlamaLogger.instance.info('Loading model: $modelName');

    if (backend.supportsUrlLoading) {
      LlamaLogger.instance.info(
        'Backend supports URL loading, attempting loadModelFromUrl.',
      );
      return _loadModelFromUrl(path, modelParams: modelParams);
    }

    try {
      await backend.setLogLevel(_nativeLogLevel);
      _modelPath = path;
      _cachedModelMetadata = null;
      _modelHandle = await backend.modelLoad(path, modelParams);
      _contextHandle = await backend.contextCreate(_modelHandle!, modelParams);
      _isReady = true;
      LlamaLogger.instance.info(
        'Model $modelName loaded successfully from $path',
      );
    } catch (e, stackTrace) {
      await _cleanupFailedLoadState();
      LlamaLogger.instance.error(
        'Failed to load model $modelName from $path',
        e,
        stackTrace,
      );
      if (e is LlamaUnsupportedException) {
        rethrow;
      }
      if (e is UnsupportedError) {
        throw _unsupportedBackendOperation('Model loading', e);
      }
      throw LlamaModelException('Failed to load model from $path', e);
    }
  }

  /// Loads a model from a structured [source].
  ///
  /// Local path sources are dispatched through [loadModel]. Remote URL targets
  /// use the native download/cache manager on file-backed backends, then load
  /// the cached local file. URL-capable web backends keep using
  /// [loadModelFromUrl] for unauthenticated prefer-cached requests.
  Future<void> loadModelSource(
    ModelSource source, {
    ModelParams modelParams = const ModelParams(),
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    final target = await modelResolver.resolve(
      source,
      ModelResolveRequest(options: options, onProgress: onProgress),
    );
    _throwIfSourceLoadCancelled(options);

    switch (target) {
      case LocalModelFile(:final path):
        if (backend.supportsUrlLoading) {
          throw LlamaUnsupportedException(
            'Explicit local model paths are not supported by URL-loading backends.',
          );
        }
        final localSource = ModelSource.path(path);
        final entry = await modelDownloadManager.ensureModel(
          localSource,
          options: options,
          onProgress: onProgress,
        );
        _throwIfSourceLoadCancelled(options);
        return loadModel(entry.filePath, modelParams: modelParams);
      case RemoteModelUrl(:final url, :final useBrowserCache):
        if (!useBrowserCache) {
          throw LlamaUnsupportedException(
            'Remote model loading without browser/backend cache is not supported yet.',
          );
        }
        if (!backend.supportsUrlLoading) {
          final downloadSource = source.isRemote
              ? source.withResolvedUri(url)
              : ModelSource.url(url, fileName: source.fileName);
          final entry = await modelDownloadManager.ensureModel(
            downloadSource,
            options: options,
            onProgress: onProgress,
          );
          _throwIfSourceLoadCancelled(options);
          return loadModel(entry.filePath, modelParams: modelParams);
        }
        _rejectUnsupportedUrlBackendOptions(options);
        return loadModelFromUrl(
          url.toString(),
          modelParams: modelParams,
          onProgress: onProgress == null
              ? null
              : (progress) =>
                    onProgress(ModelDownloadProgress.fraction(progress)),
        );
    }
  }

  /// Loads a model from a [url].
  ///
  /// This is typically used on the Web platform. Use [ModelParams] to
  /// configure loading options.
  Future<void> loadModelFromUrl(
    String url, {
    ModelParams modelParams = const ModelParams(),
    Function(double progress)? onProgress,
  }) {
    return _withModelLifecycle(
      'load a model from URL',
      () => _loadModelFromUrl(
        url,
        modelParams: modelParams,
        onProgress: onProgress,
      ),
    );
  }

  Future<void> _loadModelFromUrl(
    String url, {
    ModelParams modelParams = const ModelParams(),
    Function(double progress)? onProgress,
  }) async {
    _ensureNotReady();
    final modelName = _displayNameForSource(url);
    final redactedUrl = _redactedUriForLogs(url);
    LlamaLogger.instance.info('Loading model from URL: $modelName');

    if (!backend.supportsUrlLoading) {
      throw LlamaUnsupportedException(
        'loadModelFromUrl requires a backend that supports URL loading.',
      );
    }

    try {
      await backend.setLogLevel(_nativeLogLevel);
      _modelPath = redactedUrl;
      _cachedModelMetadata = null;

      _modelHandle = await backend.modelLoadFromUrl(
        url,
        modelParams,
        onProgress: onProgress,
      );
      _contextHandle = await backend.contextCreate(_modelHandle!, modelParams);
      _isReady = true;

      LlamaLogger.instance.info(
        'Model $modelName loaded successfully from $redactedUrl',
      );
    } catch (e, stackTrace) {
      await _cleanupFailedLoadState();

      LlamaLogger.instance.error(
        'Failed to load model $modelName from URL $redactedUrl',
        _redactedErrorDetails(e),
        stackTrace,
      );
      if (e is LlamaUnsupportedException) {
        rethrow;
      }
      if (e is UnsupportedError) {
        throw _unsupportedBackendOperation('Model URL loading', e);
      }
      throw LlamaModelException(
        'Failed to load model from $redactedUrl',
        _redactedErrorDetails(e),
      );
    }
  }

  // Runs [action] after any in-flight multimodal lifecycle operation, so
  // create/free of the multimodal context never overlap.
  Future<T> _withMmLifecycle<T>(Future<T> Function() action) {
    final result = _mmLifecycle.then((_) => action());
    // Advance the chain on a swallowed copy so one failed operation doesn't
    // wedge subsequent ones; the real result/error still flows to the caller.
    _mmLifecycle = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Loads a multimodal projector model for vision/audio support.
  Future<void> loadMultimodalProjector(String mmProjPath) {
    return _withMmLifecycle(() => _loadMultimodalProjectorLocked(mmProjPath));
  }

  /// Loads a multimodal projector from a structured [source].
  ///
  /// A model must already be loaded with [loadModel], [loadModelSource], or
  /// [loadModelFromUrl]. Calling this before the model is ready throws a
  /// [LlamaContextException].
  ///
  /// This method is lifecycle-compatible with [loadMultimodalProjector]:
  /// source resolution, package-managed download/cache work, and the final
  /// backend projector load are serialized with direct path projector loads and
  /// unloads. Concurrent projector lifecycle calls are applied in call order,
  /// and loading a new projector replaces any active projector.
  ///
  /// Local path sources are validated by the configured
  /// [modelDownloadManager], then loaded from their local file path. Remote
  /// sources use the native download/cache manager on file-backed backends. On
  /// URL-loading backends, remote unauthenticated sources are passed directly to
  /// the backend; package-managed auth, headers, checksum verification, cache
  /// policy changes, cache directories, cancellation, retry/resume settings,
  /// and progress reporting are not available because the backend/browser owns
  /// the network and cache behavior.
  ///
  /// Throws [LlamaUnsupportedException] when the active backend cannot load
  /// multimodal projectors, when a local path is used with a URL-loading
  /// backend, when the resolver returns a remote target that disallows
  /// browser/backend caching, or when URL-backend loading is requested with
  /// options that require the package-managed download/cache manager.
  Future<void> loadMultimodalProjectorSource(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) {
    return _withMmLifecycle(() async {
      _ensureReady(requireContext: false);

      final target = await modelResolver.resolve(
        source,
        ModelResolveRequest(options: options, onProgress: onProgress),
      );

      switch (target) {
        case LocalModelFile(:final path):
          if (backend.supportsUrlLoading) {
            throw LlamaUnsupportedException(
              'Explicit local multimodal projector paths are not supported by URL-loading backends.',
            );
          }
          final localSource = ModelSource.path(path);
          final entry = await modelDownloadManager.ensureModel(
            localSource,
            options: options,
            onProgress: onProgress,
          );
          return _loadMultimodalProjectorLocked(entry.filePath);
        case RemoteModelUrl(:final url, :final useBrowserCache):
          if (!useBrowserCache) {
            throw LlamaUnsupportedException(
              'Remote multimodal projector loading without browser/backend cache is not supported yet.',
            );
          }
          if (!backend.supportsUrlLoading) {
            final downloadSource = source.isRemote
                ? source.withResolvedUri(url)
                : ModelSource.url(url, fileName: source.fileName);
            final entry = await modelDownloadManager.ensureModel(
              downloadSource,
              options: options,
              onProgress: onProgress,
            );
            return _loadMultimodalProjectorLocked(entry.filePath);
          }
          _rejectUnsupportedUrlBackendOptions(
            options,
            assetType: 'multimodal projector',
          );
          return _loadMultimodalProjectorLocked(url.toString());
      }
    });
  }

  Future<void> _loadMultimodalProjectorLocked(String mmProjPath) async {
    final mmProjName = _displayNameForSource(mmProjPath);
    LlamaLogger.instance.info('Loading multimodal projector: $mmProjName');
    _ensureReady(requireContext: false);
    try {
      if (_mmContextHandle != null) {
        await _unloadMultimodalProjectorLocked();
      }

      _mmContextHandle = await backend.multimodalContextCreate(
        _modelHandle!,
        mmProjPath,
      );
      LlamaLogger.instance.info(
        'Multimodal projector $mmProjName loaded successfully',
      );
    } catch (e, stackTrace) {
      LlamaLogger.instance.error(
        'Failed to load multimodal projector $mmProjName',
        e,
        stackTrace,
      );
      if (e is UnsupportedError) {
        throw _unsupportedBackendOperation('Multimodal projectors', e);
      }
      rethrow;
    }
  }

  /// Unloads the active multimodal projector while keeping the model loaded.
  Future<void> unloadMultimodalProjector() {
    return _withMmLifecycle(_unloadMultimodalProjectorLocked);
  }

  Future<void> _unloadMultimodalProjectorLocked() async {
    final mmContextHandle = _mmContextHandle;
    if (mmContextHandle == null) {
      return;
    }

    LlamaLogger.instance.info('Unloading multimodal projector');
    // Free the native context before clearing the handle so a concurrent
    // reader never observes a null handle while teardown is still in flight.
    // Serialization via _withMmLifecycle prevents a double free.
    await backend.multimodalContextFree(mmContextHandle);
    if (_mmContextHandle == mmContextHandle) {
      _mmContextHandle = null;
    }
  }

  /// Releases all allocated resources.
  Future<void> dispose() async {
    final activeLifecycle = _modelLifecycleOperation;
    if (activeLifecycle != null) {
      try {
        await activeLifecycle;
      } catch (_) {
        // Disposal still needs to release backend resources after a failed
        // lifecycle operation.
      }
    }

    Object? unloadError;
    StackTrace? unloadStackTrace;
    try {
      await unloadModel();
    } catch (error, stackTrace) {
      unloadError = error;
      unloadStackTrace = stackTrace;
    }

    try {
      await backend.dispose();
    } catch (error, stackTrace) {
      if (unloadError == null) {
        unloadError = error;
        unloadStackTrace = stackTrace;
      }
    }

    if (unloadError != null) {
      Error.throwWithStackTrace(unloadError, unloadStackTrace!);
    }
  }

  /// Unloads the currently loaded model and frees its resources.
  Future<void> unloadModel() {
    return _withModelLifecycle('unload the current model', _unloadModel);
  }

  Future<void> _unloadModel() async {
    if (!isReady && _modelHandle == null && _mmContextHandle == null) return;
    LlamaLogger.instance.info('Unloading model...');
    _isReady = false;
    backend.cancelGeneration();
    if (_contextHandle != null) {
      await backend.contextFree(_contextHandle!);
      _contextHandle = null;
    }
    // Always queue the projector unload (even when no handle is set yet): a
    // projector load may be in flight and not have assigned _mmContextHandle.
    // Routing through the serialized lifecycle makes this wait behind that load
    // and free the projector before the model handle is released.
    await unloadMultimodalProjector();
    if (_modelHandle != null) {
      await backend.modelFree(_modelHandle!);
      _modelHandle = null;
    }
    _modelPath = null;
    _cachedModelMetadata = null;
    _isReady = false;
    LlamaLogger.instance.info('Model unloaded.');
  }

  // ============================================================
  // CHAT COMPLETIONS (Primary API)
  // ============================================================

  /// Creates a chat completion from a list of [messages].
  ///
  /// This is the primary stateless API (like OpenAI's Chat Completions).
  /// You must pass the full conversation history with each call.
  ///
  /// Pass [tools] to enable function calling. Use [toolChoice] to control
  /// whether the model should use tools:
  /// - [ToolChoice.none]: Model won't call any tool
  /// - [ToolChoice.auto]: Model can choose (default when tools present)
  /// - [ToolChoice.required]: Model must call at least one tool
  ///
  /// Set [parallelToolCalls] to allow multiple tool calls in one response for
  /// templates that support it.
  ///
  /// For TranslateGemma-style templates, set [sourceLangCode] and
  /// [targetLangCode] to control language metadata injected into user
  /// content blocks.
  ///
  /// Use [chatTemplateKwargs] to inject additional template globals (equivalent
  /// to llama.cpp `chat_template_kwargs`).
  /// Use [templateNow] to set deterministic template time context.
  ///
  /// Pass [responseFormat] to request strict structured output through
  /// grammar-constrained decoding on compatible backends. Supported shapes are:
  /// - `{'type': 'json_object'}`
  /// - `{'type': 'json_schema', 'json_schema': {'schema': <JSON schema>}}`
  /// Use [LlamaStructuredOutput.responseFormat] or [createStructuredJson] for a
  /// typed helper that also validates and decodes the final JSON output.
  ///
  /// Backends without grammar-constrained decoding, including LiteRT-LM native
  /// and web today, throw [LlamaUnsupportedException] for strict
  /// [responseFormat] requests instead of silently running unconstrained
  /// generation.
  ///
  /// Structured output is separate from tool-call parsing: LiteRT-LM can still
  /// parse compatible best-effort tool-call text, but it does not currently
  /// enforce arbitrary JSON-schema constraints.
  ///
  /// Example:
  /// ```dart
  /// final messages = [
  ///   LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hello!'),
  /// ];
  /// await for (final token in engine.create(messages)) {
  ///   print(token);
  /// }
  ///
  /// await engine.create(messages, responseFormat: const {
  ///   'type': 'json_schema',
  ///   'json_schema': {
  ///     'schema': {
  ///       'type': 'object',
  ///       'properties': {
  ///         'ok': {'type': 'boolean'},
  ///       },
  ///       'required': ['ok'],
  ///     },
  ///   },
  /// }).drain();
  /// ```
  Stream<LlamaCompletionChunk> create(
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? responseFormat,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) async* {
    _ensureReady();

    // Keep tools available to template routing even with toolChoice.none,
    // matching llama.cpp behavior.
    final effectiveTools = tools;
    final effectiveToolChoice = toolChoice ?? ToolChoice.auto;

    // Apply chat template with tools - returns grammar for constraining
    final result = await chatTemplate(
      messages,
      tools: effectiveTools,
      toolChoice: effectiveToolChoice,
      parallelToolCalls: parallelToolCalls,
      enableThinking: enableThinking,
      responseFormat: responseFormat,
      sourceLangCode: sourceLangCode,
      targetLangCode: targetLangCode,
      chatTemplateKwargs: chatTemplateKwargs,
      templateNow: templateNow,
      includeTokenCount: false,
    );
    final plan = ChatCompletionRequestPlanner.build(
      backend: backend,
      templateResult: result,
      messages: messages,
      params: params,
      tools: effectiveTools,
      toolChoice: effectiveToolChoice,
      parallelToolCalls: parallelToolCalls,
      responseFormat: responseFormat,
    );

    // Generate raw tokens with grammar constraint. Backends that can consume
    // structured chat natively may receive the original messages/tools, while
    // all other backends keep the rendered prompt path.
    final tokenStream = plan.usesNativeChatGeneration
        ? _generateNativeChat(
            plan.nativeChatBackend!,
            messages,
            params: plan.generationParams,
            tools: effectiveTools,
            toolChoice: effectiveToolChoice,
            parallelToolCalls: parallelToolCalls,
            enableThinking: enableThinking,
            chatTemplateKwargs: chatTemplateKwargs,
            sourceLangCode: sourceLangCode,
            targetLangCode: targetLangCode,
            templateNow: templateNow,
          )
        : generate(
            result.prompt,
            params: plan.generationParams,
            parts: plan.mediaParts,
          );

    final completionId = DateTime.now().millisecondsSinceEpoch.toString();
    yield* ChatCompletionStreamParser.parse(
      tokenStream: tokenStream,
      templateResult: plan.templateResult,
      parseToolCallsEnabled: plan.parseToolCallsEnabled,
      enableThinking: enableThinking,
      modelName: _modelPath ?? 'llama_model',
      completionId: completionId,
    );
  }

  /// Generates strict structured JSON and decodes the final output.
  ///
  /// This helper applies `output.responseFormat` to [create], collects streamed
  /// content deltas, validates the completed JSON value, and returns the typed
  /// value produced by [output]'s decoder. Use [create] directly when you need
  /// to render tokens live; the returned stream can still be finalized with
  /// `await stream.parseStructuredJson(output)`.
  Future<T> createStructuredJson<T>(
    List<LlamaChatMessage> messages, {
    required LlamaStructuredOutput<T> output,
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) {
    return create(
      messages,
      params: params,
      tools: tools,
      toolChoice: toolChoice,
      parallelToolCalls: parallelToolCalls,
      enableThinking: enableThinking,
      responseFormat: output.responseFormat,
      sourceLangCode: sourceLangCode,
      targetLangCode: targetLangCode,
      chatTemplateKwargs: chatTemplateKwargs,
      templateNow: templateNow,
    ).parseStructuredJson(output);
  }

  /// Formats a list of [messages] into a prompt string using the model's template.
  ///
  /// This is useful for preparing messages before calling [generate] directly,
  /// or for inspecting the formatted prompt for debugging purposes.
  ///
  /// Pass [customTemplate] to override default routing.
  /// Pass [responseFormat] to request structured output grammar generation.
  /// Supported shapes are:
  /// - `{'type': 'json_object'}`
  /// - `{'type': 'json_schema', 'json_schema': {'schema': <JSON schema>}}`
  /// Use [LlamaStructuredOutput.responseFormat] to avoid hand-writing these
  /// maps in application code.
  ///
  /// [jsonSchema] is a legacy shortcut for
  /// `responseFormat: {'type': 'json_schema', 'json_schema': {'schema': ...}}`.
  /// If both [responseFormat] and [jsonSchema] are provided, [responseFormat]
  /// wins.
  ///
  /// For TranslateGemma-style templates, [sourceLangCode] and
  /// [targetLangCode] are forwarded to the template renderer.
  ///
  /// Set [includeTokenCount] to false to skip the prompt tokenization pass
  /// and reduce per-request overhead when token count is not needed.
  ///
  /// Use [chatTemplateKwargs] to inject additional template globals (equivalent
  /// to llama.cpp `chat_template_kwargs`).
  /// Use [templateNow] to set deterministic template time context.
  ///
  Future<LlamaChatTemplateResult> chatTemplate(
    List<LlamaChatMessage> messages, {
    bool addAssistant = true,
    @Deprecated(
      'Use responseFormat: {"type": "json_schema", '
      '"json_schema": {"schema": ...}} instead.',
    )
    Map<String, dynamic>? jsonSchema,
    List<ToolDefinition>? tools,
    ToolChoice toolChoice = ToolChoice.auto,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? responseFormat,
    String? customTemplate,
    String? sourceLangCode,
    String? targetLangCode,
    bool includeTokenCount = true,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) async {
    _ensureReady(requireContext: false);
    return ChatTemplateRenderer.render(
      loadMetadata: _getCachedMetadata,
      tokenize: tokenize,
      messages: messages,
      addAssistant: addAssistant,
      jsonSchema: jsonSchema,
      tools: tools,
      toolChoice: toolChoice,
      parallelToolCalls: parallelToolCalls,
      enableThinking: enableThinking,
      responseFormat: responseFormat,
      customTemplate: customTemplate,
      sourceLangCode: sourceLangCode,
      targetLangCode: targetLangCode,
      includeTokenCount: includeTokenCount,
      chatTemplateKwargs: chatTemplateKwargs,
      templateNow: templateNow,
    );
  }

  // ============================================================
  // LOW-LEVEL GENERATION
  // ============================================================

  /// Generates a stream of text tokens based on the provided raw [prompt].
  ///
  /// This is the low-level generation API. For chat-style interactions with
  /// proper template formatting, use [create] instead.
  ///
  /// Use [GenerationParams] to tune the sampling process.
  ///
  /// If [parts] contains media content, markers will be automatically injected
  /// into the prompt if missing.
  Stream<String> generate(
    String prompt, {
    GenerationParams params = const GenerationParams(),
    List<LlamaContentPart>? parts,
  }) async* {
    _ensureReady();

    try {
      final stream = backend.generate(
        _contextHandle!,
        prompt,
        params,
        parts: parts,
      );

      await for (final token in stream.transform(
        const Utf8Decoder(allowMalformed: true),
      )) {
        yield token;
      }
    } on UnsupportedError catch (error) {
      throw _unsupportedBackendOperation('Generation', error);
    } on LlamaException {
      rethrow;
    } catch (error, stackTrace) {
      // Wrap raw backend failures so callers catching LlamaException (the
      // documented error contract) don't see unexpected error types escape,
      // while preserving the original backend stack trace.
      Error.throwWithStackTrace(
        LlamaInferenceException('Generation failed', error),
        stackTrace,
      );
    }
  }

  Stream<String> _generateNativeChat(
    BackendNativeChatGeneration nativeBackend,
    List<LlamaChatMessage> messages, {
    required GenerationParams params,
    List<ToolDefinition>? tools,
    required ToolChoice toolChoice,
    required bool parallelToolCalls,
    required bool enableThinking,
    Map<String, dynamic>? chatTemplateKwargs,
    String? sourceLangCode,
    String? targetLangCode,
    DateTime? templateNow,
  }) async* {
    _ensureReady();

    try {
      final stream = nativeBackend.generateChat(
        _contextHandle!,
        messages,
        params,
        tools: tools,
        toolChoice: toolChoice,
        parallelToolCalls: parallelToolCalls,
        enableThinking: enableThinking,
        chatTemplateKwargs: chatTemplateKwargs,
        sourceLangCode: sourceLangCode,
        targetLangCode: targetLangCode,
        templateNow: templateNow,
      );

      await for (final token in stream.transform(
        const Utf8Decoder(allowMalformed: true),
      )) {
        yield token;
      }
    } on UnsupportedError catch (error) {
      throw _unsupportedBackendOperation('Native chat generation', error);
    } on LlamaException {
      rethrow;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        LlamaInferenceException('Native chat generation failed', error),
        stackTrace,
      );
    }
  }

  /// Immediately cancels any ongoing generation process.
  void cancelGeneration() {
    backend.cancelGeneration();
  }

  // ============================================================
  // TOKENIZATION
  // ============================================================

  /// Encodes the given [text] into a list of token IDs.
  Future<List<int>> tokenize(String text, {bool addSpecial = true}) async {
    _ensureReady(requireContext: false);
    try {
      return await backend.tokenize(
        _modelHandle!,
        text,
        addSpecial: addSpecial,
      );
    } on UnsupportedError catch (error) {
      throw _unsupportedBackendOperation('Tokenization', error);
    }
  }

  /// Decodes a list of [tokens] back into a human-readable string.
  Future<String> detokenize(List<int> tokens, {bool special = false}) async {
    _ensureReady(requireContext: false);
    try {
      return await backend.detokenize(_modelHandle!, tokens, special: special);
    } on UnsupportedError catch (error) {
      throw _unsupportedBackendOperation('Detokenization', error);
    }
  }

  /// Utility to count the number of tokens in [text] without running inference.
  Future<int> getTokenCount(String text) async {
    final tokens = await tokenize(text, addSpecial: false);
    return tokens.length;
  }

  // ============================================================
  // EMBEDDINGS
  // ============================================================

  /// Generates a single embedding vector for [text].
  ///
  /// When [normalize] is true, the returned vector is L2-normalized.
  Future<List<double>> embed(String text, {bool normalize = true}) async {
    _ensureReady();
    try {
      final embeddingBackend = _resolveEmbeddingBackend();
      return await embeddingBackend.embed(
        _contextHandle!,
        text,
        normalize: normalize,
      );
    } on UnsupportedError catch (error) {
      throw _unsupportedBackendOperation('Embeddings', error);
    }
  }

  /// Generates embedding vectors for all [texts] in order.
  ///
  /// When [normalize] is true, each returned vector is L2-normalized.
  Future<List<List<double>>> embedBatch(
    List<String> texts, {
    bool normalize = true,
  }) async {
    _ensureReady();
    if (texts.isEmpty) {
      return const <List<double>>[];
    }

    final embeddingBackend = _resolveEmbeddingBackend();
    try {
      if (embeddingBackend is BackendBatchEmbeddings) {
        return await embeddingBackend.embedBatch(
          _contextHandle!,
          texts,
          normalize: normalize,
        );
      }

      final vectors = <List<double>>[];
      for (final text in texts) {
        final vector = await embeddingBackend.embed(
          _contextHandle!,
          text,
          normalize: normalize,
        );
        vectors.add(vector);
      }
      return vectors;
    } on UnsupportedError catch (error) {
      throw _unsupportedBackendOperation('Embeddings', error);
    }
  }

  LlamaUnsupportedException _unsupportedBackendOperation(
    String operation,
    UnsupportedError error,
  ) {
    final message = error.message;
    final detail = message == null ? '' : message.toString();
    if (detail.isEmpty) {
      return LlamaUnsupportedException(
        '$operation is not supported by the active backend.',
      );
    }
    return LlamaUnsupportedException(
      '$operation is not supported by the active backend: $detail',
    );
  }

  BackendEmbeddings _resolveEmbeddingBackend() {
    final candidate = backend;
    if (candidate is BackendEmbeddingsSupport &&
        !(candidate as BackendEmbeddingsSupport).supportsEmbeddings) {
      throw LlamaUnsupportedException(
        'Embeddings are not supported by the active backend.',
      );
    }
    if (candidate is BackendEmbeddings) {
      return candidate as BackendEmbeddings;
    }

    throw LlamaUnsupportedException(
      'Embeddings are not supported by the active backend.',
    );
  }

  // ============================================================
  // STATE PERSISTENCE
  // ============================================================

  /// Whether the active backend reports state save/load support.
  ///
  /// Supported native llama.cpp backends persist to disk. WebGPU backends report
  /// support only after the active JavaScript bridge exposes the `stateSaveFile`
  /// and `stateLoadFile` APIs introduced in bridge assets `v0.1.15`; older or
  /// custom bridge assets report false and calls throw
  /// [LlamaUnsupportedException] before reaching the bridge.
  bool get supportsStatePersistence {
    final candidate = backend;
    if (candidate is BackendStatePersistenceSupport) {
      return (candidate as BackendStatePersistenceSupport)
          .supportsStatePersistence;
    }
    return candidate is BackendStatePersistence;
  }

  /// Persists the KV-cache state of the loaded model to [path] together
  /// with [tokens] — the token sequence the current state was produced
  /// from. A later [stateLoadFile] call rebuilds the same in-memory
  /// state without re-evaluating the prompt, which is the difference
  /// between a 30-second resume on phone CPUs and an instant one.
  ///
  /// File format is whatever llama.cpp emits — opaque, not portable
  /// across builds, and tied to the same model used at save time.
  ///
  /// Returns true on success.
  Future<bool> stateSaveFile(String path, {required List<int> tokens}) async {
    _ensureReady();
    final persistence = await _resolveStatePersistence();
    try {
      return await persistence.stateSaveFile(_contextHandle!, path, tokens);
    } on UnsupportedError catch (error) {
      throw _unsupportedBackendOperation('State persistence', error);
    }
  }

  /// Restores a previously saved state from [path]. [tokenCapacity]
  /// caps how many tokens to read back; passing the loaded model's
  /// `n_ctx` is a safe default.
  ///
  /// Returns the token sequence the saved state was originally produced
  /// from. This API restores the native KV cache only — callers that use
  /// [ChatSession] must persist and reconstruct the chat message history
  /// separately (e.g. on disk), since [ChatSession.addMessage] takes
  /// [LlamaChatMessage] objects, not raw token ids. The returned token
  /// list is exposed mainly for diagnostics and for callers driving the
  /// engine at the raw prompt level.
  Future<StateLoadResult> stateLoadFile(
    String path, {
    required int tokenCapacity,
  }) async {
    _ensureReady();
    final persistence = await _resolveStatePersistence();
    try {
      return await persistence.stateLoadFile(
        _contextHandle!,
        path,
        tokenCapacity,
      );
    } on UnsupportedError catch (error) {
      throw _unsupportedBackendOperation('State persistence', error);
    }
  }

  Future<BackendStatePersistence> _resolveStatePersistence() async {
    final candidate = backend;
    if (candidate is BackendStatePersistenceSupport &&
        !(candidate as BackendStatePersistenceSupport)
            .supportsStatePersistence) {
      throw LlamaUnsupportedException(
        await _statePersistenceUnsupportedMessage(),
      );
    }
    if (candidate is BackendStatePersistence) {
      return candidate as BackendStatePersistence;
    }
    throw LlamaUnsupportedException(
      'State persistence is not supported by the active backend.',
    );
  }

  Future<String> _statePersistenceUnsupportedMessage() async {
    String backendName = '';
    try {
      backendName = await backend.getBackendName();
    } catch (_) {
      // Fall back to the generic message when backend diagnostics are not
      // available on the active runtime.
    }

    final normalizedBackendName = backendName.toLowerCase();
    if (normalizedBackendName.contains('litert-lm')) {
      return 'State persistence is not supported by the active LiteRT-LM '
          'backend because the LiteRT-LM APIs exposed through llamadart do not '
          'provide KV-cache save/load yet.';
    }
    if (normalizedBackendName.contains('webgpu') ||
        normalizedBackendName.contains('web gpu')) {
      return 'State persistence is not supported by the active backend. '
          'For WebGPU, use bridge assets that expose '
          'stateSaveFile/stateLoadFile (v0.1.15 or newer).';
    }
    return 'State persistence is not supported by the active backend.';
  }

  // ============================================================
  // MODEL INTROSPECTION
  // ============================================================

  /// Retrieves all available metadata from the loaded model.
  Future<Map<String, String>> getMetadata() async {
    if (!_isReady || _modelHandle == null) {
      return <String, String>{};
    }
    final metadata = await backend.modelMetadata(_modelHandle!);
    _cachedModelMetadata = Map<String, String>.from(metadata);
    return metadata;
  }

  /// Returns the actual context size being used by the current session.
  Future<int> getContextSize() async {
    if (_isReady && _contextHandle != null) {
      final size = await backend.getContextSize(_contextHandle!);
      if (size > 0) return size;
    }
    final meta = await getMetadata();
    // Try common context length keys in metadata
    final ctx =
        meta['llm.context_length'] ??
        meta['llama.context_length'] ??
        meta['model.context_length'] ??
        meta['n_ctx'] ??
        "0";
    return int.tryParse(ctx) ?? 0;
  }

  /// Whether the loaded model supports vision.
  Future<bool> get supportsVision async =>
      _mmContextHandle != null &&
      await backend.supportsVision(_mmContextHandle!);

  /// Whether the loaded model supports audio.
  Future<bool> get supportsAudio async =>
      _mmContextHandle != null &&
      await backend.supportsAudio(_mmContextHandle!);

  // ============================================================
  // LORA MANAGEMENT
  // ============================================================

  /// Dynamically loads or updates a LoRA adapter's scale.
  Future<void> setLora(String path, {double scale = 1.0}) async {
    _ensureReady();
    try {
      await backend.setLoraAdapter(_contextHandle!, path, scale);
    } on UnsupportedError catch (error) {
      throw _unsupportedBackendOperation('LoRA adapters', error);
    }
  }

  /// Removes a specific LoRA adapter from the active session.
  Future<void> removeLora(String path) async {
    _ensureReady();
    try {
      await backend.removeLoraAdapter(_contextHandle!, path);
    } on UnsupportedError catch (error) {
      throw _unsupportedBackendOperation('LoRA adapters', error);
    }
  }

  /// Removes all active LoRA adapters from the current context.
  Future<void> clearLoras() async {
    _ensureReady();
    try {
      await backend.clearLoraAdapters(_contextHandle!);
    } on UnsupportedError catch (error) {
      throw _unsupportedBackendOperation('LoRA adapters', error);
    }
  }

  // ============================================================
  // BACKEND UTILITIES
  // ============================================================

  /// Internal model handle.
  int? get modelHandle => _modelHandle;

  /// Internal context handle.
  int? get contextHandle => _contextHandle;

  /// Returns the name of the active GPU backend.
  Future<String> getBackendName() => backend.getBackendName();

  /// Returns backend options available for user selection.
  Future<String> getAvailableBackends() {
    final candidate = backend;
    if (candidate is BackendAvailability) {
      return (candidate as BackendAvailability).getAvailableBackends();
    }
    return candidate.getBackendName();
  }

  /// Returns resolved GPU layers for the active model load when available.
  Future<int?> getResolvedGpuLayers() {
    final candidate = backend;
    if (candidate is BackendRuntimeDiagnostics) {
      return (candidate as BackendRuntimeDiagnostics).getResolvedGpuLayers();
    }
    return Future<int?>.value(null);
  }

  /// Returns model file type or quantization metadata when available.
  ///
  /// llama.cpp/GGUF backends expose this via the native `llama_model_ftype` and
  /// `llama_ftype_name` APIs. Backends that do not expose equivalent metadata,
  /// such as LiteRT-LM or older web bridge assets, return null.
  Future<ModelFileType?> getModelFileType() {
    final modelHandle = _modelHandle;
    if (!_isReady || modelHandle == null) {
      return Future<ModelFileType?>.value(null);
    }

    final candidate = backend;
    if (candidate is BackendModelFileTypeDiagnostics) {
      return (candidate as BackendModelFileTypeDiagnostics).getModelFileType(
        modelHandle,
      );
    }
    return Future<ModelFileType?>.value(null);
  }

  /// Returns native llama.cpp perf timings for the active context when available.
  Future<BackendPerfContextData?> getPerformanceContext() {
    final candidate = backend;
    final contextHandle = _contextHandle;
    if (contextHandle == null) {
      return Future<BackendPerfContextData?>.value(null);
    }
    if (candidate is BackendPerformanceDiagnostics) {
      return (candidate as BackendPerformanceDiagnostics).getPerformanceContext(
        contextHandle,
      );
    }
    return Future<BackendPerfContextData?>.value(null);
  }

  /// Returns true if the current hardware and backend support GPU acceleration.
  Future<bool> isGpuSupported() => backend.isGpuSupported();

  /// Returns total and free VRAM in bytes.
  Future<({int total, int free})> getVramInfo() => backend.getVramInfo();

  /// Lists GPU-class devices when the active backend supports enumeration,
  /// otherwise an empty list. With an empty [probeBackends] only
  /// already-registered backends are inspected (no backend module is loaded);
  /// pass backends to opt into loading just those before enumerating.
  Future<List<GpuDeviceInfo>> listGpuDevices({
    List<GpuBackend> probeBackends = const [],
  }) {
    final candidate = backend;
    if (candidate is BackendGpuEnumeration) {
      return (candidate as BackendGpuEnumeration).listGpuDevices(
        probeBackends: probeBackends,
      );
    }
    return Future.value(const []);
  }

  // ============================================================
  // INTERNAL HELPERS
  // ============================================================

  Future<Map<String, String>> _getCachedMetadata() async {
    if (_cachedModelMetadata != null) {
      return Map<String, String>.from(_cachedModelMetadata!);
    }

    final metadata = await getMetadata();
    _cachedModelMetadata = Map<String, String>.from(metadata);
    return Map<String, String>.from(_cachedModelMetadata!);
  }

  Future<void> _withModelLifecycle(
    String operation,
    Future<void> Function() action,
  ) async {
    if (_modelLifecycleOperation != null) {
      throw LlamaStateException(
        'Cannot $operation while another model lifecycle operation is in progress.',
      );
    }
    final lifecycleOperation = action();
    _modelLifecycleOperation = lifecycleOperation;
    try {
      await lifecycleOperation;
    } finally {
      if (identical(_modelLifecycleOperation, lifecycleOperation)) {
        _modelLifecycleOperation = null;
      }
    }
  }

  Future<void> _cleanupFailedLoadState() async {
    if (_contextHandle != null) {
      try {
        await backend.contextFree(_contextHandle!);
      } catch (_) {}
      _contextHandle = null;
    }
    if (_modelHandle != null) {
      try {
        await backend.modelFree(_modelHandle!);
      } catch (_) {}
      _modelHandle = null;
    }
    _modelPath = null;
    _cachedModelMetadata = null;
    _isReady = false;
  }

  void _rejectUnsupportedUrlBackendOptions(
    ModelLoadOptions options, {
    String assetType = 'model',
  }) {
    final isModel = assetType == 'model';
    if (options.cachePolicy != ModelCachePolicy.preferCached) {
      throw LlamaUnsupportedException(
        '${options.cachePolicy.name} $assetType loading requires the native download/cache manager.',
      );
    }
    if (options.bearerToken != null || options.headers.isNotEmpty) {
      throw LlamaUnsupportedException(
        'Authenticated $assetType URL loading requires the native download/cache manager.',
      );
    }
    if (options.cancelToken != null) {
      throw LlamaUnsupportedException(
        isModel
            ? 'Cancellation tokens require the native download/cache manager.'
            : 'Cancellation tokens for $assetType loading require the native download/cache manager.',
      );
    }
    if (options.sha256 != null) {
      throw LlamaUnsupportedException(
        isModel
            ? 'Checksum verification requires the native download/cache manager.'
            : 'Checksum verification for $assetType loading requires the native download/cache manager.',
      );
    }
    if (options.cacheDirectory != null) {
      throw LlamaUnsupportedException(
        isModel
            ? 'cacheDirectory is not supported by URL-loading backends.'
            : 'cacheDirectory is not supported for $assetType loading by URL-loading backends.',
      );
    }
    if (!options.resume) {
      throw LlamaUnsupportedException(
        isModel
            ? 'Disabling resume is not supported by URL-loading backends.'
            : 'Disabling resume is not supported for $assetType loading by URL-loading backends.',
      );
    }
    if (options.maxRetries != ModelLoadOptions.defaults.maxRetries) {
      throw LlamaUnsupportedException(
        isModel
            ? 'Custom maxRetries is not supported by URL-loading backends.'
            : 'Custom maxRetries is not supported for $assetType loading by URL-loading backends.',
      );
    }
  }

  void _throwIfSourceLoadCancelled(ModelLoadOptions options) {
    if (options.cancelToken?.isCancelled ?? false) {
      throw LlamaStateException('Model source loading was cancelled.');
    }
  }

  String _displayNameForSource(String source) {
    final parsedUri = Uri.tryParse(source);
    if (parsedUri != null &&
        parsedUri.hasScheme &&
        parsedUri.pathSegments.isNotEmpty) {
      final lastSegment = parsedUri.pathSegments.last;
      if (lastSegment.isNotEmpty) {
        return Uri.decodeComponent(lastSegment);
      }
    }

    final normalizedSource = source.replaceAll('\\', '/');
    final segments = normalizedSource.split('/');
    final lastSegment = segments.isNotEmpty ? segments.last : source;
    return lastSegment.isNotEmpty ? lastSegment : source;
  }

  String _redactedUriForLogs(String source) {
    final uri = Uri.tryParse(source);
    if (uri == null || !uri.hasScheme) {
      return _displayNameForSource(source);
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.hasAuthority ? uri.host : null,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    ).toString();
  }

  Object _redactedErrorDetails(Object error) {
    final message = error.toString().replaceAllMapped(
      RegExp(r'https?://[^\s)]+'),
      (match) => _redactedUriForLogs(match.group(0)!),
    );
    return <String, Object?>{
      'type': error.runtimeType.toString(),
      'message': message,
    };
  }

  /// Validates engine is ready for inference.
  void _ensureReady({bool requireContext = true}) {
    if (!_isReady) {
      throw LlamaContextException("Engine not ready. Call loadModel first.");
    }
    if (requireContext && _contextHandle == null) {
      throw LlamaContextException("Context not initialized.");
    }
  }

  /// Ensures the engine is NOT currently loaded.
  void _ensureNotReady() {
    if (_isReady) {
      throw LlamaStateException(
        'Model is already loaded. Call unloadModel() first.',
      );
    }
  }
}
