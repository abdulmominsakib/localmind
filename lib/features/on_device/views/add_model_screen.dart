import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/providers/service_providers.dart';
import 'package:localmind/features/on_device/data/huggingface_model_search_service.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:localmind/features/on_device/providers/unified_model_search_provider.dart';
import 'package:localmind/features/on_device/views/components/model_file_sheet.dart';
import 'package:localmind/features/on_device/views/components/model_search_filter_bar.dart';
import 'package:localmind/features/on_device/views/components/model_search_result_row.dart';
import 'package:localmind/l10n/app_localizations.dart';

class AddOnDeviceModelScreen extends ConsumerStatefulWidget {
  const AddOnDeviceModelScreen({super.key});

  @override
  ConsumerState<AddOnDeviceModelScreen> createState() =>
      _AddOnDeviceModelScreenState();
}

class _AddOnDeviceModelScreenState
    extends ConsumerState<AddOnDeviceModelScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _addedFileUrls = <String>{};
  final Set<String> _addedFileNames = <String>{};

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  HuggingFaceModelSearchService get _searchService =>
      HuggingFaceModelSearchService(dio: ref.read(dioProvider));

  String? get _token {
    try {
      return ref.read(settingsProvider).huggingFaceToken;
    } catch (_) {
      return null;
    }
  }

  Set<String> get _registeredUrls => {
        ...ref.read(importedGgufModelsProvider).map((m) => m.huggingFaceUrl),
        ...ref.read(importedLitertModelsProvider).map((m) => m.huggingFaceUrl),
      }..removeWhere((url) => url.trim().isEmpty);

  Set<String> get _registeredFileNames => {
        ...ref.read(importedGgufModelsProvider).map((m) => m.name),
        ...ref.read(importedLitertModelsProvider).map((m) => m.name),
      };

  Future<void> _openRepo(String repoId) async {
    CancelToken? cancelToken;
    try {
      cancelToken = CancelToken();
      final files = await _searchService.listFiles(
        repoId: repoId,
        extension: '.gguf',
        token: _token,
        cancelToken: cancelToken,
      );
      // If no gguf files, try litertlm.
      final litertFiles = files.isEmpty
          ? await _searchService.listFiles(
              repoId: repoId,
              extension: '.litertlm',
              token: _token,
              cancelToken: cancelToken,
            )
          : <HuggingFaceModelFile>[];
      final allFiles = [...files, ...litertFiles];
      if (!mounted) return;
      final state = ref.read(unifiedModelSearchProvider);
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => ModelFileSheet(
          repoId: repoId,
          files: allFiles,
          showSplitModels: state.showSplitModels,
          addedUrls: _addedFileUrls,
          registeredUrls: _registeredUrls,
          registeredFileNames: _registeredFileNames,
          addedFileNames: _addedFileNames,
          onAddFile: (file) async {
            await _addFile(file);
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      cancelToken?.cancel();
    }
  }

  Future<void> _addFile(HuggingFaceModelFile file) async {
    final name = file.name.toLowerCase();
    final isLitert = name.endsWith('.litertlm');
    try {
      if (isLitert) {
        await ref.read(importedLitertModelsProvider.notifier).addFromUrl(
              file.downloadUrl,
              token: _token,
            );
      } else {
        await ref.read(importedGgufModelsProvider.notifier).addFromUrl(
              file.downloadUrl,
              huggingFaceToken: _token,
            );
      }
      if (!mounted) return;
      setState(() {
        _addedFileUrls.add(file.downloadUrl);
        _addedFileNames.add(file.name);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_l10n.add_model_file_added(file.name))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _pickLocalFile({required bool gguf}) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: gguf ? const ['gguf'] : const ['litertlm'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    final name = result.files.single.name;
    if (path == null) return;
    try {
      if (gguf) {
        await ref.read(importedGgufModelsProvider.notifier).importModel(path);
      } else {
        await ref.read(importedLitertModelsProvider.notifier).addFromPath(path);
      }
      if (!mounted) return;
      setState(() => _addedFileNames.add(name));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_l10n.add_model_file_added(name))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(unifiedModelSearchProvider);
    final notifier = ref.read(unifiedModelSearchProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(_l10n.add_model_title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          labelText: 'Search models',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: HugeIcon(icon: HugeIcons.strokeRoundedSearch01, size: 20),
                            onPressed: () {
                              notifier.setQuery(_searchController.text);
                              notifier.search();
                            },
                          ),
                        ),
                        onSubmitted: (v) {
                          notifier.setQuery(v);
                          notifier.search();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                const SizedBox(height: 8),
                ModelSearchFilterBar(state: state, notifier: notifier),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        notifier.setQuery(_searchController.text);
                        notifier.search();
                      },
                      child: Text(state.isLoading ? 'Searching...' : 'Search'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _pickLocalFile(gguf: true),
                      child: const Text('Pick GGUF'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _pickLocalFile(gguf: false),
                      child: const Text('Pick LiteRT'),
                    ),
                  ],
                ),
                if (state.error != null) ...[
                  const SizedBox(height: 8),
                  Text(state.error!, style: const TextStyle(color: Colors.red)),
                ],
                if (state.hiddenUnknownCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${state.hiddenUnknownCount} models with unknown size hidden',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
          if (state.isLoading)
            const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              itemCount: state.results.length,
              itemBuilder: (context, index) {
                final result = state.results[index];
                final already = _registeredUrls.contains(result.repoId) ||
                    _addedFileUrls.contains(result.repoId);
                return ModelSearchResultRow(
                  result: result,
                  alreadyAdded: already,
                  onTap: () => _openRepo(result.repoId),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
