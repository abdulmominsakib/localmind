import 'package:hugeicons/hugeicons.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/utils/safe_file_picker.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import 'package:localmind/features/on_device/providers/foreground_download_providers.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:localmind/features/on_device/components/memory_stats_panel.dart';
import 'package:localmind/features/on_device/components/model_card.dart';
import 'package:url_launcher/url_launcher.dart';

enum _ImportAction { localFile, huggingFace }

class OnDeviceModelManagerScreen extends ConsumerStatefulWidget {
  const OnDeviceModelManagerScreen({super.key});

  @override
  ConsumerState<OnDeviceModelManagerScreen> createState() =>
      _OnDeviceModelManagerScreenState();
}

class _OnDeviceModelManagerScreenState
    extends ConsumerState<OnDeviceModelManagerScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(importedGgufModelsProvider.notifier).pruneMissing(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final models = ref.watch(onDeviceModelsProvider);
    final downloadedAsync = ref.watch(downloadedModelsProvider);
    final engineState = ref.watch(onDeviceEngineProvider);
    final downloadProgress = ref.watch(foregroundDownloadNotifierProvider);

    final importedModels = models.where((model) => model.isImported).toList()
      ..sort(
        (a, b) => (b.importedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.importedAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );
    final curatedModels = models.where((model) => !model.isImported).toList();

    return Column(
      children: [
        _ManagerHeader(
          l10n: l10n,
          theme: theme,
          onImportLocalGguf: () => _importLocalGguf(context),
          onImportFromHuggingFace: () => _importFromHuggingFace(context),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const MemoryStatsPanel(),
              _ImportOverviewCard(
                importedModels: importedModels,
                onImportLocalGguf: () => _importLocalGguf(context),
                onImportFromHuggingFace: () => _importFromHuggingFace(context),
              ),
              _EngineStatusCard(
                engineState: engineState,
                models: models,
                l10n: l10n,
                theme: theme,
              ),
              const SizedBox(height: 4),
              _SectionHeader(
                title: l10n.gguf_imported_models_title,
                subtitle: importedModels.isEmpty
                    ? l10n.gguf_imported_models_empty_subtitle
                    : '${importedModels.length} ${l10n.gguf_imported_models_ready}',
              ),
              if (importedModels.isEmpty)
                _EmptyImportedModelsCard(
                  onImportLocalGguf: () => _importLocalGguf(context),
                  onImportFromHuggingFace: () =>
                      _importFromHuggingFace(context),
                )
              else
                ...importedModels.map(
                  (model) => ModelCard(
                    model: model,
                    downloadedAsync: downloadedAsync,
                    downloadProgress: downloadProgress[model.id],
                    engineState: engineState,
                  ),
                ),
              const SizedBox(height: 8),
              _SectionHeader(
                title: l10n.available_models,
                subtitle: l10n.gguf_curated_models_subtitle,
              ),
              const SizedBox(height: 4),
              ...curatedModels.map(
                (model) => ModelCard(
                  model: model,
                  downloadedAsync: downloadedAsync,
                  downloadProgress: downloadProgress[model.id],
                  engineState: engineState,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _importLocalGguf(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    try {
      final result = await SafeFilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['gguf'],
      );
      if (result == null || result.files.isEmpty) return;

      final path = result.files.single.path;
      if (path == null || !path.toLowerCase().endsWith('.gguf')) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.gguf_only_supported)),
        );
        return;
      }

      final model = await ref
          .read(importedGgufModelsProvider.notifier)
          .importModel(path);
      messenger.showSnackBar(
        SnackBar(
          content: Text('${model.name} ${l10n.gguf_imported_from_local_file}'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${l10n.gguf_import_failed}: ${_friendlyErrorForL10n(l10n, e)}',
          ),
        ),
      );
    }
  }

  Future<void> _importFromHuggingFace(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    final importedModel = await showDialog<OnDeviceModel>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _HuggingFaceGgufImportDialog(),
    );

    if (!mounted || importedModel == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${importedModel.name} ${l10n.gguf_imported_from_huggingface}',
        ),
      ),
    );
  }

  String _friendlyErrorForL10n(AppLocalizations l10n, Object error) {
    if (SafeFilePicker.isExplorerNotFoundError(error)) {
      return l10n.file_explorer_not_found;
    }
    final message = error.toString();
    final normalized = message
        .replaceFirst('HttpException: ', '')
        .replaceFirst('FormatException: ', '')
        .replaceFirst('FileSystemException: ', '')
        .replaceFirst('PlatformException: ', '');

    switch (normalized) {
      case 'GGUF import canceled.':
        return l10n.gguf_import_canceled;
      case 'Enter a Hugging Face GGUF URL.':
        return l10n.gguf_enter_huggingface_url;
      case 'Only official Hugging Face GGUF URLs are supported.':
        return l10n.gguf_only_official_huggingface_urls;
      case 'Use an HTTPS Hugging Face URL for GGUF import.':
        return l10n.gguf_use_https_url;
      case 'The Hugging Face URL must point directly to a .gguf file.':
        return l10n.gguf_url_must_point_to_file;
      case 'Unable to determine the GGUF file name.':
        return l10n.gguf_unable_to_detect_file_name;
      case 'The downloaded GGUF file was empty or missing.':
        return l10n.gguf_download_empty;
      case 'Selected model file does not exist':
        return l10n.gguf_selected_file_missing;
      default:
        return SafeFilePicker.getErrorMessage(
          error,
          l10n,
          fallbackMessage: normalized,
        );
    }
  }
}

