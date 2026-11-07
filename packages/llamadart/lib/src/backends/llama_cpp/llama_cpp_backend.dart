import 'dart:async';
import 'dart:isolate';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import '../backend.dart';
import '../../core/models/chat/content_part.dart';
import '../../core/models/config/gpu_backend.dart';
import '../../core/models/config/gpu_device_info.dart';
import '../../core/models/config/log_level.dart';
import '../../core/models/diagnostics/model_file_type.dart';
import '../../core/exceptions.dart';
import '../../core/models/inference/model_params.dart';
import '../../core/models/inference/generation_params.dart';
import 'worker.dart';

/// Creates a [NativeLlamaBackend].
LlamaBackend createBackend() => NativeLlamaBackend();

/// Native implementation of [LlamaBackend] using isolates and FFI.
class NativeLlamaBackend
    implements
        LlamaBackend,
        BackendAvailability,
        BackendRuntimeDiagnostics,
        BackendModelFileTypeDiagnostics,
        BackendGpuEnumeration,
        BackendPerformanceDiagnostics,
        BackendEmbeddings,
        BackendBatchEmbeddings,
        BackendStatePersistence {
  Isolate? _isolate;
  SendPort? _sendPort;
  Future<void>? _isolateStart;
  final ReceivePort _responsesPort = ReceivePort();
  Pointer<Int8>? _activeCancelToken;
  void Function()? _activeGenerationCleanup;
  void Function()? _activeFreeToken;

  bool _isReady = false;
  LlamaLogLevel _currentLogLevel = LlamaLogLevel.warn;

  /// Creates a new [NativeLlamaBackend] and initializes its ports.
  NativeLlamaBackend({SendPort? initialSendPort}) {
    _responsesPort.listen(_handleResponse);
    if (initialSendPort != null) {
      _sendPort = initialSendPort;
      _isReady = true;
    }
  }

  @override
  bool get isReady => _isReady;

  void _handleResponse(dynamic message) {
    if (message is SendPort) {
      _sendPort = message;
      // Complete handshake
      _sendPort!.send(WorkerHandshake(_currentLogLevel));
      // Sync log level, closing the reply port once acked so it does not leak
      // (mirrors _ensureIsolate).
      final logRp = ReceivePort();
      _sendPort!.send(LogLevelRequest(_currentLogLevel, logRp.sendPort));
      logRp.first.then((_) => logRp.close());
    }
  }

  void _expectDoneResponse(Object? response, String operation) {
    if (response is DoneResponse) {
      return;
    }
    if (response is ErrorResponse) {
      throw _workerError(response);
    }
    throw Exception('Unknown response during $operation');
  }

  Object _workerError(ErrorResponse response) {
    switch (response.kind) {
      case WorkerErrorKind.model:
        return LlamaModelException(response.message);
      case WorkerErrorKind.context:
        return LlamaContextException(response.message);
      case WorkerErrorKind.inference:
        return LlamaInferenceException(response.message);
      case WorkerErrorKind.unsupported:
        return LlamaUnsupportedException(response.message);
      case WorkerErrorKind.state:
        return LlamaStateException(response.message);
      case WorkerErrorKind.generic:
        const exceptionPrefix = 'Exception: ';
        final message = response.message.startsWith(exceptionPrefix)
            ? response.message.substring(exceptionPrefix.length)
            : response.message;
        return Exception(message);
    }
  }

  Future<void> _ensureIsolate() async {
    if (_sendPort != null) {
      _isReady = true;
      return;
    }
    final existingStart = _isolateStart;
    if (existingStart != null) {
      await existingStart;
      _isReady = _sendPort != null;
      return;
    }

    final start = _startIsolate();
    _isolateStart = start;
    try {
      await start;
    } finally {
      if (_isolateStart == start) {
        _isolateStart = null;
      }
    }
  }

  Future<void> _startIsolate() async {
    final completer = Completer<void>();
    final tempPort = ReceivePort();
    tempPort.listen((msg) {
      if (msg is SendPort) {
        _sendPort = msg;
        _sendPort!.send(WorkerHandshake(_currentLogLevel));
        final logRp = ReceivePort();
        _sendPort!.send(LogLevelRequest(_currentLogLevel, logRp.sendPort));
        logRp.first.then((_) {
          logRp.close();
        });
        tempPort.close();
        completer.complete();
      }
    });
    try {
      _isolate = await Isolate.spawn(llamaWorkerEntry, tempPort.sendPort);
      await completer.future;
      _isReady = true;
    } catch (_) {
      tempPort.close();
      rethrow;
    }
  }

  @override
  void cancelGeneration() {
    _activeCancelToken?.value = 1;
  }

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {
    _currentLogLevel = level;
    if (_sendPort != null) {
      final rp = ReceivePort();
      _sendPort!.send(LogLevelRequest(level, rp.sendPort));
      await rp.first;
      rp.close();
    }
  }

  @override
  Future<int> modelLoad(String path, ModelParams params) async {
    await _ensureIsolate();
    final rp = ReceivePort();
    _sendPort!.send(ModelLoadRequest(path, params, rp.sendPort));
    final res = await rp.first;
    rp.close();
    if (res is HandleResponse) return res.handle;
    if (res is ErrorResponse) throw _workerError(res);
    throw Exception("Unknown response during model load");
  }

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    Function(double progress)? onProgress,
  }) async {
    throw UnimplementedError("Use modelLoad with a local path for now");
  }

  @override
  Future<void> modelFree(int modelHandle) async {
    if (_sendPort == null) return;
    final rp = ReceivePort();
    _sendPort!.send(ModelFreeRequest(modelHandle, rp.sendPort));
    final res = await rp.first;
    rp.close();
    _expectDoneResponse(res, 'model free');
  }

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async {
    await _ensureIsolate();
    final rp = ReceivePort();
    _sendPort!.send(ContextCreateRequest(modelHandle, params, rp.sendPort));
    final res = await rp.first;
    rp.close();
    if (res is HandleResponse) return res.handle;
    if (res is ErrorResponse) throw _workerError(res);
    throw Exception("Unknown response during context creation");
  }

  @override
  Future<void> contextFree(int contextHandle) async {
    if (_sendPort == null) return;
    final rp = ReceivePort();
    _sendPort!.send(ContextFreeRequest(contextHandle, rp.sendPort));
    final res = await rp.first;
    rp.close();
    _expectDoneResponse(res, 'context free');
  }

  @override
  Future<int> getContextSize(int contextHandle) async {
    if (_sendPort == null) return 0;
    final rp = ReceivePort();
    _sendPort!.send(GetContextSizeRequest(contextHandle, rp.sendPort));
    final res = await rp.first;
    rp.close();
    if (res is GetContextSizeResponse) return res.size;
    return 0;
  }

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) {
    if (_activeCancelToken != null || _activeGenerationCleanup != null) {
      return Stream<List<int>>.error(
        StateError('llama.cpp generation is already in progress.'),
      );
    }

    late final StreamController<List<int>> controller;
    final rp = ReceivePort();

    final cancelToken = malloc<Int8>(1);
    cancelToken.value = 0;
    _activeCancelToken = cancelToken;

    // The cancel token is shared with the worker isolate, which polls it every
    // decode iteration. It must only be freed once the worker has stopped
    // reading it. Cleanup is split in two: detachAndClose() runs eagerly on
    // cancel and only tears down the Dart-side controller, while freeToken()
    // frees the native token and closes the response port. The only safe times
    // to free are when the worker proves it has stopped: a terminal
    // DoneResponse/ErrorResponse (the worker breaks its decode loop on seeing
    // the cancel flag and then emits one), or dispose() freeing it after
    // killing the worker isolate. A timer-based backstop is deliberately
    // avoided: it could fire mid-decode (e.g. during a slow prompt eval) and
    // reintroduce the use-after-free. Worst case (a wedged worker that never
    // responds and is never disposed) leaks a single byte, which is acceptable.
    var tokenFreed = false;
    late final void Function() freeToken;
    freeToken = () {
      if (tokenFreed) {
        return;
      }
      tokenFreed = true;
      rp.close();
      malloc.free(cancelToken);
      if (_activeCancelToken == cancelToken) {
        _activeCancelToken = null;
      }
      if (_activeFreeToken == freeToken) {
        _activeFreeToken = null;
      }
    };
    _activeFreeToken = freeToken;

    var detached = false;
    void detachAndClose() {
      if (detached) {
        return;
      }
      detached = true;
      if (!controller.isClosed) {
        unawaited(controller.close());
      }
      if (_activeGenerationCleanup == detachAndClose) {
        _activeGenerationCleanup = null;
      }
    }

    controller = StreamController<List<int>>(
      onCancel: () {
        cancelGeneration();
        // Close the Dart side immediately, but keep the response port open and
        // the native token alive so the worker can observe the cancel flag and
        // emit its terminal response, at which point freeToken() runs.
        detachAndClose();
      },
    );
    _activeGenerationCleanup = detachAndClose;

    _sendPort!.send(
      GenerateRequest(
        contextHandle,
        prompt,
        params,
        cancelToken.address,
        rp.sendPort,
        parts: parts,
      ),
    );

    rp.listen((msg) {
      if (msg is TokenResponse) {
        if (!controller.isClosed) {
          controller.add(msg.bytes);
        }
      } else if (msg is DoneResponse) {
        detachAndClose();
        freeToken();
      } else if (msg is ErrorResponse) {
        if (!controller.isClosed) {
          controller.addError(_workerError(msg));
        }
        detachAndClose();
        freeToken();
      }
    });

    return controller.stream;
  }

  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async {
    final rp = ReceivePort();
    _sendPort!.send(
      TokenizeRequest(modelHandle, text, addSpecial, rp.sendPort),
    );
    final res = await rp.first;
    rp.close();
    if (res is TokenizeResponse) return res.tokens;
    throw Exception("Tokenization failed");
  }

  @override
  Future<List<double>> embed(
    int contextHandle,
    String text, {
    bool normalize = true,
  }) async {
    await _ensureIsolate();
    final rp = ReceivePort();
    _sendPort!.send(EmbedRequest(contextHandle, text, normalize, rp.sendPort));
    final res = await rp.first;
    rp.close();
    if (res is EmbedResponse) return res.embedding;
    if (res is ErrorResponse) throw Exception(res.message);
    throw Exception('Embedding failed');
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

    await _ensureIsolate();
    final rp = ReceivePort();
    _sendPort!.send(
      EmbedBatchRequest(
        contextHandle,
        List<String>.from(texts),
        normalize,
        rp.sendPort,
      ),
    );
    final res = await rp.first;
    rp.close();
    if (res is EmbedBatchResponse) return res.embeddings;
    if (res is ErrorResponse) throw Exception(res.message);
    throw Exception('Batch embedding failed');
  }

  @override
  Future<String> detokenize(
    int modelHandle,
    List<int> tokens, {
    bool special = false,
  }) async {
    final rp = ReceivePort();
    _sendPort!.send(
      DetokenizeRequest(modelHandle, tokens, special, rp.sendPort),
    );
    final res = await rp.first;
    rp.close();
    if (res is DetokenizeResponse) return res.text;
    throw Exception("Detokenization failed");
  }

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async {
    final rp = ReceivePort();
    _sendPort!.send(MetadataRequest(modelHandle, rp.sendPort));
    final res = await rp.first;
    rp.close();
    if (res is MetadataResponse) return res.metadata;
    return {};
  }

  @override
  Future<ModelFileType?> getModelFileType(int modelHandle) async {
    final rp = ReceivePort();
    _sendPort!.send(ModelFileTypeRequest(modelHandle, rp.sendPort));
    final res = await rp.first;
    rp.close();
    if (res is ModelFileTypeResponse) return res.modelFileType;
    if (res is ErrorResponse) throw Exception(res.message);
    return null;
  }

  @override
  Future<bool> stateSaveFile(
    int contextHandle,
    String path,
    List<int> tokens,
  ) async {
    await _ensureIsolate();
    final rp = ReceivePort();
    _sendPort!.send(
      StateSaveFileRequest(
        contextHandle,
        path,
        List<int>.from(tokens),
        rp.sendPort,
      ),
    );
    final res = await rp.first;
    rp.close();
    if (res is StateSaveFileResponse) return res.success;
    if (res is ErrorResponse) throw Exception(res.message);
    throw Exception('State save failed');
  }

  @override
  Future<StateLoadResult> stateLoadFile(
    int contextHandle,
    String path,
    int tokenCapacity,
  ) async {
    await _ensureIsolate();
    final rp = ReceivePort();
    _sendPort!.send(
      StateLoadFileRequest(contextHandle, path, tokenCapacity, rp.sendPort),
    );
    final res = await rp.first;
    rp.close();
    if (res is StateLoadFileResponse) {
      return StateLoadResult(tokens: res.tokens);
    }
    if (res is ErrorResponse) throw Exception(res.message);
    throw Exception('State load failed');
  }

  @override
  Future<void> setLoraAdapter(
    int contextHandle,
    String path,
    double scale,
  ) async {
    final rp = ReceivePort();
    _sendPort!.send(
      LoraRequest(
        contextHandle,
        'set',
        path: path,
        scale: scale,
        sendPort: rp.sendPort,
      ),
    );
    final res = await rp.first;
    rp.close();
    if (res is ErrorResponse) throw Exception(res.message);
  }

  @override
  Future<void> removeLoraAdapter(int contextHandle, String path) async {
    final rp = ReceivePort();
    _sendPort!.send(
      LoraRequest(contextHandle, 'remove', path: path, sendPort: rp.sendPort),
    );
    final res = await rp.first;
    rp.close();
    if (res is ErrorResponse) throw Exception(res.message);
  }

  @override
  Future<void> clearLoraAdapters(int contextHandle) async {
    final rp = ReceivePort();
    _sendPort!.send(LoraRequest(contextHandle, 'clear', sendPort: rp.sendPort));
    final res = await rp.first;
    rp.close();
    if (res is ErrorResponse) throw Exception(res.message);
  }

  @override
  Future<String> getBackendName() async {
    await _ensureIsolate();
    final rp = ReceivePort();
    _sendPort!.send(BackendInfoRequest(rp.sendPort));
    final res = await rp.first;
    rp.close();
    return (res as BackendInfoResponse).name;
  }

  @override
  Future<String> getAvailableBackends() async {
    await _ensureIsolate();
    final rp = ReceivePort();
    _sendPort!.send(AvailableBackendsRequest(rp.sendPort));
    final res = await rp.first;
    rp.close();
    return (res as BackendInfoResponse).name;
  }

  @override
  Future<int?> getResolvedGpuLayers() async {
    await _ensureIsolate();
    final rp = ReceivePort();
    _sendPort!.send(ResolvedGpuLayersRequest(rp.sendPort));
    final res = await rp.first;
    rp.close();
    return (res as ResolvedGpuLayersResponse).layers;
  }

  @override
  Future<BackendPerfContextData?> getPerformanceContext(
    int contextHandle,
  ) async {
    await _ensureIsolate();
    final rp = ReceivePort();
    _sendPort!.send(PerformanceContextRequest(contextHandle, rp.sendPort));
    final res = await rp.first;
    rp.close();
    if (res is PerformanceContextResponse) {
      return BackendPerfContextData(
        loadMs: res.loadMs,
        promptEvalMs: res.promptEvalMs,
        evalMs: res.evalMs,
        sampleMs: res.sampleMs,
        decodeMs: res.decodeMs,
        promptEvalTokens: res.promptEvalTokens,
        evalTokens: res.evalTokens,
        sampleCount: res.sampleCount,
        reusedGraphs: res.reusedGraphs,
        speculativeDraftTokens: res.speculativeDraftTokens,
        speculativeAcceptedDraftTokens: res.speculativeAcceptedDraftTokens,
        speculativeDraftAttempts: res.speculativeDraftAttempts,
        speculativeVerifyTokens: res.speculativeVerifyTokens,
        speculativeReplayTokens: res.speculativeReplayTokens,
        speculativeDraftMs: res.speculativeDraftMs,
        speculativeVerifyMs: res.speculativeVerifyMs,
      );
    }
    if (res is ErrorResponse) {
      throw Exception(res.message);
    }
    return null;
  }

  @override
  bool get supportsUrlLoading => false;

  @override
  Future<bool> isGpuSupported() async {
    await _ensureIsolate();
    final rp = ReceivePort();
    _sendPort!.send(GpuSupportRequest(rp.sendPort));
    final res = await rp.first;
    rp.close();
    return (res as GpuSupportResponse).support;
  }

  @override
  Future<void> dispose() async {
    // Signal any in-flight generation to stop and close the Dart side, but do
    // not free the shared cancel token yet: the worker may still poll it. The
    // worker awaits the in-flight generation before acking the dispose, so its
    // terminal response normally frees the token first. After killing the
    // worker (below) the token is provably unread, so freeing it there is safe
    // and idempotent (guarded by the freeToken tokenFreed flag).
    _activeCancelToken?.value = 1;
    _activeGenerationCleanup?.call();

    if (_sendPort != null) {
      final rp = ReceivePort();
      _sendPort!.send(DisposeRequest(rp.sendPort));
      await rp.first;
      rp.close();
    }
    _isolate?.kill();
    _responsesPort.close();
    // Worker is gone; free the token if a terminal response did not already.
    _activeFreeToken?.call();
    _activeCancelToken = null;
    _activeGenerationCleanup = null;
    _activeFreeToken = null;
    _isReady = false;
  }

  @override
  Future<int?> multimodalContextCreate(
    int modelHandle,
    String mmProjPath,
  ) async {
    final rp = ReceivePort();
    _sendPort!.send(
      MultimodalContextCreateRequest(modelHandle, mmProjPath, rp.sendPort),
    );
    final res = await rp.first;
    rp.close();
    if (res is HandleResponse) return res.handle;
    if (res is ErrorResponse) throw Exception(res.message);
    return null;
  }

  @override
  Future<void> multimodalContextFree(int mmContextHandle) async {
    final rp = ReceivePort();
    _sendPort!.send(MultimodalContextFreeRequest(mmContextHandle, rp.sendPort));
    final res = await rp.first;
    rp.close();
    _expectDoneResponse(res, 'multimodal context free');
  }

  @override
  Future<bool> supportsAudio(int mmContextHandle) async {
    final rp = ReceivePort();
    _sendPort!.send(SupportsAudioRequest(mmContextHandle, rp.sendPort));
    final res = await rp.first;
    rp.close();
    return res as bool;
  }

  @override
  Future<bool> supportsVision(int mmContextHandle) async {
    final rp = ReceivePort();
    _sendPort!.send(SupportsVisionRequest(mmContextHandle, rp.sendPort));
    final res = await rp.first;
    rp.close();
    return res as bool;
  }

  @override
  Future<({int total, int free})> getVramInfo() async {
    await _ensureIsolate();
    final rp = ReceivePort();
    _sendPort!.send(SystemInfoRequest(rp.sendPort));
    final res = await rp.first;
    rp.close();
    if (res is SystemInfoResponse) {
      return (total: res.totalVram, free: res.freeVram);
    }
    return (total: 0, free: 0);
  }

  @override
  Future<List<GpuDeviceInfo>> listGpuDevices({
    List<GpuBackend> probeBackends = const [],
  }) async {
    await _ensureIsolate();
    final rp = ReceivePort();
    _sendPort!.send(ListGpuDevicesRequest(probeBackends, rp.sendPort));
    final res = await rp.first;
    rp.close();
    if (res is ListGpuDevicesResponse) {
      return res.devices;
    }
    return const [];
  }

  @override
  Future<String> applyChatTemplate(
    int modelHandle,
    List<Map<String, dynamic>> messages, {
    String? customTemplate,
    bool addAssistant = true,
  }) async {
    await _ensureIsolate();
    final rp = ReceivePort();
    _sendPort!.send(
      ChatTemplateRequest(
        modelHandle,
        messages,
        customTemplate,
        addAssistant,
        rp.sendPort,
      ),
    );
    final res = await rp.first;
    rp.close();
    if (res is ChatTemplateResponse) return res.result;
    if (res is ErrorResponse) throw Exception(res.message);
    throw Exception("Unknown response during chat template application");
  }
}
