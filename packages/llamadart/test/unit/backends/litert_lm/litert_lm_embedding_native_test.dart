@TestOn('vm && (mac-os || linux)')
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_embedding.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_backend.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';
import 'package:llamadart/src/backends/litert_lm/worker.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:test/test.dart';

import '../../../support/suite_system_temp.dart';
import 'litert_lm_embedding_test.dart' show embeddingBundleHeader;

void main() {
  final suite = useSuiteSystemTemp();
  late String library;
  late String model;
  late void Function(int) mode;
  late int Function() allocations;
  late int Function() processorBackends;
  late int Function() calls;
  late void Function() release;
  setUpAll(() async {
    final source = File('${suite().path}/embedding.c');
    await source.writeAsString(_source);
    library = '${suite().path}/embedding${Platform.isMacOS ? '.dylib' : '.so'}';
    final result = await Process.run('cc', [
      Platform.isMacOS ? '-dynamiclib' : '-shared',
      '-fPIC',
      source.path,
      '-o',
      library,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final lib = DynamicLibrary.open(library);
    mode = lib.lookupFunction<Void Function(Int), void Function(int)>(
      'set_mode',
    );
    allocations = lib.lookupFunction<Int Function(), int Function()>(
      'allocations',
    );
    calls = lib.lookupFunction<Int Function(), int Function()>('compute_calls');
    release = lib.lookupFunction<Void Function(), void Function()>(
      'release_compute',
    );
    processorBackends = lib.lookupFunction<Int Function(), int Function()>(
      'processor_backends',
    );
    model = '${suite().path}/model.litertlm';
    await File(model).writeAsBytes(embeddingBundleHeader());
  });
  setUp(() {
    mode(0);
    // The fake runtime stands in for a qualified target on every test host.
    debugLiteRtLmAbiOverride = Abi.macosArm64;
    addTearDown(() => debugLiteRtLmAbiOverride = null);
  });
  Future<LiteRtLmEmbeddingSession> create({
    String? modelPath,
    String? libraryPath,
    String backend = 'cpu',
  }) => LiteRtLmRuntimeClient(libraryPath: libraryPath ?? library)
      .createEmbeddingSession(
        modelPath: modelPath ?? model,
        backend: backend,
        cacheDir: suite().path,
        maxInputLength: 1024,
        numberOfThreads: 2,
      );
  List<LiteRtLmEmbeddingPart> input() => [
    LiteRtLmEmbeddingPart(0, Uint8List.fromList([97, 98])),
  ];
  const embeddingParams = ModelParams(
    liteRtLmEmbeddingEngine: true,
    device: ComputeDevice.cpu,
    contextSize: 1024,
    numberOfThreads: 2,
  );
  Future<(LiteRtLmBackend, int, int)> backendForTest({
    Duration embeddingTimeout = const Duration(minutes: 10),
  }) async {
    final port = ReceivePort();
    final service = LiteRtLmService(
      clientFactory: () => LiteRtLmRuntimeClient(libraryPath: library),
    );
    runLiteRtLmWorkerForTesting(port.sendPort, service, exitOnDispose: false);
    final backend = LiteRtLmBackend(
      initialSendPort: await port.first as SendPort,
      embeddingTimeout: embeddingTimeout,
    );
    port.close();
    addTearDown(backend.dispose);
    final handle = await backend.modelLoad(model, embeddingParams);
    final context = await backend.contextCreate(handle, embeddingParams);
    await backend.getEmbeddingCapabilities(context);
    return (backend, handle, context);
  }

  Future<void> waitForCompute() async {
    await Future<void>(() async {
      while (calls() == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }).timeout(const Duration(seconds: 3));
  }

  test(
    'embedding deadline throws a typed error and cancels native work before reuse',
    () async {
      // The deadline also bounds the reuse call, which must not race it on a
      // loaded host.
      const deadline = Duration(seconds: 1);
      final (backend, _, context) = await backendForTest(
        embeddingTimeout: deadline,
      );
      mode(11);
      final timedOut = expectLater(
        backend.embedBatch(context, List.filled(60, 'x')),
        throwsA(
          isA<LlamaInferenceException>().having(
            (e) => e.message,
            'timeout',
            contains('timed out'),
          ),
        ),
      );
      await waitForCompute();
      await timedOut;
      release();
      // The queued probe waits for cancellation settlement on the production worker chain.
      await backend.getEmbeddingCapabilities(context);
      expect(calls(), 1);
      mode(0);
      expect(await backend.embed(context, 'reuse', normalize: false), [3, 4]);
    },
  );
  test(
    'one embedding timeout preserves another caller queued behind it',
    () async {
      final (backend, _, context) = await backendForTest(
        embeddingTimeout: const Duration(seconds: 2),
      );
      mode(11);
      final first = expectLater(
        backend.embedBatch(context, List.filled(60, 'active')),
        throwsA(
          isA<LlamaInferenceException>().having(
            (e) => e.message,
            'deadline',
            contains('timed out'),
          ),
        ),
      );
      await waitForCompute();
      await Future<void>.delayed(const Duration(seconds: 1));
      final second = backend.embed(context, 'queued', normalize: false);
      // Attach the expectation before releasing the held native item.
      final secondResult = expectLater(second, completion([3.0, 4.0]));
      await first;
      release();
      await secondResult;
      expect(
        calls(),
        2,
        reason: 'only the timed-out batch loses its remaining items',
      );
    },
  );
  for (final operation in ['dispose', 'contextFree']) {
    test('$operation during preflight prevents embedding dispatch', () async {
      final (backend, _, context) = await backendForTest();
      final pending = backend.embedBatch(context, List.filled(60, 'preflight'));
      final rejected = expectLater(
        pending,
        throwsA(
          isA<LlamaInferenceException>().having(
            (e) => e.message,
            'preflight cancellation',
            contains('during media preflight'),
          ),
        ),
      );
      await (operation == 'dispose'
          ? backend.dispose()
          : backend.contextFree(context));
      await rejected;
      expect(calls(), 0);
    });
  }
  test(
    'cancel during embedding creation prevents the first native inference',
    () async {
      final service = LiteRtLmService(
        clientFactory: () => LiteRtLmRuntimeClient(libraryPath: library),
      );
      addTearDown(service.dispose);
      final handle = await service.loadModel(model, embeddingParams);
      final context = service.createContext(handle, embeddingParams);
      mode(12);
      final rejected = expectLater(
        service.embed(context, [input()], normalize: false),
        throwsA(isA<LlamaInferenceException>()),
      );
      await waitForCompute();
      service.cancelGeneration();
      release();
      await rejected;
      expect(calls(), 1, reason: 'only engine creation entered the fake');
      mode(0);
      expect(await service.embed(context, [input()], normalize: false), [
        [3, 4],
      ]);
    },
  );
  test(
    'embedding request on a stale context reports a typed state error',
    () async {
      final (backend, _, _) = await backendForTest();
      await expectLater(
        backend.embed(-1, 'stale'),
        throwsA(isA<LlamaStateException>()),
      );
      expect((await backend.getEmbeddingCapabilities(-1)).text, isFalse);
    },
  );
  test(
    'cancel during helper-isolate preflight prevents later dispatch',
    () async {
      final (backend, _, context) = await backendForTest();
      final pending = backend.embed(context, 'cancel before dispatch');
      backend.cancelGeneration();
      await expectLater(pending, throwsA(isA<LlamaInferenceException>()));
      expect(calls(), 0);
      expect(await backend.embed(context, 'reuse', normalize: false), [3, 4]);
    },
  );
  test(
    'temporary native input buffers are freed on success and allocation failure',
    () async {
      final session = await create();
      addTearDown(session.dispose);
      final baseline = allocations();
      for (final fault in [0, 2]) {
        mode(fault);
        final result = session.compute(
          input(),
          normalize: false,
          inputAllocator: _FakeAllocator(library),
        );
        if (fault == 0) {
          expect(await result, [3, 4]);
        } else {
          await expectLater(result, throwsA(isA<LlamaInferenceException>()));
        }
        expect(allocations(), baseline);
      }
    },
  );
  test('concurrent embeddings queue and both complete', () async {
    final (backend, _, context) = await backendForTest();
    expect(
      await Future.wait([
        backend.embed(context, 'first', normalize: false),
        backend.embed(context, 'second', normalize: false),
      ]),
      [
        [3, 4],
        [3, 4],
      ],
    );
  });
  for (final operation in ['cancel', 'unload', 'dispose']) {
    test(
      '$operation settles a multi-item batch after the current item',
      () async {
        final (backend, handle, context) = await backendForTest();
        mode(11);
        final pending = backend.embedBatch(context, List.filled(60, 'x'));
        final rejected = expectLater(
          pending,
          throwsA(isA<LlamaInferenceException>()),
        );
        await waitForCompute();
        final settlement = switch (operation) {
          'unload' => backend.contextFree(context),
          'dispose' => backend.dispose(),
          _ => Future<void>(() => backend.cancelGeneration()),
        };
        await Future<void>.delayed(const Duration(milliseconds: 20));
        release();
        await settlement;
        await rejected;
        expect(
          calls(),
          1,
          reason: 'cancel must prevent item 2 from entering native code',
        );
        mode(0);
        if (operation == 'cancel') {
          expect(await backend.embed(context, 'reuse', normalize: false), [
            3,
            4,
          ]);
        } else if (operation == 'unload') {
          await backend.modelFree(handle);
          final next = await backend.modelLoad(model, embeddingParams);
          final ctx = await backend.contextCreate(next, embeddingParams);
          expect(await backend.embed(ctx, 'reload', normalize: false), [3, 4]);
        }
      },
    );
  }
  test(
    'cancel suppresses the last native result and queued dispatch; reuse resets it',
    () async {
      final (backend, _, context) = await backendForTest();
      mode(11);
      final first = expectLater(
        backend.embed(context, 'active'),
        throwsA(isA<LlamaInferenceException>()),
      );
      await waitForCompute();
      final queued = expectLater(
        backend.embed(context, 'queued'),
        throwsA(isA<LlamaInferenceException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      backend.cancelGeneration();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      release();
      await Future.wait([first, queued]);
      expect(calls(), 1);
      mode(0);
      expect(await backend.embed(context, 'reuse', normalize: false), [3, 4]);
    },
  );
  test(
    'media preflight yields the caller and validates the whole batch before native work',
    () async {
      final (backend, _, context) = await backendForTest();
      var callerProgress = false;
      Timer.run(() => callerProgress = true);
      await expectLater(
        backend.embedContentBatch(context, [
          LlamaEmbeddingInput(const [LlamaTextContent('valid')]),
          LlamaEmbeddingInput([
            LlamaImageContent(
              bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
            ),
          ]),
        ]),
        throwsA(isA<LlamaInferenceException>()),
      );
      expect(callerProgress, isTrue);
      expect(calls(), 0);
    },
  );
  final ignoredOptions = <String, ModelParams>{
    'loras': embeddingParams.copyWith(
      loras: [const LoraAdapterConfig(path: 'adapter')],
    ),
    'chatTemplate': embeddingParams.copyWith(chatTemplate: 'ignored'),
    'liteRtLmActivationDataType': embeddingParams.copyWith(
      liteRtLmActivationDataType: LiteRtLmActivationDataType.float16,
    ),
    'liteRtLmPrefillChunkSize': embeddingParams.copyWith(
      liteRtLmPrefillChunkSize: 32,
    ),
    'liteRtLmParallelFileSectionLoading': embeddingParams.copyWith(
      liteRtLmParallelFileSectionLoading: false,
    ),
    'liteRtLmDispatchLibDir': embeddingParams.copyWith(
      liteRtLmDispatchLibDir: 'dispatch',
    ),
    'liteRtLmMaxProgramCacheBytes': embeddingParams.copyWith(
      liteRtLmMaxProgramCacheBytes: 0,
    ),
    'loadMtp': embeddingParams.copyWith(loadMtp: true),
    'speculativeRollbackTokenMax': embeddingParams.copyWith(
      speculativeRollbackTokenMax: 1,
    ),
    'preferMemory64': embeddingParams.copyWith(preferMemory64: true),
    'modelBytesHint': embeddingParams.copyWith(modelBytesHint: 42),
  };
  for (final entry in ignoredOptions.entries) {
    test(
      'embedding mode rejects ${entry.key} before model I/O and at context creation',
      () async {
        final service = LiteRtLmService();
        addTearDown(service.dispose);
        final matcher = throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'option and mode',
            allOf(contains(entry.key), contains('embedding mode')),
          ),
        );
        await expectLater(
          service.loadModel('${suite().path}/missing.litertlm', entry.value),
          matcher,
        );
        final handle = await service.loadModel(model, embeddingParams);
        expect(() => service.createContext(handle, entry.value), matcher);
      },
    );
  }
  test(
    'contextSize forwards the encoder signature length without truncating text',
    () async {
      final service = LiteRtLmService(
        clientFactory: () => LiteRtLmRuntimeClient(libraryPath: library),
      );
      addTearDown(service.dispose);
      final params = embeddingParams.copyWith(contextSize: 64);
      final handle = await service.loadModel(model, params);
      final context = service.createContext(handle, params);
      expect(
        await service.embed(context, [
          [LiteRtLmEmbeddingPart(0, Uint8List(256))],
        ], normalize: false),
        [
          [3, 4],
        ],
      );
      final limit = DynamicLibrary.open(
        library,
      ).lookupFunction<Int Function(), int Function()>('signature_limit');
      expect(limit(), 64);
      expect(calls(), 1);
    },
  );
  test(
    'creation failure releases the cache lease and disposes the client',
    () async {
      mode(10);
      final client = _FailingEmbeddingClient(library);
      final cache = await Directory(
        suite().path,
      ).createTemp('failed-embedding-cache');
      final service = LiteRtLmService(clientFactory: () => client);
      addTearDown(service.dispose);
      final params = embeddingParams.copyWith(liteRtLmCacheDir: cache.path);
      final modelHandle = await service.loadModel(model, params);
      final context = service.createContext(modelHandle, params);
      await expectLater(
        service.embeddingCapabilities(context),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(client.disposed, isTrue);
      expect(cache.listSync(), isEmpty);
    },
  );
  test(
    'production backend worker and service route embedding mode and reject chat',
    () async {
      final port = ReceivePort();
      final service = LiteRtLmService(
        clientFactory: () => LiteRtLmRuntimeClient(libraryPath: library),
      );
      runLiteRtLmWorkerForTesting(port.sendPort, service, exitOnDispose: false);
      final backend = LiteRtLmBackend(
        initialSendPort: await port.first as SendPort,
      );
      addTearDown(() async {
        await backend.dispose();
        port.close();
      });
      const params = ModelParams(
        liteRtLmEmbeddingEngine: true,
        device: ComputeDevice.cpu,
        contextSize: 1024,
        numberOfThreads: 2,
      );
      expect((await backend.getEmbeddingCapabilities(-1)).text, isFalse);
      final handle = await backend.modelLoad(model, params);
      final context = await backend.contextCreate(handle, params);
      expect((await backend.getEmbeddingCapabilities(context)).audio, isTrue);
      expect(await backend.embedBatch(context, ['a', 'b'], normalize: false), [
        [3, 4],
        [3, 4],
      ]);
      expect(await backend.embedContentBatch(context, []), isEmpty);
      await expectLater(
        backend.generate(context, 'x', const GenerationParams()).toList(),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      await expectLater(
        backend.tokenize(context, 'x'),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      await expectLater(
        backend.embedContentBatch(context, [
          LlamaEmbeddingInput(const [LlamaTextContent('valid')]),
          LlamaEmbeddingInput(const [
            LlamaImageContent(url: 'https://private.invalid'),
          ]),
        ]),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      mode(7);
      await expectLater(
        backend.embedBatch(context, ['valid', 'overflow']),
        throwsA(isA<LlamaInferenceException>()),
      );
      mode(0);
      await backend.contextFree(context);
      expect((await backend.getEmbeddingCapabilities(context)).text, isFalse);
      await backend.modelFree(handle);
      expect(backend.supportsEmbeddings, isFalse);
      expect(allocations(), 0);
    },
  );
  test('context cannot change the engine selected at model load', () async {
    final service = LiteRtLmService();
    addTearDown(service.dispose);
    for (final embedding in [true, false]) {
      final handle = await service.loadModel(
        model,
        ModelParams(
          liteRtLmEmbeddingEngine: embedding,
          device: ComputeDevice.cpu,
        ),
      );
      expect(
        () => service.createContext(
          handle,
          ModelParams(
            liteRtLmEmbeddingEngine: !embedding,
            device: ComputeDevice.cpu,
          ),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      service.freeModel(handle);
    }
  });
  for (final (kind, partType) in [
    ('tf_lite_vision_adapter', 1),
    ('tf_lite_audio_adapter', 3),
  ]) {
    test(
      'missing $kind fails whole-batch preflight before computation',
      () async {
        final bytes = Uint8List.fromList(embeddingBundleHeader());
        final needle = kind.codeUnits;
        for (var i = 0; i <= bytes.length - needle.length; i++) {
          if (List.generate(
            needle.length,
            (j) => bytes[i + j] == needle[j],
          ).every((v) => v)) {
            bytes[i] = 88;
          }
        }
        final bundle = File('${suite().path}/missing-$partType.litertlm');
        await bundle.writeAsBytes(bytes);
        final service = LiteRtLmService(
          clientFactory: () => LiteRtLmRuntimeClient(libraryPath: library),
        );
        addTearDown(service.dispose);
        const params = ModelParams(
          liteRtLmEmbeddingEngine: true,
          device: ComputeDevice.cpu,
          numberOfThreads: 2,
        );
        final handle = await service.loadModel(bundle.path, params);
        final context = service.createContext(handle, params);
        final caps = await service.embeddingCapabilities(context);
        expect(partType == 1 ? caps.image : caps.audio, isFalse);
        await expectLater(
          service.embed(context, [
            input(),
            [LiteRtLmEmbeddingPart(partType, Uint8List(1))],
          ], normalize: true),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        service.freeModel(handle);
        expect(allocations(), 0);
      },
    );
  }
  test(
    'native GPU load rejects the unsafe ABI before context or runtime work',
    () async {
      final service = LiteRtLmService();
      addTearDown(service.dispose);
      await expectLater(
        service.loadModel(
          model,
          const ModelParams(
            liteRtLmEmbeddingEngine: true,
            device: ComputeDevice.gpu,
          ),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'ABI diagnostic',
            allOf(contains('requalified on GPU'), contains('dd3db31236')),
          ),
        ),
      );
    },
  );
  test('rejects native GPU and NPU before native allocation', () async {
    for (final backend in ['gpu', 'npu']) {
      await expectLater(
        create(backend: backend),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'condition',
            backend == 'gpu' ? contains('dd3db31236') : contains('CPU'),
          ),
        ),
      );
      expect(allocations(), 0);
    }
  });
  int settingsCreates() => DynamicLibrary.open(
    library,
  ).lookupFunction<Int Function(), int Function()>('settings_creates')();
  for (final abi in [Abi.androidX64, Abi.windowsArm64]) {
    test('$abi rejects embedding loads on a custom runtime before any native '
        'call', () async {
      debugLiteRtLmAbiOverride = abi;
      final matcher = throwsA(
        isA<LlamaUnsupportedException>().having(
          (e) => e.message,
          'capability, platform and condition',
          allOf(
            contains('LiteRT-LM native embeddings are unsupported on $abi'),
            contains('they are not qualified there'),
            contains('every LiteRT-LM runtime library, including a custom one'),
            contains('Linux x64 and arm64, and Windows x64'),
            isNot(contains('pinned')),
          ),
        ),
      );
      await expectLater(create(), matcher);

      final port = ReceivePort();
      final service = LiteRtLmService(
        clientFactory: () => LiteRtLmRuntimeClient(libraryPath: library),
      );
      runLiteRtLmWorkerForTesting(port.sendPort, service, exitOnDispose: false);
      final backend = LiteRtLmBackend(
        initialSendPort: await port.first as SendPort,
      );
      port.close();
      addTearDown(backend.dispose);
      await expectLater(backend.modelLoad(model, embeddingParams), matcher);
      expect(backend.supportsEmbeddings, isFalse);
      expect(settingsCreates(), 0);
      expect(allocations(), 0);

      final chat = await backend.modelLoad(
        model,
        const ModelParams(device: ComputeDevice.cpu),
      );
      expect(chat, isPositive);
    });
  }
  for (final abi in [Abi.linuxArm64, Abi.linuxX64, Abi.windowsX64]) {
    test('$abi rejects embeddings on a legacy runtime before any native '
        'call', () async {
      debugLiteRtLmAbiOverride = abi;
      final matcher = throwsA(
        isA<LlamaUnsupportedException>().having(
          (e) => e.message,
          'capability, legacy runtime condition and required runtime',
          allOf(
            contains('LiteRT-LM native embeddings on $abi'),
            contains('C API 1 runtime from litert-lm-native v0.19.1-2'),
            contains('legacy one without litert_lm_get_api_version'),
            contains('v0.18.x'),
          ),
        ),
      );
      await expectLater(create(), matcher);

      final port = ReceivePort();
      final service = LiteRtLmService(
        clientFactory: () => LiteRtLmRuntimeClient(libraryPath: library),
      );
      runLiteRtLmWorkerForTesting(port.sendPort, service, exitOnDispose: false);
      final backend = LiteRtLmBackend(
        initialSendPort: await port.first as SendPort,
      );
      port.close();
      addTearDown(backend.dispose);
      final handle = await backend.modelLoad(model, embeddingParams);
      final context = await backend.contextCreate(handle, embeddingParams);
      await expectLater(backend.getEmbeddingCapabilities(context), matcher);
      expect(settingsCreates(), 0);
      expect(allocations(), 0);
    });
  }
  for (final abi in [Abi.macosArm64, Abi.iosArm64, Abi.androidArm64]) {
    test('$abi creates the embedding engine', () async {
      debugLiteRtLmAbiOverride = abi;
      final session = await create();
      expect(settingsCreates(), 1);
      expect(await session.compute(input(), normalize: false), [3, 4]);
      session.dispose();
      expect(allocations(), 0);
    });
  }
  test(
    'single-item compute copies pooled width, normalize and overflow-error options',
    () async {
      final LiteRtLmEmbeddingRuntimeSession session = await create();
      expect(processorBackends(), 3);
      expect(
        [
          session.capabilities.text,
          session.capabilities.image,
          session.capabilities.audio,
        ],
        [true, true, true],
      );
      expect(await session.compute(input(), normalize: true), [
        closeTo(0.6, 1e-6),
        closeTo(0.8, 1e-6),
      ]);
      expect(await session.compute(input(), normalize: false), [3, 4]);
      session.dispose();
      session.dispose();
      expect(allocations(), 0);
      expect(
        () => session.compute(input(), normalize: true),
        throwsA(isA<LlamaStateException>()),
      );
    },
  );
  for (final fault in [1, 2, 3, 4, 5, 6]) {
    test(
      'native fault $fault releases every allocated input option and response',
      () async {
        final session = await create();
        mode(fault);
        await expectLater(
          session.compute(input(), normalize: true),
          throwsA(isA<LlamaInferenceException>()),
        );
        mode(0);
        expect(await session.compute(input(), normalize: false), [3, 4]);
        session.dispose();
        expect(allocations(), 0);
      },
    );
  }
  test('settings and engine failures clean up', () async {
    for (final fault in [9, 10]) {
      mode(fault);
      await expectLater(create(), throwsA(isA<LlamaException>()));
      expect(allocations(), 0);
    }
  });
  test(
    'truncated and excessive native headers reject before C allocation',
    () async {
      for (final bytes in [
        Uint8List(1),
        Uint8List(32),
        Uint8List.fromList(embeddingBundleHeader())..[27] = 127,
      ]) {
        final bad = File('${suite().path}/bounds.litertlm');
        await bad.writeAsBytes(bytes);
        await expectLater(
          create(modelPath: bad.path),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(allocations(), 0);
      }
    },
  );

  for (final symbol in [
    'response_get_values',
    'options_set_input_overflow_strategy',
    'engine_settings_set_num_threads',
  ]) {
    test(
      'missing required embedding export $symbol fails before allocation',
      () async {
        final source = File('${suite().path}/missing-$symbol.c');
        await source.writeAsString(
          _source.replaceAll('litert_lm_embedding_$symbol', 'unused_$symbol'),
        );
        final path =
            '${suite().path}/missing-$symbol${Platform.isMacOS ? '.dylib' : '.so'}';
        final built = await Process.run('cc', [
          Platform.isMacOS ? '-dynamiclib' : '-shared',
          '-fPIC',
          source.path,
          '-o',
          path,
        ]);
        expect(built.exitCode, 0, reason: '${built.stderr}');
        final live = DynamicLibrary.open(
          path,
        ).lookupFunction<Int Function(), int Function()>('allocations');
        await expectLater(
          create(libraryPath: path),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'capability diagnostic',
              contains('single-input embedding C API'),
            ),
          ),
        );
        expect(live(), 0);
      },
    );
  }

  const batchOnly = [
    'engine_compute_embedding_batch',
    'responses_delete',
    'responses_get_size',
    'responses_get_at',
  ];
  for (final removed in [
    ...batchOnly.map((symbol) => [symbol]),
    batchOnly,
  ]) {
    test(
      'embedding does not require batch-only exports: ${removed.join(', ')}',
      () async {
        var variant = _source;
        for (final symbol in removed) {
          variant = variant.replaceAll(
            'litert_lm_embedding_$symbol',
            'unused_$symbol',
          );
        }
        final name = removed.length == 1 ? removed.single : 'all';
        final source = File('${suite().path}/no-$name.c');
        await source.writeAsString(variant);
        final path =
            '${suite().path}/no-$name${Platform.isMacOS ? '.dylib' : '.so'}';
        final built = await Process.run('cc', [
          Platform.isMacOS ? '-dynamiclib' : '-shared',
          '-fPIC',
          source.path,
          '-o',
          path,
        ]);
        expect(built.exitCode, 0, reason: '${built.stderr}');
        final session = await create(libraryPath: path);
        try {
          expect(await session.compute(input(), normalize: false), [3, 4]);
        } finally {
          session.dispose();
        }
        final live = DynamicLibrary.open(
          path,
        ).lookupFunction<Int Function(), int Function()>('allocations');
        expect(live(), 0);
      },
    );
  }

  test(
    'unknown bundle and old runtime fail before allocating an engine',
    () async {
      final bad = File('${suite().path}/bad.litertlm');
      await bad.writeAsBytes(Uint8List(32));
      await expectLater(
        create(modelPath: bad.path),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      final source = File('${suite().path}/old.c');
      await source.writeAsString(
        _source.replaceAll(
          'litert_lm_embedding_engine_compute_embedding',
          'old_compute',
        ),
      );
      final old = '${suite().path}/old${Platform.isMacOS ? '.dylib' : '.so'}';
      final result = await Process.run('cc', [
        Platform.isMacOS ? '-dynamiclib' : '-shared',
        '-fPIC',
        source.path,
        '-o',
        old,
      ]);
      expect(result.exitCode, 0);
      await expectLater(
        create(libraryPath: old),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(allocations(), 0);
    },
  );
}

class _FakeAllocator implements Allocator {
  final String library;
  _FakeAllocator(this.library);
  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) =>
      DynamicLibrary.open(library)
          .lookupFunction<
            Pointer<Void> Function(Size),
            Pointer<Void> Function(int)
          >('tracked_alloc')(byteCount)
          .cast<T>();
  @override
  void free(Pointer<NativeType> pointer) =>
      DynamicLibrary.open(library).lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('tracked_free')(pointer.cast());
}

class _FailingEmbeddingClient extends LiteRtLmRuntimeClient {
  bool disposed = false;
  _FailingEmbeddingClient(String library) : super(libraryPath: library);
  @override
  void dispose() => disposed = true;
}

const _source = r'''
#include <stdlib.h>
#include <stdatomic.h>
#include <unistd.h>
void* litert_lm_engine_settings_create(void){return NULL;}
#include <stddef.h>
#include <stdbool.h>
#include <math.h>
#include <string.h>
static int mode=0, processors=0, signature=0, settings_count=0;
int signature_limit(void){return signature;}
int settings_creates(void){return settings_count;}
static atomic_int live=0;
static atomic_int compute_count=0, released=0;
int compute_calls(void){return compute_count;}
void release_compute(void){released=1;}
int processor_backends(void){return processors;}
void set_mode(int n){mode=n;compute_count=0;released=0;settings_count=0;}
int allocations(void){return live;}
static void* alloc(void){live++;return calloc(1,16);}
static void del(void*p){if(p){live--;free(p);}}
void* tracked_alloc(size_t n){live++;return calloc(1,n);}
void tracked_free(void*p){del(p);}
void* litert_lm_embedding_engine_settings_create(const char*m,const char*b,const char*v,const char*a){settings_count++;processors=(v&&strcmp(v,"cpu")==0?1:0)|(a&&strcmp(a,"cpu")==0?2:0);return mode==9||strcmp(b,"cpu")!=0?NULL:alloc();}
void litert_lm_embedding_engine_settings_delete(void*p){del(p);}
void litert_lm_embedding_engine_settings_set_cache_dir(void*p,const char*s){}
void litert_lm_embedding_engine_settings_set_max_input_length(void*p,int n){signature=n;}
void litert_lm_embedding_engine_settings_set_num_threads(void*p,int n){((int*)p)[0]=n;}
void* litert_lm_embedding_engine_create(void*p){if(mode==12){compute_count++;while(!released)usleep(1000);}return mode==10||((int*)p)[0]!=2?NULL:alloc();}
void litert_lm_embedding_engine_delete(void*p){del(p);}
void* litert_lm_embedding_options_create(void){return mode==1?NULL:alloc();}
void litert_lm_embedding_options_delete(void*p){del(p);}
void litert_lm_embedding_options_set_normalize(void*p,bool n){((int*)p)[0]=n;}
void litert_lm_embedding_options_set_input_overflow_strategy(void*p,int n){((int*)p)[1]=n;}
void* litert_lm_input_data_create(int t,const void*d,size_t n){return mode==2?NULL:alloc();}
void litert_lm_input_data_delete(void*p){del(p);}
static float raw[2]={3,4}, normalized[2]={0.6f,0.8f}, invalid[2]={NAN,1};
void* litert_lm_embedding_engine_compute_embedding(void*e,const void*const*i,size_t n,const void*o){compute_count++; if(mode==11){while(!released)usleep(1000);} if(mode==3||(mode==7&&compute_count==2)||((int*)o)[1]!=2)return NULL;void*r=alloc();((int*)r)[0]=((int*)o)[0];return r;}
void litert_lm_embedding_response_delete(void*p){raw[0]=-999;raw[1]=-999;normalized[0]=-999;normalized[1]=-999;del(p);}
size_t litert_lm_embedding_response_get_size(const void*p){return mode==4?0:2;}
const float* litert_lm_embedding_response_get_values(const void*p){raw[0]=3;raw[1]=4;normalized[0]=0.6f;normalized[1]=0.8f;if(mode==5)return NULL;if(mode==6)return invalid;return ((int*)p)[0]?normalized:raw;}
void* litert_lm_embedding_engine_compute_embedding_batch(void*e,const void*const*const*i,const size_t*n,size_t b,const void*o){if(mode==7)return NULL;void*r=NULL;for(size_t j=0;j<b;j++){if(r)litert_lm_embedding_response_delete(r);r=litert_lm_embedding_engine_compute_embedding(e,NULL,0,o);if(!r)return NULL;}((int*)r)[1]=b;return r;}
size_t litert_lm_embedding_responses_get_size(const void*p){return mode==8?1:((int*)p)[1];}
const void* litert_lm_embedding_responses_get_at(const void*p,size_t i){return p;}
void litert_lm_embedding_responses_delete(void*p){del(p);}
''';