class _ManagerHeader extends StatelessWidget {
  const _ManagerHeader({
    required this.l10n,
    required this.theme,
    required this.onImportLocalGguf,
    required this.onImportFromHuggingFace,
  });

  final AppLocalizations l10n;
  final ThemeData theme;
  final VoidCallback onImportLocalGguf;
  final VoidCallback onImportFromHuggingFace;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: topPadding + 8,
        bottom: 16,
      ),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? const Color(0xFF0A0A0A)
            : const Color(0xFFFAFAFA),
        border: Border(
          bottom: BorderSide(
            color: theme.brightness == Brightness.dark
                ? const Color(0xFF2A2A2A)
                : const Color(0xFFE5E5E5),
          ),
        ),
      ),
      child: Row(
        children: [
          Builder(
            builder: (context) => IconButton(
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedMenu01),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.on_device_models_title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: theme.brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black,
              ),
            ),
          ),
          if (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)
            PopupMenuButton<_ImportAction>(
              tooltip: l10n.gguf_import_action,
              onSelected: (value) {
                switch (value) {
                  case _ImportAction.localFile:
                    onImportLocalGguf();
                  case _ImportAction.huggingFace:
                    onImportFromHuggingFace();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<_ImportAction>(
                  value: _ImportAction.localFile,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const HugeIcon(
                      icon: HugeIcons.strokeRoundedFolder01,
                    ),
                    title: Text(l10n.gguf_import_local_title),
                    subtitle: Text(l10n.gguf_import_local_subtitle),
                  ),
                ),
                PopupMenuItem<_ImportAction>(
                  value: _ImportAction.huggingFace,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const HugeIcon(
                      icon: HugeIcons.strokeRoundedCloudDownload,
                    ),
                    title: Text(l10n.gguf_import_huggingface_title),
                    subtitle: Text(l10n.gguf_import_huggingface_subtitle),
                  ),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedAddCircle,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(l10n.gguf_import_action),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ImportOverviewCard extends StatelessWidget {
  const _ImportOverviewCard({
    required this.importedModels,
    required this.onImportLocalGguf,
    required this.onImportFromHuggingFace,
  });

  final List<OnDeviceModel> importedModels;
  final VoidCallback onImportLocalGguf;
  final VoidCallback onImportFromHuggingFace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final localImports = importedModels
        .where((model) => model.isImportedFromLocalFile)
        .length;
    final huggingFaceImports = importedModels
        .where((model) => model.isImportedFromHuggingFace)
        .length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedCpu,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.gguf_overview_title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.gguf_overview_subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SummaryPill(
                icon: HugeIcons.strokeRoundedLayers01,
                label:
                    '${importedModels.length} ${l10n.gguf_imported_count_label}',
              ),
              _SummaryPill(
                icon: HugeIcons.strokeRoundedFolder01,
                label: '$localImports ${l10n.gguf_local_files_label}',
              ),
              _SummaryPill(
                icon: HugeIcons.strokeRoundedCloudDownload,
                label: '$huggingFaceImports ${l10n.gguf_huggingface_label}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: onImportLocalGguf,
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedFolder01),
                label: Text(l10n.gguf_import_local_title),
              ),
              OutlinedButton.icon(
                onPressed: onImportFromHuggingFace,
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedCloudDownload,
                ),
                label: Text(l10n.gguf_import_huggingface_title),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.icon, required this.label});

  final List<List<dynamic>> icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HugeIcon(icon: icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyImportedModelsCard extends StatelessWidget {
  const _EmptyImportedModelsCard({
    required this.onImportLocalGguf,
    required this.onImportFromHuggingFace,
  });

  final VoidCallback onImportLocalGguf;
  final VoidCallback onImportFromHuggingFace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.gguf_no_imported_title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.gguf_no_imported_subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: onImportLocalGguf,
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedFolder01),
                label: Text(l10n.gguf_import_local_title),
              ),
              OutlinedButton.icon(
                onPressed: onImportFromHuggingFace,
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedCloudDownload,
                ),
                label: Text(l10n.gguf_import_huggingface_title),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HuggingFaceGgufImportDialog extends ConsumerStatefulWidget {
  const _HuggingFaceGgufImportDialog();

  @override
  ConsumerState<_HuggingFaceGgufImportDialog> createState() =>
      _HuggingFaceGgufImportDialogState();
}

