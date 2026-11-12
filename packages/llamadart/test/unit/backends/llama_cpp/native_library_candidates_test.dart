@TestOn('vm')
library;

import 'dart:ffi';

import 'package:llamadart/src/backends/llama_cpp/native_library_candidates.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

const _dir = '/bundle';

LlamaCppLibraryCandidates _candidates(
  String os, {
  Abi abi = Abi.linuxX64,
  List<String>? files,
  bool unreadable = false,
}) => LlamaCppLibraryCandidates(
  os: os,
  abi: abi,
  moduleDirectory: files == null && !unreadable ? null : _dir,
  listFiles: (directory) {
    if (unreadable) {
      throw StateError('cannot list $directory');
    }
    return directory == _dir ? files! : const <String>[];
  },
  fileExists: (filePath) =>
      path.dirname(filePath) == _dir &&
      (files ?? const <String>[]).contains(path.basename(filePath)),
);

void main() {
  group('without a module directory', () {
    const androidCpuVariants = <String>[
      'libggml-cpu-android_armv9.2_2.so',
      'libggml-cpu-android_armv9.2_1.so',
      'libggml-cpu-android_armv9.0_1.so',
      'libggml-cpu-android_armv8.6_1.so',
      'libggml-cpu-android_armv8.2_2.so',
      'libggml-cpu-android_armv8.2_1.so',
      'libggml-cpu-android_armv8.0_1.so',
    ];
    final table = <String, Map<String, List<String>>>{
      'linux': {
        'cpu': ['libggml-cpu.so'],
        'vulkan': ['libggml-vulkan.so'],
        'ggml': ['libggml.so'],
        'wrapper': ['libllamadart.so'],
        'mtmd': ['libmtmd.so'],
      },
      'android': {
        'cpu': [...androidCpuVariants, 'libggml-cpu.so'],
        'vulkan': ['libggml-vulkan.so'],
        'ggml': ['libggml.so'],
        'wrapper': ['libllamadart.so'],
        'mtmd': ['libmtmd.so'],
      },
      'macos': {
        'cpu': ['libggml-cpu.dylib'],
        'vulkan': ['libggml-vulkan.dylib'],
        'ggml': ['libggml.dylib'],
        'wrapper': [
          'libllamadart.dylib',
          path.join('llamadart.framework', 'llamadart'),
          path.join('llama.framework', 'llama'),
        ],
        'mtmd': ['libmtmd.dylib'],
      },
      'ios': {
        'cpu': ['libggml-cpu.dylib'],
        'vulkan': ['libggml-vulkan.dylib'],
        'ggml': ['libggml.dylib'],
        'wrapper': [
          'libllamadart.dylib',
          path.join('llamadart.framework', 'llamadart'),
          path.join('llama.framework', 'llama'),
        ],
        'mtmd': ['libmtmd.dylib'],
      },
      'windows': {
        'cpu': ['ggml-cpu.dll'],
        'vulkan': ['ggml-vulkan.dll'],
        'ggml': ['ggml.dll'],
        'wrapper': ['llamadart.dll', 'llamadart_wrapper.dll'],
        'mtmd': ['mtmd.dll'],
      },
    };
    for (final MapEntry(key: os, value: expected) in table.entries) {
      test('$os names each library by its bare file name', () {
        final candidates = _candidates(os);
        expect(candidates.backend('cpu'), expected['cpu']);
        expect(candidates.backend('vulkan'), expected['vulkan']);
        expect(candidates.ggml(), expected['ggml']);
        expect(candidates.wrapper(), expected['wrapper']);
        expect(candidates.mtmd(), expected['mtmd']);
      });
    }
  });

  group('with a module directory', () {
    test('linux keeps the unsuffixed backend ahead of sorted matches', () {
      final candidates = _candidates(
        'linux',
        files: [
          'libggml-vulkan.so',
          'libggml-cpu-zen4.so',
          'libggml-cpu.so',
          'libggml-cpu-haswell.so',
          'libggml-cpu.dylib',
          'libggml-cpuextra.so',
          'libggml.so',
          'libggml-base.so',
          'libllamadart.so',
          'libllamadart_wrapper.so',
          'libllamadart-abi2.so',
          'libllama.so',
          'libmtmd.so',
          'libmtmd-helper.so',
        ],
      );
      expect(candidates.backend('cpu'), [
        'libggml-cpu.so',
        'libggml-cpu-haswell.so',
        'libggml-cpu-zen4.so',
      ]);
      expect(candidates.backend('vulkan'), ['libggml-vulkan.so']);
      expect(candidates.backend('cuda'), isEmpty);
      expect(candidates.ggml(), [
        'libggml.so',
        'libggml-base.so',
        'libggml-cpu-haswell.so',
        'libggml-cpu-zen4.so',
        'libggml-cpu.so',
        'libggml-cpuextra.so',
        'libggml-vulkan.so',
      ]);
      expect(candidates.wrapper(), [
        'libllamadart.so',
        'libllamadart-abi2.so',
        'libllamadart_wrapper.so',
      ]);
      expect(candidates.mtmd(), ['libmtmd.so', 'libmtmd-helper.so']);
    });

    test('linux lists suffixed modules when the unsuffixed one is absent', () {
      final candidates = _candidates(
        'linux',
        files: ['libggml-cpu-haswell.so'],
      );
      expect(candidates.backend('cpu'), ['libggml-cpu-haswell.so']);
      expect(candidates.ggml(), ['libggml.so', 'libggml-cpu-haswell.so']);
      expect(candidates.wrapper(), ['libllamadart.so']);
      expect(candidates.mtmd(), ['libmtmd.so']);
    });

    test('android ranks known cpu variants, then unknown, then baseline', () {
      final candidates = _candidates(
        'android',
        abi: Abi.androidArm64,
        files: [
          'libggml-cpu-linux_armv8.6_1.so',
          'libggml-cpu.so',
          'libggml-cpu-android_armv8.0_1.so',
          'libggml-cpu-android_armv7_9.so',
          'libggml-cpu-android_armv8.6_1.so',
          'libggml-cpu-android_armv9.2_2.so',
          'libggml-vulkan.so',
        ],
      );
      expect(candidates.backend('cpu'), [
        'libggml-cpu-android_armv9.2_2.so',
        'libggml-cpu-android_armv8.6_1.so',
        'libggml-cpu-android_armv8.0_1.so',
        'libggml-cpu-android_armv7_9.so',
        'libggml-cpu-linux_armv8.6_1.so',
        'libggml-cpu.so',
      ]);
      expect(candidates.backend('vulkan'), ['libggml-vulkan.so']);
    });

    group('linux arm64 cpu variants', () {
      const v86 = 'libggml-cpu-linux_armv8.6_1.so';
      const v82 = 'libggml-cpu-linux_armv8.2_2.so';
      const baseline = 'libggml-cpu.so';

      final table = <String, (List<String>, List<String>)>{
        'both variants': ([baseline, v82, v86], [v86, v82, baseline]),
        'only armv8.2': ([v82, baseline], [v82, baseline]),
        'only armv8.6': ([baseline, v86], [v86, baseline]),
        'only baseline': ([baseline], [baseline]),
        'no baseline': ([v82, v86], [v86, v82]),
        'unlisted variants after baseline': (
          [
            'libggml-cpu-linux_armv9.2_1.so',
            v82,
            baseline,
            'libggml-cpu-android_armv8.6_1.so',
          ],
          [
            v82,
            baseline,
            'libggml-cpu-android_armv8.6_1.so',
            'libggml-cpu-linux_armv9.2_1.so',
          ],
        ),
      };
      for (final MapEntry(key: name, value: (files, expected))
          in table.entries) {
        test('$name: best variant first, baseline as fallback', () {
          final candidates = _candidates(
            'linux',
            abi: Abi.linuxArm64,
            files: [...files, 'libggml-vulkan.so', 'libggml-vulkan-x.so'],
          );
          expect(candidates.backend('cpu'), expected);
          expect(candidates.backend('vulkan'), [
            'libggml-vulkan.so',
            'libggml-vulkan-x.so',
          ]);
        });
      }

      test('other linux ABIs keep the baseline first', () {
        for (final abi in [Abi.linuxX64, Abi.linuxArm, Abi.linuxRiscv64]) {
          final candidates = _candidates(
            'linux',
            abi: abi,
            files: [v86, baseline, v82],
          );
          expect(candidates.backend('cpu'), [
            baseline,
            v82,
            v86,
          ], reason: '$abi');
        }
      });

      test('without a module directory only the baseline is named', () {
        final candidates = _candidates('linux', abi: Abi.linuxArm64);
        expect(candidates.backend('cpu'), [baseline]);
        expect(candidates.backendAssetUris('cpu'), [
          'package:llamadart/cpu',
          'package:llamadart/ggml_cpu',
          'package:llamadart/ggml-cpu',
        ]);
      });
    });

    test('apple matches dylibs and keeps framework wrapper names', () {
      final candidates = _candidates(
        'macos',
        files: [
          'libggml-metal.dylib',
          'libggml-cpu.dylib',
          'libggml-cpu-x.dylib',
          'libggml.dylib',
          'libllamadart-abi2.dylib',
          'libmtmd.dylib',
          'libggml-cpu.so',
        ],
      );
      expect(candidates.backend('cpu'), [
        'libggml-cpu.dylib',
        'libggml-cpu-x.dylib',
      ]);
      expect(candidates.backend('metal'), ['libggml-metal.dylib']);
      expect(candidates.ggml(), [
        'libggml.dylib',
        'libggml-cpu-x.dylib',
        'libggml-cpu.dylib',
        'libggml-metal.dylib',
      ]);
      expect(candidates.wrapper(), [
        'libllamadart.dylib',
        path.join('llamadart.framework', 'llamadart'),
        path.join('llama.framework', 'llama'),
        'libllamadart-abi2.dylib',
      ]);
      expect(candidates.mtmd(), ['libmtmd.dylib']);
    });

    test('windows matches dlls', () {
      final candidates = _candidates(
        'windows',
        files: [
          'ggml-cuda.dll',
          'ggml-cpu.dll',
          'ggml-cpu-x64.dll',
          'ggml.dll',
          'ggml-base.dll',
          'llamadart.dll',
          'llamadart_wrapper.dll',
          'mtmd.dll',
          'cudart64_12.dll',
        ],
      );
      expect(candidates.backend('cpu'), ['ggml-cpu.dll', 'ggml-cpu-x64.dll']);
      expect(candidates.backend('cuda'), ['ggml-cuda.dll']);
      expect(candidates.ggml(), [
        'ggml.dll',
        'ggml-base.dll',
        'ggml-cpu-x64.dll',
        'ggml-cpu.dll',
        'ggml-cuda.dll',
      ]);
      expect(candidates.wrapper(), ['llamadart.dll', 'llamadart_wrapper.dll']);
      expect(candidates.mtmd(), ['mtmd.dll']);
    });

    test('escapes the backend name in its file pattern', () {
      final candidates = _candidates(
        'linux',
        files: ['libggml-aXb.so', 'libggml-a.b-1.so'],
      );
      expect(candidates.backend('a.b'), ['libggml-a.b-1.so']);
    });

    test('an unreadable directory yields no listed names', () {
      for (final os in ['linux', 'android', 'macos', 'windows']) {
        final candidates = _candidates(os, unreadable: true);
        expect(candidates.backend('cpu'), isEmpty, reason: os);
        expect(candidates.ggml(), hasLength(1), reason: os);
        expect(candidates.mtmd(), hasLength(1), reason: os);
      }
    });
  });

  test('backendFileName names the unsuffixed module per platform', () {
    expect(_candidates('linux').backendFileName('cuda'), 'libggml-cuda.so');
    expect(_candidates('android').backendFileName('cpu'), 'libggml-cpu.so');
    expect(
      _candidates('macos').backendFileName('metal'),
      'libggml-metal.dylib',
    );
    expect(_candidates('ios').backendFileName('metal'), 'libggml-metal.dylib');
    expect(_candidates('windows').backendFileName('cuda'), 'ggml-cuda.dll');
  });

  group('asset URIs', () {
    test('backend URIs add Android cpu variants with underscored dots', () {
      const shared = [
        'package:llamadart/cpu',
        'package:llamadart/ggml_cpu',
        'package:llamadart/ggml-cpu',
      ];
      expect(_candidates('linux').backendAssetUris('cpu'), shared);
      expect(_candidates('android').backendAssetUris('cpu'), [
        ...shared,
        'package:llamadart/ggml-cpu-android_armv9_2_2',
        'package:llamadart/ggml-cpu-android_armv9_2_1',
        'package:llamadart/ggml-cpu-android_armv9_0_1',
        'package:llamadart/ggml-cpu-android_armv8_6_1',
        'package:llamadart/ggml-cpu-android_armv8_2_2',
        'package:llamadart/ggml-cpu-android_armv8_2_1',
        'package:llamadart/ggml-cpu-android_armv8_0_1',
      ]);
      expect(_candidates('android').backendAssetUris('vulkan'), [
        'package:llamadart/vulkan',
        'package:llamadart/ggml_vulkan',
        'package:llamadart/ggml-vulkan',
      ]);
    });

    test('ggml and wrapper URIs add Windows split-bundle names', () {
      expect(_candidates('linux').ggmlAssetUris(), ['package:llamadart/ggml']);
      expect(_candidates('windows').ggmlAssetUris(), [
        'package:llamadart/ggml',
        'package:llamadart/ggml-base',
      ]);
      expect(_candidates('macos').wrapperAssetUris(), [
        'package:llamadart/llamadart',
      ]);
      expect(_candidates('windows').wrapperAssetUris(), [
        'package:llamadart/llamadart_wrapper',
        'package:llamadart/llamadart',
      ]);
    });
  });

  test('wrapperPaths joins lookup directories and dedupes in order', () {
    final candidates = LlamaCppLibraryCandidates(
      os: 'linux',
      abi: Abi.linuxX64,
      moduleDirectory: '/a',
      listFiles: (directory) => switch (directory) {
        '/a' => ['libllamadart_v2.so', 'libllamadart.so'],
        '/b' => ['libllamadart-x.so', 'libggml.so'],
        _ => throw StateError('unreadable'),
      },
      fileExists: (_) => false,
    );
    expect(candidates.wrapperPaths(['/a', '/b', '/c', '/a']), [
      'package:llamadart/llamadart',
      path.join('/a', 'libllamadart.so'),
      path.join('/a', 'libllamadart_v2.so'),
      path.join('/b', 'libllamadart.so'),
      path.join('/b', 'libllamadart_v2.so'),
      path.join('/b', 'libllamadart-x.so'),
      path.join('/c', 'libllamadart.so'),
      path.join('/c', 'libllamadart_v2.so'),
      'libllamadart.so',
      'libllamadart_v2.so',
    ]);
  });
}
