import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/features/chat/views/components/chat_input_bar.dart';
import 'package:localmind/features/chat/views/components/top_bar/smart_reply_chips.dart';
import 'package:localmind/features/chat/providers/chat_providers.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart' as conv;
import 'package:localmind/features/models/views/model_picker_sheet.dart';
import 'package:localmind/l10n/app_localizations.dart';

class ChatBottomBar extends ConsumerWidget {
  const ChatBottomBar({
    super.key,
    required this.isStreaming,
    required this.keyboardBottomInset,
    required this.inputFocusNode,
  });

  final bool isStreaming;
  final double keyboardBottomInset;
  final FocusNode inputFocusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTemporary = ref.watch(chatProvider.select((s) => s.isTemporary));
    final keyboardIncognito =
        isTemporary &&
        ref.watch(settingsProvider.select((s) => s.tempChatKeyboardIncognito));
    final messages = ref.watch(chatProvider.select((s) => s.messages));
    final hasActiveConv = ref.watch(conv.activeConversationProvider) != null;
    final dbTokenCount = ref.watch(
      conv.activeConversationProvider.select((c) => c?.totalTokenCount),
    );
    final streamingId = ref.watch(
      chatProvider.select((s) => s.streamingMessage?.id),
    );

    int totalTokenCount = 0;
    if (hasActiveConv && dbTokenCount != null && dbTokenCount > 0) {
      totalTokenCount = dbTokenCount;
    } else {
      final lastWithStats = messages.reversed
          .where(
            (m) =>
                m.id != streamingId &&
                m.role == MessageRole.assistant &&
                (m.inputTokenCount != null || m.tokenCount != null),
          )
          .firstOrNull;
      if (lastWithStats != null) {
        totalTokenCount =
            (lastWithStats.inputTokenCount ?? 0) +
            (lastWithStats.tokenCount ?? 0);
      } else {
        totalTokenCount = messages
            .where((m) => m.id != streamingId)
            .fold<int>(0, (sum, m) => sum + (m.content.length / 4).round());
      }
    }

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.1),
              Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.8),
              Theme.of(context).scaffoldBackgroundColor,
            ],
            stops: const [0.0, 0.7, 1.0],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isStreaming && keyboardBottomInset == 0) ...[
              const SizedBox(height: 4),
              const SmartReplyChipsWrapper(),
            ],
            ChatInputBar(
              focusNode: inputFocusNode,
              isStreaming: isStreaming,
              keyboardIncognito: keyboardIncognito,
              onSend: (message, {attachments}) {
                ref
                    .read(chatProvider.notifier)
                    .sendMessage(message, attachments: attachments);
              },
              onStop: () => ref.read(chatProvider.notifier).cancelStream(),
              totalTokenCount: totalTokenCount,
            ),
          ],
        ),
      ),
    );
  }
}

class SmartReplyChipsWrapper extends ConsumerWidget {
  const SmartReplyChipsWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SmartReplyChips(
      onSend: (message) {
        if (ref.read(selectedModelProvider) == null) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.model_required_toast)),
          );
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => const ModelPickerSheet(),
          );
          return;
        }
        ref.read(chatProvider.notifier).sendMessage(message);
      },
    );
  }
}
