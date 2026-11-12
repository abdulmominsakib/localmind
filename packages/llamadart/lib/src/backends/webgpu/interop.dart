@JS()
library;

import 'dart:js_interop';

/// JS bridge constructor for llama.cpp WebGPU runtime.
@JS('LlamaWebGpuBridge')
extension type LlamaWebGpuBridge._(JSObject _) implements JSObject {
  /// Creates a bridge instance.
  external factory LlamaWebGpuBridge([WebGpuBridgeConfig? config]);

  /// Loads a GGUF model from a URL.
  external JSPromise<JSAny?>? loadModelFromUrl(
    String url, [
    WebGpuLoadModelOptions? options,
  ]);

  /// Prefetches a model URL into browser cache storage.
  external JSPromise<JSAny?>? prefetchModelToCache(
    String url, [
    WebGpuCacheOptions? options,
  ]);

  /// Evicts a model URL from browser cache storage.
  external JSPromise<JSAny?>? evictModelFromCache(
    String url, [
    WebGpuCacheOptions? options,
  ]);

  /// Generates completion output for a prompt.
  external JSPromise<JSAny?>? createCompletion(
    String prompt, [
    WebGpuCompletionOptions? options,
  ]);

  /// Reports which optional completion options the loaded core applies.
  external JSPromise<JSAny?>? getCompletionCapabilities();

  /// Loads the draft GGUF at [url] for draft-model speculative decoding,
  /// replacing any draft.
  external JSPromise<JSAny?>? loadDraftModel(
    String url, [
    WebGpuDraftModelLoadOptions? options,
  ]);

  /// Frees the draft model.
  external JSPromise<JSAny?>? unloadDraftModel();

  /// Loads multimodal projector from URL/path.
  external JSPromise<JSAny?>? loadMultimodalProjector(String url);

  /// Unloads multimodal projector if loaded.
  external JSPromise<JSAny?>? unloadMultimodalProjector();

  /// Returns whether loaded projector supports vision.
  external bool? supportsVision();

  /// Returns whether loaded projector supports audio.
  external bool? supportsAudio();

  /// Returns dedicated text-to-speech capabilities for the loaded projector.
  external JSPromise<JSAny?>? getTextToSpeechCapabilities();

  /// Synthesizes one complete speech buffer.
  external JSPromise<JSAny?>? synthesizeSpeech(
    WebGpuTextToSpeechOptions options,
  );

  /// Returns decision-head support for the loaded model.
  external JSPromise<JSAny?>? getDecisionCapabilities();

  /// Loads a decision head from a URL for the loaded model.
  external JSPromise<JSAny?>? loadDecisionHead(
    String url, [
    WebGpuDecisionHeadOptions? options,
  ]);

  /// Runs decision sequences through the encoder and the head [handle].
  external JSPromise<JSAny?>? runDecision(
    int handle,
    JSArray<WebGpuDecisionSequence> sequences,
  );

  /// Frees the decision head [handle]; unknown handles are ignored.
  external JSPromise<JSAny?>? freeDecisionHead(int handle);

  /// Reports whether the loaded core can load LoRA adapters.
  external JSPromise<JSAny?>? getLoraAdapterCapabilities();

  /// Loads the LoRA adapter at [source] without applying it.
  external JSPromise<JSAny?>? loadLoraAdapter(
    String source, [
    WebGpuLoraAdapterLoadOptions? options,
  ]);

  /// Applies the LoRA adapter [handle] at [scale].
  external JSPromise<JSAny?>? setLoraAdapter(int handle, double scale);

  /// Stops applying the LoRA adapter [handle]; it stays loaded.
  external JSPromise<JSAny?>? removeLoraAdapter(int handle);

  /// Stops applying every LoRA adapter; they stay loaded.
  external JSPromise<JSAny?>? clearLoraAdapters();

  /// Tokenizes text.
  external JSPromise<JSAny>? tokenize(String text, [bool? addSpecial]);

  /// Detokenizes token ids.
  external JSPromise<JSString>? detokenize(JSArray tokens, [bool? special]);

  /// Saves the active KV-cache/session state to a bridge WASMFS path.
  external JSPromise<JSAny?>? stateSaveFile(String path, JSArray tokens);

  /// Loads KV-cache/session state from a bridge WASMFS path.
  external JSPromise<JSAny?>? stateLoadFile(String path, int tokenCapacity);

  /// Probes loaded-model embedding modalities (API version 1).
  external JSPromise<JSAny?>? getEmbeddingCapabilities();

  /// Generates one vector for a string or an ordered embedding-parts array.
  external JSPromise<JSAny?>? embed(
    JSAny input, [
    WebGpuEmbeddingOptions? options,
  ]);

