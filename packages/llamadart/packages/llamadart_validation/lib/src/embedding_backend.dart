import 'dart:async';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';

/// Forwards the embedding pack's backend and observes the public SPI compute
/// boundary. Dispatch does not prove that a worker has begun native encoding.
class EmbeddingDispatchBackend
    implements
        LlamaBackend,
        BackendMultimodalEmbeddings,
        BackendMultimodalSupport,
        BackendRuntimeDiagnostics {
  EmbeddingDispatchBackend(this.delegate);
  final LlamaBackend delegate;
  int dispatches = 0;
  Completer<void>? dispatched;

  @override
  Future<LlamaEmbeddingCapabilities> getEmbeddingCapabilities(
    int contextHandle,
  ) => (delegate as BackendMultimodalEmbeddings).getEmbeddingCapabilities(
    contextHandle,
  );

  @override
  Future<List<List<double>>> embedContentBatch(
    int contextHandle,
    List<LlamaEmbeddingInput> inputs, {
    bool normalize = true,
  }) {
    final pending = (delegate as BackendMultimodalEmbeddings).embedContentBatch(
      contextHandle,
      inputs,
      normalize: normalize,
    );
    dispatches++;
    dispatched?.complete();
    dispatched = null;
    return pending;
  }

  @override
  Future<int?> getResolvedGpuLayers() =>
      (delegate as BackendRuntimeDiagnostics).getResolvedGpuLayers();
  @override
  bool get isReady => delegate.isReady;
  @override
  bool get supportsUrlLoading => delegate.supportsUrlLoading;
  @override
  Future<int> modelLoad(String path, ModelParams params) =>
      delegate.modelLoad(path, params);
  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    void Function(double)? onProgress,
  }) => delegate.modelLoadFromUrl(url, params, onProgress: onProgress);
  @override
  Future<void> modelFree(int modelHandle) => delegate.modelFree(modelHandle);
  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) =>
      delegate.contextCreate(modelHandle, params);
  @override
  Future<void> contextFree(int contextHandle) =>
      delegate.contextFree(contextHandle);
  @override
  Future<int> getContextSize(int contextHandle) =>
      delegate.getContextSize(contextHandle);
  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) => delegate.generate(contextHandle, prompt, params, parts: parts);
  @override
  void cancelGeneration() => delegate.cancelGeneration();
  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) => delegate.tokenize(modelHandle, text, addSpecial: addSpecial);
  @override
  Future<String> detokenize(
    int modelHandle,
    List<int> tokens, {
    bool special = false,
  }) => delegate.detokenize(modelHandle, tokens, special: special);
  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) =>
      delegate.modelMetadata(modelHandle);
  @override
  Future<String> getBackendName() => delegate.getBackendName();
  @override
  Future<bool> isGpuSupported() => delegate.isGpuSupported();
  @override
  Future<void> setLogLevel(LlamaLogLevel level) => delegate.setLogLevel(level);
  @override
  Future<void> dispose() => delegate.dispose();
  @override
  Future<int?> multimodalContextCreate(int modelHandle, String mmProjPath) =>
      _multimodal.multimodalContextCreate(modelHandle, mmProjPath);
  @override
  Future<void> multimodalContextFree(int mmContextHandle) =>
      _multimodal.multimodalContextFree(mmContextHandle);
  @override
  Future<bool> supportsVision(int mmContextHandle) =>
      _multimodal.supportsVision(mmContextHandle);
  @override
  Future<bool> supportsAudio(int mmContextHandle) =>
      _multimodal.supportsAudio(mmContextHandle);
  BackendMultimodalSupport get _multimodal {
    final delegate = this.delegate;
    if (delegate is BackendMultimodalSupport) {
      return delegate as BackendMultimodalSupport;
    }
    throw LlamaUnsupportedException(
      'Multimodal projectors are not supported by the wrapped backend: it '
      'does not implement BackendMultimodalSupport.',
    );
  }

  @override
  Future<({int total, int free})> getVramInfo() => delegate.getVramInfo();
  @override
  Future<String> applyChatTemplate(
    int modelHandle,
    List<Map<String, dynamic>> messages, {
    String? customTemplate,
    bool addAssistant = true,
  }) => delegate.applyChatTemplate(
    modelHandle,
    messages,
    customTemplate: customTemplate,
    addAssistant: addAssistant,
  );
}
