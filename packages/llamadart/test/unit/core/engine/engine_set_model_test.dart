import 'dart:async';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/models/model_target_file.dart'
    show UncacheableLocalModelFileException;
import 'package:test/test.dart';

import 'engine_test.dart' show MockLlamaBackend;

void main() {
  final remoteModel = ModelSource.parse('hf://owner/repo/model.gguf');
  final remoteProjector = ModelSource.parse('hf://owner/repo/mmproj.gguf');
  final localModel = ModelSource.path('/models/local.gguf');
  final otherModel = ModelSource.parse('https://example.com/other.gguf');
  final adapter = ModelSource.parse('https://example.com/adapters/tone.gguf');

  Map<ModelSource, String> cacheFiles() => {
    remoteModel: '/cache/model.gguf',
    remoteProjector: '/cache/mmproj.gguf',
    otherModel: '/cache/other.gguf',
    adapter: '/cache/tone.gguf',
  };

  group('LlamaEngine.setModel on a file backend', () {
    test('downloads the model and its projector, then loads both', () async {
      final backend = _Backend();
      final manager = _Manager(cacheFiles());
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      final progress = <ModelDownloadProgress>[];

      await engine.setModel(
        LlamaModel(remoteModel, projector: remoteProjector),
        params: const ModelParams(contextSize: 1024),
        onProgress: progress.add,
      );

      expect(engine.isReady, isTrue);
      expect(engine.hasMultimodalProjector, isTrue);
      expect(backend.events, [
        'modelLoad /cache/model.gguf',
        'projector /cache/mmproj.gguf',
      ]);
      expect(backend.contextParams.single.contextSize, 1024);
      expect(manager.sources, [remoteModel.cacheKey, remoteProjector.cacheKey]);
      expect(progress.last.receivedBytes, 200);
      expect(progress.last.totalBytes, 200);
      await engine.dispose();
    });

    test('keeps the loaded model serving until every file has resolved, then '
        'replaces it', () async {
      final backend = _Backend();
      final manager = _Manager(cacheFiles(), gated: {remoteProjector});
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      await engine.setModel(LlamaModel(localModel));
      backend.events.clear();

      final replacing = engine.setModel(
        LlamaModel(remoteModel, projector: remoteProjector),
      );
      await manager.started(remoteProjector);

      expect(engine.isReady, isTrue);
      expect(backend.events, isEmpty);
      expect(
        await engine.create([
          const LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ]).text(),
        'response',
      );

      manager.release(remoteProjector);
      await replacing;

      expect(backend.events, [
        'contextFree',
        'modelFree',
        'modelLoad /cache/model.gguf',
        'projector /cache/mmproj.gguf',
      ]);
      expect(engine.isReady, isTrue);
      await engine.dispose();
    });

    test(
      'a file that fails to resolve leaves the loaded model as it was',
      () async {
        final backend = _Backend();
        final manager = _Manager(cacheFiles(), failing: {remoteProjector});
        final engine = LlamaEngine(backend, modelDownloadManager: manager);
        await engine.setModel(LlamaModel(localModel));
        backend.events.clear();

        await expectLater(
          engine.setModel(LlamaModel(remoteModel, projector: remoteProjector)),
          throwsA(isA<LlamaModelException>()),
        );

        expect(backend.events, isEmpty);
        expect(engine.isReady, isTrue);
        expect(await engine.getTokenCount('still here'), 3);
        await engine.dispose();
      },
    );

    test('a projector that fails to load leaves nothing loaded', () async {
      final backend = _Backend()..projectorError = Exception('bad projector');
      final engine = LlamaEngine(
        backend,
        modelDownloadManager: _Manager(cacheFiles()),
      );
      await engine.setModel(LlamaModel(localModel));
      backend.events.clear();

      await expectLater(
        engine.setModel(LlamaModel(remoteModel, projector: remoteProjector)),
        throwsA(isA<LlamaModelException>()),
      );

      expect(backend.events, [
        'contextFree',
        'modelFree',
        'modelLoad /cache/model.gguf',
        'projector /cache/mmproj.gguf',
        'contextFree',
        'modelFree',
      ]);
      expect(engine.isReady, isFalse);
      expect(engine.modelHandle, isNull);
      expect(engine.hasMultimodalProjector, isFalse);

      backend.projectorError = null;
      await engine.setModel(
        LlamaModel(remoteModel, projector: remoteProjector),
      );
      expect(engine.isReady, isTrue);
      await engine.dispose();
    });

    test('a model that fails to load leaves nothing loaded', () async {
      final backend = _Backend();
      final engine = LlamaEngine(
        backend,
        modelDownloadManager: _Manager(cacheFiles()),
      );
      await engine.setModel(LlamaModel(localModel));
      backend.modelLoadError = Exception('corrupt');

      await expectLater(
        engine.setModel(LlamaModel(remoteModel)),
        throwsA(isA<LlamaModelException>()),
      );

      expect(engine.isReady, isFalse);
      expect(engine.modelHandle, isNull);
      await engine.dispose();
    });

    group('rejects before any file access, keeping the loaded model', () {
      late _Backend backend;
      late _Manager manager;
      late _CountingResolver resolver;
      late LlamaEngine engine;

      setUp(() async {
        backend = _Backend();
        manager = _Manager(cacheFiles());
        resolver = _CountingResolver();
        engine = LlamaEngine(
          backend,
          modelResolver: resolver,
          modelDownloadManager: manager,
        );
        await engine.setModel(LlamaModel(localModel));
        manager.sources.clear();
        resolver.calls = 0;
        backend.events.clear();
      });

      tearDown(() => engine.dispose());

      Future<void> expectRejected(
        Future<void> Function() load,
        Matcher error,
      ) async {
        await expectLater(load(), throwsA(error));
        expect(resolver.calls, 0);
        expect(manager.sources, isEmpty);
        expect(backend.events, isEmpty);
        expect(engine.isReady, isTrue);
      }

      test('a runtime-specific ModelParams for the other runtime', () async {
        await expectRejected(
          () => engine.setModel(
            LlamaModel(remoteModel),
            params: const LiteRtLmModelParams(embeddingEngine: true),
          ),
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'message',
            contains('Use LlamaCppModelParams.'),
          ),
        );
      });

      test('an invalid ModelParams', () async {
        await expectRejected(
          () => engine.setModel(
            LlamaModel(remoteModel),
            params: const ModelParams(
              device: ComputeDevice.cpu,
              preferredBackend: GpuBackend.vulkan,
            ),
          ),
          isA<LlamaArgumentException>(),
        );
      });

      test('a projector for a LiteRT-LM model, known by its file name or its '
          'format', () async {
        for (final source in [
          ModelSource.parse('hf://owner/repo/gemma.litertlm'),
          ModelSource.path('/models/GEMMA.LITERTLM'),
          ModelSource.parse(
            'https://example.com/download?id=7',
            format: ModelFormat.liteRtLm,
          ),
        ]) {
          await expectRejected(
            () =>
                engine.setModel(LlamaModel(source, projector: remoteProjector)),
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              contains('LiteRT-LM model takes no multimodal projector'),
            ),
          );
        }
      });

      test('ComputeDevice.npu for a GGUF model', () async {
        for (final source in [
          remoteModel,
          ModelSource.parse(
            'https://example.com/download?id=7',
            format: ModelFormat.gguf,
          ),
        ]) {
          await expectRejected(
            () => engine.setModel(
              LlamaModel(source),
              params: const ModelParams(device: ComputeDevice.npu),
            ),
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              contains('ComputeDevice.npu is not available for llama.cpp'),
            ),
          );
        }
      });

      test('liteRtLmEmbeddingEngine for a GGUF model', () async {
        await expectRejected(
          () => engine.setModel(
            LlamaModel(remoteModel),
            params: const ModelParams(liteRtLmEmbeddingEngine: true),
          ),
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('liteRtLmEmbeddingEngine applies only to LiteRT-LM'),
          ),
        );
      });

      test('a checksum for a model with a projector', () async {
        await expectRejected(
          () => engine.setModel(
            LlamaModel(remoteModel, projector: remoteProjector),
            download: ModelLoadOptions(sha256: 'a' * 64),
          ),
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            'Model loading uses 2 files, so ModelLoadOptions.sha256 cannot '
                'apply to them. Leave it unset.',
          ),
        );
      });

      test('a format the backend cannot route to a runtime', () async {
        await expectRejected(
          () => engine.setModel(
            LlamaModel(
              ModelSource.parse(
                'hf://owner/repo/model.litertlm',
                format: ModelFormat.liteRtLm,
              ),
            ),
          ),
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('cannot load ModelFormat.liteRtLm'),
          ),
        );
      });

      test('credentials for files on two hosts', () async {
        await expectLater(
          engine.setModel(
            LlamaModel(remoteModel, projector: otherModel),
            download: ModelLoadOptions(bearerToken: 'secret-token'),
          ),
          throwsA(
            isA<LlamaArgumentException>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('huggingface.co'),
                contains('example.com'),
                isNot(contains('secret-token')),
              ),
            ),
          ),
        );
        expect(manager.sources, isEmpty);
        expect(backend.events, isEmpty);
        expect(engine.isReady, isTrue);
      });
    });

    test('asks the backend to check ModelParams for the named format before '
        'any download', () async {
      final backend = _ParamsCheckBackend();
      final manager = _Manager(cacheFiles());
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      addTearDown(engine.dispose);
      const ignored = ModelParams(liteRtLmCacheDir: '/cache');

      await expectLater(
        engine.setModel(LlamaModel(remoteModel), params: ignored),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(backend.checkedFormats, [ModelFormat.gguf]);
      expect(manager.sources, isEmpty);
      expect(backend.events, isEmpty);

      final unnamed = ModelSource.parse('https://example.com/download?id=7');
      await expectLater(
        engine.setModel(LlamaModel(unnamed), params: ignored),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(backend.checkedFormats, [ModelFormat.gguf, null]);
      expect(manager.sources, isEmpty);

      await engine.setModel(LlamaModel(remoteModel));
      expect(backend.events, ['modelLoad /cache/model.gguf']);
    });

    test('does not reject a device or projector for a file whose format it '
        'cannot tell', () async {
      final backend = _Backend();
      final source = ModelSource.parse('https://example.com/download?id=7');
      final engine = LlamaEngine(
        backend,
        modelDownloadManager: _Manager({
          source: '/cache/download',
          remoteProjector: '/cache/mmproj.gguf',
        }),
      );

      await engine.setModel(
        LlamaModel(source, projector: remoteProjector),
        params: const ModelParams(device: ComputeDevice.npu),
      );

      expect(backend.events.first, 'modelLoad /cache/download');
      await engine.dispose();
    });

    test('a remote file takes the download options and a local file only '
        'the checksum and cancel token', () async {
      final manager = _Manager(cacheFiles());
      final engine = LlamaEngine(_Backend(), modelDownloadManager: manager);
      final token = ModelDownloadCancelToken();

      await engine.setModel(
        LlamaModel(remoteModel, projector: ModelSource.path('/m/mmproj.gguf')),
        download: ModelLoadOptions(
          bearerToken: 'secret-token',
          cacheDirectory: '/models',
          cachePolicy: ModelCachePolicy.refresh,
          maxRetries: 7,
          cancelToken: token,
        ),
      );

      final remote = manager.options[0];
      expect(remote.bearerToken, 'secret-token');
      expect(remote.cacheDirectory, '/models');
      expect(remote.cachePolicy, ModelCachePolicy.refresh);
      expect(remote.maxRetries, 7);
      final local = manager.options[1];
      expect(local.bearerToken, isNull);
      expect(local.cacheDirectory, isNull);
      expect(local.cachePolicy, ModelCachePolicy.preferCached);
      expect(local.maxRetries, 3);
      for (final options in manager.options) {
        expect(options.cancelToken!.isCancelled, isFalse);
      }
      token.cancel();
      for (final options in manager.options) {
        expect(options.cancelToken!.isCancelled, isTrue);
      }
      await engine.dispose();
    });

    test('verifies a single local file against the checksum', () async {
      final manager = _Manager(const {});
      final engine = LlamaEngine(_Backend(), modelDownloadManager: manager);

      await engine.setModel(
        LlamaModel(localModel),
        download: ModelLoadOptions(sha256: 'b' * 64),
      );

      expect(manager.options.single.sha256, 'b' * 64);
      await engine.dispose();
    });

    test('loads a local file its download manager cannot describe as a '
        'cache entry', () async {
      final backend = _Backend();
      final engine = LlamaEngine(
        backend,
        modelDownloadManager: _Manager(
          const {},
          uncacheable: {'/models/a%2Fb.gguf'},
        ),
      );

      await engine.setModel(LlamaModel(ModelSource.path('/models/a%2Fb.gguf')));

      expect(backend.events, ['modelLoad /abs/models/a%2Fb.gguf']);
      await engine.dispose();
    });

    test(
      'passes an explicit format to a backend that routes by format',
      () async {
        final backend = _RoutingBackend();
        final engine = LlamaEngine(
          backend,
          modelDownloadManager: _Manager(const {}),
        );

        await engine.setModel(
          LlamaModel(
            ModelSource.path('/models/blob', format: ModelFormat.liteRtLm),
          ),
        );

        expect(backend.events, ['modelLoadAs liteRtLm /models/blob']);
        await engine.dispose();
      },
    );

    test('resolves ModelParams.loras sources before it replaces the model, '
        'with only the non-secret download options', () async {
      final backend = _Backend();
      final manager = _Manager(cacheFiles(), gated: {adapter});
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      await engine.setModel(LlamaModel(localModel));
      backend.events.clear();

      final replacing = engine.setModel(
        LlamaModel(remoteModel),
        params: ModelParams(
          loras: [LoraAdapterConfig.source(adapter, scale: 0.5)],
        ),
        download: ModelLoadOptions(
          bearerToken: 'secret-token',
          cacheDirectory: '/models',
        ),
      );
      await manager.started(adapter);
      expect(backend.events, isEmpty);
      expect(engine.isReady, isTrue);
      manager.release(adapter);
      await replacing;

      final adapterOptions = manager.options.last;
      expect(adapterOptions.bearerToken, isNull);
      expect(adapterOptions.cacheDirectory, '/models');
      expect(
        [
          for (final lora in backend.contextParams.last.loras)
            (lora.path, lora.scale),
        ],
        [('/cache/tone.gguf', 0.5)],
      );
      await engine.removeLoraSource(adapter);
      expect(backend.removedLoraPaths, ['/cache/tone.gguf']);
      await engine.dispose();
    });

    test('loads local adapters and a local draft model their download '
        'manager cannot describe as cache entries', () async {
      final backend = _Backend();
      const loadAdapter = '/models/load%2Fadapter.gguf';
      const laterAdapter = '/models/later%2Fadapter.gguf';
      const draft = '/models/draft%2Fmodel.gguf';
      final engine = LlamaEngine(
        backend,
        modelDownloadManager: _Manager(
          const {},
          uncacheable: {loadAdapter, laterAdapter, draft},
        ),
      );

      await engine.setModel(
        LlamaModel(localModel),
        params: ModelParams(
          loras: [LoraAdapterConfig.source(ModelSource.path(loadAdapter))],
        ),
      );
      await engine.setLoraSource(ModelSource.path(laterAdapter));
      await engine
          .generate(
            'hi',
            params: GenerationParams(
              speculativeDecodingConfig: SpeculativeDecodingConfig.draftSimple(
                draftModel: ModelSource.path(draft),
              ),
            ),
          )
          .drain<void>();

      expect(
        backend.contextParams.single.loras.single.path,
        '/abs$loadAdapter',
      );
      expect(backend.lastLoraPath, '/abs$laterAdapter');
      expect(
        backend.lastGenerationParams!.speculativeDecodingConfig!.draftModelPath,
        '/abs$draft',
      );
      await engine.dispose();
    });

    test('an adapter that fails to download leaves the loaded model as it '
        'was', () async {
      final backend = _Backend();
      final engine = LlamaEngine(
        backend,
        modelDownloadManager: _Manager(cacheFiles(), failing: {adapter}),
      );
      await engine.setModel(LlamaModel(localModel));
      backend.events.clear();

      await expectLater(
        engine.setModel(
          LlamaModel(remoteModel),
          params: ModelParams(loras: [LoraAdapterConfig.source(adapter)]),
        ),
        throwsA(isA<LlamaModelException>()),
      );

      expect(backend.events, isEmpty);
      expect(engine.isReady, isTrue);
      await engine.dispose();
    });

    test('while it downloads, another setModel and unloadModel throw and '
        'download nothing', () async {
      final backend = _Backend();
      final manager = _Manager(cacheFiles(), gated: {remoteModel});
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      await engine.setModel(LlamaModel(localModel));
      manager.sources.clear();

      final replacing = engine.setModel(LlamaModel(remoteModel));
      await manager.started(remoteModel);

      await expectLater(
        engine.setModel(LlamaModel(otherModel)),
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            contains('another model lifecycle operation'),
          ),
        ),
      );
      await expectLater(
        engine.unloadModel(),
        throwsA(isA<LlamaStateException>()),
      );
      expect(manager.sources, [remoteModel.cacheKey]);
      expect(engine.isReady, isTrue);

      manager.release(remoteModel);
      await replacing;
      expect(backend.lastModelPath, '/cache/model.gguf');
      await engine.dispose();
    });

    test("the caller's cancel token stops a download and keeps the loaded "
        'model', () async {
      final backend = _Backend();
      final manager = _Manager(cacheFiles(), polling: {remoteModel});
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      await engine.setModel(LlamaModel(localModel));
      backend.events.clear();
      final token = ModelDownloadCancelToken();

      final replacing = engine.setModel(
        LlamaModel(remoteModel),
        download: ModelLoadOptions(cancelToken: token),
      );
      await manager.started(remoteModel);
      token.cancel();

      await expectLater(replacing, throwsA(isA<LlamaStateException>()));
      expect(backend.events, isEmpty);
      expect(engine.isReady, isTrue);
      await engine.dispose();
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('a cancel token cancelled once the files have resolved stops the '
        'call with the loaded model as it was', () async {
      final backend = _Backend();
      final token = ModelDownloadCancelToken();
      final manager = _Manager(cacheFiles());
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      await engine.setModel(LlamaModel(localModel));
      backend.events.clear();
      manager.onResolved = token.cancel;

      await expectLater(
        engine.setModel(
          LlamaModel(remoteModel),
          download: ModelLoadOptions(cancelToken: token),
        ),
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            'Model loading was cancelled.',
          ),
        ),
      );
      expect(backend.events, isEmpty);
      expect(engine.isReady, isTrue);
      await engine.dispose();
    });

    test('a cancel token cancelled while an adapter resolves stops the call '
        'with the loaded model as it was', () async {
      final backend = _Backend();
      final token = ModelDownloadCancelToken();
      final manager = _Manager(cacheFiles());
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      await engine.setModel(LlamaModel(localModel));
      backend.events.clear();
      manager.onResolved = () {
        if (manager.sources.last == adapter.cacheKey) token.cancel();
      };

      await expectLater(
        engine.setModel(
          LlamaModel(remoteModel),
          params: ModelParams(loras: [LoraAdapterConfig.source(adapter)]),
          download: ModelLoadOptions(cancelToken: token),
        ),
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            'Model loading was cancelled.',
          ),
        ),
      );
      expect(backend.events, isEmpty);
      expect(engine.isReady, isTrue);
      await engine.dispose();
    });

    test('a cancel token cancelled while the projector loads leaves nothing '
        'loaded', () async {
      final backend = _Backend();
      final token = ModelDownloadCancelToken();
      backend.onProjectorLoad = token.cancel;
      final engine = LlamaEngine(
        backend,
        modelDownloadManager: _Manager(cacheFiles()),
      );

      await expectLater(
        engine.setModel(
          LlamaModel(remoteModel, projector: remoteProjector),
          download: ModelLoadOptions(cancelToken: token),
        ),
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            'Model loading was cancelled.',
          ),
        ),
      );
      expect(backend.events, [
        'modelLoad /cache/model.gguf',
        'projector /cache/mmproj.gguf',
        'contextFree',
        'modelFree',
      ]);
      expect(engine.isReady, isFalse);
      await engine.dispose();
    });

    test('dispose stops a download at once: the call throws, nothing loads '
        'and the download sees its token cancelled', () async {
      final backend = _Backend();
      final manager = _Manager(cacheFiles(), gated: {remoteModel});
      final engine = LlamaEngine(backend, modelDownloadManager: manager);

      final loading = engine.setModel(LlamaModel(remoteModel));
      await manager.started(remoteModel);
      final token = manager.options.single.cancelToken!;
      expect(token.isCancelled, isFalse);

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
      await engine.dispose();
      await outcome;

      expect(token.isCancelled, isTrue);
      expect(backend.events, isEmpty);
      expect(backend.disposeCalls, 1);
      manager.release(remoteModel);
      await pumpEventQueue();
      expect(backend.events, isEmpty);
      expect(engine.isReady, isFalse);
    });

    test('dispose stops an adapter download too', () async {
      final backend = _Backend();
      final manager = _Manager(cacheFiles(), polling: {adapter});
      final engine = LlamaEngine(backend, modelDownloadManager: manager);

      final loading = engine.setModel(
        LlamaModel(localModel),
        params: ModelParams(loras: [LoraAdapterConfig.source(adapter)]),
      );
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
      await manager.started(adapter);
      final token = manager.options.last.cancelToken!;
      expect(token.isCancelled, isFalse);
      await engine.dispose();
      await outcome;

      expect(token.isCancelled, isTrue);
      expect(backend.events, isEmpty);
    }, timeout: const Timeout(Duration(seconds: 10)));

    test(
      'dispose during the load unloads the model and the call throws',
      () async {
        final loadGate = Completer<void>();
        final backend = _Backend()..modelLoadDelay = loadGate.future;
        final engine = LlamaEngine(
          backend,
          modelDownloadManager: _Manager(cacheFiles()),
        );

        final loading = engine.setModel(
          LlamaModel(remoteModel, projector: remoteProjector),
        );
        await backend.modelLoadStarted.future;
        final dispose = engine.dispose();
        loadGate.complete();

        await expectLater(
          loading,
          throwsA(
            isA<LlamaStateException>().having(
              (error) => error.message,
              'message',
              contains('disposed while loading'),
            ),
          ),
        );
        await dispose;
        expect(backend.modelFreeCalls, 1);
        expect(backend.disposeCalls, 1);
        expect(engine.isReady, isFalse);
      },
    );

    test('dispose while the replaced model unloads stops the call before '
        'the new model loads', () async {
      final unloadGate = Completer<void>();
      final backend = _Backend();
      final engine = LlamaEngine(
        backend,
        modelDownloadManager: _Manager(cacheFiles()),
      );
      await engine.setModel(LlamaModel(localModel));
      backend
        ..events.clear()
        ..contextFreeDelay = unloadGate.future;

      final replacing = engine.setModel(LlamaModel(remoteModel));
      final outcome = expectLater(
        replacing,
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            contains('disposed while loading'),
          ),
        ),
      );
      await pumpEventQueue();
      expect(backend.events, ['contextFree']);
      final dispose = engine.dispose();
      unloadGate.complete();
      await outcome;
      await dispose;

      expect(backend.events, ['contextFree', 'modelFree']);
      expect(backend.disposeCalls, 1);
    });

    test('dispose while the loaded model is read for observers makes the '
        'call throw, and unloads the model', () async {
      final backend = _Backend()..metadataGate = Completer<void>();
      final engine = LlamaEngine(
        backend,
        modelDownloadManager: _Manager(cacheFiles()),
        observers: [_LoadObserver()],
      );

      final loading = engine.setModel(LlamaModel(remoteModel));
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
      await backend.metadataStarted.future;
      final dispose = engine.dispose();
      backend.metadataGate!.complete();
      await outcome;
      await dispose;

      expect(backend.events, [
        'modelLoad /cache/model.gguf',
        'contextFree',
        'modelFree',
      ]);
      expect(engine.isReady, isFalse);
    });

    test('throws LlamaStateException after dispose', () async {
      final manager = _Manager(cacheFiles());
      final engine = LlamaEngine(_Backend(), modelDownloadManager: manager);
      await engine.dispose();

      await expectLater(
        engine.setModel(LlamaModel(remoteModel)),
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            contains('disposed'),
          ),
        ),
      );
      expect(manager.sources, isEmpty);
    });

    test('reports the whole call to observers as one model load', () async {
      final observer = _LoadObserver();
      final manager = _Manager(cacheFiles(), gated: {remoteModel});
      final engine = LlamaEngine(
        _Backend(),
        modelDownloadManager: manager,
        observers: [observer],
      );
      const params = ModelParams(contextSize: 1024);

      final loading = engine.setModel(
        LlamaModel(remoteModel, projector: remoteProjector),
        params: params,
      );
      await manager.started(remoteModel);
      expect(observer.started.single.model, 'model.gguf');
      expect(observer.started.single.modelParams, same(params));
      expect(observer.ended, isEmpty);
      manager.release(remoteModel);
      await loading;

      expect(observer.started, hasLength(1));
      expect(observer.ended, [null]);
      await engine.dispose();
    });

    test('reports a file that fails to resolve to observers as a failed '
        'model load', () async {
      final observer = _LoadObserver();
      final engine = LlamaEngine(
        _Backend(),
        modelDownloadManager: _Manager(cacheFiles(), failing: {remoteModel}),
        observers: [observer],
      );

      await expectLater(
        engine.setModel(LlamaModel(remoteModel)),
        throwsA(isA<LlamaModelException>()),
      );

      expect(observer.started.single.model, 'model.gguf');
      expect(observer.ended.single, isA<LlamaModelException>());
      await engine.dispose();
    });
  });

  group('LlamaEngine.setModel on a URL-loading backend', () {
    test('hands the runtime the URL of a remote source and the path of a '
        'local one, as written', () async {
      final backend = _Backend(urlLoadingSupported: true);
      final manager = _Manager(const {});
      final engine = LlamaEngine(backend, modelDownloadManager: manager);

      await engine.setModel(
        LlamaModel(
          ModelSource.path('models/tiny.gguf'),
          projector: ModelSource.path('blob:https://app.example/3f2a'),
        ),
      );
      await engine.setModel(LlamaModel(otherModel, projector: remoteProjector));

      expect(backend.events, [
        'modelLoadFromUrl models/tiny.gguf',
        'projector blob:https://app.example/3f2a',
        'contextFree',
        'modelFree',
        'modelLoadFromUrl https://example.com/other.gguf',
        'projector https://huggingface.co/owner/repo/resolve/main/'
            'mmproj.gguf?download=true',
      ]);
      expect(manager.sources, isEmpty);
      await engine.dispose();
    });

    test('reports the model fetch as the whole progress, or as its first '
        'half and then 1 once a projector loads', () async {
      final backend = _Backend(urlLoadingSupported: true);
      final engine = LlamaEngine(backend);
      final alone = <Object?>[];
      final withProjector = <Object?>[];

      await engine.setModel(
        LlamaModel(otherModel),
        onProgress: (progress) => alone.add(progress.fraction),
      );
      backend.onProjectorLoad = () => withProjector.add('projector');
      await engine.setModel(
        LlamaModel(otherModel, projector: remoteProjector),
        onProgress: (progress) => withProjector.add(progress.fraction),
      );

      expect(alone, [0.25]);
      expect(withProjector, [0.125, 'projector', 1.0]);
      await engine.dispose();
    });

    test('does not report full progress when the projector fails to '
        'load', () async {
      final backend = _Backend(urlLoadingSupported: true)
        ..projectorError = Exception('bad projector');
      final engine = LlamaEngine(backend);
      final progress = <double?>[];

      await expectLater(
        engine.setModel(
          LlamaModel(otherModel, projector: remoteProjector),
          onProgress: (event) => progress.add(event.fraction),
        ),
        throwsA(isA<LlamaModelException>()),
      );

      expect(progress, [0.125]);
      expect(engine.isReady, isFalse);
      await engine.dispose();
    });

    test('unloads the model and projector when onProgress throws at full '
        'progress', () async {
      final backend = _Backend(urlLoadingSupported: true);
      final engine = LlamaEngine(backend);
      final progress = <double?>[];

      await expectLater(
        engine.setModel(
          LlamaModel(otherModel, projector: remoteProjector),
          onProgress: (event) {
            progress.add(event.fraction);
            if (event.fraction == 1) throw StateError('callback failed');
          },
        ),
        throwsA(isA<StateError>()),
      );

      expect(progress, [0.125, 1.0]);
      expect(engine.isReady, isFalse);
      expect(engine.hasMultimodalProjector, isFalse);
      expect(backend.events, contains('modelFree'));
      await engine.dispose();
    });

    test('dispose while the loaded model is read for observers reports no '
        'full progress', () async {
      final backend = _Backend(urlLoadingSupported: true)
        ..metadataGate = Completer<void>();
      final engine = LlamaEngine(backend, observers: [_LoadObserver()]);
      final progress = <double?>[];

      final outcome = expectLater(
        engine.setModel(
          LlamaModel(otherModel, projector: remoteProjector),
          onProgress: (event) => progress.add(event.fraction),
        ),
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            contains('disposed while loading'),
          ),
        ),
      );
      await backend.metadataStarted.future;
      final dispose = engine.dispose();
      backend.metadataGate!.complete();
      await outcome;
      await dispose;

      expect(progress, [0.125]);
      expect(engine.isReady, isFalse);
    });

    test('rejects a download option the runtime fetch cannot apply before it '
        'resolves anything, keeping the loaded model', () async {
      final backend = _Backend(urlLoadingSupported: true);
      final resolver = _CountingResolver();
      final engine = LlamaEngine(backend, modelResolver: resolver);
      await engine.setModel(LlamaModel(otherModel));
      resolver.calls = 0;
      backend.events.clear();

      for (final download in [
        ModelLoadOptions(bearerToken: 'secret-token'),
        ModelLoadOptions(cancelToken: ModelDownloadCancelToken()),
        ModelLoadOptions(cachePolicy: ModelCachePolicy.refresh),
      ]) {
        await expectLater(
          engine.setModel(LlamaModel(remoteModel), download: download),
          throwsA(isA<LlamaUnsupportedException>()),
        );
      }

      expect(resolver.calls, 0);
      expect(backend.events, isEmpty);
      expect(engine.isReady, isTrue);
      await engine.dispose();
    });

    test('routes a URL with an explicit format by that format', () async {
      final backend = _RoutingBackend(urlLoadingSupported: true);
      final engine = LlamaEngine(backend);

      await engine.setModel(
        LlamaModel(
          ModelSource.parse(
            'https://example.com/download?id=7',
            format: ModelFormat.liteRtLm,
          ),
        ),
      );

      expect(backend.events, [
        'modelLoadFromUrlAs liteRtLm https://example.com/download?id=7',
      ]);
      await engine.dispose();
    });

    test('a fetch that fails leaves nothing loaded', () async {
      final backend = _Backend(urlLoadingSupported: true);
      final engine = LlamaEngine(backend);
      await engine.setModel(LlamaModel(otherModel));
      backend.modelLoadError = Exception('404');

      await expectLater(
        engine.setModel(LlamaModel(remoteModel)),
        throwsA(isA<LlamaModelException>()),
      );

      expect(engine.isReady, isFalse);
      await engine.dispose();
    });
  });

  group('LlamaEngine.load', () {
    test('returns a loaded engine that uses the store and observers', () async {
      final backend = _Backend();
      final manager = _Manager(cacheFiles());
      final resolver = _CountingResolver();
      final observer = _LoadObserver();

      final engine = await LlamaEngine.load(
        LlamaModel(remoteModel, projector: remoteProjector),
        params: const ModelParams(contextSize: 512),
        store: ModelFileStore(resolver: resolver, downloadManager: manager),
        backend: backend,
        observers: [observer],
      );

      expect(engine.isReady, isTrue);
      expect(engine.backend, same(backend));
      expect(engine.modelResolver, same(resolver));
      expect(engine.modelDownloadManager, same(manager));
      expect(engine.observers, [observer]);
      expect(backend.contextParams.single.contextSize, 512);
      expect(backend.events, [
        'modelLoad /cache/model.gguf',
        'projector /cache/mmproj.gguf',
      ]);
      await engine.dispose();
      expect(backend.disposeCalls, 1);
    });

    test('a failed load disposes the engine and its backend', () async {
      final backend = _Backend()..projectorError = Exception('bad projector');

      await expectLater(
        LlamaEngine.load(
          LlamaModel(remoteModel, projector: remoteProjector),
          store: ModelFileStore(downloadManager: _Manager(cacheFiles())),
          backend: backend,
        ),
        throwsA(isA<LlamaModelException>()),
      );

      expect(backend.modelFreeCalls, 1);
      expect(backend.disposeCalls, 1);
    });

    test(
      'a load rejected before any file access disposes the backend',
      () async {
        final backend = _Backend();
        final manager = _Manager(cacheFiles());

        await expectLater(
          LlamaEngine.load(
            LlamaModel(remoteModel),
            params: const ModelParams(device: ComputeDevice.npu),
            store: ModelFileStore(downloadManager: manager),
            backend: backend,
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );

        expect(manager.sources, isEmpty);
        expect(backend.events, isEmpty);
        expect(backend.disposeCalls, 1);
      },
    );
  });

  group('deprecated loaders', () {
    for (final blocked in [remoteModel, adapter]) {
      final label = blocked == remoteModel ? 'model' : 'adapter';
      for (final failsLate in [false, true]) {
        test('dispose cancels a legacy $label download without cancelling '
            'caller tokens, even when it ${failsLate ? 'fails' : 'returns'} '
            'late', () async {
          final backend = _Backend();
          final manager = _Manager(
            cacheFiles(),
            gated: {blocked},
            failing: failsLate ? {blocked} : {},
            ignoresCancel: true,
          );
          final engine = LlamaEngine(backend, modelDownloadManager: manager);
          final callerToken = ModelDownloadCancelToken();
          final adapterToken = ModelDownloadCancelToken();
          final loading = engine.loadModelSource(
            remoteModel,
            options: ModelLoadOptions(cancelToken: callerToken),
            modelParams: ModelParams(
              loras: [
                LoraAdapterConfig.source(
                  adapter,
                  download: ModelLoadOptions(cancelToken: adapterToken),
                ),
              ],
            ),
          );
          final outcome = expectLater(
            loading,
            throwsA(isA<LlamaStateException>()),
          );
          try {
            await manager.started(blocked);
            final token = manager.options.last.cancelToken!;
            expect(token.isCancelled, isFalse);

            await engine.dispose();

            expect(token.isCancelled, isTrue);
            expect(callerToken.isCancelled, isFalse);
            expect(adapterToken.isCancelled, isFalse);
            await outcome.timeout(const Duration(seconds: 5));
            expect(backend.events, isEmpty);
            expect(backend.disposeCalls, 1);
          } finally {
            manager.release(blocked);
            await outcome;
            await engine.dispose();
          }
          await pumpEventQueue();
          expect(backend.events, isEmpty);
          expect(engine.isReady, isFalse);
          if (blocked == remoteModel) {
            expect(manager.sources, [remoteModel.cacheKey]);
          }
        });
      }

      test('dispose stops a cooperative legacy $label download', () async {
        final backend = _Backend();
        final manager = _Manager(cacheFiles(), polling: {blocked});
        final engine = LlamaEngine(backend, modelDownloadManager: manager);
        final callerToken = ModelDownloadCancelToken();
        final loading = engine.loadModelSource(
          remoteModel,
          options: ModelLoadOptions(cancelToken: callerToken),
          modelParams: ModelParams(loras: [LoraAdapterConfig.source(adapter)]),
        );
        final outcome = expectLater(
          loading,
          throwsA(isA<LlamaStateException>()),
        );
        try {
          await manager.started(blocked);
          final token = manager.options.last.cancelToken!;
          await engine.dispose();

          expect(token.isCancelled, isTrue);
          expect(callerToken.isCancelled, isFalse);
          await outcome.timeout(const Duration(seconds: 5));
          expect(backend.events, isEmpty);
          expect(engine.isReady, isFalse);
        } finally {
          callerToken.cancel();
          await outcome;
          await engine.dispose();
        }
      });

      test(
        'caller cancellation still stops a legacy $label download',
        () async {
          final backend = _Backend();
          final manager = _Manager(cacheFiles(), polling: {blocked});
          final engine = LlamaEngine(backend, modelDownloadManager: manager);
          final token = ModelDownloadCancelToken();
          final loading = engine.loadModelSource(
            remoteModel,
            options: ModelLoadOptions(cancelToken: token),
            modelParams: ModelParams(
              loras: [LoraAdapterConfig.source(adapter)],
            ),
          );
          final outcome = expectLater(
            loading,
            throwsA(isA<LlamaStateException>()),
          );
          await manager.started(blocked);
          token.cancel();
          await outcome;

          expect(backend.events, isEmpty);
          expect(engine.isDisposed, isFalse);
          await engine.dispose();
        },
      );
    }

    test(
      'dispose abandons every legacy resolution alongside setModel',
      () async {
        final backend = _Backend();
        final sources = [remoteModel, otherModel, adapter];
        final manager = _Manager(
          cacheFiles(),
          gated: sources.toSet(),
          ignoresCancel: true,
        );
        final engine = LlamaEngine(backend, modelDownloadManager: manager);
        final outcomes = [
          for (final source in sources.take(2))
            expectLater(
              engine.loadModelSource(source),
              throwsA(isA<LlamaStateException>()),
            ),
          expectLater(
            engine.setModel(LlamaModel(adapter)),
            throwsA(isA<LlamaStateException>()),
          ),
        ];
        try {
          await Future.wait(sources.map(manager.started));
          await engine.dispose();

          expect(
            manager.options.map((options) => options.cancelToken?.isCancelled),
            everyElement(isTrue),
          );
          await Future.wait(outcomes).timeout(const Duration(seconds: 5));
          expect(backend.disposeCalls, 1);
        } finally {
          for (final source in sources) {
            manager.release(source);
          }
          await Future.wait(outcomes);
          await engine.dispose();
        }
        await pumpEventQueue();
        expect(backend.events, isEmpty);
        expect(engine.isReady, isFalse);
      },
    );

    for (final failsLate in [false, true]) {
      test(
        'dispose abandons a legacy resolver that '
        '${failsLate ? 'fails' : 'returns'} late before any download',
        () async {
          final backend = _Backend();
          final manager = _Manager(cacheFiles());
          final resolver = _GatedResolver(failsLate: failsLate);
          final engine = LlamaEngine(
            backend,
            modelResolver: resolver,
            modelDownloadManager: manager,
          );
          final callerToken = ModelDownloadCancelToken();
          final outcome = expectLater(
            engine.loadModelSource(
              remoteModel,
              options: ModelLoadOptions(cancelToken: callerToken),
            ),
            throwsA(isA<LlamaStateException>()),
          );
          try {
            await resolver.started.future;
            await engine.dispose();

            expect(resolver.token!.isCancelled, isTrue);
            expect(callerToken.isCancelled, isFalse);
            await outcome.timeout(const Duration(seconds: 5));
          } finally {
            resolver.release.complete();
            await outcome;
            await engine.dispose();
          }
          await pumpEventQueue();
          expect(manager.sources, isEmpty);
          expect(backend.events, isEmpty);
        },
      );
    }

    test('a legacy resolver that disposes synchronously rejects the load '
        'without waiting for its result', () async {
      final backend = _Backend();
      final manager = _Manager(cacheFiles());
      final resolver = _GatedResolver(failsLate: false);
      late final LlamaEngine engine;
      resolver.onResolve = () => unawaited(engine.dispose());
      engine = LlamaEngine(
        backend,
        modelResolver: resolver,
        modelDownloadManager: manager,
      );
      final outcome = expectLater(
        engine.loadModelSource(remoteModel),
        throwsA(isA<LlamaStateException>()),
      );
      try {
        await resolver.started.future;
        await outcome.timeout(const Duration(seconds: 5));
      } finally {
        resolver.release.complete();
        await outcome;
        await engine.dispose();
      }
      await pumpEventQueue();
      expect(manager.sources, isEmpty);
      expect(backend.events, isEmpty);
    });

    test('loadModelSource throws for a loaded engine before it resolves or '
        'downloads', () async {
      final manager = _Manager(cacheFiles());
      final resolver = _CountingResolver();
      final engine = LlamaEngine(
        _Backend(),
        modelResolver: resolver,
        modelDownloadManager: manager,
      );
      await engine.setModel(LlamaModel(localModel));
      manager.sources.clear();
      resolver.calls = 0;

      await expectLater(
        engine.loadModelSource(remoteModel),
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            contains('already loaded'),
          ),
        ),
      );

      expect(resolver.calls, 0);
      expect(manager.sources, isEmpty);
      await engine.dispose();
    });
  });

  group('fixed-runtime projector preflight', () {
    for (final urlLoading in [false, true]) {
      for (final name in ['model.gguf', 'download?id=7']) {
        for (final replacing in [false, true]) {
          test('$name, URL loading $urlLoading, replacement $replacing '
              'refuses before I/O and keeps the previous model', () async {
            final backend = _FixedRuntimeBackend(
              LlamaRuntime.liteRtLm,
              urlLoadingSupported: urlLoading,
            );
            final source = ModelSource.parse('https://example.com/$name');
            final manager = _Manager({
              source: '/cache/new-model',
              remoteProjector: '/cache/mmproj.gguf',
            });
            final resolver = _CountingResolver();
            final engine = LlamaEngine(
              backend,
              modelResolver: resolver,
              modelDownloadManager: manager,
            );
            addTearDown(engine.dispose);
            if (replacing) await engine.setModel(LlamaModel(localModel));
            final loads = backend.modelLoadCalls;
            final urlLoads = backend.modelLoadFromUrlCalls;
            final previousPath = backend.lastModelPath;
            resolver.calls = 0;
            manager.sources.clear();
            backend.events.clear();
            final model = LlamaModel(source, projector: remoteProjector);

            final report = await engine.checkLoad(model);
            expect(resolver.calls, 0);
            LlamaUnsupportedException? refusal;
            await expectLater(
              engine.setModel(model),
              throwsA(
                isA<LlamaUnsupportedException>().having(
                  (error) {
                    refusal = error;
                    return error.message;
                  },
                  'message',
                  contains('takes no multimodal projector'),
                ),
              ),
            );

            expect(resolver.calls, 0);
            expect(manager.sources, isEmpty);
            expect(backend.events, isEmpty);
            expect(backend.modelLoadCalls, loads);
            expect(backend.modelLoadFromUrlCalls, urlLoads);
            expect(backend.modelFreeCalls, 0);
            expect(backend.contextFreeCalls, 0);
            expect(backend.multimodalContextCreateCalls, 0);
            expect(backend.lastModelPath, previousPath);
            expect(engine.isReady, replacing);
            expect(report.status, LlamaLoadCheckStatus.unsupported);
            expect(refusal!.message, report.error!.message);
            if (replacing) {
              expect(
                await engine.create([
                  const LlamaChatMessage.fromText(
                    role: LlamaChatRole.user,
                    text: 'hi',
                  ),
                ]).text(),
                'response',
              );
            }
          });
        }
      }

      for (final identity in [LlamaRuntime.llamaCpp, null]) {
        test(
          '$identity, URL loading $urlLoading, still loads a projector',
          () async {
            final backend = _FixedRuntimeBackend(
              identity,
              urlLoadingSupported: urlLoading,
            );
            final engine = LlamaEngine(
              backend,
              modelDownloadManager: _Manager(cacheFiles()),
            );
            addTearDown(engine.dispose);
            await engine.setModel(
              LlamaModel(remoteModel, projector: remoteProjector),
            );
            expect(engine.isReady, isTrue);
            expect(engine.hasMultimodalProjector, isTrue);
            expect(backend.multimodalContextCreateCalls, 1);
          },
        );
      }

      test('a router previously running LiteRT-LM still loads a GGUF projector '
          'with URL loading $urlLoading', () async {
        final backend = _RoutingBackend(urlLoadingSupported: urlLoading);
        final engine = LlamaEngine(
          backend,
          modelDownloadManager: _Manager(cacheFiles()),
        );
        addTearDown(engine.dispose);
        await engine.setModel(
          LlamaModel(
            ModelSource.parse(
              '/models/previous.litertlm',
              format: ModelFormat.liteRtLm,
            ),
          ),
        );
        expect(engine.runtime, LlamaRuntime.liteRtLm);
        final model = LlamaModel(
          ModelSource.parse(
            'hf://owner/repo/model.gguf',
            format: ModelFormat.gguf,
          ),
          projector: remoteProjector,
        );
        expect(
          (await engine.checkLoad(model)).status,
          isNot(LlamaLoadCheckStatus.unsupported),
        );
        await engine.setModel(model);
        expect(engine.runtime, LlamaRuntime.llamaCpp);
        expect(engine.hasMultimodalProjector, isTrue);
      });

      test(
        'fixed LiteRT-LM keeps filename mismatch behavior without a projector '
        'with URL loading $urlLoading',
        () async {
          final backend = _FixedRuntimeBackend(
            LlamaRuntime.liteRtLm,
            urlLoadingSupported: urlLoading,
          );
          final engine = LlamaEngine(
            backend,
            modelDownloadManager: _Manager(cacheFiles()),
          );
          addTearDown(engine.dispose);
          final model = LlamaModel(remoteModel);
          expect(
            (await engine.checkLoad(model)).status,
            LlamaLoadCheckStatus.unknown,
          );
          await engine.setModel(model);
          expect(engine.isReady, isTrue);
          expect(backend.modelLoadCalls + backend.modelLoadFromUrlCalls, 1);
        },
      );
    }

    test('all projector entry points use the same LiteRT-LM refusal', () async {
      final backend = _FixedRuntimeBackend(LlamaRuntime.liteRtLm);
      final resolver = _CountingResolver();
      final engine = LlamaEngine(
        backend,
        modelResolver: resolver,
        modelDownloadManager: _Manager(cacheFiles()),
      );
      addTearDown(engine.dispose);
      await engine.setModel(LlamaModel(localModel));
      resolver.calls = 0;
      final model = LlamaModel(
        ModelSource.parse('/models/new.litertlm'),
        projector: remoteProjector,
      );
      final reason = (await engine.checkLoad(model)).error!.message;
      for (final operation in <Future<void> Function()>[
        () => engine.setModel(model),
        () => engine.loadMultimodalProjectorSource(remoteProjector),
        // ignore: deprecated_member_use_from_same_package
        () => engine.loadMultimodalProjector('/models/mmproj.gguf'),
      ]) {
        await expectLater(
          operation(),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              reason,
            ),
          ),
        );
      }
      expect(resolver.calls, 0);
      expect(backend.multimodalContextCreateCalls, 0);
      expect(engine.isReady, isTrue);
    });
  });

  group('loadMultimodalProjectorSource', () {
    test(
      'takes download, or the deprecated options, and rejects both',
      () async {
        final manager = _Manager(cacheFiles());
        final engine = LlamaEngine(_Backend(), modelDownloadManager: manager);
        await engine.setModel(LlamaModel(localModel));
        manager.options.clear();

        await engine.loadMultimodalProjectorSource(
          remoteProjector,
          download: ModelLoadOptions(cacheDirectory: '/new'),
        );
        await engine.loadMultimodalProjectorSource(
          remoteProjector,
          options: ModelLoadOptions(cacheDirectory: '/old'),
        );
        await engine.loadMultimodalProjectorSource(remoteProjector);

        expect(
          [for (final options in manager.options) options.cacheDirectory],
          ['/new', '/old', null],
        );
        manager.options.clear();
        expect(
          () => engine.loadMultimodalProjectorSource(
            remoteProjector,
            download: ModelLoadOptions.defaults,
            options: ModelLoadOptions.defaults,
          ),
          throwsA(
            isA<LlamaArgumentException>().having(
              (error) => error.name,
              'name',
              'options',
            ),
          ),
        );
        expect(manager.options, isEmpty);
        await engine.dispose();
      },
    );

    test('unloadModel stops its download, and the load throws '
        'LlamaStateException', () async {
      final backend = _Backend();
      final manager = _Manager(cacheFiles(), polling: {remoteProjector});
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      await engine.setModel(LlamaModel(localModel));

      final loading = engine.loadMultimodalProjectorSource(remoteProjector);
      final outcome = expectLater(
        loading,
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            contains('model was unloaded while its multimodal projector'),
          ),
        ),
      );
      await manager.started(remoteProjector);
      await engine.unloadModel();
      await outcome;

      expect(backend.multimodalContextCreateCalls, 0);
      expect(engine.isReady, isFalse);
      await engine.dispose();
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('dispose stops its download, and the load throws '
        'LlamaStateException', () async {
      final backend = _Backend();
      final manager = _Manager(cacheFiles(), polling: {remoteProjector});
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      await engine.setModel(LlamaModel(localModel));

      final loading = engine.loadMultimodalProjectorSource(remoteProjector);
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
      await manager.started(remoteProjector);
      await engine.dispose();
      await outcome;

      expect(backend.multimodalContextCreateCalls, 0);
      expect(backend.disposeCalls, 1);
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('a download that ends after the model is unloaded loads no '
        'projector and throws LlamaStateException', () async {
      final backend = _Backend();
      final manager = _Manager(
        cacheFiles(),
        gated: {remoteProjector},
        ignoresCancel: true,
      );
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      await engine.setModel(LlamaModel(localModel));

      final loading = engine.loadMultimodalProjectorSource(remoteProjector);
      final outcome = expectLater(
        loading,
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            contains('model was unloaded while its multimodal projector'),
          ),
        ),
      );
      await manager.started(remoteProjector);
      final unload = engine.unloadModel();
      manager.release(remoteProjector);
      await outcome;
      await unload;

      expect(backend.multimodalContextCreateCalls, 0);
      await engine.dispose();
    });

    test('loads a local projector its download manager cannot describe as a '
        'cache entry', () async {
      final backend = _Backend();
      final engine = LlamaEngine(
        backend,
        modelDownloadManager: _Manager(
          const {},
          uncacheable: {'/models/mm%2Fproj.gguf'},
        ),
      );
      await engine.setModel(LlamaModel(localModel));

      await engine.loadMultimodalProjectorSource(
        ModelSource.path('/models/mm%2Fproj.gguf'),
      );

      expect(backend.events.last, 'projector /abs/models/mm%2Fproj.gguf');
      await engine.dispose();
    });

    test("the caller's cancel token still stops the download", () async {
      final manager = _Manager(cacheFiles(), polling: {remoteProjector});
      final engine = LlamaEngine(_Backend(), modelDownloadManager: manager);
      await engine.setModel(LlamaModel(localModel));
      final token = ModelDownloadCancelToken();

      final loading = engine.loadMultimodalProjectorSource(
        remoteProjector,
        download: ModelLoadOptions(cancelToken: token),
      );
      final outcome = expectLater(
        loading,
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            'Model download was cancelled.',
          ),
        ),
      );
      await manager.started(remoteProjector);
      token.cancel();
      await outcome;

      expect(engine.isReady, isTrue);
      await engine.dispose();
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('a URL-loading backend loads a local path as written', () async {
      final backend = _Backend(urlLoadingSupported: true);
      final engine = LlamaEngine(backend);
      await engine.setModel(LlamaModel(otherModel));

      await engine.loadMultimodalProjectorSource(
        ModelSource.path('models/mmproj.gguf'),
      );

      expect(backend.events.last, 'projector models/mmproj.gguf');
      await engine.dispose();
    });
  });

  test('before a load, requests name LlamaEngine.load and setModel', () async {
    final engine = LlamaEngine(_Backend());

    expect(
      (await engine.capabilities).unsupportedReason,
      'No model is loaded. Call LlamaEngine.load or setModel first.',
    );
    await expectLater(
      engine.tokenize('hi'),
      throwsA(
        isA<LlamaContextException>().having(
          (error) => error.message,
          'message',
          'Engine not ready: no model is loaded. Call LlamaEngine.load or '
              'setModel first.',
        ),
      ),
    );
    await engine.dispose();
  });
}