  /// Generates embedding vectors for all input texts.
  external JSPromise<JSAny?>? embedBatch(
    JSArray texts, [
    WebGpuEmbeddingOptions? options,
  ]);

  /// Scores the token that would follow [prompt].
  external JSPromise<JSAny?>? scoreNextToken(
    String prompt, [
    WebGpuNextTokenScoreOptions? options,
  ]);

  /// Returns model metadata as a plain JS object.
  external JSObject? getModelMetadata();

  /// Returns current context size if available.
  external int? getContextSize();

  /// Returns true when GPU compute is active.
  external bool? isGpuActive();

  /// Returns a backend display name.
  external JSString? getBackendName();

  /// Updates runtime log level in the underlying core.
  external JSAny? setLogLevel(int level);

  /// Cancels active generation.
  external JSAny? cancel();

  /// Disposes runtime resources.
  external JSPromise<JSAny?>? dispose();

  /// Applies chat template.
  external JSPromise<JSString>? applyChatTemplate(
    JSArray messages,
    bool addAssistant, [
    String? customTemplate,
  ]);
}

/// Bridge construction config.
@JS()
@anonymous
extension type WebGpuBridgeConfig._(JSObject _) implements JSObject {
  /// Creates a config object for the JS bridge.
  external factory WebGpuBridgeConfig({
    JSString? wasmUrl,
    @JS('wasmUrlMem64') JSString? wasmUrlMem64,
    JSString? workerUrl,
    @JS('coreModuleUrl') JSString? coreModuleUrl,
    @JS('coreModuleUrlMem64') JSString? coreModuleUrlMem64,
    bool? preferMemory64,
    int? threadPoolSize,
    @JS('allowAutoRemoteFetchBackend') bool? allowAutoRemoteFetchBackend,
    int? remoteFetchThresholdBytes,
    int? remoteFetchChunkBytes,
    int? logLevel,
    JSObject? logger,
  });
}

/// Model loading options.
@JS()
@anonymous
extension type WebGpuLoadModelOptions._(JSObject _) implements JSObject {
  /// Creates model loading options.
  external factory WebGpuLoadModelOptions({
    @JS('nCtx') int? nCtx,
    @JS('nThreads') int? nThreads,
    @JS('nThreadsBatch') int? nThreadsBatch,
    @JS('nBatch') int? nBatch,
    @JS('nUbatch') int? nUbatch,
    @JS('nGpuLayers') int? nGpuLayers,
    @JS('nSeqMax') int? nSeqMax,
    @JS('flashAttention') int? flashAttention,
    @JS('cacheTypeK') int? cacheTypeK,
    @JS('cacheTypeV') int? cacheTypeV,
    @JS('kvUnified') bool? kvUnified,
    @JS('ropeFrequencyBase') double? ropeFrequencyBase,
    @JS('ropeFrequencyScale') double? ropeFrequencyScale,
    @JS('splitMode') int? splitMode,
    @JS('mainGpu') int? mainGpu,
    @JS('useCache') bool? useCache,
    @JS('forceRemoteFetchBackend') bool? forceRemoteFetchBackend,
    @JS('remoteFetchThresholdBytes') int? remoteFetchThresholdBytes,
    @JS('remoteFetchChunkBytes') int? remoteFetchChunkBytes,
    @JS('modelBytesHint') int? modelBytesHint,
    @JS('loadMtp') bool? loadMtp,
    @JS('speculativeRollbackTokenMax') int? speculativeRollbackTokenMax,
    @JS('progressCallback') JSFunction? progressCallback,
  });
}

/// Cache prefetch/eviction options.
@JS()
@anonymous
extension type WebGpuCacheOptions._(JSObject _) implements JSObject {
  /// Creates cache options.
  external factory WebGpuCacheOptions({
    bool? useCache,
    bool? force,
    JSString? cacheName,
    @JS('progressCallback') JSFunction? progressCallback,
  });
}

/// Completion options.
@JS()
@anonymous
extension type WebGpuCompletionOptions._(JSObject _) implements JSObject {
  /// Creates completion options.
  external factory WebGpuCompletionOptions({
    @JS('nPredict') int? nPredict,
    @JS('mediaMaxPredict') int? mediaMaxPredict,
    double? temp,
    @JS('topK') int? topK,
    @JS('topP') double? topP,
    @JS('minP') double? minP,
    double? penalty,
    @JS('presencePenalty') double? presencePenalty,
    int? seed,
    String? grammar,
    @JS('grammarLazy') bool? grammarLazy,
    @JS('grammarRoot') String? grammarRoot,
    @JS('grammarTriggers') JSArray<WebGpuGrammarTrigger>? grammarTriggers,
    @JS('thinkingBudget') WebGpuThinkingBudgetOptions? thinkingBudget,
    @JS('speculativeDecoding')
    WebGpuSpeculativeDecodingOptions? speculativeDecoding,
    @JS('mediaMaxImagePixels') int? mediaMaxImagePixels,
    @JS('mediaMaxImageEdge') int? mediaMaxImageEdge,
    @JS('onToken') JSFunction? onToken,
    @JS('onUsage') JSFunction? onUsage,
    @JS('emitCurrentTextOnToken') bool? emitCurrentTextOnToken,
    @JS('tokenEventEncoding') String? tokenEventEncoding,
    @JS('tokenEventFlushMs') int? tokenEventFlushMs,
    @JS('tokenEventFlushChars') int? tokenEventFlushChars,
    bool? warmup,
    JSArray? parts,
    JSAny? signal,
  });

