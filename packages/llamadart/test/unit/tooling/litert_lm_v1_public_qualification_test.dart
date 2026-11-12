@TestOn('vm && (mac-os || linux)')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_platform.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';
import 'package:test/test.dart';

import '../../support/dart_script_snapshot.dart';
import '../../support/suite_system_temp.dart';

void main() {
  useSuiteSystemTemp();
  late Directory directory;
  late String script, dispatchScript, core;
  late File model, manifest, chat, speech;
  late DynamicLibrary library;
  String hash(File file) => sha256.convert(file.readAsBytesSync()).toString();
  int count(String name) =>
      library.lookupFunction<Int Function(), int Function()>('fixture_$name')();
  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync(
      'litert_public_qualification_',
    );
    script = await compileDartScript(
      'test/fixtures/litert_lm_v1_public_qualification.dart',
    );
    dispatchScript = await compileDartScript(
      'test/fixtures/litert_lm_v1_public_dispatch_smoke.dart',
    );
    final names = liteRtLmRequiredLibrariesForAbi(Abi.current());
    final coreName = Platform.isMacOS ? 'libLiteRtLm.dylib' : 'libLiteRtLm.so';
    core = '${directory.path}/$coreName';
    final built = await Process.run('cc', [
      '-shared',
      '-fPIC',
      '-pthread',
      'test/fixtures/litert_lm/c_api_v1_public_dispatch.c',
      '-o',
      core,
    ]);
    expect(built.exitCode, 0, reason: '${built.stderr}');
    final stub = File('${directory.path}/companion.c')
      ..writeAsStringSync('int fixture_companion_stub(void) { return 1; }\n');
    final stubLibrary = '${directory.path}/stub.bin';
    final stubBuilt = await Process.run('cc', [
      '-shared',
      '-fPIC',
      stub.path,
      '-o',
      stubLibrary,
    ]);
    expect(stubBuilt.exitCode, 0, reason: '${stubBuilt.stderr}');
    for (final name in names.where((name) => name != coreName)) {
      File(stubLibrary).copySync('${directory.path}/$name');
    }
    manifest = File('${directory.path}/runtime.json')
      ..writeAsStringSync(
        jsonEncode([
          for (final name in names)
            {
              'name': name,
              'bytes': File('${directory.path}/$name').lengthSync(),
              'sha256': hash(File('${directory.path}/$name')),
            },
        ]),
      );
    model = File('${directory.path}/Qwen3-fixture.litertlm')
      ..writeAsStringSync('model-free fixture');
    final profile =
        jsonDecode(
              File(
                'packages/llamadart_validation/assets/profiles/chat-litert-cpu.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    (profile['model'] as Map)['sha256'] = hash(model);
    (profile['model'] as Map)['bytes'] = model.lengthSync();
    chat = File('${directory.path}/profile.json')
      ..writeAsStringSync(jsonEncode(profile));
    final tokenizer = File('${directory.path}/tokenizer.json')
      ..writeAsStringSync('{}');
    final audio = File('${directory.path}/audio.wav')
      ..writeAsBytesSync(List.filled(44, 0));
    speech = File('${directory.path}/speech.json')
      ..writeAsStringSync(
        jsonEncode({
          'tokenizer': {'path': tokenizer.path, 'sha256': hash(tokenizer)},
          'audio': {'path': audio.path, 'sha256': hash(audio)},
          'preset': 'moonshine-tiny',
          'expected_transcript': 'final café',
        }),
      );
    library = DynamicLibrary.open(core);
  });
  tearDownAll(() => directory.deleteSync(recursive: true));
  for (final route in ['direct', 'service']) {
    test(
      'public default $route preserves signed tagged settings across async creation',
      () async {
        final tagged = Directory('${directory.path}/tagged-$route')
          ..createSync();
        final taggedCore = '${tagged.path}/${File(core).uri.pathSegments.last}';
        final built = await Process.run('cc', [
          '-shared',
          '-fPIC',
          '-pthread',
          '-DFIXTURE_TAGGED_SETTINGS',
          'test/fixtures/litert_lm/c_api_v1_public_dispatch.c',
          '-o',
          taggedCore,
        ]);
        expect(built.exitCode, 0, reason: '${built.stderr}');
        for (final name in liteRtLmRequiredLibrariesForAbi(Abi.current())) {
          if (name != File(core).uri.pathSegments.last) {
            File('${directory.path}/$name').copySync('${tagged.path}/$name');
          }
        }
        final result = await Process.run(
          Platform.resolvedExecutable,
          [
            dispatchScript,
            route,
            taggedCore,
            model.path,
            chat.path,
            'tagged-settings',
          ],
          environment: {
            'LLAMADART_LITERT_LM_LIB_DIR': tagged.path,
            'TMPDIR': tagged.path,
          },
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(
          '${result.stdout}',
          contains(
            'PUBLIC_FIXTURE_DISPATCH $route settled; model_qualification=false',
          ),
        );
      },
    );
  }
  for (final route in ['direct', 'service', 'speech']) {
    test(
      'public default $route dispatches compiled v1 fixture and settles without overrides',
      () async {
        final config = route == 'speech' ? speech : chat;
        // Valid WAV bytes are needed to reach the default speech capability probe.
        if (route == 'speech') {
          final audio = File('${directory.path}/audio.wav');
          final bytes = List<int>.filled(52, 0);
          void tag(int offset, String value) {
            bytes.setRange(offset, offset + value.length, ascii.encode(value));
          }

          void u16(int offset, int value) {
            bytes[offset] = value & 255;
            bytes[offset + 1] = (value >> 8) & 255;
          }

          void u32(int offset, int value) {
            for (var i = 0; i < 4; i++) {
              bytes[offset + i] = (value >> (8 * i)) & 255;
            }
          }

          tag(0, 'RIFF');
          u32(4, 44);
          tag(8, 'WAVE');
          tag(12, 'fmt ');
          u32(16, 16);
          u16(20, 1);
          u16(22, 1);
          u32(24, 16000);
          u32(28, 32000);
          u16(32, 2);
          u16(34, 16);
          tag(36, 'data');
          u32(40, 8);
          audio.writeAsBytesSync(bytes);
          final value =
              jsonDecode(speech.readAsStringSync()) as Map<String, dynamic>;
          (value['audio'] as Map)['sha256'] = hash(audio);
          speech.writeAsStringSync(jsonEncode(value));
        }
        final result = await Process.run(
          Platform.resolvedExecutable,
          [dispatchScript, route, core, model.path, config.path],
          environment: {
            'LLAMADART_LITERT_LM_LIB_DIR': directory.path,
            'TMPDIR': directory.path,
          },
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(
          '${result.stdout}',
          contains(
            'PUBLIC_FIXTURE_DISPATCH $route settled; model_qualification=false',
          ),
        );
      },
    );
  }
  for (final badIndex in [2, 4, 6, 8]) {
    test(
      'incorrect identity $badIndex refuses before supplied runtime loading',
      () async {
        final args = [
          'direct',
          core,
          hash(File(core)),
          model.path,
          hash(model),
          manifest.path,
          hash(manifest),
          chat.path,
          hash(chat),
          directory.path,
          'model-free-hash-refusal',
        ];
        args[badIndex] = '0' * 64;
        final result = await Process.run(Platform.resolvedExecutable, [
          script,
          '--child',
          '--expect-disabled',
          ...args,
        ]);
        expect(result.exitCode, 1);
        expect(
          '${result.stdout}',
          contains('SHA256 mismatch before native loading'),
        );
        expect('${result.stdout}', isNot(contains('"stage":"identity"')));
        expect('${result.stderr}', isNot(contains('PUBLIC_FIXTURE_LOADED')));
      },
    );
  }
  for (final explicit in [true, false]) {
    test(
      'staged v1 status9 ${explicit ? 'preserves typed explicit GPU refusal' : 'retains automatic GPU-to-CPU fallback'}',
      () async {
        if (!liteRtLmNativeGpuSupportedOnCurrentPlatform()) {
          markTestSkipped(
            'GPU preference routing is not available on this host.',
          );
          return;
        }
        library.lookupFunction<Void Function(), void Function()>(
          'fixture_public_reset',
        )();
        final service = LiteRtLmService(
          runtimeClientFactory: () => createLiteRtLmSelectedServiceClient(
            libraryPath: core,
            allowV1: true,
          ),
          useTempCacheDir: false,
        );
        final params = ModelParams(
          device: explicit ? ComputeDevice.gpu : ComputeDevice.auto,
          preferredBackend: GpuBackend.metal,
          liteRtLmCacheDir: '${directory.path}/cache',
        );
        try {
          final handle = await service.loadModel(model.path, params);
          if (explicit) {
            await expectLater(
              service.tokenize(handle, 'hello', false),
              throwsA(
                isA<LlamaUnsupportedException>().having(
                  (error) => error.message,
                  'native safety error',
                  allOf(
                    contains('GPU safety preflight'),
                    contains('FAILED_PRECONDITION'),
                    contains('(9)'),
                    contains('ComputeDevice.cpu'),
                  ),
                ),
              ),
            );
            expect(count('public_gpu_refusals'), 1);
            expect(count('public_cpu_creates'), 0);
          } else {
            expect(await service.tokenize(handle, 'hello', false), isNotEmpty);
            expect(service.getActiveBackendName(), 'LiteRT-LM cpu');
            expect(count('public_gpu_refusals'), 1);
            expect(count('public_cpu_creates'), 1);
          }
          expect(service.nativeSettlement, LiteRtLmNativeSettlement.settled);
        } finally {
          service.dispose();
        }
        expect(count('live'), 0);
      },
    );
  }
}
