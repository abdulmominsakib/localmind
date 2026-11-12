import 'dart:convert';
import 'dart:io';

import 'package:llamadart/src/core/diagnostics/runtime_setup_report.dart';
import 'package:llamadart/src/core/exceptions.dart';

const String _usage = '''
Usage: dart run llamadart:doctor [--json]
       dart run llamadart:doctor --help

Produces a model-free desktop setup report (macOS, Linux, Windows).
Exit 0 means a report was produced, not that a native runtime was verified.
The collector initializes no native libraries and uses no network or commands.
Before main, dart run's build hook can prepare/download assets or fail.
Web/mobile and Flutter app/device/browser validation are outside this scope.
Exit codes: 0 report/help, 1 report unavailable, 64 invalid arguments.''';

Future<void> main(List<String> arguments) async {
  if (arguments.length > 1 ||
      (arguments.isNotEmpty &&
          !const {'--json', '--help', '-h'}.contains(arguments.single))) {
    stderr.writeln('doctor: invalid arguments. Use --help.');
    exitCode = 64;
    return;
  }
  if (arguments.isNotEmpty && arguments.single != '--json') {
    stdout.writeln(_usage);
    return;
  }
  try {
    final report = await collectLlamaRuntimeSetupReport();
    stdout.writeln(
      arguments.isNotEmpty ? jsonEncode(report.toJson()) : report.toText(),
    );
  } on LlamaUnsupportedException {
    stderr.writeln(
      'doctor: report unavailable. Run on macOS, Linux or Windows desktop; '
      'validate mobile/Web in the intended app/device/browser.',
    );
    exitCode = 1;
  } catch (_) {
    // Raw failures can contain local paths or environment values.
    stderr.writeln('doctor: report unavailable. Retry on a supported desktop.');
    exitCode = 1;
  }
}