/// Records what reaches the backend, in order.
class _Backend extends MockLlamaBackend {
  _Backend({super.urlLoadingSupported});

  final List<String> events = <String>[];
  final List<ModelParams> contextParams = <ModelParams>[];
  final List<String> removedLoraPaths = <String>[];
  final Completer<void> modelLoadStarted = Completer<void>();
  final Completer<void> metadataStarted = Completer<void>();
  Completer<void>? metadataGate;
  Object? projectorError;
  void Function()? onProjectorLoad;

  @override
  Future<int> modelLoad(String path, ModelParams params) {
    events.add('modelLoad $path');
    if (!modelLoadStarted.isCompleted) modelLoadStarted.complete();
    return super.modelLoad(path, params);
  }

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    void Function(double progress)? onProgress,
  }) {
    events.add('modelLoadFromUrl $url');
    final loadError = modelLoadError;
    if (loadError != null) throw loadError;
    return super.modelLoadFromUrl(url, params, onProgress: onProgress);
  }

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) {
    contextParams.add(params);
    return super.contextCreate(modelHandle, params);
  }

  @override
  Future<void> contextFree(int contextHandle) {
    events.add('contextFree');
    return super.contextFree(contextHandle);
  }

  @override
  Future<void> modelFree(int modelHandle) {
    events.add('modelFree');
    return super.modelFree(modelHandle);
  }

  @override
  Future<int?> multimodalContextCreate(int modelHandle, String mmProjPath) {
    events.add('projector $mmProjPath');
    onProjectorLoad?.call();
    final error = projectorError;
    if (error != null) throw error;
    return super.multimodalContextCreate(modelHandle, mmProjPath);
  }

  @override
  Future<void> removeLoraAdapter(int contextHandle, String path) {
    removedLoraPaths.add(path);
    return super.removeLoraAdapter(contextHandle, path);
  }

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async {
    if (!metadataStarted.isCompleted) metadataStarted.complete();
    await metadataGate?.future;
    return super.modelMetadata(modelHandle);
  }
}