class _HuggingFaceGgufImportDialogState
    extends ConsumerState<_HuggingFaceGgufImportDialog> {
  static final Uri _huggingFaceModelsUri = Uri.parse(
    'https://huggingface.co/models?search=gguf',
  );

  final TextEditingController _urlController = TextEditingController();
  CancelToken? _cancelToken;
  bool _isImporting = false;
  String? _error;
  int _receivedBytes = 0;
  int _totalBytes = 0;

  @override
  void dispose() {
    _cancelToken?.cancel();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final hasHuggingFaceToken = ref.watch(
      settingsProvider.select(
        (settings) => settings.huggingFaceToken?.trim().isNotEmpty == true,
      ),
    );
    final input = _urlController.text.trim();
    final preview = _ImportUrlPreview.fromInput(input);
    final progress = _totalBytes > 0 ? _receivedBytes / _totalBytes : null;
    final dialogWidth = MediaQuery.of(context).size.width > 560
        ? 520.0
        : MediaQuery.of(context).size.width * 0.82;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: HugeIcon(
              icon: HugeIcons.strokeRoundedCloudDownload,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(l10n.gguf_import_huggingface_dialog_title)),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.gguf_import_huggingface_dialog_subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _urlController,
                enabled: !_isImporting,
                maxLines: 2,
                minLines: 1,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                onChanged: (_) {
                  if (_error != null) {
                    setState(() => _error = null);
                  } else {
                    setState(() {});
                  }
                },
                onSubmitted: (_) {
                  if (!_isImporting) {
                    _startImport();
                  }
                },
                decoration: InputDecoration(
                  labelText: l10n.gguf_url_or_repo_path,
                  hintText:
                      'owner/repo/blob/main/model.gguf\nhttps://huggingface.co/owner/repo/resolve/main/model.gguf',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Center(
                    widthFactor: 1.0,
                    heightFactor: 1.0,
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedLink01,
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isImporting ? null : _pasteFromClipboard,
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedClipboard,
                      size: 18,
                    ),
                    label: Text(l10n.paste),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isImporting || input.isEmpty
                        ? null
                        : _clearInput,
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedCancel01,
                      size: 18,
                    ),
                    label: Text(l10n.clear_huggingface_token),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isImporting
                        ? null
                        : () => _openHuggingFace(context),
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedShare01,
                      size: 18,
                    ),
                    label: Text(l10n.gguf_browse),
                  ),
                ],
              ),
              if (preview != null) ...[
                const SizedBox(height: 14),
                _ImportPreviewCard(preview: preview),
              ],
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HugeIcon(
                      icon: hasHuggingFaceToken
                          ? HugeIcons.strokeRoundedCheckmarkBadge01
                          : HugeIcons.strokeRoundedInformationCircle,
                      size: 18,
                      color: hasHuggingFaceToken
                          ? Colors.green
                          : theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasHuggingFaceToken
                                ? l10n.gguf_huggingface_token_ready
                                : l10n.gguf_huggingface_token_optional,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hasHuggingFaceToken
                                ? l10n.gguf_huggingface_token_ready_desc
                                : l10n.gguf_huggingface_token_optional_desc,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_isImporting) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              preview?.fileName ?? l10n.gguf_downloading,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              progress == null
                                  ? l10n.gguf_preparing
                                  : '${(progress * 100).toStringAsFixed(1)}%',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _ImportProgressBar(progress: progress),
                      const SizedBox(height: 10),
                      Text(
                        progress != null
                            ? '${_formatBytes(_receivedBytes)} / ${_formatBytes(_totalBytes)}'
                            : l10n.gguf_preparing_download,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.70,
                          ),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const HugeIcon(
                        icon: HugeIcons.strokeRoundedInformationCircle,
                        color: Colors.red,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isImporting
              ? () {
                  _cancelToken?.cancel();
                  Navigator.of(context).pop();
                }
              : () => Navigator.of(context).pop(),
          child: Text(_isImporting ? l10n.gguf_cancel_import : l10n.cancel),
        ),
        ElevatedButton.icon(
          onPressed: _isImporting || input.isEmpty ? null : _startImport,
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedDownload01,
            size: 18,
          ),
          label: Text(l10n.gguf_import_action),
        ),
      ],
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim();
    if (!mounted) return;
    if (text == null || text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.clipboard_empty)),
      );
      return;
    }
    setState(() {
      _urlController.text = text;
      _error = null;
    });
  }

  void _clearInput() {
    setState(() {
      _urlController.clear();
      _error = null;
    });
  }

  Future<void> _openHuggingFace(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final launched = await launchUrl(
      _huggingFaceModelsUri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.could_not_open_huggingface,
          ),
        ),
      );
    }
  }

  Future<void> _startImport() async {
    final sourceUrl = _urlController.text.trim();
    if (sourceUrl.isEmpty) {
      setState(() {
        _error = AppLocalizations.of(context)!.gguf_paste_url_error;
      });
      return;
    }

    setState(() {
      _isImporting = true;
      _error = null;
      _receivedBytes = 0;
      _totalBytes = 0;
    });

    _cancelToken = CancelToken();

    try {
      final huggingFaceToken = ref.read(
        settingsProvider.select((settings) => settings.huggingFaceToken),
      );
      final model = await ref
          .read(importedGgufModelsProvider.notifier)
          .importModelFromHuggingFaceUrl(
            sourceUrl,
            huggingFaceToken: huggingFaceToken,
            cancelToken: _cancelToken,
            onProgress: (receivedBytes, totalBytes) {
              if (!mounted) return;
              setState(() {
                _receivedBytes = receivedBytes;
                _totalBytes = totalBytes > 0 ? totalBytes : 0;
              });
            },
          );

      if (!mounted) return;
      Navigator.of(context).pop(model);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isImporting = false;
        _error = _friendlyError(e);
      });
    }
  }

  String _friendlyError(Object error) {
    final l10n = AppLocalizations.of(context)!;
    final message = error.toString();
    final normalized = message
        .replaceFirst('HttpException: ', '')
        .replaceFirst('FormatException: ', '')
        .replaceFirst('Exception: ', '')
        .replaceFirst('FileSystemException: ', '');
    switch (normalized) {
      case 'GGUF import canceled.':
        return l10n.gguf_import_canceled;
      case 'Enter a Hugging Face GGUF URL.':
        return l10n.gguf_enter_huggingface_url;
      case 'Only official Hugging Face GGUF URLs are supported.':
        return l10n.gguf_only_official_huggingface_urls;
      case 'Use an HTTPS Hugging Face URL for GGUF import.':
        return l10n.gguf_use_https_url;
      case 'The Hugging Face URL must point directly to a .gguf file.':
        return l10n.gguf_url_must_point_to_file;
      case 'Unable to determine the GGUF file name.':
        return l10n.gguf_unable_to_detect_file_name;
      case 'The downloaded GGUF file was empty or missing.':
        return l10n.gguf_download_empty;
      case 'Selected model file does not exist':
        return l10n.gguf_selected_file_missing;
      default:
        return normalized;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }
}

