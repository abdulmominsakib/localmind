import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Compiles the Dart [script] to a kernel snapshot and returns its path; the
/// snapshot is deleted after the calling test, or after the group when called
/// from `setUpAll`.
///
/// `dart <script>` recompiles the script and all of its imports on every
/// launch, which costs seconds per run on CI. Pass the snapshot to `dart` in
/// place of the script to run the same program.
Future<String> compileDartScript(String script) async {
  final directory = await Directory.systemTemp.createTemp('dart_script_');
  addTearDown(() => directory.delete(recursive: true));
  final snapshot = p.join(
    directory.path,
    '${p.basenameWithoutExtension(script)}.dill',
  );
  final result = await Process.run(Platform.resolvedExecutable, <String>[
    'compile',
    'kernel',
    '--packages=${p.absolute('.dart_tool/package_config.json')}',
    '--output=$snapshot',
    p.absolute(script),
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'dart compile kernel $script exited ${result.exitCode}:\n'
      '${result.stdout}${result.stderr}',
    );
  }
  return snapshot;
}

/// Compiles the Dart [script] to a kernel snapshot that loads the native
/// assets this test run already bundled, and returns its path; the snapshot is
/// deleted after the calling test.
///
/// `dart run` re-runs the build hooks and copies the native libraries into
/// `.dart_tool/lib`, which Windows refuses while the test process has them
/// loaded. The snapshot runs with `dart <snapshot>` and loads those files in
/// place instead.
Future<String> compileDartScriptWithBundledNativeAssets(String script) async {
  final nativeAssets = File('.dart_tool/native_assets.yaml');
  if (!nativeAssets.existsSync()) {
    throw StateError(
      '${nativeAssets.path} is missing; run this under `dart test`, which '
      'bundles the native assets.',
    );
  }
  final directory = await Directory.systemTemp.createTemp('dart_script_');
  addTearDown(() => directory.delete(recursive: true));
  final snapshot = p.join(
    directory.path,
    '${p.basenameWithoutExtension(script)}.dill',
  );
  final sdk = p.dirname(p.dirname(Platform.resolvedExecutable));
  final result = await Process.run(
    p.join(
      sdk,
      'bin',
      Platform.isWindows ? 'dartaotruntime.exe' : 'dartaotruntime',
    ),
    [
      p.join(sdk, 'bin', 'snapshots', 'gen_kernel_aot.dart.snapshot'),
      '--platform',
      p.join(sdk, 'lib', '_internal', 'vm_platform_strong.dill'),
      '--packages',
      p.absolute('.dart_tool/package_config.json'),
      '--native-assets',
      nativeAssets.absolute.path,
      '--output',
      snapshot,
      p.absolute(script),
    ],
  );
  if (result.exitCode != 0) {
    throw StateError(
      'gen_kernel $script exited ${result.exitCode}:\n'
      '${result.stdout}${result.stderr}',
    );
  }
  return snapshot;
}
