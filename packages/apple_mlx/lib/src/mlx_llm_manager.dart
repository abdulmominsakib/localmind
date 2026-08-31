import 'dart:async';
import 'package:lib_mlx/lib_mlx.dart';

import 'mlx_capabilities.dart';

typedef AppleMlxOpenAiClientFactory = LibMlxOpenAiClient Function(Uri baseUri);

/// Represents streaming chunk delta from an MLX LLM generation.
class AppleMlxChatDelta {
  /// Regular content delta chunk.
  final String? content;

  /// Reasoning / thinking delta chunk (if model supports thinking).
  final String? reasoningContent;

  /// Whether generation is finished.
  final bool isDone;

  /// Raw chunk data if available.
  final Map<String, Object?>? rawData;

  const AppleMlxChatDelta({
    this.content,
    this.reasoningContent,
    this.isDone = false,
    this.rawData,
  });
}

/// High-level client for the native `lib_mlx` lifecycle and localhost server.
///
/// Check [AppleMlxCapabilities.nativeLlmInferenceAvailable] before exposing
/// this manager as an inference backend.
class AppleMlxLlmManager {
  final LibMlxRuntime _runtime;
  final AppleMlxOpenAiClientFactory _clientFactory;
  LibMlxOpenAiClient? _client;
  MlxModelHandle? _handle;
  MlxServerInfo? _serverInfo;

  AppleMlxLlmManager({
    LibMlxRuntime? runtime,
    AppleMlxOpenAiClientFactory? clientFactory,
  }) : _runtime = runtime ?? const LibMlxRuntime(),
       _clientFactory =
           clientFactory ?? ((baseUri) => LibMlxOpenAiClient(baseUri: baseUri));

  bool get isModelLoaded => _handle != null;
  bool get isServerRunning => _serverInfo != null;
  MlxServerInfo? get serverInfo => _serverInfo;
  MlxModelHandle? get modelHandle => _handle;

  /// Loads an MLX model from disk and starts the local OpenAI-compatible inference server.
  Future<MlxServerInfo> loadAndStartServer({
    required String modelPath,
    String modelId = MlxAvailableModel.defaultHuggingFaceModelId,
    bool thinkingEnabled = true,
    bool lazyEncoders = true,
    int port = 0,
    int queueLimit = 1,
  }) async {
    await dispose();

    final config = MlxModelConfig(
      modelPath: modelPath,
      modelId: modelId,
      thinkingEnabled: thinkingEnabled,
      lazyEncoders: lazyEncoders,
    );

    try {
      _handle = await _runtime.loadModel(config);

      final serverConfig = MlxServerConfig(
        port: port,
        modelId: modelId,
        queueLimit: queueLimit,
      );

      final serverInfo = await _runtime.startServer(
        _handle!,
        config: serverConfig,
      );
      _serverInfo = serverInfo;
      _client = _clientFactory(serverInfo.uri);
      return serverInfo;
    } catch (_) {
      // Loading succeeds before the server is started. If either server start
      // or client construction fails, release that resident native handle so
      // the next attempt does not leak model memory.
      await dispose();
      rethrow;
    }
  }

  /// Streams chat completions using Server-Sent Events (SSE).
  Stream<AppleMlxChatDelta> generateStream({
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int? maxTokens,
    bool thinking = true,
  }) async* {
    final client = _client;
    final serverInfo = _serverInfo;
    if (client == null || serverInfo == null) {
      throw StateError(
        'AppleMlxLlmManager: Model is not loaded or server is not running. Call loadAndStartServer() first.',
      );
    }

    final request = <String, Object?>{
      'model': serverInfo.modelId,
      'messages': messages,
      'temperature': temperature,
      'thinking': thinking,
      'max_tokens': ?maxTokens,
    };

    final sseStream = client.chatCompletionsStream(request);

    await for (final event in sseStream) {
      if (event.done) {
        break;
      }

      final choices = event.data?['choices'];
      if (choices is! List || choices.isEmpty) continue;

      final choice = choices.first;
      if (choice is! Map) continue;

      final delta = choice['delta'];
      if (delta is! Map) continue;

      final rawContent = delta['content'];
      final rawReasoning = delta['reasoning_content'];
      final content = rawContent is String ? rawContent : null;
      final reasoning = rawReasoning is String ? rawReasoning : null;

      if (content != null || reasoning != null) {
        yield AppleMlxChatDelta(
          content: content,
          reasoningContent: reasoning,
          rawData: event.data,
        );
      }
    }

    // Some HTTP servers close a valid SSE response without a final [DONE]
    // sentinel. Always terminate the higher-level stream consistently.
    yield const AppleMlxChatDelta(isDone: true);
  }

  /// Generates non-streaming completion response.
  Future<String> generate({
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int? maxTokens,
  }) async {
    final client = _client;
    final serverInfo = _serverInfo;
    if (client == null || serverInfo == null) {
      throw StateError(
        'AppleMlxLlmManager: Model is not loaded or server is not running. Call loadAndStartServer() first.',
      );
    }

    final request = <String, Object?>{
      'model': serverInfo.modelId,
      'messages': messages,
      'temperature': temperature,
      'max_tokens': ?maxTokens,
    };

    final response = await client.chatCompletions(request);
    final choices = response['choices'];
    if (choices is! List || choices.isEmpty) return '';

    final first = choices.first;
    if (first is! Map) return '';

    final message = first['message'];
    if (message is! Map) return '';

    final content = message['content'];
    if (content is String) return content;
    return '';
  }

  /// Checks the current runtime and model status.
  Future<MlxRuntimeStatus?> checkStatus() async {
    final handle = _handle;
    if (handle == null) return null;
    return _runtime.serverStatus(handle);
  }

  /// Stops server, unloads model, and releases memory.
  Future<void> dispose() async {
    final client = _client;
    final handle = _handle;

    _client = null;
    _handle = null;
    _serverInfo = null;
    client?.close(force: true);

    if (handle != null) {
      try {
        await _runtime.stopServer(handle);
      } catch (_) {}
      try {
        await _runtime.unloadModel(handle);
      } catch (_) {}
    }
  }
}
