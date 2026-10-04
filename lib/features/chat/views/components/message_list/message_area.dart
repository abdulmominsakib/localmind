import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:localmind/core/services/share_service.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/chat/providers/chat_providers.dart';
import 'package:localmind/features/conversations/data/models/conversation.dart';
import 'package:localmind/features/models/views/model_picker_sheet.dart';
import 'package:localmind/features/chat/views/components/model_info_sheet.dart';
import 'package:localmind/features/chat/views/components/edit_message_dialog.dart';
import 'package:localmind/features/chat/views/components/message_list/message_list.dart';
import 'package:localmind/features/chat/views/components/message_list/empty_state.dart';
import 'package:localmind/features/chat/views/components/message_list/quick_prompt_chips.dart';
import 'package:localmind/features/chat/utils/new_chat_presence.dart';
import 'package:localmind/features/chat/views/components/message_list/corrupted_state.dart';
import 'package:localmind/features/saved_messages/views/components/save_message_sheet.dart';
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

  /// Mirrors the app bar: a model counts once one is chosen (or loaded on
  /// device) and its server is reachable, not when chats would fall back to
  /// a remote server's default model.
  static NewChatReadiness _readiness(WidgetRef ref, ServerType? serverType) {
    final target = ref.watch(activeChatTargetProvider);
    if (serverType == ServerType.onDevice) {
      // Apple Foundation Models and other on-device picks count as soon as
      // they're chosen; they load on first send.
      final picked = ref.watch(selectedModelProvider) != null;
      return picked || target.effectiveModelId != null
          ? NewChatReadiness.ready
          : NewChatReadiness.noModel;
    }
    final status = ref.watch(connectionStatusProvider);
    if (status == ConnectionStatus.disconnected ||
        status == ConnectionStatus.error) {
      return NewChatReadiness.disconnected;
    }
    return target.selectedModel == null
        ? NewChatReadiness.noModel
        : NewChatReadiness.ready;
  }

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
      final serverType = activeServer == null
          ? null
          : activeServer.isOnDevice
          ? ServerType.onDevice
          : activeServer.type;

      return EmptyState(
        presence: NewChatPresence.forServerType(serverType),
        serverName: activeServer?.name ?? '',
        readiness: _readiness(ref, serverType),
        onQuickPrompt: (prompt) {
          if (!ref.read(activeChatTargetProvider).isReady) {
            final toastL10n = AppLocalizations.of(context)!;
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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
          QuickPrompt(
            icon: HugeIcons.strokeRoundedSourceCode,
            text: l10n.quick_write,
          ),
          QuickPrompt(
            icon: HugeIcons.strokeRoundedCode,
            text: l10n.quick_explain,
          ),
          QuickPrompt(
            icon: HugeIcons.strokeRoundedBug01,
            text: l10n.quick_debug,
          ),
          QuickPrompt(
            icon: HugeIcons.strokeRoundedIdea01,
            text: l10n.quick_async,
          ),
        ],
        bottomInset: effectiveBottomInset,
        keyboardOpen: keyboardBottomInset > 0,
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
        // Guard every ref-touching statement post-await — the user can
        // pop this screen or open another conversation mid-edit.
        if (!context.mounted) return;
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
        if (!context.mounted) return;
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
