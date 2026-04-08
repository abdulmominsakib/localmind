import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../chat/providers/chat_providers.dart';
import '../data/models/model_info.dart';
import '../../servers/providers/server_providers.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/models/enums.dart';

final modelSearchQueryProvider = NotifierProvider<_ModelSearchNotifier, String>(
  _ModelSearchNotifier.new,
);

class _ModelSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String q) => state = q;
  void clear() => state = '';
}

class ModelPickerSheet extends ConsumerWidget {
  const ModelPickerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final activeServer = ref.watch(activeServerProvider);
    final selectedModel = ref.watch(selectedModelProvider);
    final searchQuery = ref.watch(modelSearchQueryProvider);
    final modelLoading = ref.watch(modelLoadingProvider);
    final isThinking = ref.watch(modelThinkingProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Select Model',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        if (isThinking) ...[
                          const SizedBox(width: 8),
                          _ThinkingIndicator(isDark: isDark),
                        ],
                      ],
                    ),
                    if (modelLoading.isLoading)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Loading ${modelLoading.modelId ?? "model"}...',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? const Color(0xFF888888)
                                    : const Color(0xFF999999),
                              ),
                            ),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: modelLoading.progress,
                              backgroundColor: isDark
                                  ? const Color(0xFF333333)
                                  : const Color(0xFFE0E0E0),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (activeServer != null)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () {
                    ref.invalidate(availableModelsProvider(activeServer.id));
                    ref.invalidate(loadedModelsProvider(activeServer));
                  },
                  tooltip: 'Refresh models',
                ),
            ],
          ),
          if (activeServer != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                activeServer.name,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? const Color(0xFF888888)
                      : const Color(0xFF999999),
                ),
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search models...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              suffixIcon: searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () =>
                          ref.read(modelSearchQueryProvider.notifier).clear(),
                    )
                  : null,
            ),
            onChanged: (q) =>
                ref.read(modelSearchQueryProvider.notifier).setQuery(q),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: activeServer == null
                ? _NoServerState(isDark: isDark)
                : _ModelList(
                    serverId: activeServer.id,
                    selectedModelId: selectedModel?.id,
                    searchQuery: searchQuery,
                    isDark: isDark,
                  ),
          ),
        ],
      ),
    );
  }
}

