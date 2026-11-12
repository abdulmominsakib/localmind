import '../../core/engine/engine_capabilities.dart';
import '../../core/engine/engine_observer.dart';
import '../../core/exceptions.dart';
import '../../core/models/chat/chat_message.dart';
import '../../core/models/chat/content_part.dart';
import '../../core/models/config/gpu_backend.dart';
import '../../core/models/config/gpu_device_info.dart';
import '../../core/models/config/log_level.dart';
import '../../core/models/diagnostics/model_file_type.dart';
import '../../core/models/inference/generation_params.dart';
import '../../core/models/inference/generation_usage.dart';
import '../../core/models/inference/model_params.dart';
import '../../core/models/inference/model_params_runtime_support.dart';
import '../../core/models/inference/embedding.dart';
import '../../core/models/inference/reranking.dart';
import '../../core/models/inference/next_token_scores.dart';
import '../../core/models/inference/state_identity.dart';
import '../../core/models/inference/tool_choice.dart';
import '../../core/models/model_format.dart';
import '../../core/models/tools/tool_definition.dart';
import '../../core/template/handlers/translate_gemma_handler.dart';
import '../../core/template/media_placeholders.dart';
import '../backend.dart';
import '../litert_lm/litert_lm_backend.dart';
import '../litert_lm/litert_lm_platform.dart';
import '../litert_lm/litert_lm_runtime.dart';
import '../llama_cpp/llama_cpp_backend.dart';
import 'model_format_probe.dart';

/// Creates the native backend for the current platform.
LlamaBackend createBackend() => NativeAutoBackend();

/// Preserves native runtime selection for the portable text-history opt-in.
LlamaBackend createTextHistoryBackend() => createBackend();

