import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

// The private harness cannot be a root dependency without creating a cycle.
// ignore: avoid_relative_lib_imports
import '../../../packages/llamadart_validation/lib/src/manifest.dart';

import 'process.dart';

/// Derives the opt-in Android report contract from clean source and its profile.
Future<({List<String> defines, Map<String, dynamic> binding})>
deriveInternalDiagnosticContract(
  String root,
  String runId,
  Map<String, dynamic> profileData,
  String executionPath,
  Map<String, dynamic> provenance, {
  CommandExecutor execute = executeCommand,
}) async {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$').hasMatch(runId)) {
    throw const FormatException('Invalid internal diagnostic run id');
  }
  if (provenance['source_dirty'] != false || executionPath != 'public_api') {
    throw StateError(
      'Internal diagnostic builds require clean public-API source',
    );
  }
  if (!RegExp(r'^[a-f0-9]{40}$').hasMatch('${provenance['source_commit']}') ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch('${provenance['hook_sha256']}') ||
      !RegExp(
        r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$',
      ).hasMatch('${provenance['litert_tag']}')) {
    throw StateError('Invalid diagnostic source or runtime identity');
  }
  final profile = ValidationProfile.fromJson({
    ...profileData,
    'execution_path': executionPath,
  });
  final listed = await execute('git', ['ls-files', '-z'], directory: root);
  if (listed.code != 0 || !listed.output.endsWith('\u0000')) {
    throw StateError('Cannot establish tracked diagnostic source inventory');
  }
  final paths = listed.output.split('\u0000')..removeLast();
  if (paths.isEmpty || paths.toSet().length != paths.length) {
    throw StateError('Empty or duplicate diagnostic source inventory');
  }
  paths.sort();
  final inventory = <String, dynamic>{};
  final resolvedRoot = Directory(root).resolveSymbolicLinksSync();
  for (final relative in paths) {
    // Git emits POSIX paths even when the build host uses Windows separators.
    if (p.posix.isAbsolute(relative) ||
        p.windows.rootPrefix(relative).isNotEmpty ||
        p.posix.normalize(relative) != relative ||
        relative == '..' ||
        relative.startsWith('../') ||
        relative.contains('\\')) {
      throw StateError('Invalid diagnostic source path');
    }
    final file = File(p.join(resolvedRoot, relative));
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        !p.isWithin(resolvedRoot, file.resolveSymbolicLinksSync())) {
      throw StateError('Diagnostic source must be a confined regular file');
    }
    final bytes = file.readAsBytesSync();
    inventory[relative] = {
      'bytes': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
    };
  }
  final binding = <String, dynamic>{
    'run_id': runId,
    'profile_hash': jsonHash(profile.data),
    'model_sha256': profile.modelHash,
    'model_bytes': profile.model['bytes'],
    'source_commit': provenance['source_commit'],
    'source_snapshot_sha256': jsonHash(inventory),
    'source_dirty': false,
    'hook_sha256': provenance['hook_sha256'],
    'litert_tag': provenance['litert_tag'],
    'expected_case_ids': profile.caseIds,
  };
  return (
    defines: [
      'VALIDATION_INTERNAL_DIAGNOSTIC=true',
      'VALIDATION_DIAGNOSTIC_RUN_ID=$runId',
      'VALIDATION_DIAGNOSTIC_PROFILE_HASH=${binding['profile_hash']}',
      'VALIDATION_DIAGNOSTIC_MODEL_SHA256=${binding['model_sha256']}',
      'VALIDATION_DIAGNOSTIC_MODEL_BYTES=${binding['model_bytes']}',
      'VALIDATION_DIAGNOSTIC_SOURCE_SHA256=${binding['source_snapshot_sha256']}',
      'VALIDATION_DIAGNOSTIC_CASE_IDS=${profile.caseIds.join(',')}',
    ],
    binding: binding,
  );
}
