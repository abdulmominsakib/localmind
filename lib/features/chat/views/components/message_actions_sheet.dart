import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:localmind/core/components/action_sheet.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/l10n/app_localizations.dart';
import '../../../saved_messages/providers/saved_message_providers.dart';
import '../../../tts/providers/tts_providers.dart' as tts;
import '../../providers/message_selection_provider.dart';

/// Everything the message action row and the actions sheet need about one
/// message. A null callback hides its action.
class MessageActions {
  const MessageActions({
    required this.content,
    this.messageId,
    this.conversationId,
    this.modelId,
    this.createdAt,
    this.tokenCount,
    this.inputTokenCount,
    this.generationTimeMs,
    this.ttftMs,
    this.tokensPerSecond,
    this.stopReason,
    this.onCopy,
    this.onRetry,
    this.onDelete,
    this.onEdit,
    this.onShare,
    this.onBranch,
    this.onContinue,
    this.onSave,
    this.onModelInfo,
  });

  final String content;
  final String? messageId;
  final String? conversationId;
  final String? modelId;
  final DateTime? createdAt;
  final int? tokenCount;
  final int? inputTokenCount;
  final int? generationTimeMs;
  final int? ttftMs;
  final double? tokensPerSecond;
  final String? stopReason;
  final VoidCallback? onCopy;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final VoidCallback? onShare;
  final VoidCallback? onBranch;
  final VoidCallback? onContinue;
  final VoidCallback? onSave;
  final VoidCallback? onModelInfo;
}

/// Whether text-to-speech is currently playing or paused on this message.
bool isMessageSpeechActive(tts.TtsState state, MessageActions actions) {
  if (actions.messageId != null &&
      state.playingMessageId == actions.messageId) {
    return state.isSpeaking || state.isPaused;
  }
  return state.playingContent == actions.content &&
      (state.isSpeaking || state.isPaused);
}

/// Starts reading [actions] aloud, or pauses/resumes it if it's the message
/// already playing.
Future<void> toggleMessageSpeech(WidgetRef ref, MessageActions actions) async {
  final notifier = ref.read(tts.ttsProvider.notifier);
  final state = ref.read(tts.ttsProvider);
  if (isMessageSpeechActive(state, actions)) {
    notifier.togglePauseResume();
    return;
  }
  if (state.isSpeaking || state.isPaused) await notifier.stop();
  try {
    await notifier.speak(
      actions.content,
      messageId: actions.messageId,
      conversationId: actions.conversationId,
    );
  } catch (_) {}
}

Future<void> copyMessageText(
  BuildContext context,
  MessageActions actions,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.maybeOf(context);
  await Clipboard.setData(ClipboardData(text: actions.content));
  actions.onCopy?.call();
  messenger?.showSnackBar(
    SnackBar(
      content: Text(l10n.copied_to_clipboard),
      duration: const Duration(seconds: 2),
    ),
  );
}

void showMessageActionsSheet(BuildContext context, MessageActions actions) {
  HapticFeedback.selectionClick();
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => MessageActionsSheet(actions: actions),
  );
}

/// Every action for one message: quick actions on top, the rest as a list,
/// and the generation stats underneath.
class MessageActionsSheet extends ConsumerWidget {
  const MessageActionsSheet({super.key, required this.actions});

  final MessageActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final ttsState = ref.watch(tts.ttsProvider);
    final speaking = isMessageSpeechActive(ttsState, actions);
    final playing = speaking && ttsState.isSpeaking && !ttsState.isPaused;
    final isSaved = actions.messageId != null
        ? ref.watch(isMessageSavedProvider(actions.messageId!)).value ?? false
        : false;

