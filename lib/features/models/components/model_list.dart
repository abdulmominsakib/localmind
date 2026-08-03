import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/features/chat/providers/chat_params_providers.dart';
import 'package:localmind/features/chat/providers/model_loading_providers.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/service_providers.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/chat/providers/model_selection_providers.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/features/models/providers/model_metadata_providers.dart';
import 'package:localmind/features/models/providers/model_picker_providers.dart';
import 'package:localmind/features/models/utils/model_instance_utils.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'model_tile.dart';

class ModelList extends ConsumerStatefulWidget {
  const ModelList({
    super.key,
    required this.serverId,
    required this.selectedModelId,
    required this.isDark,
    this.scrollController,
  });

  final String serverId;
  final String? selectedModelId;
  final bool isDark;
  final ScrollController? scrollController;

  @override
  ConsumerState<ModelList> createState() => _ModelListState();
}

class _ModelListState extends ConsumerState<ModelList> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(modelMetadataProvider.notifier).loadForServer(widget.serverId);
    });
  }

  @override
  void didUpdateWidget(covariant ModelList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serverId != widget.serverId) {
      ref.read(modelMetadataProvider.notifier).loadForServer(widget.serverId);
    }
  }

  List<ModelInfo> _sortedModels(List<ModelInfo> models) {
    final metadata = ref.watch(modelMetadataProvider);
    final sortOption = ref.watch(modelSortOptionProvider);
    final sorted = List<ModelInfo>.from(models);

    int byName(ModelInfo a, ModelInfo b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());

    switch (sortOption) {
      case ModelSortOption.favorites:
        sorted.sort((a, b) {
          final aFavorite = metadata[a.id]?.isFavorite ?? false;
          final bFavorite = metadata[b.id]?.isFavorite ?? false;
          if (aFavorite != bFavorite) return aFavorite ? -1 : 1;
          return byName(a, b);
        });
      case ModelSortOption.nameAsc:
        sorted.sort(byName);
      case ModelSortOption.sizeAsc:
        sorted.sort((a, b) {
          final size = (a.fileSize ?? 0).compareTo(b.fileSize ?? 0);
          return size != 0 ? size : byName(a, b);
        });
      case ModelSortOption.sizeDesc:
        sorted.sort((a, b) {
          final size = (b.fileSize ?? 0).compareTo(a.fileSize ?? 0);
          return size != 0 ? size : byName(a, b);
        });
      case ModelSortOption.contextDesc:
        sorted.sort((a, b) {
          final ctx = (b.contextLength ?? 0).compareTo(a.contextLength ?? 0);
          return ctx != 0 ? ctx : byName(a, b);
        });
    }
    return sorted;
  }

  Future<void> _showModelOptions(
    BuildContext context,
    ModelInfo model,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final metadata = ref.read(modelMetadataProvider)[model.id];
    final noteController = TextEditingController(text: metadata?.note ?? '');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final settings = ref.read(settingsProvider);
        final isDefaultModel =
            settings.defaultModelServerId == widget.serverId &&
                settings.defaultModelId == model.id;

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  model.displayName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: HugeIcon(
                    icon: isDefaultModel
                        ? HugeIcons.strokeRoundedDelete01
                        : HugeIcons.strokeRoundedRocket,
                    color: isDefaultModel ? Colors.red[400] : Colors.green[600],
                  ),
                  title: Text(
                    isDefaultModel
                        ? l10n.model_clear_default
                        : l10n.model_set_default,
                  ),
                  onTap: () async {
                    final notifier = ref.read(settingsProvider.notifier);
                    if (isDefaultModel) {
                      notifier.clearDefaultModel();
                    } else {
                      notifier.setDefaultModel(
                        serverId: widget.serverId,
                        modelId: model.id,
                      );
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: HugeIcon(icon: 
                    metadata?.isFavorite == true
                        ? HugeIcons.strokeRoundedStar
                        : HugeIcons.strokeRoundedStar,
                    color: Colors.amber[700],
                  ),
                  title: Text(l10n.model_favorite_toggle),
                  onTap: () async {
                    await ref
                        .read(modelMetadataProvider.notifier)
                        .toggleFavorite(model.id);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
                TextField(
                  controller: noteController,
                  decoration: InputDecoration(
                    labelText: l10n.model_note_label,
                    hintText: l10n.model_note_hint,
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(l10n.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () async {
                        await ref
                            .read(modelMetadataProvider.notifier)
                            .setNote(model.id, noteController.text);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      child: Text(l10n.save),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    noteController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final searchQuery = ref.watch(modelSearchQueryProvider);
    final metadata = ref.watch(modelMetadataProvider);

    final connectionStatus = ref.watch(connectionStatusProvider);

    if (connectionStatus == ConnectionStatus.error) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              HugeIcon(icon: HugeIcons.strokeRoundedCloud, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                l10n.server_offline,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.could_not_establish_connection,
                style: TextStyle(
                  fontSize: 13,
                  color: widget.isDark ? AppColors.darkMutedText : AppColors.lightMutedText,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () async {
                  await ref.read(connectionStatusProvider.notifier).refresh();
                  ref.invalidate(availableModelsProvider(widget.serverId));
                },
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh),
                label: Text(l10n.retry_connection),
              ),
            ],
          ),
        ),
      );
    }

    if (connectionStatus == ConnectionStatus.checking) {
      return const Center(child: CircularProgressIndicator());
    }

    final modelsAsync = ref.watch(availableModelsProvider(widget.serverId));

    return modelsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HugeIcon(icon: HugeIcons.strokeRoundedInformationCircle, size: 48, color: Colors.red[400]),
            const SizedBox(height: 16),
            Text(
              l10n.failed_load_models,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: widget.isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              err.toString(),
              style: TextStyle(
                fontSize: 12,
                color: widget.isDark ? AppColors.darkMutedText : AppColors.lightMutedText,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.invalidate(availableModelsProvider(widget.serverId)),
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh),
              label: Text(l10n.retry),
            ),
          ],
        ),
      ),
      data: (models) {
        final serversAsync = ref.watch(serversProvider);
        final servers = serversAsync.value ?? [];
        final activeServer =
            servers.where((s) => s.id == widget.serverId).firstOrNull;
        final loadedModelsAsync = activeServer != null
            ? ref.watch(loadedModelsProvider(activeServer))
            : const AsyncValue<Set<String>>.data(<String>{});

        final loadedInstances = loadedModelsAsync.maybeWhen(
          data: (data) => data,
          orElse: () => <String>{},
        );

        final modelList = models.cast<ModelInfo>();
        final modelLoading = ref.watch(modelLoadingProvider);
        final filtered = searchQuery.isEmpty
            ? modelList
            : modelList
                  .where(
                    (m) =>
                        m.displayName.toLowerCase().contains(
                          searchQuery.toLowerCase(),
                        ) ||
                        m.id.toLowerCase().contains(searchQuery.toLowerCase()),
                  )
                  .toList();

        final sorted = _sortedModels(filtered);

        if (sorted.isEmpty) {
          return Center(
            child: Text(
              searchQuery.isEmpty
                  ? l10n.no_models_available
                  : l10n.no_models_match(searchQuery),
              style: TextStyle(
                fontSize: 14,
                color: widget.isDark ? AppColors.darkMutedText : AppColors.lightMutedText,
              ),
            ),
          );
        }

        return ListView.builder(
          controller: widget.scrollController,
          itemCount: sorted.length,
          itemBuilder: (context, index) {
            final model = sorted[index];
            final isSelected = model.id == widget.selectedModelId;
            final isLoaded = isModelKeyLoaded(loadedInstances, model.id);
            final modelMeta = metadata[model.id];

            return ModelTile(
              model: model,
              isSelected: isSelected,
              isLoaded: isLoaded,
              isDark: widget.isDark,
              isLoading: modelLoading.isLoading && modelLoading.modelId == model.id,
              isFavorite: modelMeta?.isFavorite ?? false,
              isDefault: ref.watch(
                settingsProvider.select(
                  (s) =>
                      s.defaultModelServerId == widget.serverId &&
                      s.defaultModelId == model.id,
                ),
              ),
              note: modelMeta?.note,
              onLongPress: () => _showModelOptions(context, model),
              onTap: () async {
                final activeServer = ref.read(activeServerProvider);
                if (activeServer == null) return;

                final supportsLoad = model.serverType == ServerType.lmStudio;

                if (supportsLoad && !isLoaded) {
                  ref.read(modelLoadingProvider.notifier).setLoading(model.id);

                  try {
                    final apiService = ref.read(serverApiServiceProvider);
                    final settings = ref.read(settingsProvider);
                    final contextLength =
                        ref.read(chatParamsProvider).contextLength;

                    if (settings.unloadModelsBeforeLoad) {
                      final instances = await ref.read(
                        loadedModelsProvider(activeServer).future,
                      );
                      await apiService.unloadAllInstances(
                        activeServer,
                        instances,
                      );
                    }

                    await apiService.loadModelWithInstanceId(
                      activeServer,
                      model.id,
                      contextLength: contextLength,
                    );

                    ref.invalidate(loadedModelsProvider(activeServer));
                    ref.read(modelLoadingProvider.notifier).setLoaded();
                  } catch (e) {
                    ref.read(modelLoadingProvider.notifier).setLoaded();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l10n.model_load_failed(e.toString())),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                    return;
                  }
                }

                ref.read(selectedModelProvider.notifier).setModel(model);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              onUnload: () async {
                final activeServer = ref.read(activeServerProvider);
                if (activeServer == null) return;

                try {
                  final apiService = ref.read(serverApiServiceProvider);
                  final instances = await ref.read(
                    loadedModelsProvider(activeServer).future,
                  );
                  await apiService.unloadInstancesForModelKey(
                    activeServer,
                    model.id,
                    instances,
                  );
                  ref.invalidate(loadedModelsProvider(activeServer));

                  final selectedModel = ref.read(selectedModelProvider);
                  if (selectedModel?.id == model.id) {
                    ref.read(selectedModelProvider.notifier).clear();
                  }

                  if (context.mounted) {
                    final message = activeServer.isOllamaFamily
                        ? l10n.model_unloaded_ollama(model.name)
                        : l10n.model_unloaded_success(model.name);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(message)),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.model_unload_failed(e.toString())),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
            );
          },
        );
      },
    );
  }
}