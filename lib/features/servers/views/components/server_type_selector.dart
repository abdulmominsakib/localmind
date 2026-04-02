import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../../core/models/enums.dart';

class ServerTypeSelector extends StatelessWidget {
  final ServerType selectedType;
  final ValueChanged<ServerType> onChanged;

  const ServerTypeSelector({
    super.key,
    required this.selectedType,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final types = [
      (
        ServerType.lmStudio,
        'LM Studio',
        HugeIcons.strokeRoundedAiComputer,
        Colors.blue,
      ),
      (
        ServerType.openAICompatible,
        'OpenAI',
        HugeIcons.strokeRoundedApi,
        Colors.green,
      ),
      (
        ServerType.ollama,
        'Ollama',
        HugeIcons.strokeRoundedPencilEdit02,
        Colors.orange,
      ),
      (
        ServerType.openRouter,
        'OpenRouter',
        HugeIcons.strokeRoundedCloud,
        Colors.purple,
      ),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.0,
      children: types.map((item) {
        final type = item.$1;
        final label = item.$2;
        final icon = item.$3;
        final accentColor = item.$4;
        final isSelected = selectedType == type;

        return GestureDetector(
          onTap: () => onChanged(type),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? accentColor.withValues(alpha: 0.15)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? accentColor.withValues(alpha: 0.5)
                    : colorScheme.outline.withValues(alpha: 0.3),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? accentColor.withValues(alpha: 0.2)
                        : colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: HugeIcon(
                    icon: icon,
                    size: 18,
                    color: isSelected ? accentColor : colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? accentColor : colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
