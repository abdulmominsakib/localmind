import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The kind of model source represented by a [ModelSource].
enum ModelSourceKind {
  /// A local filesystem path supplied explicitly by the caller.
  path,

  /// An HTTP or HTTPS URL.
  http,

  /// A Hugging Face repository reference.
  huggingFace,
}

/// Describes where a model file can be loaded from.
///
/// [ModelSource] is a value object only; creating one does not perform network
/// or filesystem access.
class ModelSource {
  /// Creates a local filesystem path model source.
  factory ModelSource.path(String path) {
    if (path.isEmpty) {
      throw ArgumentError.value(path, 'path', 'Path must not be empty.');
    }
    return ModelSource._(
      kind: ModelSourceKind.path,
      path: path,
      fileName: _fileNameFromPath(path),
      canonicalKey: 'path:$path',
    );
  }

  /// Creates an HTTP(S) URL model source.
  factory ModelSource.url(Uri url, {String? fileName}) {
    if (url.scheme != 'http' && url.scheme != 'https') {
      throw ArgumentError.value(
        url,
        'url',
        'Only http and https URLs are supported.',
      );
    }
    if (!url.hasAuthority || url.host.isEmpty) {
      throw ArgumentError.value(
        url,
        'url',
        'HTTP(S) model URLs must include a host.',
      );
    }
    final inferredFileName = fileName == null
        ? _fileNameFromUri(url)
        : _validateRemoteFileName(fileName, 'fileName');
    return ModelSource._(
      kind: ModelSourceKind.http,
      url: url,
      fileName: inferredFileName,
      canonicalKey: fileName == null
          ? url.toString()
          : 'url:${url.toString()}\nfileName:$inferredFileName',
    );
  }

  /// Creates a Hugging Face model source from repository details.
  ///
  /// The generated download URL uses Hugging Face's `/resolve/{revision}/...`
  /// endpoint. [revision] defaults to `main`; use a branch, tag, commit SHA, or
  /// pull-request ref such as `refs/pr/12` when a model must be pinned.
  factory ModelSource.huggingFace({
    required String repoId,
    required String filePath,
    String revision = 'main',
    String? fileName,
  }) {
    final normalizedRepoId = _validateRepoId(repoId);
    final normalizedRevision = _validateRevision(revision);
    final normalizedFilePath = _validateFilePath(filePath);
    final resolvedUri = _huggingFaceResolvedUri(
      normalizedRepoId,
      normalizedRevision,
      normalizedFilePath,
    );
    return ModelSource._(
      kind: ModelSourceKind.huggingFace,
      url: resolvedUri,
      repoId: normalizedRepoId,
      revision: normalizedRevision,
      filePath: normalizedFilePath,
      fileName: _validateRemoteFileName(
        fileName ?? _fileNameFromPath(normalizedFilePath),
        'fileName',
      ),
      canonicalKey: _huggingFaceCanonicalKey(
        normalizedRepoId,
        normalizedRevision,
        normalizedFilePath,
      ),
    );
  }

  /// Parses [value] as a local path, HTTP(S) URL, or `hf://` reference.
  ///
  /// Hugging Face references use `hf://owner/repo/path/to/model-file`. A simple
  /// branch or tag can be written as `hf://owner/repo@revision/model-file`; use
  /// `?revision=refs/pr/12` when the revision itself contains `/`.
  factory ModelSource.parse(String value) {
    if (value.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Source must not be empty.');
    }

    if (value.startsWith('hf://')) {
      return _parseHuggingFaceUri(value);
    }

    final parsedUri = Uri.tryParse(value);
    if (parsedUri != null && parsedUri.hasScheme) {
      if (parsedUri.scheme == 'http' || parsedUri.scheme == 'https') {
        return ModelSource.url(parsedUri);
      }
      if (_looksLikeWindowsPath(value, parsedUri.scheme)) {
        return ModelSource.path(value);
      }
      throw ArgumentError.value(
        value,
        'value',
        'Unsupported model source scheme: ${parsedUri.scheme}.',
      );
    }

    return ModelSource.path(value);
  }

  const ModelSource._({
    required this.kind,
    required this.fileName,
    required this.canonicalKey,
    this.path,
    this.url,
    this.repoId,
    this.revision,
    this.filePath,
  });

