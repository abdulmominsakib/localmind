@TestOn('vm && (mac-os || linux)')
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_embedding.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime_client_contract.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';
import 'package:test/test.dart';

import '../../../support/dart_script_snapshot.dart';
import '../../../support/suite_system_temp.dart';
import 'litert_lm_embedding_test.dart' as fixtures;

void main() {
  final suite = useSuiteSystemTemp();
  late DynamicLibrary library;
  late DynamicLibrary missing;
  late String libraryPath;
  late String unmarkedPath;
  late String model;
  int count(String name, [DynamicLibrary? from]) =>
      (from ?? library).lookupFunction<Int Function(), int Function()>(
        'fixture_embedding_$name',
      )();
  void set(String name, int value) =>
      library.lookupFunction<Void Function(Int), void Function(int)>(
        'fixture_embedding_$name',
      )(value);
  LiteRtLmV1RuntimeClient client([DynamicLibrary? selected]) {
    final value = LiteRtLmV1RuntimeClient(selected ?? library);
    addTearDown(value.dispose);
    return value;
  }

  Future<LiteRtLmEmbeddingRuntimeSession> create(
    LiteRtLmV1RuntimeClient value, {
    String backend = 'cpu',
    String? path,
  }) => value.createEmbeddingSession(
    modelPath: path ?? model,
    backend: backend,
    cacheDir: '/secret/cache',
    maxInputLength: 1024,
    numberOfThreads: 2,
  );
  List<LiteRtLmEmbeddingPart> input() => [
    LiteRtLmEmbeddingPart(0, Uint8List.fromList([65, 0, 66])),
  ];
  setUpAll(() async {
    for (final omit in [false, true]) {
      final path =
          '${suite().path}/${omit ? 'missing' : 'embedding'}.${Platform.isMacOS ? 'dylib' : 'so'}';
      final result = await Process.run('cc', [
        '-shared',
        '-fPIC',
        '-pthread',
        if (omit) '-DOMIT_EMBEDDING_VALUES',
        'test/fixtures/litert_lm/c_api_v1_embedding.c',
        '-o',
        path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      if (omit) {
        missing = DynamicLibrary.open(path);
      } else {
        libraryPath = path;
        library = DynamicLibrary.open(path);
      }
    }
    unmarkedPath =
        '${suite().path}/unmarked.${Platform.isMacOS ? 'dylib' : 'so'}';
    final unmarked = await Process.run('cc', [
      '-shared',
      '-fPIC',
      '-pthread',
      '-DOMIT_IN_PROCESS_LITERT_MARKER',
      'test/fixtures/litert_lm/c_api_v1_embedding.c',
      '-o',
      unmarkedPath,
    ]);
    expect(unmarked.exitCode, 0, reason: '${unmarked.stderr}');
    model = '${suite().path}/model.litertlm';
    File(model).writeAsBytesSync(fixtures.embeddingBundleHeader());
  });
  setUp(() {
    debugLiteRtLmAbiOverride = Abi.macosArm64;
    set('fault', 0);
    set('delay', 0);
    set('in_process_litert', 1);
    expect(count('count'), 0);
    addTearDown(() => debugLiteRtLmAbiOverride = null);
  });

  for (final unsettled in [false, true]) {
    test(
      'service retains only unsettled embedding creation resources ($unsettled)',
      () async {
        final fake = _BlockedEmbeddingClient();
        final cache = Directory('${suite().path}/cache-$unsettled')
          ..createSync();
        final service = LiteRtLmService(runtimeClientFactory: () => fake);
        final params = ModelParams(
          liteRtLmEmbeddingEngine: true,
          device: ComputeDevice.cpu,
          liteRtLmCacheDir: cache.path,
        );
        final handle = await service.loadModel(model, params);
        final context = service.createContext(handle, params);
        final pending = service.embeddingCapabilities(context);
        final failed = expectLater(
          pending,
          throwsA(isA<LlamaInferenceException>()),
        );
        expect(service.nativeSettlement, LiteRtLmNativeSettlement.pending);
        expect(service.dispose, throwsA(isA<LlamaStateException>()));
        await expectLater(
          service.embeddingCapabilities(context),
          throwsA(isA<LlamaStateException>()),
        );
        expect(fake.creations, 1);
        final files = cache
            .listSync(recursive: true)
            .whereType<File>()
            .map((file) => file.path)
            .toList();
        expect(files, isNotEmpty);
        fake.settlement = unsettled
            ? LiteRtLmNativeSettlement.quarantined
            : LiteRtLmNativeSettlement.settled;
        fake.result.completeError(
          LlamaInferenceException('fixture transport failed'),
        );
        await failed;
        if (unsettled) {
          expect(
            service.nativeSettlement,
            LiteRtLmNativeSettlement.quarantined,
          );
          expect(fake.disposals, 0);
          expect(service.dispose, throwsA(isA<LlamaStateException>()));
          expect(files.every((path) => File(path).existsSync()), isTrue);
        } else {
          expect(fake.disposals, 1);
          expect(files.any((path) => File(path).existsSync()), isFalse);
          service.dispose();
        }
      },
    );
  }

  test(
    'status/out ABI preserves vectors, modalities and copied response bytes',
    () async {
      final value = client();
      final session = await create(value);
      expect(
        [
          session.capabilities.text,
          session.capabilities.image,
          session.capabilities.audio,
        ],
        [true, true, true],
      );
      expect(
        [count('threads'), count('context'), count('vision'), count('audio')],
        [2, 1024, 1, 1],
      );
      final vector = await session.compute([
        ...input(),
        LiteRtLmEmbeddingPart(1, Uint8List.fromList([1, 2])),
        LiteRtLmEmbeddingPart(3, Uint8List.fromList([3, 4, 5])),
      ], normalize: false);
      expect(vector, [3, 4, 0]);
      expect(count('types'), 11);
      expect(
        library.lookupFunction<Size Function(), int Function()>(
          'fixture_embedding_byte_count',
        )(),
        8,
      );
      expect(count('count'), 1);
      final normalized = await session.compute(input(), normalize: true);
      expect(normalized[0], closeTo(.6, .00001));
      expect(normalized[1], closeTo(.8, .00001));
      session.dispose();
      expect(vector, [3, 4, 0]);
      expect(count('count'), 0);
      value.dispose();
    },
  );

  test('embedding C int settings reject overflow before allocation', () async {
    final value = client();
    final before = count('call_count');
    for (final pair in [
      (0, 2),
      (-1, 2),
      (0x80000000, 2),
      (0x100000001, 2),
      (1024, -1),
      (1024, 0x80000000),
      (1024, 0x100000002),
    ]) {
      await expectLater(
        value.createEmbeddingSession(
          modelPath: model,
          backend: 'cpu',
          cacheDir: '/secret/cache',
          maxInputLength: pair.$1,
          numberOfThreads: pair.$2,
        ),
        throwsA(isA<LlamaArgumentException>()),
      );
    }
    expect(count('call_count'), before);
    final session = await value.createEmbeddingSession(
      modelPath: model,
      backend: 'cpu',
      cacheDir: '/secret/cache',
      maxInputLength: 0x7fffffff,
      numberOfThreads: 0x7fffffff,
    );
    expect([count('context'), count('threads')], [0x7fffffff, 0x7fffffff]);
    session.dispose();
  });

  for (final stage in [1, 2, 3, 4, 5, 101, 105, 201, 205]) {
    test(
      'creation failure $stage releases partial owners and snapshots TLS',
      () async {
        set('fault', stage);
        final value = client();
        await expectLater(
          create(value),
          throwsA(
            isA<LlamaException>().having(
              (error) => error.toString(),
              'copied error',
              allOf(
                isNot(contains('cleanup replaced')),
                isNot(contains('/secret/cache')),
                stage <= 12 || stage >= 200
                    ? contains('stage${stage % 200}')
                    : anything,
              ),
            ),
          ),
        );
        expect(value.nativeSettlement, LiteRtLmNativeSettlement.settled);
        expect(count('count'), 0);
      },
    );
  }
  for (final stage in [
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    106,
    109,
    110,
    206,
    209,
    210,
  ]) {
    test('compute failure $stage releases results and allows retry', () async {
      final session = await create(client());
      set('fault', stage);
      await expectLater(
        session.compute(input(), normalize: false),
        throwsA(
          isA<LlamaException>().having(
            (error) => error.toString(),
            'copied error',
            allOf(
              isNot(contains('cleanup replaced')),
              isNot(contains('/secret/cache')),
              stage <= 12 || stage >= 200
                  ? contains('stage${stage % 200}')
                  : anything,
            ),
          ),
        ),
      );
      expect(count('count'), 1);
      set('fault', 0);
      expect(await session.compute(input(), normalize: false), [3, 4, 0]);
    });
  }
  for (final abi in [Abi.linuxArm64, Abi.linuxX64, Abi.windowsX64]) {
    test('$abi creates the embedding engine on the selected C API 1 '
        'runtime', () async {
      debugLiteRtLmAbiOverride = abi;
      final selected = LiteRtLmRuntimeClient(libraryPath: libraryPath);
      addTearDown(selected.dispose);
      final session = await selected.createEmbeddingSession(
        modelPath: model,
        backend: 'cpu',
        cacheDir: '/secret/cache',
        maxInputLength: 1024,
        numberOfThreads: 2,
      );
      expect(await session.compute(input(), normalize: false), [3, 4, 0]);
      session.dispose();
      expect(count('count'), 0);
    });
  }
  Future<LiteRtLmEmbeddingRuntimeSession> createSelected(String path) {
    final selected = LiteRtLmRuntimeClient(libraryPath: path);
    addTearDown(selected.dispose);
    return selected.createEmbeddingSession(
      modelPath: model,
      backend: 'cpu',
      cacheDir: '/secret/cache',
      maxInputLength: 1024,
      numberOfThreads: 2,
    );
  }

  for (final abi in [Abi.linuxArm64, Abi.linuxX64, Abi.windowsX64]) {
    for (final marker in <int?>[null, 0, 2, -1]) {
      test('$abi refuses in-process LiteRT marker $marker before any native '
          'embedding call', () async {
        debugLiteRtLmAbiOverride = abi;
        if (marker != null) set('in_process_litert', marker);
        final runtime = DynamicLibrary.open(
          marker == null ? unmarkedPath : libraryPath,
        );
        final before = count('call_count', runtime);
        await expectLater(
          createSelected(marker == null ? unmarkedPath : libraryPath),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('native embeddings on $abi'),
                contains('LiteRT compiled into the runtime'),
                contains('litert-lm-native v0.19.1-2'),
                contains(
                  marker == null
                      ? 'does not export'
                      : 'reports litert_lm_native_in_process_litert_abi_version '
                            '$marker',
                ),
              ),
            ),
          ),
        );
        expect(
          [
            count('call_count', runtime),
            count('entered', runtime),
            count('count', runtime),
          ],
          [before, 0, 0],
        );
      });
    }
    test('$abi refuses a directly constructed client without a marker '
        'value', () async {
      debugLiteRtLmAbiOverride = abi;
      final before = count('call_count');
      await expectLater(
        create(client()),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(count('call_count'), before);
    });
  }
  group('LLAMADART_LITERT_LM_LIB_DIR route', () {
    late String script;
    setUpAll(
      () async => script = await compileDartScript(
        'test/fixtures/litert_lm_v1_env_dir_embedding.dart',
      ),
    );

    Future<String> createFromEnvironmentDirectory(
      String runtimePath,
      Abi abi,
    ) async {
      final runtime = Directory(
        '${suite().path}/env-dir-${runtimePath.hashCode}',
      )..createSync();
      final primary = liteRtLmPrimaryLibraryForAbi(Abi.current())!;
      File(runtimePath).copySync('${runtime.path}/$primary');
      final stub = File('${runtime.path}/stub.c')
        ..writeAsStringSync('int fixture_companion_stub(void) { return 1; }\n');
      final stubLibrary = '${runtime.path}/stub.bin';
      final built = await Process.run('cc', [
        '-shared',
        '-fPIC',
        stub.path,
        '-o',
        stubLibrary,
      ]);
      expect(built.exitCode, 0, reason: '${built.stderr}');
      for (final name in liteRtLmRequiredLibrariesForAbi(
        Abi.current(),
      ).where((name) => name != primary)) {
        File(stubLibrary).copySync('${runtime.path}/$name');
      }
      final result = await Process.run(
        Platform.resolvedExecutable,
        [script, '$abi', model, '${runtime.path}/cache'],
        environment: {
          'LLAMADART_LITERT_LM_LIB_DIR': runtime.path,
          'TMPDIR': suite().path,
        },
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      return '${result.stdout}';
    }

    for (final abi in [Abi.linuxArm64, Abi.linuxX64, Abi.windowsX64]) {
      test('$abi refuses an unmarked runtime selected by the environment '
          'directory', () async {
        final output = await createFromEnvironmentDirectory(unmarkedPath, abi);
        expect(output, contains('LlamaUnsupportedException'));
        expect(output, contains('native embeddings on $abi'));
        expect(output, contains('does not export'));
      });
    }

    test('linux_x64 admits a marked runtime selected by the environment '
        'directory', () async {
      expect(
        await createFromEnvironmentDirectory(libraryPath, Abi.linuxX64),
        contains('ENV_DIR_EMBEDDING created'),
      );
    });
  });
  for (final abi in [Abi.macosArm64, Abi.iosArm64, Abi.androidArm64]) {
    test(
      '$abi creates embeddings without the in-process LiteRT marker',
      () async {
        debugLiteRtLmAbiOverride = abi;
        final runtime = DynamicLibrary.open(unmarkedPath);
        final unmarked = await createSelected(unmarkedPath);
        expect(await unmarked.compute(input(), normalize: false), [3, 4, 0]);
        unmarked.dispose();
        expect(count('count', runtime), 0);
        set('in_process_litert', 0);
        final reportsZero = await createSelected(libraryPath);
        expect(await reportsZero.compute(input(), normalize: false), [3, 4, 0]);
        reportsZero.dispose();
        expect(count('count'), 0);
      },
    );
  }
  test(
    'missing export, unsupported target/backend and invalid bundle allocate nothing',
    () async {
      await expectLater(
        create(client(missing)),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      final value = client();
      final before = count('call_count');
      await expectLater(
        create(value, backend: 'gpu'),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      debugLiteRtLmAbiOverride = Abi.androidX64;
      await expectLater(
        create(value),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      debugLiteRtLmAbiOverride = Abi.macosArm64;
      final invalid = File('${suite().path}/invalid')..writeAsBytesSync([1, 2]);
      await expectLater(
        create(value, path: invalid.path),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(count('call_count'), before);
    },
  );
  test(
    'creation and compute keep event loop live and reject teardown while pending',
    () async {
      set('delay', 150);
      final value = client();
      final pending = create(value);
      expect(value.nativeSettlement, LiteRtLmNativeSettlement.pending);
      expect(value.dispose, throwsA(isA<LlamaStateException>()));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(value.nativeSettlement, LiteRtLmNativeSettlement.pending);
      final session = await pending;
      final result = session.compute(input(), normalize: false);
      expect(value.nativeSettlement, LiteRtLmNativeSettlement.pending);
      expect(session.dispose, throwsA(isA<LlamaStateException>()));
      await expectLater(
        session.compute(input(), normalize: false),
        throwsA(isA<LlamaStateException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(value.nativeSettlement, LiteRtLmNativeSettlement.pending);
      expect(await result, [3, 4, 0]);
      expect(value.nativeSettlement, LiteRtLmNativeSettlement.settled);
    },
  );
}

final class _BlockedEmbeddingClient implements LiteRtLmRuntimeClientContract {
  final result = Completer<LiteRtLmEmbeddingRuntimeSession>();
  LiteRtLmNativeSettlement settlement = LiteRtLmNativeSettlement.settled;
  int creations = 0;
  int disposals = 0;
  @override
  LiteRtLmNativeSettlement get nativeSettlement => settlement;
  @override
  Future<LiteRtLmEmbeddingRuntimeSession> createEmbeddingSession({
    required String modelPath,
    required String backend,
    required String cacheDir,
    required int maxInputLength,
    required int numberOfThreads,
  }) {
    creations++;
    return result.future;
  }

  @override
  void dispose() {
    disposals++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
