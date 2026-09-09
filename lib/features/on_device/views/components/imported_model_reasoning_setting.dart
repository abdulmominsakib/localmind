import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/models/on_device_model.dart';
import '../../providers/on_device_providers.dart';

/// Persisted generation control, available even when GGUF metadata does not
/// advertise thinking support. Changes apply to the next response.
class ImportedModelReasoningSetting extends ConsumerStatefulWidget {
  const ImportedModelReasoningSetting({super.key, required this.model});

  final OnDeviceModel model;

  @override
  ConsumerState<ImportedModelReasoningSetting> createState() =>
      _ImportedModelReasoningSettingState();
}

class _ImportedModelReasoningSettingState
    extends ConsumerState<ImportedModelReasoningSetting> {
  bool _saving = false;
  String? _error;

  Future<void> _save(String? value) async {
    if (value == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(importedGgufModelsProvider.notifier)
          .updateReasoning(
            widget.model.id,
            value == 'default' ? null : value == 'on',
          );
    } catch (_) {
      if (mounted) {
        _error = AppLocalizations.of(context)!.model_reasoning_save_error;
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey('${widget.model.reasoningEnabled}-$_saving-$_error'),
            initialValue: switch (widget.model.reasoningEnabled) {
              true => 'on',
              false => 'off',
              null => 'default',
            },
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.thinking_mode_title,
              helperText: l10n.model_reasoning_help,
              helperMaxLines: 3,
              errorText: _error,
              errorMaxLines: 2,
            ),
            items: [
              DropdownMenuItem(
                value: 'default',
                child: Text(l10n.model_reasoning_default),
              ),
              DropdownMenuItem(
                value: 'on',
                child: Text(l10n.model_reasoning_on),
              ),
              DropdownMenuItem(
                value: 'off',
                child: Text(l10n.reasoning_effort_off),
              ),
            ],
            onChanged: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}