  /// The source kind.
  final ModelSourceKind kind;

  /// The local path when [kind] is [ModelSourceKind.path].
  final String? path;

  /// The resolved remote URI for HTTP(S) and Hugging Face sources.
  final Uri? url;

  /// The Hugging Face repository id (`owner/repo`) when applicable.
  final String? repoId;

  /// The Hugging Face revision when applicable.
  final String? revision;

  /// The Hugging Face file path inside the repository when applicable.
  final String? filePath;

  /// The inferred or supplied model file name.
  final String fileName;

  /// A canonical identity string used for deterministic cache keys.
  final String canonicalKey;

  /// Whether this source is a local filesystem path.
  bool get isLocal => kind == ModelSourceKind.path;

  /// Whether this source resolves to a remote URI.
  bool get isRemote => !isLocal;

  /// The remote URI to load or download, if any.
  Uri? get resolvedUri => url;

  /// The URL scheme for remote sources or `path` for local sources.
  String get scheme => isLocal ? 'path' : url!.scheme;

  /// Human-friendly source name suitable for logs.
  String get displayName => fileName;

  /// SHA-256 digest of [canonicalKey], used as a deterministic cache key.
  String get cacheKey => sha256.convert(utf8.encode(canonicalKey)).toString();

  /// Redacted source identity suitable for persisted metadata and logs.
  ///
  /// [canonicalKey] intentionally remains the full source identity so cache keys
  /// stay unique for signed URLs. This value omits raw URL query strings while
  /// including [cacheKey] so persisted metadata can still be correlated with the
  /// deterministic cache entry without storing credentials.
  String get metadataSourceKey {
    if (kind == ModelSourceKind.http) {
      final redactedUri = _uriWithoutQueryOrFragment(url!);
      return 'url:${redactedUri.toString()}#cacheKey=$cacheKey';
    }
    return canonicalKey;
  }

  /// Safe deterministic cache directory name for this source.
  String get cacheDirectoryName {
    final stem = _fileStem(fileName);
    final safeStem = _safeName(stem.isEmpty ? 'model' : stem);
    return '$safeStem-${cacheKey.substring(0, 12)}';
  }

  @override
  String toString() => metadataSourceKey;

  /// Returns a copy that downloads/loads from [resolvedUri] while preserving
  /// this source's canonical cache identity.
  ///
  /// This is intended for resolvers that translate a stable user-facing source
  /// such as `hf://owner/repo/model.gguf` or
  /// `hf://owner/repo/model.litertlm` to a concrete HTTP(S) URL. Cache
  /// operations should still use the original [canonicalKey], [cacheKey], and
  /// [cacheDirectoryName] so entries remain discoverable by the caller's source.
  ModelSource withResolvedUri(Uri resolvedUri) {
    if (isLocal) {
      throw StateError('Local model sources cannot be resolved to a URL.');
    }
    _validateRemoteUri(resolvedUri, 'resolvedUri');
    return ModelSource._(
      kind: kind,
      url: resolvedUri,
      repoId: repoId,
      revision: revision,
      filePath: filePath,
      fileName: fileName,
      canonicalKey: canonicalKey,
    );
  }
}

void _validateRemoteUri(Uri url, String name) {
  if (url.scheme != 'http' && url.scheme != 'https') {
    throw ArgumentError.value(
      url,
      name,
      'Only http and https URLs are supported.',
    );
  }
  if (!url.hasAuthority || url.host.isEmpty) {
    throw ArgumentError.value(
      url,
      name,
      'HTTP(S) model URLs must include a host.',
    );
  }
}

