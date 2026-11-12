import 'dart:async';

import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:test/test.dart';

import 'test_support/rejecting_media_resolver.dart';

void main() {
  test(
    'prepareModelTask emits progress, loading, and ready snapshots',
    () async {
      final resolver = RejectingMediaResolver();
      final manager = _FakeDownloadManager();
      final task = llamaDart.prepareModelTask(
        name: 'chat',
        source: ModelSource.url(Uri.parse('https://example.com/chat.gguf')),
        downloadManager: manager,
        mediaResolver: resolver,
        supportsEmbeddings: false,
      );
      final snapshots = <LlamaModelPreparationSnapshot>[];
      final subscription = task.snapshots.listen(snapshots.add);
      addTearDown(() async {
        await subscription.cancel();
        await task.dispose();
      });

      final prepared = await task.result;
      addTearDown(prepared.dispose);
      await expectResolverUsed(prepared.plugin, resolver);

      expect(prepared.definition.name, 'chat');
      expect(prepared.definition.modelPath, '/cache/chat.gguf');
      expect(prepared.embedderRef, isNull);
      expect(snapshots.last.stage, LlamaModelPreparationStage.ready);
      expect(snapshots.last.preparedModel, same(prepared));
      expect(
        snapshots.map((snapshot) => snapshot.stage),
        containsAllInOrder(<LlamaModelPreparationStage>[
          LlamaModelPreparationStage.resolving,
          LlamaModelPreparationStage.checkingCache,
          LlamaModelPreparationStage.downloading,
          LlamaModelPreparationStage.verifying,
          LlamaModelPreparationStage.loading,
          LlamaModelPreparationStage.ready,
        ]),
      );
      final downloading = snapshots.firstWhere(
        (snapshot) =>
            snapshot.stage == LlamaModelPreparationStage.downloading &&
            snapshot.progress != null,
      );
      expect(downloading.sourceRole, LlamaModelPreparationSourceRole.model);
      expect(downloading.fraction, 0.5);
    },
  );

  test('prepareModelTask surfaces cache-hit snapshots', () async {
    final manager = _FakeDownloadManager(cacheHit: true);
    final task = llamaDart.prepareModelTask(
      name: 'cached',
      source: ModelSource.url(Uri.parse('https://example.com/cached.gguf')),
      downloadManager: manager,
    );
    final snapshots = <LlamaModelPreparationSnapshot>[];
    final subscription = task.snapshots.listen(snapshots.add);
    addTearDown(() async {
      await subscription.cancel();
      await task.dispose();
    });

    final prepared = await task.result;

    final stages = snapshots.map((snapshot) => snapshot.stage).toList();
    expect(stages, contains(LlamaModelPreparationStage.checkingCache));
    expect(stages, isNot(contains(LlamaModelPreparationStage.downloading)));
    expect(snapshots.last.stage, LlamaModelPreparationStage.ready);
    expect(prepared.modelEntry.filePath, '/cache/cached.gguf');
  });

  test(
    'prepareModelTask resolves optional mmproj source with snapshots',
    () async {
      final manager = _FakeDownloadManager();
      final source = ModelSource.url(
        Uri.parse('https://example.com/vision.gguf'),
      );
      final mmprojSource = ModelSource.url(
        Uri.parse('https://example.com/mmproj.gguf'),
      );
      final task = llamaDart.prepareModelTask(
        name: 'vision',
        source: source,
        mmprojSource: mmprojSource,
        downloadManager: manager,
      );
      final snapshots = <LlamaModelPreparationSnapshot>[];
      final subscription = task.snapshots.listen(snapshots.add);
      addTearDown(() async {
        await subscription.cancel();
        await task.dispose();
      });

      final prepared = await task.result;

      expect(manager.calls, hasLength(2));
      expect(manager.calls.first.source, same(source));
      expect(manager.calls.last.source, same(mmprojSource));
      expect(prepared.definition.modelPath, '/cache/vision.gguf');
      expect(prepared.definition.mmprojPath, '/cache/mmproj.gguf');
      expect(prepared.mmprojEntry?.filePath, '/cache/mmproj.gguf');
      expect(
        snapshots
            .where(
              (snapshot) =>
                  snapshot.sourceRole == LlamaModelPreparationSourceRole.mmproj,
            )
            .map((snapshot) => snapshot.stage),
        containsAllInOrder(<LlamaModelPreparationStage>[
          LlamaModelPreparationStage.resolving,
          LlamaModelPreparationStage.downloading,
          LlamaModelPreparationStage.verifying,
        ]),
      );
    },
  );

  test('prepareModelTask propagates redacted download failures', () async {
    final manager = _FakeDownloadManager(
      error: LlamaModelException(
        'download failed from https://example.com/broken.gguf?token=secret '
        'with authorization: Bearer abc123',
      ),
    );
    final task = llamaDart.prepareModelTask(
      name: 'broken',
      source: ModelSource.url(Uri.parse('https://example.com/broken.gguf')),
      downloadManager: manager,
    );
    final snapshots = <LlamaModelPreparationSnapshot>[];
    final subscription = task.snapshots.listen(snapshots.add);
    addTearDown(() async {
      await subscription.cancel();
      await task.dispose();
    });

    await expectLater(task.result, throwsA(isA<LlamaModelException>()));

    expect(snapshots.last.stage, LlamaModelPreparationStage.failed);
    expect(snapshots.last.errorMessage, contains('download failed'));
    expect(
      snapshots.last.errorMessage,
      contains('https://example.com/broken.gguf'),
    );
    expect(snapshots.last.errorMessage, isNot(contains('token=')));
    expect(snapshots.last.errorMessage, isNot(contains('secret')));
    expect(snapshots.last.errorMessage, isNot(contains('abc123')));
  });

  test('prepareModelTask supports cooperative cancellation', () async {
    final manager = _FakeDownloadManager(waitForCancellation: true);
    final task = llamaDart.prepareModelTask(
      name: 'cancelled',
      source: ModelSource.url(Uri.parse('https://example.com/cancelled.gguf')),
      downloadManager: manager,
    );
    final snapshots = <LlamaModelPreparationSnapshot>[];
    final subscription = task.snapshots.listen(snapshots.add);
    addTearDown(() async {
      await subscription.cancel();
      await task.dispose();
    });

    await manager.started.future;
    task.cancel();

    await expectLater(task.result, throwsA(isA<LlamaStateException>()));
    expect(snapshots.last.stage, LlamaModelPreparationStage.cancelled);
    expect(snapshots.last.errorMessage, contains('cancelled'));
  });

  test('prepareModelTask honors cancellation from loading snapshot', () async {
    final manager = _FakeDownloadManager(cacheHit: true);
    final task = llamaDart.prepareModelTask(
      name: 'loading-cancelled',
      source: ModelSource.url(
        Uri.parse('https://example.com/loading-cancelled.gguf'),
      ),
      downloadManager: manager,
    );
    final snapshots = <LlamaModelPreparationSnapshot>[];
    final subscription = task.snapshots.listen((snapshot) {
      snapshots.add(snapshot);
      if (snapshot.stage == LlamaModelPreparationStage.loading) {
        task.cancel();
      }
    });
    addTearDown(() async {
      await subscription.cancel();
      await task.dispose();
    });

    await expectLater(task.result, throwsA(isA<LlamaStateException>()));

    expect(
      snapshots.map((snapshot) => snapshot.stage),
      contains(LlamaModelPreparationStage.loading),
    );
    expect(
      snapshots.map((snapshot) => snapshot.stage),
      isNot(contains(LlamaModelPreparationStage.ready)),
    );
    expect(snapshots.last.stage, LlamaModelPreparationStage.cancelled);
  });

  test(
    'prepareModelTask dispose closes snapshots during in-flight work',
    () async {
      final manager = _FakeDownloadManager(waitForCancellation: true);
      final task = llamaDart.prepareModelTask(
        name: 'disposed',
        source: ModelSource.url(Uri.parse('https://example.com/disposed.gguf')),
        downloadManager: manager,
      );
      final snapshots = <LlamaModelPreparationSnapshot>[];
      final streamDone = Completer<void>();
      final subscription = task.snapshots.listen(
        snapshots.add,
        onDone: streamDone.complete,
      );
      addTearDown(subscription.cancel);

      final resultExpectation = expectLater(task.result, throwsStateError);
      await manager.started.future;
      await task.dispose();

      await resultExpectation;
      await streamDone.future;
      expect(snapshots, isNotEmpty);
    },
  );
}