/// Reports a fixed runtime without routing by the model's format.
class _FixedRuntimeBackend extends _Backend implements BackendRuntimeIdentity {
  _FixedRuntimeBackend(this.runtime, {super.urlLoadingSupported});

  @override
  final LlamaRuntime? runtime;
}

/// Chooses the runtime from an explicit format, as `LlamaBackend()` does.
class _RoutingBackend extends _Backend
    implements BackendModelFormatRouting, BackendRuntimeIdentity {
  _RoutingBackend({super.urlLoadingSupported});

  @override
  LlamaRuntime? runtime;

  @override
  Future<int> modelLoadAs(String path, ModelParams params, ModelFormat format) {
    events.add('modelLoadAs ${format.name} $path');
    runtime = format.runtime;
    return super.modelLoad(path, params).whenComplete(events.removeLast);
  }

  @override
  Future<int> modelLoadFromUrlAs(
    String url,
    ModelParams params,
    ModelFormat format, {
    void Function(double progress)? onProgress,
  }) {
    events.add('modelLoadFromUrlAs ${format.name} $url');
    runtime = format.runtime;
    return super
        .modelLoadFromUrl(url, params, onProgress: onProgress)
        .whenComplete(events.removeLast);
  }
}

/// Resolves a remote source to its mapped cache file and a local one to its
/// own path.
///
/// A [gated] source waits for [release], ignoring cancellation; a [polling]
/// one waits for its cancel token, like the package download manager; a
/// [failing] one throws; and an [uncacheable] local path throws what the
/// package download manager throws for a name no cache entry can hold. With
/// [ignoresCancel] a download completes although its token is cancelled.
class _ParamsCheckBackend extends _Backend implements BackendLoadCheck {
  final List<ModelFormat?> checkedFormats = <ModelFormat?>[];