ModelSource _parseHuggingFaceUri(String value) {
  final reference = value.substring('hf://'.length);
  if (reference.isEmpty || reference.contains('#')) {
    throw ArgumentError.value(
      value,
      'value',
      'Invalid Hugging Face reference.',
    );
  }

  final queryStart = reference.indexOf('?');
  final pathReference = queryStart == -1
      ? reference
      : reference.substring(0, queryStart);
  final queryRevision = queryStart == -1
      ? null
      : _parseHuggingFaceRevisionQuery(
          reference.substring(queryStart + 1),
          value,
        );

  if (pathReference.isEmpty || pathReference.contains('//')) {
    throw ArgumentError.value(
      value,
      'value',
      'Invalid Hugging Face reference.',
    );
  }

  final rawParts = pathReference.split('/');
  if (rawParts.length < 3) {
    throw ArgumentError.value(
      value,
      'value',
      'Hugging Face references require owner, repo, and file path.',
    );
  }

  final owner = rawParts[0];
  final repoAndRevision = rawParts[1];
  if (owner.isEmpty || repoAndRevision.isEmpty) {
    throw ArgumentError.value(value, 'value', 'Invalid Hugging Face repo id.');
  }

  final repoRevisionParts = repoAndRevision.split('@');
  if (repoRevisionParts.length > 2 || repoRevisionParts.first.isEmpty) {
    throw ArgumentError.value(value, 'value', 'Invalid Hugging Face repo id.');
  }
  final inlineRevision = repoRevisionParts.length == 2
      ? repoRevisionParts[1]
      : null;
  if (inlineRevision != null && queryRevision != null) {
    throw ArgumentError.value(
      value,
      'value',
      'Use either @revision or ?revision=, not both.',
    );
  }
  final revision = queryRevision ?? inlineRevision ?? 'main';
  final repoId = '$owner/${repoRevisionParts.first}';
  final decodedFileSegments = rawParts
      .skip(2)
      .map((segment) {
        if (segment.isEmpty) {
          throw ArgumentError.value(
            value,
            'value',
            'Hugging Face file path contains an empty segment.',
          );
        }
        final decodedSegment = _decodeHuggingFacePathSegment(segment, value);
        if (decodedSegment.contains('/') || decodedSegment.contains('\\')) {
          throw ArgumentError.value(
            value,
            'value',
            'Hugging Face file path contains an encoded separator.',
          );
        }
        return decodedSegment;
      })
      .toList(growable: false);

  return ModelSource.huggingFace(
    repoId: repoId,
    revision: revision,
    filePath: decodedFileSegments.join('/'),
  );
}

String _parseHuggingFaceRevisionQuery(String rawQuery, String value) {
  if (rawQuery.isEmpty) {
    throw ArgumentError.value(
      value,
      'value',
      'Hugging Face reference query must include revision=...',
    );
  }

  String? revision;
  for (final pair in rawQuery.split('&')) {
    if (pair.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Invalid Hugging Face query.');
    }
    final separator = pair.indexOf('=');
    final rawKey = separator == -1 ? pair : pair.substring(0, separator);
    final rawValue = separator == -1 ? '' : pair.substring(separator + 1);
    final key = _decodeHuggingFaceQueryComponent(rawKey, value);
    if (key != 'revision') {
      throw ArgumentError.value(
        value,
        'value',
        'Unsupported Hugging Face query parameter: $key.',
      );
    }
    if (revision != null) {
      throw ArgumentError.value(
        value,
        'value',
        'Hugging Face revision query must appear only once.',
      );
    }
    revision = _decodeHuggingFaceQueryComponent(rawValue, value);
  }

  return revision ?? '';
}

String _huggingFaceCanonicalKey(
  String repoId,
  String revision,
  String filePath,
) {
  final encodedFilePath = _encodedHuggingFaceFilePath(filePath);
  if (!revision.contains('/') &&
      revision == Uri.encodeComponent(revision) &&
      filePath == encodedFilePath) {
    return 'hf://$repoId@$revision/$filePath';
  }

  final encodedRevision = Uri.encodeQueryComponent(revision);
  return 'hf://$repoId/$encodedFilePath?revision=$encodedRevision';
}

Uri _huggingFaceResolvedUri(String repoId, String revision, String filePath) {
  final encodedRepoId = repoId.split('/').map(Uri.encodeComponent).join('/');
  final encodedRevision = Uri.encodeComponent(revision);
  final encodedFilePath = _encodedHuggingFaceFilePath(filePath);
  return Uri.parse(
    'https://huggingface.co/$encodedRepoId/resolve/$encodedRevision/$encodedFilePath?download=true',
  );
}

String _encodedHuggingFaceFilePath(String filePath) {
  return filePath.split('/').map(Uri.encodeComponent).join('/');
}

