import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:localmind/core/routes/app_routes.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:localmind/core/services/share_service.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/chat/providers/chat_providers.dart';
import 'package:localmind/features/conversations/data/models/conversation.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart'
    as conv;
import 'package:localmind/features/models/views/model_picker_sheet.dart';
import 'package:localmind/features/personas/providers/personas_providers.dart';
import 'package:localmind/features/chat/views/components/model_info_sheet.dart';
import 'package:localmind/features/chat/views/components/edit_message_dialog.dart';
import 'package:localmind/features/chat/views/components/message_list/message_list.dart';
import 'package:localmind/features/chat/views/components/message_list/empty_state.dart';
import 'package:localmind/features/chat/views/components/message_list/corrupted_state.dart';
import 'package:localmind/features/saved_messages/views/components/save_message_sheet.dart';
import 'package:localmind/features/personas/views/components/persona_picker_sheet.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';

class MessageArea extends ConsumerWidget {
  const MessageArea({
    super.key,
    required this.isLoading,
    required this.messages,
    required this.activeConversation,
    this.errorMessage,
    required this.selectedModel,
    required this.isStreaming,
    required this.scrollController,
    required this.effectiveBottomInset,
    required this.keyboardBottomInset,
    required this.onModelPicker,
  });

  final bool isLoading;
  final List<Message> messages;
  final Conversation? activeConversation;
  final String? errorMessage;
  final dynamic selectedModel;
  final bool isStreaming;
  final ScrollController scrollController;
  final double effectiveBottomInset;
  final double keyboardBottomInset;
  final VoidCallback onModelPicker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    if (isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (messages.isEmpty && activeConversation != null) {
      return CorruptedChatState(
        conversation: activeConversation!,
        errorMessage: errorMessage,
        onStartNewChat: () =>
            ref.read(chatProvider.notifier).startNewConversation(),
      );
    }

    if (messages.isEmpty) {
      final activeServer = ref.watch(activeServerProvider);
      final isCloudProvider = activeServer?.type == ServerType.openRouter;

      return EmptyState(
        isCloudProvider: isCloudProvider,
        onQuickPrompt: (prompt) {
          if (!ref.read(activeChatTargetProvider).isReady) {
            final toastL10n = AppLocalizations.of(context)!;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(toastL10n.model_required_toast)),
            );
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => const ModelPickerSheet(),
            );
            return;
          }
          ref.read(chatProvider.notifier).sendMessage(prompt);
        },
        quickPrompts: [
          l10n.quick_write,
          l10n.quick_explain,
          l10n.quick_debug,
          l10n.quick_async,
        ],
        recentConversations: ref.watch(conv.recentConversationsProvider),
        onSeeAll: () => context.push(AppRoutes.chatHistory),
        selectedModel: selectedModel,
        onModelTap: onModelPicker,
        selectedPersonas: ref.watch(selectedPersonasProvider),
        onPersonaTap: () => showPersonaPickerSheet(
          context,
          mode: PersonaPickerMode.preselection,
        ),
      );
    }

    return MessageList(
      scrollController: scrollController,
      messages: messages,
      allMessages: ref.watch(chatProvider.select((s) => s.allMessages)),
      isStreaming: isStreaming,
      onRetry: (messageId) =>
          ref.read(chatProvider.notifier).retryMessage(messageId),
      onDelete: (messageId) =>
          ref.read(chatProvider.notifier).deleteMessage(messageId),
      onEdit: (messageId, currentContent) async {
        final result = await EditMessageDialog.showUserEdit(
          context,
          initialContent: currentContent,
        );
        if (result == null || result.content == currentContent) return;
        if (result.regenerate) {
          await ref
              .read(chatProvider.notifier)
              .editMessage(messageId, result.content);
        } else {
          await ref
              .read(chatProvider.notifier)
              .editMessageSaveOnly(messageId, result.content);
        }
      },
      onEditAssistant: (messageId, currentContent) async {
        final editL10n = AppLocalizations.of(context)!;
        final newContent = await EditMessageDialog.show(
          context,
          initialContent: currentContent,
          description: editL10n.edit_assistant_message_desc,
          saveLabel: editL10n.save,
        );
        if (newContent != null && newContent != currentContent) {
          await ref
              .read(chatProvider.notifier)
              .editAssistantMessage(messageId, newContent);
        }
      },
      onBranch: (messageId) =>
          ref.read(chatProvider.notifier).branchFromMessage(messageId),
      onContinue: (messageId) =>
          ref.read(chatProvider.notifier).continueFromMessage(messageId),
      onCycleVariant: (messageId, direction) => ref
          .read(chatProvider.notifier)
          .cycleMessageVariant(messageId, direction),
      onSave: (message) => showSaveMessageSheet(
        context,
        ref,
        message,
        isTemporaryChat: ref.read(chatProvider.select((s) => s.isTemporary)),
      ),
      onShare: (message) => ShareService.shareText(message.content),
      onGenerateResponse: () =>
          ref.read(chatProvider.notifier).generateResponseForLastUser(),
      onModelPicker: onModelPicker,
      onModelLongPress: (modelId) => showModelInfoSheet(context, ref, modelId),
      hasSmartReplies:
          !isStreaming &&
          keyboardBottomInset == 0 &&
          (ref.watch(smartRepliesProvider).asData?.value.isNotEmpty ?? false),
      bottomInset: effectiveBottomInset,
    );
  }
}
