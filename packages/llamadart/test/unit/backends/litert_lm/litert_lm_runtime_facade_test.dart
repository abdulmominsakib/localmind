@TestOn('vm && (mac-os || linux)')
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_legacy_service_client.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime_client_contract.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';
import 'package:llamadart/src/core/speech/litert_lm_speech_to_text_driver_io.dart';
import 'package:test/test.dart';

LiteRtLmRuntimeClientContract _stagedSpeech(String? path) =>
    LiteRtLmLegacyServiceClient(
      createLiteRtLmSelectedRuntimeClient(
        libraryPath: path,
        allowV1: true,
        eager: true,
      ),
    );

LiteRtLmRuntimeClientContract _stagedOldMacSpeech(String? path) =>
    createLiteRtLmSelectedServiceClient(
      libraryPath: path,
      allowV1: true,
      macOsVersion: 'Version 13.7',
      eager: true,
    );

void main() {
  late Directory directory;
  final paths = <String, String>{};
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('litert_selected_');
    for (final entry in {
      'legacy': 'c_api_legacy_service.c',
      'v1': 'c_api_v1_public_dispatch.c',
      'missing': 'c_api_version.c',
    }.entries) {
      final path =
          '${directory.path}/${entry.key}.${Platform.isMacOS ? 'dylib' : 'so'}';
      final result = await Process.run('cc', [
        '-shared',
        '-fPIC',
        '-pthread',
        'test/fixtures/litert_lm/${entry.value}',
        '-o',
        path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      paths[entry.key] = path;
    }
    for (final entry in {
      'validation-v1': '-DFACADE_V1',
      'validation-legacy': '-DFACADE_LEGACY',
      'validation-companion': '-DFACADE_COMPANION',
    }.entries) {
      final path = '${directory.path}/${entry.key}';
      final result = await Process.run('cc', [
        '-shared',
        '-fPIC',
        '-pthread',
        entry.value,
        'test/fixtures/litert_lm/facade_validation_fixture.c',
        '-o',
        path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      paths[entry.key] = path;
    }
  });
  tearDownAll(() => directory.delete(recursive: true));

  for (final mode in ['default', 'v1', 'legacy', 'legacy-disabled']) {
    test(
      '$mode validates before any library open or engine creation',
      () async {
        final primary =
            paths[mode == 'legacy' || mode == 'legacy-disabled'
                ? 'validation-legacy'
                : 'validation-v1']!;
        final libraryDir = Directory('${directory.path}/validation-$mode-dir')
          ..createSync();
        for (final library in liteRtLmRequiredLibrariesForAbi(
          Abi.current(),
          cApiV1: true,
        )) {
          File(
            library == liteRtLmPrimaryLibraryForAbi(Abi.current())
                ? primary
                : paths['validation-companion']!,
          ).copySync('${libraryDir.path}/$library');
        }
        final result = await Process.run(
          Platform.resolvedExecutable,
          [
            '--packages=.dart_tool/package_config.json',
            'test/fixtures/litert_lm/facade_validation_probe.dart',
            mode,
            primary,
          ],
          environment: {'LLAMADART_LITERT_LM_LIB_DIR': libraryDir.path},
        );
        final output = '${result.stderr}';
        expect(result.exitCode, 0, reason: '${result.stdout}\n$output');
        final invalid = output.indexOf('FACADE_INVALID_COMPLETE');
        final opened = output.indexOf('FACADE_LIBRARY_OPEN');
        final engine = output.indexOf('FACADE_ENGINE_CREATE');
        final valid = output.indexOf('FACADE_VALID_COMPLETE');
        expect(invalid, isNonNegative, reason: output);
        expect(opened, greaterThan(invalid), reason: output);
        expect(engine, greaterThan(opened), reason: output);
        expect(valid, greaterThan(engine), reason: output);
        expect(RegExp('FACADE_ENGINE_CREATE').allMatches(output), hasLength(1));
      },
    );
  }

  test('invalid arguments precede public platform refusal', () async {
    debugLiteRtLmAbiOverride = Abi.macosX64;
    addTearDown(() => debugLiteRtLmAbiOverride = null);
    final client = LiteRtLmRuntimeClient();
    addTearDown(client.dispose);
    await expectLater(
      client.initialize(modelPath: 'fixture', maxTokens: 0),
      throwsA(
        isA<ArgumentError>().having((error) => error.name, 'name', 'maxTokens'),
      ),
    );
    expect(
      () => client.generate('hello', maxOutputTokens: 0),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.name,
          'name',
          'maxOutputTokens',
        ),
      ),
    );
    expect(
      () => client.generateMessageJson('{}', visualTokenBudget: 0),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.name,
          'name',
          'visualTokenBudget',
        ),
      ),
    );
    await expectLater(
      client.run(prompt: 'hello', measuredRuns: 0),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.name,
          'name',
          'measuredRuns',
        ),
      ),
    );
    await expectLater(
      client.initialize(modelPath: 'fixture', backend: 'cpu'),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'platform refusal',
          contains('macOS x86_64'),
        ),
      ),
    );
  });

  test(
    'explicit legacy path preserves compatibility on an unsupported published ABI',
    () async {
      debugLiteRtLmAbiOverride = Abi.macosX64;
      addTearDown(() => debugLiteRtLmAbiOverride = null);
      final client = LiteRtLmRuntimeClient(libraryPath: paths['legacy']);
      try {
        await client.initialize(
          modelPath: 'fixture',
          backend: 'cpu',
          speculativeDecoding: false,
        );
        expect(client.nativeSettlement, LiteRtLmNativeSettlement.settled);
      } finally {
        client.dispose();
      }
    },
  );

  test(
    'explicit v1 path rejects an unsupported ABI before creating an engine',
    () async {
      debugLiteRtLmAbiOverride = Abi.macosX64;
      addTearDown(() => debugLiteRtLmAbiOverride = null);
      final library = DynamicLibrary.open(paths['v1']!);
      final attempts = library.lookupFunction<Int Function(), int Function()>(
        'fixture_public_engine_attempts',
      );
      final before = attempts();
      final client = LiteRtLmRuntimeClient(libraryPath: paths['v1']);
      try {
        await expectLater(
          client.initialize(modelPath: 'fixture', backend: 'cpu'),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'unsupported ABI',
              contains('macOS x86_64'),
            ),
          ),
        );
        expect(attempts(), before);
      } finally {
        client.dispose();
      }
    },
  );

  test('public facade lazily selects v1 and releases its engine', () async {
    final client = LiteRtLmRuntimeClient(libraryPath: paths['v1']);
    expect(client.nativeSettlement, LiteRtLmNativeSettlement.settled);
    expect(client.supportsFinishReasons, isTrue);
    await client.initialize(
      modelPath: 'unused',
      backend: 'cpu',
      speculativeDecoding: false,
    );
    expect(client.tokenize('hello', addSpecial: false), [5, 104, 111]);
    client.dispose();
    final library = DynamicLibrary.open(paths['v1']!);
    expect(
      library.lookupFunction<Int Function(), int Function()>('fixture_live')(),
      0,
    );
  });

  test('explicit disabled selector refuses v1 before engine calls', () async {
    final client = createLiteRtLmSelectedRuntimeClient(
      libraryPath: paths['v1'],
      allowV1: false,
    );
    await expectLater(
      client.initialize(modelPath: 'unused', backend: 'cpu'),
      throwsA(isA<LlamaUnsupportedException>()),
    );
    client.dispose();
  });

  test(
    'staged discovery selects complete v1 without creating engines for probes',
    () {
      final client = createLiteRtLmSelectedRuntimeClient(
        libraryPath: paths['v1'],
        allowV1: true,
      );
      final library = DynamicLibrary.open(paths['v1']!);
      int live() => library.lookupFunction<Int Function(), int Function()>(
        'fixture_live',
      )();
      expect(client.supportsFinishReasons, isTrue);
      expect(client.supportsAsrBridge, isTrue);
      expect(live(), 0);
      client.dispose();
      expect(live(), 0);
    },
  );

  test(
    'staged facade routes actual engine creation and tokenizer through v1',
    () async {
      final client = createLiteRtLmSelectedRuntimeClient(
        libraryPath: paths['v1'],
        allowV1: true,
      );
      addTearDown(client.dispose);
      await client.initialize(
        modelPath: 'unused',
        backend: 'cpu',
        speculativeDecoding: false,
      );
      expect(client.tokenize('hello', addSpecial: false), [5, 104, 111]);
      expect(client.nativeSettlement, LiteRtLmNativeSettlement.settled);
    },
  );

  test(
    'service fresh capability and finish probes share staged selection without engines',
    () {
      final service = LiteRtLmService(
        runtimeClientFactory: () => createLiteRtLmSelectedServiceClient(
          libraryPath: paths['v1'],
          allowV1: true,
        ),
      );
      addTearDown(service.dispose);
      expect(service.reportsFinishReasons(), isTrue);
      expect(service.generationControls().penalties, isTrue);
      final library = DynamicLibrary.open(paths['v1']!);
      expect(
        library.lookupFunction<Int Function(), int Function()>(
          'fixture_live',
        )(),
        0,
      );
    },
  );

  test('staged discovery preserves legacy runtime and arities', () async {
    final client = createLiteRtLmSelectedRuntimeClient(
      libraryPath: paths['legacy'],
      allowV1: true,
    );
    expect(client.supportsAsrBridge, isFalse);
    await client.initialize(
      modelPath: 'unused',
      backend: 'cpu',
      speculativeDecoding: false,
    );
    client.dispose();
  });

  test('incomplete v1 refuses before any arity-bomb engine function', () async {
    final client = createLiteRtLmSelectedRuntimeClient(
      libraryPath: paths['missing'],
      allowV1: true,
    );
    await expectLater(
      client.initialize(modelPath: 'unused', backend: 'cpu'),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'required symbols',
          contains('missing required'),
        ),
      ),
    );
    client.dispose();
  });

  test(
    'public speech default admits the complete independent v1 ASR bridge',
    () async {
      final support = await createLiteRtLmSpeechToTextDriver().probeSupport(
        libraryPath: paths['v1'],
      );
      expect(support.isSupported, isTrue);
      expect(support.unsupportedReason, isNull);
    },
  );

  test(
    'same staged selector serves speech capability and receiving-isolate worker',
    () async {
      final driver = createLiteRtLmSpeechToTextDriverWithRuntime(_stagedSpeech);
      expect(
        (await driver.probeSupport(libraryPath: paths['v1'])).isSupported,
        isTrue,
      );
      final worker = await driver.start(
        LiteRtLmAsrRuntimeConfig.source(
          model: ModelSource.path('fixture.litertlm'),
          tokenizer: ModelSource.path('fixture.json'),
          modelPreset: LiteRtLmAsrModelPreset.moonshineTiny,
        ),
        libraryPath: paths['v1'],
      );
      final subscription = worker.updates.listen((_) {});
      try {
        expect(await worker.pushAudio(Float32List(4)), 4);
        expect(await worker.finish(), contains('final café'));
      } finally {
        await worker.dispose();
        await subscription.cancel();
      }
    },
  );

  test(
    'macOS 13 speech probe and receiving-isolate worker refuse before dlopen',
    () async {
      if (!Platform.isMacOS) return;
      final driver = createLiteRtLmSpeechToTextDriverWithRuntime(
        _stagedOldMacSpeech,
      );
      for (final path in [null, '/not-a-runtime.dylib']) {
        final support = await driver.probeSupport(libraryPath: path);
        expect(support.isSupported, isFalse);
        expect(support.unsupportedReason, contains('macOS 14'));
        await expectLater(
          driver.start(
            LiteRtLmAsrRuntimeConfig.source(
              model: ModelSource.path('fixture.litertlm'),
              tokenizer: ModelSource.path('fixture.json'),
              modelPreset: LiteRtLmAsrModelPreset.moonshineTiny,
            ),
            libraryPath: path,
          ),
          throwsA(
            isA<LlamaSpeechException>().having(
              (error) => error.details,
              'floor before load',
              contains('macOS 14'),
            ),
          ),
        );
      }
    },
  );

  test('macOS 13 refuses packaged and explicit discovery before dlopen', () {
    if (!Platform.isMacOS) return;
    for (final path in [null, '/not-a-runtime.dylib']) {
      expect(
        () => createLiteRtLmSelectedRuntimeClient(
          libraryPath: path,
          allowV1: true,
          macOsVersion: 'Version 13.7',
          eager: true,
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'floor before load',
            contains('macOS 14'),
          ),
        ),
      );
    }
  });
}
