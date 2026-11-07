import 'package:flutter/material.dart';

import '../../providers/unified_model_search_provider.dart';
import '../../utils/model_modality_classifier.dart';

class ModelSearchFilterBar extends StatelessWidget {
  const ModelSearchFilterBar({
    super.key,
    required this.state,
    required this.notifier,
  });

  final UnifiedModelSearchState state;
  final UnifiedModelSearchNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Model type selector
        Wrap(
          spacing: 8,
          children: UnifiedModelTypeFilter.values.map((t) {
            final selected = state.modelType == t;
            return ChoiceChip(
              label: Text(_modelTypeLabel(t)),
              selected: selected,
              onSelected: (_) => notifier.setModelType(t),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        // Modality selector
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('All'),
              selected: state.modality == null,
              onSelected: (_) => notifier.setModality(null),
            ),
            ...ModelModality.values
                .where((m) => m != ModelModality.unknown)
                .map((m) => ChoiceChip(
                      label: Text(_modalityLabel(m)),
                      selected: state.modality == m,
                      onSelected: (_) => notifier.setModality(m),
                    )),
          ],
        ),
        const SizedBox(height: 8),
        // Param size range
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Min B',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
                onChanged: notifier.setMinParam,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Max B',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
                onChanged: notifier.setMaxParam,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Checkbox(
              value: state.includeUnknownParam,
              onChanged: (v) => notifier.setIncludeUnknownParam(v ?? false),
            ),
            const Text('Include unknown sizes'),
            const Spacer(),
            Row(
              children: [
                const Text('Split models'),
                Switch(
                  value: state.showSplitModels,
                  onChanged: notifier.setShowSplitModels,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  String _modelTypeLabel(UnifiedModelTypeFilter t) {
    switch (t) {
      case UnifiedModelTypeFilter.both:
        return 'Both';
      case UnifiedModelTypeFilter.litert:
        return 'LiteRT';
      case UnifiedModelTypeFilter.gguf:
        return 'Llama.cpp (GGUF)';
      case UnifiedModelTypeFilter.none:
        return 'None';
    }
  }

  String _modalityLabel(ModelModality m) {
    switch (m) {
      case ModelModality.text:
        return 'Text';
      case ModelModality.vision:
        return 'Vision';
      case ModelModality.audio:
        return 'Audio';
      case ModelModality.embedding:
        return 'Embedding';
      case ModelModality.unknown:
        return 'Unknown';
    }
  }
}
