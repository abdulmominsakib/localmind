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
  final TextEditingController _litertSearchController = TextEditingController();

  List<HuggingFaceModelSearchResult> _ggufRepos = [];
  List<HuggingFaceModelFile> _ggufFiles = [];
  String? _selectedGgufRepo;

  List<HuggingFaceModelSearchResult> _litertRepos = [];
  List<HuggingFaceModelFile> _litertFiles = [];
  String? _selectedLitertRepo;

  bool _isSearching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ggufUrlController.dispose();
    _ggufSearchController.dispose();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GGUF model added')),
      );
      _ggufUrlController.clear();
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
    setState(() {
      _isSearching = true;
      _error = null;
      _ggufFiles = [];
      _selectedGgufRepo = null;
    });
    try {
      final repos = await _searchService.searchModels(
        query: _ggufSearchController.text.trim().isEmpty
            ? 'gguf'
            : _ggufSearchController.text.trim(),
        token: _token,
      );
      if (!mounted) return;
      setState(() => _ggufRepos = repos);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _openGgufRepo(String repoId) async {
    setState(() {
      _isSearching = true;
      _error = null;
    });
    try {
      final files = await _searchService.listFiles(
        repoId: repoId,
        extension: '.gguf',
        token: _token,
      );
      if (!mounted) return;
      setState(() {
        _selectedGgufRepo = repoId;
        _ggufFiles = files;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _addGgufFile(HuggingFaceModelFile file) async {
    try {
      await ref.read(importedGgufModelsProvider.notifier).addFromUrl(
            file.downloadUrl,
            huggingFaceToken: _token,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${file.name} added')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _searchLitert() async {
    setState(() {
      _isSearching = true;
      _error = null;
      _litertFiles = [];
      _selectedLitertRepo = null;
    });
    try {
      final repos = await _searchService.searchModels(
        query: _litertSearchController.text.trim(),
        author: 'litert-community',
        token: _token,
      );
      if (!mounted) return;
      setState(() => _litertRepos = repos);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _openLitertRepo(String repoId) async {
    setState(() {
      _isSearching = true;
      _error = null;
    });
    try {
      final files = await _searchService.listFiles(
        repoId: repoId,
        extension: '.litertlm',
        token: _token,
      );
      if (!mounted) return;
      setState(() {
        _selectedLitertRepo = repoId;
        _litertFiles = files;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _addLitertFile(HuggingFaceModelFile file) async {
    try {
      await ref.read(importedLitertModelsProvider.notifier).addFromUrl(
            file.downloadUrl,
            token: _token,
          );
      if (!mounted) return;
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
        ..._ggufRepos.map((repo) => ListTile(
              title: Text(repo.repoId),
              subtitle: Text('${repo.downloads} downloads'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openGgufRepo(repo.repoId),
            )),
        if (_selectedGgufRepo != null) ...[
          const SizedBox(height: 8),
          Text('Files in $_selectedGgufRepo'),
          ..._ggufFiles.map((file) => ListTile(
                title: Text(file.name),
                subtitle: Text('${file.size} bytes'),
                trailing: ElevatedButton(
                  onPressed: () => _addGgufFile(file),
                  child: const Text('Add'),
                ),
              )),
        ],
      ],
    );
  }

  Widget _buildLitertTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
        ..._litertRepos.map((repo) => ListTile(
              title: Text(repo.repoId),
              subtitle: Text('${repo.downloads} downloads'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openLitertRepo(repo.repoId),
            )),
        if (_selectedLitertRepo != null) ...[
          const SizedBox(height: 8),
          Text('Files in $_selectedLitertRepo'),
          ..._litertFiles.map((file) => ListTile(
                title: Text(file.name),
                subtitle: Text('${file.size} bytes'),
                trailing: ElevatedButton(
                  onPressed: () => _addLitertFile(file),
                  child: const Text('Add'),
                ),
              )),
        ],
      ],
    );
  }
}
