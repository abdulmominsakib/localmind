import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/l10n/app_localizations.dart';

import '../../chat/providers/model_selection_providers.dart';
import '../data/model_vision_overrides.dart';

/// Manual "this model accepts images" toggle for servers that don't expose
/// capability metadata (plain OpenAI-compatible endpoints, vLLM, custom
/// gateways). Persisted per (server, model); the active chat target's
/// effective model is refreshed immediately so the assistant's vision gate
/// and the voice-mode Screen pill follow along.
class ModelVisionOverrideRow extends ConsumerWidget {
  const ModelVisionOverrideRow({
    required this.serverId,
    required this.modelId,
    required this.baseSupportsVision,
    super.key,
  });

  final String serverId;
  final String modelId;

  /// What the server catalog itself reports for this model.
  final bool baseSupportsVision;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = ModelVisionOverridesNotifier.key(serverId, modelId);
    final effective = ref.watch(
      modelVisionOverridesProvider.select((overrides) => overrides[key]),
    );
    final l10n = AppLocalizations.of(context)!;

    return SwitchListTile(
      title: Text(
        l10n.model_vision_support_label,
        style: const TextStyle(fontSize: 12),
      ),
      subtitle: Text(
        l10n.model_vision_support_desc,
        style: const TextStyle(fontSize: 11),
      ),
      value: effective ?? baseSupportsVision,
      onChanged: (value) async {
        // Returning the switch in line with the server's own report clears
        // the override so future catalog refreshes stay authoritative.
        await ref
            .read(modelVisionOverridesProvider.notifier)
            .setVision(
              serverId,
              modelId,
              value == baseSupportsVision ? null : value,
            );
        final selected = ref.read(selectedModelProvider);
        if (selected != null &&
            selected.serverId == serverId &&
            selected.id == modelId) {
          ref
              .read(selectedModelProvider.notifier)
              .setModel(selected.copyWith(supportsVision: value));
        }
      },
    );
  }
}
