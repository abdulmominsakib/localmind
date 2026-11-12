@TestOn('vm && (mac-os || linux)')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late DynamicLibrary library;
  final missing = <String, DynamicLibrary>{};
  int value(int index) =>
      library.lookupFunction<Int Function(Int), int Function(int)>(
        'fixture_value',
      )(index);
  int calls(int index) =>
      library.lookupFunction<Int Function(Int), int Function(int)>(
        'fixture_calls',
      )(index);
  int live() =>
      library.lookupFunction<Int Function(), int Function()>('fixture_live')();
  String text(int index) => library
      .lookupFunction<Pointer<Utf8> Function(Int), Pointer<Utf8> Function(int)>(
        'fixture_text',
      )(index)
      .toDartString();
  void fail(int stage) =>
      library.lookupFunction<Void Function(Int), void Function(int)>(
        'fixture_fail',
      )(stage);
  const fullCpu = LiteRtLmV1EngineSettings(
    backend: ComputeDevice.cpu,
    visionBackend: ComputeDevice.gpu,
    audioBackend: ComputeDevice.cpu,
    contextSize: 8192,
    numberOfThreads: 3,
    cacheDir: '/secret/cache',
    activationDataType: LiteRtLmActivationDataType.int8,
    prefillChunkSize: 64,
    parallelFileSectionLoading: false,
    prefillTokens: 17,
    speculativeDecoding: true,
  );
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('litert_v1_settings_');
    for (final entry in <String, List<String>>{
      'valid': [],
      'prefill': ['-DOMIT_PREFILL_CHUNK_SETTER'],
      'speculative': ['-DOMIT_ENGINE_SPECULATIVE_SETTER'],
    }.entries) {
      final path =
          '${directory.path}/${entry.key}.${Platform.isMacOS ? 'dylib' : 'so'}';
      final result = await Process.run('cc', [
        '-shared',
        '-fPIC',
        ...entry.value,
        'test/fixtures/litert_lm/c_api_v1_text.c',
        '-o',
        path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final candidate = DynamicLibrary.open(path);
      if (entry.key == 'valid') {
        library = candidate;
      } else {
        missing[entry.key] = candidate;
      }
    }
  });
  tearDownAll(() => directory.delete(recursive: true));
  setUp(() {
    expect(live(), 0);
    fail(0);
    library.lookupFunction<Void Function(), void Function()>(
      'fixture_reset_settings',
    )();
  });
  tearDown(() => expect(live(), 0));

  for (final device in [
    ComputeDevice.cpu,
    ComputeDevice.gpu,
    ComputeDevice.npu,
  ]) {
    test(
      'resolved ${device.name} transports without fallback or implicit CPU overrides',
      () {
        final runtime = LiteRtLmV1Runtime(library);
        runtime.loadConfigured(
          '/model',
          LiteRtLmV1EngineSettings(backend: device),
        );
        expect(text(1), device.name);
        expect(text(2), '<unset>');
        expect(text(3), '<unset>');
        expect(text(4), '<unset>');
        expect(value(0), 4096);
        expect(value(1), -1);
        expect(value(2), -1);
        expect(value(3), -1);
        expect(value(4), -1);
        expect(value(5), 1);
        expect(value(6), -1);
        expect(value(7), 0);
        expect(value(8), 0);
        expect(calls(2), 0);
        expect(calls(28), 0);
        expect(calls(34), 0);
        expect(live(), 1);
        runtime.dispose();
      },
    );
  }
  test(
    'CPU overrides and auxiliary backends reach native settings before engine creation',
    () {
      final runtime = LiteRtLmV1Runtime(library);
      runtime.loadConfigured('/secret/models/m.litertlm', fullCpu);
      expect(
        [for (var i = 0; i < 9; i++) value(i)],
        [8192, 3, 0, 3, 64, 1, 17, 1, 0],
      );
      expect(
        [for (var i = 0; i < 6; i++) text(i)],
        [
          '/secret/models/m.litertlm',
          'cpu',
          'gpu',
          'cpu',
          '/secret/cache',
          '<unset>',
        ],
      );
      expect(calls(34), 0);
      expect(live(), 1);
      runtime.dispose();
    },
  );
  test(
    'NPU dispatch path and auxiliary backend strings are retained through creation',
    () {
      final runtime = LiteRtLmV1Runtime(library);
      runtime.loadConfigured(
        '/model',
        const LiteRtLmV1EngineSettings(
          backend: ComputeDevice.npu,
          visionBackend: ComputeDevice.npu,
          audioBackend: ComputeDevice.gpu,
          dispatchLibDir: '/secret/dispatch',
        ),
      );
      expect(
        [text(1), text(2), text(3), text(5)],
        ['npu', 'npu', 'gpu', '/secret/dispatch'],
      );
      expect(value(7), 0);
      runtime.dispose();
    },
  );
  for (final activation in LiteRtLmActivationDataType.values) {
    test(
      'activation ${activation.name} uses its maintained native wire value',
      () {
        final runtime = LiteRtLmV1Runtime(library);
        runtime.loadConfigured(
          '/model',
          LiteRtLmV1EngineSettings(activationDataType: activation),
        );
        expect(value(3), activation.nativeValue);
        runtime.dispose();
      },
    );
  }
  test(
    'explicit parallel true and benchmark false preserve their distinct requests',
    () {
      final runtime = LiteRtLmV1Runtime(library);
      runtime.loadConfigured(
        '/model',
        const LiteRtLmV1EngineSettings(
          parallelFileSectionLoading: true,
          enableBenchmark: false,
        ),
      );
      expect(value(2), 1);
      expect(value(5), 0);
      expect(value(6), -1);
      expect(calls(25), 0);
      expect(calls(29), 0);
      runtime.dispose();
    },
  );
  test(
    'GPU speculation on is explicit and never installs CPU-only controls',
    () {
      final runtime = LiteRtLmV1Runtime(library);
      runtime.loadConfigured(
        '/model',
        const LiteRtLmV1EngineSettings(
          backend: ComputeDevice.gpu,
          speculativeDecoding: true,
        ),
      );
      expect(text(1), 'gpu');
      expect(value(7), 1);
      expect(calls(2), 0);
      expect(calls(28), 0);
      runtime.dispose();
    },
  );

  for (final entry in <String, LiteRtLmV1EngineSettings>{
    'auto main backend': const LiteRtLmV1EngineSettings(
      backend: ComputeDevice.auto,
    ),
    'auto vision backend': const LiteRtLmV1EngineSettings(
      visionBackend: ComputeDevice.auto,
    ),
    'auto audio backend': const LiteRtLmV1EngineSettings(
      audioBackend: ComputeDevice.auto,
    ),
    'GPU threads': const LiteRtLmV1EngineSettings(
      backend: ComputeDevice.gpu,
      numberOfThreads: 2,
    ),
    'NPU threads': const LiteRtLmV1EngineSettings(
      backend: ComputeDevice.npu,
      numberOfThreads: 2,
    ),
    'GPU prefill chunks': const LiteRtLmV1EngineSettings(
      backend: ComputeDevice.gpu,
      prefillChunkSize: 64,
    ),
    'NPU prefill chunks': const LiteRtLmV1EngineSettings(
      backend: ComputeDevice.npu,
      prefillChunkSize: 64,
    ),
    'CPU dispatch': const LiteRtLmV1EngineSettings(
      dispatchLibDir: '/secret/dispatch',
    ),
    'GPU dispatch': const LiteRtLmV1EngineSettings(
      backend: ComputeDevice.gpu,
      dispatchLibDir: '/secret/dispatch',
    ),
    'NPU speculation': const LiteRtLmV1EngineSettings(
      backend: ComputeDevice.npu,
      speculativeDecoding: true,
    ),
    'legacy-only image capacity': const LiteRtLmV1EngineSettings(
      maxNumImages: 2,
    ),
  }.entries) {
    test(
      '${entry.key} refuses before native allocation and preserves the active engine',
      () {
        final runtime = LiteRtLmV1Runtime(library);
        runtime.load('/model', cacheDir: '/cache');
        final before = calls(1);
        expect(
          () => runtime.loadConfigured('/model', entry.value),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(calls(1), before);
        expect(live(), 1);
        expect(runtime.generateText('old engine'), 'old engine');
        runtime.dispose();
      },
    );
  }
  for (final entry in <String, LiteRtLmV1EngineSettings>{
    'context zero': const LiteRtLmV1EngineSettings(contextSize: 0),
    'context overflow': const LiteRtLmV1EngineSettings(contextSize: 0x80000000),
    'threads zero': const LiteRtLmV1EngineSettings(numberOfThreads: 0),
    'threads overflow': const LiteRtLmV1EngineSettings(
      numberOfThreads: 0x80000000,
    ),
    'prefill chunk negative': const LiteRtLmV1EngineSettings(
      prefillChunkSize: -1,
    ),
    'prefill chunk overflow': const LiteRtLmV1EngineSettings(
      prefillChunkSize: 0x80000000,
    ),
    'prefill count zero': const LiteRtLmV1EngineSettings(prefillTokens: 0),
    'prefill count overflow': const LiteRtLmV1EngineSettings(
      prefillTokens: 0x80000000,
    ),
    'image count zero': const LiteRtLmV1EngineSettings(maxNumImages: 0),
    'empty cache': const LiteRtLmV1EngineSettings(cacheDir: ''),
    'NUL cache': const LiteRtLmV1EngineSettings(
      cacheDir: '/secret/\u0000cache',
    ),
    'blank dispatch': const LiteRtLmV1EngineSettings(
      backend: ComputeDevice.npu,
      dispatchLibDir: ' ',
    ),
    'NUL dispatch': const LiteRtLmV1EngineSettings(
      backend: ComputeDevice.npu,
      dispatchLibDir: '/secret/\u0000dispatch',
    ),
    'benchmark conflict': const LiteRtLmV1EngineSettings(
      enableBenchmark: false,
      prefillTokens: 2,
    ),
  }.entries) {
    test('${entry.key} is typed invalid before native allocation', () {
      final runtime = LiteRtLmV1Runtime(library);
      expect(
        () => runtime.loadConfigured('/model', entry.value),
        throwsA(isA<LlamaArgumentException>()),
      );
      expect(calls(1), 0);
      runtime.dispose();
    });
  }
  for (final stage in [1, 2, 3, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30]) {
    test(
      'settings status failure $stage frees owned temporaries and preserves old engine and error',
      () {
        final runtime = LiteRtLmV1Runtime(library);
        runtime.load('/model', cacheDir: '/cache');
        final creates = calls(1);
        fail(stage);
        expect(
          () => runtime.loadConfigured(
            '/secret/models/m.litertlm',
            stage == 30
                ? const LiteRtLmV1EngineSettings(
                    backend: ComputeDevice.npu,
                    cacheDir: '/secret/cache',
                    dispatchLibDir: '/secret/dispatch',
                  )
                : fullCpu,
          ),
          throwsA(
            isA<LlamaModelException>().having(
              (error) => error.message,
              'original redacted native error',
              allOf(
                contains('stage$stage'),
                isNot(contains('cleanup overwrote')),
                isNot(contains('/secret')),
              ),
            ),
          ),
        );
        expect(calls(1), creates + 1);
        expect(live(), 1);
        fail(0);
        expect(runtime.generateText('recovered'), 'recovered');
        runtime.loadConfigured('/model', const LiteRtLmV1EngineSettings());
        expect(live(), 1);
        runtime.dispose();
      },
    );
  }
  for (final stage in [31, 32, 33]) {
    test(
      'null success $stage refuses without leaking or replacing the old engine',
      () {
        final runtime = LiteRtLmV1Runtime(library);
        runtime.load('/model', cacheDir: '/cache');
        fail(stage);
        expect(
          () => runtime.loadConfigured('/model', fullCpu),
          throwsA(isA<LlamaStateException>()),
        );
        expect(live(), 1);
        fail(0);
        expect(runtime.generateText('recovered'), 'recovered');
        runtime.dispose();
      },
    );
  }
  test(
    'configured load rejects invalid model paths and disposed use before native allocation',
    () {
      final runtime = LiteRtLmV1Runtime(library);
      for (final path in ['', ' ', '/secret/\u0000model']) {
        expect(
          () => runtime.loadConfigured(path, const LiteRtLmV1EngineSettings()),
          throwsA(isA<LlamaArgumentException>()),
        );
        expect(calls(1), 0);
      }
      runtime.dispose();
      expect(
        () =>
            runtime.loadConfigured('/model', const LiteRtLmV1EngineSettings()),
        throwsA(isA<LlamaStateException>()),
      );
    },
  );
  test('signed C int maximum is preserved without truncation', () {
    final runtime = LiteRtLmV1Runtime(library);
    runtime.loadConfigured(
      '/model',
      const LiteRtLmV1EngineSettings(
        contextSize: 0x7fffffff,
        numberOfThreads: 0x7fffffff,
        prefillChunkSize: 0x7fffffff,
        prefillTokens: 0x7fffffff,
      ),
    );
    for (final index in [0, 1, 4, 6]) {
      expect(value(index), 0x7fffffff);
    }
    runtime.dispose();
  });

  for (final name in ['prefill', 'speculative']) {
    test('missing $name export refuses before settings allocation', () {
      final selected = missing[name]!;
      expect(
        () => LiteRtLmV1Runtime(selected),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(
        selected.lookupFunction<Int Function(), int Function()>(
          'fixture_live',
        )(),
        0,
      );
      expect(
        selected.lookupFunction<Int Function(Int), int Function(int)>(
          'fixture_calls',
        )(1),
        0,
      );
    });
  }
}
