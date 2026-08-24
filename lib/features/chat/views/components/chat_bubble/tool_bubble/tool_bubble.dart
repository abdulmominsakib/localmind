import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/l10n/app_localizations.dart';

class ToolBubble extends StatelessWidget {
  const ToolBubble({super.key, required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        margin: const EdgeInsetsDirectional.only(
          start: 8,
          end: 48,
          top: 4,
          bottom: 4,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2937) : const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF374151) : const Color(0xFFC7D2FE),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedTools,
                  size: 14,
                  color: isDark
                      ? AppColors.darkMutedText
                      : AppColors.lightMutedText,
                ),
                const SizedBox(width: 4),
                Text(
                  message.toolCallId != null
                      ? l10n.tool_label(message.toolCallId!)
                      : l10n.tool_unknown,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? AppColors.darkMutedText
                        : AppColors.lightMutedText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              message.content,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white : Colors.black87,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
