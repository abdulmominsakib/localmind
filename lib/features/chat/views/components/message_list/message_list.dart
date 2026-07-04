import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/chat/providers/chat_providers.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart';
import 'package:localmind/l10n/app_localizations.dart';
import '../chat_bubble.dart';

class MessageList extends StatelessWidget {
  const MessageList({
    super.key,
    required this.scrollController,
    required this.messages,
    required this.allMessages,
    required this.isStreaming,
    required this.onRetry,
    required this.onDelete,
    required this.onEdit,
    required this.onEditAssistant,
    required this.onBranch,
    required this.onContinue,
    required this.onCycleVariant,
    required this.onModelPicker,
    this.onModelLongPress,
    this.onSave,
    this.onShare,
    this.onGenerateResponse,
    this.hasSmartReplies = false,
    this.bottomInset = 0,
  });

  final ScrollController scrollController;
  final List<Message> messages;
  final List<Message> allMessages;
  final bool isStreaming;
  final void Function(String) onRetry;
  final void Function(String) onDelete;
  final void Function(String messageId, String currentContent) onEdit;
  final void Function(String messageId, String currentContent) onEditAssistant;
  final void Function(String messageId) onBranch;
  final void Function(String messageId) onContinue;
  final void Function(String messageId, int direction) onCycleVariant;
  final VoidCallback onModelPicker;
  final void Function(String modelId)? onModelLongPress;
  final void Function(Message message)? onSave;
  final void Function(Message message)? onShare;
  final VoidCallback? onGenerateResponse;
  final bool hasSmartReplies;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return _MessageListConsumer(
      scrollController: scrollController,
      messages: messages,
      allMessages: allMessages,
      isStreaming: isStreaming,
      onRetry: onRetry,
      onDelete: onDelete,
      onEdit: onEdit,
      onEditAssistant: onEditAssistant,
      onBranch: onBranch,
      onContinue: onContinue,
      onCycleVariant: onCycleVariant,
      onModelPicker: onModelPicker,
      onModelLongPress: onModelLongPress,
      onSave: onSave,
      onShare: onShare,
      onGenerateResponse: onGenerateResponse,
      hasSmartReplies: hasSmartReplies,
      bottomInset: bottomInset,
    );
  }
}

class _MessageListConsumer extends ConsumerStatefulWidget {
  const _MessageListConsumer({
    required this.scrollController,
    required this.messages,
    required this.allMessages,
    required this.isStreaming,
    required this.onRetry,
    required this.onDelete,
    required this.onEdit,
    required this.onEditAssistant,
    required this.onBranch,
    required this.onContinue,
    required this.onCycleVariant,
    required this.onModelPicker,
    this.onModelLongPress,
    this.onSave,
    this.onShare,
    this.onGenerateResponse,
    this.hasSmartReplies = false,
    this.bottomInset = 0,
  });

  final ScrollController scrollController;
  final List<Message> messages;
  final List<Message> allMessages;
  final bool isStreaming;
  final void Function(String) onRetry;
  final void Function(String) onDelete;
  final void Function(String messageId, String currentContent) onEdit;
  final void Function(String messageId, String currentContent) onEditAssistant;
  final void Function(String messageId) onBranch;
  final void Function(String messageId) onContinue;
  final void Function(String messageId, int direction) onCycleVariant;
  final VoidCallback onModelPicker;
  final void Function(String modelId)? onModelLongPress;
  final void Function(Message message)? onSave;
  final void Function(Message message)? onShare;
  final VoidCallback? onGenerateResponse;
  final bool hasSmartReplies;
  final double bottomInset;

  @override
  ConsumerState<_MessageListConsumer> createState() =>
      _MessageListConsumerState();
}

class _MessageListConsumerState extends ConsumerState<_MessageListConsumer> {
  final _messageKeys = <String, GlobalKey>{};

  @override
  void didUpdateWidget(covariant _MessageListConsumer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final activeIds = widget.messages.map((m) => m.id).toSet();
    _messageKeys.removeWhere((id, _) => !activeIds.contains(id));
  }

  void _scrollToMessage(String messageId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _messageKeys[messageId];
      final targetContext = key?.currentContext;
      if (targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.3,
        );
      }
      ref.read(scrollToMessageIdProvider.notifier).clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(scrollToMessageIdProvider, (previous, next) {
      if (next != null) {
        _scrollToMessage(next);
      }
    });

    final pendingScroll = ref.watch(scrollToMessageIdProvider);
    if (pendingScroll != null) {
      _scrollToMessage(pendingScroll);
    }

    final streamingMessage = ref.watch(
      chatProvider.select((s) => s.streamingMessage),
    );

    return _MessageList(
      scrollController: widget.scrollController,
      messages: widget.messages,
      allMessages: widget.allMessages,
      streamingMessage: streamingMessage,
      isStreaming: widget.isStreaming,
      messageKeys: _messageKeys,
      onRetry: widget.onRetry,
      onDelete: widget.onDelete,
      onEdit: widget.onEdit,
      onEditAssistant: widget.onEditAssistant,
      onBranch: widget.onBranch,
      onContinue: widget.onContinue,
      onCycleVariant: widget.onCycleVariant,
      onModelPicker: widget.onModelPicker,
      onModelLongPress: widget.onModelLongPress,
      onSave: widget.onSave,
      onShare: widget.onShare,
      onGenerateResponse: widget.onGenerateResponse,
      hasSmartReplies: widget.hasSmartReplies,
      bottomInset: widget.bottomInset,
    );
  }
}

