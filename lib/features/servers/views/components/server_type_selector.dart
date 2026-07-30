import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/l10n/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final types = [
      (
        ServerType.lmStudio,
        l10n.server_type_lm_studio,
        HugeIcons.strokeRoundedAiComputer,
        Colors.blue,
      ),
      (
        ServerType.openAICompatible,
        l10n.server_type_openai_display,
        HugeIcons.strokeRoundedApi,
        Colors.green,
      ),
      (
        ServerType.ollama,
        l10n.server_type_ollama,
        HugeIcons.strokeRoundedPencilEdit02,
        Colors.orange,
      ),
      (
        ServerType.ollamaCloud,
        l10n.server_type_ollama_cloud,
        HugeIcons.strokeRoundedAiCloud,
        Colors.deepOrange,
      ),
      (
        ServerType.openRouter,
        l10n.server_type_openrouter,
        HugeIcons.strokeRoundedCloud,
        Colors.purple,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemAspectRatio = constraints.maxWidth >= 420 ? 2.15 : 1.95;

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: itemAspectRatio,
          children: types.map((item) {
            final type = item.$1;
            final label = item.$2;
            final icon = item.$3;
            final accentColor = item.$4;
            final isSelected = selectedType == type;

            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onChanged(type),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? accentColor.withValues(alpha: 0.14)
                        : colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.38,
                          ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? accentColor.withValues(alpha: 0.58)
                          : colorScheme.outline.withValues(alpha: 0.24),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? accentColor.withValues(alpha: 0.20)
                                    : colorScheme.surface,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: HugeIcon(
                                icon: icon,
                                size: 18,
                                color: isSelected
                                    ? accentColor
                                    : colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              label,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 15,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: isSelected
                                    ? accentColor
                                    : colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        PositionedDirectional(
                          top: 6,
                          end: 6,
                          child: HugeIcon(icon: 
                            HugeIcons.strokeRoundedCheckmarkCircle01,
                            size: 17,
                            color: accentColor,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
