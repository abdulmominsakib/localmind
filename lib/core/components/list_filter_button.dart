import 'package:flutter/material.dart';

class ListFilterOption<T> {
  const ListFilterOption({
    required this.value,
    required this.label,
    this.icon,
  });

  final T value;
  final String label;
  final IconData? icon;
}

class ListFilterButton<T> extends StatelessWidget {
  const ListFilterButton({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.tooltip,
    this.icon = Icons.filter_list_rounded,
    this.showBadgeWhenNotDefault = true,
  });

  final List<ListFilterOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final String? tooltip;
  final IconData icon;
  final bool showBadgeWhenNotDefault;

  bool get _hasActiveFilter {
    if (!showBadgeWhenNotDefault || options.isEmpty) return false;
    return selected != options.first.value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return IconButton(
      tooltip: tooltip,
      onPressed: () => _showFilterSheet(context),
      icon: Badge(
        isLabelVisible: _hasActiveFilter,
        smallSize: 8,
        child: Icon(
          icon,
          color: _hasActiveFilter
              ? theme.colorScheme.primary
              : theme.iconTheme.color,
        ),
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ...options.map(
                (option) => ListTile(
                  leading: option.icon != null
                      ? Icon(
                          option.icon,
                          color: selected == option.value
                              ? Theme.of(ctx).colorScheme.primary
                              : null,
                        )
                      : null,
                  title: Text(option.label),
                  trailing: selected == option.value
                      ? Icon(
                          Icons.check,
                          color: Theme.of(ctx).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    onChanged(option.value);
                    Navigator.pop(ctx);
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
