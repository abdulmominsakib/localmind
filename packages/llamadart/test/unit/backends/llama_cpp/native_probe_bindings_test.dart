@TestOn('vm')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late String kernel;

  Future<void> run(String executable, List<String> arguments) async {
    final result = await Process.run(executable, arguments);
    expect(
      result.exitCode,
      0,
      reason:
          '$executable ${arguments.join(' ')}\n'
          '${result.stdout}\n${result.stderr}',
    );
  }

  setUpAll(() async {
    temp = Directory.systemTemp.createTempSync('native-probe-bindings-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final library = path.join(
      temp.path,
      Platform.isWindows
          ? 'probe.dll'
          : 'libprobe.${Platform.isMacOS ? 'dylib' : 'so'}',
    );
    await run(Platform.isWindows ? 'clang' : 'cc', [
      if (Platform.isWindows) '-fuse-ld=lld',
      Platform.isMacOS ? '-dynamiclib' : '-shared',
      if (!Platform.isWindows) '-fPIC',
      'test/fixtures/native_probe_bindings.c',
      '-o',
      library,
    ]);
    final assets = File(path.join(temp.path, 'native_assets.json'));
    assets.writeAsStringSync(
      jsonEncode({
        'format-version': [1, 0, 0],
        'native-assets': {
          Abi.current().toString(): {
            'package:llamadart/llamadart': ['absolute', library],
            'package:llamadart/llamadart_wrapper': ['absolute', library],
            'package:llamadart/ggml': ['absolute', library],
            'package:llamadart/ggml-base': ['absolute', library],
          },
        },
      }),
    );
    final sdk = path.dirname(path.dirname(Platform.resolvedExecutable));
    kernel = path.join(temp.path, 'checks.dill');
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
        kernel,
        'test/fixtures/native_probe_checks.dart',
      ],
    );
  });

  for (final mode in ['cold', 'dead-model', 'dead-vocab']) {
    test(
      'generation capability probe: $mode (fake bindings, no model)',
      () async {
        await run(Platform.resolvedExecutable, [kernel, mode]);
      },
    );
  }

  test('Windows registry code assets use the fake DLL on every host', () async {
    await run(Platform.resolvedExecutable, [kernel, 'windows-registry']);
  });

  test(
    'model diagnostics and decision-head CPU placement use fake devices',
    () async {
      await run(Platform.resolvedExecutable, [kernel, 'placement']);
    },
  );
}
