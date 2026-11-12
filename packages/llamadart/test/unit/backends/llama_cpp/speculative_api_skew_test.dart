@TestOn('vm')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory temp;
  final kernels = <String, ({String snapshot, String library})>{};

  Future<void> run(String executable, List<String> arguments) async {
    final result = await Process.run(executable, arguments);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }

  setUpAll(() async {
    temp = Directory.systemTemp.createTempSync('speculative-api-skew-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final sdk = path.dirname(path.dirname(Platform.resolvedExecutable));
    for (final variant in ['legacy', 'retired', 'missing']) {
      final library = path.join(
        temp.path,
        '$variant.${Platform.isWindows
            ? 'dll'
            : Platform.isMacOS
            ? 'dylib'
            : 'so'}',
      );
      await run(Platform.isWindows ? 'clang' : 'cc', [
        if (Platform.isWindows) '-fuse-ld=lld',
        Platform.isMacOS ? '-dynamiclib' : '-shared',
        if (!Platform.isWindows) '-fPIC',
        '-DCONTEXT_PARAMS_SIZE=${sizeOf<llama_context_params>()}',
        if (variant == 'legacy') '-DRETAIN_LEGACY_QUERIES',
        if (variant == 'missing') '-DOMIT_PROCESS_BATCH',
        'test/fixtures/speculative_api_runtime.c',
        '-o',
        library,
      ]);
      final assets = File(path.join(temp.path, '$variant-assets.json'))
        ..writeAsStringSync(
          jsonEncode({
            'format-version': [1, 0, 0],
            'native-assets': {
              Abi.current().toString(): {
                'package:llamadart/llamadart': ['absolute', library],
                'package:llamadart/llamadart_wrapper': ['absolute', library],
              },
            },
          }),
        );
      final snapshot = path.join(temp.path, '$variant.dill');
      await run(
        path.join(
          sdk,
          'bin',
          Platform.isWindows ? 'dartaotruntime.exe' : 'dartaotruntime',
        ),
        [
          path.join(sdk, 'bin', 'snapshots', 'gen_kernel_aot.dart.snapshot'),
          '--platform',
          path.join(sdk, 'lib', '_internal', 'vm_platform_strong.dill'),
          '--packages',
          path.absolute('.dart_tool/package_config.json'),
          '--native-assets',
          assets.path,
          '--output',
          snapshot,
          'test/fixtures/speculative_api_checks.dart',
        ],
      );
      kernels[variant] = (snapshot: snapshot, library: library);
    }
  });

  for (final mode in ['direct', 'windows', 'dynamic']) {
    for (final variant in ['legacy', 'retired', 'missing']) {
      test(
        '$mode binds $variant speculative runtime without legacy queries',
        () async {
          final kernel = kernels[variant]!;
          await run(Platform.resolvedExecutable, [
            kernel.snapshot,
            mode,
            variant == 'missing' ? 'missing' : 'complete',
            kernel.library,
          ]);
        },
      );
    }
  }
}
