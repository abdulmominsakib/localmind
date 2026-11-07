/// Canonicalizes a Hugging Face file URL so equivalent forms dedupe.
///
/// Normalization rules:
/// - scheme is forced to https
/// - host is normalized to huggingface.co
/// - the `/blob/` action segment is rewritten to `/resolve/`
/// - query strings and fragments are dropped
/// - trailing slashes are removed
/// - path segments are percent-decoded for comparison stability
Uri canonicalizeHuggingFaceUrl(String input, {String? emptyMessage}) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw FormatException(emptyMessage ?? 'Enter a Hugging Face URL.');
  }

  final withScheme =
      trimmed.startsWith('http://') || trimmed.startsWith('https://')
      ? trimmed
      : 'https://huggingface.co/$trimmed';

  final uri = Uri.parse(withScheme);
  final host = uri.host.toLowerCase();
  if (host != 'huggingface.co' &&
      host != 'www.huggingface.co' &&
      host != 'hf.co') {
    throw const FormatException(
      'Only official Hugging Face URLs are supported.',
    );
  }

  if (uri.scheme.toLowerCase() != 'https') {
    throw const FormatException('Use an HTTPS Hugging Face URL.');
  }

  final segments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .map((segment) => Uri.decodeComponent(segment))
      .toList();

  if (segments.length >= 3 && segments[2].toLowerCase() == 'blob') {
    segments[2] = 'resolve';
  }

  final path = segments.isEmpty ? '/' : '/${segments.join('/')}';
  return Uri(scheme: 'https', host: 'huggingface.co', path: path);
}
