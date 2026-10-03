import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:localmind/core/theme/colors.dart';
import '../../../tts/providers/tts_providers.dart' as tts;
import 'message_actions_sheet.dart';

/// The compact row under an assistant reply: copy, retry, read aloud, and
/// "more", which opens [MessageActionsSheet] with every other action.
class MessageActionBar extends ConsumerWidget {
  const MessageActionBar({super.key, required this.actions});

  final MessageActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final ttsState = ref.watch(tts.ttsProvider);
    final speaking = isMessageSpeechActive(ttsState, actions);
    final playing = speaking && ttsState.isSpeaking && !ttsState.isPaused;
    final initializing = speaking && ttsState.isInitializing;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MessageActionButton(
          key: const ValueKey('message_action_copy'),
          icon: HugeIcons.strokeRoundedCopy01,
          label: l10n.copy,
          onTap: () => copyMessageText(context, actions),
        ),
        if (actions.onRetry != null)
          MessageActionButton(
            key: const ValueKey('message_action_retry'),
            icon: HugeIcons.strokeRoundedRefresh,
            label: l10n.retry,
            onTap: actions.onRetry,
          ),
        MessageActionButton(
          key: const ValueKey('message_action_speak'),
          icon: speaking
              ? (playing
                    ? HugeIcons.strokeRoundedPauseCircle
                    : HugeIcons.strokeRoundedPlayCircle)
              : (initializing
                    ? HugeIcons.strokeRoundedClock01
                    : HugeIcons.strokeRoundedVolumeUp),
          label: speaking
              ? (playing ? l10n.pause : l10n.resume)
              : (initializing ? l10n.initializing : l10n.read_aloud),
          isActive: speaking,
          onTap: initializing ? null : () => toggleMessageSpeech(ref, actions),
        ),
        MessageActionButton(
          key: const ValueKey('message_action_more'),
          icon: HugeIcons.strokeRoundedMoreHorizontal,
          label: l10n.more,
          onTap: () => showMessageActionsSheet(context, actions),
        ),
      ],
    );
  }
}

class MessageActionButton extends StatelessWidget {
  const MessageActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  final List<List<dynamic>> icon;
  final String label;
  final VoidCallback? onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = isActive
        ? theme.colorScheme.primary
        : (isDark ? AppColors.darkMutedText : AppColors.lightMutedText);

    return IconButton(
      onPressed: onTap,
      tooltip: label,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      padding: EdgeInsets.zero,
      icon: HugeIcon(icon: icon, size: 18, color: color),
    );
  }
}
