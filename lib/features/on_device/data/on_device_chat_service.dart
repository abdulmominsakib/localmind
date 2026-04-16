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

      final liteMessages = _convertMessages(messages);

      if (_isCancelled) {
        await conversation.dispose();
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
        _streamController?.add(const ChatResponse(type: ChatResponseType.done));
        await _streamController?.close();
        return;
      }

      final stream = conversation.sendMessageStream(lastUserMessage.text ?? '');

      final buffer = StringBuffer();
      await for (final delta in stream) {
        if (_isCancelled) {
          await conversation.dispose();
          _streamController?.add(
            const ChatResponse(type: ChatResponseType.done),
          );
          await _streamController?.close();
          return;
        }

        if (delta.text.isNotEmpty) {
          buffer.write(delta.text);
          _streamController?.add(
            ChatResponse(type: ChatResponseType.message, content: delta.text),
          );
        }

        if (delta.toolCalls.isNotEmpty) {
          for (final tc in delta.toolCalls) {
            _streamController?.add(
              ChatResponse(
                type: ChatResponseType.toolCall,
                toolCall: ToolCallData(tool: tc.name, arguments: tc.arguments),
              ),
            );
          }
        }
      }

      _streamController?.add(const ChatResponse(type: ChatResponseType.done));
      await conversation.dispose();
      await _streamController?.close();
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
    _currentSubscription?.cancel();
    _currentSubscription = null;
    if (!(_streamController?.isClosed ?? true)) {
      _streamController?.add(const ChatResponse(type: ChatResponseType.done));
      _streamController?.close();
    }
  }
}
