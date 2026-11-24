import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/l10n/app_localizations.dart';
import '../../data/models/conversation.dart';
import '../../providers/conversation_providers.dart';

/// Edits the tags on one chat. Changes are saved when the sheet's Done
/// button is pressed.
Future<void> showConversationTagsSheet(
  BuildContext context,
  Conversation conversation,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ConversationTagsEditor(conversation: conversation),
  );
}

class ConversationTagsEditor extends ConsumerStatefulWidget {
  const ConversationTagsEditor({super.key, required this.conversation});

  final Conversation conversation;

  @override
  ConsumerState<ConversationTagsEditor> createState() =>
      _ConversationTagsEditorState();
}

class _ConversationTagsEditorState
    extends ConsumerState<ConversationTagsEditor> {
  late List<String> _tags;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tags = [...widget.conversation.tags];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add(String raw) {
    setState(() {
      _tags = normalizeConversationTags([..._tags, ...raw.split(',')]);
      _controller.clear();
    });
  }

  void _remove(String tag) {
    setState(() => _tags = _tags.where((t) => t != tag).toList());
  }

  Future<void> _save() async {
    final pending = _controller.text.trim();
    final tags = normalizeConversationTags([
      ..._tags,
      if (pending.isNotEmpty) ...pending.split(','),
    ]);
    final navigator = Navigator.of(context);
    await ref
        .read(conversationsProvider.notifier)
        .setTags(widget.conversation.id, tags);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;
    final lowerTags = _tags.map((t) => t.toLowerCase()).toSet();
    final suggestions = ref
        .watch(conversationTagsProvider)
        .where((t) => !lowerTags.contains(t.toLowerCase()))
        .toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.conversation_tags,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.darkPrimaryText
                  : AppColors.lightPrimaryText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.conversation_tags_desc,
            style: TextStyle(fontSize: 13, color: muted),
          ),
          const SizedBox(height: 14),
          if (_tags.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in _tags)
                  InputChip(
                    key: ValueKey('tag_chip_$tag'),
                    avatar: const HugeIcon(
                      icon: HugeIcons.strokeRoundedTag01,
                      size: 14,
                    ),
                    label: Text(tag),
                    deleteIcon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedCancel01,
                      size: 14,
                    ),
                    onDeleted: () => _remove(tag),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            key: const ValueKey('tag_input'),
            controller: _controller,
            autofocus: _tags.isEmpty,
            maxLength: maxConversationTagLength,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: l10n.conversation_tags_add_hint,
              counterText: '',
              prefixIcon: const Padding(
                padding: EdgeInsets.all(12),
                child: HugeIcon(icon: HugeIcons.strokeRoundedAdd01, size: 18),
              ),
            ),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) _add(value);
            },
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              l10n.conversation_tags_existing,
              style: TextStyle(fontSize: 12.5, color: muted),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in suggestions)
                  ActionChip(
                    key: ValueKey('tag_suggestion_$tag'),
                    avatar: const HugeIcon(
                      icon: HugeIcons.strokeRoundedAdd01,
                      size: 14,
                    ),
                    label: Text(tag),
                    onPressed: () => _add(tag),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('tag_save'),
            onPressed: _save,
            child: Text(l10n.done),
          ),
        ],
      ),
    );
  }
}
