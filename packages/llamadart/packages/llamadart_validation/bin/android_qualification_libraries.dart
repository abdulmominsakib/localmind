import 'dart:convert';
import 'dart:io';

import 'package:llamadart_validation/src/android_qualification_libraries.dart';

/// Records the actual normal-hook selection; it never copies or loads libraries.
void main(List<String> arguments) {
  if (arguments.length != 2) {
    throw const FormatException(
      'Expected archive inventory and new selection file',
    );
  }
  final inventory =
      jsonDecode(File(arguments[0]).readAsStringSync()) as Map<String, dynamic>;
  final output = File(arguments[1]);
  if (output.existsSync()) throw StateError('Selection output already exists');
  output.writeAsStringSync(
    jsonEncode(androidQualificationLibrarySelection(inventory.keys)),
    flush: true,
  );
}
