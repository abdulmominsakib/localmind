import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/components/anchored_menu.dart';
import 'package:localmind/l10n/app_localizations.dart';
import '../../providers/saved_message_providers.dart';
import 'saved_messages_filters.dart';

/// Select and the list filter in one menu; a dot marks a filter other than
/// "All".
class SavedMessagesMenuButton extends ConsumerWidget {
  const SavedMessagesMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final filter = ref.watch(savedMessageListFilterProvider);

    Future<void> open(BuildContext buttonContext) async {
      final action = await showAnchoredMenu(buttonContext, [
        AnchoredMenuEntry(
          value: 'select',
          icon: HugeIcons.strokeRoundedCheckList,
          label: l10n.select,
        ),
        const AnchoredMenuEntry.divider(),
        AnchoredMenuEntry.header(l10n.filter_title),
        for (final option in SavedMessageListFilter.values)
          AnchoredMenuEntry(
            value: option.name,
            icon: option.icon,
            label: option.label(l10n),
            isChecked: filter == option,
          ),
      ]);
      if (action == null) return;
      if (action == 'select') {
        ref.read(savedMessageSelectionModeProvider.notifier).enable();
        return;
      }
      ref
          .read(savedMessageListFilterProvider.notifier)
          .setFilter(SavedMessageListFilter.values.byName(action));
    }

    return Builder(
      builder: (buttonContext) => IconButton(
        key: const ValueKey('saved_menu'),
        tooltip: l10n.options_tooltip,
        onPressed: () => open(buttonContext),
        icon: Badge(
          isLabelVisible: filter != SavedMessageListFilter.all,
          smallSize: 7,
          child: const HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical),
        ),
      ),
    );
  }
}
