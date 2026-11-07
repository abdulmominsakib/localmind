import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../data/huggingface_model_search_service.dart';
import '../../utils/gguf_file_classifier.dart';

class ModelFileSheet extends StatelessWidget {
  const ModelFileSheet({
    super.key,
    required this.repoId,
    required this.files,
    required this.showSplitModels,
    required this.addedUrls,
    required this.registeredUrls,
    required this.registeredFileNames,
    required this.addedFileNames,
    required this.onAddFile,
  });

  final String repoId;
  final List<HuggingFaceModelFile> files;
  final bool showSplitModels;
  final Set<String> addedUrls;
  final Set<String> registeredUrls;
  final Set<String> registeredFileNames;
  final Set<String> addedFileNames;
  final Future<void> Function(HuggingFaceModelFile file) onAddFile;

  @override
  Widget build(BuildContext context) {
    final visible = files.where((f) {
      if (isProjectorFile(f.path)) return false;
      if (isSplitModelFile(f.path) && !showSplitModels) return false;
      return true;
    }).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              repoId,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            if (visible.isEmpty)
              const Text('No model files found.')
            else
              ...visible.map((file) {
                final isSplit = isSplitModelFile(file.path);
                final already = addedUrls.contains(file.downloadUrl) ||
                    registeredUrls.contains(file.downloadUrl) ||
                    registeredFileNames.contains(file.name) ||
                    addedFileNames.contains(file.name);
                return ListTile(
                  title: Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(_formatBytes(file.size)),
                  trailing: isSplit
                      ? const _SplitBadge()
                      : ElevatedButton(
                          onPressed: already
                              ? null
                              : () async {
                                  await onAddFile(file);
                                },
                          child: Text(already ? 'Added' : 'Add'),
                        ),
                );
              }),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double value = bytes.toDouble();
    int unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    final decimals = unitIndex == 0 ? 0 : (value < 10 ? 2 : 1);
    return '${value.toStringAsFixed(decimals)} ${units[unitIndex]}';
  }
}

class _SplitBadge extends StatelessWidget {
  const _SplitBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedAlert01,
            size: 12,
            color: Colors.amber,
          ),
          const SizedBox(width: 4),
          const Text('Split model', style: TextStyle(fontSize: 10, color: Colors.amber)),
        ],
      ),
    );
  }
}
