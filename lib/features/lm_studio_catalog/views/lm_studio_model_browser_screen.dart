import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/l10n/app_localizations.dart';

import '../data/catalog_models.dart';
import '../providers/lm_studio_catalog_providers.dart';
import '../utils/download_matching.dart';
import '../utils/memory_compatibility.dart';
import 'lm_studio_download_widgets.dart';
import 'lm_studio_quant_selector.dart';

class LmStudioModelBrowserScreen extends ConsumerStatefulWidget {
  const LmStudioModelBrowserScreen({super.key, required this.server});

  final Server server;

  @override
  ConsumerState<LmStudioModelBrowserScreen> createState() =>
      _LmStudioModelBrowserScreenState();
}

class _LmStudioModelBrowserScreenState
    extends ConsumerState<LmStudioModelBrowserScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  final _listScrollController = ScrollController();
  String _searchQuery = '';
  LmCatalogModel? _selectedModel;
  late AnimationController _panelController;
  late Animation<Offset> _panelSlide;

  @override
  void initState() {
    super.initState();
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _panelSlide = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _panelController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
    _listScrollController.addListener(_onListScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _listScrollController.dispose();
    _panelController.dispose();
    super.dispose();
  }

  void _onListScroll() {
    if (_searchQuery.trim().isEmpty) return;
    if (!_listScrollController.hasClients) return;
    final pos = _listScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      ref.read(lmCatalogSearchProvider.notifier).loadMore();
    }
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
      if (value.trim().isEmpty) {
        _closeDetails();
      }
    });
    ref.read(lmCatalogSearchProvider.notifier).search(value);
  }

  Future<void> _selectModel(LmCatalogModel model) async {
    setState(() => _selectedModel = model);
    await _panelController.forward();
  }

  Future<void> _closeDetails() async {
    if (_selectedModel == null) return;
    await _panelController.reverse();
    if (mounted) setState(() => _selectedModel = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final trimmedQuery = _searchQuery.trim();
    final isSearching = trimmedQuery.isNotEmpty;

    final staffPicksAsync = ref.watch(lmStudioStaffPicksProvider);
    final searchState = isSearching
        ? ref.watch(lmCatalogSearchProvider)
        : null;

    return PopScope(
      canPop: _selectedModel == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _closeDetails();
      },
      child: Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: Text(l10n.lm_studio_model_browser_title),
        actions: const [
          LmDownloadIndicatorButton(),
        ],
      ),
      body: Stack(
        children: [
          Column(
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
                    fillColor:
                        isDark ? AppColors.darkSurface : AppColors.lightSurface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: isSearching
                    ? _buildSearchList(searchState, l10n, theme)
                    : staffPicksAsync.when(
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (error, _) => Center(
                          child:
                              Text(l10n.error_with_message(error.toString())),
                        ),
                        data: (models) =>
                            _buildModelList(models, l10n, theme, null),
                      ),
              ),
            ],
          ),
          if (_selectedModel != null) ...[
            GestureDetector(
              onTap: _closeDetails,
              child: AnimatedBuilder(
                animation: _panelController,
                builder: (context, _) => Container(
                  color: Colors.black.withValues(
                    alpha: 0.45 * _panelController.value,
                  ),
                ),
              ),
            ),
            SlideTransition(
              position: _panelSlide,
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: MediaQuery.sizeOf(context).width * 0.85,
                  child: _ModelDetailPanel(
                    server: widget.server,
                    model: _selectedModel!,
                    onClose: _closeDetails,
                    onSwipeDismiss: _closeDetails,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }

  Widget _buildSearchList(
    LmCatalogSearchState? state,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    if (state == null || state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.allModels.isEmpty) {
      return Center(child: Text(l10n.error_with_message(state.error!)));
    }
    if (state.allModels.isEmpty) {
      return Center(child: Text(l10n.lm_studio_no_models));
    }
    return _buildModelList(
      state.allModels,
      l10n,
      theme,
      state,
      staffMatches: state.staffMatches,
      communityModels: state.communityModels,
    );
  }

  Widget _buildModelList(
    List<LmCatalogModel> models,
    AppLocalizations l10n,
    ThemeData theme,
    LmCatalogSearchState? searchState, {
    List<LmCatalogModel>? staffMatches,
    List<LmCatalogModel>? communityModels,
  }) {
    final isSearching = _searchQuery.trim().isNotEmpty;
    final staff = isSearching ? (staffMatches ?? []) : models;
    final community = isSearching ? (communityModels ?? []) : const <LmCatalogModel>[];

    return ListView(
      controller: _listScrollController,
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
        if (staff.isNotEmpty && isSearching)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Text(
              l10n.lm_studio_staff_picks,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ...staff.map(
          (model) => _ModelListTile(
            model: model,
            selected: _selectedModel?.id == model.id,
            onTap: () => _selectModel(model),
          ),
        ),
        if (community.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
            child: Text(
              l10n.lm_studio_community_models,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...community.map(
            (model) => _ModelListTile(
              model: model,
              selected: _selectedModel?.id == model.id,
              onTap: () => _selectModel(model),
            ),
          ),
        ],
        if (searchState?.isLoadingMore == true)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
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
                            model.displayLabel,
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
                        if (model.likes > 0) ...[
                          Icon(Icons.favorite_border,
                              size: 14, color: theme.hintColor),
                          const SizedBox(width: 2),
                          Text(
                            _formatCount(model.likes),
                            style: theme.textTheme.labelSmall,
                          ),
                          const SizedBox(width: 8),
                        ],
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

class _ModelDetailPanel extends ConsumerStatefulWidget {
  const _ModelDetailPanel({
    required this.server,
    required this.model,
    required this.onClose,
    required this.onSwipeDismiss,
  });

  final Server server;
  final LmCatalogModel model;
  final VoidCallback onClose;
  final VoidCallback onSwipeDismiss;

  @override
  ConsumerState<_ModelDetailPanel> createState() => _ModelDetailPanelState();
}

class _ModelDetailPanelState extends ConsumerState<_ModelDetailPanel> {
  LmModelQuantOption? _selectedQuant;

  @override
  void didUpdateWidget(covariant _ModelDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model.id != widget.model.id) {
      _selectedQuant = null;
    }
  }

  LmModelQuantOption? _effectiveQuant(List<LmModelQuantOption> quants) {
    if (quants.isEmpty) return null;
    if (_selectedQuant != null &&
        quants.any((q) => q.fileName == _selectedQuant!.fileName)) {
      return _selectedQuant;
    }
    return LmModelQuantOption.recommended(quants);
  }

  LmDownloadJob? _activeJobFor(LmModelDetail detail) {
    final jobs = ref.watch(lmDownloadManagerProvider).jobs;
    final hfRepo = detail.hfRepoId;
    return jobs.where((job) {
      if (!job.status.isActive) return false;
      if (job.modelId == widget.model.catalogId) return true;
      if (hfRepo != null && job.modelId.contains(hfRepo)) return true;
      if (_selectedQuant != null &&
          job.displayName.contains(_selectedQuant!.quantization)) {
        return job.displayName.startsWith(widget.model.displayLabel);
      }
      return job.displayName.startsWith(widget.model.displayLabel);
    }).firstOrNull;
  }

  Future<void> _startDownload(LmModelDetail detail) async {
    final l10n = AppLocalizations.of(context)!;
    final quant = _effectiveQuant(detail.quants);
    if (detail.quants.isNotEmpty && quant == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.lm_studio_download_options)),
      );
      return;
    }

    try {
      await ref.read(lmDownloadManagerProvider.notifier).startDownload(
            server: widget.server,
            model: widget.model,
            detail: detail,
            quant: quant,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.error_with_message(e.toString())),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final detailAsync = ref.watch(lmModelDetailProvider(widget.model));

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 250) {
          widget.onSwipeDismiss();
        }
      },
      child: Material(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        elevation: 8,
        child: SafeArea(
          child: detailAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.error_with_message(error.toString())),
              ),
            ),
            data: (detail) {
              final selectedQuant = _effectiveQuant(detail.quants);
              final activeJob = _activeJobFor(detail);
              final selectedSize = selectedQuant?.sizeBytes ??
                  detail.model.metadata.minMemoryUsageBytes;
              final compatibility = estimateMemoryCompatibility(
                modelSizeBytes: selectedSize,
                availableRamGb: widget.server.availableRamGb,
                availableVramGb: widget.server.availableVramGb,
              );
              final serverModels =
                  ref.watch(availableModelsProvider(widget.server.id));
              final downloadedModels = serverModels.maybeWhen(
                data: downloadedModelsList,
                orElse: () => const <ModelInfo>[],
              );
              final selectedDownloaded = selectedQuant != null &&
                  isQuantDownloaded(
                    model: widget.model,
                    quant: selectedQuant,
                    downloadedModels: downloadedModels,
                  );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: widget.onClose,
                        ),
                        Expanded(
                          child: Text(
                            widget.model.catalogId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: widget.onClose,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (widget.model.isStaffPick)
                          _BadgeChip(
                            label: l10n.lm_studio_staff_pick,
                            color: Colors.purple,
                          ),
                        const SizedBox(height: 12),
                        Text(
                          widget.model.displayLabel,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.model.owner,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.darkMutedText
                                : AppColors.lightMutedText,
                          ),
                        ),
                        if (widget.model.likes > 0 ||
                            widget.model.downloads > 0) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              if (widget.model.likes > 0) ...[
                                Icon(Icons.favorite_border,
                                    size: 16, color: theme.hintColor),
                                const SizedBox(width: 4),
                                Text('${_formatCount(widget.model.likes)}'),
                                const SizedBox(width: 16),
                              ],
                              if (widget.model.downloads > 0) ...[
                                Icon(Icons.download_outlined,
                                    size: 16, color: theme.hintColor),
                                const SizedBox(width: 4),
                                Text('${_formatCount(widget.model.downloads)}'),
                              ],
                            ],
                          ),
                        ],
                        if (widget.model.description != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            widget.model.description!,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: isDark
                                  ? AppColors.darkAccent
                                  : AppColors.lightAccent,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (widget.model.metadata.paramsStrings.isNotEmpty)
                              _MetaChip(
                                label: l10n.lm_studio_params,
                                value: widget.model.metadata.paramsStrings
                                    .join(', '),
                              ),
                            if (widget.model.metadata.architectures.isNotEmpty)
                              _MetaChip(
                                label: l10n.lm_studio_arch,
                                value: widget.model.metadata.architectures
                                    .join(', '),
                              ),
                            _MetaChip(
                              label: l10n.lm_studio_domain,
                              value: widget.model.metadata.type.toUpperCase(),
                            ),
                            if (widget
                                .model.metadata.compatibilityTypes.isNotEmpty)
                              _MetaChip(
                                label: l10n.lm_studio_format,
                                value: widget.model.metadata.compatibilityTypes
                                    .join(', ')
                                    .toUpperCase(),
                                highlighted: true,
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _CapabilityRow(model: widget.model),
                        const SizedBox(height: 20),
                        Text(
                          l10n.lm_studio_download_options,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (detail.quants.isEmpty)
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
                            child: Text(
                              widget.model.displayLabel,
                              style: theme.textTheme.titleSmall,
                            ),
                          )
                        else
                          LmStudioQuantSelector(
                            quants: detail.quants,
                            selected: selectedQuant,
                            onSelected: (quant) =>
                                setState(() => _selectedQuant = quant),
                            serverRamGb: widget.server.availableRamGb,
                            serverVramGb: widget.server.availableVramGb,
                            downloadedModels: downloadedModels,
                            modelCapabilities: widget.model,
                          ),
                        if (detail.quants.isEmpty &&
                            compatibility != MemoryCompatibility.unknown) ...[
                          const SizedBox(height: 8),
                          _CompatibilityBadge(compatibility: compatibility),
                        ],
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: activeJob != null || selectedDownloaded
                                ? null
                                : () => _startDownload(detail),
                            icon: activeJob != null
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      value: activeJob.progressFraction,
                                    ),
                                  )
                                : Icon(
                                    selectedDownloaded
                                        ? Icons.check
                                        : Icons.download,
                                  ),
                            label: Text(
                              activeJob != null
                                  ? l10n.lm_studio_downloading_percent(
                                      ((activeJob.progressFraction ?? 0) * 100)
                                          .round(),
                                    )
                                  : selectedDownloaded
                                      ? l10n.downloaded
                                      : selectedSize != null
                                          ? l10n.lm_studio_download_size(
                                              formatBytes(selectedSize),
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
                        if (detail.readme == null ||
                            detail.readme!.trim().isEmpty)
                          Text(l10n.lm_studio_readme_unavailable)
                        else
                          GptMarkdown(detail.readme!),
                      ],
                    ),
                  ),
                ],
              );
            },
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
