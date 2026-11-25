import '../../core/engine/engine_observer.dart';
import '../../core/exceptions.dart';
import '../../core/models/chat/content_part.dart';
import '../../core/models/chat/chat_message.dart';
import '../../core/models/chat/completion_chunk.dart';
import '../../core/models/inference/tool_choice.dart';
import '../../core/models/tools/tool_definition.dart';
import '../../core/models/config/log_level.dart';
import '../../core/models/inference/generation_params.dart';
import '../../core/models/inference/generation_usage.dart';
import '../../core/models/inference/model_params.dart';
import '../../core/models/inference/model_params_runtime_support.dart';
import '../../core/models/inference/embedding.dart';
import '../../core/models/inference/next_token_scores.dart';
import '../../core/models/model_format.dart';
import '../../core/template/media_placeholders.dart';
import '../backend.dart';
import '../litert_lm/litert_lm_backend_web.dart';
import '../webgpu/webgpu_backend.dart';

/// Creates a web backend that can route between multiple web runtimes.
LlamaBackend createBackend() => WebAutoBackend();

/// Creates the explicit LiteRT-LM Web text-history router.
LlamaBackend createTextHistoryBackend() => WebAutoBackend.withTextHistory();

/// Uses the unified web backend implementation.
///
/// The runtime fetches a model URL itself, so the URL picks the runtime before
/// any content is read: an explicit [ModelFormat], then a `.litertlm` path
/// extension, select LiteRT-LM, and anything else uses the llama.cpp WebGPU
/// bridge.
class WebAutoBackend
    implements
        BackendRuntimeIdentity,
        BackendModelFormatRouting,
        BackendLoadCheck,
        LlamaBackend,
        BackendAvailability,
        BackendLoraSupport,
        BackendMultimodalSupport,
        BackendChatScope,
        BackendEmbeddingsSupport,
        BackendMultimodalEmbeddings,
        BackendBatchEmbeddings,
        BackendPromptSpeechToTextSupport,
        BackendGrammarConstraintsSupport,
        BackendLazyGrammarSupport,
        BackendDeferredEngineCreation,
        BackendTextToSpeech,
        BackendTextToSpeechModelSupport,
        BackendDecision,
        BackendGenerationCapabilitiesSupport,
        BackendGenerationUsageReporting,
        BackendGenerationLimitReporting,
        BackendGenerationLimitSupport,
        BackendRuntimeToolCalls,
        BackendChatPromptGeneration,
        BackendPromptPenaltyGeneration,
        BackendNextTokenScoring,
        BackendNextTokenScoringSupport,
        BackendStatePersistence,
        BackendStatePersistenceSupport {
  static const String _decisionUnsupportedMessage =
      'The active Web runtime does not run decision models. Load a '
      'ModernBERT encoder GGUF, which uses the llama.cpp WebGPU bridge.';

  final LlamaBackend Function() _webGpuFactory;
  final LlamaBackend Function() _liteRtLmFactory;

  LlamaBackend? _delegate;
  int _embeddingCancelEpoch = 0;
  LlamaRuntime? _delegateKind;
  LlamaLogLevel _currentLogLevel = LlamaLogLevel.warn;

  /// Creates a web backend router.
  ///
  /// Optional backend is injectable for legacy tests that need a fixed
  /// delegate. Factory overrides are injectable for router tests.
  WebAutoBackend({
    LlamaBackend? webBackend,
    LlamaBackend Function()? webGpuFactory,
    LlamaBackend Function()? liteRtLmFactory,
  }) : _webGpuFactory =
           webGpuFactory ?? (() => webBackend ?? WebGpuLlamaBackend()),
       _liteRtLmFactory = liteRtLmFactory ?? (() => LiteRtLmBackend()) {
    if (webBackend != null) {
      _delegate = webBackend;
      _delegateKind = LlamaRuntime.llamaCpp;
    }
  }

  /// Creates an internal Web router with LiteRT-LM text history enabled.
  ///
  /// Only a delegate exposing the native chat SPI receives structured chat.
  /// The original constructor preserves legacy/custom subclass dispatch.
  factory WebAutoBackend.withTextHistory({
    LlamaBackend? webBackend,
    LlamaBackend Function()? webGpuFactory,
    LlamaBackend Function()? liteRtLmFactory,
  }) => _TextHistoryWebAutoBackend(
    webBackend: webBackend,
    webGpuFactory: webGpuFactory,
    liteRtLmFactory: liteRtLmFactory,
  );

  @override
  bool get isReady => _delegate?.isReady ?? false;

  @override
  String? checkLoad(ModelParams params, ModelFormat? format) {
    if (format == null) return null;
    checkModelParamsSupportedBy(params, format.runtime, web: true);
    if (format.runtime == LlamaRuntime.liteRtLm) liteRtLmWebCheckLoad(params);
    return null;
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
      'Next-token scoring is not supported by the active web backend.',
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
  bool get supportsGrammarConstraints {
    final delegate = _delegate;
    if (delegate is BackendGrammarConstraintsSupport) {
      return (delegate as BackendGrammarConstraintsSupport)
          .supportsGrammarConstraints;
    }
    return true;
  }

  @override
  bool get supportsMultiTurnChat {
    final delegate = _delegate;
    return delegate is! BackendChatScope ||
        (delegate as BackendChatScope).supportsMultiTurnChat;
  }

  @override
  bool get supportsToolCalling {
    final delegate = _delegate;
    return delegate is! BackendChatScope ||
        (delegate as BackendChatScope).supportsToolCalling;
  }

  @override
  bool get supportsLazyGrammar {
    final delegate = _delegate;
    if (delegate is BackendLazyGrammarSupport) {
      return (delegate as BackendLazyGrammarSupport).supportsLazyGrammar;
    }
    return true;
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
  bool get supportsPromptSpeechToText {
    final delegate = _delegate;
    final speechDelegate = delegate is BackendPromptSpeechToTextSupport
        ? delegate as BackendPromptSpeechToTextSupport
        : null;
    return speechDelegate?.supportsPromptSpeechToText ?? false;
  }

  @override
  String? get promptSpeechToTextUnsupportedReason {
    final delegate = _delegate;
    final speechDelegate = delegate is BackendPromptSpeechToTextSupport
        ? delegate as BackendPromptSpeechToTextSupport
        : null;
    if (speechDelegate != null) {
      return speechDelegate.promptSpeechToTextUnsupportedReason;
    }
    return 'The active Web runtime does not expose validated typed '
        'speech-to-text support.';
  }

  @override
  Future<int> modelLoad(String path, ModelParams params) async {
    final delegate = await _delegateFor(_runtimeForSource(path));
    return delegate.modelLoad(path, params);
  }

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    void Function(double p1)? onProgress,
  }) async {
    final delegate = await _delegateFor(_runtimeForSource(url));
    return delegate.modelLoadFromUrl(url, params, onProgress: onProgress);
  }

  @override
  Future<int> modelLoadAs(
    String path,
    ModelParams params,
    ModelFormat format,
  ) async {
    final delegate = await _delegateFor(format.runtime);
    if (delegate is BackendModelFormatRouting) {
      return (delegate as BackendModelFormatRouting).modelLoadAs(
        path,
        params,
        format,
      );
    }
    return delegate.modelLoad(path, params);
  }

  @override
  Future<int> modelLoadFromUrlAs(
    String url,
    ModelParams params,
    ModelFormat format, {
    void Function(double progress)? onProgress,
  }) async {
    final delegate = await _delegateFor(format.runtime);
    if (delegate is BackendModelFormatRouting) {
      return (delegate as BackendModelFormatRouting).modelLoadFromUrlAs(
        url,
        params,
        format,
        onProgress: onProgress,
      );
    }
    return delegate.modelLoadFromUrl(url, params, onProgress: onProgress);
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
        'The selected Web runtime cannot preserve prompt penalties with a '
        'grammar. WebGPU needs bridge assets v0.1.82+ whose loaded core '
        'reports penaltyPromptTokensWithGrammar.',
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
  void cancelGeneration() {
    _embeddingCancelEpoch++;
    _delegate?.cancelGeneration();
  }

  @override
  Future<String?> textToSpeechModelUnsupportedReason(
    BackendTextToSpeechModel model,
  ) async => webTextToSpeechModelUnsupportedReason(model);

  @override
  Future<BackendTextToSpeechCapabilities> textToSpeechCapabilities(
    int contextHandle,
    int mmContextHandle,
  ) {
    final delegate = _delegate;
    if (delegate is BackendTextToSpeech) {
      return (delegate as BackendTextToSpeech).textToSpeechCapabilities(
        contextHandle,
        mmContextHandle,
      );
    }
    return Future<BackendTextToSpeechCapabilities>.value(
      const BackendTextToSpeechCapabilities(
        isSupported: false,
        unsupportedReason:
            'The active Web runtime does not expose dedicated text-to-speech.',
      ),
    );
  }

  @override
  Future<BackendTextToSpeechResult> synthesizeTextToSpeech(
    int contextHandle,
    int mmContextHandle,
    BackendTextToSpeechRequest request, {
    void Function(BackendTextToSpeechProgress progress)? onProgress,
  }) {
    final delegate = _delegate;
    if (delegate is BackendTextToSpeech) {
      return (delegate as BackendTextToSpeech).synthesizeTextToSpeech(
        contextHandle,
        mmContextHandle,
        request,
        onProgress: onProgress,
      );
    }
    throw LlamaUnsupportedException(
      'Text-to-speech is not supported by the active Web runtime.',
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
      'Embeddings are not supported by the active web backend.',
    );
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

    final delegate = _requireDelegate();
    if (delegate is BackendBatchEmbeddings) {
      return (delegate as BackendBatchEmbeddings).embedBatch(
        contextHandle,
        texts,
        normalize: normalize,
      );
    }

    if (delegate is BackendEmbeddings) {
      final vectors = <List<double>>[];
      for (final text in texts) {
        vectors.add(
          await (delegate as BackendEmbeddings).embed(
            contextHandle,
            text,
            normalize: normalize,
          ),
        );
      }
      return vectors;
    }

    throw UnsupportedError(
      'Embeddings are not supported by the active web backend.',
    );
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
      'State persistence is not supported by the active web backend.',
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
      'State persistence is not supported by the active web backend.',
    );
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
      'LoRA adapters are not supported by the active Web runtime.',
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
  String? get generationLimitUnsupportedReason {
    final delegate = _delegate;
    return delegate is BackendGenerationLimitSupport
        ? (delegate as BackendGenerationLimitSupport)
              .generationLimitUnsupportedReason
        : null;
  }

  @override
  BackendGenerationLimit? generationLimitOf(Stream<List<int>> generation) =>
      generationLimitReporterOf(_delegate)?.generationLimitOf(generation);

  @override
  List<LlamaCompletionChunkToolCall>? runtimeToolCallsOf(
    Stream<List<int>> generation,
  ) => runtimeToolCallReporterOf(_delegate)?.runtimeToolCallsOf(generation);

  @override
  LlamaGenerationUsage? generationUsageOf(Stream<List<int>> generation) {
    final delegate = _delegate;
    return delegate is BackendGenerationUsageReporting
        ? (delegate as BackendGenerationUsageReporting).generationUsageOf(
            generation,
          )
        : null;
  }

  @override
  Future<String> getBackendName() {
    final delegate = _delegate;
    if (delegate == null) {
      return Future<String>.value('Web auto');
    }
    return delegate.getBackendName();
  }

  @override
  Future<String> getAvailableBackends() {
    final delegate = _delegate;
    if (delegate is BackendAvailability) {
      return (delegate as BackendAvailability).getAvailableBackends();
    }
    if (delegate != null) {
      return delegate.getBackendName();
    }
    return Future<String>.value('llama.cpp webgpu, LiteRT-LM web');
  }

  @override
  bool get supportsUrlLoading => true;

  @override
  Future<bool> isGpuSupported() {
    final delegate = _delegate;
    if (delegate != null) {
      return delegate.isGpuSupported();
    }
    final diagnosticDelegate = _webGpuFactory();
    return diagnosticDelegate.isGpuSupported().whenComplete(
      diagnosticDelegate.dispose,
    );
  }

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {
    _currentLogLevel = level;
    await _delegate?.setLogLevel(level);
  }

  @override
  Future<void> dispose() async {
    final delegate = _delegate;
    _delegate = null;
    _delegateKind = null;
    await delegate?.dispose();
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
      'Multimodal projectors are not supported by the active Web runtime.',
    );
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
  Future<({int total, int free})> getVramInfo() {
    final delegate = _delegate;
    if (delegate != null) {
      return delegate.getVramInfo();
    }
    return Future<({int total, int free})>.value((total: 0, free: 0));
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

  Future<LlamaBackend> _delegateFor(LlamaRuntime kind) async {
    if (_delegate != null && _delegateKind == kind) {
      return _delegate!;
    }

    final oldDelegate = _delegate;
    _delegate = null;
    _delegateKind = null;
    await oldDelegate?.dispose();

    final delegate = switch (kind) {
      LlamaRuntime.liteRtLm => _liteRtLmFactory(),
      LlamaRuntime.llamaCpp => _webGpuFactory(),
    };
    await delegate.setLogLevel(_currentLogLevel);
    _delegate = delegate;
    _delegateKind = kind;
    return delegate;
  }

  LlamaRuntime _runtimeForSource(String source) {
    return ModelFormat.fromPath(_sourcePath(source))?.runtime ??
        LlamaRuntime.llamaCpp;
  }

  String _sourcePath(String source) {
    final uri = Uri.tryParse(source);
    if (uri != null && uri.path.isNotEmpty) {
      return uri.path;
    }
    final queryIndex = source.indexOf('?');
    return queryIndex < 0 ? source : source.substring(0, queryIndex);
  }

  LlamaBackend _requireDelegate() {
    final delegate = _delegate;
    if (delegate == null) {
      throw LlamaStateException(
        'No web backend has been selected. Load a model with '
        'LlamaEngine.load or setModel first.',
      );
    }
    return delegate;
  }
}

// The explicit text-history factory selects this private subtype without
// changing the required members or dispatch of the public generative class.
final class _TextHistoryWebAutoBackend extends WebAutoBackend
    implements BackendNativeChatGeneration, BackendChatMessageValidation {
  _TextHistoryWebAutoBackend({
    super.webBackend,
    super.webGpuFactory,
    LlamaBackend Function()? liteRtLmFactory,
  }) : super(
         liteRtLmFactory: liteRtLmFactory ?? LiteRtLmBackend.withTextHistory,
       );

  @override
  bool get supportsNativeChatGeneration {
    final delegate = _delegate;
    return delegate is BackendNativeChatGeneration &&
        (delegate as BackendNativeChatGeneration).supportsNativeChatGeneration;
  }

  @override
  bool get requiresStructuredChatInput {
    final delegate = _delegate;
    return delegate is BackendChatMessageValidation &&
        (delegate as BackendChatMessageValidation).requiresStructuredChatInput;
  }

  @override
  void validateChatMessages(List<LlamaChatMessage> messages) {
    final delegate = _delegate;
    if (delegate is BackendChatMessageValidation) {
      (delegate as BackendChatMessageValidation).validateChatMessages(messages);
    }
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
    String? sourceLangCode,
    String? targetLangCode,
    DateTime? templateNow,
  }) {
    final delegate = _requireDelegate();
    if (delegate is! BackendNativeChatGeneration) {
      throw LlamaUnsupportedException(
        'The selected Web runtime has no structured chat API.',
      );
    }
    return (delegate as BackendNativeChatGeneration).generateChat(
      contextHandle,
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
  }
}
