import 'dart:async';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/backend.dart'
    show BackendModelFormatDetection;
import 'package:test/test.dart';

import 'engine_test.dart'
    show MockLlamaBackend, NativeChatMockBackend, PerformanceCounterBackend;

void main() {
  final hfAdapter = ModelSource.parse('hf://owner/repo/adapters/style.gguf');
  final urlAdapter = ModelSource.url(
    Uri.parse('https://example.com/adapters/tone.gguf'),
  );
  final localAdapter = ModelSource.path('/models/local-adapter.gguf');
  final hfDraft = ModelSource.parse('hf://owner/repo/draft.gguf');

  group('LoRA sources', () {
    test('setLoraSource downloads a Hugging Face adapter with the options '
        'and progress, and removeLoraSource removes the cached file', () async {
      final backend = _RecordingBackend();
      final manager = _CacheManager({hfAdapter: '/cache/style.gguf'});
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      await engine.loadModel('/models/model.gguf');
      final options = ModelLoadOptions(bearerToken: 'secret-token');
      final progress = <ModelDownloadProgress>[];

      await engine.setLoraSource(
        hfAdapter,
        scale: 0.5,
        download: options,
        onProgress: progress.add,
      );

      expect(manager.calls.single.source.cacheKey, hfAdapter.cacheKey);
      expect(
        manager.calls.single.source.resolvedUri.toString(),
        'https://huggingface.co/owner/repo/resolve/main/adapters/style.gguf?download=true',
      );
      expect(manager.calls.single.options.bearerToken, 'secret-token');
      expect(progress.single.fraction, 0.5);
      expect(backend.lastLoraPath, '/cache/style.gguf');
      expect(backend.lastLoraScale, 0.5);

      await engine.removeLoraSource(hfAdapter);
      expect(backend.removedLoraPaths, ['/cache/style.gguf']);
    });

    test('setLoraSource checks a local adapter and loads its path', () async {
      final backend = _RecordingBackend();
      final manager = _CacheManager({});
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      await engine.loadModel('/models/model.gguf');

      await engine.setLoraSource(localAdapter);
      await engine.removeLoraSource(localAdapter);

      expect(manager.calls.single.source.path, '/models/local-adapter.gguf');
      expect(backend.lastLoraScale, 1.0);
      expect(backend.removedLoraPaths, ['/models/local-adapter.gguf']);
    });

    test('removeLoraSource ignores a remote adapter that was never set, and '
        'clearLoras forgets the cached files', () async {
      final backend = _RecordingBackend();
      final manager = _CacheManager({urlAdapter: '/cache/tone.gguf'});
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      await engine.loadModel('/models/model.gguf');

      await engine.removeLoraSource(urlAdapter);
      await engine.setLoraSource(urlAdapter);
      await engine.clearLoras();
      await engine.removeLoraSource(urlAdapter);

      expect(backend.removedLoraPaths, isEmpty);
    });

    test('setLoraSource needs a loaded model before it downloads', () async {
      final manager = _CacheManager({hfAdapter: '/cache/style.gguf'});
      final engine = LlamaEngine(
        _RecordingBackend(),
        modelDownloadManager: manager,
      );

      await expectLater(
        engine.setLoraSource(hfAdapter),
        throwsA(isA<LlamaContextException>()),
      );
      expect(manager.calls, isEmpty);
    });

    test('LiteRT-LM rejects setLoraSource before it downloads', () async {
      final manager = _CacheManager({hfAdapter: '/cache/style.gguf'});
      final engine = LlamaEngine(
        _RuntimeBackend(LlamaRuntime.liteRtLm),
        modelDownloadManager: manager,
      );
      await engine.loadModel('/models/model.litertlm');

      await expectLater(
        engine.setLoraSource(hfAdapter),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('LiteRT-LM has no runtime LoRA adapter API'),
          ),
        ),
      );
      expect(manager.calls, isEmpty);
    });

    test('LiteRT-LM rejects loadMultimodalProjectorSource before it '
        'downloads', () async {
      final manager = _CacheManager({hfAdapter: '/cache/mmproj.gguf'});
      final engine = LlamaEngine(
        _RuntimeBackend(LlamaRuntime.liteRtLm),
        modelDownloadManager: manager,
      );
      await engine.loadModel('/models/model.litertlm');

      await expectLater(
        engine.loadMultimodalProjectorSource(hfAdapter),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('A LiteRT-LM model takes no multimodal projector'),
          ),
        ),
      );
      expect(manager.calls, isEmpty);
    });

    test('LiteRT-LM rejects the deprecated loadMultimodalProjector on a '
        'backend that implements BackendMultimodalSupport', () async {
      final backend = _RuntimeBackend(LlamaRuntime.liteRtLm);
      final engine = LlamaEngine(backend);
      await engine.loadModel('/models/model.litertlm');

      await expectLater(
        // ignore: deprecated_member_use_from_same_package
        engine.loadMultimodalProjector('/cache/mmproj.gguf'),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('A LiteRT-LM model takes no multimodal projector'),
          ),
        ),
      );
      expect(backend.multimodalContextCreateCalls, 0);
    });

    test('removeLoraSource does nothing on a backend without a LoRA API when '
        'no adapter from the source is applied', () async {
      final engine = LlamaEngine(
        _NoLoraBackend(),
        modelDownloadManager: _CacheManager({}),
      );
      await engine.loadModel('/models/model.litertlm');

      await engine.removeLoraSource(localAdapter);
      await engine.removeLoraSource(urlAdapter);
    });

    test('removeLoraSource reports a backend without a LoRA API that applied '
        'a path adapter at load', () async {
      final engine = LlamaEngine(
        _NoLoraBackend(),
        modelDownloadManager: _CacheManager({}),
      );
      await engine.loadModel(
        '/models/model.litertlm',
        modelParams: const ModelParams(
          loras: [LoraAdapterConfig(path: '/models/local-adapter.gguf')],
        ),
      );

      await expectLater(
        engine.removeLoraSource(localAdapter),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });

    test('removeLoraSource reports a load-time path adapter given as an alias '
        'on a backend without a LoRA API', () async {
      final engine = LlamaEngine(
        _NoLoraBackend(),
        modelDownloadManager: _CacheManager({}),
      );
      await engine.loadModel(
        '/models/model.litertlm',
        modelParams: const ModelParams(
          loras: [LoraAdapterConfig(path: '/models/a.gguf')],
        ),
      );

      await expectLater(
        engine.removeLoraSource(ModelSource.path('/models/./a.gguf')),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });

    group('path aliases', () {
      const aliases = [
        '/models/./a.gguf',
        '/models//a.gguf',
        '/models/sub/../a.gguf',
        '/models/a.gguf/',
      ];

      for (final alias in aliases) {
        test('removeLoraSource($alias) removes an adapter set as '
            '/models/a.gguf', () async {
          final backend = _RecordingBackend();
          final engine = LlamaEngine(
            backend,
            modelDownloadManager: _CacheManager({}),
          );
          await engine.loadModel('/models/model.gguf');

          await engine.setLoraSource(ModelSource.path('/models/a.gguf'));
          await engine.removeLoraSource(ModelSource.path(alias));

          expect(backend.removedLoraPaths, ['/models/a.gguf']);
        });
      }

      test(
        'removeLoraSource removes a load-time adapter given as an alias',
        () async {
          final backend = _RecordingBackend();
          final engine = LlamaEngine(
            backend,
            modelDownloadManager: _CacheManager({}),
          );
          await engine.loadModel(
            '/models/model.gguf',
            modelParams: const ModelParams(
              loras: [LoraAdapterConfig(path: '/models/a.gguf')],
            ),
          );

          await engine.removeLoraSource(ModelSource.path('/models//a.gguf'));

          expect(backend.removedLoraPaths, ['/models/a.gguf']);
        },
      );

      test('removeLoraSource finds a load-time path adapter loaded under a '
          'non-normal path', () async {
        final backend = _RecordingBackend();
        final engine = LlamaEngine(
          backend,
          modelDownloadManager: _CacheManager({}),
        );
        await engine.loadModel(
          '/models/model.gguf',
          modelParams: const ModelParams(
            loras: [LoraAdapterConfig(path: '/models/./a.gguf')],
          ),
        );

        await engine.removeLoraSource(ModelSource.path('/models/a.gguf'));

        expect(backend.removedLoraPaths, ['/models/./a.gguf']);
      });

      test('removeLoraSource finds a load-time source adapter loaded under '
          'a non-normal path', () async {
        final backend = _RecordingBackend();
        final engine = LlamaEngine(
          backend,
          modelDownloadManager: _CacheManager({}),
        );
        await engine.loadModel(
          '/models/model.gguf',
          modelParams: ModelParams(
            loras: [
              LoraAdapterConfig.source(ModelSource.path('/models//a.gguf')),
            ],
          ),
        );

        await engine.removeLoraSource(ModelSource.path('/models/a.gguf'));

        expect(backend.removedLoraPaths, ['/models//a.gguf']);
      });

      test('setLoraSource through an alias only changes the scale of the '
          'applied adapter', () async {
        final backend = _RecordingBackend();
        final engine = LlamaEngine(
          backend,
          modelDownloadManager: _CacheManager({}),
        );
        await engine.loadModel('/models/model.gguf');

        await engine.setLoraSource(ModelSource.path('/models/a.gguf'));
        await engine.setLoraSource(
          ModelSource.path('/models//a.gguf'),
          scale: 0.5,
        );

        expect(backend.setLoraPaths, ['/models/a.gguf', '/models/a.gguf']);
        expect(backend.removedLoraPaths, isEmpty);

        await engine.removeLoraSource(ModelSource.path('/models/a.gguf'));
        expect(backend.removedLoraPaths, ['/models/a.gguf']);
      });

      test('Windows-style aliases match, other files do not', () async {
        final backend = _RecordingBackend();
        final engine = LlamaEngine(
          backend,
          modelDownloadManager: _CacheManager({}),
        );
        await engine.loadModel('/models/model.gguf');

        await engine.setLoraSource(ModelSource.path(r'C:\models\a.gguf'));
        await engine.removeLoraSource(ModelSource.path(r'C:\models\b.gguf'));
        await engine.removeLoraSource(ModelSource.path(r'C:\models\.\a.gguf'));
        await engine.setLoraSource(ModelSource.path('C:/models/a.gguf'));
        await engine.removeLoraSource(ModelSource.path(r'C:\models\\a.gguf'));

        expect(backend.removedLoraPaths, [
          r'C:\models\b.gguf',
          r'C:\models\a.gguf',
          'C:/models/a.gguf',
        ]);
      });

      test('a different file does not remove the tracked adapter', () async {
        final backend = _RecordingBackend();
        final engine = LlamaEngine(
          backend,
          modelDownloadManager: _CacheManager({}),
        );
        await engine.loadModel('/models/model.gguf');

        await engine.setLoraSource(ModelSource.path('/models/a.gguf'));
        await engine.removeLoraSource(ModelSource.path('/models/./b.gguf'));
        await engine.removeLoraSource(ModelSource.path('/other/../a.gguf'));
        await engine.removeLoraSource(ModelSource.path('/models/a.gguf'));

        expect(backend.removedLoraPaths, [
          '/models/./b.gguf',
          '/other/../a.gguf',
          '/models/a.gguf',
        ]);
      });
    });

    test('setLoraSource stops at a cancelled download token', () async {
      final backend = _RecordingBackend();
      final manager = _CacheManager({hfAdapter: '/cache/a.gguf'});
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      await engine.loadModel('/models/model.gguf');
      final token = ModelDownloadCancelToken()..cancel();

      await expectLater(
        engine.setLoraSource(
          hfAdapter,
          download: ModelLoadOptions(cancelToken: token),
        ),
        throwsA(isA<LlamaStateException>()),
      );
      expect(backend.lastLoraPath, isNull);
    });

    test("the caller's token stops an adapter download in progress", () async {
      final backend = _RecordingBackend();
      final manager = _BlockingManager();
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      await engine.loadModel('/models/model.gguf');
      final token = ModelDownloadCancelToken();

      final setting = engine.setLoraSource(
        hfAdapter,
        download: ModelLoadOptions(cancelToken: token),
      );
      await manager.started.future;
      token.cancel();

      await expectLater(setting, throwsA(isA<LlamaStateException>()));
      expect(manager.sawCancel, isTrue);
      expect(backend.setLoraPaths, isEmpty);
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('URL-loading backends get a remote adapter URL, and a local '
        'adapter path as written', () async {
      final backend = _RecordingBackend(urlLoadingSupported: true);
      final manager = _CacheManager({});
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      await engine.loadModelSource(
        ModelSource.url(Uri.parse('https://example.com/model.gguf')),
      );

      await engine.setLoraSource(urlAdapter, scale: 0.25);
      await engine.removeLoraSource(urlAdapter);

      expect(backend.lastLoraScale, 0.25);
      expect(backend.removedLoraPaths, [
        'https://example.com/adapters/tone.gguf',
      ]);
      await engine.setLoraSource(localAdapter);
      expect(backend.setLoraPaths.last, '/models/local-adapter.gguf');
      expect(manager.calls, isEmpty);
      await expectLater(
        engine.setLoraSource(
          urlAdapter,
          download: ModelLoadOptions(bearerToken: 'secret-token'),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });

    test('loadModelSource gives an adapter without its own options only the '
        "load's non-secret options, and one with its own options those plus "
        "the load's cancel token", () async {
      final modelSource = ModelSource.parse('hf://owner/repo/model.gguf');
      final backend = _RecordingBackend();
      final manager = _CacheManager({
        modelSource: '/cache/model.gguf',
        hfAdapter: '/cache/style.gguf',
        urlAdapter: '/cache/tone.gguf',
      });
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      final token = ModelDownloadCancelToken();
      final options = ModelLoadOptions(
        bearerToken: 'MODEL-HOST-TOKEN',
        headers: const {'X-Model-Host': 'secret'},
        sha256: 'a' * 64,
        cachePolicy: ModelCachePolicy.cacheOnly,
        cacheDirectory: '/models/cache',
        cancelToken: token,
        resume: false,
        maxRetries: 5,
      );
      final adapterOptions = ModelLoadOptions(bearerToken: 'ADAPTER-TOKEN');

      await engine.loadModelSource(
        modelSource,
        options: options,
        modelParams: ModelParams(
          loras: [
            LoraAdapterConfig.source(hfAdapter, scale: 0.5),
            LoraAdapterConfig.source(localAdapter),
            LoraAdapterConfig.source(
              urlAdapter,
              scale: 0.75,
              download: adapterOptions,
            ),
          ],
        ),
      );

      expect(backend.lastModelPath, '/cache/model.gguf');
      expect(
        [
          for (final lora in backend.contextParams.single.loras)
            (lora.path, lora.scale),
        ],
        [
          ('/cache/style.gguf', 0.5),
          ('/models/local-adapter.gguf', 1.0),
          ('/cache/tone.gguf', 0.75),
        ],
      );
      final modelOptions = manager.calls[0].options;
      expect(modelOptions.bearerToken, options.bearerToken);
      expect(modelOptions.headers, options.headers);
      expect(modelOptions.sha256, options.sha256);
      expect(modelOptions.cachePolicy, options.cachePolicy);
      expect(modelOptions.cacheDirectory, options.cacheDirectory);
      expect(modelOptions.resume, options.resume);
      expect(modelOptions.maxRetries, options.maxRetries);
      expect(modelOptions.cancelToken, isNot(same(token)));
      expect(modelOptions.cancelToken!.isCancelled, isFalse);
      final inherited = manager.calls[1].options;
      expect(inherited.bearerToken, isNull);
      expect(inherited.headers, isEmpty);
      expect(inherited.sha256, isNull);
      expect(inherited.cachePolicy, ModelCachePolicy.cacheOnly);
      expect(inherited.cacheDirectory, '/models/cache');
      expect(inherited.resume, isFalse);
      expect(inherited.maxRetries, 5);
      expect(inherited.cancelToken, same(modelOptions.cancelToken));
      final local = manager.calls[2].options;
      expect(local.bearerToken, isNull);
      expect(local.cachePolicy, ModelCachePolicy.preferCached);
      expect(local.cacheDirectory, isNull);
      expect(local.cancelToken, same(modelOptions.cancelToken));
      final own = manager.calls[3].options;
      expect(own.bearerToken, 'ADAPTER-TOKEN');
      expect(own.headers, isEmpty);
      expect(own.cacheDirectory, isNull);
      expect(own.cancelToken!.isCancelled, isFalse);
      token.cancel();
      expect(modelOptions.cancelToken!.isCancelled, isTrue);
      expect(inherited.cancelToken!.isCancelled, isTrue);
      expect(local.cancelToken!.isCancelled, isTrue);
      expect(own.cancelToken!.isCancelled, isTrue);

      await engine.removeLoraSource(urlAdapter);
      expect(backend.removedLoraPaths, ['/cache/tone.gguf']);
    });

    test("an adapter's own cancel token and the load's both cancel its "
        'download', () async {
      final loadToken = ModelDownloadCancelToken();
      final ownToken = ModelDownloadCancelToken();
      final manager = _CacheManager({hfAdapter: '/cache/style.gguf'});
      final engine = LlamaEngine(
        _RecordingBackend(),
        modelDownloadManager: manager,
      );

      await engine.loadModelSource(
        localAdapter,
        options: ModelLoadOptions(cancelToken: loadToken),
        modelParams: ModelParams(
          loras: [
            LoraAdapterConfig.source(
              hfAdapter,
              download: ModelLoadOptions(cancelToken: ownToken),
            ),
          ],
        ),
      );

      final linked = manager.calls.last.options.cancelToken!;
      expect(linked.isCancelled, isFalse);
      ownToken.cancel();
      expect(linked.isCancelled, isTrue);
      expect(loadToken.isCancelled, isFalse);
    });

    test('loadModel resolves ModelParams.loras sources with default options '
        'and keeps deprecated path adapters as written', () async {
      final backend = _RecordingBackend();
      final manager = _CacheManager({hfAdapter: '/cache/style.gguf'});
      final engine = LlamaEngine(backend, modelDownloadManager: manager);

      await engine.loadModel(
        '/models/model.gguf',
        modelParams: ModelParams(
          loras: [
            const LoraAdapterConfig(path: 'relative/legacy.gguf'),
            LoraAdapterConfig.source(hfAdapter),
          ],
        ),
      );

      expect(backend.contextParams.single.loras.map((lora) => lora.path), [
        'relative/legacy.gguf',
        '/cache/style.gguf',
      ]);
      final options = manager.calls.single.options;
      expect(options.bearerToken, isNull);
      expect(options.cachePolicy, ModelCachePolicy.preferCached);
      expect(options.cacheDirectory, isNull);
      expect(options.cancelToken, isNull);

      await engine.removeLoraSource(hfAdapter);
      expect(backend.removedLoraPaths, ['/cache/style.gguf']);
    });

    test('loadModel on a URL-loading backend records its adapters, so '
        'removeLoraSource removes them', () async {
      final backend = _RecordingBackend(urlLoadingSupported: true);
      final engine = LlamaEngine(backend);

      await engine.loadModel(
        'https://example.com/model.gguf',
        modelParams: ModelParams(loras: [LoraAdapterConfig.source(urlAdapter)]),
      );
      await engine.removeLoraSource(urlAdapter);

      expect(backend.removedLoraPaths, [
        'https://example.com/adapters/tone.gguf',
      ]);
    });

    test('a failed adapter download fails the load before the model loads, '
        'and an already loaded engine downloads nothing', () async {
      final backend = _RecordingBackend();
      final manager = _CacheManager({}, failing: {hfAdapter});
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      final params = ModelParams(loras: [LoraAdapterConfig.source(hfAdapter)]);

      await expectLater(
        engine.loadModel('/models/model.gguf', modelParams: params),
        throwsA(isA<LlamaModelException>()),
      );
      expect(backend.modelLoadCalls, 0);
      expect(engine.isReady, isFalse);

      await engine.loadModel('/models/model.gguf');
      manager.calls.clear();
      await expectLater(
        engine.loadModel('/models/model.gguf', modelParams: params),
        throwsA(isA<LlamaStateException>()),
      );
      expect(manager.calls, isEmpty);
    });

    test('URL-loading backends load ModelParams.loras sources as URLs', () async {
      final backend = _RecordingBackend(urlLoadingSupported: true);
      final engine = LlamaEngine(backend);

      await engine.loadModelSource(
        ModelSource.url(Uri.parse('https://example.com/model.gguf')),
        modelParams: ModelParams(loras: [LoraAdapterConfig.source(hfAdapter)]),
      );

      expect(
        backend.contextParams.single.loras.single.path,
        'https://huggingface.co/owner/repo/resolve/main/adapters/style.gguf?download=true',
      );
    });
  });

  group('LiteRT-LM ModelParams.loras', () {
    Matcher unsupportedLoras(String reason) => throwsA(
      isA<LlamaUnsupportedException>().having(
        (error) => error.message,
        'message',
        allOf(
          contains('LiteRT-LM takes one LoRA adapter at scale 1.0'),
          contains(reason),
          contains('no adapter was downloaded'),
        ),
      ),
    );
    final twoAdapters = ModelParams(
      loras: [
        LoraAdapterConfig.source(hfAdapter),
        LoraAdapterConfig.source(urlAdapter),
      ],
    );
    final halfScale = ModelParams(
      loras: [LoraAdapterConfig.source(hfAdapter, scale: 0.5)],
    );

    test('a LiteRT-LM backend rejects two adapters or another scale before '
        'it downloads any, and still loads one adapter at scale 1.0', () async {
      final backend = _RuntimeBackend(LlamaRuntime.liteRtLm);
      final manager = _CacheManager({
        hfAdapter: '/cache/style.gguf',
        urlAdapter: '/cache/tone.gguf',
      });
      final engine = LlamaEngine(backend, modelDownloadManager: manager);

      await expectLater(
        engine.loadModel('/models/model', modelParams: twoAdapters),
        unsupportedLoras('has 2 adapters'),
      );
      await expectLater(
        engine.loadModel('/models/model', modelParams: halfScale),
        unsupportedLoras('sets scale 0.5'),
      );
      expect(manager.calls, isEmpty);
      expect(backend.modelLoadCalls, 0);

      await engine.loadModel(
        '/models/model',
        modelParams: ModelParams(loras: [LoraAdapterConfig.source(hfAdapter)]),
      );
      expect(manager.calls.single.source.cacheKey, hfAdapter.cacheKey);
      expect(
        backend.contextParams.single.loras.single.path,
        '/cache/style.gguf',
      );
    });

    test('a format-routing backend rejects them for a .litertlm file or a '
        'declared LiteRT-LM format, and downloads them for a GGUF model even '
        'after a LiteRT-LM load', () async {
      final backend = _FormatRoutingBackend();
      final manager = _CacheManager({
        hfAdapter: '/cache/style.gguf',
        urlAdapter: '/cache/tone.gguf',
      });
      final engine = LlamaEngine(backend, modelDownloadManager: manager);

      await expectLater(
        engine.loadModel('/models/model.litertlm', modelParams: halfScale),
        unsupportedLoras('sets scale 0.5'),
      );
      await expectLater(
        engine.setModel(
          LlamaModel(
            ModelSource.path('/models/model', format: ModelFormat.liteRtLm),
          ),
          params: twoAdapters,
        ),
        unsupportedLoras('has 2 adapters'),
      );
      expect(manager.calls.map((call) => call.source.path), ['/models/model']);
      manager.calls.clear();

      await engine.loadModel('/models/model.litertlm');
      expect(engine.runtime, LlamaRuntime.liteRtLm);
      await engine.unloadModel();
      await engine.loadModel('/models/model.gguf', modelParams: twoAdapters);
      expect(manager.calls.map((call) => call.source.cacheKey), [
        hfAdapter.cacheKey,
        urlAdapter.cacheKey,
      ]);
    });

    test('loadModelSource downloads a remote .litertlm model but none of the '
        'adapters LiteRT-LM rejects', () async {
      final model = ModelSource.url(
        Uri.parse('https://example.com/model.litertlm'),
      );
      final manager = _CacheManager({
        model: '/cache/model.litertlm',
        hfAdapter: '/cache/style.gguf',
      });
      final engine = LlamaEngine(
        _FormatRoutingBackend(),
        modelDownloadManager: manager,
      );

      await expectLater(
        engine.loadModelSource(model, modelParams: halfScale),
        unsupportedLoras('sets scale 0.5'),
      );
      expect(manager.calls.map((call) => call.source.cacheKey), [
        model.cacheKey,
      ]);
    });

    test('a format-routing backend that detects a LiteRT-LM bundle in an '
        'extensionless file rejects them before it downloads any, and reads '
        'no file for adapters it takes', () async {
      final backend = _DetectingBackend(ModelFormat.liteRtLm);
      final manager = _CacheManager({
        hfAdapter: '/cache/style.gguf',
        urlAdapter: '/cache/tone.gguf',
      });
      final engine = LlamaEngine(backend, modelDownloadManager: manager);

      await expectLater(
        engine.loadModel('/models/download', modelParams: twoAdapters),
        unsupportedLoras('has 2 adapters'),
      );
      expect(backend.detectedPaths, ['/models/download']);
      expect(manager.calls, isEmpty);
      expect(backend.modelLoadCalls, 0);

      backend.detectedPaths.clear();
      await engine.loadModel(
        '/models/download',
        modelParams: ModelParams(loras: [LoraAdapterConfig.source(hfAdapter)]),
      );
      expect(backend.detectedPaths, isEmpty);
      expect(manager.calls.single.source.cacheKey, hfAdapter.cacheKey);
    });

    test('a format-routing backend that detects GGUF in an extensionless '
        'file downloads stacked adapters', () async {
      final backend = _DetectingBackend(ModelFormat.gguf);
      final manager = _CacheManager({
        hfAdapter: '/cache/style.gguf',
        urlAdapter: '/cache/tone.gguf',
      });
      final engine = LlamaEngine(backend, modelDownloadManager: manager);

      await engine.loadModel('/models/download', modelParams: twoAdapters);
      expect(manager.calls.map((call) => call.source.cacheKey), [
        hfAdapter.cacheKey,
        urlAdapter.cacheKey,
      ]);
    });

    test('LiteRT-LM embedding mode rejects an adapter before it downloads '
        'it', () async {
      final backend = _RuntimeBackend(LlamaRuntime.liteRtLm);
      final manager = _CacheManager({hfAdapter: '/cache/style.gguf'});
      final engine = LlamaEngine(backend, modelDownloadManager: manager);

      await expectLater(
        engine.loadModel(
          '/models/model',
          modelParams: ModelParams(
            liteRtLmEmbeddingEngine: true,
            loras: [LoraAdapterConfig.source(hfAdapter)],
          ),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('LiteRT-LM embedding mode takes no LoRA adapter'),
          ),
        ),
      );
      expect(manager.calls, isEmpty);
      expect(backend.modelLoadCalls, 0);
    });

    test('LiteRtLmModelParams names the embedding option as it spells '
        'it', () async {
      final backend = _RuntimeBackend(LlamaRuntime.liteRtLm);
      final manager = _CacheManager({hfAdapter: '/cache/style.gguf'});
      final engine = LlamaEngine(backend, modelDownloadManager: manager);

      await expectLater(
        engine.loadModel(
          '/models/model',
          modelParams: LiteRtLmModelParams(
            embeddingEngine: true,
            loras: [LoraAdapterConfig.source(hfAdapter)],
          ),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('empty with embeddingEngine.'),
          ),
        ),
      );
      expect(manager.calls, isEmpty);
    });

    test('a URL-loading LiteRT-LM backend rejects even one adapter at scale '
        '1.0 before it resolves it', () async {
      final backend = _RuntimeBackend(
        LlamaRuntime.liteRtLm,
        urlLoadingSupported: true,
      );
      final resolver = _CountingResolver();
      final engine = LlamaEngine(backend, modelResolver: resolver);

      await expectLater(
        engine.loadModelSource(
          ModelSource.url(Uri.parse('https://example.com/model.litertlm')),
          modelParams: ModelParams(
            loras: [LoraAdapterConfig.source(hfAdapter)],
          ),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('LiteRT-LM on the Web takes no LoRA adapter'),
              contains('has 1'),
            ),
          ),
        ),
      );
      expect(resolver.resolved, isNot(contains(hfAdapter.cacheKey)));
      expect(backend.modelLoadCalls, 0);
    });
  });

  group('speculative draft model sources', () {
    const prompt = 'hello';

    test('a generation downloads a Hugging Face draft model with '
        'draftModelDownload and sends its cached path', () async {
      final backend = _RecordingBackend();
      final manager = _CacheManager({hfDraft: '/cache/draft.gguf'});
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      await engine.loadModel('/models/model.gguf');
      final userToken = ModelDownloadCancelToken();

      await engine
          .generate(
            prompt,
            params: GenerationParams(
              speculativeDecodingConfig: SpeculativeDecodingConfig.draftSimple(
                draftModel: hfDraft,
                draftModelDownload: ModelLoadOptions(
                  bearerToken: 'secret-token',
                  cacheDirectory: '/drafts',
                  cancelToken: userToken,
                ),
                draftTokenMax: 8,
                minProbability: 0.6,
              ),
            ),
          )
          .drain<void>();

      final sent = backend.lastGenerationParams!.speculativeDecodingConfig!;
      expect(sent.draftModelPath, '/cache/draft.gguf');
      expect(sent.draftModel!.isLocal, isTrue);
      expect(sent.draftModelDownload, same(ModelLoadOptions.defaults));
      expect(sent.strategy, SpeculativeDecodingStrategy.draftSimple);
      expect(sent.strategies, [SpeculativeDecodingStrategy.draftSimple]);
      expect(sent.draftTokenMax, 8);
      expect(sent.minProbability, 0.6);
      final options = manager.calls.single.options;
      expect(options.bearerToken, 'secret-token');
      expect(options.cacheDirectory, '/drafts');
      expect(options.cancelToken, isNot(same(userToken)));
      expect(options.cancelToken!.isCancelled, isFalse);
      userToken.cancel();
      expect(options.cancelToken!.isCancelled, isTrue);
    });

    test('a local draft model is checked and sent as its path; a config '
        'without one is sent unchanged', () async {
      final backend = _RecordingBackend();
      final manager = _CacheManager({});
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      await engine.loadModel('/models/model.gguf');

      await engine
          .generate(
            prompt,
            params: GenerationParams(
              speculativeDecodingConfig: SpeculativeDecodingConfig.mixed(
                strategies: const [
                  SpeculativeDecodingStrategy.ngramMod,
                  SpeculativeDecodingStrategy.draftEagle3,
                ],
                draftModel: ModelSource.path('/models/eagle.gguf'),
                ngramMatch: 4,
              ),
            ),
          )
          .drain<void>();
      final sent = backend.lastGenerationParams!.speculativeDecodingConfig!;
      expect(sent.draftModelPath, '/models/eagle.gguf');
      expect(sent.ngramMatch, 4);
      expect(sent.effectiveStrategies, [
        SpeculativeDecodingStrategy.ngramMod,
        SpeculativeDecodingStrategy.draftEagle3,
      ]);
      expect(manager.calls.single.source.path, '/models/eagle.gguf');

      const ngram = GenerationParams(
        speculativeDecodingConfig: SpeculativeDecodingConfig.ngramMod(),
      );
      await engine.generate(prompt, params: ngram).drain<void>();
      expect(backend.lastGenerationParams, same(ngram));
      expect(manager.calls, hasLength(1));
    });

    test('chat completions resolve the draft model too', () async {
      final backend = _RecordingBackend();
      final engine = LlamaEngine(
        backend,
        modelDownloadManager: _CacheManager({hfDraft: '/cache/draft.gguf'}),
      );
      await engine.loadModel('/models/model.gguf');

      await engine.complete(
        const [LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi')],
        params: GenerationParams(
          speculativeDecodingConfig: SpeculativeDecodingConfig.draftSimple(
            draftModel: hfDraft,
          ),
        ),
      );

      expect(
        backend.lastGenerationParams!.speculativeDecodingConfig!.draftModelPath,
        '/cache/draft.gguf',
      );
    });

    test('URL-loading backends get the URL of a remote draft model and the '
        'path of a local one as written', () async {
      final backend = _RecordingBackend(urlLoadingSupported: true);
      final engine = LlamaEngine(backend);
      await engine.loadModelSource(
        ModelSource.url(Uri.parse('https://example.com/model.gguf')),
      );

      for (final (draft, location) in [
        (
          hfDraft,
          'https://huggingface.co/owner/repo/resolve/main/draft.gguf'
              '?download=true',
        ),
        (ModelSource.path('models/draft.gguf'), 'models/draft.gguf'),
        (
          ModelSource.path('blob:https://app.example/3f2a'),
          'blob:https://app.example/3f2a',
        ),
      ]) {
        await engine
            .generate(
              prompt,
              params: GenerationParams(
                speculativeDecodingConfig:
                    SpeculativeDecodingConfig.draftSimple(draftModel: draft),
              ),
            )
            .drain<void>();

        expect(
          backend
              .lastGenerationParams!
              .speculativeDecodingConfig!
              .draftModelPath,
          location,
        );
      }
    });

    test('cancelGeneration stops a draft model download without cancelling '
        "the caller's token", () async {
      final backend = _RecordingBackend();
      final manager = _BlockingManager();
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      await engine.loadModel('/models/model.gguf');
      final userToken = ModelDownloadCancelToken();

      final tokens = <String>[];
      final done = engine
          .generate(
            prompt,
            params: GenerationParams(
              speculativeDecodingConfig: SpeculativeDecodingConfig.draftSimple(
                draftModel: hfDraft,
                draftModelDownload: ModelLoadOptions(cancelToken: userToken),
              ),
            ),
          )
          .listen(tokens.add)
          .asFuture<void>();
      await manager.started.future;
      engine.cancelGeneration();
      await done;

      expect(tokens, isEmpty);
      expect(backend.lastGenerationParams, isNull);
      expect(manager.sawCancel, isTrue);
      expect(userToken.isCancelled, isFalse);
    });

    test('a failed draft model download fails the generation', () async {
      final backend = _RecordingBackend();
      final engine = LlamaEngine(
        backend,
        modelDownloadManager: _CacheManager({}, failing: {hfDraft}),
      );
      await engine.loadModel('/models/model.gguf');

      await expectLater(
        engine
            .generate(
              prompt,
              params: GenerationParams(
                speculativeDecodingConfig:
                    SpeculativeDecodingConfig.draftSimple(draftModel: hfDraft),
              ),
            )
            .drain<void>(),
        throwsA(isA<LlamaModelException>()),
      );
      expect(backend.lastGenerationParams, isNull);
    });
  });

  group('LoRA source lifecycle', () {
    test('unloading forgets where remote adapters resolved', () async {
      final backend = _RecordingBackend();
      final engine = LlamaEngine(
        backend,
        modelDownloadManager: _CacheManager({urlAdapter: '/cache/tone.gguf'}),
      );
      await engine.loadModel('/models/model.gguf');
      await engine.setLoraSource(urlAdapter);
      await engine.unloadModel();
      await engine.loadModel('/models/model.gguf');

      await engine.removeLoraSource(urlAdapter);

      expect(backend.removedLoraPaths, isEmpty);
    });

    test('removeLoraSource removes a local adapter by its path even when it '
        'was not set from that source', () async {
      final backend = _RecordingBackend();
      final engine = LlamaEngine(
        backend,
        modelDownloadManager: _CacheManager({}),
      );
      await engine.loadModel('/models/model.gguf');

      await engine.removeLoraSource(localAdapter);

      expect(backend.removedLoraPaths, ['/models/local-adapter.gguf']);
    });

    test('setLoraSource with options that resolve the same source to another '
        'file replaces the adapter applied from it', () async {
      final backend = _RecordingBackend();
      final manager = _DirectoryManager();
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      await engine.loadModel('/models/model.gguf');

      await engine.setLoraSource(
        urlAdapter,
        download: ModelLoadOptions(cacheDirectory: '/a'),
      );
      await engine.setLoraSource(
        urlAdapter,
        download: ModelLoadOptions(cacheDirectory: '/b'),
      );
      await engine.removeLoraSource(urlAdapter);

      expect(backend.setLoraPaths, ['/a/tone.gguf', '/b/tone.gguf']);
      expect(backend.removedLoraPaths, ['/a/tone.gguf', '/b/tone.gguf']);
    });

    test('setLoraSource stops when its token is cancelled while the adapter '
        'resolves', () async {
      final backend = _RecordingBackend();
      final token = ModelDownloadCancelToken();
      final engine = LlamaEngine(
        backend,
        modelDownloadManager: _CacheManager({
          hfAdapter: '/cache/style.gguf',
        }, onEnsure: token.cancel),
      );
      await engine.loadModel('/models/model.gguf');

      await expectLater(
        engine.setLoraSource(
          hfAdapter,
          download: ModelLoadOptions(cancelToken: token),
        ),
        throwsA(isA<LlamaStateException>()),
      );
      expect(backend.setLoraPaths, isEmpty);
    });

    test(
      'loadModelFromUrl resolves adapter sources through the resolver',
      () async {
        final backend = _RecordingBackend(urlLoadingSupported: true);
        final engine = LlamaEngine(backend, modelResolver: _MirrorResolver());

        await engine.loadModelFromUrl(
          'https://example.com/model.gguf',
          modelParams: ModelParams(
            loras: [LoraAdapterConfig.source(hfAdapter)],
          ),
        );

        expect(
          backend.contextParams.single.loras.single.path,
          'https://mirror.example.com/style.gguf',
        );
      },
    );
  });

  group('LoRA locations and model changes', () {
    test('removeLoraSource forgets the location it removed', () async {
      final backend = _RecordingBackend();
      final engine = LlamaEngine(
        backend,
        modelDownloadManager: _CacheManager({urlAdapter: '/cache/tone.gguf'}),
      );
      await engine.loadModel('/models/model.gguf');

      await engine.setLoraSource(urlAdapter);
      await engine.removeLoraSource(urlAdapter);
      await engine.removeLoraSource(urlAdapter);

      expect(backend.removedLoraPaths, ['/cache/tone.gguf']);
    });

    test('an adapter download that finishes after the model was unloaded is '
        'not applied, and unloading stops it', () async {
      final backend = _RecordingBackend();
      final manager = _BlockingManager();
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      await engine.loadModel('/models/model.gguf');

      final setting = engine.setLoraSource(hfAdapter);
      await manager.started.future;
      await engine.unloadModel();
      await engine.loadModel('/models/other.gguf');

      await expectLater(
        setting,
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            contains('unloaded'),
          ),
        ),
      );
      expect(manager.sawCancel, isTrue);
      expect(backend.setLoraPaths, isEmpty);
    });

    test('an adapter download that completes after the model was reloaded '
        'is not applied', () async {
      final backend = _RecordingBackend();
      final manager = _GatedManager({hfAdapter: '/cache/style.gguf'});
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      await engine.loadModel('/models/model.gguf');

      final setting = engine.setLoraSource(hfAdapter);
      await manager.started.future;
      await engine.unloadModel();
      await engine.loadModel('/models/model.gguf');
      manager.gate.complete();

      await expectLater(setting, throwsA(isA<LlamaStateException>()));
      expect(backend.setLoraPaths, isEmpty);
    });

    test('an adapter resolved for a load that fails is forgotten', () async {
      final backend = _RecordingBackend()..modelLoadError = Exception('bad');
      final engine = LlamaEngine(
        backend,
        modelDownloadManager: _CacheManager({urlAdapter: '/cache/tone.gguf'}),
      );

      await expectLater(
        engine.loadModel(
          '/models/model.gguf',
          modelParams: ModelParams(
            loras: [LoraAdapterConfig.source(urlAdapter)],
          ),
        ),
        throwsA(isA<LlamaModelException>()),
      );
      backend.modelLoadError = null;
      await engine.loadModel('/models/model.gguf');
      await engine.removeLoraSource(urlAdapter);

      expect(backend.removedLoraPaths, isEmpty);
    });

    test('loadModelSource on a loaded engine keeps the applied adapter '
        'locations', () async {
      final backend = _RecordingBackend();
      final engine = LlamaEngine(
        backend,
        modelDownloadManager: _DirectoryManager(),
      );
      await engine.loadModel('/models/model.gguf');
      await engine.setLoraSource(
        urlAdapter,
        download: ModelLoadOptions(cacheDirectory: '/a'),
      );

      await expectLater(
        engine.loadModelSource(
          localAdapter,
          modelParams: ModelParams(
            loras: [
              LoraAdapterConfig.source(
                urlAdapter,
                download: ModelLoadOptions(cacheDirectory: '/b'),
              ),
            ],
          ),
        ),
        throwsA(isA<LlamaException>()),
      );
      await engine.removeLoraSource(urlAdapter);

      expect(backend.removedLoraPaths, ['/a/tone.gguf']);
    });

    test('loadModelSource stops when its token is cancelled while an adapter '
        'downloads', () async {
      final backend = _RecordingBackend();
      final token = ModelDownloadCancelToken();
      var downloads = 0;
      final engine = LlamaEngine(
        backend,
        modelDownloadManager: _CacheManager(
          {hfAdapter: '/cache/style.gguf'},
          onEnsure: () {
            if (++downloads == 2) token.cancel();
          },
        ),
      );

      await expectLater(
        engine.loadModelSource(
          localAdapter,
          options: ModelLoadOptions(cancelToken: token),
          modelParams: ModelParams(
            loras: [LoraAdapterConfig.source(hfAdapter)],
          ),
        ),
        throwsA(isA<LlamaStateException>()),
      );
      expect(backend.modelLoadCalls, 0);
    });
  });

  group('speculative draft model reuse', () {
    GenerationParams draftParams({
      ModelLoadOptions download = ModelLoadOptions.defaults,
    }) => GenerationParams(
      speculativeDecodingConfig: SpeculativeDecodingConfig.draftSimple(
        draftModel: hfDraft,
        draftModelDownload: download,
      ),
    );

    for (final nativeChat in [false, true]) {
      for (final reuseHandle in [false, true]) {
        test('late draft resolution preserves reload counters '
            '(native: $nativeChat, reused: $reuseHandle)', () async {
          final backend = _ReloadPerformanceBackend(
            nativeChat: nativeChat,
            reuseHandle: reuseHandle,
          );
          final manager = _GatedManager({hfDraft: '/cache/draft.gguf'});
          final engine = LlamaEngine(backend, modelDownloadManager: manager);
          addTearDown(engine.dispose);
          await engine.loadModel('/models/model.gguf');
          final old = nativeChat
              ? engine.create(const [
                  LlamaChatMessage.fromText(
                    role: LlamaChatRole.user,
                    text: 'hi',
                  ),
                ], params: draftParams()).drain<void>()
              : engine.generate('hi', params: draftParams()).drain<void>();
          final settled = expectLater(old, throwsA(isA<LlamaStateException>()));
          await manager.started.future;
          await engine.unloadModel();
          await engine.loadModel('/models/reloaded.gguf');
          await engine.generate('new').drain<void>();
          expect((await engine.getPerformanceContext())?.evalTokens, 1);
          manager.gate.complete();
          await settled;
          expect((await engine.getPerformanceContext())?.evalTokens, 1);
        });
      }
    }

    for (final reuseHandle in [false, true]) {
      test('old context calls cannot hide a reload early cancel '
          '(reused: $reuseHandle)', () async {
        final backend = _ReloadPerformanceBackend(
          nativeChat: false,
          reuseHandle: reuseHandle,
        );
        final engine = LlamaEngine(backend);
        addTearDown(engine.dispose);
        await engine.loadModel('/models/model.gguf');
        final release = Completer<void>();
        backend.embeddingHold = release.future;
        final old = engine.embed('old');
        await backend.embeddingStarted.future;
        await engine.unloadModel();
        await engine.loadModel('/models/reloaded.gguf');
        await engine.generate('new').drain<void>();
        expect((await engine.getPerformanceContext())?.evalTokens, 1);
        Future<void> cancelEarly() async {
          final cancelled = engine.generate('cancelled').drain<void>();
          engine.cancelGeneration();
          await cancelled;
          expect(await engine.getPerformanceContext(), isNull);
        }

        try {
          await cancelEarly();
        } finally {
          release.complete();
          await old;
        }
        await engine.generate('next').drain<void>();
        expect((await engine.getPerformanceContext())?.evalTokens, 1);
        await cancelEarly();
      });
    }

    test(
      'ending one overlapping call keeps the remaining context call counted',
      () async {
        final backend = _ReloadPerformanceBackend(
          nativeChat: false,
          reuseHandle: true,
        );
        final engine = LlamaEngine(backend);
        addTearDown(engine.dispose);
        await engine.loadModel('/models/model.gguf');
        final release = Completer<void>();
        backend.hold = release.future;
        final first = engine.generate('first').listen((_) {});
        final second = engine.generate('second').drain<void>();
        while (backend.generations < 2) {
          await Future<void>.delayed(Duration.zero);
        }
        try {
          await first.cancel();
          final early = engine.generate('early').listen((_) {});
          await early.cancel();
          await Future<void>.delayed(Duration.zero);
          expect((await engine.getPerformanceContext())?.evalTokens, 0);
        } finally {
          release.complete();
          await second;
        }
      },
    );

    test('a draft model resolves once across generations, and again after '
        'the model reloads', () async {
      final backend = _RecordingBackend();
      final manager = _CacheManager({hfDraft: '/cache/draft.gguf'});
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      await engine.loadModel('/models/model.gguf');
      final download = ModelLoadOptions(sha256: 'b' * 64);

      for (var i = 0; i < 3; i++) {
        await engine
            .generate('hi', params: draftParams(download: download))
            .drain<void>();
        expect(
          backend
              .lastGenerationParams!
              .speculativeDecodingConfig!
              .draftModelPath,
          '/cache/draft.gguf',
        );
      }
      expect(manager.calls, hasLength(1));

      await engine.unloadModel();
      await engine.loadModel('/models/model.gguf');
      await engine
          .generate('hi', params: draftParams(download: download))
          .drain<void>();
      expect(manager.calls, hasLength(2));
    });

    test(
      'another cache directory or checksum resolves the draft model again',
      () async {
        final manager = _CacheManager({hfDraft: '/cache/draft.gguf'});
        final engine = LlamaEngine(
          _RecordingBackend(),
          modelDownloadManager: manager,
        );
        await engine.loadModel('/models/model.gguf');

        await engine.generate('hi', params: draftParams()).drain<void>();
        await engine
            .generate(
              'hi',
              params: draftParams(
                download: ModelLoadOptions(cacheDirectory: '/other'),
              ),
            )
            .drain<void>();
        await engine
            .generate(
              'hi',
              params: draftParams(download: ModelLoadOptions(sha256: 'c' * 64)),
            )
            .drain<void>();
        await engine.generate('hi', params: draftParams()).drain<void>();

        expect(manager.calls, hasLength(3));
      },
    );

    for (final policy in [ModelCachePolicy.noCache, ModelCachePolicy.refresh]) {
      test('draftModelDownload rejects ModelCachePolicy.${policy.name} before '
          'downloading', () async {
        final backend = _RecordingBackend();
        final manager = _CacheManager({hfDraft: '/cache/draft.gguf'});
        final engine = LlamaEngine(backend, modelDownloadManager: manager);
        await engine.loadModel('/models/model.gguf');

        await expectLater(
          engine
              .generate(
                'hi',
                params: draftParams(
                  download: ModelLoadOptions(cachePolicy: policy),
                ),
              )
              .drain<void>(),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              contains('ModelCachePolicy.${policy.name}'),
            ),
          ),
        );
        expect(manager.calls, isEmpty);
        expect(backend.lastGenerationParams, isNull);
      });
    }

    test('unloading the model stops a draft model download and the '
        'generation never reaches the backend', () async {
      final backend = _RecordingBackend();
      final manager = _BlockingManager();
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      await engine.loadModel('/models/model.gguf');

      final chat = ChatSession(engine);
      final done = expectLater(
        chat.send('hi', params: draftParams()),
        throwsA(isA<LlamaStateException>()),
      );
      await manager.started.future;
      await engine.unloadModel();
      await engine.loadModel('/models/model.gguf');
      await done;

      expect(chat.history, isEmpty);
      expect(manager.sawCancel, isTrue);
      expect(backend.lastGenerationParams, isNull);
    });

    test('a generation cancelled as its draft model finishes downloading '
        'stops, and the next one resolves the draft again', () async {
      final backend = _RecordingBackend();
      late final LlamaEngine engine;
      var cancelNext = true;
      final manager = _CacheManager(
        {hfDraft: '/cache/draft.gguf'},
        onEnsure: () {
          if (cancelNext) engine.cancelGeneration();
          cancelNext = false;
        },
      );
      engine = LlamaEngine(backend, modelDownloadManager: manager);
      await engine.loadModel('/models/model.gguf');

      await engine.generate('hi', params: draftParams()).drain<void>();
      expect(backend.lastGenerationParams, isNull);

      await engine.generate('hi', params: draftParams()).drain<void>();
      expect(manager.calls, hasLength(2));
      expect(backend.lastGenerationParams, isNotNull);
    });

    test("backends never receive a config's download options, whatever its "
        'strategy', () async {
      final backend = _RecordingBackend();
      final manager = _CacheManager({});
      final engine = LlamaEngine(backend, modelDownloadManager: manager);
      await engine.loadModel('/models/model.gguf');
      final download = ModelLoadOptions(
        bearerToken: 'secret-token',
        cancelToken: ModelDownloadCancelToken(),
      );

      for (final config in [
        SpeculativeDecodingConfig.mtp(draftModelDownload: download),
        SpeculativeDecodingConfig(
          strategies: const [SpeculativeDecodingStrategy.ngramSimple],
          ngramSizeN: 3,
          draftModelDownload: download,
        ),
        SpeculativeDecodingConfig.draftSimple(
          draftModelPath: '/models/draft.gguf',
          draftTokenMax: 4,
          draftModelDownload: download,
        ),
      ]) {
        await engine
            .generate(
              'hi',
              params: GenerationParams(speculativeDecodingConfig: config),
            )
            .drain<void>();
        final sent = backend.lastGenerationParams!.speculativeDecodingConfig!;
        expect(sent.draftModelDownload, same(ModelLoadOptions.defaults));
        expect(sent.strategies, config.strategies);
        expect(sent.draftModelPath, config.draftModelPath);
        expect(sent.ngramSizeN, config.ngramSizeN);
        expect(sent.draftTokenMax, config.draftTokenMax);
      }
      expect(manager.calls, isEmpty);

      const plain = GenerationParams(
        speculativeDecodingConfig: SpeculativeDecodingConfig.ngramMod(),
      );
      await engine.generate('hi', params: plain).drain<void>();
      expect(backend.lastGenerationParams, same(plain));
    });

    test('LiteRT-LM rejects a draft model before it downloads', () async {
      final manager = _CacheManager({hfDraft: '/cache/draft.gguf'});
      final engine = LlamaEngine(
        _RuntimeBackend(LlamaRuntime.liteRtLm),
        modelDownloadManager: manager,
      );
      await engine.loadModel('/models/model.litertlm');

      await expectLater(
        engine.generate('hi', params: draftParams()).drain<void>(),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('LiteRT-LM cannot load an external speculative draft'),
          ),
        ),
      );
      expect(manager.calls, isEmpty);
    });

    test('a backend that does not report the strategy rejects the draft '
        'model before it downloads, and one that does resolves it', () async {
      final manager = _CacheManager({hfDraft: '/cache/draft.gguf'});
      final unsupported = LlamaEngine(
        _RuntimeBackend(
          LlamaRuntime.llamaCpp,
          strategies: {SpeculativeDecodingStrategy.ngramMod},
        ),
        modelDownloadManager: manager,
      );
      await unsupported.loadModel('/models/model.gguf');

      await expectLater(
        unsupported.generate('hi', params: draftParams()).drain<void>(),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('draftSimple'),
          ),
        ),
      );
      expect(manager.calls, isEmpty);

      final supportedBackend = _RuntimeBackend(
        LlamaRuntime.llamaCpp,
        strategies: {SpeculativeDecodingStrategy.draftSimple},
      );
      final supported = LlamaEngine(
        supportedBackend,
        modelDownloadManager: manager,
      );
      await supported.loadModel('/models/model.gguf');
      await supported.generate('hi', params: draftParams()).drain<void>();
      expect(manager.calls, hasLength(1));
    });

    test('native chat generation resolves the draft model', () async {
      final backend = NativeChatMockBackend();
      final engine = LlamaEngine(
        backend,
        modelDownloadManager: _CacheManager({hfDraft: '/cache/draft.gguf'}),
      );
      await engine.loadModel('/models/model.gguf');

      await engine.complete(const [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
      ], params: draftParams());

      expect(backend.nativeGenerateChatCalls, 1);
      expect(
        backend.lastNativeParams!.speculativeDecodingConfig!.draftModelPath,
        '/cache/draft.gguf',
      );
    });

    test('the resolved config keeps every other field', () async {
      final backend = _RecordingBackend();
      final engine = LlamaEngine(
        backend,
        modelDownloadManager: _CacheManager({hfDraft: '/cache/draft.gguf'}),
      );
      await engine.loadModel('/models/model.gguf');
      final config = SpeculativeDecodingConfig.mixed(
        strategies: const [
          SpeculativeDecodingStrategy.ngramSimple,
          SpeculativeDecodingStrategy.ngramMod,
          SpeculativeDecodingStrategy.ngramCache,
          SpeculativeDecodingStrategy.draftSimple,
        ],
        draftTokenMax: 9,
        draftTokenMin: 2,
        minProbability: 0.3,
        draftSplitProbability: 0.2,
        draftModel: hfDraft,
        ngramSize: 3,
        ngramSizeN: 4,
        ngramSizeM: 5,
        ngramMinHits: 6,
        ngramMatch: 7,
        ngramTokenMin: 8,
        ngramTokenMax: 10,
        ngramCacheStaticPath: '/static.bin',
        ngramCacheDynamicPath: '/dynamic.bin',
      );

      await engine
          .generate(
            'hi',
            params: GenerationParams(speculativeDecodingConfig: config),
          )
          .drain<void>();

      final sent = backend.lastGenerationParams!.speculativeDecodingConfig!;
      expect(
        (
          sent.strategy,
          sent.strategies,
          sent.draftTokenMax,
          sent.draftTokenMin,
          sent.minProbability,
          sent.draftSplitProbability,
          sent.draftModelPath,
          sent.draftModel!.kind,
        ),
        (
          config.strategy,
          config.strategies,
          9,
          2,
          0.3,
          0.2,
          '/cache/draft.gguf',
          ModelSourceKind.path,
        ),
      );
      expect(
        (
          sent.ngramSize,
          sent.ngramSizeN,
          sent.ngramSizeM,
          sent.ngramMinHits,
          sent.ngramMatch,
          sent.ngramTokenMin,
          sent.ngramTokenMax,
          sent.ngramCacheStaticPath,
          sent.ngramCacheDynamicPath,
        ),
        (3, 4, 5, 6, 7, 8, 10, '/static.bin', '/dynamic.bin'),
      );
    });
  });
}

