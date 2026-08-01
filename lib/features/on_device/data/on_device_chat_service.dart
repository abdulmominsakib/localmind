import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart' as gemma;

import '../../../core/logger/app_logger.dart';
import '../../../core/models/enums.dart';
import '../../../core/utils/bpe_decoder.dart';
import '../../chat/data/chat_service.dart';
import '../../chat/data/models/chat_parameters.dart';
import '../../chat/data/models/mcp_integration.dart';
import '../../chat/data/models/message.dart' hide ToolCallData;
import '../../chat/data/tools/tool_definition.dart';
import '../../servers/data/models/server.dart';
import 'on_device_gemma_service.dart';

class OnDeviceChatService implements ChatService {
  final OnDeviceGemmaService _gemmaService;
  StreamSubscription<gemma.ModelResponse>? _currentSubscription;
  StreamController<ChatResponse>? _streamController;
  gemma.InferenceChat? _activeChat;
  String? _activeModelId;
  String? _activeSystemInstruction;
  // Safe in Dart's single-threaded event loop: reads/writes are not
  // interrupted by other isolates, and async boundaries only yield control
  // at `await` points — so simple `bool` state is sufficient.
  bool _isCancelled = false;

  OnDeviceChatService(this._gemmaService);

  @override
  Stream<ChatResponse> sendMessage({
    required Server server,
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
    List<McpIntegration>? integrations,
    List<ToolDefinition>? tools,
    bool continueGeneration = false,
  }) {
    cancelStream();
    _isCancelled = false;
    _streamController = StreamController<ChatResponse>();

    _startInference(modelId, messages, params);

    return _streamController!.stream;
  }

