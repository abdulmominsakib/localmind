import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/l10n/app_localizations.dart';
import '../providers/model_picker_providers.dart';

class ModelSortControl extends ConsumerWidget {
  const ModelSortControl({super.key});

  String _labelFor(AppLocalizations l10n, ModelSortOption option) {
    switch (option) {
      case ModelSortOption.favorites:
        return l10n.sort_by_favorites;
      case ModelSortOption.nameAsc:
        return l10n.sort_by_name;
      case ModelSortOption.sizeAsc:
        return l10n.sort_by_size_smallest;
      case ModelSortOption.sizeDesc:
        return l10n.sort_by_size_largest;
      case ModelSortOption.contextDesc:
        return l10n.sort_by_context_length;
    }
  }

  IconData _iconFor(ModelSortOption option) {
    switch (option) {
      case ModelSortOption.favorites:
        return Icons.star_outline;
      case ModelSortOption.nameAsc:
        return Icons.sort_by_alpha;
      case ModelSortOption.sizeAsc:
      case ModelSortOption.sizeDesc:
        return Icons.sd_storage_outlined;
      case ModelSortOption.contextDesc:
        return Icons.view_column_outlined;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final current = ref.watch(modelSortOptionProvider);

    return PopupMenuButton<ModelSortOption>(
      tooltip: l10n.sort_models_tooltip,
      initialValue: current,
      onSelected: (option) =>
          ref.read(modelSortOptionProvider.notifier).setOption(option),
      icon: const Icon(Icons.sort, size: 20),
      itemBuilder: (context) => ModelSortOption.values.map((option) {
        return PopupMenuItem(
          value: option,
          child: Row(
            children: [
              Icon(
                _iconFor(option),
                size: 18,
                color: option == current
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              const SizedBox(width: 10),
              Text(
                _labelFor(l10n, option),
                style: TextStyle(
                  fontWeight:
                      option == current ? FontWeight.w600 : FontWeight.normal,
                  color: option == current
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
