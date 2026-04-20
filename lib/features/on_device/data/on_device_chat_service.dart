import 'dart:async';

import 'package:flutter_litert_lm/flutter_litert_lm.dart';

import '../../../core/logger/app_logger.dart';
import '../../../core/models/enums.dart';
import '../../chat/data/chat_service.dart';
import '../../chat/data/models/chat_parameters.dart';
import '../../chat/data/models/mcp_integration.dart';
import '../../chat/data/models/message.dart' hide ToolCallData;
import '../../servers/data/models/server.dart';
import 'on_device_engine_service.dart';

class OnDeviceChatService implements ChatService {
  final OnDeviceEngineService _engineService;
  StreamSubscription<LiteLmMessage>? _currentSubscription;
  StreamController<ChatResponse>? _streamController;
  LiteLmConversation? _activeConversation;
  bool _isCancelled = false;

  OnDeviceChatService(this._engineService);

  @override
  Stream<ChatResponse> sendMessage({
    required Server server,
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
    List<McpIntegration>? integrations,
    String? previousResponseId,
  }) {
    // Cancel any previous inference before starting a new one
    cancelStream();
    _isCancelled = false;
    _streamController = StreamController<ChatResponse>();

    _startInference(messages, params);

    return _streamController!.stream;
  }

  Future<void> _startInference(
    List<Message> messages,
    ChatParameters params,
  ) async {
    try {
      if (_engineService.engine == null || _isCancelled) {
        _streamController?.add(
          const ChatResponse(
            type: ChatResponseType.error,
            content: 'Engine not loaded',
          ),
        );
        _streamController?.add(const ChatResponse(type: ChatResponseType.done));
        await _streamController?.close();
        return;
      }

      final systemInstruction = params.systemPrompt?.isNotEmpty == true
          ? params.systemPrompt
          : null;

      final samplerConfig = LiteLmSamplerConfig(
        temperature: params.temperature,
        topK: 40,
        topP: params.topP,
      );

      final conversation = await _engineService.createConversation(
        systemInstruction: systemInstruction,
        samplerConfig: samplerConfig,
      );

      // Store a reference so cancelStream can dispose it
      _activeConversation = conversation;

      final liteMessages = _convertMessages(messages);

      if (_isCancelled) {
        _disposeConversation(conversation);
        _streamController?.add(const ChatResponse(type: ChatResponseType.done));
        await _streamController?.close();
        return;
      }

      final lastUserMessage = liteMessages
          .where((m) => m.role == 'user')
          .lastOrNull;
      if (lastUserMessage == null) {
        _streamController?.add(
          const ChatResponse(
            type: ChatResponseType.error,
            content: 'No user message found',
          ),
        );
        _disposeConversation(conversation);
        _streamController?.add(const ChatResponse(type: ChatResponseType.done));
        await _streamController?.close();
        return;
      }

      final stream = conversation.sendMessageStream(lastUserMessage.text ?? '');

      // Use .listen() instead of `await for` so the subscription can be
      // cancelled externally without waiting for the next native token.
      final completer = Completer<void>();

      _currentSubscription = stream.listen(
        (delta) {
          if (_isCancelled) return;

          if (delta.text.isNotEmpty) {
            _streamController?.add(
              ChatResponse(
                type: ChatResponseType.message,
                content: delta.text,
              ),
            );
          }

          if (delta.toolCalls.isNotEmpty) {
            for (final tc in delta.toolCalls) {
              _streamController?.add(
                ChatResponse(
                  type: ChatResponseType.toolCall,
                  toolCall:
                      ToolCallData(tool: tc.name, arguments: tc.arguments),
                ),
              );
            }
          }
        },
        onDone: () {
          if (!_isCancelled) {
            _streamController?.add(
              const ChatResponse(type: ChatResponseType.done),
            );
            _disposeConversation(conversation);
            _streamController?.close();
          }
          _activeConversation = null;
          _currentSubscription = null;
          if (!completer.isCompleted) completer.complete();
        },
        onError: (error) {
          Log.error('OnDevice stream error: $error');
          if (!_isCancelled &&
              !(_streamController?.isClosed ?? true)) {
            _streamController?.add(
              ChatResponse(
                type: ChatResponseType.error,
                content: 'Inference error: ${error.toString()}',
              ),
            );
            _streamController?.add(
              const ChatResponse(type: ChatResponseType.done),
            );
            _streamController?.close();
          }
          _disposeConversation(conversation);
          _activeConversation = null;
          _currentSubscription = null;
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      await completer.future;
    } catch (e) {
      Log.error('OnDevice inference error: $e');
      if (!(_streamController?.isClosed ?? true)) {
        _streamController?.add(
          ChatResponse(
            type: ChatResponseType.error,
            content: 'Inference error: ${e.toString()}',
          ),
        );
        _streamController?.add(const ChatResponse(type: ChatResponseType.done));
        await _streamController?.close();
      }
    }
  }

  /// Dispose a conversation without blocking — fire and forget.
  void _disposeConversation(LiteLmConversation conversation) {
    conversation.dispose().catchError((e) {
      Log.error('Error disposing conversation: $e');
    });
  }

  List<({String role, String? text})> _convertMessages(List<Message> messages) {
    return messages
        .where(
          (m) =>
              m.role == MessageRole.user ||
              m.role == MessageRole.assistant ||
              m.role == MessageRole.system,
        )
        .map((m) => (role: m.role.name, text: m.content))
        .toList();
  }

  @override
  void cancelStream() {
    _isCancelled = true;

    // Cancel the native stream subscription first — this stops the
    // EventChannel from delivering more tokens and unblocks the loop.
    _currentSubscription?.cancel();
    _currentSubscription = null;

    // Dispose the active conversation (fire-and-forget to avoid blocking
    // the UI thread if the native side is mid-inference).
    final conversation = _activeConversation;
    _activeConversation = null;
    if (conversation != null) {
      _disposeConversation(conversation);
    }

    if (!(_streamController?.isClosed ?? true)) {
      _streamController?.add(const ChatResponse(type: ChatResponseType.done));
      _streamController?.close();
    }
  }
}
