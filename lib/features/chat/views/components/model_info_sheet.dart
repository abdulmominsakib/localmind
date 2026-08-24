import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/chat/providers/chat_params_providers.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/l10n/app_localizations.dart';

Future<void> showModelInfoSheet(
  BuildContext context,
  WidgetRef ref,
  String modelId,
) async {
  final l10n = AppLocalizations.of(context)!;
  final server = ref.read(activeServerProvider);
  ModelInfo? model;
  if (server != null) {
    try {
      final models = await ref.read(availableModelsProvider(server.id).future);
      for (final m in models) {
        if (m is ModelInfo && m.id == modelId) {
          model = m;
          break;
        }
      }
    } catch (_) {
      // Model info fetch failed, fallback to basic identifier display
    }
  }

  if (!context.mounted) return;

  final displayName = model?.displayName ?? modelId;
  final contextLength = ref.read(chatParamsProvider).contextLength;
  final identifier = model?.id ?? modelId;

  final capabilities = <String>[
    if (model?.supportsVision == true) l10n.lm_studio_vision,
    if (model?.supportsReasoning == true) l10n.lm_studio_reasoning,
    if (model?.supportsToolUse == true) l10n.lm_studio_tool_use,
  ];

  await showShadSheet(
    context: context,
    builder: (ctx) => ShadSheet(
      title: Text(l10n.model_info),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModelInfoRow(label: l10n.model_name, value: displayName),
          _ModelInfoRow(label: l10n.model_identifier, value: identifier),
          if (capabilities.isNotEmpty)
            _ModelInfoRow(
              label: l10n.model_capabilities,
              value: capabilities.join(', '),
            ),
          _ModelInfoRow(
            label: l10n.context_length,
            value: contextLength.toString(),
          ),
          if (model?.serverType == ServerType.openRouter &&
              model?.pricingLabel != null)
            _ModelInfoRow(
              label: l10n.model_api_pricing,
              value: model!.isPricingFree
                  ? l10n.openrouter_pricing_free
                  : '${model.formattedInputPrice ?? '—'} / '
                        '${model.formattedOutputPrice ?? '—'}',
            ),
        ],
      ),
    ),
  );
}

class _ModelInfoRow extends StatelessWidget {
  const _ModelInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      title: Text(label, style: const TextStyle(fontSize: 12)),
      subtitle: SelectableText(value),
      trailing: IconButton(
        icon: const HugeIcon(icon: HugeIcons.strokeRoundedCopy, size: 18),
        tooltip: l10n.copy,
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: value));
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l10n.copied_to_clipboard)));
          }
        },
      ),
    );
  }
}
