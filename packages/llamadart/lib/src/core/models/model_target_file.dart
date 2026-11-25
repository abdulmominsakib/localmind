import '../exceptions.dart';
import 'download/model_download_manager_base.dart';
import 'model_file_store.dart';
import 'model_load_options.dart';
import 'model_resolver.dart';
import 'model_source.dart';

/// Thrown by the default download manager for a local file that exists and
/// passed its checks, but whose name a [ModelCacheEntry] cannot hold.
///
/// [resolveModelSourceFiles] loads [filePath] anyway, since it needs no cache
/// entry for a local file.
class UncacheableLocalModelFileException extends LlamaUnsupportedException {
  /// Creates the exception for the checked file at [filePath].
  UncacheableLocalModelFileException(
    super.message, {
    required this.filePath,
    required this.bytes,
  });

  /// The absolute, normalized path of the file.
  final String filePath;

  /// The size of the file.
  final int bytes;
}

/// Makes the [target] that a [ModelResolver] returned for [source] a local
/// file through [manager], for backends that load files rather than URLs.
///
/// A local target is checked by [manager]; a remote one is downloaded or
/// taken from its cache under [source]'s cache identity. A local target of a
/// remote [source], such as a resolver's offline mirror, takes only the
/// checksum and cancel token of [options], since its cache and credential
/// options apply to downloads only.
///
/// Throws [LlamaUnsupportedException] for a remote target that disallows the
/// browser/backend cache, naming [assetType] in the message.
Future<ModelCacheEntry> ensureModelTargetFile(
  ModelDownloadManager manager,
  ModelSource source,
  ModelLoadTarget target, {
  required ModelLoadOptions options,
  ModelDownloadProgressCallback? onProgress,
  String assetType = 'model',
}) async {
  switch (target) {
    case LocalModelFile(:final path):
      return manager.ensureModel(
        ModelSource.path(path, format: source.format),
        options: source.isRemote
            ? ModelLoadOptions(
                sha256: options.sha256,
                cancelToken: options.cancelToken,
              )
            : options,
        onProgress: onProgress,
      );
    case RemoteModelUrl(:final url, :final useBrowserCache):
      if (!useBrowserCache) {
        throw LlamaUnsupportedException(
          'Remote $assetType loading without browser/backend cache is not '
          'supported yet.',
        );
      }
      final downloadSource = source.isRemote
          ? source.withResolvedUri(url)
          : ModelSource.url(
              url,
              fileName: source.fileName,
              format: source.format,
            );
      return manager.ensureModel(
        downloadSource,
        options: options,
        onProgress: onProgress,
      );
  }
}

/// Local paths of [sources], in order, resolved one at a time through
/// [store]'s resolver and download manager, for a load of several files
/// named [operation] (such as `Image model loading`).
///
/// [download] applies to every remote file. Its bearer token and headers are
/// never sent across hosts: when they are set and the remote sources, or the
/// URLs the resolver returns for them, span more than one origin (scheme,
/// host and port), this throws [LlamaArgumentException] naming the origins,
/// never the credentials, before downloading from another host. A local
/// file takes only the cancel token and, for a single file, the checksum,
/// since [ModelLoadOptions] rejects download options for local files. A
/// local file whose name the default download manager cannot describe as a
/// [ModelCacheEntry], such as one holding `%2F`, loads from its path.
///
/// [onProgress] reports the files together. Byte progress counts every file
/// resolved so far plus the bytes of the current one; `totalBytes` is their
/// combined size once every size is known, from [knownSizes] (by index), a
/// download or a resolved file, and null before. A file that reports only a
/// fraction, as a URL-loading backend does, makes the combined progress a
/// fraction of all the files.
///
/// Throws [LlamaUnsupportedException] before resolving anything when
/// [download] sets [ModelLoadOptions.sha256] for more than one file; a
/// single file, local or remote, is verified against it. Throws
/// [LlamaStateException] when [download]'s cancel token is cancelled after a
/// file resolves.
Future<List<String>> resolveModelSourceFiles(
  List<ModelSource> sources, {
  required ModelFileStore store,
  required ModelLoadOptions download,
  required String operation,
  ModelDownloadProgressCallback? onProgress,
  Map<int, int> knownSizes = const <int, int>{},
  String assetType = 'model',
}) async {
  if (sources.length > 1 && download.sha256 != null) {
    throw LlamaUnsupportedException(
      '$operation uses ${sources.length} files, so ModelLoadOptions.sha256 '
      'cannot apply to them. Leave it unset.',
    );
  }
  final sendsCredentials =
      download.bearerToken != null || download.headers.isNotEmpty;
  void checkOrigins(Set<String> origins, Uri url) {
    if (!sendsCredentials) return;
    origins.add('${url.scheme}://${url.host}:${url.port}');
    if (origins.length > 1) {
      throw LlamaArgumentException(
        '$operation would send ModelLoadOptions.bearerToken or headers to '
        'more than one host (${origins.join(', ')}). Credentials are never '
        'forwarded across hosts: load these files from one host, or leave '
        'bearerToken and headers unset.',
        name: 'download',
      );
    }
  }

  final sourceOrigins = <String>{};
  for (final source in sources) {
    if (source.resolvedUri case final url?) checkOrigins(sourceOrigins, url);
  }
  final targetOrigins = <String>{};
  final progress = _FilesProgress(onProgress, sources.length, knownSizes);
  final localOptions = ModelLoadOptions(
    sha256: download.sha256,
    cancelToken: download.cancelToken,
  );
  final files = <String>[];
  for (final (index, source) in sources.indexed) {
    final fileOptions = source.isLocal ? localOptions : download;
    final fileProgress = progress.file(index);
    final target = await store.resolver.resolve(
      source,
      ModelResolveRequest(options: fileOptions, onProgress: fileProgress),
    );
    if (source.isRemote && target is RemoteModelUrl) {
      checkOrigins(targetOrigins, target.url);
    }
    String filePath;
    int? bytes;
    try {
      final entry = await ensureModelTargetFile(
        store.downloadManager,
        source,
        target,
        options: fileOptions,
        onProgress: fileProgress,
        assetType: assetType,
      );
      filePath = entry.filePath;
      bytes = entry.bytes;
    } on UncacheableLocalModelFileException catch (file) {
      filePath = file.filePath;
      bytes = file.bytes;
    }
    if (download.cancelToken?.isCancelled ?? false) {
      throw LlamaStateException('$operation was cancelled.');
    }
    progress.resolved(index, bytes);
    files.add(filePath);
  }
  return files;
}