class _RecordingBackend extends MockLlamaBackend {
  _RecordingBackend({super.urlLoadingSupported});

  final List<ModelParams> contextParams = <ModelParams>[];
  final List<String> setLoraPaths = <String>[];
  final List<String> removedLoraPaths = <String>[];

  @override
  Future<void> setLoraAdapter(int contextHandle, String path, double scale) {
    setLoraPaths.add(path);
    return super.setLoraAdapter(contextHandle, path, scale);
  }

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) {
    contextParams.add(params);
    return super.contextCreate(modelHandle, params);
  }

  @override
  Future<void> removeLoraAdapter(int contextHandle, String path) {
    removedLoraPaths.add(path);
    return super.removeLoraAdapter(contextHandle, path);
  }
}

typedef _Call = ({ModelSource source, ModelLoadOptions options});

/// Returns the file mapped to each source's cache key, the path of a local
/// source, and fails for [failing] sources. [onEnsure] runs once a download
/// has passed its cancellation check, as a cancel arriving after it.
class _CacheManager implements ModelDownloadManager {
  _CacheManager(
    Map<ModelSource, String> files, {
    Set<ModelSource>? failing,
    this.onEnsure,
  }) : _files = {
         for (final MapEntry(:key, :value) in files.entries)
           key.cacheKey: value,
       },
       _failing = {for (final source in failing ?? {}) source.cacheKey};