class _ImportPreviewCard extends StatelessWidget {
  const _ImportPreviewCard({required this.preview});

  final _ImportUrlPreview preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PreviewPill(
                icon: preview.isBlobLink
                    ? HugeIcons.strokeRoundedRefresh
                    : HugeIcons.strokeRoundedLink01,
                label: preview.isBlobLink
                    ? l10n.gguf_blob_link
                    : preview.inputStyleLabel,
              ),
              if (preview.fileName != null)
                _PreviewPill(
                  icon: HugeIcons.strokeRoundedFile01,
                  label: preview.fileName!,
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (preview.repoPath != null)
            _PreviewRow(
              label: l10n.gguf_repository_label,
              value: preview.repoPath!,
            ),
          if (preview.normalizedDisplay != null)
            _PreviewRow(
              label: l10n.gguf_detected_path_label,
              value: preview.normalizedDisplay!,
            ),
        ],
      ),
    );
  }
}

class _PreviewPill extends StatelessWidget {
  const _PreviewPill({required this.icon, required this.label});

  final List<List<dynamic>> icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HugeIcon(icon: icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportProgressBar extends StatelessWidget {
  const _ImportProgressBar({required this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trackColor = theme.colorScheme.primary.withValues(alpha: 0.12);
    final fillColor = theme.colorScheme.primary;
    final normalizedProgress = progress?.clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 10,
        child: LinearProgressIndicator(
          value: normalizedProgress?.toDouble(),
          backgroundColor: trackColor,
          valueColor: AlwaysStoppedAnimation<Color>(fillColor),
        ),
      ),
    );
  }
}

class _ImportUrlPreview {
  const _ImportUrlPreview({
    required this.inputStyleLabel,
    required this.isBlobLink,
    this.repoPath,
    this.fileName,
    this.normalizedDisplay,
  });

