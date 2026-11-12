@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:llamadart/src/hook/native_release_pins.dart';
import 'package:test/test.dart';

void main() {
  test('child validates request nonce before writing any result', () async {
    final config = (await Isolate.packageConfig)!;
    for (final nonce in ['0' * 48, 'PRIVATE_DIAGNOSTIC_TOKEN']) {
      final directory = await Directory.systemTemp.createTemp(
        'llamadart_native_diagnostic_',
      );
      try {
        final output = File('${directory.path}/result.json');
        final manifest = File('${directory.path}/native_assets.yaml');
        await manifest.writeAsString(
          jsonEncode({
            'format-version': [1, 0, 0],
            'native-assets': {
              'macos_arm64': {
                'package:llamadart/llamadart': [
                  'absolute',
                  File('${directory.path}/missing').absolute.path,
                ],
              },
            },
          }),
        );
        final process = await Process.start(Platform.resolvedExecutable, [
          '--disable-dart-dev',
          '--packages=${config.toFilePath()}',
          File(
            'lib/src/platform/io/native_diagnostics_child.dart',
          ).absolute.path,
        ]);
        final out = process.stdout.transform(utf8.decoder).join();
        final err = process.stderr.transform(utf8.decoder).join();
        process.stdin.write(
          jsonEncode({
            'runtime': 'llama_cpp',
            'nonce': nonce,
            'output': output.path,
            'phase': '${directory.path}/phase',
            'manifest': manifest.path,
            'abi': 'macos_arm64',
          }),
        );
        await process.stdin.close();
        expect(await process.exitCode, nonce.startsWith('0') ? 0 : 1);
        expect(await output.exists(), nonce.startsWith('0'));
        if (await output.exists()) {
          expect(
            (jsonDecode(await output.readAsString()) as Map)['code'],
            'ARTIFACT_MISSING',
          );
        }
        expect(await out, isEmpty);
        expect(await err, isEmpty);
      } finally {
        await directory.delete(recursive: true);
      }
    }
  });
  test(
    'child probes the macOS LiteRT-LM hook cache only when undeclared',
    () async {
      final config = (await Isolate.packageConfig)!;
      final directory = await Directory.systemTemp.createTemp(
        'llamadart_native_diagnostic_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final root = Directory('${directory.path}/llamadart');
      final cache = Directory(
        '${root.path}/.dart_tool/llamadart/litert_lm/$liteRtLmVersion/'
        'macos/arm64',
      );
      final manifest = File('${directory.path}/native_assets.yaml');
      await manifest.writeAsString(
        jsonEncode({
          'format-version': [1, 0, 0],
          'native-assets': {'macos_arm64': <String, Object>{}},
        }),
      );
      await File('${directory.path}/package_config.json').writeAsString(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {
              'name': 'llamadart',
              'rootUri': root.uri.toString(),
              'packageUri': 'lib/',
            },
          ],
        }),
      );
      Future<Map<Object?, Object?>> check(
        String runtime, {
        Map<String, String>? environment,
      }) async {
        final output = File('${directory.path}/result.json');
        if (await output.exists()) await output.delete();
        final process = await Process.start(Platform.resolvedExecutable, [
          '--disable-dart-dev',
          '--packages=${config.toFilePath()}',
          File(
            'lib/src/platform/io/native_diagnostics_child.dart',
          ).absolute.path,
        ], environment: environment);
        final out = process.stdout.transform(utf8.decoder).join();
        final err = process.stderr.transform(utf8.decoder).join();
        process.stdin.write(
          jsonEncode({
            'runtime': runtime,
            'nonce': '0' * 48,
            'output': output.path,
            'phase': '${directory.path}/phase',
            'manifest': manifest.path,
            'abi': 'macos_arm64',
          }),
        );
        await process.stdin.close();
        expect(await process.exitCode, 0);
        expect(await out, isEmpty);
        expect(await err, isEmpty);
        return jsonDecode(await output.readAsString()) as Map;
      }

      final missing = await check('litert_lm');
      expect(missing['code'], 'ASSET_NOT_DECLARED');
      expect(missing['source'], 'local_manifest_declaration');

      await cache.create(recursive: true);
      for (final library in [
        'libCLiteRTLM_mac.dylib',
        'libGemmaModelConstraintProvider.dylib',
        'libLiteRtLm.dylib',
        'libwebgpu_dawn.dylib',
      ]) {
        await File('${cache.path}/$library').writeAsString('');
      }
      // Empty files cannot load, so reaching the open phase proves the cached
      // files were selected without loading anything real.
      final cached = await check('litert_lm');
      expect(cached['source'], 'build_hook_cache');
      expect(cached['phase'], 'open');
      expect(cached['code'], isNot('ASSET_NOT_DECLARED'));

      // The documented choice: the target is the hook cache, never the
      // directory override, which the runtime would refuse here as incomplete.
      final overridden = await check(
        'litert_lm',
        environment: {'LLAMADART_LITERT_LM_LIB_DIR': directory.path},
      );
      expect(overridden['source'], 'build_hook_cache');
      expect(overridden['phase'], 'open');

      final otherRuntime = await check('llama_cpp');
      expect(otherRuntime['code'], 'ASSET_NOT_DECLARED');
      expect(otherRuntime['source'], 'local_manifest_declaration');
    },
  );
  test(
    'packaged child rejects malformed/unbounded requests without raw output',
    () async {
      for (final input in ['PRIVATE_DIAGNOSTIC_TOKEN', 'x' * 33000, '{}']) {
        final config = (await Isolate.packageConfig)!;
        final process = await Process.start(Platform.resolvedExecutable, [
          '--disable-dart-dev',
          '--packages=${config.toFilePath()}',
          File(
            'lib/src/platform/io/native_diagnostics_child.dart',
          ).absolute.path,
        ]);
        final out = process.stdout.transform(utf8.decoder).join();
        final err = process.stderr.transform(utf8.decoder).join();
        process.stdin.write(input);
        await process.stdin.close();
        expect(await process.exitCode, 1);
        expect(await out, isEmpty);
        expect(await err, isEmpty);
      }
    },
  );
}
