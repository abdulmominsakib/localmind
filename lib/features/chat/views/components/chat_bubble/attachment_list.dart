import 'dart:io';
import 'package:flutter/material.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/chat/views/components/image_preview_dialog.dart';
import 'package:localmind/features/chat/utils/attachment_helpers.dart';
import 'package:localmind/features/chat/views/components/audio_player_widget.dart';

class AttachmentList extends StatelessWidget {
  const AttachmentList({super.key, required this.paths, required this.isUser});

  final List<String> paths;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: paths.map((path) => _AttachmentItem(path: path)).toList(),
    );
  }
}

class _AttachmentItem extends StatelessWidget {
  const _AttachmentItem({required this.path});

  final String path;

  void _viewImage(BuildContext context) {
    showImagePreview(context, path);
  }

  void _viewText(BuildContext context) async {
    final text = await AttachmentHelpers.readTextFile(path);
    if (!context.mounted) return;
    if (text == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read file')),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _TextPreviewSheet(
        fileName: AttachmentHelpers.fileNameOf(path),
        text: text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final file = File(path);
    final fileName = AttachmentHelpers.fileNameOf(path);

    if (AttachmentHelpers.isImagePath(path)) {
      return GestureDetector(
        onTap: () => _viewImage(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            file,
            width: 120,
            height: 120,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _FilePlaceholder(fileName: fileName),
          ),
        ),
      );
    }

    if (AttachmentHelpers.isTextPath(path)) {
      return GestureDetector(
        onTap: () => _viewText(context),
        child: Container(
          width: 180,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurfaceCard : AppColors.lightSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.description_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  fileName,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (path.toLowerCase().endsWith('.mp3') ||
        path.toLowerCase().endsWith('.wav') ||
        path.toLowerCase().endsWith('.ogg') ||
        path.toLowerCase().endsWith('.flac') ||
        path.toLowerCase().endsWith('.aac') ||
        path.toLowerCase().endsWith('.m4a') ||
        path.toLowerCase().endsWith('.wma') ||
        path.toLowerCase().endsWith('.opus')) {
      return AudioPlayerWidget(source: path);
    }

    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceCard : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            size: 20,
            color: isDark ? AppColors.darkMutedText : AppColors.lightMutedText,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              fileName,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _TextPreviewSheet extends StatelessWidget {
  const _TextPreviewSheet({required this.fileName, required this.text});

  final String fileName;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Material(
          color: isDark ? const Color(0xFF121212) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF444444) : const Color(0xFFDDDDDD),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.description_outlined, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fileName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    text,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      fontFamily: AttachmentHelpers.isTextPath(fileName)
                          ? 'monospace'
                          : null,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FilePlaceholder extends StatelessWidget {
  const _FilePlaceholder({required this.fileName});
  final String fileName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      color: Colors.grey[800],
      child: Center(
        child: Text(
          AttachmentHelpers.extensionOf(fileName).toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
