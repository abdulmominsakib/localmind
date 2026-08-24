import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart'
    as conv;
import 'package:localmind/features/voice_mode/providers/voice_mode_provider.dart';
import 'chat_notifier.dart';
import 'chat_params_providers.dart';
import 'chat_service_providers.dart';
import 'model_selection_providers.dart';

final smartRepliesProvider = FutureProvider<List<String>>((ref) async {
  final isStreaming = ref.watch(chatProvider.select((s) => s.isStreaming));
  final settings = ref.watch(settingsProvider);
  final voiceState = ref.watch(voiceModeProvider);
  final target = ref.watch(activeChatTargetProvider);
  final chatParams = ref.watch(chatParamsProvider);
  final chatService = ref.watch(chatServiceProvider);

  if (isStreaming) return [];
  if (voiceState.isActive || voiceState.phase != VoiceModePhase.idle) return [];

  final messages = ref.watch(chatProvider.select((s) => s.messages));
  if (messages.isEmpty) return [];

  final lastMessage = messages.last;
  if (lastMessage.role != MessageRole.assistant ||
      lastMessage.status != MessageStatus.complete) {
    return [];
  }

  // Only watch the smart replies cache fields of the active conversation to avoid
  // invalidating and restarting this provider when conversation title or stats change.
  final cachedData = ref.watch(
    conv.activeConversationProvider.select((c) {
      if (c == null) return null;
      return (
        id: c.id,
        smartRepliesLastMessageId: c.smartRepliesLastMessageId,
        smartReplies: c.smartReplies,
      );
    }),
  );

  if (cachedData != null &&
      cachedData.smartRepliesLastMessageId == lastMessage.id &&
      cachedData.smartReplies != null &&
      cachedData.smartReplies!.isNotEmpty) {
    return cachedData.smartReplies!;
  }

  // If AI title generation is running for this conversation, wait for it first
  // so LLM inference executes sequentially without colliding on local models.
  final chatNotifier = ref.read(chatProvider.notifier);
  await chatNotifier.waitForTitleGeneration(lastMessage.conversationId);

  if (!ref.mounted) return [];
  if (ref.read(chatProvider.select((s) => s.isStreaming))) return [];

  List<String> suggestions = [];

  if (settings.smartReplyEnabled) {
    final server = target.server;
    final modelId = target.effectiveModelId;

    if (server != null && chatService != null && modelId != null) {
      final service = ref.read(smartReplyServiceProvider);
      suggestions = await service.suggestRepliesWithLLM(
        chatService: chatService,
        server: server,
        modelId: modelId,
        messages: messages,
        params: chatParams,
        personaSystemPrompt: settings.smartRepliesUsePersona
            ? chatParams.systemPrompt
            : null,
      );
      if (!ref.mounted) return [];
    }
  }

  if (suggestions.isEmpty) {
    if (!ref.mounted) return [];
    final service = ref.read(smartReplyServiceProvider);
    suggestions = service.getFallbackReplies(lastMessage.content);
  }

  final convId = cachedData?.id ?? lastMessage.conversationId;
  if (suggestions.isNotEmpty) {
    Future.microtask(() {
      if (ref.mounted) {
        ref
            .read(conv.conversationsProvider.notifier)
            .updateSmartReplies(convId, suggestions, lastMessage.id);
      }
    });
  }

  return suggestions;
});
