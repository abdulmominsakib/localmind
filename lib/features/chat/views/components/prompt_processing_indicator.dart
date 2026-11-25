import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../../core/theme/colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../providers/chat_providers.dart';
import '../../../conversations/providers/conversation_providers.dart' as conv;
import '../../data/models/live_generation.dart';
import 'heartbeat_dot.dart';

/// How long the finished reply's numbers stay above the composer.
const liveStatusCompletedHold = Duration(milliseconds: 2500);

/// A small centred line above the composer's input row while a reply is
/// produced: what is happening, the live numbers, and the conversation's
/// processed-prompt count. It takes no room when there is nothing to show,
/// and the field below stays free to type in.
class PromptProcessingStatusBar extends ConsumerStatefulWidget {
  const PromptProcessingStatusBar({super.key});

  @override
  ConsumerState<PromptProcessingStatusBar> createState() =>
      _PromptProcessingStatusBarState();
}

class _PromptProcessingStatusBarState
    extends ConsumerState<PromptProcessingStatusBar> {
  Timer? _timer;

  /// Repaints every 200 ms while a live generation exists, so elapsed-time
  /// driven numbers move. Driven from `build`, because the bar is first built
  /// while idle and initState alone would never start the ticker.
  void _syncTimer(bool active) {
    if (active && _timer == null) {
      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (mounted) setState(() {});
      });
    } else if (!active && _timer != null) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(
      settingsProvider.select((s) => s.showPromptProcessingIndicator),
    );
    final live = ref.watch(chatProvider.select((s) => s.liveGeneration));
    _syncTimer(enabled && live != null);
    if (!enabled || live == null) return const SizedBox.shrink();

    final completedAt = live.completedAt;
    if (live.phase == LiveGenerationPhase.completed &&
        (completedAt == null ||
            DateTime.now().difference(completedAt) > liveStatusCompletedHold)) {
      return const SizedBox.shrink();
    }

    final count = ref.watch(
      conv.activeConversationProvider.select((c) => c?.promptsProcessed ?? 0),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: ComposerLiveStatus(live: live)),
            if (count > 0) ...[
              const SizedBox(width: 8),
              PromptCountChip(count: count),
            ],
          ],
        ),
      ),
    );
  }
}

/// The conversation's processed-prompt count, shown beside the live status.
class PromptCountChip extends StatelessWidget {
  const PromptCountChip({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;
    return Tooltip(
      message: AppLocalizations.of(context)!.prompts_processed_label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedMessage01,
              size: 11,
              color: muted,
            ),
            const SizedBox(width: 3),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                color: muted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The live status line: an activity mark, what is happening, and quieter
/// numbers beside it.
class ComposerLiveStatus extends ConsumerWidget {
  const ComposerLiveStatus({super.key, required this.live});

  final LiveGeneration live;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;
    final dotColor = muted;

    switch (live.phase) {
      case LiveGenerationPhase.processingPrompt:
        final pct = _prefillPercent(live);
        return LiveStatusLine(
          key: const ValueKey('live_status_processing'),
          lead: SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              value: pct / 100,
              strokeWidth: 1.5,
              strokeCap: StrokeCap.round,
              backgroundColor: muted.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(muted),
            ),
          ),
          label: _withoutEllipsis(l10n.processing_prompt_label),
          detail: '$pct%',
        );
      case LiveGenerationPhase.generating:
        final first = live.firstTokenAt ?? live.startedAt;
        final elapsedMs = DateTime.now().difference(first).inMilliseconds;
        final outputChars = ref.watch(
          chatProvider.select((s) => s.streamingMessage?.content.length ?? 0),
        );
        final reasoningChars = ref.watch(
          chatProvider.select(
            (s) => s.streamingMessage?.reasoningContent?.length ?? 0,
          ),
        );
        final thinking = outputChars == 0 && reasoningChars > 0;
        final tokens = (outputChars / 4).round();
        final tps = elapsedMs > 0 ? tokens / (elapsedMs / 1000) : 0.0;
        return LiveStatusLine(
          key: const ValueKey('live_status_generating'),
          lead: HeartbeatDot(size: 5, color: dotColor),
          label: thinking
              ? l10n.thinking
              : _withoutEllipsis(l10n.generating_label),
          detail: thinking
              ? formatLiveDuration(elapsedMs)
              : '${formatTokensPerSecond(tps)} tok/s · '
                    '${formatLiveDuration(elapsedMs)}',
        );
      case LiveGenerationPhase.completed:
        final tps = live.tokensPerSecond;
        return LiveStatusLine(
          key: const ValueKey('live_status_completed'),
          lead: HugeIcon(
            icon: HugeIcons.strokeRoundedTick02,
            size: 12,
            color: muted,
          ),
          label: l10n.done,
          detail: [
            '${live.outputTokens ?? 0} tok',
            if (tps != null) '${formatTokensPerSecond(tps)} tok/s',
            formatLiveDuration(live.generationTimeMs ?? 0),
          ].join(' · '),
        );
    }
  }
}

/// One status line: [lead] in a fixed slot, [label] in the field's text
/// colour, then [detail] muted with steady-width digits.
class LiveStatusLine extends StatelessWidget {
  const LiveStatusLine({
    super.key,
    required this.lead,
    required this.label,
    required this.detail,
  });

  final Widget lead;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 12, height: 12, child: Center(child: lead)),
        const SizedBox(width: 6),
        Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

int _prefillPercent(LiveGeneration live) {
  final double progress;
  if (live.realPrefillProgress != null) {
    progress = live.realPrefillProgress!.clamp(0.0, 1.0);
  } else {
    final elapsed = DateTime.now().difference(live.startedAt).inMilliseconds;
    final t = (elapsed / live.estimatedPrefillMs).clamp(0.0, 0.97);
    progress = Curves.easeOut.transform(t);
  }
  // Prefill is still running until the first token: never claim 100%.
  return (progress * 100).round().clamp(0, 99);
}

String _withoutEllipsis(String label) =>
    label.replaceFirst(RegExp(r'\s*(…|\.\.\.)$'), '');

/// Whole numbers from 10 tok/s up, so the figure does not flicker.
@visibleForTesting
String formatTokensPerSecond(double tps) =>
    tps >= 10 ? tps.toStringAsFixed(0) : tps.toStringAsFixed(1);

/// `4.2s` under a minute, `1m 05s` after.
@visibleForTesting
String formatLiveDuration(int ms) {
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
  final seconds = ms ~/ 1000;
  return '${seconds ~/ 60}m ${(seconds % 60).toString().padLeft(2, '0')}s';
}