String _validateRepoId(String repoId) {
  final parts = repoId.split('/');
  if (parts.length != 2 || parts.any((part) => part.isEmpty)) {
    throw ArgumentError.value(repoId, 'repoId', 'Repo id must be owner/repo.');
  }
  for (final part in parts) {
    _validateRepoSegment(part, repoId);
  }
  return repoId;
}

String _decodeHuggingFacePathSegment(String segment, String value) {
  try {
    return Uri.decodeComponent(segment);
  } on FormatException catch (error) {
    throw ArgumentError.value(
      value,
      'value',
      'Hugging Face file path contains invalid percent-encoding: ${error.message}',
    );
  }
}

String _decodeHuggingFaceQueryComponent(String component, String value) {
  try {
    return Uri.decodeComponent(component);
  } on FormatException catch (error) {
    throw ArgumentError.value(
      value,
      'value',
      'Hugging Face query contains invalid percent-encoding: ${error.message}',
    );
  }
}

void _validateRepoSegment(String segment, String repoId) {
  final validSegment = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');
  if (!validSegment.hasMatch(segment) || segment.contains('..')) {
    throw ArgumentError.value(
      repoId,
      'repoId',
      'Invalid Hugging Face repo id.',
    );
  }
}

String _validateRevision(String revision) {
  final invalidCharacters = RegExp(r'[\x00-\x20\x7F~^:?*\[\\\]#]');
  if (revision.isEmpty ||
      revision.startsWith('/') ||
      revision.endsWith('/') ||
      revision.contains('//') ||
      revision.contains('..') ||
      revision.contains('@{') ||
      invalidCharacters.hasMatch(revision)) {
    throw ArgumentError.value(
      revision,
      'revision',
      'Invalid Hugging Face revision.',
    );
  }
  return revision;
}

String _validateFilePath(String filePath) {
  if (filePath.isEmpty || filePath.startsWith('/')) {
    throw ArgumentError.value(
      filePath,
      'filePath',
      'Hugging Face file path must be relative.',
    );
  }

  final segments = filePath.split('/');
  for (final segment in segments) {
    if (segment.isEmpty ||
        segment == '.' ||
        segment == '..' ||
        segment.contains('\\')) {
      throw ArgumentError.value(
        filePath,
        'filePath',
        'Invalid Hugging Face file path.',
      );
    }
  }
  return filePath;
}

String _fileNameFromUri(Uri uri) {
  final rawSegments = uri.path
      .split('/')
      .where((segment) => segment.isNotEmpty);
  if (rawSegments.isEmpty) {
    throw ArgumentError.value(
      uri,
      'url',
      'URL must include a model file name.',
    );
  }
  for (final segment in rawSegments) {
    _validateRemoteFileName(segment, 'url');
  }
  return _validateRemoteFileName(rawSegments.last, 'url');
}

String _validateRemoteFileName(String fileName, String name) {
  final decodedFileName = _decodeFileNameComponent(fileName, name);
  if (decodedFileName.isEmpty ||
      decodedFileName == '.' ||
      decodedFileName == '..' ||
      RegExp(r'[<>:"/\\|?*\x00-\x1F]').hasMatch(decodedFileName)) {
    throw ArgumentError.value(
      fileName,
      name,
      'Remote model file name must be a non-empty base name.',
    );
  }
  return decodedFileName;
}

String _decodeFileNameComponent(String fileName, String name) {
  try {
    return Uri.decodeComponent(fileName);
  } on FormatException catch (error) {
    throw ArgumentError.value(fileName, name, error.message);
  }
}

String _fileNameFromPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final segments = normalized.split('/');
  final last = segments.isEmpty ? path : segments.last;
  return last.isEmpty ? 'model.gguf' : last;
}

String _fileStem(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0) {
    return fileName;
  }
  return fileName.substring(0, dot);
}

String _safeName(String value) {
  final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
  final trimmed = sanitized.replaceAll(RegExp(r'^-+|-+$'), '');
  return trimmed.isEmpty ? 'model' : trimmed;
}

bool _looksLikeWindowsPath(String value, String scheme) {
  return scheme.length == 1 &&
      value.length >= 3 &&
      value.codeUnitAt(1) == 0x3A &&
      (value.codeUnitAt(2) == 0x5C || value.codeUnitAt(2) == 0x2F);
}

Uri _uriWithoutQueryOrFragment(Uri uri) {
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  );
}
