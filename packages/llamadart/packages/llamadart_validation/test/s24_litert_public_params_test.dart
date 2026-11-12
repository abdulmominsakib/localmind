@TestOn('vm && (mac-os || linux)')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

// ignore: implementation_imports
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart_validation/android_litert_qualification.dart';
import 'package:test/test.dart';

void main() {
  final abi = Abi.current();
  if (abi != Abi.macosArm64 && abi != Abi.linuxX64) {
    test(
      'native GPU fixture requires a supported host ABI',
      () {},
      skip: 'This native GPU fixture supports macOS arm64 and Linux x64.',
    );
    return;
  }
  late Directory directory;
  late String core;
  late File model;
  late String probe;
  final root = Directory('../..').absolute.path;

  Future<void> compile(String source, String destination) async {
    final result = await Process.run('cc', [
      '-shared',
      '-fPIC',
      '-pthread',
      source,
      '-o',
      destination,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('s24_public_params_');
    final coreName = liteRtLmPrimaryLibraryForAbi(Abi.current())!;
    core = '${directory.path}/$coreName';
    await compile(
      '$root/test/fixtures/litert_lm/c_api_v1_public_dispatch.c',
      core,
    );
    final companion = '${directory.path}/companion';
    await compile(
      '$root/test/fixtures/litert_lm/discovery_companion.c',
      companion,
    );
    for (final name in liteRtLmRequiredLibrariesForAbi(
      Abi.current(),
      cApiV1: true,
    )) {
      if (name != coreName) File(companion).copySync('${directory.path}/$name');
    }
    model = File('${directory.path}/Qwen3-fixture.litertlm')
      ..writeAsStringSync('model-free fixture');
    probe = '${directory.path}/probe';
    final built = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      'test/fixtures/s24_litert_public_params_probe.dart',
      '-o',
      probe,
    ]);
    expect(built.exitCode, 0, reason: '${built.stdout}\n${built.stderr}');
  });
  tearDownAll(() => directory.delete(recursive: true));

  Future<Map<String, dynamic>> run(String route) async {
    final result = await Process.run(
      probe,
      [route, core, model.path, '${directory.path}/cache-$route'],
      workingDirectory: directory.path,
      includeParentEnvironment: false,
      environment: {
        'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
        'HOME': directory.path,
        'TMPDIR': directory.path,
        'LLAMADART_LITERT_LM_LIB_DIR': directory.path,
      },
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final resultRow = (result.stdout as String).trim().split('\n').last;
    final row = jsonDecode(resultRow) as Map<String, dynamic>;
    expect(row['live'], 0, reason: 'Fixture native owner leaked');
    return row;
  }

  test(
    'old GPU CPU-thread option refuses before native engine creation',
    () async {
      final row = await run('old-gpu');
      expect(row['typed_unsupported'], isTrue);
      expect(row['error'], contains('CPU'));
      expect(row['attempts'], 0);
      expect(row['gpu_refusals'], 0);
      expect(row['cpu_creates'], 0);
    },
  );

  test('runner GPU options reach the distinct native owner guard', () async {
    final row = await run('gpu');
    expect(row['threads'], 0);
    expect(row['typed_unsupported'], isTrue);
    expect(
      row['error'],
      contains(
        'Android GPU safety preflight refused the known fixture; use CPU.',
      ),
    );
    expect(row['attempts'], 1);
    expect(row['gpu_refusals'], 1);
    expect(row['cpu_creates'], 0);
  });

  test(
    'runner auto options follow platform selection and preserve fallback',
    () async {
      final row = await run('auto');
      expect(row['threads'], 0);
      expect(row['error'], isNull);
      expect(row['tokens'], greaterThan(0));
      expect(row['cpu_creates'], 1);
      if (Platform.isLinux) {
        expect(row['attempts'], 1);
        expect(row['gpu_refusals'], 0);
        expect(
          row['warnings'],
          isNot(anyElement(contains(s24LiteRtFallbackWarning))),
        );
      } else {
        expect(row['attempts'], 2);
        expect(row['gpu_refusals'], 1);
        expect(row['warnings'], anyElement(contains(s24LiteRtFallbackWarning)));
      }
    },
  );

  test(
    'runner explicit CPU keeps four threads and reaches the engine',
    () async {
      final row = await run('cpu');
      expect(row['threads'], 4);
      expect(row['error'], isNull);
      expect(row['tokens'], greaterThan(0));
      expect(row['attempts'], 1);
      expect(row['gpu_refusals'], 0);
      expect(row['cpu_creates'], 1);
    },
  );
}