  final String inputStyleLabel;
  final bool isBlobLink;
  final String? repoPath;
  final String? fileName;
  final String? normalizedDisplay;

  static _ImportUrlPreview? fromInput(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final hasScheme =
        trimmed.startsWith('https://') || trimmed.startsWith('http://');
    final displayUri = hasScheme ? Uri.tryParse(trimmed) : null;
    final pathSource = displayUri != null && displayUri.pathSegments.isNotEmpty
        ? displayUri.pathSegments
        : trimmed.split('/').where((part) => part.isNotEmpty).toList();

    if (pathSource.isEmpty) {
      return const _ImportUrlPreview(
        inputStyleLabel: 'Manual path',
        isBlobLink: false,
      );
    }

    final blobIndex = pathSource.indexOf('blob');
    final resolveIndex = pathSource.indexOf('resolve');
    final fileName =
        pathSource.isNotEmpty && pathSource.last.toLowerCase().endsWith('.gguf')
        ? pathSource.last
        : null;
    final repoPath = pathSource.length >= 2
        ? '${pathSource[0]}/${pathSource[1]}'
        : null;

    String? normalizedDisplay;
    if (blobIndex != -1) {
      final normalized = [...pathSource]..[blobIndex] = 'resolve';
      normalizedDisplay = normalized.join('/');
    } else if (resolveIndex != -1 || fileName != null) {
      normalizedDisplay = pathSource.join('/');
    }

    return _ImportUrlPreview(
      inputStyleLabel: hasScheme ? 'Direct URL' : 'Repo path',
      isBlobLink: blobIndex != -1,
      repoPath: repoPath,
      fileName: fileName,
      normalizedDisplay: normalizedDisplay,
    );
  }
}

class _EngineStatusCard extends StatelessWidget {
  const _EngineStatusCard({
    required this.engineState,
    required this.models,
    required this.l10n,
    required this.theme,
  });

  final OnDeviceEngineState engineState;
  final List<OnDeviceModel> models;
  final AppLocalizations l10n;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (engineState.status == OnDeviceEngineStatus.loaded) {
      final loadedId = engineState.loadedModelId;
      final loadedName = loadedId == null
          ? 'Unknown'
          : models.where((m) => m.id == loadedId).map((m) => m.name).followedBy(
              [loadedId],
            ).first;

      return Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green),
        ),
        child: Row(
          children: [
            const HugeIcon(
              icon: HugeIcons.strokeRoundedCpu,
              color: Colors.green,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.model_loaded(
                  loadedName,
                  engineState.backend?.name ?? 'CPU',
                ),
                style: const TextStyle(color: Colors.green),
              ),
            ),
          ],
        ),
      );
    }

    if (engineState.status == OnDeviceEngineStatus.loading) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: LinearProgressIndicator(),
      );
    }

    if (engineState.status == OnDeviceEngineStatus.error) {
      return Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red),
        ),
        child: Text(
          engineState.error ?? l10n.unknown_error,
          style: const TextStyle(color: Colors.red),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
