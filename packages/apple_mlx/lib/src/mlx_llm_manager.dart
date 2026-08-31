import 'dart:async';
import 'package:lib_mlx/lib_mlx.dart';

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

/// High-level manager for running MLX LLM text generation models natively on Apple devices.
class AppleMlxLlmManager {
  final LibMlxRuntime _runtime;
  LibMlxOpenAiClient? _client;
  MlxModelHandle? _handle;
  MlxServerInfo? _serverInfo;

  AppleMlxLlmManager({LibMlxRuntime? runtime})
    : _runtime = runtime ?? const LibMlxRuntime();

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
    // Unload existing session if present
    await dispose();

    final config = MlxModelConfig(
      modelPath: modelPath,
      modelId: modelId,
      thinkingEnabled: thinkingEnabled,
      lazyEncoders: lazyEncoders,
    );

    _handle = await _runtime.loadModel(config);

    final serverConfig = MlxServerConfig(
      port: port,
      modelId: modelId,
      queueLimit: queueLimit,
    );

    _serverInfo = await _runtime.startServer(_handle!, config: serverConfig);
    _client = LibMlxOpenAiClient(baseUri: _serverInfo!.uri);

    return _serverInfo!;
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
        yield const AppleMlxChatDelta(isDone: true);
        break;
      }

      final choices = event.data?['choices'] as List?;
      final choice = choices?.firstOrNull as Map?;
      final delta = choice?['delta'] as Map?;

      if (delta != null) {
        final content = delta['content'] as String?;
        final reasoning = delta['reasoning_content'] as String?;

        if (content != null || reasoning != null) {
          yield AppleMlxChatDelta(
            content: content,
            reasoningContent: reasoning,
            rawData: event.data,
          );
        }
      }
    }
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
    final choices = response['choices'] as List?;
    if (choices != null && choices.isNotEmpty) {
      final first = choices.first as Map?;
      final message = first?['message'] as Map?;
      return message?['content'] as String? ?? '';
    }
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
    _client?.close();
    _client = null;

    final handle = _handle;
    if (handle != null) {
      try {
        await _runtime.stopServer(handle);
      } catch (_) {}
      try {
        await _runtime.unloadModel(handle);
      } catch (_) {}
      _handle = null;
    }
    _serverInfo = null;
  }
}