  final Map<String, String> _files;
  final Set<String> _failing;
  final List<_Call> calls = <_Call>[];
  final void Function()? onEnsure;

  @override
  Future<ModelCacheEntry> ensureModel(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    calls.add((source: source, options: options));
    if (options.cancelToken?.isCancelled ?? false) {
      throw LlamaStateException('Model download was cancelled.');
    }
    onEnsure?.call();
    if (_failing.contains(source.cacheKey)) {
      throw LlamaModelException('Download failed.');
    }
    onProgress?.call(
      const ModelDownloadProgress(receivedBytes: 1, totalBytes: 2),
    );
    return ModelCacheEntry(
      sourceCanonicalKey: source.metadataSourceKey,
      cacheKey: source.cacheKey,
      fileName: source.fileName,
      filePath: source.path ?? _files[source.cacheKey]!,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
  }

  @override
  Future<void> clear({String? cacheDirectory}) async {}

  @override
  Future<ModelCacheEntry?> get(
    String cacheKey, {
    String? cacheDirectory,
  }) async => null;

  @override
  Future<List<ModelCacheEntry>> list({String? cacheDirectory}) async =>
      const <ModelCacheEntry>[];

  @override
  Future<List<ModelCacheEntry>> prune({
    Duration? maxAge,
    int? maxBytes,
    String? cacheDirectory,
  }) async => const <ModelCacheEntry>[];

  @override
  Future<void> remove(String cacheKey, {String? cacheDirectory}) async {}
}

/// Polls its cancel token like the package download manager, until it is
/// cancelled.
class _BlockingManager extends _CacheManager {
  _BlockingManager() : super({});

