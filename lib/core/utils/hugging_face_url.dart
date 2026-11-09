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

/// Parsed Hugging Face repository metadata extracted from a file URL.
class HuggingFaceUrlMetadata {
  final String? repoId;
  final String? rfilename;
  final String? revision;

  const HuggingFaceUrlMetadata({this.repoId, this.rfilename, this.revision});
}

/// Best-effort extraction of repoId/rfilename/revision from a Hugging Face URL.
/// Returns null fields when the information is not available.
HuggingFaceUrlMetadata parseHuggingFaceUrlMetadata(String url) {
  Uri uri;
  try {
    uri = Uri.parse(url.trim());
  } catch (_) {
    return const HuggingFaceUrlMetadata();
  }
  final segs = uri.pathSegments
      .where((s) => s.isNotEmpty)
      .map(Uri.decodeComponent)
      .toList();
  if (segs.length < 2) return const HuggingFaceUrlMetadata();

  final repoId = '${segs[0]}/${segs[1]}';

  // Find the action marker (resolve/blob/raw).
  final markerIdx = segs.indexWhere(
    (s) => s.toLowerCase() == 'resolve' ||
        s.toLowerCase() == 'blob' ||
        s.toLowerCase() == 'raw',
  );

  String? revision;
  String? rfilename;

  if (markerIdx >= 0 && markerIdx + 1 < segs.length) {
    final candidateRevision = segs[markerIdx + 1];
    // Match addFromUrl: only set revision when not 'main'/'master'.
    if (candidateRevision.toLowerCase() != 'main' &&
        candidateRevision.toLowerCase() != 'master') {
      revision = candidateRevision;
    }
    if (markerIdx + 2 < segs.length) {
      rfilename = segs.sublist(markerIdx + 2).join('/');
    }
  }

  // If no marker, treat last segment as filename (repo root or tree).
  if (rfilename == null && markerIdx < 0) {
    rfilename = segs.isNotEmpty ? segs.last : null;
  }

  if (rfilename != null && rfilename.trim().isEmpty) rfilename = null;
  if (repoId.trim().isEmpty) {
    return const HuggingFaceUrlMetadata();
  }

  return HuggingFaceUrlMetadata(
    repoId: repoId,
    rfilename: rfilename,
    revision: revision,
  );
}
