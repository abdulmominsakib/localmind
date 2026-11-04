import 'dart:async';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  group('ModelDownloadController', () {
    test(
      'returns cached remote entries without reporting a download',
      () async {
        final source = ModelSource.url(
          Uri.parse('https://example.com/model.gguf?token=secret'),
        );
        final cached = _entryFor(source, '/cache/model.gguf');
        final manager = _FakeDownloadManager(
          entry: cached,
          cachedEntry: cached,
        );
        final controller = ModelDownloadController(manager: manager);
        addTearDown(controller.dispose);

        final stages = <ModelDownloadTaskStage>[];
        final sub = controller.snapshots.listen(
          (snapshot) => stages.add(snapshot.stage),
        );
        addTearDown(sub.cancel);

        final entry = await controller.start(source);

        expect(entry, same(cached));
        expect(manager.ensureCalls, 1);
        expect(stages, <ModelDownloadTaskStage>[
          ModelDownloadTaskStage.resolving,
          ModelDownloadTaskStage.checkingCache,
          ModelDownloadTaskStage.verifying,
          ModelDownloadTaskStage.ready,
        ]);
        expect(stages, isNot(contains(ModelDownloadTaskStage.downloading)));
        expect(controller.snapshot.entry, same(cached));
        expect(controller.snapshot.isRunning, isFalse);
      },
    );

    test('validates cached entries through ensureModel before ready', () async {
      final source = ModelSource.url(
        Uri.parse('https://example.com/model.gguf'),
      );
      final cached = _entryFor(source, '/cache/model.gguf');
      final manager = _FakeDownloadManager(cachedEntry: cached)
        ..error = LlamaModelException('Checksum mismatch for cached model.');
      final controller = ModelDownloadController(manager: manager);
      addTearDown(controller.dispose);

      await expectLater(
        controller.start(
          source,
          options: ModelLoadOptions(
            sha256:
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          ),
        ),
        throwsA(isA<LlamaModelException>()),
      );

      expect(manager.ensureCalls, 1);
      expect(controller.snapshot.stage, ModelDownloadTaskStage.failed);
      expect(controller.snapshot.entry, isNull);
    });

    test(
      'emits download, verification, and ready states for cache misses',
      () async {
        final source = ModelSource.url(
          Uri.parse('https://example.com/model.gguf'),
        );
        final entry = _entryFor(source, '/cache/model.gguf');
        final manager = _FakeDownloadManager(entry: entry)
          ..progressEvents = const <ModelDownloadProgress>[
            ModelDownloadProgress(receivedBytes: 2, totalBytes: 10),
            ModelDownloadProgress(receivedBytes: 10, totalBytes: 10),
          ];
        final controller = ModelDownloadController(manager: manager);
        addTearDown(controller.dispose);

        final snapshots = <ModelDownloadTaskSnapshot>[];
        final sub = controller.snapshots.listen(snapshots.add);
        addTearDown(sub.cancel);

        final result = await controller.start(source);

        expect(result, same(entry));
        expect(manager.ensureCalls, 1);
        expect(manager.lastOptions?.cancelToken, isNotNull);
        expect(
          snapshots.map((snapshot) => snapshot.stage),
          containsAllInOrder(<ModelDownloadTaskStage>[
            ModelDownloadTaskStage.resolving,
            ModelDownloadTaskStage.checkingCache,
            ModelDownloadTaskStage.downloading,
            ModelDownloadTaskStage.verifying,
            ModelDownloadTaskStage.ready,
          ]),
        );
        expect(
          snapshots
              .where(
                (snapshot) =>
                    snapshot.stage == ModelDownloadTaskStage.downloading,
              )
              .last
              .progress
              ?.fraction,
          1.0,
        );
        expect(controller.snapshot.entry, same(entry));
      },
    );

    test(
      'cancel requests cooperative cancellation and emits cancelled',
      () async {
        final source = ModelSource.url(
          Uri.parse('https://example.com/model.gguf'),
        );
        final manager = _FakeDownloadManager(
          entry: _entryFor(source, '/cache/model.gguf'),
        );
        final controller = ModelDownloadController(manager: manager);
        addTearDown(controller.dispose);
        final gate = Completer<void>();
        manager.ensureGate = gate;

        final stages = <ModelDownloadTaskStage>[];
        final sub = controller.snapshots.listen(
          (snapshot) => stages.add(snapshot.stage),
        );
        addTearDown(sub.cancel);

        final task = controller.start(source);
        await Future<void>.delayed(Duration.zero);

        controller.cancel();
        gate.complete();

        await expectLater(task, throwsA(isA<LlamaStateException>()));
        expect(manager.lastOptions?.cancelToken?.isCancelled, isTrue);
        expect(controller.snapshot.stage, ModelDownloadTaskStage.cancelled);
        expect(controller.snapshot.canRetry, isTrue);
        expect(stages, contains(ModelDownloadTaskStage.cancelled));
      },
    );

    test(
      'manager cancellation-like errors fail unless controller cancelled',
      () async {
        final source = ModelSource.url(
          Uri.parse('https://example.com/model.gguf'),
        );
        final manager = _FakeDownloadManager()
          ..error = LlamaStateException('Download was cancelled by server.');
        final controller = ModelDownloadController(manager: manager);
        addTearDown(controller.dispose);

        await expectLater(
          controller.start(source),
          throwsA(isA<LlamaStateException>()),
        );

        expect(controller.snapshot.stage, ModelDownloadTaskStage.failed);
        expect(controller.snapshot.canRetry, isTrue);
        expect(
          controller.snapshot.errorMessage,
          contains('Download was cancelled by server.'),
        );
      },
    );

    test('redacts secrets from failure messages', () async {
      final source = ModelSource.url(
        Uri.parse('https://example.com/model.gguf?token=secret#fragment'),
      );
      final manager = _FakeDownloadManager()
        ..error = LlamaModelException(
          'Failed to fetch https://example.com/model.gguf?token=secret#fragment',
        );
      final controller = ModelDownloadController(manager: manager);
      addTearDown(controller.dispose);

      await expectLater(
        controller.start(source),
        throwsA(isA<LlamaModelException>()),
      );

      expect(controller.snapshot.stage, ModelDownloadTaskStage.failed);
      expect(
        controller.snapshot.errorMessage,
        contains('https://example.com/model.gguf'),
      );
      expect(controller.snapshot.errorMessage, isNot(contains('secret')));
      expect(controller.snapshot.errorMessage, isNot(contains('token=')));
    });

    test(
      'redacts semicolon and comma query tails from failure messages',
      () async {
        final source = ModelSource.url(
          Uri.parse(
            'https://example.com/model.gguf?token=secret;sig=abc,scope=all',
          ),
        );
        final manager = _FakeDownloadManager()
          ..error = LlamaModelException(
            'Failed https://example.com/model.gguf?token=secret;sig=abc,scope=all.',
          );
        final controller = ModelDownloadController(manager: manager);
        addTearDown(controller.dispose);

        await expectLater(
          controller.start(source),
          throwsA(isA<LlamaModelException>()),
        );

        expect(
          controller.snapshot.errorMessage,
          contains('https://example.com/model.gguf'),
        );
        expect(controller.snapshot.errorMessage, isNot(contains('secret')));
        expect(controller.snapshot.errorMessage, isNot(contains('sig=')));
        expect(controller.snapshot.errorMessage, isNot(contains('scope=')));
      },
    );

    test('rejects caller-supplied cancellation tokens', () {
      final source = ModelSource.url(
        Uri.parse('https://example.com/model.gguf'),
      );
      final controller = ModelDownloadController(
        manager: _FakeDownloadManager(),
      );
      addTearDown(controller.dispose);

      expect(
        () => controller.start(
          source,
          options: ModelLoadOptions(cancelToken: ModelDownloadCancelToken()),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('retry reuses the last source and options after failure', () async {
      final source = ModelSource.url(
        Uri.parse('https://example.com/model.gguf'),
      );
      final entry = _entryFor(source, '/cache/model.gguf');
      final manager = _FakeDownloadManager()
        ..error = LlamaModelException('temporary failure');
      final controller = ModelDownloadController(manager: manager);
      addTearDown(controller.dispose);

      await expectLater(
        controller.start(
          source,
          options: ModelLoadOptions(cachePolicy: ModelCachePolicy.refresh),
        ),
        throwsA(isA<LlamaModelException>()),
      );
      expect(controller.snapshot.stage, ModelDownloadTaskStage.failed);

      manager
        ..error = null
        ..entry = entry;
      final retried = await controller.retry();

      expect(retried, same(entry));
      expect(manager.ensureCalls, 2);
      expect(manager.lastOptions?.cachePolicy, ModelCachePolicy.refresh);
      expect(controller.snapshot.stage, ModelDownloadTaskStage.ready);
    });
  });
}

ModelCacheEntry _entryFor(ModelSource source, String filePath) {
  final now = DateTime.utc(2026);
  return ModelCacheEntry(
    sourceCanonicalKey: source.metadataSourceKey,
    cacheKey: source.cacheKey,
    fileName: source.fileName,
    filePath: filePath,
    bytes: 10,
    createdAt: now,
    updatedAt: now,
  );
}

class _FakeDownloadManager implements ModelDownloadManager {
  _FakeDownloadManager({this.entry, this.cachedEntry});

  ModelCacheEntry? entry;
  ModelCacheEntry? cachedEntry;
  Object? error;
  Completer<void>? ensureGate;
  List<ModelDownloadProgress> progressEvents = const <ModelDownloadProgress>[];
  int ensureCalls = 0;
  ModelLoadOptions? lastOptions;

  @override
  Future<ModelCacheEntry> ensureModel(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    ensureCalls += 1;
    lastOptions = options;
    await ensureGate?.future;
    if (options.cancelToken?.isCancelled ?? false) {
      throw LlamaStateException('Model download was cancelled.');
    }
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    for (final progress in progressEvents) {
      onProgress?.call(progress);
    }
    return entry ?? _entryFor(source, '/cache/${source.fileName}');
  }

  @override
  Future<List<ModelCacheEntry>> list({String? cacheDirectory}) async =>
      cachedEntry == null
      ? const <ModelCacheEntry>[]
      : <ModelCacheEntry>[cachedEntry!];

  @override
  Future<ModelCacheEntry?> get(
    String cacheKey, {
    String? cacheDirectory,
  }) async {
    final entry = cachedEntry;
    return entry != null && entry.cacheKey == cacheKey ? entry : null;
  }

  @override
  Future<void> remove(String cacheKey, {String? cacheDirectory}) async {}

  @override
  Future<void> clear({String? cacheDirectory}) async {}

  @override
  Future<List<ModelCacheEntry>> prune({
    Duration? maxAge,
    int? maxBytes,
    String? cacheDirectory,
  }) async => const <ModelCacheEntry>[];
}
