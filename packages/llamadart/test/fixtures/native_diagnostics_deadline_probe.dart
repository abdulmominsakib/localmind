// The unit test runs this program with its own deadline, so regressions in
// parent filesystem handling cannot hang the test runner's VM.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:llamadart/src/platform/io/native_diagnostics.dart';

Future<void> main(List<String> arguments) async {
  final mode = arguments[0];
  final directory = Directory(arguments[1]);
  final pidFile = File(arguments[2]);
  final config = File('${directory.path}/package_config.json');
  await config.writeAsString('{}');
  final manifest = File('${directory.path}/native_assets.yaml');
  await manifest.writeAsString(
    jsonEncode({
      'format-version': [1, 0, 0],
      'native-assets': {
        'macos_arm64': {
          'package:llamadart/llamadart': [
            'absolute',
            File('${directory.path}/absent').absolute.path,
          ],
        },
      },
    }),
  );
  if (mode == 'fifo-manifest' || mode == 'link-manifest') {
    await manifest.delete();
    final fifo = mode == 'link-manifest'
        ? '${manifest.path}.pipe'
        : manifest.path;
    final created = await Process.run('mkfifo', [fifo]);
    if (created.exitCode != 0) {
      exitCode = 2;
      return;
    }
    if (mode == 'link-manifest') await Link(manifest.path).create(fifo);
  }
  final packageConfig = (await Isolate.packageConfig)!;
  final script = File(arguments[3]).absolute;
  Process? launched;
  var starts = 0;
  final elapsed = Stopwatch()..start();
  final result = await runNativeDiagnostic(
    'llama_cpp',
    packageConfig: config.uri,
    childScript: script.uri,
    abi: 'macos_arm64',
    timeout: const Duration(seconds: 2),
    start: (executable, _) async {
      starts++;
      if (mode == 'swap-manifest') {
        await manifest.delete();
        final created = await Process.run('mkfifo', [manifest.path]);
        if (created.exitCode != 0) throw StateError('FIFO control unavailable');
      }
      launched = await Process.start(executable, [
        '--disable-dart-dev',
        '--packages=${packageConfig.toFilePath()}',
        script.path,
        if (mode != 'regular' && !mode.endsWith('manifest')) mode,
      ]);
      await pidFile.writeAsString('${launched!.pid}', flush: true);
      return launched!;
    },
  );
  final reaped =
      launched == null ||
      await launched!.exitCode.timeout(const Duration(milliseconds: 300)) == 0;
  stdout.writeln(
    jsonEncode({
      'code': result['code'],
      'starts': starts,
      'elapsed_ms': elapsed.elapsedMilliseconds,
      'child_reaped': reaped,
      'private_output': !jsonEncode(result).contains(directory.path),
    }),
  );
}