  /// `false` keeps the prompt out of the penalty window; set only when the
  /// core reports `penaltyPromptTokens`.
  @JS('penaltyPromptTokens')
  external set penaltyPromptTokens(bool value);

  /// Seeds only the penalty sampler, leaving an attached grammar untouched.
  /// Set only when the loaded core reports this capability.
  @JS('penaltyPromptTokensWithGrammar')
  external set penaltyPromptTokensWithGrammar(bool value);
}

/// A lazy-grammar activation in the bridge's string-based trigger protocol.
@JS()
@anonymous
extension type WebGpuGrammarTrigger._(JSObject _) implements JSObject {
  /// Creates a text or token trigger; token triggers use [token].
  external factory WebGpuGrammarTrigger({
    required String type,
    String? value,
    int? token,
  });
}

/// Reasoning-block budget in [WebGpuCompletionOptions].
@JS()
@anonymous
extension type WebGpuThinkingBudgetOptions._(JSObject _) implements JSObject {
  /// Creates a thinking budget.
  external factory WebGpuThinkingBudgetOptions({
    @JS('maxTokens') required int maxTokens,
    @JS('startTag') required String startTag,
    @JS('endTag') required String endTag,
    @JS('forcedMessage') required String forcedMessage,
  });
}

/// Completion options reported by `getCompletionCapabilities`.
@JS()
@anonymous
extension type WebGpuCompletionCapabilities._(JSObject _) implements JSObject {
  /// Whether the loaded core applies `presencePenalty`.
  @JS('presencePenalty')
  external JSAny? get presencePenalty;

  /// Whether the loaded core applies `minP`.
  @JS('minP')
  external JSAny? get minP;

  /// Whether the loaded core applies `thinkingBudget`.
  @JS('thinkingBudget')
  external JSAny? get thinkingBudget;

  /// Whether the loaded core counts the prompt in its penalty window and
  /// applies `penaltyPromptTokens`.
  @JS('penaltyPromptTokens')
  external JSAny? get penaltyPromptTokens;

  /// Whether the loaded core can seed prompt penalties with attached grammar.
  @JS('penaltyPromptTokensWithGrammar')
  external JSAny? get penaltyPromptTokensWithGrammar;

  /// Whether the loaded core applies lazy grammars and custom grammar roots.
  @JS('lazyGrammar')
  external JSAny? get lazyGrammar;

  /// Whether the loaded models can run each speculative strategy, by its
  /// llama.cpp name.
  @JS('speculativeDecoding')
  external JSAny? get speculativeDecoding;
}

/// Speculative decoding in [WebGpuCompletionOptions]; a null field keeps the
/// llama.cpp default.
@JS()
@anonymous
extension type WebGpuSpeculativeDecodingOptions._(JSObject _)
    implements JSObject {
  /// Creates speculative decoding options.
  external factory WebGpuSpeculativeDecodingOptions({
    required JSArray<JSString> strategies,
    @JS('draftTokenMax') int? draftTokenMax,
    @JS('draftTokenMin') int? draftTokenMin,
    @JS('minProbability') double? minProbability,
    @JS('draftSplitProbability') double? draftSplitProbability,
    @JS('ngramSizeN') int? ngramSizeN,
    @JS('ngramSizeM') int? ngramSizeM,
    @JS('ngramMinHits') int? ngramMinHits,
    @JS('ngramMatch') int? ngramMatch,
    @JS('ngramTokenMin') int? ngramTokenMin,
    @JS('ngramTokenMax') int? ngramTokenMax,
    @JS('ngramCacheStatic') String? ngramCacheStatic,
    @JS('ngramCacheDynamic') String? ngramCacheDynamic,
  });
}

/// Draft model load options.
@JS()
@anonymous
extension type WebGpuDraftModelLoadOptions._(JSObject _) implements JSObject {
  /// Creates draft model load options.
  external factory WebGpuDraftModelLoadOptions({
    @JS('useCache') bool? useCache,
    JSAny? signal,
  });
}

