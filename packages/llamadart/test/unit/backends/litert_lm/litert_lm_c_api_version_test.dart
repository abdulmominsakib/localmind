@TestOn('vm && (mac-os || linux)')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:llamadart/src/hook/native_release_pins.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_c_api_version.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  final libraries = <String, String>{};

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('litert_c_api_version_');
    for (final entry in <String, List<String>>{
      'legacy': ['-DOMIT_API_VERSION'],
      'v1': [],
      'future': ['-DAPI_MAJOR=2'],
      'failed': ['-DAPI_STATUS=13'],
      'futureMinor': ['-DAPI_MINOR=1'],
      'negativePatch': ['-DAPI_PATCH=-1'],
      'incomplete': ['-DOMIT_PATCH_WRITE'],
      'inProcess0': ['-DIN_PROCESS_LITERT_ABI=0'],
      'inProcess1': ['-DIN_PROCESS_LITERT_ABI=1'],
      'inProcess2': ['-DIN_PROCESS_LITERT_ABI=2'],
    }.entries) {
      final output =
          '${directory.path}/${entry.key}.${Platform.isMacOS ? 'dylib' : 'so'}';
      final result = await Process.run('cc', [
        '-shared',
        '-fPIC',
        ...entry.value,
        'test/fixtures/litert_lm/c_api_version.c',
        '-o',
        output,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      libraries[entry.key] = output;
    }
  });

  tearDownAll(() => directory.delete(recursive: true));

  test('shared probe admits only legacy and C API 1.0.x', () {
    expect(
      readLiteRtLmCApiVersion(DynamicLibrary.open(libraries['legacy']!)),
      isNull,
    );
    expect(readLiteRtLmCApiVersion(DynamicLibrary.open(libraries['v1']!)), (
      major: 1,
      minor: 0,
      patch: 0,
    ));
    for (final name in [
      'future',
      'failed',
      'futureMinor',
      'negativePatch',
      'incomplete',
    ]) {
      expect(
        () => readLiteRtLmCApiVersion(DynamicLibrary.open(libraries[name]!)),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    }
  });

  test('in-process LiteRT probe reports the export value or null', () {
    int? read(String name) => readLiteRtLmInProcessLiteRtAbiVersion(
      DynamicLibrary.open(libraries[name]!),
    );
    expect(read('v1'), isNull);
    expect(read('legacy'), isNull);
    expect(
      [read('inProcess0'), read('inProcess1'), read('inProcess2')],
      [0, 1, 2],
    );
  });

  test('legacy runtime continues to existing capability checks', () {
    expect(
      () =>
          requireLiteRtLmLegacyCApi(DynamicLibrary.open(libraries['legacy']!)),
      returnsNormally,
    );
  });

  for (final entry in {
    'v1': '1.0.0',
    'future': '2.0.0',
    'failed': 'status 13',
    'futureMinor': '1.1.0',
    'negativePatch': '1.0.-1',
    'incomplete': '1.0.-1',
  }.entries) {
    test('${entry.key} refuses before legacy engine calls', () async {
      final client = LiteRtLmRuntimeClient(libraryPath: libraries[entry.key]);
      try {
        await expectLater(
          client.initialize(modelPath: 'unused.litertlm', backend: 'cpu'),
          entry.key == 'v1'
              ? throwsA(
                  isA<LlamaUnsupportedException>().having(
                    (error) => error.message,
                    'incomplete admitted v1',
                    contains('missing required preparation export'),
                  ),
                )
              : throwsA(
                  isA<LlamaUnsupportedException>()
                      .having(
                        (error) => error.message,
                        'version',
                        contains(entry.value),
                      )
                      .having(
                        (error) => error.message,
                        'repair',
                        contains('litert-lm-native $liteRtLmReleaseTag'),
                      )
                      .having(
                        (error) => error.message,
                        'admitted ABI',
                        contains('supported C API 1.0.x'),
                      )
                      .having(
                        (error) => error.message,
                        'ABI contract',
                        contains(
                          'https://github.com/leehack/llamadart/issues/1677',
                        ),
                      ),
                ),
        );
      } finally {
        client.dispose();
      }
    });
    test(
      '${entry.key} legacy gate directs callers to the admitting client',
      () {
        expect(
          () => requireLiteRtLmLegacyCApi(
            DynamicLibrary.open(libraries[entry.key]!),
          ),
          throwsA(
            isA<LlamaUnsupportedException>()
                .having(
                  (error) => error.message,
                  'legacy refusal',
                  contains('incompatible with the pre-1.0 bindings'),
                )
                .having(
                  (error) => error.message,
                  'admitting client',
                  contains('default LiteRtLmRuntimeClient or LiteRtLmService'),
                )
                .having(
                  (error) => error.message,
                  'compatible override',
                  contains('compatible legacy runtime override'),
                )
                .having(
                  (error) => error.message,
                  'no legacy engine call',
                  contains('No legacy engine call was attempted'),
                ),
          ),
        );
      },
    );
  }
}
