import 'dart:async';

import 'package:llamadart/llamadart.dart' as llama;

import '../../../core/logger/app_logger.dart';
import '../../../core/models/enums.dart';
import '../../chat/data/chat_service.dart';
import '../../chat/data/models/chat_parameters.dart';
import '../../chat/data/models/mcp_integration.dart';
import '../../chat/data/models/message.dart' hide ToolCallData;
import '../../chat/data/tools/tool_definition.dart';
import '../../servers/data/models/server.dart';
import 'models/on_device_model.dart';

class OnDeviceLlamaService {
  llama.LlamaEngine? _engine;
  llama.ChatSession? _session;
  String? _currentModelId;
  int? _currentContextLength;
  String? _currentSystemPrompt;
  bool _isDisposed = false;

  /// Tracks the most recent user message we processed, so we can detect
  /// out-of-band edits or regenerations and rebuild the chat history.
  String? _lastUserMessageId;
  int _userMessageCount = 0;

  String? get currentModelId => _currentModelId;
  bool get isLoaded => _engine != null && !_isDisposed;

  Future<void> loadModel(
    OnDeviceModel model, {
    int contextLength = 4096,
    bool useGpu = false,
  }) async {
    if (_isDisposed) {
      throw StateError('OnDeviceLlamaService has been disposed');
    }
    if (model.localPath == null || model.localPath!.isEmpty) {
      throw StateError('Imported GGUF model is missing a local file path');
    }

    final gpuLayers = useGpu ? llama.ModelParams.maxGpuLayers : 0;
    final alreadyLoaded = _engine != null && _currentModelId == model.id;
    final contextChanged = _currentContextLength != contextLength;

    if (alreadyLoaded && !contextChanged) {
      return;
    }

    await unloadModel();

    Log.info(
      'Loading GGUF model ${model.id} from ${model.localPath} '
      '(context=$contextLength, gpuLayers=$gpuLayers)',
    );
    final engine = llama.LlamaEngine(llama.LlamaBackend());
    await engine.loadModel(
      model.localPath!,
      modelParams: llama.ModelParams(
        contextSize: contextLength,
        gpuLayers: gpuLayers,
      ),
    );

    _engine = engine;
    _currentModelId = model.id;
    _currentContextLength = contextLength;
    _session = null;
    _currentSystemPrompt = null;
    _lastUserMessageId = null;
    _userMessageCount = 0;
    Log.info('GGUF model ${model.id} loaded successfully');
  }

  /// Resets the chat session so the next [sendMessage] starts from an empty
  /// history. Useful when the caller knows the upstream message list has been
  /// edited or regenerated outside of this service.
  void resetSession() {
    _session = null;
    _currentSystemPrompt = null;
    _lastUserMessageId = null;
    _userMessageCount = 0;
  }

