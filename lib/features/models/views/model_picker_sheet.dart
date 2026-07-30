import 'package:cue/cue.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/service_providers.dart';
import 'package:localmind/core/routes/app_routes.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/chat/providers/chat_providers.dart';
import 'package:localmind/features/on_device/components/on_device_picker_section.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/features/lm_studio_catalog/views/lm_studio_download_widgets.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart'
    as conv;
import 'package:localmind/l10n/app_localizations.dart';
import '../components/model_list.dart';
import '../components/model_search_field.dart';
import '../components/model_sort_control.dart';
import '../components/no_server_state.dart';
import '../components/thinking_indicator.dart';
import '../providers/model_picker_providers.dart';

class ModelPickerSheet extends ConsumerStatefulWidget {
  const ModelPickerSheet({super.key});

  @override
  ConsumerState<ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends ConsumerState<ModelPickerSheet> {
  @override
  void deactivate() {
    // Reset search when the sheet closes so the next open starts from a
    // clean, matching state instead of an empty box that's still filtering.
    final searchNotifier = ref.read(modelSearchQueryProvider.notifier);
    Future.microtask(() => searchNotifier.clear());
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final activeServer = ref.watch(activeServerProvider);
    final selectedModel = ref.watch(selectedModelProvider);
    final isThinking = ref.watch(modelThinkingProvider);

    ref.listen(onDeviceEngineProvider, (prev, next) {
      if (next.status == OnDeviceEngineStatus.loaded &&
          prev?.status == OnDeviceEngineStatus.loading) {
        final loadedId = next.loadedModelId;
        final models = ref.read(onDeviceModelsProvider);
        final loadedName = loadedId == null
            ? 'Unknown'
            : models
                  .where((m) => m.id == loadedId)
                  .map((m) => m.name)
                  .followedBy([loadedId])
                  .first;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.model_loaded(loadedName, next.backend?.name ?? 'CPU'),
            ),
          ),
        );
      }
    });

    final serversAsync = ref.watch(serversProvider);
    final servers = serversAsync.value ?? [];
    final currentServer = servers
        .where((s) => s.id == activeServer?.id)
        .firstOrNull;
    final isOnDevice =
        currentServer != null && currentServer.type == ServerType.onDevice;
    final isLmStudio =
        currentServer != null && currentServer.type == ServerType.lmStudio;

    final loadedModelsAsync = activeServer != null
        ? ref.watch(loadedModelsProvider(activeServer))
        : const AsyncValue<Set<String>>.data(<String>{});
    final loadedCount = loadedModelsAsync.maybeWhen(
      data: (models) => models.length,
      orElse: () => 0,
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 1.0,
      expand: false,
      builder: (context, scrollController) {
        return Cue.onMount(
          motion: .smooth(),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBackground : AppColors.lightSurface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[600] : Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _ModelPickerHeader(
                  isDark: isDark,
                  isThinking: isThinking,
                  loadedCount: loadedCount,
                  showBrowseButton: isLmStudio,
                  onBrowseModels: isLmStudio
                      ? () {
                          Navigator.of(context).pop();
                          context.push(
                            AppRoutes.lmStudioModelBrowser,
                            extra: currentServer,
                          );
                        }
                      : null,
                  onRefresh: activeServer != null
                      ? () {
                          ref.invalidate(
                            availableModelsProvider(activeServer.id),
                          );
                          ref.invalidate(loadedModelsProvider(activeServer));
                        }
                      : null,
                  onUnloadAll: activeServer != null && loadedCount > 0
                      ? () => _unloadAllModels(context, ref, activeServer)
                      : null,
                ),
                if (activeServer != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      activeServer.name,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? AppColors.darkMutedText
                            : AppColors.lightMutedText,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(child: ModelSearchField()),
                    const SizedBox(width: 8),
                    const ModelSortControl(),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: activeServer == null
                      ? NoServerState(isDark: isDark)
                      : isOnDevice
                      ? OnDevicePickerSection(
                          selectedModelId: selectedModel?.id,
                          isDark: isDark,
                          scrollController: scrollController,
                        )
                      : ModelList(
                          serverId: activeServer.id,
                          selectedModelId: selectedModel?.id,
                          isDark: isDark,
                          scrollController: scrollController,
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _unloadAllModels(
    BuildContext context,
    WidgetRef ref,
    dynamic activeServer,
  ) async {
    final l10n = AppLocalizations.of(context)!;

    try {
      if (activeServer.type == ServerType.onDevice) {
        await ref.read(onDeviceEngineProvider.notifier).unloadModel();
      } else {
        final loadedInstances = await ref.read(
          loadedModelsProvider(activeServer).future,
        );
        final apiService = ref.read(serverApiServiceProvider);
        await apiService.unloadAllInstances(activeServer, loadedInstances);
      }

      ref.invalidate(loadedModelsProvider(activeServer));
      ref.read(selectedModelProvider.notifier).clear();

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.all_models_unloaded)));
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
  }
}

class _ModelPickerHeader extends ConsumerWidget {
  const _ModelPickerHeader({
    required this.isDark,
    required this.isThinking,
    required this.loadedCount,
    this.showBrowseButton = false,
    this.onBrowseModels,
    this.onRefresh,
    this.onUnloadAll,
  });

  final bool isDark;
  final bool isThinking;
  final int loadedCount;
  final bool showBrowseButton;
  final VoidCallback? onBrowseModels;
  final VoidCallback? onRefresh;
  final VoidCallback? onUnloadAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider);
    final activeConv = ref.watch(conv.activeConversationProvider);
    final contextLength = activeConv?.contextLength ?? settings.contextLength;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    l10n.select_model_title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  if (loadedCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (isDark
                                    ? AppColors.darkAccent
                                    : AppColors.lightAccent)
                                .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        l10n.loaded_models_count(loadedCount),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.darkAccent
                              : AppColors.lightAccent,
                        ),
                      ),
                    ),
                  ],
                  if (isThinking) ...[
                    const SizedBox(width: 8),
                    ThinkingIndicator(isDark: isDark),
                  ],
                ],
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showContextLengthDialog(
                  context,
                  ref,
                  contextLength,
                  activeConv?.id,
                ),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    color: isDark ? Colors.grey[900] : Colors.grey[50],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedLayers01,
                        size: 14,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$contextLength',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            if (onUnloadAll != null)
              IconButton(
                onPressed: onUnloadAll,
                tooltip: l10n.unload_all_models,
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedPower,
                  size: 20,
                  color: Colors.red[400],
                ),
              ),
            if (showBrowseButton && onBrowseModels != null)
              IconButton(
                onPressed: onBrowseModels,
                tooltip: l10n.lm_studio_browse_models,
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedCompass01,
                  size: 20,
                ),
              ),
            const LmDownloadIndicatorButton(compact: true),
            if (onRefresh != null)
              IconButton(
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedRefresh,
                  size: 20,
                ),
                onPressed: onRefresh,
                tooltip: l10n.refresh_models,
              ),
          ],
        ),
      ],
    );
  }
}

