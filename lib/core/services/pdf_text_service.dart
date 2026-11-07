import 'dart:io';

import 'package:pdfrx/pdfrx.dart';

/// The sole PDF entry point. PDFium is initialized lazily and document work
/// is serialized on pdfrx's existing worker, including disposal on failure.
class PdfTextService {
  PdfTextService({
    Future<void> Function()? initialize,
    Future<String?> Function(String)? extract,
  }) : _initialize = initialize ?? pdfrxFlutterInitialize,
       _extract = extract ?? _extractText;

  static final instance = PdfTextService();
  final Future<void> Function() _initialize;
  final Future<String?> Function(String) _extract;
  Future<void>? _initialization;
  Future<void> _tail = Future.value();

  Future<String?> read(String path) {
    final result = _tail.then((_) async {
      if (!await File(path).exists()) return null;
      await (_initialization ??= _initialize());
      return _extract(path);
    });
    // A malformed document must not poison the queue for subsequent reads.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result.catchError((Object _) => null);
  }

  static Future<String?> _extractText(String path) async {
    final document = await PdfDocument.openFile(path);
    try {
      final text = StringBuffer();
      for (final page in document.pages) {
        final pageText = await page.loadText();
        final content = pageText?.fullText.trim() ?? '';
        if (content.isEmpty) continue;
        if (text.isNotEmpty) text.writeln('\n--- Page ${page.pageNumber} ---');
        text.write(content);
      }
      final extracted = text.toString().trim();
      return extracted.isEmpty ? null : extracted;
    } finally {
      await document.dispose();
    }
  }
}
