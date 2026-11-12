import 'package:llamadart/llamadart.dart' as llama;

import '../../api/model_definition.dart';
import 'llama_runtime.dart';
import 'operation_usage.dart';

class LlamaEngineRuntime
    implements
        LlamaRuntime,
        LlamaRuntimeCapabilityProvider,
        LlamaRuntimeInspectionProvider,
        LlamaRuntimeEmbeddingProvider,
        LlamaRuntimeScoringProvider,
        LlamaRuntimeLoraProvider {
  LlamaEngineRuntime({
    llama.LlamaEngine? engine,
    Iterable<llama.LlamaEngineObserver> observers = const [],
  }) : _engine =
           engine ??
           llama.LlamaEngine(
             llama.LlamaBackend(),
             observers: [const UsageObserver(), ...observers],
           );

  final llama.LlamaEngine _engine;
  bool _initialized = false;

  @override
  Future<llama.LlamaEngineCapabilities> get capabilities =>
      _engine.capabilities;

  @override
  Future<int?> get contextSize async {
    if (const bool.fromEnvironment('dart.library.js_interop')) return null;
    if (_engine.runtime != llama.LlamaRuntime.llamaCpp) return null;
    final size = await _engine.getContextSize();
    return size > 0 ? size : null;
  }

  @override
  Future<List<int>> tokenize(String text, {bool addSpecial = false}) =>
      _engine.tokenize(text, addSpecial: addSpecial);

  @override
  Future<llama.LlamaNextTokenScores> scoreNextToken(
    String prompt, {
    List<int> candidates = const [],
    int topK = 0,
    bool reusePromptPrefix = true,
  }) => _engine.scoreNextToken(
    prompt,
    candidates: candidates,
    topK: topK,
    reusePromptPrefix: reusePromptPrefix,
  );

  @override
  Future<bool> get supportsLiveLora async =>
      !const bool.fromEnvironment('dart.library.js_interop') &&
      _engine.isReady &&
      _engine.runtime == llama.LlamaRuntime.llamaCpp;

  @override
  Future<void> setLoraSource(
    llama.ModelSource source, {
    double scale = 1,
    llama.ModelLoadOptions download = llama.ModelLoadOptions.defaults,
    llama.ModelDownloadProgressCallback? onProgress,
  }) => _engine.setLoraSource(
    source,
    scale: scale,
    download: download,
    onProgress: onProgress,
  );

  @override
  Future<void> removeLoraSource(llama.ModelSource source) =>
      _engine.removeLoraSource(source);

  @override
  Future<void> clearLoras() => _engine.clearLoras();

  bool get supportsPromptCache =>
      _engine.supportsStatePersistence && _engine.supportsNextTokenScoring;

  Future<List<int>> savePromptCache(String prompt, String path) async {
    final tokens = await _engine.tokenize(prompt, addSpecial: true);
    final capacity = await _engine.getContextSize();
    if (tokens.isEmpty || tokens.length >= capacity) {
      throw llama.LlamaStateException(
        'The prompt exceeds the cache context budget.',
      );
    }
    final scores = await _engine.scoreNextToken(
      prompt,
      topK: 1,
      reusePromptPrefix: false,
    );
    if (scores.promptTokens != tokens.length ||
        !await _engine.stateSaveFile(path, tokens: tokens)) {
      throw llama.LlamaStateException(
        'Unable to save the evaluated raw prompt.',
      );
    }
    return tokens;
  }

  Future<List<int>> loadPromptCache(String path, int tokenCapacity) async =>
      (await _engine.stateLoadFile(path, tokenCapacity: tokenCapacity)).tokens;

  @override
  Future<void> initialize(LlamaModelDefinition definition) async {
    if (_initialized) {
      return;
    }

    await _engine.setModel(
      llama.LlamaModel(
        llama.ModelSource.path(definition.modelPath),
        projector: definition.mmprojPath == null
            ? null
            : llama.ModelSource.path(definition.mmprojPath!),
      ),
      params: definition.modelParams,
    );
    _initialized = true;
  }

  @override
  Stream<llama.LlamaCompletionChunk> create(
    List<llama.LlamaChatMessage> messages, {
    llama.GenerationParams? params,
    List<llama.ToolDefinition>? tools,
    llama.ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = false,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
  }) {
    return _engine.create(
      messages,
      params: params,
      tools: tools,
      toolChoice: toolChoice,
      parallelToolCalls: parallelToolCalls,
      enableThinking: enableThinking,
      chatTemplateKwargs: _languageKwargs(
        chatTemplateKwargs,
        sourceLangCode,
        targetLangCode,
      ),
    );
  }

  @override
  Future<llama.LlamaChatTemplateResult> chatTemplate(
    List<llama.LlamaChatMessage> messages, {
    bool addAssistant = true,
    List<llama.ToolDefinition>? tools,
    llama.ToolChoice toolChoice = llama.ToolChoice.auto,
    bool parallelToolCalls = false,
    bool enableThinking = false,
    Map<String, dynamic>? responseFormat,
    String? sourceLangCode,
    String? targetLangCode,
    bool includeTokenCount = false,
    Map<String, dynamic>? chatTemplateKwargs,
  }) {
    return _engine.chatTemplate(
      messages,
      addAssistant: addAssistant,
      tools: tools,
      toolChoice: toolChoice,
      parallelToolCalls: parallelToolCalls,
      enableThinking: enableThinking,
      responseFormat: responseFormat,
      includeTokenCount: includeTokenCount,
      chatTemplateKwargs: _languageKwargs(
        chatTemplateKwargs,
        sourceLangCode,
        targetLangCode,
      ),
    );
  }

  @override
  Stream<String> generate(
    String prompt, {
    llama.GenerationParams params = const llama.GenerationParams(),
    List<llama.LlamaContentPart>? parts,
  }) {
    return _engine.generate(prompt, params: params, parts: parts);
  }

  @override
  Future<List<List<double>>> embedBatch(
    List<String> texts, {
    bool normalize = true,
  }) {
    return _engine.embedBatch(texts, normalize: normalize);
  }

  @override
  Future<llama.LlamaEmbeddingCapabilities> get embeddingCapabilities =>
      _engine.embeddingCapabilities;

  @override
  Future<List<List<double>>> embedContentBatch(
    List<llama.LlamaEmbeddingInput> inputs, {
    bool normalize = true,
  }) => _engine.embedContentBatch(inputs, normalize: normalize);

  @override
  void cancelGeneration() => _engine.cancelGeneration();

  @override
  Future<void> dispose() async {
    await _engine.dispose();
  }
}

Map<String, dynamic>? _languageKwargs(
  Map<String, dynamic>? kwargs,
  String? source,
  String? target,
) {
  final hasSource = source != null && source.isNotEmpty;
  final hasTarget = target != null && target.isNotEmpty;
  if (!hasSource && !hasTarget) return kwargs;
  return <String, dynamic>{
    ...?kwargs,
    if (hasSource) 'source_lang_code': source,
    if (hasTarget) 'target_lang_code': target,
  };
}
