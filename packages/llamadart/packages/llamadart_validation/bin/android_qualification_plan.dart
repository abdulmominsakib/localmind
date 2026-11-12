import 'dart:convert';
import 'dart:io';

import 'package:llamadart_validation/android_qualification.dart';

/// Exports only the fixed request contract; never downloads or dispatches.
void main(List<String> arguments) {
  if (arguments.length != 2) {
    throw const FormatException('Expected a35|pixel8a and a new output file');
  }
  final scenario = AndroidQualificationScenario.values.byName(arguments[0]);
  final file = File(arguments[1]);
  if (file.existsSync()) throw StateError('Plan output already exists');
  file.writeAsStringSync(
    jsonEncode(AndroidQualificationPlan(scenario).wire),
    flush: true,
  );
}
