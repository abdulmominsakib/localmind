import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:localmind/l10n/app_localizations.dart';
import '../../providers/unified_model_search_provider.dart';
import '../../utils/filter_summary.dart';
import '../../utils/model_modality_classifier.dart';

class ModelSearchFilterBar extends StatefulWidget {
  const ModelSearchFilterBar({
    super.key,
    required this.state,
    required this.notifier,
  });

  final UnifiedModelSearchState state;
  final UnifiedModelSearchNotifier notifier;

  @override
  State<ModelSearchFilterBar> createState() => _ModelSearchFilterBarState();
}

class _ModelSearchFilterBarState extends State<ModelSearchFilterBar> {
  bool _expanded = false;

  UnifiedModelSearchState get state => widget.state;
  UnifiedModelSearchNotifier get notifier => widget.notifier;

  bool get _litertEnabled =>
      state.modelType == UnifiedModelTypeFilter.litert ||
      state.modelType == UnifiedModelTypeFilter.both;

  bool get _ggufEnabled =>
      state.modelType == UnifiedModelTypeFilter.gguf ||
      state.modelType == UnifiedModelTypeFilter.both;

  int get _activeCount {
    int c = 0;
    if (!_litertEnabled || !_ggufEnabled) c++;
    if (state.modality != null) c++;
    if (state.minParamBillions != null || state.maxParamBillions != null) c++;
    if (state.includeUnknownParam) c++;
    if (state.showSplitModels) c++;
    return c;
  }

  String get _summary {
    final l10n = AppLocalizations.of(context)!;
    return formatFilterSummary(
      litertEnabled: _litertEnabled,
      ggufEnabled: _ggufEnabled,
      modalityLabel: state.modality != null
          ? _modalityLabel(state.modality!, l10n)
          : null,
      minParamBillions: state.minParamBillions,
      maxParamBillions: state.maxParamBillions,
      litertLabel: l10n.onDeviceModelTypeLitert,
      ggufLabel: l10n.onDeviceModelTypeGguf,
      bothLabel: l10n.onDeviceModelTypeBoth,
      noneLabel: l10n.onDeviceModelTypeNone,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text(
                  AppLocalizations.of(context)!.onDeviceFilters,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(width: 8),
                if (_activeCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$_activeCount',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                const Spacer(),
                if (!_expanded && _activeCount > 0)
                  Flexible(
                    child: Text(
                      _summary,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                const SizedBox(width: 4),
                HugeIcon(
                  icon: _expanded
                      ? HugeIcons.strokeRoundedArrowUp01
                      : HugeIcons.strokeRoundedArrowDown01,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          // Framework
          Text(AppLocalizations.of(context)!.onDeviceFramework,
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: Text(AppLocalizations.of(context)!.onDeviceModelTypeLitert),
                selected: _litertEnabled,
                onSelected: (v) => notifier.setLitertEnabled(v),
              ),
              FilterChip(
                label: Text(AppLocalizations.of(context)!.onDeviceModelTypeGguf),
                selected: _ggufEnabled,
                onSelected: (v) => notifier.setGgufEnabled(v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Modality
          Text(AppLocalizations.of(context)!.onDeviceModality,
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text(AppLocalizations.of(context)!.onDeviceModalityAll),
                selected: state.modality == null,
                onSelected: (_) => notifier.setModality(null),
              ),
              ...ModelModality.values.map((m) => ChoiceChip(
                    label: Text(_modalityLabel(m, AppLocalizations.of(context)!)),
                    selected: state.modality == m,
                    onSelected: (_) => notifier.setModality(m),
                  )),
            ],
          ),
          const SizedBox(height: 8),
          // Param size
          Text(AppLocalizations.of(context)!.onDeviceParameterSize,
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.onDeviceMinParam,
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
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.onDeviceMaxParam,
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
          Wrap(
            spacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: state.includeUnknownParam,
                    onChanged: (v) =>
                        notifier.setIncludeUnknownParam(v ?? false),
                  ),
                  Text(AppLocalizations.of(context)!.onDeviceIncludeUnknownSizes),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(AppLocalizations.of(context)!.onDeviceSplitModels),
                  Switch(
                    value: state.showSplitModels,
                    onChanged: notifier.setShowSplitModels,
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }


  String _modalityLabel(ModelModality m, AppLocalizations l10n) {
    switch (m) {
      case ModelModality.text:
        return l10n.onDeviceModalityText;
      case ModelModality.vision:
        return l10n.onDeviceModalityVision;
      case ModelModality.audio:
        return l10n.onDeviceModalityAudio;
      case ModelModality.embedding:
        return l10n.onDeviceModalityEmbedding;
      case ModelModality.omni:
        return l10n.onDeviceModalityOmni;
      case ModelModality.unknown:
        return l10n.onDeviceModalityUnknown;
    }
  }
}