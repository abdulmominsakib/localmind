@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/ci/test_shards.dart';

void main() {
  group('partitionTests', () {
    test('puts every file in exactly one shard, balanced by weight', () {
      final files = [for (var i = 0; i < 9; i++) 'test/f${i}_test.dart'];
      final weights = {
        'test/f0_test.dart': 90,
        'test/f1_test.dart': 60,
        'test/f2_test.dart': 50,
        'test/f3_test.dart': 40,
        'test/f4_test.dart': 30,
        'test/f5_test.dart': 20,
        'test/f6_test.dart': 10,
      };
      final shards = partitionTests(files, weights, 3);

      expect(shards.expand((shard) => shard).toList()..sort(), files);
      // The unmeasured f7 and f8 weigh the median measured weight, 40.
      expect(shards, [
        ['test/f0_test.dart', 'test/f8_test.dart'],
        [
          'test/f1_test.dart',
          'test/f5_test.dart',
          'test/f6_test.dart',
          'test/f7_test.dart',
        ],
        ['test/f2_test.dart', 'test/f3_test.dart', 'test/f4_test.dart'],
      ]);
    });

    test('is independent of input order and works without weights', () {
      final files = [for (var i = 0; i < 7; i++) 'test/g${i}_test.dart'];
      final shards = partitionTests(files.reversed.toList(), const {}, 2);

      expect(shards, partitionTests(files, const {}, 2));
      expect(shards.map((shard) => shard.length), [4, 3]);
    });

    test('rejects a shard count below one', () {
      expect(() => partitionTests(const [], const {}, 0), throwsArgumentError);
    });
  });

  test('suiteWeights runs from a suite start to its end or the next start', () {
    final weights = suiteWeights([
      {
        'reporterElapsedMs': 100,
        'suites': [
          {'id': 0, 'path': 'test/a_test.dart'},
          {'id': 1, 'path': 'test/b_test.dart'},
          {'id': 2, 'path': '<external-or-loading-suite>'},
          {'id': 3, 'path': 'test/c_test.dart'},
        ],
        'tests': [
          {'suiteId': 0, 'startMs': 10, 'durationMs': 5},
          {'suiteId': 0, 'startMs': 12, 'durationMs': 20},
          {'suiteId': 1, 'startMs': 40, 'durationMs': null},
          {'suiteId': 2, 'startMs': 0, 'durationMs': 9},
          {'suiteId': 3, 'startMs': 45, 'durationMs': 30},
        ],
      },
    ]);

    // a ends at 32 but b starts at 40; c overlaps nothing after it.
    expect(weights, {
      'test/a_test.dart': 30,
      'test/b_test.dart': 5,
      'test/c_test.dart': 55,
    });
  });

  test('suiteWeights averages a suite over several summaries', () {
    Map<String, dynamic> run(int duration) => {
      'reporterElapsedMs': duration,
      'suites': [
        {'id': 7, 'path': 'test/a_test.dart'},
      ],
      'tests': [
        {'suiteId': 7, 'startMs': 0, 'durationMs': duration},
      ],
    };

    expect(suiteWeights([run(10), run(31)]), {'test/a_test.dart': 20});
  });

  group('rootTestFiles', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('test-shards-'));
    tearDown(() => root.deleteSync(recursive: true));

    void touch(String path) =>
        (File('${root.path}/$path')..createSync(recursive: true));

    test('lists every *_test.dart under test/, sorted', () {
      touch('test/unit/b_test.dart');
      touch('test/a_test.dart');
      touch('test/support/helper.dart');
      touch('tool/c_test.dart');

      expect(rootTestFiles(root.path), [
        'test/a_test.dart',
        'test/unit/b_test.dart',
      ]);
    });

    test('rejects a path the workflow could not pass as one word', () {
      touch(r'test/a $(x)_test.dart');

      expect(() => rootTestFiles(root.path), throwsFormatException);
    });
  });

  test('the weights file has an entry for every timing source', () {
    expect(readWeights().keys, weightLanes);
    expect(testShardLanes.values.toSet(), weightLanes.toSet());
  });

  group('hostReasons', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('test-hosts-'));
    tearDown(() => root.deleteSync(recursive: true));

    void write(String path, String source) => File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(source);
    List<String> reasons(String path, String source) {
      write(path, source);
      return hostReasons(path, root.path);
    }

    const neutral = """
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() => test('renders', () {});
""";

    test('keeps platform-neutral tests on Linux only', () {
      expect(reasons('test/unit/core/template/a_test.dart', neutral), isEmpty);
      expect(reasons('test/integration/core/a_test.dart', neutral), isEmpty);
      expect(reasons('test/unit/tooling/a_test.dart', neutral), isEmpty);
      expect(reasons('test/unit/backends/web/a_test.dart', neutral), isEmpty);
    });

    test('runs host-bound areas on every OS', () {
      for (final path in [
        'test/unit/backends/llama_cpp/a_test.dart',
        'test/unit/backends/litert_lm/a_test.dart',
        'test/unit/backends/stable_diffusion/a_test.dart',
        'test/unit/backends/native/a_test.dart',
        'test/unit/backends/a_test.dart',
        'test/unit/hook/a_test.dart',
        'test/unit/platform/io/a_test.dart',
        'test/integration/a_test.dart',
        'test/integration/backends/llama_cpp/a_test.dart',
        'test/e2e/backends/a_test.dart',
      ]) {
        expect(reasons(path, neutral), isNotEmpty, reason: path);
      }
      expect(reasons('test/unit/core/a_io_test.dart', neutral), [
        'dart:io implementation',
      ]);
    });

    test('follows test helpers to native code and real models', () {
      write(
        'test/support/native.dart',
        "import 'package:llamadart/src/backends/llama_cpp/bindings.dart';\n",
      );
      write(
        'test/support/model.dart',
        'final dir = Platform.environment["LLAMADART_TEST_MODELS_DIR"];\n',
      );
      write(
        'test/support/portable.dart',
        "final exe = Platform.isWindows ? 'dart.exe' : 'dart';\n",
      );

      expect(
        reasons(
          'test/unit/core/a_test.dart',
          "import '../../support/native.dart';\n",
        ),
        [
          'imports lib/src/backends/llama_cpp/bindings.dart via '
              'test/support/native.dart',
        ],
      );
      expect(
        reasons(
          'test/unit/core/b_test.dart',
          'import "../../support/model.dart";\n',
        ),
        ['loads a test model via test/support/model.dart'],
      );
      // A helper's own portability branch is not a host check of the test.
      expect(
        reasons(
          'test/unit/tooling/c_test.dart',
          "import '../../support/portable.dart';\n",
        ),
        isEmpty,
      );
    });

    test('finds native imports, conditional ones included', () {
      expect(reasons('test/unit/core/a_test.dart', "import 'dart:ffi';\n"), [
        'imports dart:ffi',
      ]);
      expect(
        reasons(
          'test/unit/core/b_test.dart',
          "import 'stub.dart'\n"
              "    if (dart.library.io) "
              "'package:llamadart/src/platform/io/native_diagnostics.dart';\n",
        ),
        ['imports lib/src/platform/io/native_diagnostics.dart'],
      );
      expect(
        reasons('test/unit/core/c_test.dart', 'final b = LlamaBackend();\n'),
        ['constructs the platform backend'],
      );
    });

    test('runs tests that check the host OS on every OS', () {
      for (final source in [
        "@TestOn('windows')\nlibrary;\n",
        "@TestOn('vm && mac-os')\nlibrary;\n",
        "@TestOn('vm && !windows')\nlibrary;\n",
        "test('a', () {}, skip: !Platform.isLinux);\n",
        "test('a', () {}, skip: Platform.isWindows ? false : 'Windows only');\n",
        "test('a', () {}, onPlatform: {'windows': Skip()});\n",
      ]) {
        expect(reasons('test/unit/tooling/a_test.dart', source), [
          'checks the host OS',
        ], reason: source);
      }
      expect(
        reasons(
          'test/unit/tooling/b_test.dart',
          "import 'dart:io';\nimport 'package:path/path.dart' as p;\n",
        ),
        ['builds host paths'],
      );
    });

    test('a POSIX-only skip guard alone keeps a test on Linux only', () {
      for (final guard in [
        "skip: Platform.isWindows ? 'requires bash' : false,",
        'skip: Platform.isWindows ? _posixOnly : null)',
        'skip: Platform.isWindows,',
      ]) {
        expect(
          reasons('test/unit/tooling/a_test.dart', "test('a', () {}, $guard\n"),
          isEmpty,
          reason: guard,
        );
      }
    });
  });

  group('host OS lanes', () {
    final files = rootTestFiles();
    final macos = laneFiles('macos', files);
    final tooling = laneFiles('windows-tooling', files);
    final runtime = laneFiles('windows-runtime', files);

    test('Linux VM and Chrome run every file; macOS and Windows the same '
        'host-sensitive ones', () {
      expect(laneFiles('linux-vm', files), files);
      expect(laneFiles('chrome', files), files);
      expect(macos, [
        for (final file in files)
          if (hostReasons(file).isNotEmpty) file,
      ]);
      expect(tooling.toSet().intersection(runtime.toSet()), isEmpty);
      expect([...tooling, ...runtime]..sort(), macos);
      expect(tooling, everyElement(startsWith('test/unit/')));
      expect(
        tooling,
        contains('test/unit/tooling/windows_registry_qualification_test.dart'),
      );
      expect(
        runtime,
        contains(
          'test/integration/backends/llama_cpp/prompt_state_isolation_test.dart',
        ),
      );
    });

    test('a file that skips Linux runs on the other hosts', () {
      final restricted = RegExp(r"@TestOn\('([^']*)'\)");
      for (final file in files) {
        final platforms = restricted
            .firstMatch(File(file).readAsStringSync())
            ?.group(1);
        if (platforms == null || platforms.contains('linux')) continue;
        if (!platforms.contains('windows') && !platforms.contains('mac-os')) {
          continue;
        }
        expect(macos, contains(file), reason: '$file: $platforms');
      }
    });

    test('lists only existing history suites the rules would miss', () {
      for (final MapEntry(key: file, value: evidence)
          in hostHistoryTests.entries) {
        expect(files, contains(file));
        expect(hostReasons(file), ['host history: $evidence'], reason: file);
      }
    });

    test('keeps known host-specific suites on macOS and Windows', () {
      for (final file in [
        'test/integration/windows_ggml_registry_test.dart',
        'test/integration/apple_companion_flutter_cache_test.dart',
        'test/integration/core/grammar/grammar_regression_test.dart',
        'test/unit/core/engine/engine_set_model_io_test.dart',
        'test/unit/tooling/bounded_process_test.dart',
        'test/unit/tooling/sync_native_release_pins_script_test.dart',
        'test/unit/tooling/prepare_workspace_test.dart',
      ]) {
        expect(macos, contains(file));
        expect(
          [...tooling, ...runtime],
          contains(file),
          reason: '$file must run on a Windows lane',
        );
      }
      for (final file in [
        'test/unit/core/template/chat_format_registry_test.dart',
        'test/unit/core/engine/chat_completion_stream_parser_test.dart',
        'test/unit/tooling/safe_pr_head_update_test.dart',
        'test/unit/tooling/test_matrix_test.dart',
      ]) {
        expect(macos, isNot(contains(file)));
      }
    });
  });

  group('command line', () {
    Future<ProcessResult> run(
      List<String> arguments, {
      Map<String, String> environment = const {},
    }) => Process.run(Platform.resolvedExecutable, [
      'tool/ci/test_shards.dart',
      ...arguments,
    ], environment: environment);

    test('writes one shard to stdout and GITHUB_OUTPUT', () async {
      final scratch = Directory.systemTemp.createTempSync('test-shards-out-');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final output = File('${scratch.path}/output')..createSync();

      final result = await run(
        ['windows-tooling', '2', '3'],
        environment: {'GITHUB_OUTPUT': output.path},
      );

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final expected = partitionTests(
        laneFiles('windows-tooling', rootTestFiles()),
        readWeights()['windows']!,
        3,
      )[1];
      expect(LineSplitter.split('${result.stdout}'), expected);
      expect(output.readAsStringSync(), 'files=${expected.join(' ')}\n');
    });

    for (final arguments in [
      ['unknown', '1', '2'],
      ['macos', '0', '2'],
      ['macos', '3', '2'],
      ['macos', '1'],
    ]) {
      test('rejects ${arguments.join(' ')}', () async {
        final result = await run(arguments);

        expect(result.exitCode, 64);
        expect(result.stdout, isEmpty);
      });
    }
  });
}
