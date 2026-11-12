@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:llamadart/src/hook/native_release_pins.dart';
import 'package:llamadart/src/platform/io/native_diagnostics_hook_cache.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

const _v1Libraries = [
  'libCLiteRTLM_mac.dylib',
  'libGemmaModelConstraintProvider.dylib',
  'libLiteRtLm.dylib',
  'libwebgpu_dawn.dylib',
];

void main() {
  late Directory scratch;
  late Directory packageRoot;
  late File packageConfig;
  late Directory cache;

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('diagnostic_hook_cache_');
    packageRoot = Directory(path.join(scratch.path, 'llamadart'));
    cache = Directory(
      path.join(
        packageRoot.path,
        '.dart_tool',
        'llamadart',
        'litert_lm',
        liteRtLmVersion,
        'macos',
        'arm64',
      ),
    );
    await cache.create(recursive: true);
    packageConfig = File(
      path.join(scratch.path, 'consumer', '.dart_tool', 'package_config.json'),
    );
    await packageConfig.parent.create(recursive: true);
    await packageConfig.writeAsString(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {
            'name': 'llamadart',
            'rootUri': packageRoot.uri.toString(),
            'packageUri': 'lib/',
          },
        ],
      }),
    );
  });
  tearDown(() => scratch.delete(recursive: true));

  Future<void> populate(Iterable<String> libraries) async {
    for (final library in libraries) {
      await File(path.join(cache.path, library)).writeAsString('');
    }
  }

  test(
    'targets the complete macOS hook cache under the llamadart root',
    () async {
      await populate(_v1Libraries);

      final target = nativeDiagnosticLiteRtLmHookCacheTarget(
        packageConfig,
        'macos_arm64',
      )!;

      String cached(String name) =>
          path.normalize(path.join(cache.absolute.path, name));
      expect(target.primary, cached('libLiteRtLm.dylib'));
      expect(target.wrapper, target.primary);
      expect(target.companions, [
        for (final library in _v1Libraries)
          if (library != 'libLiteRtLm.dylib') cached(library),
      ]);
    },
  );

  test('finds no target for a missing or incomplete hook cache', () async {
    expect(
      nativeDiagnosticLiteRtLmHookCacheTarget(packageConfig, 'macos_arm64'),
      isNull,
    );
    await populate(
      _v1Libraries.where((name) => name != 'libwebgpu_dawn.dylib'),
    );
    expect(
      nativeDiagnosticLiteRtLmHookCacheTarget(packageConfig, 'macos_arm64'),
      isNull,
    );
  });

  test('finds no target without a llamadart package entry', () async {
    await populate(_v1Libraries);
    await packageConfig.writeAsString(
      jsonEncode({'configVersion': 2, 'packages': <Object>[]}),
    );
    expect(
      nativeDiagnosticLiteRtLmHookCacheTarget(packageConfig, 'macos_arm64'),
      isNull,
    );
    await packageConfig.delete();
    expect(
      nativeDiagnosticLiteRtLmHookCacheTarget(packageConfig, 'macos_arm64'),
      isNull,
    );
  });

  test(
    'reads the package config only as a bounded regular file',
    () async {
      await populate(_v1Libraries);
      final valid = await packageConfig.readAsString();
      expect(
        nativeDiagnosticLiteRtLmHookCacheTarget(packageConfig, 'macos_arm64'),
        isNotNull,
      );

      await packageConfig.writeAsString(valid.padRight(256 * 1024 + 1));
      expect(
        nativeDiagnosticLiteRtLmHookCacheTarget(packageConfig, 'macos_arm64'),
        isNull,
      );

      final real = File(path.join(scratch.path, 'real_package_config.json'));
      await real.writeAsString(valid);
      await packageConfig.delete();
      await Link(packageConfig.path).create(real.path);
      expect(
        nativeDiagnosticLiteRtLmHookCacheTarget(packageConfig, 'macos_arm64'),
        isNull,
      );
    },
    skip: Platform.isWindows ? 'File links need elevation on Windows.' : false,
  );

  test('ignores hook caches outside macOS arm64', () async {
    await populate(_v1Libraries);
    for (final abi in ['macos_x64', 'linux_x64', 'windows_x64']) {
      expect(
        nativeDiagnosticLiteRtLmHookCacheTarget(packageConfig, abi),
        isNull,
      );
    }
  });
}