  Future<void> _startInference(
    String modelId,
    List<Message> messages,
    ChatParameters params,
  ) async {
    try {
      if (!_gemmaService.isLoaded || _isCancelled) {
        _streamController?.add(
          const ChatResponse(
            type: ChatResponseType.error,
            content: 'Model not loaded',
          ),
        );
        _streamController?.add(const ChatResponse(type: ChatResponseType.done));
        await _streamController?.close();
        return;
      }

      final systemInstruction = params.systemPrompt?.isNotEmpty == true
          ? params.systemPrompt
          : null;

      final gemmaMessages = _convertMessages(messages);

      bool canReuse = false;
      List<gemma.Message> newMessagesToFeed = [];

      if (_activeChat != null &&
          _activeModelId == modelId &&
          _activeSystemInstruction == systemInstruction) {
        final existingHistory = _activeChat!.fullHistory;
        if (existingHistory.length <= gemmaMessages.length) {
          bool isPrefix = true;
          for (int i = 0; i < existingHistory.length; i++) {
            if (existingHistory[i].text != gemmaMessages[i].text ||
                existingHistory[i].isUser != gemmaMessages[i].isUser) {
              isPrefix = false;
              break;
            }
          }
          if (isPrefix) {
            canReuse = true;
            newMessagesToFeed = gemmaMessages.sublist(existingHistory.length);
          }
        }
      }

      gemma.InferenceChat chat;
      if (canReuse) {
        chat = _activeChat!;
        Log.debug('Reusing existing active chat session for on-device inference.');
        for (final msg in newMessagesToFeed) {
          if (_isCancelled) break;
          await chat.addQueryChunk(msg);
        }
      } else {
        Log.debug('Creating new chat session for on-device inference.');
        if (_activeChat != null) {
          _disposeChat(_activeChat!);
          _activeChat = null;
        }

        final newChat = await _gemmaService.createChat(
          systemInstruction: systemInstruction,
          tools: const [],
        );

        if (newChat == null) {
          _streamController?.add(
            const ChatResponse(
              type: ChatResponseType.error,
              content: 'Failed to create chat session',
            ),
          );
          _streamController?.add(const ChatResponse(type: ChatResponseType.done));
          await _streamController?.close();
          return;
        }

        chat = newChat;
        _activeChat = chat;
        _activeModelId = modelId;
        _activeSystemInstruction = systemInstruction;

        for (final msg in gemmaMessages) {
          if (_isCancelled) break;
          await chat.addQueryChunk(msg);
        }
      }

      if (_isCancelled) {
        _disposeChat(chat);
        _activeChat = null;
        _streamController?.add(const ChatResponse(type: ChatResponseType.done));
        await _streamController?.close();
        return;
      }

      // Start streaming response
      final responseStream = chat.generateChatResponseAsync();
      final completer = Completer<void>();

      final isBpeModel = modelId.toLowerCase().contains('qwen') ||
          modelId.toLowerCase().contains('deepseek');
      final textDecoder = isBpeModel ? BpeDecoder() : null;
      final reasoningDecoder = isBpeModel ? BpeDecoder() : null;

      _currentSubscription = responseStream.listen(
        (response) {
          if (_isCancelled) return;

          if (response is gemma.TextResponse) {
            if (response.token.isNotEmpty) {
              final content = textDecoder != null
                  ? textDecoder.decodeChunk(response.token)
                  : response.token;
              if (content.isNotEmpty) {
                _streamController?.add(
                  ChatResponse(
                    type: ChatResponseType.message,
                    content: content,
                  ),
                );
              }
            }
          } else if (response is gemma.FunctionCallResponse) {
            _streamController?.add(
              ChatResponse(
                type: ChatResponseType.toolCall,
                toolCall: ToolCallData(
                  tool: response.name,
                  arguments: response.args,
                ),
              ),
            );
          } else if (response is gemma.ThinkingResponse) {
            if (response.content.isNotEmpty) {
              final reasoningContent = reasoningDecoder != null
                  ? reasoningDecoder.decodeChunk(response.content)
                  : response.content;
              if (reasoningContent.isNotEmpty) {
                _streamController?.add(
                  ChatResponse(
                    type: ChatResponseType.reasoning,
                    reasoningContent: reasoningContent,
                  ),
                );
              }
            }
          }
        },
        onDone: () {
          if (!_isCancelled) {
            final finalToken = textDecoder?.flush() ?? '';
            final finalReasoning = reasoningDecoder?.flush() ?? '';
            if (finalToken.isNotEmpty) {
              _streamController?.add(
                ChatResponse(
                  type: ChatResponseType.message,
                  content: finalToken,
                ),
              );
            }
            if (finalReasoning.isNotEmpty) {
              _streamController?.add(
                ChatResponse(
                  type: ChatResponseType.reasoning,
                  reasoningContent: finalReasoning,
                ),
              );
            }
            _streamController?.add(
              const ChatResponse(type: ChatResponseType.done),
            );
            _streamController?.close();
          }
          _currentSubscription = null;
          if (!completer.isCompleted) completer.complete();
        },
        onError: (error) {
          Log.error('OnDevice stream error: $error');
          if (!_isCancelled && !(_streamController?.isClosed ?? true)) {
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
          _disposeChat(chat);
          if (_activeChat == chat) {
            _activeChat = null;
          }
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

  void _disposeChat(gemma.InferenceChat chat) {
    chat.close().catchError((e) {
      Log.error('Error disposing chat: $e');
    });
  }

  List<gemma.Message> _convertMessages(List<Message> messages) {
    var list = messages;
    if (list.isNotEmpty &&
        list.last.role == MessageRole.assistant &&
        list.last.content.isEmpty) {
      list = list.sublist(0, list.length - 1);
    }
    return list
        .where(
          (m) =>
              m.role == MessageRole.user ||
              m.role == MessageRole.assistant ||
              m.role == MessageRole.system,
        )
        .map(
          (m) => gemma.Message.text(
            text: m.content,
            isUser: m.role == MessageRole.user,
          ),
        )
        .toList();
  }

  @override
  void cancelStream() {
    _isCancelled = true;

    _currentSubscription?.cancel();
    _currentSubscription = null;

    if (_activeChat != null) {
      _activeChat!.stopGeneration().catchError((e) {
        Log.error('Error stopping generation: $e');
      });
    }

    if (!(_streamController?.isClosed ?? true)) {
      _streamController?.add(const ChatResponse(type: ChatResponseType.done));
      _streamController?.close();
    }
  }

  void dispose() {
    if (_activeChat != null) {
      _disposeChat(_activeChat!);
      _activeChat = null;
    }
  }
}
