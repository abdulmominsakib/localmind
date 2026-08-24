import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/chat/utils/message_variants.dart';

class MessageVariantNavigator extends StatelessWidget {
  const MessageVariantNavigator({
    super.key,
    required this.message,
    required this.allMessages,
    required this.onCycle,
  });

  final Message message;
  final List<Message> allMessages;
  final void Function(int direction) onCycle;

  @override
  Widget build(BuildContext context) {
    final variants = MessageVariants.variantsForMessage(allMessages, message);
    if (variants.length <= 1) return const SizedBox.shrink();

    final currentIndex = MessageVariants.activeVariantIndex(variants);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: currentIndex > 0 ? () => onCycle(-1) : null,
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedArrowLeft01,
              size: 18,
              color: muted,
            ),
          ),
          Text(
            '${currentIndex + 1} / ${variants.length}',
            style: TextStyle(
              fontSize: 11,
              color: muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: currentIndex < variants.length - 1
                ? () => onCycle(1)
                : null,
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedArrowRight01,
              size: 18,
              color: muted,
            ),
          ),
        ],
      ),
    );
  }
}
