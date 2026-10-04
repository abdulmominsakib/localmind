import 'package:flutter/material.dart';
import 'package:localmind/core/theme/colors.dart';

/// Small outlined pills under the new-chat heading: whether a model is
/// ready, and which kind of server will answer.
class NewChatStatusTags extends StatelessWidget {
  const NewChatStatusTags({
    super.key,
    required this.status,
    required this.isReady,
    this.provider,
  });

  final String status;
  final bool isReady;
  final String? provider;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;

    return Wrap(
      alignment: .center,
      spacing: 8,
      runSpacing: 8,
      children: [
        NewChatTag(
          label: status,
          leading: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: .circle,
              color: isReady ? AppColors.success : muted,
            ),
          ),
        ),
        if (provider != null) NewChatTag(label: provider!),
      ],
    );
  }
}

class NewChatTag extends StatelessWidget {
  const NewChatTag({super.key, required this.label, this.leading});

  final String label;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const .symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: .circular(999),
        border: Border.all(
          color: isDark ? const Color(0xFF3A3A3A) : AppColors.lightBorder,
        ),
      ),
      child: Row(
        mainAxisSize: .min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: isDark
                  ? const Color(0xFFC8C8C8)
                  : AppColors.lightMutedText,
            ),
          ),
        ],
      ),
    );
  }
}