    void run(VoidCallback action) {
      Navigator.of(context).pop();
      action();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: MessageQuickAction(
                  icon: HugeIcons.strokeRoundedCopy01,
                  label: l10n.copy,
                  onTap: () {
                    Navigator.of(context).pop();
                    copyMessageText(context, actions);
                  },
                ),
              ),
              if (actions.onRetry != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: MessageQuickAction(
                    icon: HugeIcons.strokeRoundedRefresh,
                    label: l10n.retry,
                    onTap: () => run(actions.onRetry!),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: MessageQuickAction(
                  icon: speaking
                      ? (playing
                            ? HugeIcons.strokeRoundedPauseCircle
                            : HugeIcons.strokeRoundedPlayCircle)
                      : HugeIcons.strokeRoundedVolumeUp,
                  label: speaking
                      ? (playing ? l10n.pause : l10n.resume)
                      : l10n.read_aloud,
                  onTap: () {
                    Navigator.of(context).pop();
                    toggleMessageSpeech(ref, actions);
                  },
                ),
              ),
              if (actions.onShare != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: MessageQuickAction(
                    icon: HugeIcons.strokeRoundedShare01,
                    label: l10n.share,
                    onTap: () => run(actions.onShare!),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          ActionSheetGroup(
            children: [
              if (actions.onEdit != null)
                ActionSheetTile(
                  icon: HugeIcons.strokeRoundedPencilEdit02,
                  label: l10n.edit,
                  onTap: () => run(actions.onEdit!),
                ),
              if (actions.onContinue != null)
                ActionSheetTile(
                  icon: HugeIcons.strokeRoundedArrowRight01,
                  label: l10n.continue_action,
                  onTap: () => run(actions.onContinue!),
                ),
              if (actions.onSave != null)
                ActionSheetTile(
                  icon: HugeIcons.strokeRoundedBookmark01,
                  label: isSaved
                      ? l10n.message_already_saved
                      : l10n.save_message,
                  onTap: () => run(actions.onSave!),
                ),
              if (actions.onBranch != null)
                ActionSheetTile(
                  icon: HugeIcons.strokeRoundedGitBranch,
                  label: l10n.branch_chat,
                  onTap: () => run(actions.onBranch!),
                ),
              ActionSheetTile(
                icon: HugeIcons.strokeRoundedCode,
                label: l10n.copy_markdown,
                onTap: () {
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  Navigator.of(context).pop();
                  Clipboard.setData(ClipboardData(text: actions.content));
                  messenger?.showSnackBar(
                    SnackBar(content: Text(l10n.copied_markdown)),
                  );
                },
              ),
              if (actions.messageId != null)
                ActionSheetTile(
                  icon: HugeIcons.strokeRoundedCheckList,
                  label: l10n.select,
                  onTap: () {
                    Navigator.of(context).pop();
                    ref.read(messageSelectionModeProvider.notifier).enable();
                    ref
                        .read(selectedMessageIdsProvider.notifier)
                        .toggle(actions.messageId!);
                  },
                ),
              if (actions.onModelInfo != null && actions.modelId != null)
                ActionSheetTile(
                  icon: HugeIcons.strokeRoundedInformationCircle,
                  label: actions.modelId!,
                  onTap: () => run(actions.onModelInfo!),
                ),
              if (actions.onDelete != null)
                ActionSheetTile(
                  icon: HugeIcons.strokeRoundedDelete01,
                  label: l10n.delete,
                  isDestructive: true,
                  onTap: () {
                    final onDelete = actions.onDelete!;
                    Navigator.of(context).pop();
                    confirmMessageDelete(context, onDelete);
                  },
                ),
            ],
          ),
          MessageStatsFooter(actions: actions),
        ],
      ),
    );
  }
}

void confirmMessageDelete(BuildContext context, VoidCallback onDelete) {
  final l10n = AppLocalizations.of(context)!;
  showShadDialog(
    context: context,
    builder: (dialogContext) => ShadDialog(
      title: Text(l10n.delete_message_title),
      description: Text(l10n.cannot_undo),
      actions: [
        ShadButton.outline(
          child: Text(l10n.cancel),
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
        ShadButton.destructive(
          child: Text(l10n.delete),
          onPressed: () {
            Navigator.of(dialogContext).pop();
            onDelete();
          },
        ),
      ],
    ),
  );
}

class MessageQuickAction extends StatelessWidget {
  const MessageQuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final List<List<dynamic>> icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark
        ? AppColors.darkPrimaryText
        : AppColors.lightPrimaryText;
    return Material(
      color: isDark ? AppColors.darkSurfaceCard : const Color(0xFFF4F4F5),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          height: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              HugeIcon(icon: icon, size: 20, color: foreground),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Generation stats and the message time, shown at the bottom of the
/// actions sheet instead of under every message.
class MessageStatsFooter extends StatelessWidget {
  const MessageStatsFooter({super.key, required this.actions});

  final MessageActions actions;

  static String _formatMs(int ms) =>
      ms >= 1000 ? '${(ms / 1000).toStringAsFixed(2)}s' : '${ms}ms';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;
    final createdAt = actions.createdAt;

    final stats = <(String, String)>[
      if (createdAt != null)
        (
          '',
          MaterialLocalizations.of(context).formatTimeOfDay(
            TimeOfDay.fromDateTime(createdAt),
            alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
          ),
        ),
      if (actions.ttftMs != null)
        (l10n.stream_ttft, _formatMs(actions.ttftMs!)),
      if (actions.generationTimeMs != null)
        (l10n.stream_generation_time, _formatMs(actions.generationTimeMs!)),
      if (actions.inputTokenCount != null)
        (l10n.stream_input_tokens, '${actions.inputTokenCount}'),
      if (actions.tokenCount != null)
        (l10n.stream_output_tokens, '${actions.tokenCount}'),
      if (actions.tokensPerSecond != null)
        (
          l10n.stream_tokens_per_sec,
          actions.tokensPerSecond!.toStringAsFixed(1),
        ),
      if (actions.stopReason?.isNotEmpty ?? false)
        (l10n.stream_stop_reason, actions.stopReason!),
      (l10n.characters_label, '${actions.content.length}'),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: [
          for (final (label, value) in stats)
            Text.rich(
              TextSpan(
                children: [
                  if (label.isNotEmpty) TextSpan(text: '$label '),
                  TextSpan(
                    text: value,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              style: TextStyle(fontSize: 12, color: muted),
            ),
        ],
      ),
    );
  }
}