/// What a URL-loading backend fetches for each of [sources], in order: the
/// URL that [resolver] returns for a remote source, and the path of a local
/// one as written, which a browser reads as a URL relative to the document,
/// or as a `blob:` URL.
///
/// Nothing is fetched here. Throws [LlamaUnsupportedException] when
/// [download] asks for what only the package download manager provides, and
/// for a remote target that disallows the browser/backend cache, naming
/// [assetType] in the message.
Future<List<String>> resolveModelSourceUrls(
  List<ModelSource> sources, {
  required ModelResolver resolver,
  required ModelLoadOptions download,
  String assetType = 'model',
}) async {
  rejectUnsupportedUrlBackendOptions(download, assetType: assetType);
  final request = ModelResolveRequest(options: download);
  return [
    for (final source in sources)
      switch (await resolver.resolve(source, request)) {
        LocalModelFile(:final path) => path,
        RemoteModelUrl(:final url, useBrowserCache: true) => '$url',
        RemoteModelUrl() => throw LlamaUnsupportedException(
          'Remote $assetType loading without browser/backend cache is not '
          'supported yet.',
        ),
      },
  ];
}

/// Throws [LlamaUnsupportedException] when [options] asks for what only the
/// package download manager provides, for an [assetType] that a URL-loading
/// backend fetches itself.
void rejectUnsupportedUrlBackendOptions(
  ModelLoadOptions options, {
  String assetType = 'model',
}) {
  final isModel = assetType == 'model';
  if (options.cachePolicy != ModelCachePolicy.preferCached) {
    throw LlamaUnsupportedException(
      '${options.cachePolicy.name} $assetType loading requires the native download/cache manager.',
    );
  }
  if (options.bearerToken != null || options.headers.isNotEmpty) {
    throw LlamaUnsupportedException(
      'Authenticated $assetType URL loading requires the native download/cache manager.',
    );
  }
  if (options.cancelToken != null) {
    throw LlamaUnsupportedException(
      isModel
          ? 'Cancellation tokens require the native download/cache manager.'
          : 'Cancellation tokens for $assetType loading require the native download/cache manager.',
    );
  }
  if (options.sha256 != null) {
    throw LlamaUnsupportedException(
      isModel
          ? 'Checksum verification requires the native download/cache manager.'
          : 'Checksum verification for $assetType loading requires the native download/cache manager.',
    );
  }
  if (options.cacheDirectory != null) {
    throw LlamaUnsupportedException(
      isModel
          ? 'cacheDirectory is not supported by URL-loading backends.'
          : 'cacheDirectory is not supported for $assetType loading by URL-loading backends.',
    );
  }
  if (!options.resume) {
    throw LlamaUnsupportedException(
      isModel
          ? 'Disabling resume is not supported by URL-loading backends.'
          : 'Disabling resume is not supported for $assetType loading by URL-loading backends.',
    );
  }
  if (options.maxRetries != ModelLoadOptions.defaults.maxRetries) {
    throw LlamaUnsupportedException(
      isModel
          ? 'Custom maxRetries is not supported by URL-loading backends.'
          : 'Custom maxRetries is not supported for $assetType loading by URL-loading backends.',
    );
  }
}

/// Combines the progress of files resolved one after another into one
/// callback; see [resolveModelSourceFiles].
class _FilesProgress {
  final ModelDownloadProgressCallback? _onProgress;
  final int _fileCount;
  final Map<int, int> _sizes;

  _FilesProgress(this._onProgress, this._fileCount, Map<int, int> knownSizes)
    : _sizes = Map<int, int>.of(knownSizes);

  ModelDownloadProgressCallback? file(int index) {
    final onProgress = _onProgress;
    if (onProgress == null) {
      return null;
    }
    return (ModelDownloadProgress progress) {
      final fraction = progress.fraction;
      if (progress.receivedBytes == 0 &&
          progress.totalBytes == null &&
          fraction != null) {
        onProgress(
          ModelDownloadProgress.fraction((index + fraction) / _fileCount),
        );
        return;
      }
      if (progress.totalBytes case final total?) {
        _sizes[index] = total;
      }
      _report(index, progress.receivedBytes);
    };
  }

  void resolved(int index, int? bytes) {
    if (_onProgress == null) {
      return;
    }
    if (bytes != null) {
      _sizes[index] = bytes;
    }
    _report(index, _sizes[index] ?? 0);
  }

  void _report(int index, int currentBytes) {
    var earlierBytes = 0;
    for (var earlier = 0; earlier < index; earlier++) {
      earlierBytes += _sizes[earlier] ?? 0;
    }
    final total = _sizes.length == _fileCount
        ? _sizes.values.fold<int>(0, (sum, size) => sum + size)
        : null;
    _onProgress!(
      ModelDownloadProgress(
        receivedBytes: earlierBytes + currentBytes,
        totalBytes: total,
      ),
    );
  }
}