void _showContextLengthDialog(
  BuildContext context,
  WidgetRef ref,
  int currentLength,
  String? activeConversationId,
) {
  showDialog(
    context: context,
    builder: (context) => _ContextLengthEditDialog(
      initialValue: currentLength,
      activeConversationId: activeConversationId,
    ),
  );
}

class _ContextLengthEditDialog extends ConsumerStatefulWidget {
  const _ContextLengthEditDialog({
    required this.initialValue,
    required this.activeConversationId,
  });

  final int initialValue;
  final String? activeConversationId;

  @override
  ConsumerState<_ContextLengthEditDialog> createState() =>
      __ContextLengthEditDialogState();
}

class __ContextLengthEditDialogState
    extends ConsumerState<_ContextLengthEditDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue.toString());
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _save(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null && parsed > 0) {
      if (widget.activeConversationId == null) {
        ref.read(settingsProvider.notifier).setContextLength(parsed);
      } else {
        ref
            .read(conv.conversationsProvider.notifier)
            .updateChatParams(
              widget.activeConversationId!,
              contextLength: parsed,
            );
      }
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    final suggestions = [2048, 4096, 8192, 16384, 32768, 65536, 131072];

    return Dialog(
      backgroundColor: isDark
          ? AppColors.darkBackground
          : AppColors.lightSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.context_length,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.tokens_label,
                  hintText: l10n.enter_context_length,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  suffixIcon: IconButton(
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedCancel01,
                      size: 18,
                    ),
                    onPressed: () => _controller.clear(),
                  ),
                ),
                onSubmitted: _save,
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: suggestions.map((val) {
                    final label = val >= 1024 ? '${val ~/ 1024}K' : '$val';
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(label),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                        backgroundColor: isDark
                            ? Colors.grey[850]
                            : Colors.grey[200],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide.none,
                        ),
                        onPressed: () {
                          _controller.text = val.toString();
                          _controller.selection = TextSelection.fromPosition(
                            TextPosition(offset: _controller.text.length),
                          );
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => _save(_controller.text),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(l10n.save),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
