@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'engine_test.dart' show MockLlamaBackend;

void main() {
  late Directory directory;
  late _TrackingManager downloads;
  late ModelFileStore store;
  late MockLlamaBackend backend;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('llamadart_set_model_');
    downloads = _TrackingManager(
      DefaultModelDownloadManager.appPrivate(
        cacheDirectory: p.join(directory.path, 'cache'),
      ),
    );
    store = ModelFileStore(downloadManager: downloads);
    backend = MockLlamaBackend();
  });

  tearDown(() => directory.delete(recursive: true));

  File local(String name) =>
      File(p.join(directory.path, name))..writeAsBytesSync([1, 2, 3]);

  test('load reads a local file whose name holds %2F, and a directory named '
      '%2e, from its path', () async {
    final escapedName = local('a%2Fb.gguf');
    await Directory(p.join(directory.path, '%2e')).create();
    final escapedDirectory = local(p.join('%2e', 'mmproj.gguf'));

    final engine = await LlamaEngine.load(
      LlamaModel(
        ModelSource.path(escapedName.path),
        projector: ModelSource.path(escapedDirectory.path),
      ),
      store: store,
      backend: backend,
    );

    expect(backend.lastModelPath, p.normalize(p.absolute(escapedName.path)));
    expect(
      backend.lastMultimodalProjectorPath,
      p.normalize(p.absolute(escapedDirectory.path)),
    );
    await engine.dispose();
  });

  test('a projector and an adapter whose names hold %2F load on a loaded '
      'model', () async {
    final engine = await LlamaEngine.load(
      LlamaModel(ModelSource.path(local('model.gguf').path)),
      store: store,
      backend: backend,
    );
    final projector = local('mm%2Fproj.gguf');
    final adapter = local('lora%5Ca.gguf');

    await engine.loadMultimodalProjectorSource(
      ModelSource.path(projector.path),
    );
    await engine.setLoraSource(ModelSource.path(adapter.path));

    expect(
      backend.lastMultimodalProjectorPath,
      p.normalize(p.absolute(projector.path)),
    );
    expect(backend.lastLoraPath, p.normalize(p.absolute(adapter.path)));
    await engine.dispose();
  });

  test('a local file that is missing or fails its checksum throws before the '
      'loaded model is replaced', () async {
    final first = local('first.gguf');
    final second = local('second.gguf');
    final engine = await LlamaEngine.load(
      LlamaModel(ModelSource.path(first.path)),
      store: store,
      backend: backend,
    );

    await expectLater(
      engine.setModel(
        LlamaModel(ModelSource.path(p.join(directory.path, 'missing.gguf'))),
      ),
      throwsA(
        isA<LlamaModelException>().having(
          (error) => error.message,
          'message',
          contains('Local model file does not exist'),
        ),
      ),
    );
    await expectLater(
      engine.setModel(
        LlamaModel(ModelSource.path(second.path)),
        download: ModelLoadOptions(sha256: '0' * 64),
      ),
      throwsA(
        isA<LlamaModelException>().having(
          (error) => error.message,
          'message',
          contains('Checksum mismatch for local model file'),
        ),
      ),
    );

    expect(backend.modelLoadCalls, 1);
    expect(backend.modelFreeCalls, 0);
    expect(engine.isReady, isTrue);

    await engine.setModel(
      LlamaModel(ModelSource.path(second.path)),
      download: ModelLoadOptions(
        sha256:
            '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
      ),
    );
    expect(backend.lastModelPath, p.normalize(p.absolute(second.path)));
    await engine.dispose();
  });

  group('a model cache directory that cannot be created', () {
    late String cacheRoot;
    late ModelLoadOptions blocked;
    final remote = ModelSource.url(
      Uri.parse('http://127.0.0.1:9/models/remote.gguf'),
    );
    final cannotCreate = throwsA(
      isA<LlamaModelException>().having(
        (error) => error.message,
        'message',
        allOf(
          contains('Cannot create the model cache directory'),
          contains('writable'),
        ),
      ),
    );

    setUp(() {
      final blocker = File(p.join(directory.path, 'not-a-directory'))
        ..writeAsStringSync('');
      cacheRoot = p.join(blocker.path, 'cache');
      blocked = ModelLoadOptions(cacheDirectory: cacheRoot, maxRetries: 0);
    });

    test('fails model loads with LlamaModelException', () async {
      final engine = LlamaEngine(backend, modelDownloadManager: downloads);

      await expectLater(
        engine.loadModelSource(remote, options: blocked),
        cannotCreate,
      );
      await expectLater(
        LlamaEngine.load(
          LlamaModel(remote),
          download: blocked,
          store: store,
          backend: backend,
        ),
        cannotCreate,
      );
      expect(backend.modelLoadCalls, 0);
      await engine.dispose();
    });

    test(
      'fails projector and adapter loads with LlamaModelException',
      () async {
        final engine = await LlamaEngine.load(
          LlamaModel(ModelSource.path(local('model.gguf').path)),
          store: store,
          backend: backend,
        );

        await expectLater(
          engine.loadMultimodalProjectorSource(remote, download: blocked),
          cannotCreate,
        );
        await expectLater(
          engine.setLoraSource(remote, download: blocked),
          cannotCreate,
        );
        await engine.dispose();
      },
    );
  });

  group('a resolver that mirrors remote sources to local files', () {
    final remoteOptions = ModelLoadOptions(
      cacheDirectory: 'unused-cache',
      bearerToken: 'secret-token',
      headers: const {'X-Test': '1'},
      cachePolicy: ModelCachePolicy.refresh,
      resume: false,
      maxRetries: 0,
    );
    ModelSource remote(String name) =>
        ModelSource.url(Uri.parse('https://example.com/models/$name'));

    test('loadModelSource loads the mirror file with the remote download '
        'options, and still checks its checksum', () async {
      final mirrored = local('model.gguf');
      final engine = LlamaEngine(
        backend,
        modelResolver: _MirrorResolver(directory.path),
        modelDownloadManager: downloads,
      );

      await engine.loadModelSource(
        remote('model.gguf'),
        options: remoteOptions,
      );
      expect(backend.lastModelPath, p.normalize(p.absolute(mirrored.path)));
      await engine.unloadModel();

      await expectLater(
        engine.loadModelSource(
          remote('model.gguf'),
          options: ModelLoadOptions(
            cacheDirectory: 'unused-cache',
            sha256: '0' * 64,
          ),
        ),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'message',
            contains('Checksum mismatch for local model file'),
          ),
        ),
      );
      await engine.dispose();
    });

    test('LlamaEngine.load loads a mirrored model and projector with the '
        'remote download options', () async {
      final model = local('model.gguf');
      final projector = local('mmproj.gguf');

      final engine = await LlamaEngine.load(
        LlamaModel(remote('model.gguf'), projector: remote('mmproj.gguf')),
        download: remoteOptions,
        store: ModelFileStore(
          resolver: _MirrorResolver(directory.path),
          downloadManager: downloads,
        ),
        backend: backend,
      );

      expect(backend.lastModelPath, p.normalize(p.absolute(model.path)));
      expect(
        backend.lastMultimodalProjectorPath,
        p.normalize(p.absolute(projector.path)),
      );
      await engine.dispose();
    });

    test('a local source still rejects remote download options', () async {
      final engine = LlamaEngine(
        backend,
        modelResolver: _MirrorResolver(directory.path),
        modelDownloadManager: downloads,
      );

      await expectLater(
        engine.loadModelSource(
          ModelSource.path(local('model.gguf').path),
          options: ModelLoadOptions(cacheDirectory: 'unused-cache'),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('do not use cacheDirectory'),
          ),
        ),
      );
      await engine.dispose();
    });
  });

  group('with a download in progress', () {
    late HttpServer server;
    late Completer<void> firstChunkSent;
    late Completer<void> finish;

    setUp(() async {
      firstChunkSent = Completer<void>();
      finish = Completer<void>();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final response = request.response
          ..statusCode = HttpStatus.ok
          ..bufferOutput = false
          ..headers.contentLength = 8;
        try {
          response.add(const [1, 2, 3, 4]);
          await response.flush();
          if (!firstChunkSent.isCompleted) firstChunkSent.complete();
          await finish.future;
          response.add(const [5, 6, 7, 8]);
          await response.close();
        } on Object {
          // The client stopped reading.
        }
      });
    });

    tearDown(() async {
      if (!finish.isCompleted) finish.complete();
      await server.close(force: true);
    });

    ModelSource remote() =>
        ModelSource.url(Uri.parse('http://127.0.0.1:${server.port}/big.gguf'));

    List<String> cachedModels() => [
      for (final file in directory.listSync(recursive: true).whereType<File>())
        if (p.basename(file.path) == 'big.gguf') file.path,
    ];

    test('dispose stops the download: load throws, nothing loads and no '
        'file is cached', () async {
      final engine = LlamaEngine(
        backend,
        modelDownloadManager: store.downloadManager,
      );
      final loading = engine.setModel(LlamaModel(remote()));
      final outcome = expectLater(
        loading,
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            contains('disposed while loading'),
          ),
        ),
      );
      await firstChunkSent.future;

      await engine.dispose();
      await outcome;
      expect(downloads.running, 1);
      finish.complete();
      await downloads.settled;

      expect(backend.modelLoadCalls, 0);
      expect(backend.disposeCalls, 1);
      expect(engine.isReady, isFalse);
      expect(cachedModels(), isEmpty);
    });

    for (final isAdapter in [false, true]) {
      final label = isAdapter ? 'adapter' : 'model';
      test('legacy disposal cancels an HTTP $label transfer without caching '
          'a complete file or loading the backend', () async {
        final source = remote();
        final callerToken = ModelDownloadCancelToken();
        final adapterToken = ModelDownloadCancelToken();
        final engine = LlamaEngine(
          backend,
          modelDownloadManager: store.downloadManager,
        );
        final loading = engine.loadModelSource(
          isAdapter ? ModelSource.path(local('first.gguf').path) : source,
          options: ModelLoadOptions(cancelToken: callerToken),
          modelParams: ModelParams(
            loras: isAdapter
                ? [
                    LoraAdapterConfig.source(
                      source,
                      download: ModelLoadOptions(cancelToken: adapterToken),
                    ),
                  ]
                : [],
          ),
        );
        final outcome = expectLater(
          loading,
          throwsA(isA<LlamaStateException>()),
        );
        try {
          // Wait until the actual manager consumes the first response chunk,
          // rather than merely until the server sends it.
          await downloads.bytesReceived(source);
          await engine.dispose();
          await outcome.timeout(const Duration(seconds: 5));

          expect(callerToken.isCancelled, isFalse);
          expect(adapterToken.isCancelled, isFalse);
          expect(backend.modelLoadCalls, 0);
          expect(backend.disposeCalls, 1);
          expect(engine.isReady, isFalse);
          expect(cachedModels(), isEmpty);
        } finally {
          if (!finish.isCompleted) finish.complete();
          await outcome;
          await downloads.settled;
          await engine.dispose();
        }
        expect(cachedModels(), isEmpty);
        final partials = directory
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => p.basename(file.path) == 'big.gguf.part');
        expect(partials, hasLength(1));
        expect(await partials.single.length(), 4);
        expect(backend.modelLoadCalls, 0);
      });
    }

    test("the caller's cancel token stops the download and the loaded model "
        'stays', () async {
      final first = local('first.gguf');
      final engine = await LlamaEngine.load(
        LlamaModel(ModelSource.path(first.path)),
        store: store,
        backend: backend,
      );
      final token = ModelDownloadCancelToken();

      final replacing = engine.setModel(
        LlamaModel(remote()),
        download: ModelLoadOptions(cancelToken: token),
      );
      final outcome = expectLater(
        replacing,
        throwsA(isA<LlamaStateException>()),
      );
      await firstChunkSent.future;
      token.cancel();
      finish.complete();
      await outcome;

      expect(backend.modelLoadCalls, 1);
      expect(backend.modelFreeCalls, 0);
      expect(engine.isReady, isTrue);
      expect(cachedModels(), isEmpty);
      await engine.dispose();
    });

    test('the download completes and replaces the loaded model', () async {
      final first = local('first.gguf');
      final engine = await LlamaEngine.load(
        LlamaModel(ModelSource.path(first.path)),
        store: store,
        backend: backend,
      );
      final progress = <ModelDownloadProgress>[];

      final replacing = engine.setModel(
        LlamaModel(remote()),
        onProgress: progress.add,
      );
      await firstChunkSent.future;
      expect(engine.isReady, isTrue);
      expect(backend.modelFreeCalls, 0);
      finish.complete();
      await replacing;

      expect(backend.modelFreeCalls, 1);
      expect(backend.lastModelPath, cachedModels().single);
      expect(progress.last.receivedBytes, 8);
      expect(progress.last.totalBytes, 8);
      await engine.dispose();
    });
  });
}

