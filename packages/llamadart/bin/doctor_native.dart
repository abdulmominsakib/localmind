import 'dart:convert';
import 'dart:io';

import 'package:llamadart/src/core/diagnostics/runtime_setup_report.dart';
import 'package:llamadart/src/platform/io/native_diagnostics.dart';

const _usage = '''
Usage: dart run llamadart:doctor_native --runtime <llama_cpp|litert_lm|stable_diffusion> [--json]
       dart run llamadart:doctor_native --help

Opt-in desktop Dart source check of one locally declared native artifact, or,
for undeclared macOS LiteRT-LM, the runtime the build hook keeps in its cache.
Loads files in an isolated process; checks selected symbols/static ABI markers.
No engine, model, GPU/device probe or inference is started. Native constructors
can run when libraries open. Production app loading and loaded release identity
remain unchecked. The default doctor and public setup collector do not load runtimes.
The child runs no hooks/network; dart run can prepare assets before this command.
Regular local files are required; special files and manifest/IPC links are refused.
The coordinator has a 30s budget plus a 3s termination/cleanup reserve, assuming
responsive local filesystem operations; arbitrary kernel/filesystem stalls are outside scope.
Exit codes: 0 report/help (including failed checks), 1 no report, 64 invalid arguments.''';

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 &&
      const {'--help', '-h'}.contains(arguments.single)) {
    stdout.writeln(_usage);
    return;
  }
  final json = arguments.length == 3 && arguments.last == '--json';
  if ((arguments.length != 2 && !json) ||
      arguments.firstOrNull != '--runtime' ||
      !nativeDiagnosticRuntimes.contains(arguments.elementAtOrNull(1))) {
    stderr.writeln('doctor_native: invalid arguments. Use --help.');
    exitCode = 64;
    return;
  }
  try {
    final setup = await collectLlamaRuntimeSetupReport();
    final probe = await runNativeDiagnostic(arguments[1]);
    final report = {
      'schema_version': 1,
      'scope': 'isolated_desktop_native_probe',
      'setup': setup.toJson(),
      'native_probe': probe,
    };
    stdout.writeln(
      json
          ? jsonEncode(report)
          : nativeDiagnosticTextReport(
              probe,
              overridesSet: setup.overrides.values.any((set) => set),
            ),
    );
  } catch (_) {
    stderr.writeln(
      'doctor_native: report unavailable. Use a supported desktop Dart source invocation.',
    );
    exitCode = 1;
  }
}
