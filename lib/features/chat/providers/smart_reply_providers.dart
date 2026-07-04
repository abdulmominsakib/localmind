import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart'
    as conv;
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'chat_notifier.dart';
import 'chat_params_providers.dart';
import 'chat_service_providers.dart';
import 'model_selection_providers.dart';

final smartRepliesProvider = FutureProvider<List<String>>((ref) async {
  final isStreaming = ref.watch(chatProvider.select((s) => s.isStreaming));
  final settings = ref.watch(settingsProvider);

  if (isStreaming) return [];

  final messages = ref.watch(chatProvider.select((s) => s.messages));
  if (messages.isEmpty) return [];

  final lastMessage = messages.last;
  if (lastMessage.role != MessageRole.assistant ||
      lastMessage.status != MessageStatus.complete) {
    return [];
  }

  final activeConv = ref.watch(conv.activeConversationProvider);
  if (activeConv != null &&
      activeConv.smartRepliesLastMessageId == lastMessage.id &&
      activeConv.smartReplies != null &&
      activeConv.smartReplies!.isNotEmpty) {
    return activeConv.smartReplies!;
  }

  List<String> suggestions = [];

  if (settings.smartReplyEnabled) {
    final server = ref.watch(activeServerProvider);
    final selectedModel = ref.watch(selectedModelProvider);
    final chatParams = ref.watch(chatParamsProvider);
    final chatService = ref.watch(chatServiceProvider);

    if (server != null && chatService != null && selectedModel != null) {
      final service = ref.read(smartReplyServiceProvider);
      suggestions = await service.suggestRepliesWithLLM(
        chatService: chatService,
        server: server,
        modelId: selectedModel.id,
        messages: messages,
        params: chatParams,
        personaSystemPrompt:
            settings.smartRepliesUsePersona ? chatParams.systemPrompt : null,
      );
      if (!ref.mounted) return [];
    }
  }

  if (suggestions.isEmpty) {
    final service = ref.read(smartReplyServiceProvider);
    suggestions = service.getFallbackReplies(lastMessage.content);
  }

  if (activeConv != null && suggestions.isNotEmpty) {
    Future.microtask(() {
      if (ref.mounted) {
        ref
            .read(conv.conversationsProvider.notifier)
            .updateSmartReplies(activeConv.id, suggestions, lastMessage.id);
      }
    });
  }

  return suggestions;
});
