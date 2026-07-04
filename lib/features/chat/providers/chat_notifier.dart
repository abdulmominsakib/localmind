import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/core/logger/app_logger.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/providers/review_prompt_providers.dart';
import 'package:localmind/core/providers/service_providers.dart';
import 'package:localmind/core/providers/chat_background_service_provider.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/core/services/message_save_service.dart';
import 'package:localmind/core/storage/entities.dart';
import 'package:localmind/features/conversations/data/models/conversation.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart'
    as conv;
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:localmind/features/personas/providers/personas_providers.dart';
import 'package:localmind/features/personas/utils/persona_prompt_utils.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/objectbox.g.dart';
import '../data/chat_service.dart';
import '../data/models/message.dart' hide ToolCallData;
import '../data/title_generation_service.dart';
import '../data/tools/tool_definition.dart';
import '../data/tools/tool_execution_loop.dart';
import '../data/tools/adapters/tool_transport_adapter.dart' show ParsedToolCall;
import '../utils/attachment_helpers.dart';
import 'chat_mcp_providers.dart';
import 'chat_origin_provider.dart';
import 'chat_params_providers.dart';
import 'chat_reasoning_providers.dart';
import 'chat_service_providers.dart';
import 'message_selection_provider.dart';
import 'model_selection_providers.dart';
import 'tooling_providers.dart';
import '../utils/message_variants.dart';

class PendingToolApproval {
  final ParsedToolCall toolCall;
  final Completer<bool> completer;

  PendingToolApproval({required this.toolCall, required this.completer});
}

class ChatState {
  final List<Message> messages;
  final List<Message> allMessages;
  final bool isStreaming;
  final bool isLoading;
  final String? errorMessage;
  final Message? streamingMessage;
  final PendingToolApproval? pendingToolApproval;
  final bool isTemporary;

  const ChatState({
    this.messages = const [],
    this.allMessages = const [],
    this.isStreaming = false,
    this.isLoading = false,
    this.errorMessage,
    this.streamingMessage,
    this.pendingToolApproval,
    this.isTemporary = false,
  });

  ChatState copyWith({
    List<Message>? messages,
    List<Message>? allMessages,
    bool? isStreaming,
    bool? isLoading,
    String? errorMessage,
    Message? streamingMessage,
    PendingToolApproval? pendingToolApproval,
    bool? isTemporary,
    bool clearError = false,
    bool clearStreaming = false,
    bool clearPendingApproval = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      allMessages: allMessages ?? this.allMessages,
      isStreaming: isStreaming ?? this.isStreaming,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      streamingMessage: clearStreaming
          ? null
          : (streamingMessage ?? this.streamingMessage),
      pendingToolApproval: clearPendingApproval
          ? null
          : (pendingToolApproval ?? this.pendingToolApproval),
      isTemporary: isTemporary ?? this.isTemporary,
    );
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(() {
  return ChatNotifier();
});

class ChatNotifier extends Notifier<ChatState> {
  static const _checkpointChunkThreshold = 20;
  static const _checkpointTimeThreshold = Duration(seconds: 2);

  StreamSubscription<ChatResponse>? _streamSubscription;
  int _streamGeneration = 0;
  Timer? _uiUpdateTimer;
  Message? _latestStreamingMessage;
  String? _currentConversationId;
  int _chunkCount = 0;
  DateTime? _lastCheckpointTime;
  int _lastSavedContentLength = 0;
  int _lastSavedReasoningLength = 0;

  MessageSaveService? _saveService;
  bool _pendingTemporaryChat = false;
  String? _ephemeralConversationId;
  bool _attemptedResume = false;
  static const _lastActiveConversationKey = 'lastActiveConversationId';
  ChatStats? _streamStats;
  DateTime? _streamStartTime;
  DateTime? _firstTokenTime;
  bool _useFreshConversationSystemPrompt = false;
  String? _freshConversationSystemPrompt;

  String? get _activeConversationId =>
      _currentConversationId ?? _ephemeralConversationId;

  bool get _isInMemoryChat => state.isTemporary;

  void _resetStreamMetrics() {
    _streamStats = null;
    _streamStartTime = DateTime.now();
    _firstTokenTime = null;
  }

  void _noteFirstToken() {
    _firstTokenTime ??= DateTime.now();
  }

  Message _finalizeStreamMessage(Message msg, {String? stopReason}) {
    final stats = _streamStats;
    final start = _streamStartTime;
    final firstToken = _firstTokenTime;
    final now = DateTime.now();

    int? ttftMs;
    if (firstToken != null && start != null) {
      ttftMs = firstToken.difference(start).inMilliseconds;
    } else if (stats?.timeToFirstTokenSeconds != null) {
      ttftMs = (stats!.timeToFirstTokenSeconds! * 1000).round();
    }

    int? genMs;
    if (start != null) {
      genMs = now.difference(start).inMilliseconds;
    }

    double? tps = stats?.tokensPerSecond;
    final outputTokens = stats?.totalOutputTokens;
    if (tps == null && outputTokens != null && genMs != null && genMs > 0) {
      tps = outputTokens / (genMs / 1000);
    }

    return msg.copyWith(
      tokenCount: outputTokens ?? msg.tokenCount,
      inputTokenCount: stats?.inputTokens ?? msg.inputTokenCount,
      tokensPerSecond: tps ?? msg.tokensPerSecond,
      generationTimeMs: genMs ?? msg.generationTimeMs,
      ttftMs: ttftMs ?? msg.ttftMs,
      stopReason: stopReason ?? msg.stopReason,
    );
  }

  /// Updates the conversation's total token count from the most recent
  /// assistant message's own end-of-stream stats (`inputTokenCount` +
  /// `tokenCount`, populated from the server's real usage/stats payload) —
  /// this is exactly the size of the context window the model saw on its
  /// last turn, so it doubles as an accurate "context used" figure without
  /// ever issuing an extra request just to count tokens.
  void _recomputeConversationTotal(
    String conversationId, {
    List<Message>? messages,
  }) {
    final timeline = messages ?? state.messages;
    final lastWithStats = timeline.reversed
        .where(
          (m) =>
              m.role == MessageRole.assistant &&
              (m.inputTokenCount != null || m.tokenCount != null),
        )
        .firstOrNull;
    final total = lastWithStats == null
        ? 0
        : (lastWithStats.inputTokenCount ?? 0) + (lastWithStats.tokenCount ?? 0);
    unawaited(
      ref
          .read(conv.conversationsProvider.notifier)
          .updateTokenCount(conversationId, total),
    );
  }

  /// Syncs the history-list preview/message-count/char-count/token-total
  /// for [conversationId] after a generation finishes. Generation runs in
  /// the background even after the user switches to a different
  /// conversation, so this must never assume `state.messages` belongs to
  /// [conversationId] — when it isn't the conversation currently on screen,
  /// the active timeline is re-read from the database instead. Without
  /// this, a background reply could overwrite the *foreground* conversation's
  /// history preview with its own content.
  Future<void> _syncConversationStatsAfterGeneration(
    String conversationId,
    Message finalMessage, {
    required bool isCurrentContext,
  }) async {
    final timeline = isCurrentContext
        ? state.messages
        : MessageVariants.resolveActiveTimeline(
            await ref
                .read(databaseProvider)
                .store
                .runInTransactionAsync(
                  TxMode.read,
                  _loadMessagesInBackground,
                  conversationId,
                ),
          );

    final preview = finalMessage.content.length > 100
        ? '${finalMessage.content.substring(0, 100)}...'
        : finalMessage.content;
    final totalChars = timeline.fold<int>(
      0,
      (sum, message) => sum + message.content.length,
    );

    await ref
        .read(conv.conversationsProvider.notifier)
        .syncConversationStats(
          conversationId,
          messageCount: timeline.length,
          characterCount: totalChars,
          preview: preview,
        );
    _recomputeConversationTotal(conversationId, messages: timeline);

    if (isCurrentContext) {
      final lastUserMessage =
          timeline.where((m) => m.role == MessageRole.user).firstOrNull;
      if (lastUserMessage != null) {
        _maybeAutoGenerateTitleAfterFirstReply();
      }
    }
  }

  void approveTool(bool approved) {
    final pending = state.pendingToolApproval;
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.complete(approved);
    }
  }

  void _clearPendingApproval() {
    final pending = state.pendingToolApproval;
    if (pending != null) {
      if (!pending.completer.isCompleted) {
        pending.completer.complete(false);
      }
      state = state.copyWith(clearPendingApproval: true);
    }
  }

  @override
  ChatState build() {
    final db = ref.read(databaseProvider);
    _saveService = MessageSaveService(db);
    ref.onDispose(() {
      _uiUpdateTimer?.cancel();
      _invalidateStreamCallbacks();
      final subscription = _streamSubscription;
      _streamSubscription = null;
      subscription?.cancel();
      _saveService?.dispose();
      final pending = state.pendingToolApproval;
      if (pending != null && !pending.completer.isCompleted) {
        pending.completer.complete(false);
      }
    });
    if (!_attemptedResume) {
      _attemptedResume = true;
      Future.microtask(_tryResumeLastChat);
    }
    return const ChatState();
  }

  Future<void> _tryResumeLastChat() async {
    final settings = ref.read(settingsProvider);
    if (!settings.resumeLastChat) return;
    if (state.messages.isNotEmpty || _currentConversationId != null) return;

    final prefs = ref.read(sharedPreferencesProvider);
    final lastId = prefs.getString(_lastActiveConversationKey);
    if (lastId == null || lastId.isEmpty) return;

    try {
      final conversations = await ref.read(conv.conversationsProvider.future);
      Conversation? target;
      for (final conversation in conversations) {
        if (conversation.id == lastId && !conversation.isTemporary) {
          target = conversation;
          break;
        }
      }
      if (target != null) {
        await loadConversation(target);
      }
    } catch (e, st) {
      Log.error('Failed to resume last chat: $e\n$st');
    }
  }

  void _persistLastActiveConversation(String conversationId) {
    if (!ref.read(settingsProvider).resumeLastChat) return;
    ref
        .read(sharedPreferencesProvider)
        .setString(_lastActiveConversationKey, conversationId);
  }

  Future<void> loadConversation(Conversation conversation) async {
    await cancelStream();
    _currentConversationId = conversation.id;
    ref.read(smartReplyServiceProvider).reset();
    state = state.copyWith(
      isLoading: true,
      errorMessage: null,
      clearError: true,
    );

    try {
      final db = ref.read(databaseProvider);

      final messages = await db.store.runInTransactionAsync(
        TxMode.read,
        _loadMessagesInBackground,
        conversation.id,
      );

      state = ChatState(
        allMessages: messages,
        messages: MessageVariants.resolveActiveTimeline(messages),
        isLoading: false,
        isTemporary: conversation.isTemporary,
      );
      ref
          .read(conv.activeConversationProvider.notifier)
          .setActiveConversation(conversation);

      if (!conversation.isTemporary) {
        _persistLastActiveConversation(conversation.id);
      }

      ref
          .read(chatMcpConfigProvider.notifier)
          .setEnabled(conversation.mcpEnabled ?? true);
    } catch (e, stackTrace) {
      Log.fatal(error: e, stackTrace: stackTrace);
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load conversation: $e',
      );
    }
  }