/// A draft model loaded by `loadDraftModel`.
@JS()
@anonymous
extension type WebGpuDraftModelInfo._(JSObject _) implements JSObject {
  /// The draft GGUF's `general.architecture`.
  external JSAny? get architecture;
}

/// Embedding options.
@JS()
@anonymous
extension type WebGpuEmbeddingOptions._(JSObject _) implements JSObject {
  /// Creates embedding options.
  external factory WebGpuEmbeddingOptions({bool? normalize});
}

/// Next-token scoring options.
@JS()
@anonymous
extension type WebGpuNextTokenScoreOptions._(JSObject _) implements JSObject {
  /// Creates next-token scoring options.
  external factory WebGpuNextTokenScoreOptions({
    JSArray<JSNumber>? candidates,
    int? topK,
    bool? reusePromptPrefix,
  });
}

/// Dedicated text-to-speech options accepted by the WebGPU bridge.
@JS()
@anonymous
extension type WebGpuTextToSpeechOptions._(JSObject _) implements JSObject {
  /// Creates a complete synthesis request.
  external factory WebGpuTextToSpeechOptions({
    required String text,
    String? language,
    JSUint8Array? speakerAudio,
    int? promptBatchSize,
    int? maxFrames,
    int? topK,
    double? topP,
    double? minP,
    double? temperature,
    int? seed,
    JSAny? signal,
    JSFunction? onProgress,
  });
}

/// Decision-head support reported by `getDecisionCapabilities`.
@JS()
@anonymous
extension type WebGpuDecisionCapabilities._(JSObject _) implements JSObject {
  /// Decision API version of the bridge.
  external JSAny? get apiVersion;

  /// Whether the loaded model can run decision heads.
  external JSAny? get supported;

  /// Why the loaded model cannot run decision heads.
  external JSAny? get reason;
}

/// Decision-head load options.
@JS()
@anonymous
extension type WebGpuDecisionHeadOptions._(JSObject _) implements JSObject {
  /// Creates head load options.
  ///
  /// [configJson] is Laya's `rl_agent_config.json` text; without it the
  /// bridge reads the head's `laya.config` metadata.
  external factory WebGpuDecisionHeadOptions({
    @JS('configJson') String? configJson,
    @JS('onProgress') JSFunction? onProgress,
  });
}

/// A decision head loaded by `loadDecisionHead`.
@JS()
@anonymous
extension type WebGpuDecisionHeadInfo._(JSObject _) implements JSObject {
  /// Decision API version of the bridge.
  external JSAny? get apiVersion;

  /// Bridge handle of the head.
  external JSAny? get handle;

  /// Hidden size shared by the encoder and the head.
  external JSAny? get hiddenSize;

  /// Token that starts every sequence.
  external JSAny? get clsToken;

  /// Token that separates sequence parts.
  external JSAny? get sepToken;

  /// Token placed before each option.
  external JSAny? get maskToken;

  /// Text of the mask token.
  external JSAny? get maskText;

  /// The head's Laya config as JSON text.
  external JSAny? get configJson;

  /// Name of the device the head runs on.
  external JSAny? get deviceName;
}

/// Encoder input for one question, as `runDecision` takes it.
@JS()
@anonymous
extension type WebGpuDecisionSequence._(JSObject _) implements JSObject {
  /// Creates an encoder input.
  external factory WebGpuDecisionSequence({
    required JSInt32Array tokens,
    required JSInt32Array markers,
    @JS('questionType') required int questionType,
  });
}

/// Raw head outputs for one sequence, as `runDecision` returns them.
@JS()
@anonymous
extension type WebGpuDecisionOutput._(JSObject _) implements JSObject {
  /// One raw logit per marker.
  external JSAny? get logits;

  /// Action-head logits.
  external JSAny? get actLogits;
}

/// LoRA support reported by `getLoraAdapterCapabilities`.
@JS()
@anonymous
extension type WebGpuLoraAdapterCapabilities._(JSObject _) implements JSObject {
  /// LoRA API version of the bridge.
  external JSAny? get apiVersion;

  /// Whether the loaded core can load LoRA adapters.
  external JSAny? get supported;

  /// Why the loaded core cannot load LoRA adapters.
  external JSAny? get reason;
}

/// LoRA adapter load options.
@JS()
@anonymous
extension type WebGpuLoraAdapterLoadOptions._(JSObject _) implements JSObject {
  /// Creates adapter load options.
  external factory WebGpuLoraAdapterLoadOptions({
    @JS('useCache') bool? useCache,
  });
}

/// A LoRA adapter loaded by `loadLoraAdapter`.
@JS()
@anonymous
extension type WebGpuLoraAdapterInfo._(JSObject _) implements JSObject {
  /// Bridge handle of the adapter.
  external JSAny? get handle;
}
