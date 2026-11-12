import '../engine/engine_observer.dart';

/// The container format of a model file, which selects the runtime that
/// loads it.
///
/// On native platforms `LlamaEngine(LlamaBackend())` reads a model file's
/// header to choose the runtime, so a model whose path or URL has no model
/// extension still loads in the right one. Web URL loads cannot read the file
/// before the runtime fetches it, so they route by the URL's extension; pass a
/// format explicitly, as in `ModelSource.url(uri, format: ModelFormat.liteRtLm)`,
/// when the URL has none.
enum ModelFormat {
  /// A GGUF file, run by llama.cpp.
  gguf(LlamaRuntime.llamaCpp, '.gguf', [0x47, 0x47, 0x55, 0x46]),

  /// A LiteRT-LM `.litertlm` bundle, run by LiteRT-LM.
  liteRtLm(LlamaRuntime.liteRtLm, '.litertlm', [
    0x4C,
    0x49,
    0x54,
    0x45,
    0x52,
    0x54,
    0x4C,
    0x4D,
  ]);

  const ModelFormat(this.runtime, this.extension, this._magic);

  /// The runtime that loads this format.
  final LlamaRuntime runtime;

  /// The lowercase file extension of this format, including the dot.
  final String extension;

  final List<int> _magic;

  /// The number of leading file bytes [fromHeader] needs to recognize every
  /// format.
  static const int headerLength = 8;

  /// The format whose magic bytes start [header], or null when [header]
  /// matches none.
  ///
  /// A GGUF file starts with `GGUF` and a LiteRT-LM bundle with `LITERTLM`.
  /// Pass at least [headerLength] bytes.
  static ModelFormat? fromHeader(List<int> header) {
    for (final format in values) {
      final magic = format._magic;
      if (header.length < magic.length) continue;
      var matches = true;
      for (var i = 0; i < magic.length; i++) {
        if (header[i] != magic[i]) {
          matches = false;
          break;
        }
      }
      if (matches) return format;
    }
    return null;
  }

  /// The format named by the file extension of [pathOrUrl], ignoring case,
  /// or null when it has no model extension.
  ///
  /// A URL with a scheme, such as `https:` or `blob:`, counts only its path,
  /// not its query or fragment. A string without a scheme is read as a file
  /// path, so `?` and `#` in it are literal; when that has no model extension
  /// it is read as a relative URL, such as `models/a.litertlm?v=2`. An
  /// extension is only a hint: a native load reads the file header instead
  /// whenever it can.
  static ModelFormat? fromPath(String pathOrUrl) {
    final uri = Uri.tryParse(pathOrUrl);
    // A one-letter scheme is a Windows drive letter, not a URL.
    final isUrl = uri != null && uri.scheme.length > 1;
    if (!isUrl) {
      final literal = _fromExtension(pathOrUrl);
      if (literal != null || uri == null) return literal;
    }
    return _fromExtension(uri.path);
  }

  static ModelFormat? _fromExtension(String path) {
    final lower = path.toLowerCase();
    for (final format in values) {
      if (lower.endsWith(format.extension)) return format;
    }
    return null;
  }
}