  final Completer<void> started = Completer<void>();
  bool sawCancel = false;

  @override
  Future<ModelCacheEntry> ensureModel(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    started.complete();
    while (!(options.cancelToken?.isCancelled ?? false)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    sawCancel = true;
    throw LlamaStateException('Model download was cancelled.');
  }
}

/// Puts each remote file in the options' cache directory.
class _DirectoryManager extends _CacheManager {
  _DirectoryManager() : super({});

  @override
  Future<ModelCacheEntry> ensureModel(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    calls.add((source: source, options: options));
    return ModelCacheEntry(
      sourceCanonicalKey: source.metadataSourceKey,
      cacheKey: source.cacheKey,
      fileName: source.fileName,
      filePath: '${options.cacheDirectory}/${source.fileName}',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
  }
}

/// Resolves every remote source to a mirror URL.
class _MirrorResolver implements ModelResolver {
  @override
  Future<ModelLoadTarget> resolve(
    ModelSource source,
    ModelResolveRequest request,
  ) async => source.isLocal
      ? LocalModelFile(source.path!)
      : RemoteModelUrl(
          Uri.parse('https://mirror.example.com/${source.fileName}'),
        );
}

class _RuntimeBackend extends _RecordingBackend
    implements BackendRuntimeIdentity, BackendGenerationCapabilitiesSupport {
  _RuntimeBackend(
    this.runtime, {
    this.strategies = const {},
    super.urlLoadingSupported,
  });

  @override
  final LlamaRuntime runtime;
  final Set<SpeculativeDecodingStrategy> strategies;

  @override
  Future<BackendGenerationCapabilities> generationCapabilities() async =>
      BackendGenerationCapabilities(
        presencePenalty: false,
        minP: false,
        thinkingBudget: false,
        speculativeDecodingStrategies: strategies,
      );
}

/// Chooses the runtime from an explicit format or the file extension, as
/// `LlamaBackend()` does without a readable header.
class _FormatRoutingBackend extends _RecordingBackend
    implements BackendModelFormatRouting, BackendRuntimeIdentity {
  @override
  LlamaRuntime? runtime;

  @override
  Future<int> modelLoad(String path, ModelParams params) =>
      modelLoadAs(path, params, ModelFormat.fromPath(path) ?? ModelFormat.gguf);

  @override
  Future<int> modelLoadAs(String path, ModelParams params, ModelFormat format) {
    runtime = format.runtime;
    return super.modelLoad(path, params);
  }

  @override
  Future<int> modelLoadFromUrlAs(
    String url,
    ModelParams params,
    ModelFormat format, {
    void Function(double progress)? onProgress,
  }) {
    runtime = format.runtime;
    return super.modelLoadFromUrl(url, params, onProgress: onProgress);
  }
}

/// Routes like [_FormatRoutingBackend] and detects [detected] in every file
/// it is asked about, as `LlamaBackend()` reads a native file header.
class _DetectingBackend extends _FormatRoutingBackend
    implements BackendModelFormatDetection {
  _DetectingBackend(this.detected);

  final ModelFormat detected;
  final List<String> detectedPaths = <String>[];

  @override
  Future<ModelFormat?> detectModelFormat(String path) async {
    detectedPaths.add(path);
    return detected;
  }
}

/// Resolves like the default resolver and records each source's cache key.
class _CountingResolver implements ModelResolver {
  final List<String> resolved = <String>[];

