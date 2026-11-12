import 'dart:io';

import 'package:llamadart/src/backends/litert_lm/litert_lm_model_link.dart';

/// Links the model at `args[0]` under the parent directory `args[1]` and
/// prints the link directory's mode string and entry count.
///
/// Run in its own process so a test can set the umask for it alone.
Future<void> main(List<String> args) async {
  final link = (await LiteRtLmModelLink.create(
    args[0],
    parent: Directory(args[1]),
  ))!;
  final directory = File(link.path).parent;
  stdout.writeln(
    '${directory.statSync().modeString()} ${directory.listSync().length}',
  );
  link.dispose();
}