  Stream<ChatResponse> sendMessage({
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
  }) async* {
    final engine = _engine;
    if (engine == null || _currentModelId != modelId) {
      yield const ChatResponse(
        type: ChatResponseType.error,
        content: 'GGUF model not loaded',
      );
      yield const ChatResponse(type: ChatResponseType.done);
      return;
    }

    final userMessages = messages
        .where((m) => m.role == MessageRole.user)
        .toList(growable: false);
    if (userMessages.isEmpty) {
      yield const ChatResponse(
        type: ChatResponseType.error,
        content: 'GGUF chat requires a user message.',
      );
      yield const ChatResponse(type: ChatResponseType.done);
      return;
    }

    final latestUserMessage = userMessages.last;
    final systemPrompt = params.systemPrompt?.isNotEmpty == true
        ? params.systemPrompt
        : null;
    final sessionContextChanged =
        _session != null && _currentContextLength != params.contextLength;

    if (_session == null ||
        _currentSystemPrompt != systemPrompt ||
        sessionContextChanged) {
      _session = llama.ChatSession(
        engine,
        maxContextTokens: params.contextLength,
        systemPrompt: systemPrompt,
      );
      _currentSystemPrompt = systemPrompt;
      _currentContextLength = params.contextLength;
      _userMessageCount = 0;
      _lastUserMessageId = null;
    } else if (userMessages.length < _userMessageCount ||
        (_lastUserMessageId != null &&
            latestUserMessage.id != _lastUserMessageId)) {
      // Upstream history diverged from our internal tracking (edit, retry,
      // regeneration). Discard the cached history and rebuild it from the
      // caller-supplied messages on the next create() call.
      _session!.reset(keepSystemPrompt: true);
      _userMessageCount = 0;
      _lastUserMessageId = null;
    }

    final text = latestUserMessage.content.trim();
    if (text.isEmpty) {
      yield const ChatResponse(
        type: ChatResponseType.error,
        content: 'GGUF chat requires a text prompt.',
      );
      yield const ChatResponse(type: ChatResponseType.done);
      return;
    }

    try {
      await for (final chunk in _session!.create(
        [llama.LlamaTextContent(text)],
        params: llama.GenerationParams(
          maxTokens: params.maxTokens,
          temp: params.temperature,
          topP: params.topP,
          topK: params.topK ?? 40,
          minP: params.minP ?? 0.0,
          penalty: params.repeatPenalty ?? 1.1,
        ),
      )) {
        if (chunk.choices.isEmpty) continue;
        final delta = chunk.choices.first.delta;
        final reasoning = delta.thinking;
        if (reasoning != null && reasoning.isNotEmpty) {
          yield ChatResponse(
            type: ChatResponseType.reasoning,
            reasoningContent: reasoning,
          );
        }
        final content = delta.content;
        if (content != null && content.isNotEmpty) {
          yield ChatResponse(type: ChatResponseType.message, content: content);
        }
      }
      _userMessageCount = userMessages.length;
      _lastUserMessageId = latestUserMessage.id;
      yield const ChatResponse(type: ChatResponseType.done);
    } catch (e) {
      Log.error('GGUF inference error: $e');
      yield ChatResponse(
        type: ChatResponseType.error,
        content: 'GGUF inference error: ${e.toString()}',
      );
      yield const ChatResponse(type: ChatResponseType.done);
    }
  }

  /// Cancels the currently running inference, if any. Safe to call when no
  /// generation is in progress.
  void cancelGeneration() {
    final engine = _engine;
    if (engine == null) return;
    try {
      engine.backend.cancelGeneration();
    } catch (e) {
      Log.error('Failed to cancel GGUF generation: $e');
    }
  }

  Future<void> unloadModel() async {
    final engine = _engine;
    _engine = null;
    _session = null;
    _currentModelId = null;
    _currentContextLength = null;
    _currentSystemPrompt = null;
    _lastUserMessageId = null;
    _userMessageCount = 0;
    if (engine != null) {
      try {
        await engine.dispose();
      } catch (e) {
        Log.error('Error disposing GGUF engine: $e');
      }
    }
  }

  void dispose() {
    _isDisposed = true;
    unawaited(unloadModel());
  }
}

class OnDeviceLlamaChatService implements ChatService {
  OnDeviceLlamaChatService(this._llamaService);

  final OnDeviceLlamaService _llamaService;
  bool _isCancelled = false;

  @override
  Stream<ChatResponse> sendMessage({
    required Server server,
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
    List<McpIntegration>? integrations,
    List<ToolDefinition>? tools,
    bool continueGeneration = false,
  }) async* {
    _isCancelled = false;
    await for (final response in _llamaService.sendMessage(
      modelId: modelId,
      messages: messages,
      params: params,
    )) {
      if (_isCancelled) break;
      yield response;
      if (response.type == ChatResponseType.done ||
          response.type == ChatResponseType.error) {
        break;
      }
    }
  }

  @override
  void cancelStream() {
    _isCancelled = true;
    _llamaService.cancelGeneration();
  }
}
