import 'dart:convert';
import 'dart:io';

class AttachmentHelpers {
  AttachmentHelpers._();

  static const _imageExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp'};
  static const _textExtensions = {'txt', 'md'};

  static String extensionOf(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  static String fileNameOf(String path) =>
      path.split(Platform.pathSeparator).last;

  static bool isImagePath(String path) =>
      _imageExtensions.contains(extensionOf(path));

  static bool isTextPath(String path) =>
      _textExtensions.contains(extensionOf(path));

  static String mimeTypeForImage(String path) {
    return switch (extensionOf(path)) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };
  }

  static Future<String?> readTextFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  static Future<String?> readImageBase64(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return base64Encode(bytes);
    } catch (_) {
      return null;
    }
  }

  static String appendTextAttachment(String content, String fileName, String text) {
    final block = '--- $fileName ---\n$text';
    if (content.trim().isEmpty) return block;
    return '$content\n\n$block';
  }

  /// Copies [file] into [directory] under a timestamp-prefixed unique name
  /// and returns the new path, or null if the copy fails (e.g. a locked
  /// file or a permissions error) so callers can skip that one attachment
  /// instead of aborting the whole send.
  static Future<String?> saveAttachment(File file, Directory directory) async {
    try {
      final fileName = fileNameOf(file.path);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final newPath =
          '${directory.path}${Platform.pathSeparator}${timestamp}_$fileName';
      await file.copy(newPath);
      return newPath;
    } catch (_) {
      return null;
    }
  }
}
