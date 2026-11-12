import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
// This private artifact verifier shares the owning package's loader contract.
// Inference still runs exclusively through the public engine adapter.
// ignore: implementation_imports
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
// ignore: implementation_imports
import 'package:llamadart/src/hook/native_bundle_config.dart';
import 'package:path/path.dart' as p;

import 'runtime_environment.dart';

/// Checks the portable payload before inference. Mutable run output and model
/// caches may live beside it, but executable/library directories remain sealed.
/// This proves the supplied payload, not accelerator placement or code signing.
Future<Map<String, dynamic>> verifyDesktopValidationBundle(
  Directory directory, {
  Map<String, String>? environment,
}) async {
  requireValidationRuntimeEnvironment(environment: environment, portable: true);
  final root = Directory(directory.resolveSymbolicLinksSync());
  final manifestFile = File(p.join(root.path, 'bundle-manifest.json'));
  final manifestBytes = manifestFile.readAsBytesSync();
  final manifest = jsonDecode(utf8.decode(manifestBytes)) as Map;
  if (manifest['schema_version'] != 1 || manifest['target'] != 'desktop') {
    throw const FormatException('Expected a desktop validation bundle');
  }
  final files = Map<String, dynamic>.from(manifest['files'] as Map);
  if (!files.containsKey('environment.json') ||
      !files.containsKey(
        'bin/llamadart-validate${Platform.isWindows ? '.exe' : ''}',
      )) {
    throw const FormatException('Incomplete desktop validation inventory');
  }
  if (!files.keys.any((name) => describeNativeLibrary(name).isPrimary)) {
    throw const FormatException('Desktop native code asset is missing');
  }
  // Use the runtime's own required-file contract so missing cache members
  // cannot trigger discovery in an unchecked ancestor directory.
  final abi = Abi.current();
  final libraries = liteRtLmRequiredLibrariesForAbi(abi);
  if (libraries.isNotEmpty) {
    final candidates = liteRtLmCacheDirectoryCandidatesForAbi(abi);
    final cache = candidates.singleWhere(
      (candidate) => candidate.contains('/'),
    );
    final layout =
        '.dart_tool/llamadart/litert_lm/${manifest['litert_tag']}/$cache';
    if (manifest['litert_runtime_supported'] != true ||
        manifest['litert_runtime_layout'] != layout ||
        libraries.any((name) => !files.containsKey('$layout/$name'))) {
      throw const FormatException('Incomplete pinned LiteRT runtime layout');
    }
    for (final alternate in candidates.where(
      (candidate) => candidate != cache,
    )) {
      if (Directory(
        p.join(
          root.path,
          '.dart_tool/llamadart/litert_lm',
          '${manifest['litert_tag']}',
          alternate,
        ),
      ).existsSync()) {
        throw const FormatException(
          'Alternate LiteRT cache can shadow bundled runtime',
        );
      }
    }
  }
  for (final entry in files.entries) {
    final parts = entry.key.split('/');
    if (p.posix.isAbsolute(entry.key) ||
        entry.key.contains('\\') ||
        parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw const FormatException('Unsafe desktop bundle member');
    }
    var path = root.path;
    for (final part in parts) {
      path = p.join(path, part);
      if (FileSystemEntity.typeSync(path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const FormatException('Symlink in desktop bundle');
      }
    }
    final file = File(path);
    final expected = entry.value as Map;
    if (!file.existsSync() ||
        await file.length() != expected['bytes'] ||
        (await sha256.bind(file.openRead()).first).toString() !=
            expected['sha256']) {
      throw FormatException('Desktop bundle checksum mismatch: ${entry.key}');
    }
  }
  // Ambient sidecars in loader search directories must not change resolution.
  for (final name in [
    'bin',
    'lib',
    '.dart_tool/lib',
    '.dart_tool/llamadart',
    'Frameworks',
  ]) {
    final sealed = Directory(p.join(root.path, name));
    if (!sealed.existsSync()) continue;
    for (final entity in sealed.listSync(recursive: true, followLinks: false)) {
      if (entity is Directory) continue;
      final key = p
          .relative(entity.path, from: root.path)
          .replaceAll('\\', '/');
      if (entity is Link || !files.containsKey(key)) {
        throw const FormatException('Unexpected desktop runtime member');
      }
    }
  }
  for (final entity in root.listSync(followLinks: false)) {
    final name = p.basename(entity.path);
    if (RegExp(r'\.(so(\.[0-9]+)*|dylib|dll)$').hasMatch(name) &&
        (entity is Link || !files.containsKey(name))) {
      throw const FormatException('Unexpected desktop runtime sidecar');
    }
  }
  final provenance =
      jsonDecode(File(p.join(root.path, 'environment.json')).readAsStringSync())
          as Map<String, dynamic>;
  final identity = Map<String, dynamic>.from(manifest)
    ..remove('schema_version')
    ..remove('files');
  if (provenance.length != identity.length ||
      provenance.entries.any((entry) => identity[entry.key] != entry.value)) {
    throw const FormatException('Desktop environment disagrees with bundle');
  }
  if (provenance['build_os'] != Platform.operatingSystem ||
      provenance['build_abi'] != abi.toString()) {
    throw const FormatException('Desktop bundle targets another OS or ABI');
  }
  return {
    ...provenance,
    'runtime_payload_verified': true,
    'runtime_bundle_sha256': sha256.convert(manifestBytes).toString(),
  };
}