  static List<Message> _loadMessagesInBackground(
    Store store,
    String conversationId,
  ) {
    final convBox = store.box<ConversationEntity>();
    final messageBox = store.box<MessageEntity>();

    final convQuery = convBox
        .query(ConversationEntity_.id.equals(conversationId))
        .build();
    final convEntity = convQuery.findFirst();
    convQuery.close();

    List<Message> messages = [];

    if (convEntity != null) {
      final relatedEntities = convEntity.messages;
      if (relatedEntities.isNotEmpty) {
        messages = relatedEntities.map((e) => e.toDomain()).toList();
      } else {
        final query = messageBox
            .query(MessageEntity_.conversationUid.equals(conversationId))
            .build();
        final manualEntities = query.find();
        query.close();

        if (manualEntities.isNotEmpty) {
          for (final e in manualEntities) {
            e.conversation.target = convEntity;
            messageBox.put(e);
          }
          messages = manualEntities.map((e) => e.toDomain()).toList();
        }
      }
    } else {
      final query = messageBox
          .query(MessageEntity_.conversationUid.equals(conversationId))
          .build();
      final entities = query.find();
      query.close();
      messages = entities.map((e) => e.toDomain()).toList();
    }

    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final normalized = messages
        .asMap()
        .entries
        .map((entry) {
          final msg = entry.value;
          if (msg.variantGroupId?.isNotEmpty == true) return msg;
          return msg.copyWith(
            variantGroupId: msg.id,
            variantIndex: 0,
            threadOrder: entry.key,
            isActiveVariant: true,
          );
        })
        .toList();
    return _assignLegacyParentsIfNeeded(normalized);
  }

  static List<Message> _assignLegacyParentsIfNeeded(List<Message> messages) {
    if (messages.any((m) => m.parentMessageId?.isNotEmpty == true)) {
      return messages;
    }
    final byThreadOrder = <int, List<Message>>{};
    for (final message in messages) {
      byThreadOrder.putIfAbsent(message.threadOrder, () => []).add(message);
    }
    final orders = byThreadOrder.keys.toList()..sort();
    String? previousActiveId;
    final updated = <Message>[];
    for (final order in orders) {
      final group = byThreadOrder[order]!;
      for (final message in group) {
        updated.add(message.copyWith(parentMessageId: previousActiveId));
      }
      final active = group.firstWhere(
        (m) => m.isActiveVariant,
        orElse: () => group.last,
      );
      previousActiveId = active.id;
    }
    return updated;
  }

  void _setAllMessages(List<Message> allMessages) {
    state = state.copyWith(
      allMessages: allMessages,
      messages: MessageVariants.resolveActiveTimeline(allMessages),
    );
  }

  Future<void> startNewConversation() async {
    await _abortStreamImmediately();

    _currentConversationId = null;
    _ephemeralConversationId = null;
    _pendingTemporaryChat = false;
    ref.read(smartReplyServiceProvider).reset();
    state = const ChatState();
    ref
        .read(conv.activeConversationProvider.notifier)
        .setActiveConversation(null);
    ref.read(chatOriginProvider.notifier).clear();
    ref.read(messageSelectionModeProvider.notifier).disable();

    final settings = ref.read(settingsProvider);
    ref
        .read(chatMcpConfigProvider.notifier)
        .setEnabled(settings.newChatMcpEnabled);
  }

  void _invalidateStreamCallbacks() {
    _streamGeneration++;
  }

  Future<void> _detachStreamSubscription() async {
    _invalidateStreamCallbacks();
    final subscription = _streamSubscription;
    _streamSubscription = null;
    if (subscription != null) {
      await subscription.cancel();
    }
  }

  Future<void> _abortStreamImmediately() async {
    await _detachStreamSubscription();
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = null;
    _clearPendingApproval();

    ref.read(chatServiceProvider)?.cancelStream();
    ref.read(chatBackgroundServiceProvider).stop();
    ref.read(isStreamingProvider.notifier).setStreaming(false);

    _chunkCount = 0;
    _lastCheckpointTime = null;
    _lastSavedContentLength = 0;
    _lastSavedReasoningLength = 0;

    final convId = _currentConversationId;
    final streamingMessage = _latestStreamingMessage ?? state.streamingMessage;
    _latestStreamingMessage = null;

    if (streamingMessage != null && convId != null) {
      unawaited(_persistCancelledMessageInBackground(streamingMessage, convId));
    }
  }

  Future<void> _persistCancelledMessageInBackground(
    Message streamingMessage,
    String conversationId,
  ) async {
    try {
      final finalMessage = _finalizeStreamMessage(
        streamingMessage.copyWith(
          conversationId: conversationId,
          status: MessageStatus.cancelled,
          isProcessing: false,
        ),
        stopReason: 'cancelled',
      );
      await _saveService?.flush();
      await _saveMessage(finalMessage);
    } catch (e) {
      Log.error('Failed to persist cancelled stream message: $e');
    }
  }

