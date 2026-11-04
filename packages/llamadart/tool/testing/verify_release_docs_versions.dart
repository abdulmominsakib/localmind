#!/usr/bin/env dart

import 'dart:io';

// Keep these maps in sync when adding companion packages or moving the current
// installation docs. Historical website/versioned_docs pages are intentionally
// excluded so archived release docs can keep their original package versions.
//
// During release-prep PRs, current install docs are expected to track the
// in-repository package versions being prepared. Publishing still happens only
// after merge; the release-prep PR merge is the approval boundary for the
// post-merge release automation.
const Map<String, String> _packagePubspecs = <String, String>{
  'llamadart': 'pubspec.yaml',
  'llamadart_llama_cpp_flutter':
      'packages/llamadart_llama_cpp_flutter/pubspec.yaml',
  'llamadart_litert_lm_flutter':
      'packages/llamadart_litert_lm_flutter/pubspec.yaml',
};

const Map<String, List<String>> _currentDocDependencies =
    <String, List<String>>{
      'README.md': <String>[
        'llamadart',
        'llamadart_llama_cpp_flutter',
        'llamadart_litert_lm_flutter',
      ],
      'website/docs/getting-started/installation.md': <String>[
        'llamadart',
        'llamadart_llama_cpp_flutter',
        'llamadart_litert_lm_flutter',
      ],
      'packages/llamadart_llama_cpp_flutter/README.md': <String>[
        'llamadart',
        'llamadart_llama_cpp_flutter',
      ],
      'packages/llamadart_litert_lm_flutter/README.md': <String>[
        'llamadart',
        'llamadart_litert_lm_flutter',
      ],
    };

final RegExp _dependencyLine = RegExp(
  r'^\s+(llamadart(?:_[a-z0-9_]+)?):\s+\^([0-9]+\.[0-9]+\.[0-9]+(?:[-+][^\s#]+)?)',
);
final RegExp _fenceLine = RegExp(r'^\s*```\s*([^\s`]*)?\s*$');
final RegExp _versionLine = RegExp(r'^version:\s*(\S+)\s*$');

void main() {
  final errors = <String>[];
  final versions = <String, String>{};
  for (final entry in _packagePubspecs.entries) {
    final version = _readPubspecVersion(entry.value, errors);
    if (version != null) {
      versions[entry.key] = version;
    }
  }

  if (errors.isEmpty) {
    for (final entry in _currentDocDependencies.entries) {
      _checkCurrentDoc(
        path: entry.key,
        expectedPackages: entry.value,
        versions: versions,
        errors: errors,
      );
    }
  }

  if (errors.isNotEmpty) {
    stderr.writeln('Release docs version verification failed:');
    for (final error in errors) {
      stderr.writeln('- $error');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Release docs versions verified: '
    '${versions.entries.map((entry) => '${entry.key} ${entry.value}').join(', ')}.',
  );
}

String? _readPubspecVersion(String path, List<String> errors) {
  final lines = _readLines(path, errors);
  if (lines == null) {
    return null;
  }

  for (final line in lines) {
    final match = _versionLine.firstMatch(line);
    if (match != null) {
      return match.group(1)!;
    }
  }

  errors.add('$path does not contain a top-level version field.');
  return null;
}

void _checkCurrentDoc({
  required String path,
  required List<String> expectedPackages,
  required Map<String, String> versions,
  required List<String> errors,
}) {
  final expectedPackageSet = expectedPackages.toSet();
  final seen = <String>{};
  final lines = _readLines(path, errors);
  if (lines == null) {
    return;
  }

  var inFence = false;
  var inYamlFence = false;
  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index];
    final fenceMatch = _fenceLine.firstMatch(line);
    if (fenceMatch != null) {
      if (inFence) {
        inFence = false;
        inYamlFence = false;
      } else {
        final language = fenceMatch.group(1)?.toLowerCase();
        inFence = true;
        inYamlFence = language == 'yaml' || language == 'yml';
      }
      continue;
    }

    if (!inYamlFence) {
      continue;
    }

    final match = _dependencyLine.firstMatch(line);
    if (match == null) {
      continue;
    }

    final package = match.group(1)!;
    if (!expectedPackageSet.contains(package)) {
      continue;
    }

    seen.add(package);
    final documentedVersion = match.group(2)!;
    final expectedVersion = versions[package]!;
    if (documentedVersion != expectedVersion) {
      errors.add(
        '$path:${index + 1} documents $package ^$documentedVersion, '
        'but ${packagePubspecPath(package)} is $expectedVersion.',
      );
    }
  }

  for (final package in expectedPackages) {
    if (!seen.contains(package)) {
      errors.add(
        '$path is missing a current YAML dependency snippet for '
        '$package ^${versions[package]}.',
      );
    }
  }
}

List<String>? _readLines(String path, List<String> errors) {
  final file = File(path);
  if (!file.existsSync()) {
    errors.add('$path does not exist.');
    return null;
  }

  try {
    return file.readAsLinesSync();
  } on FileSystemException catch (error) {
    errors.add('Could not read $path: ${error.message}.');
    return null;
  }
}

String packagePubspecPath(String package) => _packagePubspecs[package]!;
