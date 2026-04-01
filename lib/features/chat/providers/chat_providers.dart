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

final autoSelectFirstLoadedModelProvider = FutureProvider<void>((ref) async {
  final selectedModel = ref.read(selectedModelProvider);
  if (selectedModel != null) return;

  final activeServer = ref.read(activeServerProvider);
  if (activeServer == null) return;
  if (activeServer.type == ServerType.openRouter) return;

  final apiService = ref.read(serverApiServiceProvider);
  final loadedModels = await apiService.fetchRunningModels(activeServer);
  if (loadedModels.isEmpty) return;

  final availableModels = await ref.read(
    availableModelsProvider(activeServer.id).future,
  );
  if (availableModels.isEmpty) return;

  final typedModels = availableModels.cast<ModelInfo>();
  final firstLoadedModel = typedModels
      .where((m) => loadedModels.contains(m.id))
      .firstOrNull;

  if (firstLoadedModel != null) {
    ref.read(selectedModelProvider.notifier).setModel(firstLoadedModel);
  }
});

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

class ModelLoadingState {
  final bool isLoading;
  final String? modelId;
  final double? progress;

  const ModelLoadingState({
    this.isLoading = false,
    this.modelId,
    this.progress,
  });

  ModelLoadingState copyWith({
    bool? isLoading,
    String? modelId,
    double? progress,
  }) {
    return ModelLoadingState(
      isLoading: isLoading ?? this.isLoading,
      modelId: modelId ?? this.modelId,
      progress: progress ?? this.progress,
    );
  }
}

final modelLoadingProvider =
    NotifierProvider<ModelLoadingNotifier, ModelLoadingState>(() {
      return ModelLoadingNotifier();
    });

class ModelLoadingNotifier extends Notifier<ModelLoadingState> {
  @override
  ModelLoadingState build() => const ModelLoadingState();

  void setLoading(String modelId, {double? progress}) {
    state = ModelLoadingState(
      isLoading: true,
      modelId: modelId,
      progress: progress,
    );
  }

  void updateProgress(double progress) {
    state = state.copyWith(progress: progress);
  }

  void setLoaded() {
    state = const ModelLoadingState();
  }
}

final modelThinkingProvider = Provider<bool>((ref) {
  return ref.watch(isStreamingProvider);
});

final chatParamsProvider = Provider<ChatParameters>((ref) {
  final settings = ref.watch(settingsProvider);
  final activeConv = ref.watch(conv.activeConversationProvider);

  double temperature = settings.temperature;
  double topP = settings.topP;
  int maxTokens = settings.maxTokens;
  int contextLength = settings.contextLength;

  if (activeConv?.personaId != null) {
    final personaId = activeConv!.personaId;
    try {
      final boxes = ref.read(hiveBoxesProvider);
      final persona = boxes.personas.values.cast<dynamic>().firstWhere(
        (p) => p.id == personaId,
        orElse: () => null,
      );
      if (persona != null && persona.preferredParams != null) {
        final params = persona.preferredParams as Map<String, dynamic>;
        if (params['temperature'] != null)
          temperature = (params['temperature'] as num).toDouble();
        if (params['topP'] != null) topP = (params['topP'] as num).toDouble();
        if (params['maxTokens'] != null)
          maxTokens = (params['maxTokens'] as num).toInt();
      }
    } catch (_) {}
  }

  return ChatParameters(
    temperature: temperature,
    topP: topP,
    maxTokens: maxTokens,
    contextLength: contextLength,
  );
});

final chatServiceProvider = Provider<ChatService>((ref) {
  final server = ref.watch(activeServerProvider);
  if (server == null) {
    throw StateError('No active server');
  }
  return ChatService.forServer(server.type, ref.read(dioProvider));
});

final smartRepliesProvider = Provider<List<String>>((ref) {
  final chatState = ref.watch(chatProvider);
  final isStreaming = ref.watch(isStreamingProvider);

  if (chatState.messages.length < 2 || isStreaming) return [];

  final lastAssistant = chatState.messages.reversed.firstWhere(
    (m) =>
        m.role == MessageRole.assistant && m.status == MessageStatus.complete,
    orElse: () => chatState.messages.last,
  );
  if (lastAssistant.role != MessageRole.assistant) return [];

  final content = lastAssistant.content.toLowerCase();
  final suggestions = <String>[];

  if (content.contains('```') ||
      content.contains('function') ||
      content.contains('class ') ||
      content.contains('import ')) {
    suggestions.addAll([
      'Explain this code',
      'How can I improve this?',
      'Add error handling',
      'Write tests for this',
    ]);
  } else if (content.contains('step') ||
      content.contains('first') ||
      content.contains('then')) {
    suggestions.addAll([
      'Can you elaborate on step 1?',
      'What if I get stuck?',
      'Give me a summary',
    ]);
  } else if (content.contains('error') ||
      content.contains('problem') ||
      content.contains('issue')) {
    suggestions.addAll([
      'Show me a fix',
      'What else could cause this?',
      'How to prevent this?',
    ]);
  } else {
    suggestions.addAll([
      'Tell me more',
      'Give me an example',
      'Summarize this',
      'What are the alternatives?',
    ]);
  }

  return suggestions;
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
  StreamSubscription<ChatResponse>? _streamSubscription;
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

      String reasoningContent = '';

      _streamSubscription = chatService
          .sendMessage(
            server: server,
            modelId: selectedModel?.id ?? 'default',
            messages: messagesForApi,
            params: chatParams,
          )
          .listen(
            (response) {
              switch (response.type) {
                case ChatResponseType.message:
                  final currentContent = state.streamingMessage?.content ?? '';
                  final updatedMessage =
                      (state.streamingMessage ?? assistantMessage).copyWith(
                        content: currentContent + (response.content ?? ''),
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
                  break;
                case ChatResponseType.reasoning:
                  reasoningContent += response.reasoningContent ?? '';
                  final reasoningMessage =
                      (state.streamingMessage ?? assistantMessage).copyWith(
                        reasoningContent: reasoningContent,
                      );
                  state = state.copyWith(streamingMessage: reasoningMessage);
                  final msgIndex = state.messages.indexWhere(
                    (m) => m.id == assistantMessageId,
                  );
                  if (msgIndex != -1) {
                    final updatedMessages = List<Message>.from(state.messages);
                    updatedMessages[msgIndex] = reasoningMessage;
                    state = state.copyWith(messages: updatedMessages);
                  }
                  break;
                case ChatResponseType.toolCall:
                case ChatResponseType.invalidToolCall:
                case ChatResponseType.done:
                  break;
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

                  final userMessage = state.messages
                      .where((m) => m.role == MessageRole.user)
                      .firstOrNull;
                  if (userMessage != null && userMessage.content.length > 10) {
                    _autoGenerateTitle(
                      userMessage.content,
                      finalMessage.content,
                    );
                  }
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

  void _autoGenerateTitle(String userContent, String assistantContent) {
    final settings = ref.read(settingsProvider);
    if (!settings.autoGenerateTitle) return;
    if (_currentConversationId == null) return;

    final activeConv = ref.read(conv.activeConversationProvider);
    if (activeConv == null) return;
    if (activeConv.title != 'New Chat') return;

    final title = userContent.length > 40
        ? '${userContent.substring(0, 40)}...'
        : userContent;

    ref
        .read(conv.conversationsProvider.notifier)
        .renameConversation(_currentConversationId!, title);
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
