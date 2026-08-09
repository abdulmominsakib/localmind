import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/chat/providers/chat_providers.dart';
import 'package:localmind/l10n/app_localizations.dart';

class TokenUsageIndicator extends ConsumerWidget {
  const TokenUsageIndicator({super.key, required this.totalTokenCount});

  final int totalTokenCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // LM Studio's native chat API accepts context_length per request. Use the
    // configured per-chat value here so the indicator reflects the request the
    // app will actually send instead of a stale load-time model value.
    final contextLength = ref.watch(
      chatParamsProvider.select((params) => params.contextLength),
    );

    // totalTokenCount only updates once a response finishes (it's the real
    // server-reported count), so while one is streaming in, grow the ring
    // with a rough chars-per-token estimate of the in-progress reply —
    // corrected back to the exact figure the moment the stream ends.
    final isStreaming = ref.watch(chatProvider.select((s) => s.isStreaming));
    final streamingLength = ref.watch(
      chatProvider.select((s) => s.streamingMessage?.content.length ?? 0),
    );
    final estimatedTokenCount = isStreaming
        ? totalTokenCount + (streamingLength / 4).round()
        : totalTokenCount;

    final ratio = contextLength > 0
        ? (estimatedTokenCount / contextLength).clamp(0.0, 1.0)
        : 0.0;
    final ringColor = ratio >= 0.9 ? Colors.red : theme.colorScheme.primary;

    return GestureDetector(
      onTap: () => _showTokenUsageSheet(context, contextLength, ratio),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
        height: 20,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                value: ratio,
                strokeWidth: 2,
                backgroundColor: (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(ringColor),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${(ratio * 100).round()}%',
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTokenUsageSheet(
    BuildContext context,
    int contextLength,
    double ratio,
  ) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        final sheetTheme = Theme.of(ctx);
        final isDark = sheetTheme.brightness == Brightness.dark;
        final muted = isDark
            ? AppColors.darkMutedText
            : AppColors.lightMutedText;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.token_usage_title,
                  style: sheetTheme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _usageRow(l10n.total_tokens_label, '$totalTokenCount', muted),
                _usageRow(l10n.context_length, '$contextLength', muted),
                _usageRow(
                  l10n.usage_percent_label,
                  '${(ratio * 100).toStringAsFixed(1)}%',
                  muted,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _usageRow(String label, String value, Color muted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: muted)),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
