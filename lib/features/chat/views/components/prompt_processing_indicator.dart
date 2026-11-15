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

class PromptProcessingStatusBar extends ConsumerStatefulWidget {
  const PromptProcessingStatusBar({super.key});

  @override
  ConsumerState<PromptProcessingStatusBar> createState() =>
      _PromptProcessingStatusBarState();
}

class _PromptProcessingStatusBarState
    extends ConsumerState<PromptProcessingStatusBar> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant PromptProcessingStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  /// Starts the 200 ms repaint ticker whenever a live generation exists.
  ///
  /// This is driven from `build` as well as the lifecycle hooks: the bar is
  /// first built while `liveGeneration` is still null (idle composer), so
  /// initState alone never starts the ticker once a generation begins and the
  /// elapsed-time driven states would freeze on their first computed value.
  void _syncTimer([LiveGeneration? live]) {
    final active = live ?? ref.read(chatProvider).liveGeneration;
    if (active != null && _timer == null) {
      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (mounted) setState(() {});
      });
    } else if (active == null && _timer != null) {
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
    if (!enabled) return const SizedBox.shrink();

    final live = ref.watch(chatProvider.select((s) => s.liveGeneration));
    _syncTimer(live);
    final activeConv = ref.watch(conv.activeConversationProvider);
    final count = activeConv?.promptsProcessed ?? 0;

    if (live == null && count == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: live == null
                ? const SizedBox.shrink()
                : _LiveIndicator(live: live, muted: muted),
          ),
          if (count > 0) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: AppLocalizations.of(context)!.prompts_processed_label,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withValues(
                    alpha: 0.06,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedMessage01,
                      size: 12,
                      color: muted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LiveIndicator extends StatelessWidget {
  const _LiveIndicator({required this.live, required this.muted});

  final LiveGeneration live;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    switch (live.phase) {
      case LiveGenerationPhase.processingPrompt:
        return _ProcessingIndicator(live: live, muted: muted);
      case LiveGenerationPhase.generating:
        return _GeneratingIndicator(live: live, muted: muted);
      case LiveGenerationPhase.completed:
        return _CompletedIndicator(live: live, muted: muted);
    }
  }
}

class _ProcessingIndicator extends StatelessWidget {
  const _ProcessingIndicator({required this.live, required this.muted});

  final LiveGeneration live;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final now = DateTime.now();
    final elapsed = now.difference(live.startedAt).inMilliseconds;
    double progress;
    if (live.realPrefillProgress != null) {
      progress = live.realPrefillProgress!.clamp(0.0, 1.0);
    } else {
      final t = (elapsed / live.estimatedPrefillMs).clamp(0.0, 0.97);
      progress = Curves.easeOut.transform(t);
    }
    // The estimate never claims completion: prefill is still running until the
    // first token arrives, and rounding 0.999 would print "100%" too early.
    final pct = (progress * 100).round().clamp(0, 99);
    // Keep the arc in step with the label so its semantics do not report 100%
    // while prefill is still running either.
    final arc = pct / 100;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            value: arc,
            strokeWidth: 2,
            backgroundColor: (isDark ? Colors.white : Colors.black).withValues(
              alpha: 0.12,
            ),
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${l10n.processing_prompt_label} $pct%',
          style: TextStyle(fontSize: 11, color: muted),
        ),
      ],
    );
  }
}

class _GeneratingIndicator extends ConsumerWidget {
  const _GeneratingIndicator({required this.live, required this.muted});

  final LiveGeneration live;
  final Color muted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final first = live.firstTokenAt ?? live.startedAt;
    final elapsed = DateTime.now().difference(first).inMilliseconds;
    final outputChars = ref.watch(
      chatProvider.select((s) => s.streamingMessage?.content.length ?? 0),
    );
    final reasoningChars = ref.watch(
      chatProvider.select(
        (s) => s.streamingMessage?.reasoningContent?.length ?? 0,
      ),
    );

    if (outputChars == 0 && reasoningChars > 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${l10n.thinking}… ${(elapsed / 1000).toStringAsFixed(1)}s',
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ],
      );
    }

    final tokens = (outputChars / 4).round();
    final tps = elapsed > 0 ? tokens / (elapsed / 1000) : 0.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${l10n.generating_label} ${tps.toStringAsFixed(1)} tok/s · ${(elapsed / 1000).toStringAsFixed(1)}s',
          style: TextStyle(fontSize: 11, color: muted),
        ),
      ],
    );
  }
}

class _CompletedIndicator extends StatelessWidget {
  const _CompletedIndicator({required this.live, required this.muted});

  final LiveGeneration live;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final completedAt = live.completedAt;
    if (completedAt == null) return const SizedBox.shrink();
    final age = DateTime.now().difference(completedAt).inMilliseconds;
    if (age > 2500) return const SizedBox.shrink();
    final out = live.outputTokens ?? 0;
    final tps = live.tokensPerSecond;
    final genMs = live.generationTimeMs ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HugeIcon(
          icon: HugeIcons.strokeRoundedCheckmarkCircle01,
          size: 12,
          color: muted,
        ),
        const SizedBox(width: 6),
        Text(
          '$out tok · ${tps?.toStringAsFixed(1) ?? "0.0"} tok/s · ${(genMs / 1000).toStringAsFixed(1)}s',
          style: TextStyle(fontSize: 11, color: muted),
        ),
      ],
    );
  }
}
