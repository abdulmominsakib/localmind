import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/l10n/app_localizations.dart';
import '../providers/model_picker_providers.dart';

class ModelSearchField extends ConsumerWidget {
  const ModelSearchField({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final searchQuery = ref.watch(modelSearchQueryProvider);

    return TextField(
      decoration: InputDecoration(
        hintText: l10n.search_models_hint,
        prefixIcon: const Center(
          widthFactor: 1.0,
          heightFactor: 1.0,
          child: HugeIcon(icon: HugeIcons.strokeRoundedSearch01, size: 20),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        suffixIcon: searchQuery.isNotEmpty
            ? IconButton(
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedCancel01,
                  size: 18,
                ),
                onPressed: () =>
                    ref.read(modelSearchQueryProvider.notifier).clear(),
              )
            : null,
      ),
      onChanged: (q) => ref.read(modelSearchQueryProvider.notifier).setQuery(q),
    );
  }
}