/// Native backend router that chooses an engine from the model format.
///
/// The file header picks the runtime: GGUF files use llama.cpp and LiteRT-LM
/// bundles use LiteRT-LM. When the header is unreadable or unrecognized, an
/// explicit format, then the `.litertlm` extension, select LiteRT-LM, and
/// anything else stays on llama.cpp.
class NativeAutoBackend
    implements
        BackendRuntimeIdentity,
        BackendModelFormatRouting,
        BackendModelFormatDetection,
        BackendLoadCheck,
        LlamaBackend,
        BackendAvailability,
        BackendLoraSupport,
        BackendMultimodalSupport,
        BackendDirectMediaInput,
        BackendToolResultMedia,
        BackendRuntimeDiagnostics,
        BackendModelFileTypeDiagnostics,
        BackendGpuEnumeration,
        BackendPerformanceDiagnostics,
        BackendEmbeddings,
        BackendEmbeddingsSupport,
        BackendMultimodalEmbeddings,
        BackendBatchEmbeddings,
        BackendReranking,
        BackendNextTokenScoring,
        BackendNextTokenScoringSupport,
        BackendStatePersistence,
        BackendStatePersistenceSupport,
        BackendStateIdentity,
        BackendGrammarConstraintsSupport,
        BackendNativeChatGeneration,
        BackendJsonSchemaThinkingChatGeneration,
        BackendChatPromptGeneration,
        BackendPromptPenaltyGeneration,
        BackendDeferredEngineCreation,
        BackendTextToSpeech,
        BackendTextToSpeechModelSupport,
        BackendDecision,
        BackendGenerationCapabilitiesSupport,
        BackendVideoRuntimeSupport,
        BackendGenerationLimitReporting,
        BackendGenerationLimitSupport,
        BackendGenerationUsageReporting,
        BackendRuntimePromptTokenization,
        BackendDartLogLevel {
  final LlamaBackend Function() _llamaCppFactory;
  final LlamaBackend Function() _liteRtLmFactory;
  final bool _defaultLiteRtLm;

  LlamaBackend? _delegate;
  int _embeddingCancelEpoch = 0;
  LlamaRuntime? _delegateKind;
  LlamaBackend? _diagnosticDelegate;
  Future<LlamaBackend>? _diagnosticDelegateStart;
  LlamaLogLevel _currentLogLevel = LlamaLogLevel.warn;

  /// Creates a backend router.
  NativeAutoBackend({
    LlamaBackend Function()? llamaCppFactory,
    LlamaBackend Function()? liteRtLmFactory,
  }) : _llamaCppFactory = llamaCppFactory ?? (() => NativeLlamaBackend()),
       _liteRtLmFactory = liteRtLmFactory ?? (() => LiteRtLmBackend()),
       _defaultLiteRtLm = liteRtLmFactory == null;

  @override
  String? get generationLimitUnsupportedReason {
    final delegate = _delegate;
    return delegate is BackendGenerationLimitSupport
        ? (delegate as BackendGenerationLimitSupport)
              .generationLimitUnsupportedReason
        : null;
  }

  @override
  bool get isReady => _delegate?.isReady ?? false;

  @override
  bool get supportsUrlLoading => false;

  @override
  bool get supportsGrammarConstraints {
    // Forward the active delegate's capability so the engine skips template
    // grammars on backends that reject them (e.g. LiteRT-LM). Defaults to true
    // (llama.cpp) before a model is loaded.
    final delegate = _delegate;
    if (delegate is BackendGrammarConstraintsSupport) {
      return (delegate as BackendGrammarConstraintsSupport)
          .supportsGrammarConstraints;
    }
    return true;
  }

  @override
  bool get supportsJsonSchemaChatGeneration {
    final delegate = _delegate;
    return delegate is BackendJsonSchemaChatGeneration &&
        (delegate as BackendJsonSchemaChatGeneration)
            .supportsJsonSchemaChatGeneration;
  }

  @override
  bool get supportsJsonSchemaChatThinking {
    final delegate = _delegate;
    return delegate is BackendJsonSchemaThinkingChatGeneration &&
        (delegate as BackendJsonSchemaThinkingChatGeneration)
            .supportsJsonSchemaChatThinking;
  }

  @override
  Future<void> prepareJsonSchemaChat() async {
    final delegate = _requireDelegate();
    if (delegate is! BackendJsonSchemaChatGeneration) {
      throw LlamaUnsupportedException(
        'The selected backend has no native JSON Schema chat provider.',
      );
    }
    await (delegate as BackendJsonSchemaChatGeneration).prepareJsonSchemaChat();
  }

  @override
  Stream<List<int>> generateChatWithJsonSchema(
    int contextHandle,
    List<LlamaChatMessage> messages,
    GenerationParams params, {
    required Map<String, dynamic> jsonSchema,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) {
    final delegate = _requireDelegate();
    if (delegate is BackendJsonSchemaChatGeneration) {
      return (delegate as BackendJsonSchemaChatGeneration)
          .generateChatWithJsonSchema(
            contextHandle,
            messages,
            params,
            jsonSchema: jsonSchema,
            chatTemplateKwargs: chatTemplateKwargs,
            templateNow: templateNow,
          );
    }
    throw LlamaUnsupportedException(
      'The selected backend has no native JSON Schema chat provider.',
    );
  }

  @override
  Stream<List<int>> generateChatWithJsonSchemaAndThinking(
    int contextHandle,
    List<LlamaChatMessage> messages,
    GenerationParams params, {
    required Map<String, dynamic> jsonSchema,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) {
    final delegate = _requireDelegate();
    if (delegate is BackendJsonSchemaThinkingChatGeneration) {
      return (delegate as BackendJsonSchemaThinkingChatGeneration)
          .generateChatWithJsonSchemaAndThinking(
            contextHandle,
            messages,
            params,
            jsonSchema: jsonSchema,
            chatTemplateKwargs: chatTemplateKwargs,
            templateNow: templateNow,
          );
    }
    throw LlamaUnsupportedException(
      'The selected backend cannot reason before a native JSON Schema reply.',
    );
  }

  @override
  bool get supportsNativeChatGeneration {
    final delegate = _delegate;
    if (delegate is BackendNativeChatGeneration) {
      return (delegate as BackendNativeChatGeneration)
          .supportsNativeChatGeneration;
    }
    return false;
  }

  @override
  bool get defersEngineCreation {
    final delegate = _delegate;
    if (delegate is BackendDeferredEngineCreation) {
      return (delegate as BackendDeferredEngineCreation).defersEngineCreation;
    }
    return false;
  }

  @override
  Future<int> modelLoad(String path, ModelParams params) async {
    final format = await resolveLocalModelFormat(path);
    final delegate = await _delegateFor(format.runtime);
    return delegate.modelLoad(path, params);
  }

  @override
  String? checkLoad(ModelParams params, ModelFormat? format) {
    if (format == null) return null;
    checkModelParamsSupportedBy(params, format.runtime, web: false);
    if (format.runtime != LlamaRuntime.liteRtLm) return null;
    if (_defaultLiteRtLm) {
      final unsupported = liteRtLmUnsupportedAbiException(liteRtLmGateAbi());
      if (unsupported != null) throw unsupported;
    }
    liteRtLmEnsureDeviceAvailable(params.device);
    if (params.liteRtLmEmbeddingEngine) {
      liteRtLmEnsureNativeEmbeddingsQualified();
    }
    return _defaultLiteRtLm
        ? null
        : 'A custom LiteRT-LM factory brings its own runtime, so whether it '
              'runs on this platform is known only when it loads the model.';
  }

  @override
  Future<ModelFormat?> detectModelFormat(String path) =>
      readModelFormatHeader(path);

  @override
  Future<int> modelLoadAs(
    String path,
    ModelParams params,
    ModelFormat format,
  ) async {
    await resolveLocalModelFormat(path, requested: format);
    final delegate = await _delegateFor(format.runtime);
    return delegate.modelLoad(path, params);
  }

  @override
  Future<int> modelLoadFromUrlAs(
    String url,
    ModelParams params,
    ModelFormat format, {
    void Function(double progress)? onProgress,
  }) {
    return modelLoadFromUrl(url, params, onProgress: onProgress);
  }

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    void Function(double progress)? onProgress,
  }) {
    throw UnsupportedError(
      'NativeAutoBackend uses llamadart download/cache before modelLoad.',
    );
  }

  @override
  Future<void> modelFree(int modelHandle) {
    return _requireDelegate().modelFree(modelHandle);
  }

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) {
    return _requireDelegate().contextCreate(modelHandle, params);
  }

  @override
  Future<void> contextFree(int contextHandle) {
    return _requireDelegate().contextFree(contextHandle);
  }

  @override
  Future<int> getContextSize(int contextHandle) {
    return _requireDelegate().getContextSize(contextHandle);
  }

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) {
    return _requireDelegate().generate(
      contextHandle,
      prompt,
      params,
      parts: parts,
    );
  }

  @override
  bool get supportsPromptPenaltiesWithGrammar {
    final delegate = _delegate;
    return delegate is BackendPromptPenaltyGeneration &&
        (delegate as BackendPromptPenaltyGeneration)
            .supportsPromptPenaltiesWithGrammar;
  }

  @override
  Stream<List<int>> generateWithPromptPenalties(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    String? mediaMarker,
    List<LlamaContentPart>? parts,
  }) {
    final delegate = _requireDelegate();
    if (delegate is! BackendPromptPenaltyGeneration ||
        !(delegate as BackendPromptPenaltyGeneration)
            .supportsPromptPenaltiesWithGrammar) {
      throw LlamaUnsupportedException(
        'The selected native runtime cannot preserve prompt penalties with a grammar.',
      );
    }
    return (delegate as BackendPromptPenaltyGeneration)
        .generateWithPromptPenalties(
          contextHandle,
          prompt,
          params,
          mediaMarker: mediaMarker,
          parts: parts,
        );
  }

  @override
  Stream<List<int>> generateChatPrompt(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    required String mediaMarker,
    List<LlamaContentPart>? parts,
  }) {
    final delegate = _requireDelegate();
    if (delegate is BackendChatPromptGeneration) {
      return (delegate as BackendChatPromptGeneration).generateChatPrompt(
        contextHandle,
        prompt,
        params,
        mediaMarker: mediaMarker,
        parts: parts,
      );
    }
    return delegate.generate(
      contextHandle,
      prompt.replaceAll(mediaMarker, mtmdMediaMarker),
      params,
      parts: parts,
    );
  }

  @override
  BackendGenerationLimit? generationLimitOf(Stream<List<int>> generation) {
    return generationLimitReporterOf(_delegate)?.generationLimitOf(generation);
  }

  @override
  LlamaGenerationUsage? generationUsageOf(Stream<List<int>> generation) {
    final delegate = _delegate;
    if (delegate is BackendGenerationUsageReporting) {
      return (delegate as BackendGenerationUsageReporting).generationUsageOf(
        generation,
      );
    }
    return null;
  }

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
    @Deprecated("Use chatTemplateKwargs: {'source_lang_code': ...} instead.")
    String? sourceLangCode,
    @Deprecated("Use chatTemplateKwargs: {'target_lang_code': ...} instead.")
    String? targetLangCode,
    DateTime? templateNow,
  }) {
    final delegate = _requireDelegate();
    if (delegate is BackendNativeChatGeneration) {
      return (delegate as BackendNativeChatGeneration).generateChat(
        contextHandle,
        messages,
        params,
        tools: tools,
        toolChoice: toolChoice,
        parallelToolCalls: parallelToolCalls,
        enableThinking: enableThinking,
        chatTemplateKwargs: chatTemplateKwargsWithLanguageCodes(
          chatTemplateKwargs,
          sourceLangCode: sourceLangCode,
          targetLangCode: targetLangCode,
        ),
        templateNow: templateNow,
      );
    }
    throw UnsupportedError(
      'The selected native backend does not support native chat generation.',
    );
  }

  @override
  void cancelGeneration() {
    _embeddingCancelEpoch++;
    _delegate?.cancelGeneration();
  }

  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) {
    return _requireDelegate().tokenize(
      modelHandle,
      text,
      addSpecial: addSpecial,
    );
  }

  @override
  Future<List<int>> tokenizeRuntimePrompt(int modelHandle, String prompt) {
    final delegate = _requireDelegate();
    return runtimePromptTokenizerOf(
          delegate,
        )?.tokenizeRuntimePrompt(modelHandle, prompt) ??
        delegate.tokenize(modelHandle, prompt, addSpecial: false);
  }

  @override
  Future<String> detokenize(
    int modelHandle,
    List<int> tokens, {
    bool special = false,
  }) {
    return _requireDelegate().detokenize(modelHandle, tokens, special: special);
  }

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) {
    return _requireDelegate().modelMetadata(modelHandle);
  }

  @override
  Future<void> setLoraAdapter(int contextHandle, String path, double scale) {
    return _requireLora().setLoraAdapter(contextHandle, path, scale);
  }

  @override
  Future<void> removeLoraAdapter(int contextHandle, String path) {
    return _requireLora().removeLoraAdapter(contextHandle, path);
  }

  @override
  Future<void> clearLoraAdapters(int contextHandle) {
    return _requireLora().clearLoraAdapters(contextHandle);
  }

  BackendLoraSupport _requireLora() {
    final delegate = _requireDelegate();
    if (delegate is BackendLoraSupport) return delegate as BackendLoraSupport;
    throw LlamaUnsupportedException(
      'LoRA adapters are not supported by the active native runtime.',
    );
  }

  @override
  LlamaRuntime? get runtime {
    final delegate = _delegate;
    return delegate is BackendRuntimeIdentity
        ? (delegate as BackendRuntimeIdentity).runtime
        : null;
  }

  @override
  Future<String> getBackendName() {
    final delegate = _delegate;
    if (delegate == null) {
      return Future<String>.value('Native auto');
    }
    return delegate.getBackendName();
  }

  @override
  Future<String> getAvailableBackends() async {
    final delegate = _delegate;
    if (delegate is BackendAvailability) {
      return (delegate as BackendAvailability).getAvailableBackends();
    }
    return 'llama.cpp, LiteRT-LM';
  }

  @override
  Future<int?> getResolvedGpuLayers() {
    final delegate = _delegate;
    if (delegate is BackendRuntimeDiagnostics) {
      return (delegate as BackendRuntimeDiagnostics).getResolvedGpuLayers();
    }
    return Future<int?>.value(null);
  }

  @override
  Future<ModelFileType?> getModelFileType(int modelHandle) {
    final delegate = _delegate;
    if (delegate is BackendModelFileTypeDiagnostics) {
      return (delegate as BackendModelFileTypeDiagnostics).getModelFileType(
        modelHandle,
      );
    }
    return Future<ModelFileType?>.value(null);
  }

  @override
  Future<BackendPerfContextData?> getPerformanceContext(int contextHandle) {
    final delegate = _delegate;
    if (delegate is BackendPerformanceDiagnostics) {
      return (delegate as BackendPerformanceDiagnostics).getPerformanceContext(
        contextHandle,
      );
    }
    return Future<BackendPerfContextData?>.value(null);
  }

  @override
  Future<bool> isGpuSupported() {
    final delegate = _delegate;
    if (delegate != null) {
      return delegate.isGpuSupported();
    }
    return _ensureDiagnosticDelegate().then(
      (diagnosticDelegate) => diagnosticDelegate.isGpuSupported(),
    );
  }

  @override
  Future<void> setDartLogLevel(LlamaLogLevel level) async {
    for (final delegate in {?_delegate, ?_diagnosticDelegate}) {
      if (delegate is BackendDartLogLevel) {
        await (delegate as BackendDartLogLevel).setDartLogLevel(level);
      }
    }
  }

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {
    _currentLogLevel = level;
    await _delegate?.setLogLevel(level);
    final diagnosticDelegate = _diagnosticDelegate;
    if (diagnosticDelegate != null) {
      await diagnosticDelegate.setLogLevel(level);
      return;
    }
    final diagnosticStart = _diagnosticDelegateStart;
    if (diagnosticStart != null) {
      try {
        await (await diagnosticStart).setLogLevel(level);
      } catch (_) {
        // The original diagnostic caller receives the startup failure.
      }
    }
  }

  @override
  Future<void> dispose() async {
    final delegate = _delegate;
    final diagnosticDelegate = await _takeDiagnosticDelegate();
    await delegate?.dispose();
    // Retain a delegate whose cleanup failed: replacing it could start another
    // native runtime while the previous operation is still executing.
    _delegate = null;
    _delegateKind = null;
    if (!identical(delegate, diagnosticDelegate)) {
      await diagnosticDelegate?.dispose();
    }
  }

  @override
  Future<int?> multimodalContextCreate(int modelHandle, String mmProjPath) {
    return _requireMultimodal().multimodalContextCreate(
      modelHandle,
      mmProjPath,
    );
  }

  @override
  Future<void> multimodalContextFree(int mmContextHandle) {
    return _requireMultimodal().multimodalContextFree(mmContextHandle);
  }

  BackendMultimodalSupport _requireMultimodal() {
    final delegate = _requireDelegate();
    if (delegate is BackendMultimodalSupport) {
      return delegate as BackendMultimodalSupport;
    }
    throw LlamaUnsupportedException(
      'Multimodal projectors are not supported by the active native runtime.',
    );
  }

  @override
  Set<LlamaToolResultMedia> get toolResultMedia {
    final delegate = _delegate;
    return delegate is BackendToolResultMedia
        ? (delegate as BackendToolResultMedia).toolResultMedia
        : const <LlamaToolResultMedia>{};
  }

  @override
  Future<({bool vision, bool audio})> directMediaInput() async {
    final delegate = _delegate;
    if (delegate is! BackendDirectMediaInput) {
      return (vision: false, audio: false);
    }
    return (delegate as BackendDirectMediaInput).directMediaInput();
  }

  @override
  Future<bool> supportsVision(int mmContextHandle) {
    return _requireMultimodal().supportsVision(mmContextHandle);
  }

  @override
  Future<bool> supportsAudio(int mmContextHandle) {
    return _requireMultimodal().supportsAudio(mmContextHandle);
  }

  @override
  Future<bool?> supportsVideoRuntime(int mmContextHandle) {
    final delegate = _requireDelegate();
    if (delegate is BackendVideoRuntimeSupport) {
      return (delegate as BackendVideoRuntimeSupport).supportsVideoRuntime(
        mmContextHandle,
      );
    }
    return Future<bool?>.value();
  }

  @override
  Future<String?> textToSpeechModelUnsupportedReason(
    BackendTextToSpeechModel model,
  ) async {
    // Text-to-speech models are GGUF, which the llama.cpp delegate loads.
    final delegate = _delegateKind == LlamaRuntime.llamaCpp
        ? _delegate!
        : await _ensureDiagnosticDelegate();
    return delegate is BackendTextToSpeechModelSupport
        ? (delegate as BackendTextToSpeechModelSupport)
              .textToSpeechModelUnsupportedReason(model)
        : null;
  }

  @override
  Future<BackendTextToSpeechCapabilities> textToSpeechCapabilities(
    int contextHandle,
    int mmContextHandle,
  ) {
    final delegate = _requireDelegate();
    if (delegate is! BackendTextToSpeech) {
      return Future<BackendTextToSpeechCapabilities>.value(
        const BackendTextToSpeechCapabilities(
          isSupported: false,
          unsupportedReason:
              'The selected native backend does not expose text-to-speech.',
        ),
      );
    }
    return (delegate as BackendTextToSpeech).textToSpeechCapabilities(
      contextHandle,
      mmContextHandle,
    );
  }

  @override
  Future<BackendTextToSpeechResult> synthesizeTextToSpeech(
    int contextHandle,
    int mmContextHandle,
    BackendTextToSpeechRequest request, {
    void Function(BackendTextToSpeechProgress progress)? onProgress,
  }) {
    final delegate = _requireDelegate();
    if (delegate is! BackendTextToSpeech) {
      throw LlamaUnsupportedException(
        'The selected native backend does not expose text-to-speech.',
      );
    }
    return (delegate as BackendTextToSpeech).synthesizeTextToSpeech(
      contextHandle,
      mmContextHandle,
      request,
      onProgress: onProgress,
    );
  }

  @override
  void cancelTextToSpeech() {
    final delegate = _delegate;
    if (delegate is BackendTextToSpeech) {
      (delegate as BackendTextToSpeech).cancelTextToSpeech();
    }
  }

  @override
  Future<BackendGenerationCapabilities> generationCapabilities() async {
    final delegate = _delegate;
    if (delegate is! BackendGenerationCapabilitiesSupport) {
      return const BackendGenerationCapabilities(
        presencePenalty: false,
        minP: false,
        thinkingBudget: false,
      );
    }
    return (delegate as BackendGenerationCapabilitiesSupport)
        .generationCapabilities();
  }

  @override
  Future<BackendDecisionCapabilities> decisionCapabilities(int modelHandle) {
    final delegate = _requireDelegate();
    if (delegate is! BackendDecision) {
      return Future<BackendDecisionCapabilities>.value(
        const BackendDecisionCapabilities(
          isSupported: false,
          unsupportedReason: _decisionUnsupportedMessage,
        ),
      );
    }
    return (delegate as BackendDecision).decisionCapabilities(modelHandle);
  }

  @override
  Future<BackendDecisionHeadInfo> decisionHeadLoad(
    int modelHandle,
    String headPath, {
    String? configPath,
  }) {
    final delegate = _requireDelegate();
    if (delegate is! BackendDecision) {
      throw LlamaUnsupportedException(_decisionUnsupportedMessage);
    }
    return (delegate as BackendDecision).decisionHeadLoad(
      modelHandle,
      headPath,
      configPath: configPath,
    );
  }

  @override
  Future<List<BackendDecisionOutput>> decisionRun(
    int headHandle,
    List<BackendDecisionSequence> sequences,
  ) {
    final delegate = _requireDelegate();
    if (delegate is! BackendDecision) {
      throw LlamaUnsupportedException(_decisionUnsupportedMessage);
    }
    return (delegate as BackendDecision).decisionRun(headHandle, sequences);
  }

  @override
  Future<void> decisionHeadFree(int headHandle) {
    final delegate = _delegate;
    if (delegate is BackendDecision) {
      return (delegate as BackendDecision).decisionHeadFree(headHandle);
    }
    return Future<void>.value();
  }

  @override
  Future<({int total, int free})> getVramInfo() {
    final delegate = _delegate;
    if (delegate != null) {
      return delegate.getVramInfo();
    }
    return _ensureDiagnosticDelegate().then(
      (diagnosticDelegate) => diagnosticDelegate.getVramInfo(),
    );
  }

  @override
  Future<List<GpuDeviceInfo>> listGpuDevices({
    List<GpuBackend> probeBackends = const [],
  }) {
    final delegate = _delegate;
    if (delegate is BackendGpuEnumeration) {
      return (delegate as BackendGpuEnumeration).listGpuDevices(
        probeBackends: probeBackends,
      );
    }
    // No GPU-enumeration-capable delegate is active (none loaded yet, or a
    // backend like LiteRT-LM that doesn't enumerate). Fall back to the same
    // diagnostic llama.cpp delegate getVramInfo uses before a model load.
    return _ensureDiagnosticDelegate().then((diagnosticDelegate) {
      if (diagnosticDelegate is BackendGpuEnumeration) {
        return (diagnosticDelegate as BackendGpuEnumeration).listGpuDevices(
          probeBackends: probeBackends,
        );
      }
      return const <GpuDeviceInfo>[];
    });
  }

  @override
  Future<String> applyChatTemplate(
    int modelHandle,
    List<Map<String, dynamic>> messages, {
    String? customTemplate,
    bool addAssistant = true,
  }) {
    return _requireDelegate().applyChatTemplate(
      modelHandle,
      messages,
      customTemplate: customTemplate,
      addAssistant: addAssistant,
    );
  }

  @override
  bool get supportsEmbeddings {
    final delegate = _delegate;
    if (delegate is BackendEmbeddingsSupport) {
      return (delegate as BackendEmbeddingsSupport).supportsEmbeddings;
    }
    return delegate is BackendEmbeddings;
  }

  @override
  Future<LlamaEmbeddingCapabilities> getEmbeddingCapabilities(
    int contextHandle,
  ) async {
    final delegate = _delegate;
    if (delegate == null) return const LlamaEmbeddingCapabilities();
    return delegate.probeEmbeddingCapabilities(contextHandle);
  }

  @override
  Future<List<List<double>>> embedContentBatch(
    int contextHandle,
    List<LlamaEmbeddingInput> inputs, {
    bool normalize = true,
  }) {
    final cancelEpoch = _embeddingCancelEpoch;
    return _requireDelegate().embedContentWithFallback(
      contextHandle,
      inputs,
      normalize: normalize,
      onCompute: (compute) {
        // Delegate cancellation starts only after the router's own probe.
        if (cancelEpoch != _embeddingCancelEpoch) {
          throw LlamaInferenceException(
            'Content embedding cancelled before dispatch.',
          );
        }
        return compute();
      },
    );
  }

  @override
  Future<List<double>> embed(
    int contextHandle,
    String text, {
    bool normalize = true,
  }) {
    final delegate = _requireDelegate();
    if (delegate is BackendEmbeddings) {
      return (delegate as BackendEmbeddings).embed(
        contextHandle,
        text,
        normalize: normalize,
      );
    }
    throw UnsupportedError(
      'The selected native backend does not support embeddings.',
    );
  }

  @override
  Future<List<List<double>>> embedBatch(
    int contextHandle,
    List<String> texts, {
    bool normalize = true,
  }) async {
    final delegate = _requireDelegate();
    if (delegate is BackendBatchEmbeddings) {
      return (delegate as BackendBatchEmbeddings).embedBatch(
        contextHandle,
        texts,
        normalize: normalize,
      );
    }
    if (delegate is BackendEmbeddings) {
      final embeddings = <List<double>>[];
      for (final text in texts) {
        embeddings.add(
          await (delegate as BackendEmbeddings).embed(
            contextHandle,
            text,
            normalize: normalize,
          ),
        );
      }
      return embeddings;
    }
    throw UnsupportedError(
      'The selected native backend does not support embeddings.',
    );
  }

  @override
  Future<int> createRerankingContext(int modelHandle, ModelParams params) {
    final delegate = _requireDelegate();
    if (delegate is BackendReranking) {
      return (delegate as BackendReranking).createRerankingContext(
        modelHandle,
        params,
      );
    }
    throw LlamaUnsupportedException(
      'Explicit reranker loading requires the native llama.cpp runtime.',
    );
  }

  @override
  Future<LlamaRerankingCapabilities> getRerankingCapabilities(
    int contextHandle,
  ) async {
    final delegate = _delegate;
    if (delegate is BackendReranking) {
      return (delegate as BackendReranking).getRerankingCapabilities(
        contextHandle,
      );
    }
    return LlamaRerankingCapabilities(
      isSupported: false,
      unsupportedReason:
          'Native reranking requires the llama.cpp runtime and a rank-pooled GGUF model; LiteRT-LM does not expose it.',
    );
  }

  @override
  Future<BackendRerankingOutput> rerank(
    int contextHandle,
    String query,
    List<String> documents,
  ) {
    final delegate = _requireDelegate();
    if (delegate is BackendReranking) {
      return (delegate as BackendReranking).rerank(
        contextHandle,
        query,
        documents,
      );
    }
    throw LlamaUnsupportedException(
      'The selected native runtime does not support reranking.',
    );
  }

  @override
  bool get supportsNextTokenScoring {
    final delegate = _delegate;
    if (delegate is BackendNextTokenScoringSupport) {
      return (delegate as BackendNextTokenScoringSupport)
          .supportsNextTokenScoring;
    }
    return delegate is BackendNextTokenScoring;
  }

  @override
  Future<LlamaNextTokenScores> scoreNextToken(
    int contextHandle,
    String prompt, {
    required List<int> candidates,
    required int topK,
    required bool reusePromptPrefix,
  }) {
    final delegate = _requireDelegate();
    if (delegate is BackendNextTokenScoring) {
      return (delegate as BackendNextTokenScoring).scoreNextToken(
        contextHandle,
        prompt,
        candidates: candidates,
        topK: topK,
        reusePromptPrefix: reusePromptPrefix,
      );
    }
    throw UnsupportedError(
      'The selected native backend does not support next-token scoring.',
    );
  }

  @override
  bool get supportsStatePersistence {
    final delegate = _delegate;
    if (delegate is BackendStatePersistenceSupport) {
      return (delegate as BackendStatePersistenceSupport)
          .supportsStatePersistence;
    }
    return delegate is BackendStatePersistence;
  }

  @override
  Future<bool> stateSaveFile(int contextHandle, String path, List<int> tokens) {
    final delegate = _requireDelegate();
    if (delegate is BackendStatePersistence) {
      return (delegate as BackendStatePersistence).stateSaveFile(
        contextHandle,
        path,
        tokens,
      );
    }
    throw UnsupportedError(
      'The selected native backend does not support state persistence.',
    );
  }

  @override
  Future<StateLoadResult> stateLoadFile(
    int contextHandle,
    String path,
    int tokenCapacity,
  ) {
    final delegate = _requireDelegate();
    if (delegate is BackendStatePersistence) {
      return (delegate as BackendStatePersistence).stateLoadFile(
        contextHandle,
        path,
        tokenCapacity,
      );
    }
    throw UnsupportedError(
      'The selected native backend does not support state persistence.',
    );
  }

  @override
  Future<LlamaStateIdentity> stateIdentity(int contextHandle) {
    final delegate = _requireDelegate();
    if (delegate is BackendStateIdentity) {
      return (delegate as BackendStateIdentity).stateIdentity(contextHandle);
    }
    throw UnsupportedError(
      'The selected native backend does not report a state identity.',
    );
  }

  Future<LlamaBackend> _delegateFor(LlamaRuntime kind) async {
    if (_delegate != null && _delegateKind == kind) {
      return _delegate!;
    }

    final diagnosticDelegate = await _takeDiagnosticDelegate();
    if (_delegate == null &&
        diagnosticDelegate != null &&
        kind == LlamaRuntime.llamaCpp) {
      await diagnosticDelegate.setLogLevel(_currentLogLevel);
      _delegate = diagnosticDelegate;
      _delegateKind = kind;
      return diagnosticDelegate;
    }

    final oldDelegate = _delegate;
    await oldDelegate?.dispose();
    _delegate = null;
    _delegateKind = null;
    await diagnosticDelegate?.dispose();

    final delegate = switch (kind) {
      LlamaRuntime.liteRtLm => _liteRtLmFactory(),
      LlamaRuntime.llamaCpp => _llamaCppFactory(),
    };
    await delegate.setLogLevel(_currentLogLevel);
    _delegate = delegate;
    _delegateKind = kind;
    return delegate;
  }

  Future<LlamaBackend> _ensureDiagnosticDelegate() async {
    final existing = _diagnosticDelegate;
    if (existing != null) {
      return existing;
    }

    final existingStart = _diagnosticDelegateStart;
    if (existingStart != null) {
      return existingStart;
    }

    late final Future<LlamaBackend> start;
    start = () async {
      final delegate = _llamaCppFactory();
      try {
        await delegate.setLogLevel(_currentLogLevel);
        _diagnosticDelegate = delegate;
        return delegate;
      } catch (_) {
        await delegate.dispose();
        rethrow;
      } finally {
        if (identical(_diagnosticDelegateStart, start)) {
          _diagnosticDelegateStart = null;
        }
      }
    }();
    _diagnosticDelegateStart = start;
    return start;
  }

  Future<LlamaBackend?> _takeDiagnosticDelegate() async {
    final start = _diagnosticDelegateStart;
    if (start != null) {
      try {
        await start;
      } catch (_) {
        // The original diagnostic caller receives the failure. Later load and
        // dispose paths should still clear any partially initialized state.
      }
    }
    final delegate = _diagnosticDelegate;
    _diagnosticDelegate = null;
    _diagnosticDelegateStart = null;
    return delegate;
  }

  static const String _decisionUnsupportedMessage =
      'The selected native backend does not run decision models. Load a '
      'ModernBERT encoder GGUF, which uses the llama.cpp backend.';

  LlamaBackend _requireDelegate() {
    final delegate = _delegate;
    if (delegate == null) {
      throw StateError(
        'No native backend has been selected. Load a model first.',
      );
    }
    return delegate;
  }
}
