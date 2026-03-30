import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/service_providers.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/features/chat/data/chat_service.dart';
import 'package:localmind/features/chat/data/models/chat_parameters.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/conversations/data/models/conversation.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart'
    as conv;
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/core/providers/app_providers.dart';

final selectedModelProvider =
    NotifierProvider<SelectedModelNotifier, ModelInfo?>(() {
      return SelectedModelNotifier();
    });

class SelectedModelNotifier extends Notifier<ModelInfo?> {
  @override
  ModelInfo? build() => null;

  void setModel(ModelInfo? model) {
    state = model;
  }
}

final isStreamingProvider = NotifierProvider<IsStreamingNotifier, bool>(() {
  return IsStreamingNotifier();
});

class IsStreamingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setStreaming(bool streaming) {
    state = streaming;
  }
}

final chatParamsProvider = Provider<ChatParameters>((ref) {
  final settings = ref.watch(settingsProvider);
  return ChatParameters(
    temperature: settings.temperature,
    topP: settings.topP,
    maxTokens: settings.maxTokens,
    contextLength: settings.contextLength,
  );
});

final chatServiceProvider = Provider<ChatService>((ref) {
  final server = ref.watch(activeServerProvider);
  if (server == null) {
    throw StateError('No active server');
  }
  return ChatService.forServer(server.type, ref.read(dioProvider));
});

class ChatState {
  final List<Message> messages;
  final bool isStreaming;
  final String? errorMessage;
  final Message? streamingMessage;

  const ChatState({
    this.messages = const [],
    this.isStreaming = false,
    this.errorMessage,
    this.streamingMessage,
  });

