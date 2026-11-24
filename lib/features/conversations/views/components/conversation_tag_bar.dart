import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/components/folder_filter_bar.dart';
import '../../providers/conversation_providers.dart';

/// One chip per tag in use. Tapping a tag narrows the history to the chats
/// carrying it; tapping it again clears the filter. Hidden until a chat has
/// a tag, so history looks unchanged for people who don't use them.
class ConversationTagBar extends ConsumerWidget {
  const ConversationTagBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(conversationTagsProvider);
    final selected = ref.watch(historyTagFilterProvider);
    if (tags.isEmpty && selected == null) return const SizedBox.shrink();

    final notifier = ref.read(historyTagFilterProvider.notifier);
    final visible = [
      ...tags,
      // A filter on a tag that was just removed from its last chat stays
      // visible so it can be cleared.
      if (selected != null &&
          !tags.any((t) => t.toLowerCase() == selected.toLowerCase()))
        selected,
    ];

    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          spacing: 8,
          children: [
            for (final tag in visible)
              FolderPill(
                key: ValueKey('tag_filter_$tag'),
                label: tag,
                icon: HugeIcons.strokeRoundedTag01,
                selected: selected?.toLowerCase() == tag.toLowerCase(),
                onTap: () => notifier.setFilter(
                  selected?.toLowerCase() == tag.toLowerCase() ? null : tag,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
