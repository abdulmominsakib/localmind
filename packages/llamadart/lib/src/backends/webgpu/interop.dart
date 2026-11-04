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

  /// Loads multimodal projector from URL/path.
  external JSPromise<JSAny?>? loadMultimodalProjector(String url);

  /// Unloads multimodal projector if loaded.
  external JSPromise<JSAny?>? unloadMultimodalProjector();

  /// Returns whether loaded projector supports vision.
  external bool? supportsVision();

  /// Returns whether loaded projector supports audio.
  external bool? supportsAudio();

  /// Tokenizes text.
  external JSPromise<JSAny>? tokenize(String text, [bool? addSpecial]);

  /// Detokenizes token ids.
  external JSPromise<JSString>? detokenize(JSArray tokens, [bool? special]);

  /// Saves the active KV-cache/session state to a bridge WASMFS path.
  external JSPromise<JSAny?>? stateSaveFile(String path, JSArray tokens);

  /// Loads KV-cache/session state from a bridge WASMFS path.
  external JSPromise<JSAny?>? stateLoadFile(String path, int tokenCapacity);

  /// Generates a single embedding vector for [text].
  external JSPromise<JSAny?>? embed(
    String text, [
    WebGpuEmbeddingOptions? options,
  ]);

  /// Generates embedding vectors for all input texts.
  external JSPromise<JSAny?>? embedBatch(
    JSArray texts, [
    WebGpuEmbeddingOptions? options,
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
    double? penalty,
    int? seed,
    String? grammar,
    @JS('mediaMaxImagePixels') int? mediaMaxImagePixels,
    @JS('mediaMaxImageEdge') int? mediaMaxImageEdge,
    @JS('onToken') JSFunction? onToken,
    @JS('emitCurrentTextOnToken') bool? emitCurrentTextOnToken,
    @JS('tokenEventEncoding') String? tokenEventEncoding,
    @JS('tokenEventFlushMs') int? tokenEventFlushMs,
    @JS('tokenEventFlushChars') int? tokenEventFlushChars,
    bool? warmup,
    JSArray? parts,
    JSAny? signal,
  });
}

/// Embedding options.
@JS()
@anonymous
extension type WebGpuEmbeddingOptions._(JSObject _) implements JSObject {
  /// Creates embedding options.
  external factory WebGpuEmbeddingOptions({bool? normalize});
}