  ChatState copyWith({
    List<Message>? messages,
    bool? isStreaming,
    String? errorMessage,
    Message? streamingMessage,
    bool clearError = false,
    bool clearStreaming = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isStreaming: isStreaming ?? this.isStreaming,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      streamingMessage: clearStreaming
          ? null
          : (streamingMessage ?? this.streamingMessage),
    );
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(() {
  return ChatNotifier();
});

class ChatNotifier extends Notifier<ChatState> {
  StreamSubscription<String>? _streamSubscription;
  String? _currentConversationId;

  @override
  ChatState build() {
    ref.onDispose(() {
      _streamSubscription?.cancel();
    });
    return const ChatState();
  }

  Future<void> loadConversation(Conversation conversation) async {
    _currentConversationId = conversation.id;
    final boxes = ref.read(hiveBoxesProvider);
    final messages = boxes.messages.values
        .where((m) => m.conversationId == conversation.id)
        .toList();
    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    state = ChatState(messages: messages);
    ref
        .read(conv.activeConversationProvider.notifier)
        .setActiveConversation(conversation);
  }

  Future<void> startNewConversation() async {
    await clearConversation();
    ref
        .read(conv.activeConversationProvider.notifier)
        .setActiveConversation(null);
  }

  String generateUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    return [
          bytes.sublist(0, 4),
          bytes.sublist(4, 6),
          bytes.sublist(6, 8),
          bytes.sublist(8, 10),
          bytes.sublist(10, 16),
        ]
        .map((b) => b.map((e) => e.toRadixString(16).padLeft(2, '0')).join())
        .join('-');
  }

  Future<void> sendMessage(String content) async {
    final server = ref.read(activeServerProvider);
    final selectedModel = ref.read(selectedModelProvider);
    final chatParams = ref.read(chatParamsProvider);
    final chatService = ref.read(chatServiceProvider);
    final boxes = ref.read(hiveBoxesProvider);

    if (server == null) {
      state = state.copyWith(errorMessage: 'No server connected');
      return;
    }

    if (content.trim().isEmpty) return;

    if (_currentConversationId == null) {
      final server = ref.read(activeServerProvider);
      final selectedModel = ref.read(selectedModelProvider);
      final conversation = await ref
          .read(conv.conversationsProvider.notifier)
          .createConversation(
            title: content.length > 50
                ? '${content.substring(0, 50)}...'
                : content,
            serverId: server?.id,
            modelId: selectedModel?.id,
          );
      _currentConversationId = conversation.id;
      ref
          .read(conv.activeConversationProvider.notifier)
          .setActiveConversation(conversation);
    }

    final userMessage = Message(
      id: generateUuid(),
      conversationId: _currentConversationId!,
      role: MessageRole.user,
      content: content,
      createdAt: DateTime.now(),
      status: MessageStatus.complete,
    );

    final assistantMessageId = generateUuid();
    var assistantMessage = Message(
      id: assistantMessageId,
      conversationId: _currentConversationId!,
      role: MessageRole.assistant,
      content: '',
      createdAt: DateTime.now(),
      status: MessageStatus.streaming,
      modelId: selectedModel?.id,
    );

    state = state.copyWith(
      messages: [...state.messages, userMessage, assistantMessage],
      isStreaming: true,
      streamingMessage: assistantMessage,
      clearError: true,
    );

    await boxes.messages.put(userMessage.id, userMessage);
    await boxes.messages.put(assistantMessage.id, assistantMessage);

    final messagesForApi = _buildMessagesForApi(selectedModel);

    try {
      _streamSubscription?.cancel();
      _streamSubscription = chatService
          .sendMessage(
            server: server,
            modelId: selectedModel?.id ?? 'default',
            messages: messagesForApi,
            params: chatParams,
          )
          .listen(
            (chunk) {
              final currentContent = state.streamingMessage?.content ?? '';
              final updatedMessage =
                  (state.streamingMessage ?? assistantMessage).copyWith(
                    content: currentContent + chunk,
                  );
              state = state.copyWith(streamingMessage: updatedMessage);
              final messageIndex = state.messages.indexWhere(
                (m) => m.id == assistantMessageId,
              );
              if (messageIndex != -1) {
                final updatedMessages = List<Message>.from(state.messages);
                updatedMessages[messageIndex] = updatedMessage;
                state = state.copyWith(messages: updatedMessages);
              }
            },
            onDone: () async {
              final finalMessage = state.streamingMessage?.copyWith(
                status: MessageStatus.complete,
              );
              if (finalMessage != null) {
                await boxes.messages.put(finalMessage.id, finalMessage);
                final messageIndex = state.messages.indexWhere(
                  (m) => m.id == assistantMessageId,
                );
                if (messageIndex != -1) {
                  final updatedMessages = List<Message>.from(state.messages);
                  updatedMessages[messageIndex] = finalMessage;
                  state = state.copyWith(
                    messages: updatedMessages,
                    isStreaming: false,
                    clearStreaming: true,
                  );
                }
                if (_currentConversationId != null) {
                  final preview = finalMessage.content.length > 100
                      ? '${finalMessage.content.substring(0, 100)}...'
                      : finalMessage.content;
                  await ref
                      .read(conv.conversationsProvider.notifier)
                      .updatePreview(
                        _currentConversationId!,
                        preview,
                        DateTime.now(),
                      );
                }
              }
            },
            onError: (error) async {
              final errorMessage = state.streamingMessage?.copyWith(
                status: MessageStatus.error,
                errorMessage: error.toString(),
              );
              if (errorMessage != null) {
                await boxes.messages.put(errorMessage.id, errorMessage);
                final messageIndex = state.messages.indexWhere(
                  (m) => m.id == assistantMessageId,
                );
                if (messageIndex != -1) {
                  final updatedMessages = List<Message>.from(state.messages);
                  updatedMessages[messageIndex] = errorMessage;
                  state = state.copyWith(
                    messages: updatedMessages,
                    isStreaming: false,
                    errorMessage: error.toString(),
                    clearStreaming: true,
                  );
                }
              }
            },
          );
    } catch (e) {
      state = state.copyWith(
        isStreaming: false,
        errorMessage: e.toString(),
        clearStreaming: true,
      );
    }
  }

  List<Message> _buildMessagesForApi(ModelInfo? selectedModel) {
    final settings = ref.read(settingsProvider);
    final messages = <Message>[];

    final personaPrompt = _getPersonaSystemPrompt();
    if (personaPrompt != null) {
      messages.add(
        Message(
          id: 'system-${_currentConversationId}',
          conversationId: _currentConversationId ?? '',
          role: MessageRole.system,
          content: personaPrompt,
          createdAt: DateTime.now(),
          status: MessageStatus.complete,
        ),
      );
    } else if (settings.showSystemMessages) {
      messages.add(
        Message(
          id: 'system-default-${_currentConversationId}',
          conversationId: _currentConversationId ?? '',
          role: MessageRole.system,
          content:
              'You are LocalMind, a helpful AI assistant. Provide clear, accurate, and concise responses.',
          createdAt: DateTime.now(),
          status: MessageStatus.complete,
        ),
      );
    }

    for (final message in state.messages) {
      if (message.role != MessageRole.system || settings.showSystemMessages) {
        messages.add(message);
      }
    }

    final contextLength = ref.read(chatParamsProvider).contextLength;
    return _truncateToContextWindow(messages, contextLength);
  }

  String? _getPersonaSystemPrompt() {
    final conversation = ref.read(conv.activeConversationProvider);
    final personaId = conversation?.personaId;
    if (personaId == null) return null;

    if (conversation?.systemPrompt != null &&
        conversation!.systemPrompt!.isNotEmpty) {
      return conversation.systemPrompt;
    }

    try {
      final boxes = ref.read(hiveBoxesProvider);
      final persona = boxes.personas.values.cast<dynamic>().firstWhere(
        (p) => p.id == personaId,
        orElse: () => null,
      );
      if (persona != null &&
          persona.systemPrompt != null &&
          persona.systemPrompt.isNotEmpty) {
        return persona.systemPrompt;
      }
    } catch (_) {}

    return null;
  }

  List<Message> _truncateToContextWindow(
    List<Message> messages,
    int contextLength,
  ) {
    if (messages.isEmpty) return messages;

    int estimatedTokens = 0;
    final result = <Message>[];
    const tokensPerChar = 4;

    for (int i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      estimatedTokens += (message.content.length / tokensPerChar).ceil();

      if (estimatedTokens > contextLength) {
        break;
      }
      result.insert(0, message);
    }

    return result;
  }

  void cancelStream() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    state = state.copyWith(isStreaming: false, clearStreaming: true);
  }

