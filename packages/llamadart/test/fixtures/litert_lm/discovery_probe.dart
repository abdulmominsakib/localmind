import 'dart:convert';
import 'dart:io';

import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';

void main(List<String> arguments) {
  try {
    final client = createLiteRtLmSelectedRuntimeClient(
      allowV1: arguments.first != 'legacy-off',
      libraryPath: arguments.length > 1 ? arguments[1] : null,
      eager: true,
    );
    stdout.writeln(jsonEncode({'finishReasons': client.supportsFinishReasons}));
    client.dispose();
  } on Object catch (error) {
    stderr.writeln('${error.runtimeType}: $error');
    exitCode = 10;
  }
}