class _EnsureModelCall {
  _EnsureModelCall(this.source, this.options, this.onProgress);

  final ModelSource source;
  final ModelLoadOptions options;
  final ModelDownloadProgressCallback? onProgress;
}

class _FakeDownloadManager implements ModelDownloadManager {
  _FakeDownloadManager({
    this.cacheHit = false,
    this.error,
    this.waitForCancellation = false,
  });

  final bool cacheHit;
  final Object? error;
  final bool waitForCancellation;
  final List<_EnsureModelCall> calls = <_EnsureModelCall>[];
  final started = Completer<void>();

  @override
  Future<ModelCacheEntry> ensureModel(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    calls.add(_EnsureModelCall(source, options, onProgress));
    if (!cacheHit) {
      onProgress?.call(
        const ModelDownloadProgress(receivedBytes: 5, totalBytes: 10),
      );
    }
    if (!started.isCompleted) {
      started.complete();
    }

    if (waitForCancellation) {
      while (!(options.cancelToken?.isCancelled ?? false)) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      throw LlamaStateException('cancelled by fake manager');
    }

    final failure = error;
    if (failure != null) {
      throw failure;
    }

    return _entry(source, '/cache/${source.fileName}');
  }

  @override
  Future<List<ModelCacheEntry>> list({String? cacheDirectory}) async {
    return <ModelCacheEntry>[];
  }

  @override
  Future<ModelCacheEntry?> get(
    String cacheKey, {
    String? cacheDirectory,
  }) async {
    if (!cacheHit) {
      return null;
    }
    final source = ModelSource.url(Uri.parse('https://example.com/$cacheKey'));
    return _entry(source, '/cache/$cacheKey');
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
  }) async {
    return <ModelCacheEntry>[];
  }

  ModelCacheEntry _entry(ModelSource source, String filePath) {
    final now = DateTime.utc(2026);
    return ModelCacheEntry(
      sourceCanonicalKey: source.metadataSourceKey,
      cacheKey: source.cacheKey,
      fileName: source.fileName,
      filePath: filePath,
      createdAt: now,
      updatedAt: now,
    );
  }
}
