import 'dart:convert';
import 'dart:io';

import 'package:llamadart_validation/android_consumer_profile.dart';
import 'package:llamadart_validation/src/android_qualification_libraries.dart';
import 'package:yaml/yaml.dart';

/// Checks actual consumer configuration and exports a source-only request.
void main(List<String> arguments) {
  if (arguments.length != 4) {
    throw const FormatException(
      'Expected full|compact pubspec inventory output',
    );
  }
  final plan = AndroidConsumerProfilePlan(arguments[0]);
  final pubspec = loadYaml(File(arguments[1]).readAsStringSync()) as Map;
  final dependencies = pubspec['dependencies'];
  final devDependencies = pubspec['dev_dependencies'];
  final plugin = dependencies is Map ? dependencies['integration_test'] : null;
  if (plugin is! Map ||
      plugin.length != 1 ||
      plugin['sdk'] != 'flutter' ||
      (devDependencies is Map &&
          devDependencies.containsKey('integration_test'))) {
    throw const FormatException(
      'Release instrumentation requires integration_test as an SDK dependency, '
      'not a dev dependency, in the isolated qualification consumer',
    );
  }
  final actual = pubspec['hooks']['user_defines']['llamadart'];
  if (actual is! Map ||
      actual.length != plan.hookDefines.length ||
      plan.hookDefines.entries.any(
        (entry) => jsonEncode(actual[entry.key]) != jsonEncode(entry.value),
      )) {
    throw const FormatException(
      'Consumer hook defines differ from frozen profile',
    );
  }
  final inventory = jsonDecode(File(arguments[2]).readAsStringSync()) as Map;
  final output = File(arguments[3]);
  if (output.existsSync()) throw StateError('Output already exists');
  output.writeAsStringSync(
    jsonEncode({
      'plan': plan.wire,
      'plan_sha256': plan.hash,
      'packaging_selection': androidQualificationLibrarySelection(
        inventory.keys.cast<String>(),
        cpuProfile: plan.profile,
      ),
    }),
    flush: true,
  );
}
