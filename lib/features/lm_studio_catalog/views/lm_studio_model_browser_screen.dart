import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/l10n/app_localizations.dart';

import '../data/catalog_models.dart';
import '../providers/lm_studio_catalog_providers.dart';
import '../utils/memory_compatibility.dart';

class LmStudioModelBrowserScreen extends ConsumerStatefulWidget {
  const LmStudioModelBrowserScreen({super.key, required this.server});

  final Server server;

  @override
  ConsumerState<LmStudioModelBrowserScreen> createState() =>
      _LmStudioModelBrowserScreenState();
}

class _LmStudioModelBrowserScreenState
    extends ConsumerState<LmStudioModelBrowserScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  LmCatalogModel? _selectedModel;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
      if (value.trim().isEmpty) {
        _selectedModel = null;
      }
    });
  }

  void _selectModel(LmCatalogModel model) {
    setState(() => _selectedModel = model);
  }

  void _closeDetails() {
    setState(() => _selectedModel = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final showDetails = _selectedModel != null;

    final modelsAsync = _searchQuery.trim().isEmpty
        ? ref.watch(lmStudioStaffPicksProvider)
        : ref.watch(lmStudioCatalogSearchProvider(_searchQuery.trim()));

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: Text(l10n.lm_studio_model_browser_title),
        actions: const [
          _DownloadIndicatorButton(),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            flex: showDetails && isWide ? 4 : 1,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: l10n.lm_studio_model_search_hint,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _searchController.clear();
                                _onSearchChanged('');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: isDark
                          ? AppColors.darkSurface
                          : AppColors.lightSurface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: modelsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => Center(
                      child: Text(l10n.error_with_message(error.toString())),
                    ),
                    data: (models) {
                      if (models.isEmpty) {
                        return Center(child: Text(l10n.lm_studio_no_models));
                      }

                      final staffPicks = models
                          .where((m) => m.isStaffPick && _searchQuery.isNotEmpty)
                          .toList();
                      final others = _searchQuery.trim().isEmpty
                          ? models
                          : models.where((m) => !m.isStaffPick).toList();

                      return ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: [
                          if (_searchQuery.trim().isEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                              child: Row(
                                children: [
                                  Text(
                                    l10n.lm_studio_staff_picks,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    l10n.lm_studio_models_count(models.length),
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          if (staffPicks.isNotEmpty) ...[
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 4, 12, 8),
                              child: Text(
                                l10n.lm_studio_staff_picks,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            ...staffPicks.map(
                              (model) => _ModelListTile(
                                model: model,
                                selected: _selectedModel?.id == model.id,
                                onTap: () => _selectModel(model),
                              ),
                            ),
                            if (others.isNotEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 16, 12, 8),
                                child: Text(
                                  l10n.lm_studio_community_models,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                          ...others.map(
                            (model) => _ModelListTile(
                              model: model,
                              selected: _selectedModel?.id == model.id,
                              onTap: () => _selectModel(model),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          if (showDetails)
            Expanded(
              flex: isWide ? 6 : 1,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _ModelDetailPanel(
                  key: ValueKey(_selectedModel!.id),
                  server: widget.server,
                  model: _selectedModel!,
                  onClose: _closeDetails,
                  fullWidth: !isWide,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModelListTile extends StatelessWidget {
  const _ModelListTile({
    required this.model,
    required this.selected,
    required this.onTap,
  });

  final LmCatalogModel model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: selected
          ? (isDark ? AppColors.darkAccent : AppColors.lightAccent)
              .withValues(alpha: 0.18)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: model.source == LmCatalogSource.lmStudio
                    ? Image.network(
                        model.thumbnailUrl,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _FallbackIcon(model: model),
                      )
                    : _FallbackIcon(model: model),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            model.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (model.isVerified)
                          Icon(
                            Icons.verified,
                            size: 16,
                            color: isDark
                                ? AppColors.darkAccent
                                : AppColors.lightAccent,
                          ),
                        if (model.isStaffPick) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.auto_awesome,
                            size: 14,
                            color: Colors.purple.shade300,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      model.owner,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkMutedText
                            : AppColors.lightMutedText,
                      ),
                    ),
                    if (model.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        model.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _CapabilityIcons(model: model),
                        const Spacer(),
                        if (model.downloads > 0) ...[
                          Icon(Icons.download_outlined,
                              size: 14, color: theme.hintColor),
                          const SizedBox(width: 2),
                          Text(
                            _formatCount(model.downloads),
                            style: theme.textTheme.labelSmall,
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (model.updatedAt != null)
                          Text(
                            formatRelativeTime(model.updatedAt),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.hintColor,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatCount(int value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toString();
  }
}

class _FallbackIcon extends StatelessWidget {
  const _FallbackIcon({required this.model});

  final LmCatalogModel model;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      color: Colors.grey.shade800,
      child: Center(
        child: Text(
          model.owner.isNotEmpty ? model.owner[0].toUpperCase() : '?',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _CapabilityIcons extends StatelessWidget {
  const _CapabilityIcons({required this.model});

  final LmCatalogModel model;

  @override
  Widget build(BuildContext context) {
    final icons = <Widget>[];
    if (model.metadata.vision) {
      icons.add(_capIcon(Icons.visibility_outlined, Colors.amber));
    }
    if (model.metadata.trainedForToolUse) {
      icons.add(_capIcon(Icons.build_outlined, Colors.blue));
    }
    if (model.metadata.reasoning) {
      icons.add(_capIcon(Icons.psychology_outlined, Colors.green));
    }
    return Row(children: icons);
  }

  Widget _capIcon(IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Icon(icon, size: 16, color: color),
    );
  }
}

class _ModelDetailPanel extends ConsumerWidget {
  const _ModelDetailPanel({
    super.key,
    required this.server,
    required this.model,
    required this.onClose,
    required this.fullWidth,
  });

  final Server server;
  final LmCatalogModel model;
  final VoidCallback onClose;
  final bool fullWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final readmeAsync = ref.watch(lmStudioModelReadmeProvider(model));
    final downloadState = ref.watch(lmDownloadManagerProvider);
    final activeJob = downloadState.jobs
        .where((j) => j.modelId == model.catalogId && j.status.isActive)
        .firstOrNull;

    final memoryBytes = model.metadata.minMemoryUsageBytes;
    final compatibility = estimateMemoryCompatibility(
      modelSizeBytes: memoryBytes,
      availableRamGb: server.availableRamGb,
      availableVramGb: server.availableVramGb,
    );

    return Material(
      color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      elevation: fullWidth ? 8 : 0,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: onClose,
                  ),
                  Expanded(
                    child: Text(
                      model.catalogId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (model.isStaffPick)
                    _BadgeChip(
                      label: l10n.lm_studio_staff_pick,
                      color: Colors.purple,
                    ),
                  const SizedBox(height: 12),
                  if (model.description != null)
                    Text(
                      model.description!,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: isDark
                            ? AppColors.darkAccent
                            : AppColors.lightAccent,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (model.metadata.paramsStrings.isNotEmpty)
                        _MetaChip(
                          label: l10n.lm_studio_params,
                          value: model.metadata.paramsStrings.join(', '),
                        ),
                      if (model.metadata.architectures.isNotEmpty)
                        _MetaChip(
                          label: l10n.lm_studio_arch,
                          value: model.metadata.architectures.join(', '),
                        ),
                      _MetaChip(
                        label: l10n.lm_studio_domain,
                        value: model.metadata.type.toUpperCase(),
                      ),
                      if (model.metadata.compatibilityTypes.isNotEmpty)
                        _MetaChip(
                          label: l10n.lm_studio_format,
                          value: model.metadata.compatibilityTypes
                              .join(', ')
                              .toUpperCase(),
                          highlighted: true,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _CapabilityRow(model: model),
                  const SizedBox(height: 20),
                  Text(
                    l10n.lm_studio_download_options,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkBackground
                          : AppColors.lightBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? AppColors.darkBorder
                            : AppColors.lightBorder,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                model.displayName,
                                style: theme.textTheme.titleSmall,
                              ),
                              if (memoryBytes != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  formatBytes(memoryBytes),
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (compatibility != MemoryCompatibility.unknown) ...[
                    const SizedBox(height: 8),
                    _CompatibilityBadge(compatibility: compatibility),
                  ],
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: activeJob != null
                          ? null
                          : () async {
                              await ref
                                  .read(lmDownloadManagerProvider.notifier)
                                  .startDownload(
                                    server: server,
                                    model: model,
                                  );
                            },
                      icon: activeJob != null
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                value: activeJob.progressFraction,
                              ),
                            )
                          : const Icon(Icons.download),
                      label: Text(
                        activeJob != null
                            ? l10n.lm_studio_downloading_percent(
                                ((activeJob.progressFraction ?? 0) * 100)
                                    .round(),
                              )
                            : memoryBytes != null
                                ? l10n.lm_studio_download_size(
                                    formatBytes(memoryBytes),
                                  )
                                : l10n.lm_studio_download,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'README',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  readmeAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (_, __) => Text(l10n.lm_studio_readme_unavailable),
                    data: (readme) {
                      if (readme == null || readme.trim().isEmpty) {
                        return Text(l10n.lm_studio_readme_unavailable);
                      }
                      return GptMarkdown(readme);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.labelSmall,
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(
                color: isDark
                    ? AppColors.darkMutedText
                    : AppColors.lightMutedText,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: highlighted
                    ? (isDark ? AppColors.darkAccent : AppColors.lightAccent)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({required this.model});

  final LmCatalogModel model;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final caps = <Widget>[];
    if (model.metadata.vision) {
      caps.add(_capLabel(Icons.visibility_outlined, l10n.lm_studio_vision, Colors.amber));
    }
    if (model.metadata.trainedForToolUse) {
      caps.add(_capLabel(Icons.build_outlined, l10n.lm_studio_tool_use, Colors.blue));
    }
    if (model.metadata.reasoning) {
      caps.add(_capLabel(Icons.psychology_outlined, l10n.lm_studio_reasoning, Colors.green));
    }
    if (caps.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: caps);
  }

  Widget _capLabel(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _CompatibilityBadge extends StatelessWidget {
  const _CompatibilityBadge({required this.compatibility});

  final MemoryCompatibility compatibility;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    late final String label;
    late final Color color;
    late final IconData icon;

    switch (compatibility) {
      case MemoryCompatibility.fullGpuOffload:
        label = l10n.lm_studio_full_gpu_offload;
        color = Colors.green;
        icon = Icons.rocket_launch_outlined;
      case MemoryCompatibility.partialGpuOffload:
        label = l10n.lm_studio_partial_gpu_offload;
        color = Colors.blue;
        icon = Icons.memory_outlined;
      case MemoryCompatibility.likelyTooLarge:
        label = l10n.lm_studio_likely_too_large;
        color = Colors.red;
        icon = Icons.cancel_outlined;
      case MemoryCompatibility.unknown:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _DownloadIndicatorButton extends ConsumerWidget {
  const _DownloadIndicatorButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeCount = ref.watch(lmActiveDownloadCountProvider);
    final progress = ref.watch(lmOverallDownloadProgressProvider);
    if (activeCount <= 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 2.5,
            ),
          ),
          Text(
            '$activeCount',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