class _NoServerState extends StatelessWidget {
  const _NoServerState({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.computer_outlined,
            size: 48,
            color: isDark ? const Color(0xFF444444) : const Color(0xFFCCCCCC),
          ),
          const SizedBox(height: 16),
          Text(
            'No server connected',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add a server first to see available models.',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? const Color(0xFF888888) : const Color(0xFF999999),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelList extends ConsumerWidget {
  const _ModelList({
    required this.serverId,
    required this.selectedModelId,
    required this.searchQuery,
    required this.isDark,
  });

  final String serverId;
  final String? selectedModelId;
  final String searchQuery;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modelsAsync = ref.watch(availableModelsProvider(serverId));

    return modelsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
            const SizedBox(height: 16),
            Text(
              'Failed to load models',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              err.toString(),
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? const Color(0xFF888888)
                    : const Color(0xFF999999),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.invalidate(availableModelsProvider(serverId)),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (models) {
        final serversAsync = ref.watch(serversProvider);
        final servers = serversAsync.value ?? [];
        final activeServer = servers.where((s) => s.id == serverId).firstOrNull;
        final loadedModelsAsync = activeServer != null
            ? ref.watch(loadedModelsProvider(activeServer))
            : const AsyncValue<Set<String>>.data(<String>{});

        final loadedModels = loadedModelsAsync.maybeWhen(
          data: (data) => data,
          orElse: () => <String>{},
        );

        final modelList = models.cast<ModelInfo>();
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

        if (filtered.isEmpty) {
          return Center(
            child: Text(
              searchQuery.isEmpty
                  ? 'No models available'
                  : 'No models match "$searchQuery"',
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? const Color(0xFF888888)
                    : const Color(0xFF999999),
              ),
            ),
          );
        }

        return ListView.builder(
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final model = filtered[index];
            final isSelected = model.id == selectedModelId;
            final isLoaded = loadedModels.contains(model.id);

            return _ModelTile(
              model: model,
              isSelected: isSelected,
              isLoaded: isLoaded,
              isDark: isDark,
              onTap: () async {
                final activeServer = ref.read(activeServerProvider);
                if (activeServer == null) return;

                if (!isLoaded) {
                  ref.read(modelLoadingProvider.notifier).setLoading(model.id);

                  try {
                    final apiService = ref.read(serverApiServiceProvider);
                    await apiService.loadModelWithInstanceId(
                      activeServer,
                      model.id,
                    );

                    ref.invalidate(loadedModelsProvider(activeServer));
                    ref.read(modelLoadingProvider.notifier).setLoaded();
                  } catch (e) {
                    ref.read(modelLoadingProvider.notifier).setLoaded();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to load model: $e'),
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
                  await apiService.unloadModel(activeServer, model.id);
                  ref.invalidate(loadedModelsProvider(activeServer));

                  // If the model being unloaded is the currently selected one, clear it
                  final selectedModel = ref.read(selectedModelProvider);
                  if (selectedModel?.id == model.id) {
                    ref.read(selectedModelProvider.notifier).clear();
                  }

                  if (context.mounted) {
                    final message = activeServer.type == ServerType.ollama
                        ? '${model.name} will be unloaded once the keep-alive time passes'
                        : '${model.name} unloaded successfully';
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(message)));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to unload model: $e'),
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

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.model,
    required this.isSelected,
    required this.isLoaded,
    required this.isDark,
    required this.onTap,
    this.onUnload,
  });

  final ModelInfo model;
  final bool isSelected;
  final bool isLoaded;
  final bool isDark;
  final VoidCallback onTap;
  final Future<void> Function()? onUnload;

  @override
  Widget build(BuildContext context) {
    final accent = isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? accent.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: accent.withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          model.displayName,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (model.parameterCountDisplay != null)
                        _MetadataChip(
                          label: model.parameterCountDisplay!,
                          isDark: isDark,
                        ),
                      if (model.quantization != null)
                        _MetadataChip(
                          label: model.quantization!,
                          isDark: isDark,
                        ),
                      if (model.formattedSize != null)
                        _MetadataChip(
                          label: model.formattedSize!,
                          isDark: isDark,
                        ),
                      if (model.contextLength != null)
                        _MetadataChip(
                          label: '${model.contextLength} ctx',
                          isDark: isDark,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (isLoaded) ...[
              Container(
                width: 15,
                height: 15,
                decoration: const BoxDecoration(
                  color: Color(0xFF4CAF50),
                  shape: BoxShape.circle,
                ),
              ),
            ],
            if (isLoaded) ...[
              IconButton(
                icon: Icon(
                  Icons.power_settings_new_outlined,
                  size: 18,
                  color: Colors.red[400],
                ),
                onPressed: onUnload,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Unload from server',
              ),
              const SizedBox(width: 8),
            ],
            if (isSelected)
              Icon(Icons.check_circle, color: accent, size: 22)
            else
              Icon(
                Icons.chevron_right,
                size: 20,
                color: isDark
                    ? const Color(0xFF555555)
                    : const Color(0xFFCCCCCC),
              ),
          ],
        ),
      ),
    );
  }
}

class _ThinkingIndicator extends StatefulWidget {
  const _ThinkingIndicator({required this.isDark});
  final bool isDark;

  @override
  State<_ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<_ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: widget.isDark
                    ? Color.lerp(
                        const Color(0xFF888888),
                        const Color(0xFF4CAF50),
                        _controller.value,
                      )
                    : Color.lerp(
                        const Color(0xFF999999),
                        const Color(0xFF4CAF50),
                        _controller.value,
                      ),
                shape: BoxShape.circle,
              ),
            );
          },
        ),
        const SizedBox(width: 4),
        Text(
          'Thinking',
          style: TextStyle(
            fontSize: 12,
            color: widget.isDark
                ? const Color(0xFF888888)
                : const Color(0xFF999999),
          ),
        ),
      ],
    );
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({required this.label, required this.isDark});
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: isDark ? const Color(0xFFAAAAAA) : const Color(0xFF777777),
        ),
      ),
    );
  }
}
