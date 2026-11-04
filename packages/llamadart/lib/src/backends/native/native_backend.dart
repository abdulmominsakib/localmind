import '../../core/models/chat/chat_message.dart';
import '../../core/models/chat/content_part.dart';
import '../../core/models/config/gpu_backend.dart';
import '../../core/models/config/gpu_device_info.dart';
import '../../core/models/config/log_level.dart';
import '../../core/models/diagnostics/model_file_type.dart';
import '../../core/models/inference/generation_params.dart';
import '../../core/models/inference/model_params.dart';
import '../../core/models/inference/tool_choice.dart';
import '../../core/models/tools/tool_definition.dart';
import '../backend.dart';
import '../litert_lm/litert_lm_backend.dart';
import '../llama_cpp/llama_cpp_backend.dart';

/// Creates the native backend for the current platform.
LlamaBackend createBackend() => NativeAutoBackend();

/// Native backend router that chooses an engine from the model format.
///
/// GGUF and all unknown file extensions stay on the existing llama.cpp backend.
/// `.litertlm` model bundles use the LiteRT-LM backend.
class NativeAutoBackend
    implements
        LlamaBackend,
        BackendAvailability,
        BackendRuntimeDiagnostics,
        BackendModelFileTypeDiagnostics,
        BackendGpuEnumeration,
        BackendPerformanceDiagnostics,
        BackendEmbeddings,
        BackendEmbeddingsSupport,
        BackendBatchEmbeddings,
        BackendStatePersistence,
        BackendStatePersistenceSupport,
        BackendGrammarConstraintsSupport,
        BackendNativeChatGeneration {
  final LlamaBackend Function() _llamaCppFactory;
  final LlamaBackend Function() _liteRtLmFactory;

  LlamaBackend? _delegate;
  _NativeBackendKind? _delegateKind;
  LlamaBackend? _diagnosticDelegate;
  Future<LlamaBackend>? _diagnosticDelegateStart;
  LlamaLogLevel _currentLogLevel = LlamaLogLevel.warn;

  /// Creates a backend router.
  NativeAutoBackend({
    LlamaBackend Function()? llamaCppFactory,
    LlamaBackend Function()? liteRtLmFactory,
  }) : _llamaCppFactory = llamaCppFactory ?? (() => NativeLlamaBackend()),
       _liteRtLmFactory = liteRtLmFactory ?? (() => LiteRtLmBackend());

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
  bool get supportsNativeChatGeneration {
    final delegate = _delegate;
    if (delegate is BackendNativeChatGeneration) {
      return (delegate as BackendNativeChatGeneration)
          .supportsNativeChatGeneration;
    }
    return false;
  }

  @override
  Future<int> modelLoad(String path, ModelParams params) async {
    final delegate = await _delegateForPath(path);
    return delegate.modelLoad(path, params);
  }

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    Function(double progress)? onProgress,
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
    if (delegate is BackendNativeChatGeneration) {
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
    throw UnsupportedError(
      'The selected native backend does not support native chat generation.',
    );
  }

  @override
  void cancelGeneration() {
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
    _delegate = null;
    _delegateKind = null;
    final diagnosticDelegate = await _takeDiagnosticDelegate();
    await delegate?.dispose();
    if (!identical(delegate, diagnosticDelegate)) {
      await diagnosticDelegate?.dispose();
    }
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

  Future<LlamaBackend> _delegateForPath(String path) async {
    final kind = _kindForPath(path);
    if (_delegate != null && _delegateKind == kind) {
      return _delegate!;
    }

    final diagnosticDelegate = await _takeDiagnosticDelegate();
    if (_delegate == null &&
        diagnosticDelegate != null &&
        kind == _NativeBackendKind.llamaCpp) {
      await diagnosticDelegate.setLogLevel(_currentLogLevel);
      _delegate = diagnosticDelegate;
      _delegateKind = kind;
      return diagnosticDelegate;
    }

    final oldDelegate = _delegate;
    _delegate = null;
    _delegateKind = null;
    await oldDelegate?.dispose();
    await diagnosticDelegate?.dispose();

    final delegate = switch (kind) {
      _NativeBackendKind.liteRtLm => _liteRtLmFactory(),
      _NativeBackendKind.llamaCpp => _llamaCppFactory(),
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

  _NativeBackendKind _kindForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.litertlm')) {
      return _NativeBackendKind.liteRtLm;
    }
    return _NativeBackendKind.llamaCpp;
  }

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

enum _NativeBackendKind { llamaCpp, liteRtLm }
