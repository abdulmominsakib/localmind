import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

Object? canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return {for (final key in keys) key: canonical(value[key])};
  }
  if (value is List) return value.map(canonical).toList();
  return value;
}

void main(List<String> args) {
  final document = loadYaml(File(args[0]).readAsStringSync()) as YamlMap;
  final packages = document['packages'] as YamlMap;
  final external = <String, Object?>{};
  for (final entry in packages.entries) {
    final package = entry.value as YamlMap;
    final source = package['source'];
    if (source == 'path') continue;
    if (source == 'hosted') {
      final description = package['description'] as YamlMap;
      if (!RegExp(
        r'^[0-9a-f]{64}$',
      ).hasMatch(description['sha256'].toString())) {
        throw StateError('Hosted dependency lacks content hash: ${entry.key}');
      }
    } else if (source == 'git') {
      final description = package['description'] as YamlMap;
      if (!RegExp(
        r'^[0-9a-f]{40}$',
      ).hasMatch(description['resolved-ref'].toString())) {
        throw StateError('Git dependency lacks resolved commit: ${entry.key}');
      }
    } else if (source != 'sdk') {
      throw StateError('Unbound dependency source: ${entry.key} $source');
    }
    external[entry.key.toString()] = {
      'source': source,
      'version': package['version'],
      'description': package['description'],
    };
  }
  File(args[1]).writeAsStringSync('${jsonEncode(canonical(external))}\n');
  File(
    '${args[1]}.full.json',
  ).writeAsStringSync('${jsonEncode(canonical(document))}\n');
  stdout.writeln('DEPENDENCY_RESOLUTION_BOUND ${external.length}');
}