  @override
  Future<ModelLoadTarget> resolve(
    ModelSource source,
    ModelResolveRequest request,
  ) {
    resolved.add(source.cacheKey);
    return const DefaultModelResolver().resolve(source, request);
  }
}

/// A LiteRT-LM backend, which has no runtime LoRA API.
class _NoLoraBackend extends _RuntimeBackend {
  _NoLoraBackend() : super(LlamaRuntime.liteRtLm);

  @override
  Future<void> removeLoraAdapter(int contextHandle, String path) =>
      throw UnsupportedError('No runtime LoRA API.');
}

/// Waits for [gate] and then completes the download, ignoring cancellation.
class _GatedManager extends _CacheManager {
  _GatedManager(super.files);

  final Completer<void> started = Completer<void>();
  final Completer<void> gate = Completer<void>();

  @override
  Future<ModelCacheEntry> ensureModel(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    started.complete();
    await gate.future;
    return super.ensureModel(
      source,
      options: ModelLoadOptions(cacheDirectory: options.cacheDirectory),
    );
  }
}

class _ReloadPerformanceBackend extends PerformanceCounterBackend {
  _ReloadPerformanceBackend({
    required super.nativeChat,
    required this.reuseHandle,
  });
  final bool reuseHandle;
  int contexts = 0;

  Future<void>? embeddingHold;
  final embeddingStarted = Completer<void>();

  @override
  Future<List<double>> embed(
    int contextHandle,
    String text, {
    bool normalize = true,
  }) async {
    embeddingStarted.complete();
    await embeddingHold;
    return [1];
  }

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async {
    contexts++;
    return reuseHandle ? 1 : contexts;
  }
}
