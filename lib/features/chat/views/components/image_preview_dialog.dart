import 'dart:io';

import 'package:flutter/material.dart';

void showImagePreview(BuildContext context, String path) {
  showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (context) => _ImagePreviewDialog(path: path),
  );
}

class _ImagePreviewDialog extends StatelessWidget {
  const _ImagePreviewDialog({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Image.file(File(path)),
        ),
      ),
    );
  }
}