  @override
  String? checkLoad(ModelParams params, ModelFormat? format) {
    checkedFormats.add(format);
    if (params.liteRtLmCacheDir != null) {
      throw LlamaUnsupportedException('liteRtLmCacheDir');
    }
    return null;
  }
}

class _Manager implements ModelDownloadManager {
  _Manager(
    Map<ModelSource, String> files, {
    Set<ModelSource> gated = const {},
    Set<ModelSource> polling = const {},
    Set<ModelSource> failing = const {},
    this.uncacheable = const {},
    this.ignoresCancel = false,
  }) : _files = {
         for (final MapEntry(:key, :value) in files.entries)
           key.cacheKey: value,
       },
       _gates = {
         for (final source in gated) source.cacheKey: Completer<void>(),
       },
       _polling = {for (final source in polling) source.cacheKey},
       _failing = {for (final source in failing) source.cacheKey};

  final Map<String, String> _files;
  final Map<String, Completer<void>> _gates;
  final Map<String, Completer<void>> _started = <String, Completer<void>>{};
  final Set<String> _polling;
  final Set<String> _failing;
  final Set<String> uncacheable;
  final bool ignoresCancel;
  void Function()? onResolved;
  final List<String> sources = <String>[];
  final List<ModelLoadOptions> options = <ModelLoadOptions>[];

