import 'dart:typed_data';

// Stub implementation for non-web platforms
Future<void> copyImageWebImpl(Uint8List imageBytes) async {
  throw UnsupportedError('Web clipboard operations are only supported on web');
}

Future<Uint8List?> pasteImageWebImpl() async {
  throw UnsupportedError('Web clipboard operations are only supported on web');
}

Future<String> pasteTextWebImpl() async {
  throw UnsupportedError('Web clipboard operations are only supported on web');
}

Future<void> copyRichTextWebImpl(String text, String? html) async {
  throw UnsupportedError('Web clipboard operations are only supported on web');
}

// Note: This needs to return EnhancedClipboardData, but we can't import it here
// So we'll use dynamic and cast it in the main file
Future<dynamic> pasteRichTextWebImpl() async {
  throw UnsupportedError('Web clipboard operations are only supported on web');
}
