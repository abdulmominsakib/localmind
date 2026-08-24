import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/providers/app_providers.dart';

class BackendSelector extends ConsumerWidget {
  const BackendSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider);
    final currentBackend = settings.preferredBackend;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.inference_backend,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...PreferredBackend.values.map((backend) {
          final isSelected = currentBackend == backend;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ShadButton.outline(
              width: double.infinity,
              onPressed: () => ref
                  .read(settingsProvider.notifier)
                  .setPreferredBackend(backend),
              child: Row(
                children: [
                  HugeIcon(
                    icon: isSelected
                        ? HugeIcons.strokeRoundedCheckmarkCircle01
                        : HugeIcons.strokeRoundedCircle,
                    size: 20,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          backend.name.toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          _backendDescription(backend, context),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  String _backendDescription(PreferredBackend backend, BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (backend) {
      case PreferredBackend.cpu:
        return l10n.backend_cpu_desc;
      case PreferredBackend.gpu:
        return l10n.backend_gpu_desc;
      case PreferredBackend.npu:
        return 'Neural Processing Unit';
    }
  }
}
