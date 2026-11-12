@TestOn('vm && (mac-os || linux)')
@Tags(['local-only'])
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:llamadart/src/hook/native_release_pins.dart';
import 'package:llamadart/src/platform/io/native_diagnostics.dart';
import 'package:test/test.dart';

void main() {
  late Directory scratch;
  late Uri config;
  late Uri child;
  setUp(() async {
    scratch = await Directory.systemTemp.createTemp(
      'native_diagnostic_artifact_',
    );
    config = File('${scratch.path}/package_config.json').uri;
    await File.fromUri(config).writeAsString('{}');
    child = File(
      'lib/src/platform/io/native_diagnostics_child.dart',
    ).absolute.uri;
  });
  tearDown(() => scratch.delete(recursive: true));

  Future<Map<String, Object>> probe(
    String runtime,
    NativeDiagnosticTarget target, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final id = switch (runtime) {
      'llama_cpp' => 'llamadart',
      'stable_diffusion' => 'stable_diffusion',
      _ => Platform.isMacOS ? 'litert_lm_libLiteRtLm' : 'litert_lm_LiteRtLm',
    };
    await File('${scratch.path}/native_assets.yaml').writeAsString(
      jsonEncode({
        'format-version': [1, 0, 0],
        'native-assets': {
          Abi.current().toString(): {
            'package:llamadart/$id': ['absolute', target.primary],
          },
        },
      }),
    );
    final packageConfig = (await Isolate.packageConfig)!;
    return runNativeDiagnostic(
      runtime,
      packageConfig: config,
      childScript: child,
      timeout: timeout,
      start: (executable, _) => Process.start(executable, [
        '--disable-dart-dev',
        '--packages=${packageConfig.toFilePath()}',
        child.toFilePath(),
      ]),
    );
  }

  for (final (define, code) in [
    ('', 'SURFACE_OBSERVED'),
    ('PROBE_MISSING_SYMBOL', 'SYMBOL_MISSING'),
    ('PROBE_ABI=999', 'ABI_UNKNOWN'),
    ('PROBE_ABORT', 'CHILD_FAILED'),
    ('PROBE_HANG', 'PROBE_TIMEOUT'),
  ]) {
    test('real child contains fake native library $define', () async {
      final file = '${scratch.path}/fake${Platform.isMacOS ? '.dylib' : '.so'}';
      final compiler = await Process.run('cc', [
        Platform.isMacOS ? '-dynamiclib' : '-shared',
        '-fPIC',
        if (define.isNotEmpty) '-D$define',
        'test/fixtures/native_diagnostics_runtime.c',
        '-o',
        file,
      ]);
      expect(compiler.exitCode, 0, reason: '${compiler.stderr}');
      final result = await probe(
        'llama_cpp',
        NativeDiagnosticTarget(file, file, const []),
        timeout: Duration(seconds: define == 'PROBE_HANG' ? 2 : 20),
      );
      expect(result['code'], code);
      expect(jsonEncode(result), isNot(contains('PRIVATE_DIAGNOSTIC_TOKEN')));
      expect(jsonEncode(result), isNot(contains('private-user')));
      expect(result['loaded_release'], 'unknown');
      if (define == 'PROBE_ABORT') expect(result['phase'], 'open');
    });
  }

  test(
    'real child opens current declared llama.cpp artifact without a model',
    () async {
      final actual = await Isolate.packageConfig;
      final result = await runNativeDiagnostic(
        'llama_cpp',
        packageConfig: actual,
        childScript: child,
      );
      expect(result['code'], 'SURFACE_OBSERVED');
      expect(result['abi_marker'], 'tts_v1');
      expect(result['production_loader'], 'not_checked');
    },
  );

  test(
    'installed source CLI finds its packaged child outside repository CWD',
    () async {
      final package = Directory('${scratch.path}/installed');
      await package.create();
      for (final name in ['lib', 'bin']) {
        for (final file in Directory(
          name,
        ).listSync(recursive: true).whereType<File>()) {
          final destination = File('${package.path}/${file.path}');
          await destination.parent.create(recursive: true);
          await file.copy(destination.path);
        }
      }
      await File('pubspec.yaml').copy('${package.path}/pubspec.yaml');
      final activeConfig = (await Isolate.packageConfig)!;
      final packages =
          jsonDecode(await File.fromUri(activeConfig).readAsString()) as Map;
      for (final entry in packages['packages'] as List) {
        final item = entry as Map;
        item['rootUri'] = item['name'] == 'llamadart'
            ? package.uri.toString()
            : activeConfig.resolve(item['rootUri'] as String).toString();
      }
      final consumer = Directory('${scratch.path}/consumer');
      await Directory('${consumer.path}/.dart_tool').create(recursive: true);
      await File(
        '${consumer.path}/pubspec.yaml',
      ).writeAsString('name: consumer\nversion: 99.88.77\n');
      final installedConfig = File(
        '${consumer.path}/.dart_tool/package_config.json',
      );
      await installedConfig.writeAsString(jsonEncode(packages));
      await File.fromUri(
        activeConfig.resolve('native_assets.yaml'),
      ).copy('${consumer.path}/.dart_tool/native_assets.yaml');
      final result = await Process.run(
        Platform.resolvedExecutable,
        [
          '--disable-dart-dev',
          '--packages=${installedConfig.path}',
          '${package.path}/bin/doctor_native.dart',
          '--runtime',
          'llama_cpp',
          '--json',
        ],
        workingDirectory: consumer.path,
        environment: {'LLAMADART_NATIVE_LIB_DIR': '/PRIVATE_DIAGNOSTIC_TOKEN'},
      );
      expect(result.exitCode, 0);
      expect(result.stderr, isEmpty);
      final report = jsonDecode(result.stdout as String) as Map;
      expect(report['native_probe']['code'], 'SURFACE_OBSERVED');
      expect(report['setup']['host']['llamadart_version'], isNot('99.88.77'));
      expect(report['setup']['overrides']['LLAMADART_NATIVE_LIB_DIR'], 'set');
      expect(result.stdout, isNot(contains('PRIVATE_DIAGNOSTIC_TOKEN')));
    },
  );

  test(
    'documented dart run command accepts its generated package snapshot',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'llamadart:doctor_native',
        '--runtime',
        'llama_cpp',
        '--json',
      ]);
      expect(result.exitCode, 0);
      final report = jsonDecode(result.stdout as String) as Map;
      expect(report['native_probe']['code'], 'SURFACE_OBSERVED');
      expect(report['native_probe']['loaded_release'], 'unknown');
    },
  );

  final liteRtRelative = switch (Abi.current()) {
    Abi.macosArm64 => 'macos/arm64/libLiteRtLm.dylib',
    Abi.linuxArm64 => 'linux/arm64/libLiteRtLm.so',
    Abi.linuxX64 => 'linux/x64/libLiteRtLm.so',
    _ => null,
  };
  final liteRtFile = File(
    '.dart_tool/llamadart/litert_lm/$liteRtLmVersion/$liteRtRelative',
  ).absolute;
  test(
    'real child opens current cached LiteRT artifact via a test declaration',
    () async {
      final result = await probe(
        'litert_lm',
        NativeDiagnosticTarget(liteRtFile.path, liteRtFile.path, const []),
      );
      expect(result['code'], 'SURFACE_OBSERVED');
      expect(result['abi_marker'], 'callback_v2_finish_v1');
      expect(result['loaded_release'], 'unknown');
    },
    skip: liteRtRelative != null && liteRtFile.existsSync()
        ? false
        : 'No matching current cached LiteRT artifact; no download performed.',
  );

  final hookCache = Directory(
    '.dart_tool/llamadart/litert_lm/$liteRtLmVersion/macos/arm64',
  );
  test(
    'documented dart run command checks the macOS LiteRT-LM hook cache',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'llamadart:doctor_native',
        '--runtime',
        'litert_lm',
        '--json',
      ]);
      expect(result.exitCode, 0);
      final probe =
          (jsonDecode(result.stdout as String) as Map)['native_probe'];
      expect(probe['code'], 'SURFACE_OBSERVED');
      expect(probe['abi_marker'], 'callback_v2_finish_v1');
      expect(probe['target_source'], 'build_hook_cache');
      expect(result.stdout, isNot(contains(hookCache.absolute.path)));
    },
    skip: Abi.current() == Abi.macosArm64 && hookCache.existsSync()
        ? false
        : 'No macOS arm64 LiteRT-LM hook cache; no download performed.',
  );
}
