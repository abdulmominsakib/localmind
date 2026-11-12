import 'package:test/test.dart';

import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/download/model_download_manager_base.dart';
import 'package:llamadart/src/core/models/model_file_store.dart';
import 'package:llamadart/src/core/models/model_format.dart';
import 'package:llamadart/src/core/models/model_load_options.dart';
import 'package:llamadart/src/core/models/model_resolver.dart';
import 'package:llamadart/src/core/models/model_source.dart';
import 'package:llamadart/src/core/models/model_target_file.dart';

void main() {
  late _RecordingManager manager;

  setUp(() => manager = _RecordingManager());

  test('a local target is checked by the manager as a path source', () async {
    final options = ModelLoadOptions(sha256: 'a' * 64);
    void onProgress(ModelDownloadProgress _) {}

    final entry = await ensureModelTargetFile(
      manager,
      ModelSource.path('/models/source.gguf'),
      const LocalModelFile('/models/model.gguf'),
      options: options,
      onProgress: onProgress,
    );

    final (source, passedOptions, passedProgress) = manager.calls.single;
    expect(source.kind, ModelSourceKind.path);
    expect(source.path, '/models/model.gguf');
    expect(passedOptions, same(options));
    expect(passedProgress, same(onProgress));
    expect(entry.filePath, '/cache/model.gguf');
  });

  test('a local target of a remote source takes only the checksum and '
      'cancel token', () async {
    final cancelToken = ModelDownloadCancelToken();
    final options = ModelLoadOptions(
      cachePolicy: ModelCachePolicy.refresh,
      cacheDirectory: '/cache',
      sha256: 'a' * 64,
      bearerToken: 'secret-token',
      headers: const {'X-Test': '1'},
      cancelToken: cancelToken,
      resume: false,
      maxRetries: 1,
    );

    await ensureModelTargetFile(
      manager,
      ModelSource.parse('hf://owner/repo@main/model.gguf'),
      const LocalModelFile('/models/model.gguf'),
      options: options,
    );

    final (source, passedOptions, _) = manager.calls.single;
    expect(source.path, '/models/model.gguf');
    expect(passedOptions.sha256, 'a' * 64);
    expect(passedOptions.cancelToken, same(cancelToken));
    expect(passedOptions.cachePolicy, ModelCachePolicy.preferCached);
    expect(passedOptions.cacheDirectory, isNull);
    expect(passedOptions.bearerToken, isNull);
    expect(passedOptions.headers, isEmpty);
    expect(passedOptions.resume, isTrue);
    expect(passedOptions.maxRetries, ModelLoadOptions.defaults.maxRetries);
  });

  test('a remote target downloads under the source cache identity', () async {
    final source = ModelSource.parse('hf://owner/repo@main/model.gguf');
    final mirror = Uri.parse('https://mirror.example.com/model.gguf');

    await ensureModelTargetFile(
      manager,
      source,
      RemoteModelUrl(mirror),
      options: ModelLoadOptions.defaults,
    );

    final (downloaded, _, _) = manager.calls.single;
    expect(downloaded.resolvedUri, mirror);
    expect(downloaded.canonicalKey, source.canonicalKey);
  });

  test('a remote target for a local source downloads as a URL keeping the '
      'file name', () async {
    final url = Uri.parse('https://example.com/download?id=1');

    await ensureModelTargetFile(
      manager,
      ModelSource.path('/models/vae.safetensors'),
      RemoteModelUrl(url),
      options: ModelLoadOptions.defaults,
    );

    final (downloaded, _, _) = manager.calls.single;
    expect(downloaded.kind, ModelSourceKind.http);
    expect(downloaded.resolvedUri, url);
    expect(downloaded.fileName, 'vae.safetensors');
  });

  test(
    'keeps the source format on local, remote and re-sourced targets',
    () async {
      final hf = ModelSource.parse(
        'hf://owner/repo@main/download',
        format: ModelFormat.liteRtLm,
      );
      final local = ModelSource.path(
        '/models/download',
        format: ModelFormat.liteRtLm,
      );

      await ensureModelTargetFile(
        manager,
        local,
        const LocalModelFile('/models/download'),
        options: ModelLoadOptions.defaults,
      );
      await ensureModelTargetFile(
        manager,
        hf,
        RemoteModelUrl(Uri.parse('https://mirror.example.com/download')),
        options: ModelLoadOptions.defaults,
      );
      await ensureModelTargetFile(
        manager,
        local,
        RemoteModelUrl(Uri.parse('https://example.com/download?id=1')),
        options: ModelLoadOptions.defaults,
      );

      expect([
        for (final (source, _, _) in manager.calls) source.format,
      ], everyElement(ModelFormat.liteRtLm));
      expect(manager.calls, hasLength(3));
    },
  );

  test('a remote target without the backend cache is unsupported and names '
      'the asset type', () async {
    await expectLater(
      ensureModelTargetFile(
        manager,
        ModelSource.parse('hf://owner/repo@main/model.gguf'),
        RemoteModelUrl(
          Uri.parse('https://example.com/model.gguf?token=secret'),
          useBrowserCache: false,
        ),
        options: ModelLoadOptions.defaults,
        assetType: 'image model',
      ),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          allOf(
            'Remote image model loading without browser/backend cache is not '
            'supported yet.',
            isNot(contains('secret')),
          ),
        ),
      ),
    );
    expect(manager.calls, isEmpty);
  });
  group('resolveModelSourceFiles', () {
    final remote = ModelSource.parse('hf://owner/repo/model.tflite');
    final local = ModelSource.path('/models/tokenizer.json');

    Future<List<String>> resolve(
      List<ModelSource> sources, {
      ModelLoadOptions download = ModelLoadOptions.defaults,
      ModelDownloadProgressCallback? onProgress,
      Map<int, int> knownSizes = const {},
    }) => resolveModelSourceFiles(
      sources,
      store: ModelFileStore(downloadManager: manager),
      download: download,
      operation: 'Test loading',
      onProgress: onProgress,
      knownSizes: knownSizes,
    );

    test(
      'resolves files in order, a local one with the cancel token only',
      () async {
        final token = ModelDownloadCancelToken();
        final download = ModelLoadOptions(
          bearerToken: 'secret',
          cancelToken: token,
        );

        final paths = await resolve([remote, local], download: download);

        expect(paths, ['/cache/model.tflite', '/cache/tokenizer.json']);
        final [(first, remoteOptions, _), (second, localOptions, _)] =
            manager.calls;
        expect(first.kind, ModelSourceKind.huggingFace);
        expect(remoteOptions, same(download));
        expect(second.path, '/models/tokenizer.json');
        expect(localOptions.bearerToken, isNull);
        expect(localOptions.cancelToken, same(token));
      },
    );

    test('rejects a checksum for several files before resolving any, and '
        'keeps it for one', () async {
      final download = ModelLoadOptions(sha256: 'a' * 64);

      await expectLater(
        resolve([remote, local], download: download),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            'Test loading uses 2 files, so ModelLoadOptions.sha256 cannot '
                'apply to them. Leave it unset.',
          ),
        ),
      );
      expect(manager.calls, isEmpty);

      await resolve([remote], download: download);
      expect(manager.calls.single.$2, same(download));
    });

    test('verifies a single local file against the checksum', () async {
      final download = ModelLoadOptions(sha256: 'a' * 64);

      await resolve([local], download: download);

      expect(manager.calls.single.$2.sha256, 'a' * 64);
    });

    test('rejects credentials for remote files on more than one host before '
        'downloading, naming the hosts but not the credentials', () async {
      final other = ModelSource.url(
        Uri.parse('https://other.example.com/vae.gguf'),
      );
      for (final download in [
        ModelLoadOptions(bearerToken: 'hf_secret'),
        ModelLoadOptions(headers: const {'X-Key': 'hf_secret'}),
      ]) {
        await expectLater(
          resolve([remote, local, other], download: download),
          throwsA(
            isA<LlamaArgumentException>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('https://huggingface.co:443'),
                contains('https://other.example.com:443'),
                isNot(contains('hf_secret')),
              ),
            ),
          ),
        );
      }
      expect(manager.calls, isEmpty);
    });

    test('sends credentials to remote files on one host, and to none when a '
        'resolver moves a file to another host', () async {
      final sibling = ModelSource.parse('hf://owner/repo/tokenizer.json');
      final download = ModelLoadOptions(bearerToken: 'hf_secret');

      await resolve([remote, local, sibling], download: download);
      expect(manager.calls.map((call) => call.$2.bearerToken), [
        'hf_secret',
        null,
        'hf_secret',
      ]);
      manager.calls.clear();

      await expectLater(
        resolveModelSourceFiles(
          [remote, sibling],
          store: ModelFileStore(
            resolver: _MirrorSecondResolver(),
            downloadManager: manager,
          ),
          download: download,
          operation: 'Test loading',
        ),
        throwsA(isA<LlamaArgumentException>()),
      );
      expect(manager.calls, hasLength(1));
    });

    test('loads a checked local file that the manager cannot describe as a '
        'cache entry from its path, counting its size', () async {
      manager
        ..uncacheable = '/models/tokenizer.json'
        ..bytes = {'model.tflite': 10};
      final progress = <ModelDownloadProgress>[];

      final paths = await resolve([remote, local], onProgress: progress.add);

      expect(paths, ['/cache/model.tflite', '/abs/models/tokenizer.json']);
      expect(progress.last.receivedBytes, 17);
      expect(progress.last.totalBytes, 17);
    });

    test('stops after a file when the cancel token is cancelled', () async {
      final token = ModelDownloadCancelToken();
      manager.onEnsure = token.cancel;

      await expectLater(
        resolve([
          remote,
          local,
        ], download: ModelLoadOptions(cancelToken: token)),
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            'Test loading was cancelled.',
          ),
        ),
      );
      expect(manager.calls, hasLength(1));
    });

    test(
      'reports byte progress with a total once every size is known',
      () async {
        manager
          ..progress = {
            'model.tflite': const [
              ModelDownloadProgress(receivedBytes: 4, totalBytes: 10),
            ],
            'tokenizer.json': const [],
          }
          ..bytes = {'model.tflite': 10};
        final progress = <ModelDownloadProgress>[];

        await resolve(
          [remote, local],
          onProgress: progress.add,
          knownSizes: const {1: 5},
        );

        expect(progress.map((p) => (p.receivedBytes, p.totalBytes)), [
          (4, 15),
          (10, 15),
          (15, 15),
        ]);
      },
    );

    test('reports no total while a size is unknown', () async {
      final progress = <ModelDownloadProgress>[];

      await resolve([remote, local], onProgress: progress.add);

      expect(progress.map((p) => (p.receivedBytes, p.totalBytes)), [
        (0, null),
        (0, null),
      ]);
    });

    test(
      'combines fraction-only progress into a fraction of all files',
      () async {
        manager.progress = {
          'model.tflite': const [ModelDownloadProgress.fraction(0.5)],
        };
        final progress = <ModelDownloadProgress>[];

        await resolve([
          remote,
          remote.withResolvedUri(
            Uri.parse('https://mirror.example.com/model.tflite'),
          ),
        ], onProgress: progress.add);

        expect(
          progress
              .where((p) => p.totalBytes == null && p.receivedBytes == 0)
              .map((p) => p.fraction)
              .whereType<double>(),
          [0.25, 0.75],
        );
      },
    );
  });

  group('resolveModelSourceUrls', () {
    final remote = ModelSource.parse('hf://owner/repo/model.gguf');

    Future<List<String>> resolve(
      List<ModelSource> sources, {
      ModelResolver resolver = const DefaultModelResolver(),
      ModelLoadOptions download = ModelLoadOptions.defaults,
    }) => resolveModelSourceUrls(
      sources,
      resolver: resolver,
      download: download,
      assetType: 'decision model',
    );

    test('gives a remote source its URL and a local one its path as written, '
        'in order', () async {
      expect(
        await resolve([
          ModelSource.path('models/encoder.gguf'),
          remote,
          ModelSource.path('blob:https://app.example/3f2a'),
        ]),
        [
          'models/encoder.gguf',
          'https://huggingface.co/owner/repo/resolve/main/model.gguf'
              '?download=true',
          'blob:https://app.example/3f2a',
        ],
      );
    });

    test('rejects an option the backend fetch cannot apply before it '
        'resolves anything, naming the asset type', () async {
      final resolver = _MirrorSecondResolver();

      await expectLater(
        resolve(
          [remote],
          resolver: resolver,
          download: ModelLoadOptions(cacheDirectory: '/models'),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            'cacheDirectory is not supported for decision model loading by '
                'URL-loading backends.',
          ),
        ),
      );
      expect(resolver._remotes, 0);
    });

    test('rejects a remote target that disallows the browser cache', () async {
      await expectLater(
        resolve([remote], resolver: _NoCacheResolver()),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            'Remote decision model loading without browser/backend cache is '
                'not supported yet.',
          ),
        ),
      );
    });
  });
}

