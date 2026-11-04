import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../../core/models/chat/chat_message.dart';
import '../../core/models/chat/content_part.dart';
import '../../core/models/config/log_level.dart';
import '../../core/models/inference/generation_params.dart';
import '../../core/models/inference/model_params.dart';
import '../../core/models/inference/tool_choice.dart';
import '../../core/models/tools/tool_definition.dart';
import '../backend.dart';
import 'litert_lm_platform.dart';
import 'worker.dart';

/// Native LiteRT-LM backend for `.litertlm` models.
///
/// LiteRT-LM native state is owned by a worker isolate so callbacks, native
/// handles, and generation work do not live on the caller isolate.
class LiteRtLmBackend
    implements
        LlamaBackend,
        BackendAvailability,
        BackendGrammarConstraintsSupport,
        BackendRuntimeDiagnostics,
        BackendPerformanceDiagnostics,
        BackendEmbeddingsSupport,
        BackendStatePersistenceSupport,
        BackendNativeChatGeneration {
  Isolate? _isolate;
  SendPort? _sendPort;
  Future<void>? _isolateStart;
  int _workerGeneration = 0;
  void Function()? _activeGenerationCleanup;
  final String? _preferredBackend;

  bool _isReady = false;
  bool _disposed = false;
  LlamaLogLevel _currentLogLevel = LlamaLogLevel.warn;

  /// Creates a LiteRT-LM backend.
  ///
  /// Prefer [ModelParams.liteRtLmBackend] when using the default
  /// `LlamaBackend()` router. [preferredBackend] remains available for callers
  /// that instantiate [LiteRtLmBackend] directly.
  LiteRtLmBackend({SendPort? initialSendPort, String? preferredBackend})
    : _preferredBackend = preferredBackend {
    if (initialSendPort != null) {
      _sendPort = initialSendPort;
      _isReady = true;
    }
  }

  @override
  bool get isReady => _isReady;

  @override
  bool get supportsUrlLoading => false;

  @override
  bool get supportsEmbeddings => false;

  @override
  bool get supportsStatePersistence => false;

  @override
  bool get supportsGrammarConstraints => false;

  @override
  bool get supportsNativeChatGeneration => true;

  @override
  Future<int> modelLoad(String path, ModelParams params) async {
    await _cancelActiveGeneration();
    final response = await _sendRequest(
      (sendPort) => LiteRtLmModelLoadRequest(
        path,
        params,
        sendPort,
        backendOverride: _preferredBackend,
      ),
    );
    final handle = _expect<LiteRtLmHandleResponse>(
      response,
      'model load',
    ).handle;
    _isReady = true;
    return handle;
  }

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    Function(double progress)? onProgress,
  }) {
    throw UnsupportedError('LiteRtLmBackend requires a local .litertlm path.');
  }

  @override
  Future<void> modelFree(int modelHandle) async {
    await _cancelActiveGeneration();
    if (_sendPort == null) {
      _isReady = false;
      return;
    }
    try {
      await _sendRequest(
        (sendPort) => LiteRtLmModelFreeRequest(modelHandle, sendPort),
        timeout: const Duration(seconds: 5),
      );
    } on TimeoutException {
      _killWorker();
    }
    _isReady = false;
  }

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async {
    final response = await _sendRequest(
      (sendPort) => LiteRtLmContextCreateRequest(modelHandle, params, sendPort),
    );
    return _expect<LiteRtLmHandleResponse>(response, 'context creation').handle;
  }

  @override
  Future<void> contextFree(int contextHandle) async {
    await _cancelActiveGeneration();
    if (_sendPort == null) {
      return;
    }
    try {
      await _sendRequest(
        (sendPort) => LiteRtLmContextFreeRequest(contextHandle, sendPort),
        timeout: const Duration(seconds: 5),
      );
    } on TimeoutException {
      _killWorker();
    }
  }

  @override
  Future<int> getContextSize(int contextHandle) async {
    final response = await _sendRequest(
      (sendPort) => LiteRtLmGetContextSizeRequest(contextHandle, sendPort),
    );
    return _expect<LiteRtLmGetContextSizeResponse>(
      response,
      'context size lookup',
    ).size;
  }

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) {
    late final StreamController<List<int>> controller;
    ReceivePort? responsePort;
    var cleanedUp = false;
    var activeGeneration = false;

    void cleanup() {
      if (cleanedUp) {
        return;
      }
      cleanedUp = true;
      responsePort?.close();
      if (!controller.isClosed) {
        unawaited(controller.close());
      }
      if (_activeGenerationCleanup == cleanup) {
        _activeGenerationCleanup = null;
      }
    }

    controller = StreamController<List<int>>(
      onListen: () {
        if (_activeGenerationCleanup != null) {
          controller.addError(
            StateError('LiteRT-LM generation is already in progress.'),
          );
          cleanup();
          return;
        }

        final port = ReceivePort();
        responsePort = port;
        port.listen((message) {
          if (cleanedUp) {
            return;
          }
          if (message is LiteRtLmTokenResponse) {
            controller.add(message.bytes);
          } else if (message is LiteRtLmDoneResponse) {
            cleanup();
          } else if (message is LiteRtLmErrorResponse) {
            controller.addError(_exceptionForErrorResponse(message));
            cleanup();
          }
        });

        activeGeneration = true;
        _activeGenerationCleanup = cleanup;
        unawaited(() async {
          try {
            await _ensureIsolate();
            // Re-check after the await: a cancel during _ensureIsolate() runs
            // cleanup(), which closes the response port and may clear
            // _sendPort. Capture the port and guard in one synchronous step so
            // we never send a generate request to a closed port (which would
            // orphan a generation on the worker) or dereference a null port.
            final sendPort = _sendPort;
            if (cleanedUp || sendPort == null) {
              cleanup();
              return;
            }
            sendPort.send(
              LiteRtLmGenerateRequest(
                contextHandle,
                prompt,
                params,
                port.sendPort,
                parts: parts,
              ),
            );
          } catch (error, stackTrace) {
            if (!controller.isClosed) {
              controller.addError(error, stackTrace);
            }
            cleanup();
          }
        }());
      },
      onCancel: () {
        if (activeGeneration) {
          cancelGeneration();
        }
        cleanup();
      },
    );

    return controller.stream;
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
    late final StreamController<List<int>> controller;
    ReceivePort? responsePort;
    var cleanedUp = false;
    var activeGeneration = false;
    final nativeTools = tools
        ?.map((tool) => tool.toJson())
        .toList(growable: false);

    void cleanup() {
      if (cleanedUp) {
        return;
      }
      cleanedUp = true;
      responsePort?.close();
      if (!controller.isClosed) {
        unawaited(controller.close());
      }
      if (_activeGenerationCleanup == cleanup) {
        _activeGenerationCleanup = null;
      }
    }

    controller = StreamController<List<int>>(
      onListen: () {
        if (_activeGenerationCleanup != null) {
          controller.addError(
            StateError('LiteRT-LM generation is already in progress.'),
          );
          cleanup();
          return;
        }

        final port = ReceivePort();
        responsePort = port;
        port.listen((message) {
          if (cleanedUp) {
            return;
          }
          if (message is LiteRtLmTokenResponse) {
            controller.add(message.bytes);
          } else if (message is LiteRtLmDoneResponse) {
            cleanup();
          } else if (message is LiteRtLmErrorResponse) {
            controller.addError(_exceptionForErrorResponse(message));
            cleanup();
          }
        });

        activeGeneration = true;
        _activeGenerationCleanup = cleanup;
        unawaited(() async {
          try {
            await _ensureIsolate();
            final sendPort = _sendPort;
            if (cleanedUp || sendPort == null) {
              cleanup();
              return;
            }
            sendPort.send(
              LiteRtLmGenerateChatRequest(
                contextHandle,
                messages,
                params,
                port.sendPort,
                tools: nativeTools,
                toolChoice: toolChoice,
                parallelToolCalls: parallelToolCalls,
                enableThinking: enableThinking,
                chatTemplateKwargs: chatTemplateKwargs,
                sourceLangCode: sourceLangCode,
                targetLangCode: targetLangCode,
                templateNow: templateNow,
              ),
            );
          } catch (error, stackTrace) {
            if (!controller.isClosed) {
              controller.addError(error, stackTrace);
            }
            cleanup();
          }
        }());
      },
      onCancel: () {
        if (activeGeneration) {
          cancelGeneration();
        }
        cleanup();
      },
    );

    return controller.stream;
  }

  @override
  void cancelGeneration() {
    unawaited(_cancelGeneration());
  }

  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async {
    final response = await _sendRequest(
      (sendPort) =>
          LiteRtLmTokenizeRequest(modelHandle, text, addSpecial, sendPort),
    );
    return _expect<LiteRtLmTokenizeResponse>(response, 'tokenization').tokens;
  }

  @override
  Future<String> detokenize(
    int modelHandle,
    List<int> tokens, {
    bool special = false,
  }) async {
    final response = await _sendRequest(
      (sendPort) =>
          LiteRtLmDetokenizeRequest(modelHandle, tokens, special, sendPort),
    );
    return _expect<LiteRtLmDetokenizeResponse>(response, 'detokenization').text;
  }

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async {
    final response = await _sendRequest(
      (sendPort) => LiteRtLmMetadataRequest(modelHandle, sendPort),
    );
    return _expect<LiteRtLmMetadataResponse>(
      response,
      'metadata lookup',
    ).metadata;
  }

  @override
  Future<void> setLoraAdapter(
    int contextHandle,
    String path,
    double scale,
  ) async {
    await _sendRequest(
      (sendPort) => LiteRtLmLoraRequest(
        contextHandle,
        'set',
        path: path,
        scale: scale,
        sendPort: sendPort,
      ),
    );
  }

  @override
  Future<void> removeLoraAdapter(int contextHandle, String path) async {
    await _sendRequest(
      (sendPort) => LiteRtLmLoraRequest(
        contextHandle,
        'remove',
        path: path,
        sendPort: sendPort,
      ),
    );
  }

  @override
  Future<void> clearLoraAdapters(int contextHandle) async {
    await _sendRequest(
      (sendPort) =>
          LiteRtLmLoraRequest(contextHandle, 'clear', sendPort: sendPort),
    );
  }

  @override
  Future<String> getBackendName() async {
    final preferredBackend = _preloadPreferredBackend();
    if (preferredBackend != null) {
      return 'LiteRT-LM $preferredBackend';
    }

    final response = await _sendRequest(LiteRtLmBackendInfoRequest.new);
    return _expect<LiteRtLmBackendInfoResponse>(
      response,
      'backend info lookup',
    ).name;
  }

  @override
  Future<String> getAvailableBackends() async {
    final response = await _sendRequest(LiteRtLmAvailableBackendsRequest.new);
    return _expect<LiteRtLmBackendInfoResponse>(
      response,
      'available backend lookup',
    ).name;
  }

  @override
  Future<int?> getResolvedGpuLayers() async {
    final preferredBackend = _preloadPreferredBackend();
    if (preferredBackend != null) {
      return preferredBackend == 'cpu' ? 0 : ModelParams.maxGpuLayers;
    }

    final response = await _sendRequest(LiteRtLmResolvedGpuLayersRequest.new);
    return _expect<LiteRtLmResolvedGpuLayersResponse>(
      response,
      'resolved GPU layer lookup',
    ).layers;
  }

  @override
  Future<BackendPerfContextData?> getPerformanceContext(
    int contextHandle,
  ) async {
    final response = await _sendRequest(
      (sendPort) => LiteRtLmPerformanceContextRequest(contextHandle, sendPort),
    );
    if (response is LiteRtLmDoneResponse) {
      return null;
    }
    final perf = _expect<LiteRtLmPerformanceContextResponse>(
      response,
      'performance context lookup',
    );
    return BackendPerfContextData(
      loadMs: perf.loadMs,
      promptEvalMs: perf.promptEvalMs,
      evalMs: perf.evalMs,
      sampleMs: perf.sampleMs,
      promptEvalTokens: perf.promptEvalTokens,
      evalTokens: perf.evalTokens,
      sampleCount: perf.sampleCount,
      reusedGraphs: perf.reusedGraphs,
    );
  }

  @override
  Future<bool> isGpuSupported() async {
    final response = await _sendRequest(LiteRtLmGpuSupportRequest.new);
    return _expect<LiteRtLmGpuSupportResponse>(
      response,
      'GPU support lookup',
    ).support;
  }

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {
    _currentLogLevel = level;
    if (_sendPort == null) {
      return;
    }
    await _sendRequest(
      (sendPort) => LiteRtLmLogLevelRequest(level, sendPort),
      ensureIsolate: false,
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _cancelGeneration();
    _activeGenerationCleanup?.call();

    final sendPort = _sendPort;
    if (sendPort != null) {
      final responsePort = ReceivePort();
      try {
        sendPort.send(LiteRtLmDisposeRequest(responsePort.sendPort));
        await responsePort.first.timeout(const Duration(seconds: 5));
      } catch (_) {
        // Native LiteRT-LM teardown can stall on some accelerator paths. The
        // isolate is killed below so app shutdown is not held indefinitely.
      } finally {
        responsePort.close();
      }
    }
    _killWorker();
    _isReady = false;
  }

  @override
  Future<int?> multimodalContextCreate(
    int modelHandle,
    String mmProjPath,
  ) async {
    final response = await _sendRequest(
      (sendPort) => LiteRtLmMultimodalContextCreateRequest(
        modelHandle,
        mmProjPath,
        sendPort,
      ),
    );
    return _expect<LiteRtLmHandleResponse>(
      response,
      'multimodal context creation',
    ).handle;
  }

  @override
  Future<void> multimodalContextFree(int mmContextHandle) async {
    await _sendRequest(
      (sendPort) =>
          LiteRtLmMultimodalContextFreeRequest(mmContextHandle, sendPort),
    );
  }

  @override
  Future<bool> supportsVision(int mmContextHandle) async {
    final response = await _sendRequest(
      (sendPort) => LiteRtLmSupportsVisionRequest(mmContextHandle, sendPort),
    );
    return response as bool;
  }

  @override
  Future<bool> supportsAudio(int mmContextHandle) async {
    final response = await _sendRequest(
      (sendPort) => LiteRtLmSupportsAudioRequest(mmContextHandle, sendPort),
    );
    return response as bool;
  }

  @override
  Future<({int total, int free})> getVramInfo() async {
    final response = await _sendRequest(LiteRtLmSystemInfoRequest.new);
    final info = _expect<LiteRtLmSystemInfoResponse>(
      response,
      'system info lookup',
    );
    return (total: info.totalVram, free: info.freeVram);
  }

  @override
  Future<String> applyChatTemplate(
    int modelHandle,
    List<Map<String, dynamic>> messages, {
    String? customTemplate,
    bool addAssistant = true,
  }) async {
    final response = await _sendRequest(
      (sendPort) => LiteRtLmChatTemplateRequest(
        modelHandle,
        messages,
        customTemplate,
        addAssistant,
        sendPort,
      ),
    );
    return _expect<LiteRtLmChatTemplateResponse>(
      response,
      'chat template application',
    ).result;
  }

  Future<void> _ensureIsolate() async {
    if (_disposed) {
      throw StateError('LiteRT-LM backend has been disposed.');
    }
    if (_sendPort != null) {
      return;
    }

    final existingStart = _isolateStart;
    if (existingStart != null) {
      await existingStart;
      if (_disposed) {
        throw StateError('LiteRT-LM backend has been disposed.');
      }
      if (_sendPort == null) {
        throw StateError('LiteRT-LM worker startup did not provide a port.');
      }
      return;
    }

    final generation = _workerGeneration;
    final start = _startIsolate(generation);
    _isolateStart = start;
    try {
      await start;
    } finally {
      if (identical(_isolateStart, start)) {
        _isolateStart = null;
      }
    }

    if (_disposed) {
      throw StateError('LiteRT-LM backend has been disposed.');
    }
    if (_sendPort == null) {
      throw StateError('LiteRT-LM worker startup did not provide a port.');
    }
  }

  Future<void> _startIsolate(int generation) async {
    final completer = Completer<void>();
    final tempPort = ReceivePort();
    late final StreamSubscription<Object?> subscription;
    subscription = tempPort.listen((message) {
      if (message is SendPort) {
        if (_disposed || generation != _workerGeneration) {
          if (!completer.isCompleted) {
            completer.completeError(
              StateError('LiteRT-LM worker startup was cancelled.'),
            );
          }
          unawaited(subscription.cancel());
          tempPort.close();
          return;
        }
        _sendPort = message;
        _sendPort!.send(LiteRtLmWorkerHandshake(_currentLogLevel));
        tempPort.close();
        unawaited(subscription.cancel());
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(liteRtLmWorkerEntry, tempPort.sendPort);
      if (_disposed || generation != _workerGeneration) {
        isolate.kill(priority: Isolate.immediate);
        throw StateError('LiteRT-LM worker startup was cancelled.');
      }
      _isolate = isolate;
      await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('Timed out starting LiteRT-LM worker.');
        },
      );
    } catch (_) {
      if (identical(_isolate, isolate)) {
        _isolate = null;
      }
      isolate?.kill(priority: Isolate.immediate);
      await subscription.cancel();
      tempPort.close();
      rethrow;
    }
  }

  Future<Object?> _sendRequest(
    LiteRtLmWorkerRequest Function(SendPort sendPort) buildRequest, {
    bool ensureIsolate = true,
    Duration? timeout,
  }) async {
    if (ensureIsolate) {
      await _ensureIsolate();
    }
    final sendPort = _sendPort;
    if (sendPort == null) {
      throw StateError('LiteRT-LM worker is not initialized.');
    }

    final responsePort = ReceivePort();
    try {
      sendPort.send(buildRequest(responsePort.sendPort));
      final response = timeout == null
          ? await responsePort.first
          : await responsePort.first.timeout(timeout);
      if (response is LiteRtLmErrorResponse) {
        _throwLiteRtLmError(response);
      }
      return response;
    } finally {
      responsePort.close();
    }
  }

  void _killWorker() {
    _activeGenerationCleanup?.call();
    _workerGeneration += 1;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _isolateStart = null;
    _activeGenerationCleanup = null;
    _isReady = false;
  }

  Future<void> _cancelActiveGeneration() async {
    final cleanup = _activeGenerationCleanup;
    if (cleanup == null) {
      return;
    }
    await _cancelGeneration();
    cleanup();
  }

  Future<void> _cancelGeneration() async {
    final sendPort = _sendPort;
    if (sendPort == null) {
      return;
    }
    final responsePort = ReceivePort();
    try {
      sendPort.send(LiteRtLmCancelGenerationRequest(responsePort.sendPort));
      await responsePort.first.timeout(const Duration(seconds: 1));
    } catch (_) {
      // Cancellation is best-effort because this method is also used by
      // StreamController.onCancel and dispose paths.
    } finally {
      responsePort.close();
    }
  }

  T _expect<T>(Object? response, String operation) {
    if (response is T) {
      return response;
    }
    throw StateError('Unexpected LiteRT-LM response during $operation.');
  }

  Never _throwLiteRtLmError(LiteRtLmErrorResponse response) {
    throw _exceptionForErrorResponse(response);
  }

  Object _exceptionForErrorResponse(LiteRtLmErrorResponse response) {
    switch (response.kind) {
      case 'unsupported':
        return UnsupportedError(response.message);
      case 'argument':
        return ArgumentError(response.message);
      case 'state':
        return StateError(response.message);
      default:
        return Exception(response.message);
    }
  }

  String? _preloadPreferredBackend() {
    final preferredBackend = _preferredBackend;
    if (_isReady || preferredBackend == null) {
      return null;
    }
    final backend = normalizeLiteRtLmNativeBackendOverride(preferredBackend);
    if (backend == null) {
      return null;
    }
    final available = liteRtLmAvailableNativeBackendsForCurrentPlatform();
    if (!available.contains(backend)) {
      throw ArgumentError(
        'LiteRtLmBackend backend $backend is not available on '
        '${Platform.operatingSystem}. Available LiteRT-LM backends: '
        '${available.join(', ')}.',
      );
    }
    return backend;
  }
}