  Future<void> started(ModelSource source) =>
      _started.putIfAbsent(source.cacheKey, Completer<void>.new).future;

  void release(ModelSource source) => _gates[source.cacheKey]!.complete();

  @override
  Future<ModelCacheEntry> ensureModel(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    sources.add(source.cacheKey);
    this.options.add(options);
    final started = _started.putIfAbsent(source.cacheKey, Completer<void>.new);
    if (!started.isCompleted) started.complete();
    await _gates[source.cacheKey]?.future;
    if (_polling.contains(source.cacheKey)) {
      while (!(options.cancelToken?.isCancelled ?? false)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }
    if (!ignoresCancel && (options.cancelToken?.isCancelled ?? false)) {
      throw LlamaStateException('Model download was cancelled.');
    }
    if (_failing.contains(source.cacheKey)) {
      throw LlamaModelException('Download failed.');
    }
    final path = source.path;
    if (path != null && uncacheable.contains(path)) {
      throw UncacheableLocalModelFileException(
        'A ModelCacheEntry cannot hold $path.',
        filePath: '/abs$path',
        bytes: 100,
      );
    }
    onProgress?.call(
      const ModelDownloadProgress(receivedBytes: 50, totalBytes: 100),
    );
    onResolved?.call();
    return ModelCacheEntry(
      sourceCanonicalKey: source.metadataSourceKey,
      cacheKey: source.cacheKey,
      fileName: source.fileName,
      filePath: path ?? _files[source.cacheKey]!,
      bytes: 100,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GatedResolver implements ModelResolver {
  _GatedResolver({required this.failsLate});

  final bool failsLate;
  void Function()? onResolve;
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();
  ModelDownloadCancelToken? token;

  @override
  Future<ModelLoadTarget> resolve(
    ModelSource source,
    ModelResolveRequest request,
  ) async {
    token = request.options.cancelToken;
    onResolve?.call();
    started.complete();
    await release.future;
    if (failsLate) throw LlamaModelException('Resolver failed late.');
    return const DefaultModelResolver().resolve(source, request);
  }
}

class _CountingResolver implements ModelResolver {
  int calls = 0;

  @override
  Future<ModelLoadTarget> resolve(
    ModelSource source,
    ModelResolveRequest request,
  ) {
    calls++;
    return const DefaultModelResolver().resolve(source, request);
  }
}

final class _LoadObserver extends LlamaEngineObserver {
  final List<LlamaModelLoadOperation> started = <LlamaModelLoadOperation>[];
  final List<Object?> ended = <Object?>[];

  @override
  LlamaOperationObserver? onStart(LlamaOperation operation) {
    if (operation is! LlamaModelLoadOperation) return null;
    started.add(operation);
    return _LoadEndObserver(ended);
  }
}

final class _LoadEndObserver extends LlamaOperationObserver {
  _LoadEndObserver(this.ended);

  final List<Object?> ended;

  @override
  void onEnd(LlamaOperationResult result) => ended.add(result.error);
}
