import 'dart:io';

import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:test/test.dart';

import 'test_support/rejecting_media_resolver.dart';

void main() {
  test('prepareModel resolves a remote source and preserves options', () async {
    final resolver = RejectingMediaResolver();
    final manager = _FakeDownloadManager();
    final source = ModelSource.url(
      Uri.parse('https://example.com/models/chat.gguf'),
    );
    final options = ModelLoadOptions(
      cachePolicy: ModelCachePolicy.refresh,
      cacheDirectory: '/tmp/genkit-cache',
      sha256: 'a' * 64,
      bearerToken: 'secret-token',
      headers: const <String, String>{'X-Test': 'yes'},
      resume: false,
      maxRetries: 1,
    );
    ModelDownloadProgress? observedProgress;

    final prepared = await llamaDart.prepareModel(
      name: 'chat',
      source: source,
      options: options,
      downloadManager: manager,
      mediaResolver: resolver,
      onModelProgress: (progress) {
        observedProgress = progress;
      },
      supportsEmbeddings: false,
      supportsTools: false,
      supportsConstrainedOutput: false,
    );

    addTearDown(prepared.dispose);
    await expectResolverUsed(prepared.plugin, resolver);
    expect(manager.calls, hasLength(1));
    expect(manager.calls.single.source, same(source));
    expect(manager.calls.single.options, same(options));
    expect(manager.calls.single.onProgress, isNotNull);
    expect(observedProgress?.fraction, 0.5);
    expect(prepared.modelEntry.filePath, '/cache/chat.gguf');
    expect(prepared.definition.modelPath, '/cache/chat.gguf');
    expect(prepared.definition.mmprojPath, isNull);
    expect(prepared.definition.supportsEmbeddings, isFalse);
    expect(prepared.definition.supportsTools, isFalse);
    expect(prepared.definition.supportsConstrainedOutput, isFalse);
    expect(prepared.embedderRef, isNull);
  });

  test('prepareModel resolves optional multimodal projector source', () async {
    final manager = _FakeDownloadManager();
    final source = ModelSource.url(
      Uri.parse('https://example.com/models/vision.gguf'),
    );
    final mmprojSource = ModelSource.url(
      Uri.parse('https://example.com/models/mmproj.gguf'),
    );
    final mmprojOptions = ModelLoadOptions(
      cachePolicy: ModelCachePolicy.cacheOnly,
    );

    final prepared = await llamaDart.prepareModel(
      name: 'vision',
      source: source,
      mmprojSource: mmprojSource,
      mmprojOptions: mmprojOptions,
      downloadManager: manager,
    );

    expect(manager.calls, hasLength(2));
    expect(manager.calls.first.source, same(source));
    expect(manager.calls.last.source, same(mmprojSource));
    expect(manager.calls.last.options, same(mmprojOptions));
    expect(prepared.definition.modelPath, '/cache/vision.gguf');
    expect(prepared.definition.mmprojPath, '/cache/mmproj.gguf');
    expect(prepared.mmprojEntry?.filePath, '/cache/mmproj.gguf');
    expect(prepared.embedderRef, isNotNull);
  });

  test(
    'prepareModel lets llamadart reject remote-only options for local paths',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'genkit_llamadart_prepare_model_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final modelFile = File('${tempDir.path}/local.gguf');
      await modelFile.writeAsString('fake gguf content');

      await expectLater(
        llamaDart.prepareModel(
          name: 'local',
          source: ModelSource.path(modelFile.path),
          options: ModelLoadOptions(cachePolicy: ModelCachePolicy.refresh),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    },
  );

  test(
    'prepareModel rejects empty model names before resolving sources',
    () async {
      final manager = _FakeDownloadManager();

      await expectLater(
        llamaDart.prepareModel(
          name: '',
          source: ModelSource.path('/tmp/model.gguf'),
          downloadManager: manager,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(manager.calls, isEmpty);
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
  final List<_EnsureModelCall> calls = <_EnsureModelCall>[];

  @override
  Future<ModelCacheEntry> ensureModel(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    calls.add(_EnsureModelCall(source, options, onProgress));
    onProgress?.call(
      const ModelDownloadProgress(receivedBytes: 5, totalBytes: 10),
    );
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
    return null;
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