  void setTemporaryMode(bool enabled) {
    if (state.messages.isNotEmpty && enabled != state.isTemporary) return;
    _pendingTemporaryChat = enabled;
    state = state.copyWith(isTemporary: enabled);
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

  bool _shouldCheckpointSave(Message message) {
    final now = DateTime.now();
    final contentLength = message.content.length;
    final reasoningLength = message.reasoningContent?.length ?? 0;

    final hasNewContent =
        contentLength > _lastSavedContentLength ||
        reasoningLength > _lastSavedReasoningLength;

    if (!hasNewContent) return false;

    final meetsChunkThreshold = _chunkCount >= _checkpointChunkThreshold;

    final meetsTimeThreshold =
        _lastCheckpointTime != null &&
        now.difference(_lastCheckpointTime!) >= _checkpointTimeThreshold;

    return meetsChunkThreshold || meetsTimeThreshold;
  }

  void _resetCheckpointMetrics() {
    _chunkCount = 0;
    _lastCheckpointTime = DateTime.now();
  }

  void _updateSavedMetrics(Message message) {
    _lastSavedContentLength = message.content.length;
    _lastSavedReasoningLength = message.reasoningContent?.length ?? 0;
  }

  Future<void> checkpointStreamingMessage({bool flush = false}) async {
    if (_isInMemoryChat) return;
    final latest = _latestStreamingMessage ?? state.streamingMessage;
    if (latest == null) return;

    _saveService?.enqueue(latest);
    _updateSavedMetrics(latest);
    _resetCheckpointMetrics();

    if (flush) {
      await _saveService?.flush();
    }
  }

  void _replaceMessageInState(Message message, {bool clearStreaming = false}) {
    _replaceMessageInAll(message, clearStreaming: clearStreaming);
  }

  /// Creates a new conversation (or ephemeral in-memory chat) if one isn't
  /// already active, mirroring the same persona/title/MCP setup [sendMessage]
  /// has always done on the first message of a chat. Shared with
  /// [insertMessageWithoutGenerating] so manually-inserted messages can also
  /// start a brand new conversation.
  Future<void> _ensureConversationExists(String titleSource) async {
    if (_currentConversationId != null || _ephemeralConversationId != null) {
      return;
    }

    final server = ref.read(activeServerProvider);
    final selectedModel = ref.read(selectedModelProvider);
    final settings = ref.read(settingsProvider);
    if (server == null) return;

    final isTemp = state.isTemporary || _pendingTemporaryChat;
    if (isTemp) {
      _ephemeralConversationId = generateUuid();
      _pendingTemporaryChat = false;
      state = state.copyWith(isTemporary: true);
      return;
    }

    final titleService = ref.read(titleGenerationServiceProvider);
    final initialTitle = settings.autoGenerateTitle
        ? 'New Chat'
        : titleService.truncateFirstMessageTitle(titleSource);
    final preselected = ref.read(selectedPersonasProvider);
    final newConversationSystemPrompt = preselected.isEmpty
        ? null
        : PersonaPromptUtils.combineSystemPrompts(preselected);
    final conversation = await ref
        .read(conv.conversationsProvider.notifier)
        .createConversation(
          title: initialTitle,
          serverId: server.id,
          modelId: selectedModel?.id,
          personaId: preselected.isEmpty
              ? null
              : PersonaPromptUtils.joinPersonaIds(
                  preselected.map((p) => p.id).toList(),
                ),
          systemPrompt: newConversationSystemPrompt,
          mcpEnabled: settings.newChatMcpEnabled,
          isTemporary: false,
          folderId: ref.read(pendingNewChatFolderIdProvider.notifier).consume(),
        );
    _currentConversationId = conversation.id;
    ref
        .read(conv.activeConversationProvider.notifier)
        .setActiveConversation(conversation);
    _persistLastActiveConversation(conversation.id);
    // A conversationsProvider refresh triggered later in this same send
    // (e.g. syncConversationStats) rebuilds activeConversationProvider
    // from the reloaded list; use this captured value for this send so
    // the persona system prompt is never missed on the very first
    // message of a brand new conversation.
    _useFreshConversationSystemPrompt = true;
    _freshConversationSystemPrompt = newConversationSystemPrompt;

    ref.read(chatMcpConfigProvider.notifier).setEnabled(settings.newChatMcpEnabled);

    if (!settings.keepPersonaOnNewChat) {
      ref.read(selectedPersonasProvider.notifier).clear();
    }
  }

  Future<void> sendMessage(String content, {List<File>? attachments}) async {
    final server = ref.read(activeServerProvider);
    final selectedModel = ref.read(selectedModelProvider);
    final chatService = ref.read(chatServiceProvider);

    if (server == null) {
      state = state.copyWith(errorMessage: 'No server connected');
      return;
    }

    if (content.trim().isEmpty &&
        (attachments == null || attachments.isEmpty)) {
      return;
    }

    final trimmedContent = content.trim();

    final titleSource = trimmedContent.isNotEmpty
        ? trimmedContent
        : (attachments?.isNotEmpty == true
            ? attachments!.first.path.split(Platform.pathSeparator).last
            : 'New Chat');
    await _ensureConversationExists(titleSource);

    // Read after the conversation (and its persona system prompt) is
    // created above — chatParamsProvider derives systemPrompt from
    // activeConversationProvider, which doesn't have it yet if read at the
    // top of this function, causing the very first message's request to
    // go out with no persona system prompt.
    final chatParams = ref.read(chatParamsProvider);

    final convId = _activeConversationId;
    if (convId == null) return;

    final List<String> savedPaths = [];
    if (attachments != null && attachments.isNotEmpty) {
      final appDir = await ref.read(storageDirectoryProvider.future);
      final attachmentsDir = Directory('${appDir.path}/attachments');
      if (!await attachmentsDir.exists()) {
        await attachmentsDir.create(recursive: true);
      }

      for (final file in attachments) {
        final savedPath =
            await AttachmentHelpers.saveAttachment(file, attachmentsDir);
        if (savedPath != null) savedPaths.add(savedPath);
      }
    }

    final userThreadOrder = MessageVariants.nextThreadOrder(state.messages);
    final userGroupId = generateUuid();
    final assistantThreadOrder = userThreadOrder + 1;
    final assistantGroupId = generateUuid();
    final lastInTimeline = state.messages.isNotEmpty ? state.messages.last : null;

    final userMessage = Message(
      id: generateUuid(),
      conversationId: convId,
      role: MessageRole.user,
      content: trimmedContent,
      createdAt: DateTime.now(),
      status: MessageStatus.complete,
      attachmentPaths: savedPaths.isNotEmpty ? savedPaths : null,
      variantGroupId: userGroupId,
      variantIndex: 0,
      threadOrder: userThreadOrder,
      isActiveVariant: true,
      parentMessageId: lastInTimeline?.id,
    );

    final assistantMessageId = generateUuid();
    var assistantMessage = Message(
      id: assistantMessageId,
      conversationId: convId,
      role: MessageRole.assistant,
      content: '',
      createdAt: DateTime.now(),
      status: MessageStatus.streaming,
      modelId: selectedModel?.id,
      variantGroupId: assistantGroupId,
      variantIndex: 0,
      threadOrder: assistantThreadOrder,
      isActiveVariant: true,
      parentMessageId: userMessage.id,
    );

    final updatedAll = [...state.allMessages, userMessage, assistantMessage];
    state = state.copyWith(
      allMessages: updatedAll,
      messages: MessageVariants.resolveActiveTimeline(updatedAll),
      isStreaming: true,
      streamingMessage: assistantMessage,
      clearError: true,
    );
    ref.read(isStreamingProvider.notifier).setStreaming(true);

    await _saveMessage(userMessage);
    await _saveMessage(assistantMessage);

    if (!_isInMemoryChat && _currentConversationId != null) {
      final preview = trimmedContent.isNotEmpty
          ? (trimmedContent.length > 100
              ? '${trimmedContent.substring(0, 100)}...'
              : trimmedContent)
          : (attachments?.isNotEmpty == true ? '[attachment]' : 'New message');
      final timeline = [...state.messages, userMessage];
      await ref.read(conv.conversationsProvider.notifier).syncConversationStats(
            _currentConversationId!,
            messageCount: timeline.length,
            characterCount: timeline.fold<int>(
              0,
              (sum, message) => sum + message.content.length,
            ),
            preview: preview,
          );
    }

    ref.read(chatBackgroundServiceProvider).start();

    _resetStreamMetrics();
    _resetCheckpointMetrics();
    _updateSavedMetrics(assistantMessage);

    final messagesForApi = _buildMessagesForApi(selectedModel);

    try {
      await _detachStreamSubscription();
      _uiUpdateTimer?.cancel();

      String reasoningContent = '';
      var streamingAssistantMessage = assistantMessage;
      _latestStreamingMessage = streamingAssistantMessage;

      if (chatService != null) {
        final mcpConfig = ref.read(chatMcpConfigProvider);
        final integrations =
            mcpConfig.enabled && mcpConfig.integrations.isNotEmpty
            ? mcpConfig.integrations
            : null;

        final registry = ref.read(toolRegistryProvider);
        final tools = mcpConfig.enabled
            ? await registry.listTools()
            : const <ToolDefinition>[];

        final collectedToolCalls = <ToolCallData>[];

        bool stateNeedsUpdate = false;

        void updateUiState() {
          if (!stateNeedsUpdate) return;
          stateNeedsUpdate = false;

          final streamConvId = assistantMessage.conversationId;
          final isCurrentContext = _currentConversationId == streamConvId;

          if (isCurrentContext) {
            state = state.copyWith(streamingMessage: streamingAssistantMessage);
          }
        }

        _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
          updateUiState();
        });

        final streamGeneration = _streamGeneration;
        _streamSubscription = chatService
            .sendMessage(
              server: server,
              modelId: selectedModel?.id ?? 'default',
              messages: messagesForApi,
              params: chatParams,
              integrations: integrations,
              tools: tools,
            )
            .listen(
              (response) async {
                if (streamGeneration != _streamGeneration) return;
                final streamConvId = assistantMessage.conversationId;
                final isCurrentContext = _currentConversationId == streamConvId;

                switch (response.type) {
                  case ChatResponseType.message:
                    if (response.content?.isNotEmpty ?? false) {
                      _noteFirstToken();
                    }
                    streamingAssistantMessage = streamingAssistantMessage
                        .copyWith(
                          content:
                              streamingAssistantMessage.content +
                              (response.content ?? ''),
                          isProcessing: false,
                        );
                    _latestStreamingMessage = streamingAssistantMessage;

                    _chunkCount++;

                    if (!_isInMemoryChat &&
                        _shouldCheckpointSave(streamingAssistantMessage)) {
                      _saveService?.enqueue(streamingAssistantMessage);
                      _updateSavedMetrics(streamingAssistantMessage);
                      _resetCheckpointMetrics();
                    }

                    stateNeedsUpdate = true;
                    break;
                  case ChatResponseType.reasoning:
                    if (response.reasoningContent?.isNotEmpty ?? false) {
                      _noteFirstToken();
                    }
                    reasoningContent += response.reasoningContent ?? '';
                    streamingAssistantMessage = streamingAssistantMessage
                        .copyWith(
                          reasoningContent: reasoningContent,
                          isProcessing: false,
                        );
                    _latestStreamingMessage = streamingAssistantMessage;

                    _chunkCount++;

                    if (!_isInMemoryChat &&
                        _shouldCheckpointSave(streamingAssistantMessage)) {
                      _saveService?.enqueue(streamingAssistantMessage);
                      _updateSavedMetrics(streamingAssistantMessage);
                      _resetCheckpointMetrics();
                    }

                    stateNeedsUpdate = true;
                    break;
                  case ChatResponseType.processing:
                    streamingAssistantMessage = streamingAssistantMessage
                        .copyWith(isProcessing: true);
                    _latestStreamingMessage = streamingAssistantMessage;
                    stateNeedsUpdate = true;
                    break;
                  case ChatResponseType.timeoutError:
                  case ChatResponseType.error:
                    _uiUpdateTimer?.cancel();
                    _uiUpdateTimer = null;
                    streamingAssistantMessage = streamingAssistantMessage.copyWith(
                      status: MessageStatus.error,
                      errorMessage:
                          response.content ??
                          (response.type == ChatResponseType.timeoutError
                              ? 'Model is taking too long to respond. This may happen with free tier models.'
                              : 'An unknown error occurred.'),
                      isProcessing: false,
                    );
                    _latestStreamingMessage = streamingAssistantMessage;

                    if (isCurrentContext) {
                      _replaceMessageInState(
                        streamingAssistantMessage,
                        clearStreaming: true,
                      );
                      state = state.copyWith(
                        isStreaming: false,
                        errorMessage: streamingAssistantMessage.errorMessage,
                      );
                    }
                    ref.read(isStreamingProvider.notifier).setStreaming(false);
                    _latestStreamingMessage = null;
                    await _saveService?.flush();
                    await _saveMessage(streamingAssistantMessage);
                    break;
                  case ChatResponseType.toolCall:
                    if (response.toolCall != null) {
                      collectedToolCalls.add(response.toolCall!);
                    }
                    break;
                  case ChatResponseType.invalidToolCall:
                  case ChatResponseType.done:
                    if (response.stats != null) {
                      _streamStats = response.stats;
                    }
                    break;
                }
              },
              onDone: () async {
              _uiUpdateTimer?.cancel();
              _uiUpdateTimer = null;
              updateUiState();

              if (!_isInMemoryChat) {
                await _saveService?.flush();
              }
              ref.read(chatBackgroundServiceProvider).stop();
              final streamConvId = assistantMessage.conversationId;
              final isCurrentContext = _activeConversationId == streamConvId;
                final streamingMessage = streamingAssistantMessage;
                final hasContent =
                    streamingMessage.content.isNotEmpty ||
                    (streamingMessage.reasoningContent?.isNotEmpty ??
                        false) ||
                    collectedToolCalls.isNotEmpty;

                if (!hasContent) {
                  final errorMessage = streamingMessage.copyWith(
                    status: MessageStatus.error,
                    errorMessage:
                        'Model failed to respond. This may happen with free tier models that refuse certain prompts or when the service is busy.',
                    isProcessing: false,
                  );
                  await _saveMessage(errorMessage);
                  if (isCurrentContext) {
                    _replaceMessageInState(
                      errorMessage,
                      clearStreaming: true,
                    );
                    state = state.copyWith(
                      isStreaming: false,
                      errorMessage: errorMessage.errorMessage,
                    );
                  }
                  ref.read(isStreamingProvider.notifier).setStreaming(false);
                  _latestStreamingMessage = null;
                } else {
                  var finalMessage = _finalizeStreamMessage(
                    streamingMessage.copyWith(
                      status: MessageStatus.complete,
                      isProcessing: false,
                    ),
                    stopReason: 'complete',
                  );

                  if (mcpConfig.enabled && collectedToolCalls.isNotEmpty) {
                    try {
                      final registry = ref.read(toolRegistryProvider);
                      final adapter = createAdapterForServerType(server.type);

                      final dedupedCalls = <String, ToolCallData>{};
                      for (final tc in collectedToolCalls) {
                        dedupedCalls[tc.tool] = tc;
                      }

                      final preParsedCalls = dedupedCalls.values
                          .map(
                            (tc) => ParsedToolCall(
                              id: tc.tool,
                              name: tc.tool,
                              arguments: tc.arguments,
                            ),
                          )
                          .toList();

                      final loop = ToolExecutionLoop(
                        adapter: adapter,
                        registry: registry,
                        onRequestApproval: (call) async {
                          final completer = Completer<bool>();
                          state = state.copyWith(
                            pendingToolApproval: PendingToolApproval(
                              toolCall: call,
                              completer: completer,
                            ),
                          );

                          final result = await completer.future;

                          state = state.copyWith(clearPendingApproval: true);

                          return result;
                        },
                      );

                      final loopResult = await loop.run(
                        initialUserMessage: content,
                        assistantContent: streamingAssistantMessage.content,
                        preParsedCalls: preParsedCalls,
                      );

                      if (loopResult.events.isNotEmpty) {
                        finalMessage = finalMessage.copyWith(
                          toolSessionId: loop.sessionId,
                          toolEvents: loopResult.events,
                        );
                      }
                    } catch (e) {
                      Log.error('Tool execution loop failed: $e');
                    }
                  }

                  await _saveMessage(finalMessage);
                  if (isCurrentContext) {
                    _replaceMessageInState(
                      finalMessage,
                      clearStreaming: true,
                    );
                    state = state.copyWith(isStreaming: false);
                  }
                  ref.read(isStreamingProvider.notifier).setStreaming(false);
                  _latestStreamingMessage = null;

                  await _syncConversationStatsAfterGeneration(
                    streamConvId,
                    finalMessage,
                    isCurrentContext: isCurrentContext,
                  );

                  _maybeRequestReviewAfterSuccessfulCompletion(
                    finalMessage: finalMessage,
                    server: server,
                    selectedModel: selectedModel,
                  );

                  _chunkCount = 0;
                  _lastCheckpointTime = null;
                  _lastSavedContentLength = 0;
                  _lastSavedReasoningLength = 0;
                }
              },
              onError: (error) async {
                _uiUpdateTimer?.cancel();
                _uiUpdateTimer = null;
                _chunkCount = 0;
                _lastCheckpointTime = null;
                _lastSavedContentLength = 0;
                _lastSavedReasoningLength = 0;
                await _saveService?.flush();
                final errorMessage =
                    (_latestStreamingMessage ?? state.streamingMessage)
                        ?.copyWith(
                          status: MessageStatus.error,
                          errorMessage: error.toString(),
                        );
                if (errorMessage != null) {
                  await _saveMessage(errorMessage);

                  ref.read(chatBackgroundServiceProvider).stop();

                  final streamConvId = assistantMessage.conversationId;
                  if (_currentConversationId == streamConvId) {
                    _replaceMessageInState(errorMessage, clearStreaming: true);
                    state = state.copyWith(
                      isStreaming: false,
                      errorMessage: error.toString(),
                    );
                  }
                }
                ref.read(isStreamingProvider.notifier).setStreaming(false);
                _latestStreamingMessage = null;
              },
            );
      }
    } catch (e) {
      _uiUpdateTimer?.cancel();
      _uiUpdateTimer = null;
      final errorMsg = assistantMessage.copyWith(
        status: MessageStatus.error,
        errorMessage: e.toString(),
        isProcessing: false,
      );
      await _saveMessage(errorMsg);

      state = state.copyWith(
        isStreaming: false,
        errorMessage: e.toString(),
        clearStreaming: true,
      );
      ref.read(isStreamingProvider.notifier).setStreaming(false);
      _latestStreamingMessage = null;
      ref.read(chatBackgroundServiceProvider).stop();
    }
  }

  /// Inserts [content] as a message with the given [role] without calling
  /// the chat service or starting generation. Used by the send button's
  /// long-press ("insert without generating") and the role-swap button
  /// (which lets the user manually author an assistant-role turn).
  Future<void> insertMessageWithoutGenerating(
    String content, {
    required MessageRole role,
    List<File>? attachments,
  }) async {
    final server = ref.read(activeServerProvider);
    if (server == null) {
      state = state.copyWith(errorMessage: 'No server connected');
      return;
    }

    final trimmedContent = content.trim();
    if (trimmedContent.isEmpty && (attachments == null || attachments.isEmpty)) {
      return;
    }

    final titleSource = trimmedContent.isNotEmpty
        ? trimmedContent
        : (attachments?.isNotEmpty == true
            ? attachments!.first.path.split(Platform.pathSeparator).last
            : 'New Chat');
    await _ensureConversationExists(titleSource);

    final convId = _activeConversationId;
    if (convId == null) return;

    final List<String> savedPaths = [];
    if (attachments != null && attachments.isNotEmpty) {
      final appDir = await ref.read(storageDirectoryProvider.future);
      final attachmentsDir = Directory('${appDir.path}/attachments');
      if (!await attachmentsDir.exists()) {
        await attachmentsDir.create(recursive: true);
      }

      for (final file in attachments) {
        final savedPath =
            await AttachmentHelpers.saveAttachment(file, attachmentsDir);
        if (savedPath != null) savedPaths.add(savedPath);
      }
    }

    final threadOrder = MessageVariants.nextThreadOrder(state.messages);
    final groupId = generateUuid();
    final lastInTimeline = state.messages.isNotEmpty ? state.messages.last : null;

    final message = Message(
      id: generateUuid(),
      conversationId: convId,
      role: role,
      content: trimmedContent,
      createdAt: DateTime.now(),
      status: MessageStatus.complete,
      attachmentPaths: savedPaths.isNotEmpty ? savedPaths : null,
      variantGroupId: groupId,
      variantIndex: 0,
      threadOrder: threadOrder,
      isActiveVariant: true,
      parentMessageId: lastInTimeline?.id,
    );

    final updatedAll = [...state.allMessages, message];
    state = state.copyWith(
      allMessages: updatedAll,
      messages: MessageVariants.resolveActiveTimeline(updatedAll),
      clearError: true,
    );

    await _saveMessage(message);

    if (!_isInMemoryChat && _currentConversationId != null) {
      final preview = trimmedContent.isNotEmpty
          ? (trimmedContent.length > 100
              ? '${trimmedContent.substring(0, 100)}...'
              : trimmedContent)
          : (attachments?.isNotEmpty == true ? '[attachment]' : 'New message');
      final timeline = state.messages;
      await ref.read(conv.conversationsProvider.notifier).syncConversationStats(
            _currentConversationId!,
            messageCount: timeline.length,
            characterCount: timeline.fold<int>(
              0,
              (sum, message) => sum + message.content.length,
            ),
            preview: preview,
          );
    }
  }

  List<Message> _buildMessagesForApi(ModelInfo? selectedModel) {
    final settings = ref.read(settingsProvider);
    final messages = <Message>[];

    final reasoningConfig = ref.read(chatReasoningConfigProvider);
    final shouldDisableThinking =
        (selectedModel?.supportsReasoning ?? false) && !reasoningConfig.enabled;

    final personaPrompt = _getPersonaSystemPrompt();
    var systemContent = personaPrompt ??
        (settings.showSystemMessages
            ? 'You are LocalMind, a helpful AI assistant. Provide clear, accurate, and concise responses.'
            : null);

    if (shouldDisableThinking) {
      // Hybrid reasoning models (Qwen3 and similar) key off this literal
      // token in the prompt to skip their <think> block — send it whenever
      // the model supports reasoning and the user has switched Think off,
      // alongside the request-level reasoning-disable fields.
      systemContent = (systemContent == null || systemContent.trim().isEmpty)
          ? '/no_think'
          : '$systemContent\n/no_think';
    }

    if (systemContent != null) {
      messages.add(
        Message(
          id: 'system-$_currentConversationId',
          conversationId: _currentConversationId ?? '',
          role: MessageRole.system,
          content: systemContent,
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

  List<Message> _buildMessagesForContinue(
    ModelInfo? selectedModel,
    Message assistantMessage,
  ) {
    final messages = _buildMessagesForApi(selectedModel);
    if (messages.isEmpty) return messages;
    if (messages.last.role != MessageRole.assistant) return messages;

    messages[messages.length - 1] = assistantMessage.copyWith(
      status: MessageStatus.complete,
      isProcessing: false,
    );
    return messages;
  }

  String? _getPersonaSystemPrompt() {
    if (_useFreshConversationSystemPrompt) {
      _useFreshConversationSystemPrompt = false;
      final override = _freshConversationSystemPrompt;
      _freshConversationSystemPrompt = null;
      if (override != null && override.trim().isNotEmpty) return override;
    }

    final conversation = ref.read(conv.activeConversationProvider);
    if (conversation?.systemPrompt != null &&
        conversation!.systemPrompt!.trim().isNotEmpty) {
      return conversation.systemPrompt;
    }

    final personaIds = conversation?.personaId;
    if (personaIds == null || personaIds.isEmpty) return null;

    try {
      final personas = ref.read(personasNotifierProvider).value ?? [];
      final selected =
          PersonaPromptUtils.resolvePersonas(personaIds, personas);
      if (selected.isEmpty) return null;
      return PersonaPromptUtils.combineSystemPrompts(selected);
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

  void _maybeAutoGenerateTitleAfterFirstReply() {
    if (_currentConversationId == null || _isInMemoryChat) return;

    final settings = ref.read(settingsProvider);
    if (!settings.autoGenerateTitle) return;

    final activeConv = ref.read(conv.activeConversationProvider);
    if (activeConv == null || activeConv.title != 'New Chat') return;

    final assistantCount = state.messages
        .where((m) => m.role == MessageRole.assistant)
        .length;
    if (assistantCount != 1) return;

    unawaited(_generateAndApplyTitle(_currentConversationId!));
  }

  Future<void> _generateAndApplyTitle(String conversationId) async {
    final title = await generateTitleWithAi(conversationId);
    if (title == null || title.isEmpty || title == 'New Chat') return;

    await ref
        .read(conv.conversationsProvider.notifier)
        .renameConversation(conversationId, title);
  }

  Future<String?> generateTitleWithAi(String conversationId) async {
    final messages = await _loadMessagesForConversation(conversationId);
    if (messages.isEmpty) return null;

    final timeline = MessageVariants.resolveActiveTimeline(messages);
    if (timeline.isEmpty) return null;

    final conversation = ref
        .read(conv.conversationsProvider)
        .value
        ?.where((c) => c.id == conversationId)
        .firstOrNull;

    final server = _resolveServerForTitle(conversation);
    final modelId = _resolveModelIdForTitle(conversation);
    final titleService = ref.read(titleGenerationServiceProvider);

    if (server == null || modelId == null) {
      return _fallbackTitleFromMessages(timeline, titleService);
    }

    final chatService = _resolveChatServiceForTitle(server);
    if (chatService == null) {
      return _fallbackTitleFromMessages(timeline, titleService);
    }

    final generated = await titleService.generateTitleWithLLM(
      chatService: chatService,
      server: server,
      modelId: modelId,
      messages: timeline,
      params: ref.read(chatParamsProvider),
    );

    if (generated != null && generated.isNotEmpty) {
      return generated;
    }
    return _fallbackTitleFromMessages(timeline, titleService);
  }

  Future<List<Message>> _loadMessagesForConversation(
    String conversationId,
  ) async {
    if (_currentConversationId == conversationId && state.allMessages.isNotEmpty) {
      return MessageVariants.resolveActiveTimeline(state.allMessages);
    }

    final db = ref.read(databaseProvider);
    final loaded = await db.store.runInTransactionAsync(
      TxMode.read,
      _loadMessagesInBackground,
      conversationId,
    );
    return MessageVariants.resolveActiveTimeline(loaded);
  }

  Server? _resolveServerForTitle(Conversation? conversation) {
    if (conversation?.serverId != null) {
      final servers = ref.read(serversProvider).value ?? [];
      for (final server in servers) {
        if (server.id == conversation!.serverId) {
          return server;
        }
      }
    }
    return ref.read(activeServerProvider);
  }

  String? _resolveModelIdForTitle(Conversation? conversation) {
    return conversation?.modelId ?? ref.read(selectedModelProvider)?.id;
  }

  ChatService? _resolveChatServiceForTitle(Server server) {
    final active = ref.read(activeServerProvider);
    if (active?.id == server.id) {
      return ref.read(chatServiceProvider);
    }

    return createChatServiceForServer(
      server: server,
      dio: ref.read(dioProvider),
      onDeviceGemmaService: ref.read(onDeviceGemmaServiceProvider),
      onDeviceLlamaService: ref.read(onDeviceLlamaServiceProvider),
      loadedOnDeviceRuntime: ref.read(
        onDeviceEngineProvider.select((s) => s.loadedRuntime),
      ),
    );
  }

  String _fallbackTitleFromMessages(
    List<Message> messages,
    TitleGenerationService titleService,
  ) {
    final userMessage = messages
        .where((m) => m.role == MessageRole.user)
        .firstOrNull;
    if (userMessage == null || userMessage.content.trim().isEmpty) {
      return 'New Chat';
    }
    return titleService.truncateFirstMessageTitle(userMessage.content);
  }

  void _maybeRequestReviewAfterSuccessfulCompletion({
    required Message finalMessage,
    required Server server,
    required ModelInfo? selectedModel,
  }) {
    final modelId =
        selectedModel?.id ??
        (server.type == ServerType.onDevice
            ? ref.read(onDeviceEngineProvider).loadedModelId
            : null);

    unawaited(
      ref
          .read(reviewPromptServiceProvider)
          .maybeRequestReviewAfterSuccessfulChat(
            assistantContent: finalMessage.content,
            serverType: server.type,
            modelId: modelId,
            usedCustomPersona: _isUsingCustomPersona(),
          )
          .catchError((Object error, StackTrace stackTrace) {
            Log.error('Review prompt request failed: $error');
            return false;
          }),
    );
  }

  bool _isUsingCustomPersona() {
    final activeConversation = ref.read(conv.activeConversationProvider);
    final personaId = activeConversation?.personaId;
    if (personaId == null) return false;

    final personas = ref.read(personasNotifierProvider).value ?? [];
    return personas.any(
      (persona) => persona.id == personaId && !persona.isBuiltIn,
    );
  }

  Future<void> cancelStream() async {
    await _detachStreamSubscription();
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = null;
    _clearPendingApproval();
    ref.read(chatServiceProvider)?.cancelStream();
    ref.read(chatBackgroundServiceProvider).stop();

    _chunkCount = 0;
    _lastCheckpointTime = null;
    _lastSavedContentLength = 0;
    _lastSavedReasoningLength = 0;

    await _saveService?.flush();

    final streamingMessage = _latestStreamingMessage ?? state.streamingMessage;
    if (streamingMessage != null) {
      final finalMessage = _finalizeStreamMessage(
        streamingMessage.copyWith(
          status: MessageStatus.cancelled,
          isProcessing: false,
        ),
        stopReason: 'cancelled',
      );
      await _saveMessage(finalMessage);
      _replaceMessageInState(finalMessage, clearStreaming: true);
    }

    state = state.copyWith(isStreaming: false, clearStreaming: true);
    ref.read(isStreamingProvider.notifier).setStreaming(false);
    _latestStreamingMessage = null;
  }

  Future<void> retryLastMessage() async {
    final messages = state.messages;
    if (messages.isEmpty) return;

    final lastAssistantIndex = messages.lastIndexWhere(
      (m) => m.role == MessageRole.assistant,
    );
    if (lastAssistantIndex < 0) return;

    Message? userMessage;
    for (var i = lastAssistantIndex - 1; i >= 0; i--) {
      if (messages[i].role == MessageRole.user) {
        userMessage = messages[i];
        break;
      }
    }
    if (userMessage == null) return;

    final userMessageIndex = messages.indexWhere((m) => m.id == userMessage!.id);
    final messagesToRemove = messages.sublist(userMessageIndex);
    final db = ref.read(databaseProvider);

    for (final msg in messagesToRemove) {
      final query = db.messageBox
          .query(MessageEntity_.id.equals(msg.id))
          .build();
      db.messageBox.removeMany(query.findIds());
      query.close();
    }

    state = state.copyWith(
      messages: messages.sublist(0, userMessageIndex),
      clearStreaming: true,
    );

    await sendMessage(
      userMessage.content,
      attachments: userMessage.attachmentPaths
          ?.map((p) => File(p))
          .toList(),
    );
  }

  Future<void> continueFromMessage(String messageId) async {
    final messages = state.messages;
    if (messages.isEmpty || messages.last.id != messageId) return;
    final assistant = messages.last;
    if (assistant.role != MessageRole.assistant) return;
    if (state.isStreaming) return;

    final streamingAssistant = assistant.copyWith(
      status: MessageStatus.streaming,
      isProcessing: true,
    );
    _replaceMessageInAll(streamingAssistant);
    state = state.copyWith(
      isStreaming: true,
      streamingMessage: streamingAssistant,
      clearError: true,
    );
    ref.read(isStreamingProvider.notifier).setStreaming(true);
    ref.read(chatBackgroundServiceProvider).start();
    _resetCheckpointMetrics();
    _updateSavedMetrics(streamingAssistant);
    _latestStreamingMessage = streamingAssistant;

    await _runAssistantStream(
      streamingAssistant,
      ref.read(selectedModelProvider),
      continueGeneration: true,
    );
  }

  Future<void> cycleMessageVariant(String messageId, int direction) async {
    Message? displayMsg;
    for (final m in state.messages) {
      if (m.id == messageId) {
        displayMsg = m;
        break;
      }
    }
    if (displayMsg == null) return;

    final variants = MessageVariants.variantsForMessage(
      state.allMessages,
      displayMsg,
    );
    if (variants.length <= 1) return;

    final currentIndex = MessageVariants.activeVariantIndex(variants);
    final newIndex = (currentIndex + direction).clamp(0, variants.length - 1);
    if (newIndex == currentIndex) return;

    final groupId = MessageVariants.groupId(displayMsg);
    final targetId = variants[newIndex].id;
    final updatedAll = state.allMessages.map((message) {
      if (MessageVariants.groupId(message) != groupId) return message;
      return message.copyWith(isActiveVariant: message.id == targetId);
    }).toList();

    for (final message in updatedAll.where(
      (m) => MessageVariants.groupId(m) == groupId,
    )) {
      await _saveMessage(message);
    }
    _setAllMessages(updatedAll);
  }

  int _nextVariantIndex(String groupId) {
    final variants = state.allMessages.where(
      (m) => MessageVariants.groupId(m) == groupId,
    );
    if (variants.isEmpty) return 0;
    return variants
            .map((m) => m.variantIndex)
            .reduce((a, b) => a > b ? a : b) +
        1;
  }

  Future<void> retryMessage(String messageId) async {
    final messageIndex = state.messages.indexWhere((m) => m.id == messageId);
    if (messageIndex == -1) return;

    final message = state.messages[messageIndex];
    if (message.role != MessageRole.assistant) return;

    if (messageIndex > 0 &&
        state.messages[messageIndex - 1].role == MessageRole.user) {
      final userMessage = state.messages[messageIndex - 1];
      final groupId = MessageVariants.groupId(message);

      final deactivated = state.allMessages.map((m) {
        if (MessageVariants.groupId(m) != groupId) return m;
        return m.copyWith(isActiveVariant: false);
      }).toList();
      for (final m in deactivated.where(
        (x) => MessageVariants.groupId(x) == groupId,
      )) {
        await _saveMessage(m);
      }
      state = state.copyWith(allMessages: deactivated);

      await _regenerateAssistant(
        userMessage,
        variantGroupId: groupId,
        threadOrder: message.threadOrder,
        variantIndex: _nextVariantIndex(groupId),
      );
    }
  }

  Future<void> _regenerateAssistant(
    Message userMessage, {
    required String variantGroupId,
    required int threadOrder,
    required int variantIndex,
  }) async {
    final selectedModel = ref.read(selectedModelProvider);
    final server = ref.read(activeServerProvider);
    if (server == null || _activeConversationId == null) return;

    final assistantMessage = Message(
      id: generateUuid(),
      conversationId: _activeConversationId!,
      role: MessageRole.assistant,
      content: '',
      createdAt: DateTime.now(),
      status: MessageStatus.streaming,
      modelId: selectedModel?.id,
      variantGroupId: variantGroupId,
      variantIndex: variantIndex,
      threadOrder: threadOrder,
      isActiveVariant: true,
      parentMessageId: userMessage.id,
    );

    final updatedAll = [...state.allMessages, assistantMessage];
    state = state.copyWith(
      allMessages: updatedAll,
      messages: MessageVariants.resolveActiveTimeline(updatedAll),
      isStreaming: true,
      streamingMessage: assistantMessage,
      clearError: true,
    );
    ref.read(isStreamingProvider.notifier).setStreaming(true);
    await _saveMessage(assistantMessage);

    ref.read(chatBackgroundServiceProvider).start();
    _resetCheckpointMetrics();
    _updateSavedMetrics(assistantMessage);

    await _runAssistantStream(assistantMessage, selectedModel);
  }

  Future<void> _runAssistantStream(
    Message assistantMessage,
    ModelInfo? selectedModel, {
    bool continueGeneration = false,
  }) async {
    final server = ref.read(activeServerProvider);
    final chatParams = ref.read(chatParamsProvider);
    final chatService = ref.read(chatServiceProvider);
    if (server == null || chatService == null) return;

    final messagesForApi = continueGeneration
        ? _buildMessagesForContinue(selectedModel, assistantMessage)
        : _buildMessagesForApi(selectedModel);

    try {
      await _detachStreamSubscription();
      _uiUpdateTimer?.cancel();
      _resetStreamMetrics();

      String reasoningContent = '';
      var streamingAssistantMessage = assistantMessage;
      _latestStreamingMessage = streamingAssistantMessage;
      var isFirstContinueChunk = continueGeneration;

      final mcpConfig = ref.read(chatMcpConfigProvider);
      final integrations =
          mcpConfig.enabled && mcpConfig.integrations.isNotEmpty
          ? mcpConfig.integrations
          : null;

      final registry = ref.read(toolRegistryProvider);
      final tools = mcpConfig.enabled
          ? await registry.listTools()
          : const <ToolDefinition>[];

      bool stateNeedsUpdate = false;

      void updateUiState() {
        if (!stateNeedsUpdate) return;
        stateNeedsUpdate = false;
        if (_activeConversationId == assistantMessage.conversationId) {
          state = state.copyWith(streamingMessage: streamingAssistantMessage);
        }
      }

      _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
        updateUiState();
      });

      final streamGeneration = _streamGeneration;
      _streamSubscription = chatService
          .sendMessage(
            server: server,
            modelId: selectedModel?.id ?? 'default',
            messages: messagesForApi,
            params: chatParams,
            integrations: integrations,
            tools: tools,
            continueGeneration: continueGeneration,
          )
          .listen(
            (response) async {
              if (streamGeneration != _streamGeneration) return;
              final streamConvId = assistantMessage.conversationId;
              final isCurrentContext = _activeConversationId == streamConvId;

              switch (response.type) {
                case ChatResponseType.message:
                  if (response.content?.isNotEmpty ?? false) {
                    _noteFirstToken();
                  }
                  var delta = response.content ?? '';
                  if (isFirstContinueChunk && delta.isNotEmpty) {
                    isFirstContinueChunk = false;
                    final existing = streamingAssistantMessage.content;
                    if (existing.isNotEmpty &&
                        !RegExp(r'[\s\p{P}]$', unicode: true)
                            .hasMatch(existing) &&
                        !RegExp(r'^[\s\p{P}]', unicode: true)
                            .hasMatch(delta)) {
                      delta = ' $delta';
                    }
                  }
                  streamingAssistantMessage = streamingAssistantMessage
                      .copyWith(
                        content: streamingAssistantMessage.content + delta,
                        isProcessing: false,
                      );
                  _latestStreamingMessage = streamingAssistantMessage;
                  _chunkCount++;
                  if (!_isInMemoryChat &&
                      _shouldCheckpointSave(streamingAssistantMessage)) {
                    _saveService?.enqueue(streamingAssistantMessage);
                    _updateSavedMetrics(streamingAssistantMessage);
                    _resetCheckpointMetrics();
                  }
                  stateNeedsUpdate = true;
                  break;
                case ChatResponseType.reasoning:
                  if (response.reasoningContent?.isNotEmpty ?? false) {
                    _noteFirstToken();
                  }
                  reasoningContent += response.reasoningContent ?? '';
                  streamingAssistantMessage = streamingAssistantMessage
                      .copyWith(
                        reasoningContent: reasoningContent,
                        isProcessing: false,
                      );
                  _latestStreamingMessage = streamingAssistantMessage;
                  _chunkCount++;
                  if (!_isInMemoryChat &&
                      _shouldCheckpointSave(streamingAssistantMessage)) {
                    _saveService?.enqueue(streamingAssistantMessage);
                    _updateSavedMetrics(streamingAssistantMessage);
                    _resetCheckpointMetrics();
                  }
                  stateNeedsUpdate = true;
                  break;
                case ChatResponseType.processing:
                  streamingAssistantMessage = streamingAssistantMessage
                      .copyWith(isProcessing: true);
                  _latestStreamingMessage = streamingAssistantMessage;
                  stateNeedsUpdate = true;
                  break;
                case ChatResponseType.timeoutError:
                case ChatResponseType.error:
                  _uiUpdateTimer?.cancel();
                  _uiUpdateTimer = null;
                  streamingAssistantMessage = _finalizeStreamMessage(
                    streamingAssistantMessage.copyWith(
                      status: MessageStatus.error,
                      errorMessage: response.content,
                      isProcessing: false,
                    ),
                    stopReason: 'error',
                  );
                  await _saveMessage(streamingAssistantMessage);
                  if (isCurrentContext) {
                    _replaceMessageInAll(
                      streamingAssistantMessage,
                      clearStreaming: true,
                    );
                    state = state.copyWith(
                      isStreaming: false,
                      clearStreaming: true,
                    );
                  }
                  ref.read(isStreamingProvider.notifier).setStreaming(false);
                  ref.read(chatBackgroundServiceProvider).stop();
                  break;
                case ChatResponseType.done:
                  if (response.stats != null) {
                    _streamStats = response.stats;
                  }
                  break;
                default:
                  break;
              }
            },
            onDone: () async {
              _uiUpdateTimer?.cancel();
              _uiUpdateTimer = null;
              final streamConvId = assistantMessage.conversationId;
              final isCurrentContext = _activeConversationId == streamConvId;

              final finalMessage = _finalizeStreamMessage(
                streamingAssistantMessage.copyWith(
                  status: MessageStatus.complete,
                  isProcessing: false,
                ),
                stopReason: 'complete',
              );
              await _saveMessage(finalMessage);
              if (isCurrentContext) {
                _replaceMessageInAll(finalMessage, clearStreaming: true);
                state = state.copyWith(isStreaming: false, clearStreaming: true);
              }
              ref.read(isStreamingProvider.notifier).setStreaming(false);
              ref.read(chatBackgroundServiceProvider).stop();
              await _syncConversationStatsAfterGeneration(
                streamConvId,
                finalMessage,
                isCurrentContext: isCurrentContext,
              );
              _maybeRequestReviewAfterSuccessfulCompletion(
                finalMessage: finalMessage,
                server: server,
                selectedModel: selectedModel,
              );
            },
            onError: (Object error, StackTrace stackTrace) async {
              Log.error('Stream error: $error');
              _uiUpdateTimer?.cancel();
              _uiUpdateTimer = null;
              final isCurrentContext =
                  _activeConversationId == assistantMessage.conversationId;
              final errorMessage = streamingAssistantMessage.copyWith(
                status: MessageStatus.error,
                errorMessage: error.toString(),
                isProcessing: false,
              );
              await _saveMessage(errorMessage);
              if (isCurrentContext) {
                _replaceMessageInAll(errorMessage, clearStreaming: true);
                state = state.copyWith(
                  isStreaming: false,
                  clearStreaming: true,
                  errorMessage: error.toString(),
                );
              }
              ref.read(isStreamingProvider.notifier).setStreaming(false);
              ref.read(chatBackgroundServiceProvider).stop();
            },
          );
    } catch (e) {
      state = state.copyWith(
        isStreaming: false,
        errorMessage: e.toString(),
        clearStreaming: true,
      );
      ref.read(isStreamingProvider.notifier).setStreaming(false);
    }
  }

  void _replaceMessageInAll(Message message, {bool clearStreaming = false}) {
    final updatedAll = state.allMessages.map((m) {
      return m.id == message.id ? message : m;
    }).toList();
    state = state.copyWith(
      allMessages: updatedAll,
      messages: MessageVariants.resolveActiveTimeline(updatedAll),
      streamingMessage: clearStreaming ? null : message,
      clearStreaming: clearStreaming,
    );
  }

  Future<void> editAssistantMessage(String messageId, String newContent) async {
    final messageIndex = state.messages.indexWhere((m) => m.id == messageId);
    if (messageIndex == -1) return;

    final message = state.messages[messageIndex];
    if (message.role != MessageRole.assistant) return;
    if (newContent.trim().isEmpty) return;
    if (newContent == message.content) return;

    final updated = message.copyWith(
      content: newContent,
      status: MessageStatus.complete,
    );
    await _saveMessage(updated);
    _replaceMessageInAll(updated);
  }

  Future<void> branchFromMessage(String messageId) async {
    final messageIndex = state.messages.indexWhere((m) => m.id == messageId);
    if (messageIndex == -1) return;

    final activeConv = ref.read(conv.activeConversationProvider);
    if (activeConv == null) return;

    final messagesToCopy = state.messages.sublist(0, messageIndex + 1);
    final branchTitle = activeConv.title.length > 40
        ? '${activeConv.title.substring(0, 40)}...'
        : activeConv.title;

    final newConversation = await ref
        .read(conv.conversationsProvider.notifier)
        .createConversation(
          title: '$branchTitle (branch)',
          personaId: activeConv.personaId,
          systemPrompt: activeConv.systemPrompt,
          serverId: activeConv.serverId,
          modelId: activeConv.modelId,
          mcpEnabled: activeConv.mcpEnabled,
        );

    if (activeConv.temperature != null ||
        activeConv.topP != null ||
        activeConv.maxTokens != null ||
        activeConv.contextLength != null) {
      await ref.read(conv.conversationsProvider.notifier).updateChatParams(
            newConversation.id,
            temperature: activeConv.temperature,
            topP: activeConv.topP,
            maxTokens: activeConv.maxTokens,
            contextLength: activeConv.contextLength,
          );
    }

    for (final msg in messagesToCopy) {
      final copied = msg.copyWith(
        id: generateUuid(),
        conversationId: newConversation.id,
      );
      await _saveMessage(copied);
    }

    final lastMessage = messagesToCopy.last;
    final preview = lastMessage.content.length > 100
        ? '${lastMessage.content.substring(0, 100)}...'
        : lastMessage.content;

    await ref.read(conv.conversationsProvider.notifier).updatePreview(
          newConversation.id,
          preview,
          DateTime.now(),
          messageCount: messagesToCopy.length,
          characterCount: messagesToCopy.fold<int>(
            0,
            (sum, message) => sum + message.content.length,
          ),
        );

    final refreshedConversations = ref.read(conv.conversationsProvider).value;
    final branchedConversation = refreshedConversations?.firstWhere(
      (c) => c.id == newConversation.id,
      orElse: () => newConversation,
    );

    if (branchedConversation != null) {
      await loadConversation(branchedConversation);
    }
  }

  Future<void> deleteMessage(String messageId) async {
    final db = ref.read(databaseProvider);
    final query = db.messageBox
        .query(MessageEntity_.id.equals(messageId))
        .build();
    db.messageBox.removeMany(query.findIds());
    query.close();

    final updatedAll =
        state.allMessages.where((m) => m.id != messageId).toList();
    state = state.copyWith(
      allMessages: updatedAll,
      messages: MessageVariants.resolveActiveTimeline(updatedAll),
    );

    if (_currentConversationId != null) {
      _recomputeConversationTotal(_currentConversationId!);
    }
  }

  Future<void> editMessageSaveOnly(String messageId, String newContent) async {
    final messageIndex = state.messages.indexWhere((m) => m.id == messageId);
    if (messageIndex == -1) return;

    final message = state.messages[messageIndex];
    if (message.role != MessageRole.user) return;
    if (newContent.trim().isEmpty) return;
    if (newContent == message.content) return;

    final updated = message.copyWith(content: newContent);
    await _saveMessage(updated);
    _replaceMessageInAll(updated);
  }

  Future<void> generateResponseForLastUser() async {
    if (state.isStreaming) return;
    final messages = state.messages;
    if (messages.isEmpty || messages.last.role != MessageRole.user) return;

    final userMessage = messages.last;
    await _regenerateAssistant(
      userMessage,
      variantGroupId: generateUuid(),
      threadOrder: userMessage.threadOrder + 1,
      variantIndex: 0,
    );
  }

  Future<void> generateAiUserMessage() async {
    if (state.isStreaming) return;
    if (state.messages.isEmpty) return;

    final server = ref.read(activeServerProvider);
    final selectedModel = ref.read(selectedModelProvider);
    final chatService = ref.read(chatServiceProvider);
    if (server == null || chatService == null || selectedModel == null) return;

    final generated = await ref.read(smartReplyServiceProvider).generateUserMessage(
          chatService: chatService,
          server: server,
          modelId: selectedModel.id,
          messages: state.messages,
          params: ref.read(chatParamsProvider),
        );

    if (generated == null || generated.trim().isEmpty) return;
    await sendMessage(generated.trim());
  }

  Future<void> saveTemporaryChatToHistory() async {
    if (!state.isTemporary || state.messages.isEmpty) return;

    final server = ref.read(activeServerProvider);
    if (server == null) return;

    final settings = ref.read(settingsProvider);
    final firstUser = state.messages
        .where((m) => m.role == MessageRole.user)
        .map((m) => m.content.trim())
        .firstWhere((c) => c.isNotEmpty, orElse: () => '');

    final title = settings.autoGenerateTitle
        ? 'New Chat'
        : ref
            .read(titleGenerationServiceProvider)
            .truncateFirstMessageTitle(
              firstUser.isNotEmpty ? firstUser : 'New Chat',
            );

    final preselected = ref.read(selectedPersonasProvider);
    final conversation = await ref
        .read(conv.conversationsProvider.notifier)
        .createConversation(
          title: title,
          serverId: server.id,
          modelId: ref.read(selectedModelProvider)?.id,
          personaId: preselected.isEmpty
              ? null
              : PersonaPromptUtils.joinPersonaIds(
                  preselected.map((p) => p.id).toList(),
                ),
          systemPrompt: preselected.isEmpty
              ? null
              : PersonaPromptUtils.combineSystemPrompts(preselected),
          mcpEnabled: settings.newChatMcpEnabled,
          isTemporary: false,
        );

    _currentConversationId = conversation.id;
    _ephemeralConversationId = null;
    state = state.copyWith(isTemporary: false);
    ref
        .read(conv.activeConversationProvider.notifier)
        .setActiveConversation(conversation);

    final updatedAll = state.allMessages
        .map((m) => m.copyWith(conversationId: conversation.id))
        .toList();
    _setAllMessages(updatedAll);

    for (final message in updatedAll) {
      await _saveMessage(message);
    }
  }

  Future<void> editMessage(String messageId, String newContent) async {
    final messageIndex = state.messages.indexWhere((m) => m.id == messageId);
    if (messageIndex == -1) return;

    final message = state.messages[messageIndex];
    if (message.role != MessageRole.user) return;
    if (newContent.trim().isEmpty) return;
    if (newContent == message.content) return;

    final groupId = MessageVariants.groupId(message);
    final deactivated = state.allMessages.map((m) {
      if (MessageVariants.groupId(m) != groupId) return m;
      return m.copyWith(isActiveVariant: false);
    }).toList();
    for (final m in deactivated.where(
      (x) => MessageVariants.groupId(x) == groupId,
    )) {
      await _saveMessage(m);
    }
    state = state.copyWith(allMessages: deactivated);

    final newUser = message.copyWith(
      id: generateUuid(),
      content: newContent,
      createdAt: DateTime.now(),
      variantIndex: _nextVariantIndex(groupId),
      isActiveVariant: true,
      parentMessageId: message.parentMessageId,
    );
    await _saveMessage(newUser);
    final updatedAll = [...state.allMessages, newUser];
    _setAllMessages(updatedAll);

    await _regenerateAssistant(
      newUser,
      variantGroupId: generateUuid(),
      threadOrder: message.threadOrder + 1,
      variantIndex: 0,
    );
  }

  Future<void> _saveMessage(Message message) async {
    if (_isInMemoryChat) return;
    final db = ref.read(databaseProvider);
    await db.store.runInTransactionAsync(
      TxMode.write,
      _saveMessageInBackground,
      message,
    );
  }

  static void _saveMessageInBackground(Store store, Message message) {
    final box = store.box<MessageEntity>();
    final convBox = store.box<ConversationEntity>();

    final query = box.query(MessageEntity_.id.equals(message.id)).build();
    final existing = query.findFirst();
    query.close();

    final entity = MessageEntity.fromDomain(message);
    if (existing != null) {
      entity.internalId = existing.internalId;
    }

    final convQuery = convBox
        .query(ConversationEntity_.id.equals(message.conversationId))
        .build();
    final convEntity = convQuery.findFirst();
    convQuery.close();

    if (convEntity != null) {
      entity.conversation.target = convEntity;
      entity.conversationUid = convEntity.id;
    } else {
      entity.conversationUid = message.conversationId;
    }

    box.put(entity);
  }

  Future<void> clearConversation() async {
    final db = ref.read(databaseProvider);
    if (_currentConversationId != null && !_isInMemoryChat) {
      final query = db.messageBox
          .query(MessageEntity_.conversationUid.equals(_currentConversationId!))
          .build();
      db.messageBox.removeMany(query.findIds());
      query.close();
    }
    _currentConversationId = null;
    _ephemeralConversationId = null;
    _pendingTemporaryChat = false;
    state = const ChatState();
    ref
        .read(conv.activeConversationProvider.notifier)
        .setActiveConversation(null);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

final hasActiveChatSessionProvider = Provider<bool>((ref) {
  final chat = ref.watch(chatProvider);
  final activeConv = ref.watch(conv.activeConversationProvider);
  return chat.messages.isNotEmpty ||
      chat.isStreaming ||
      activeConv != null;
});
