import '../backend.dart';
import '../../core/models/chat/content_part.dart';
import '../../core/models/config/log_level.dart';
import '../../core/models/inference/generation_params.dart';
import '../../core/models/inference/model_params.dart';
import '../litert_lm/litert_lm_backend_web.dart';
import '../webgpu/webgpu_backend.dart';

/// Creates a web backend that can route between multiple web runtimes.
LlamaBackend createBackend() => WebAutoBackend();

/// Uses the unified web backend implementation.
class WebAutoBackend
    implements
        LlamaBackend,
        BackendAvailability,
        BackendEmbeddingsSupport,
        BackendBatchEmbeddings,
        BackendStatePersistence,
        BackendStatePersistenceSupport {
  final LlamaBackend Function() _webGpuFactory;
  final LlamaBackend Function() _liteRtLmFactory;

  LlamaBackend? _delegate;
  _WebBackendKind? _delegateKind;
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
      _delegateKind = _WebBackendKind.llamaCpp;
    }
  }

  @override
  bool get isReady => _delegate?.isReady ?? false;

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
  bool get supportsEmbeddings {
    final delegate = _delegate;
    if (delegate is BackendEmbeddingsSupport) {
      return (delegate as BackendEmbeddingsSupport).supportsEmbeddings;
    }
    return delegate is BackendEmbeddings;
  }

  @override
  Future<int> modelLoad(String path, ModelParams params) async {
    final delegate = await _delegateForSource(path);
    return delegate.modelLoad(path, params);
  }

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    Function(double p1)? onProgress,
  }) async {
    final delegate = await _delegateForSource(url);
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
  void cancelGeneration() {
    _delegate?.cancelGeneration();
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
    return _requireDelegate().setLoraAdapter(contextHandle, path, scale);
  }

  @override
  Future<void> removeLoraAdapter(int contextHandle, String path) {
    return _requireDelegate().removeLoraAdapter(contextHandle, path);
  }

  @override
  Future<void> clearLoraAdapters(int contextHandle) {
    return _requireDelegate().clearLoraAdapters(contextHandle);
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
    return _requireDelegate().multimodalContextCreate(modelHandle, mmProjPath);
  }

  @override
  Future<void> multimodalContextFree(int mmContextHandle) {
    return _requireDelegate().multimodalContextFree(mmContextHandle);
  }

  @override
  Future<bool> supportsVision(int mmContextHandle) {
    return _requireDelegate().supportsVision(mmContextHandle);
  }

  @override
  Future<bool> supportsAudio(int mmContextHandle) {
    return _requireDelegate().supportsAudio(mmContextHandle);
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

  Future<LlamaBackend> _delegateForSource(String source) async {
    final kind = _kindForSource(source);
    if (_delegate != null && _delegateKind == kind) {
      return _delegate!;
    }

    final oldDelegate = _delegate;
    _delegate = null;
    _delegateKind = null;
    await oldDelegate?.dispose();

    final delegate = switch (kind) {
      _WebBackendKind.liteRtLm => _liteRtLmFactory(),
      _WebBackendKind.llamaCpp => _webGpuFactory(),
    };
    await delegate.setLogLevel(_currentLogLevel);
    _delegate = delegate;
    _delegateKind = kind;
    return delegate;
  }

  _WebBackendKind _kindForSource(String source) {
    final path = _sourcePath(source).toLowerCase();
    if (path.endsWith('.litertlm')) {
      return _WebBackendKind.liteRtLm;
    }
    return _WebBackendKind.llamaCpp;
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
      throw StateError('No web backend has been selected. Load a model first.');
    }
    return delegate;
  }
}

enum _WebBackendKind { llamaCpp, liteRtLm }