final class _NoCacheResolver implements ModelResolver {
  @override
  Future<ModelLoadTarget> resolve(
    ModelSource source,
    ModelResolveRequest request,
  ) async => RemoteModelUrl(source.resolvedUri!, useBrowserCache: false);
}

final class _RecordingManager extends ThrowingModelDownloadManager {
  final List<(ModelSource, ModelLoadOptions, ModelDownloadProgressCallback?)>
  calls = [];
  void Function()? onEnsure;
  String? uncacheable;
  Map<String, List<ModelDownloadProgress>> progress = const {};
  Map<String, int> bytes = const {};

  @override
  Future<ModelCacheEntry> ensureModel(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    calls.add((source, options, onProgress));
    onEnsure?.call();
    if (source.path case final path? when path == uncacheable) {
      throw UncacheableLocalModelFileException(
        'A ModelCacheEntry cannot hold $path.',
        filePath: '/abs$path',
        bytes: 7,
      );
    }
    for (final event in progress[source.fileName] ?? const []) {
      onProgress?.call(event);
    }
    final now = DateTime.utc(2026);
    return ModelCacheEntry(
      sourceCanonicalKey: source.canonicalKey,
      cacheKey: source.cacheKey,
      fileName: source.fileName,
      filePath: '/cache/${source.fileName}',
      bytes: bytes[source.fileName],
      createdAt: now,
      updatedAt: now,
    );
  }
}

/// Resolves the second remote source it sees to another host.
final class _MirrorSecondResolver implements ModelResolver {
  int _remotes = 0;

  @override
  Future<ModelLoadTarget> resolve(
    ModelSource source,
    ModelResolveRequest request,
  ) async {
    if (source.isLocal) return LocalModelFile(source.path!);
    _remotes += 1;
    return RemoteModelUrl(
      _remotes == 1
          ? source.resolvedUri!
          : Uri.parse('https://mirror.example.com/${source.fileName}'),
    );
  }
}