  Future<void> retryLastMessage() async {
    final messages = state.messages;
    if (messages.isEmpty) return;

    if (messages.last.role == MessageRole.assistant) {
      final lastAssistantIndex = messages.lastIndexWhere(
        (m) => m.role == MessageRole.assistant,
      );
      if (lastAssistantIndex > 0) {
        final userMessage = messages[lastAssistantIndex - 1];
        final messagesToRemove = messages.sublist(lastAssistantIndex);
        final boxes = ref.read(hiveBoxesProvider);

        for (final msg in messagesToRemove) {
          await boxes.messages.delete(msg.id);
        }

        state = state.copyWith(
          messages: messages.sublist(0, lastAssistantIndex),
          clearStreaming: true,
        );

        await sendMessage(userMessage.content);
      }
    }
  }

  Future<void> deleteMessage(String messageId) async {
    final boxes = ref.read(hiveBoxesProvider);
    await boxes.messages.delete(messageId);
    state = state.copyWith(
      messages: state.messages.where((m) => m.id != messageId).toList(),
    );
  }

  Future<void> clearConversation() async {
    final boxes = ref.read(hiveBoxesProvider);
    for (final message in state.messages) {
      await boxes.messages.delete(message.id);
    }
    _currentConversationId = null;
    state = const ChatState();
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}