/// Resolves each remote source to the file of the same name in [directory].
class _MirrorResolver implements ModelResolver {
  _MirrorResolver(this.directory);

  final String directory;

  @override
  Future<ModelLoadTarget> resolve(
    ModelSource source,
    ModelResolveRequest request,
  ) async => LocalModelFile(
    source.isLocal ? source.path! : p.join(directory, source.fileName),
  );
}

/// Runs the package download manager and tells when its downloads have
/// ended, so a test can wait for one the engine no longer awaits.
class _TrackingManager implements ModelDownloadManager {
  _TrackingManager(this._manager);

  final ModelDownloadManager _manager;
  final List<Future<void>> _downloads = <Future<void>>[];
  int running = 0;
  final Map<String, Completer<void>> _firstBytes = {};

  Future<void> bytesReceived(ModelSource source) =>
      _firstBytes.putIfAbsent(source.cacheKey, Completer<void>.new).future;

  Future<void> get settled => Future.wait(_downloads);

  @override
  Future<ModelCacheEntry> ensureModel(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) {
    running += 1;
    final download = _manager.ensureModel(
      source,
      options: options,
      onProgress: (progress) {
        if (progress.receivedBytes > 0) {
          final received = _firstBytes.putIfAbsent(
            source.cacheKey,
            Completer<void>.new,
          );
          if (!received.isCompleted) received.complete();
        }
        onProgress?.call(progress);
      },
    );
    _downloads.add(
      download.then<void>((_) {}, onError: (_) {}).whenComplete(() {
        running -= 1;
      }),
    );
    return download;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