class _MessageList extends ConsumerWidget {
  const _MessageList({
    required this.scrollController,
    required this.messages,
    required this.allMessages,
    required this.streamingMessage,
    required this.isStreaming,
    required this.messageKeys,
    required this.onRetry,
    required this.onDelete,
    required this.onEdit,
    required this.onEditAssistant,
    required this.onBranch,
    required this.onContinue,
    required this.onCycleVariant,
    required this.onModelPicker,
    this.onModelLongPress,
    this.onSave,
    this.onShare,
    this.onGenerateResponse,
    this.hasSmartReplies = false,
    this.bottomInset = 0,
  });

  final ScrollController scrollController;
  final List<Message> messages;
  final List<Message> allMessages;
  final Message? streamingMessage;
  final bool isStreaming;
  final Map<String, GlobalKey> messageKeys;
  final void Function(String) onRetry;
  final void Function(String) onDelete;
  final void Function(String messageId, String currentContent) onEdit;
  final void Function(String messageId, String currentContent) onEditAssistant;
  final void Function(String messageId) onBranch;
  final void Function(String messageId) onContinue;
  final void Function(String messageId, int direction) onCycleVariant;
  final VoidCallback onModelPicker;
  final void Function(String modelId)? onModelLongPress;
  final void Function(Message message)? onSave;
  final void Function(Message message)? onShare;
  final VoidCallback? onGenerateResponse;
  final bool hasSmartReplies;
  final double bottomInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectionMode = ref.watch(messageSelectionModeProvider);
    final selectedIds = ref.watch(selectedMessageIdsProvider);
    final showSystemMessages =
        ref.watch(settingsProvider.select((s) => s.showSystemMessagesInChat));
    final visibleMessages = <Message>[];

    // The streaming message only belongs at the end of the currently
    // displayed branch if that branch's active timeline actually resolves
    // to it — otherwise the user has cycled to a different variant while
    // a sibling variant is still generating in the background, and the
    // live bubble must not be appended to whatever branch is now on screen.
    final streamingBelongsToActiveTimeline = streamingMessage != null &&
        messages.any((m) => m.id == streamingMessage!.id);

    for (final message in messages) {
      if (!showSystemMessages && message.role == MessageRole.system) {
        continue;
      }
      if (streamingBelongsToActiveTimeline &&
          message.id == streamingMessage!.id &&
          isStreaming) {
        continue;
      }
      visibleMessages.add(message);
    }

    final showTrailingStreamingBubble =
        streamingBelongsToActiveTimeline && isStreaming;

    return ListView.builder(
      controller: scrollController,
      padding: EdgeInsets.only(
        top: 16,
        bottom: 120 + (hasSmartReplies ? 64 : 0) + bottomInset,
      ),
      itemCount:
          visibleMessages.length +
          (showTrailingStreamingBubble ? 1 : 0),
      itemBuilder: (context, index) {
        if (showTrailingStreamingBubble && index == visibleMessages.length) {
          return ChatBubble(
            key: ValueKey(streamingMessage!.id),
            message: streamingMessage!,
            allMessages: this.allMessages,
            isStreaming: true,
            onModelTap: onModelPicker,
          );
        }

        final message = visibleMessages[index];
        final isLast = index == visibleMessages.length - 1;
        final itemKey =
            messageKeys.putIfAbsent(message.id, GlobalKey.new);

        final bubble = ChatBubble(
          key: itemKey,
          message: message,
          allMessages: this.allMessages,
          isStreaming: isLast &&
              showTrailingStreamingBubble &&
              message.id == streamingMessage?.id,
          onRetry: () => onRetry(message.id),
          onDelete: () => onDelete(message.id),
          onEdit: message.role == MessageRole.user
              ? () => onEdit(message.id, message.content)
              : message.role == MessageRole.assistant
                  ? () => onEditAssistant(message.id, message.content)
                  : null,
          onBranch: () => onBranch(message.id),
          onContinue: message.role == MessageRole.assistant && isLast
              ? () => onContinue(message.id)
              : null,
          onCycleVariant: (direction) =>
              onCycleVariant(message.id, direction),
          onModelTap: onModelPicker,
          onModelLongPress: message.modelId != null &&
                  message.role == MessageRole.assistant &&
                  onModelLongPress != null
              ? () => onModelLongPress!(message.modelId!)
              : null,
          onSave: onSave,
          onShare: onShare == null
              ? null
              : () => onShare!(message),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (selectionMode)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: selectedIds.contains(message.id),
                    onChanged: (_) => ref
                        .read(selectedMessageIdsProvider.notifier)
                        .toggle(message.id),
                  ),
                  Expanded(child: bubble),
                ],
              )
            else
              bubble,
            if (!isStreaming &&
                isLast &&
                message.role == MessageRole.user &&
                onGenerateResponse != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: onGenerateResponse,
                    icon: const Icon(Icons.auto_awesome, size: 16),
                    label: Text(
                      AppLocalizations.of(context)!.generate_ai_response,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
