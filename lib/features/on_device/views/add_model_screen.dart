import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/providers/service_providers.dart';
import 'package:localmind/features/on_device/data/huggingface_model_search_service.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';

class AddOnDeviceModelScreen extends ConsumerStatefulWidget {
  const AddOnDeviceModelScreen({super.key});

  @override
  ConsumerState<AddOnDeviceModelScreen> createState() =>
      _AddOnDeviceModelScreenState();
}

class _AddOnDeviceModelScreenState
    extends ConsumerState<AddOnDeviceModelScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _ggufUrlController = TextEditingController();
  final TextEditingController _ggufSearchController = TextEditingController();
  final TextEditingController _litertUrlController = TextEditingController();
  final TextEditingController _litertSearchController = TextEditingController();

  List<HuggingFaceModelSearchResult> _ggufRepos = [];

  List<HuggingFaceModelSearchResult> _litertRepos = [];

  bool _isSearching = false;
  bool _isLoadingFiles = false;
  String? _error;
  CancelToken? _activeCancelToken;
  final Set<String> _addedFileUrls = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _activeCancelToken?.cancel('Screen disposed');
    _tabController.dispose();
    _ggufUrlController.dispose();
    _ggufSearchController.dispose();
    _litertUrlController.dispose();
    _litertSearchController.dispose();
    super.dispose();
  }

  HuggingFaceModelSearchService get _searchService =>
      HuggingFaceModelSearchService(dio: ref.read(dioProvider));

  String? get _token => ref.read(settingsProvider).huggingFaceToken;

  Future<void> _addGgufFromUrl() async {
    final url = _ggufUrlController.text.trim();
    if (url.isEmpty) return;
    try {
      await ref.read(importedGgufModelsProvider.notifier).addFromUrl(
            url,
            huggingFaceToken: _token,
          );
      if (!mounted) return;
      setState(() => _addedFileUrls.add(url));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GGUF model added')),
      );
      _ggufUrlController.clear();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _addLitertFromUrl() async {
    final url = _litertUrlController.text.trim();
    if (url.isEmpty) return;
    try {
      await ref.read(importedLitertModelsProvider.notifier).addFromUrl(
            url,
            token: _token,
          );
      if (!mounted) return;
      setState(() => _addedFileUrls.add(url));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('LiteRT model added')),
      );
      _litertUrlController.clear();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pickLitertFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['litertlm'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    try {
      final model = await ref
          .read(importedLitertModelsProvider.notifier)
          .addFromPath(path);
      if (!mounted) return;
      setState(() => _addedFileUrls.add(model.huggingFaceUrl));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${model.name} added')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pickGgufFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gguf'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    try {
      await ref.read(importedGgufModelsProvider.notifier).importModel(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GGUF model added')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _searchGguf() async {
    _activeCancelToken?.cancel('New search started');
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;

    setState(() {
      _isSearching = true;
      _error = null;
    });
    try {
      final repos = await _searchService.searchModels(
        query: _ggufSearchController.text.trim().isEmpty
            ? 'gguf'
            : _ggufSearchController.text.trim(),
        token: _token,
        cancelToken: cancelToken,
      );
      if (!mounted || cancelToken.isCancelled) return;
      setState(() => _ggufRepos = repos);
    } on DioException catch (e) {
      if (!mounted || CancelToken.isCancel(e)) return;
      setState(() => _error = e.toString());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted && identical(_activeCancelToken, cancelToken)) {
        _activeCancelToken = null;
        setState(() => _isSearching = false);
      }
    }
  }

  Future<void> _openGgufRepo(String repoId) async {
    _activeCancelToken?.cancel('New repository opened');
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;

    setState(() {
      _isLoadingFiles = true;
      _error = null;
    });
    try {
      final files = await _searchService.listFiles(
        repoId: repoId,
        extension: '.gguf',
        token: _token,
        cancelToken: cancelToken,
      );
      if (!mounted || cancelToken.isCancelled) return;
      _showGgufFileSheet(repoId, files);
    } on DioException catch (e) {
      if (!mounted || CancelToken.isCancel(e)) return;
      setState(() => _error = e.toString());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted && identical(_activeCancelToken, cancelToken)) {
        _activeCancelToken = null;
        setState(() => _isLoadingFiles = false);
      }
    }
  }

  Future<void> _addGgufFile(HuggingFaceModelFile file) async {
    try {
      await ref.read(importedGgufModelsProvider.notifier).addFromUrl(
            file.downloadUrl,
            huggingFaceToken: _token,
          );
      if (!mounted) return;
      setState(() => _addedFileUrls.add(file.downloadUrl));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${file.name} added')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _searchLitert() async {
    _activeCancelToken?.cancel('New search started');
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;

    setState(() {
      _isSearching = true;
      _error = null;
    });
    try {
      final repos = await _searchService.searchModels(
        query: _litertSearchController.text.trim(),
        author: 'litert-community',
        token: _token,
        cancelToken: cancelToken,
      );
      if (!mounted || cancelToken.isCancelled) return;
      setState(() => _litertRepos = repos);
    } on DioException catch (e) {
      if (!mounted || CancelToken.isCancel(e)) return;
      setState(() => _error = e.toString());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted && identical(_activeCancelToken, cancelToken)) {
        _activeCancelToken = null;
        setState(() => _isSearching = false);
      }
    }
  }

  Future<void> _openLitertRepo(String repoId) async {
    _activeCancelToken?.cancel('New repository opened');
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;

    setState(() {
      _isLoadingFiles = true;
      _error = null;
    });
    try {
      final files = await _searchService.listFiles(
        repoId: repoId,
        extension: '.litertlm',
        token: _token,
        cancelToken: cancelToken,
      );
      if (!mounted || cancelToken.isCancelled) return;
      _showLitertFileSheet(repoId, files);
    } on DioException catch (e) {
      if (!mounted || CancelToken.isCancel(e)) return;
      setState(() => _error = e.toString());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted && identical(_activeCancelToken, cancelToken)) {
        _activeCancelToken = null;
        setState(() => _isLoadingFiles = false);
      }
    }
  }

  void _showGgufFileSheet(String repoId, List<HuggingFaceModelFile> files) {
    final added = Set<String>.from(_addedFileUrls);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Files in $repoId',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    if (files.isEmpty)
                      const Text('No GGUF files found.')
                    else
                      ...files.map((file) => ListTile(
                            title: Text(file.name),
                            subtitle: Text('${file.size} bytes'),
                            trailing: ElevatedButton(
                              onPressed: added.contains(file.downloadUrl)
                                  ? null
                                  : () async {
                                      await _addGgufFile(file);
                                      if (!mounted) return;
                                      setSheetState(() {
                                        added.add(file.downloadUrl);
                                      });
                                    },
                              child: Text(
                                added.contains(file.downloadUrl) ? 'Added' : 'Add',
                              ),
                            ),
                          )),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showLitertFileSheet(String repoId, List<HuggingFaceModelFile> files) {
    final added = Set<String>.from(_addedFileUrls);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Files in $repoId',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    if (files.isEmpty)
                      const Text('No LiteRT files found.')
                    else
                      ...files.map((file) => ListTile(
                            title: Text(file.name),
                            subtitle: Text('${file.size} bytes'),
                            trailing: ElevatedButton(
                              onPressed: added.contains(file.downloadUrl)
                                  ? null
                                  : () async {
                                      await _addLitertFile(file);
                                      if (!mounted) return;
                                      setSheetState(() {
                                        added.add(file.downloadUrl);
                                      });
                                    },
                              child: Text(
                                added.contains(file.downloadUrl) ? 'Added' : 'Add',
                              ),
                            ),
                          )),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _cancelActiveRequest() {
    _activeCancelToken?.cancel('User canceled');
    _activeCancelToken = null;
    if (mounted) {
      setState(() {
        _isSearching = false;
        _isLoadingFiles = false;
      });
    }
  }

  Future<void> _addLitertFile(HuggingFaceModelFile file) async {
    try {
      await ref.read(importedLitertModelsProvider.notifier).addFromUrl(
            file.downloadUrl,
            token: _token,
          );
      if (!mounted) return;
      setState(() => _addedFileUrls.add(file.downloadUrl));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${file.name} added')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Add model'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'GGUF'),
            Tab(text: 'LiteRT'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGgufTab(context),
          _buildLitertTab(context),
        ],
      ),
    );
  }

  Widget _buildGgufTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _ggufUrlController,
          decoration: const InputDecoration(
            labelText: 'Hugging Face GGUF URL',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton(
              onPressed: _addGgufFromUrl,
              child: const Text('Add from URL'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _pickGgufFile,
              child: const Text('Pick local file'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _ggufSearchController,
          decoration: const InputDecoration(
            labelText: 'Search GGUF models',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _searchGguf(),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _isSearching ? null : _searchGguf,
          child: Text(_isSearching ? 'Searching...' : 'Search'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 16),
        if (_isLoadingFiles) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              const Expanded(child: Text('Loading files...')),
              TextButton(
                onPressed: _cancelActiveRequest,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
        ..._ggufRepos.map((repo) => ListTile(
              title: Text(repo.repoId),
              subtitle: Text('${repo.downloads} downloads'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _isLoadingFiles ? null : () => _openGgufRepo(repo.repoId),
            )),
      ],
    );
  }

  Widget _buildLitertTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _litertUrlController,
          decoration: const InputDecoration(
            labelText: 'Hugging Face LiteRT URL',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton(
              onPressed: _addLitertFromUrl,
              child: const Text('Add from URL'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _pickLitertFile,
              child: const Text('Pick local file'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _litertSearchController,
          decoration: const InputDecoration(
            labelText: 'Search LiteRT models',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _searchLitert(),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _isSearching ? null : _searchLitert,
          child: Text(_isSearching ? 'Searching...' : 'Search'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 16),
        if (_isLoadingFiles) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              const Expanded(child: Text('Loading files...')),
              TextButton(
                onPressed: _cancelActiveRequest,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
        ..._litertRepos.map((repo) => ListTile(
              title: Text(repo.repoId),
              subtitle: Text('${repo.downloads} downloads'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _isLoadingFiles ? null : () => _openLitertRepo(repo.repoId),
            )),
      ],
    );
  }
}
