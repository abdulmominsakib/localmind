import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/src/hook/native_bundle_config.dart';
import 'package:path/path.dart' as p;

import 'process.dart';

/// Desktop x64 bundles advertise CPU, Vulkan and CUDA profiles together.
/// Fail before publication if hook filtering dropped one of their modules.
void requireDesktopBackendModules(Directory bundle, {Abi? abi}) {
  final target = abi ?? Abi.current();
  if (target != Abi.linuxX64 && target != Abi.windowsX64) return;
  final libraries = Directory(p.join(bundle.path, 'lib'));
  final available = libraries.existsSync()
      ? collectAvailableBackends(
          describeNativeLibraries(
            libraries.listSync().whereType<File>().map((file) => file.path),
          ),
        )
      : <String>{};
  final missing = {'cpu', 'vulkan', 'cuda'}.difference(available);
  if (missing.isNotEmpty) {
    throw StateError(
      'Desktop validation bundle is missing backend modules: '
      '${missing.join(', ')}. Check llamadart_native_backends for $target.',
    );
  }
}

/// Null keeps the supported GGUF-only Windows arm64 and macOS x64 bundles
/// buildable; litert-lm-native publishes arm64-only macOS runtimes.
String? standaloneLiteRtTarget(Abi abi) => switch (abi) {
  Abi.macosArm64 => 'macos-arm64',
  Abi.macosX64 => null,
  Abi.linuxArm64 => 'linux-arm64',
  Abi.linuxX64 => 'linux-x64',
  Abi.windowsX64 => 'windows-x64',
  Abi.windowsArm64 => null,
  _ => throw UnsupportedError('No desktop bundle for $abi'),
};

/// Locks standalone LiteRT files to the same archive contract as the build hook.
({String checksum, Set<String> libraries}) liteRtArchiveSpec(
  String source,
  String target,
) {
  if (!RegExp(r'^(macos|linux|windows)-(arm64|x64)$').hasMatch(target)) {
    throw const FormatException('Unsupported standalone LiteRT target');
  }
  final match = RegExp(
    "\\bLiteRtLmBundleSpec\\(\\s*'$target',\\s*sha256:\\s*'([a-f0-9]{64})',\\s*requiredLibraries:\\s*\\{([^}]+)\\}",
  ).firstMatch(source);
  if (match == null) {
    throw StateError('Pinned LiteRT archive contract unavailable for $target');
  }
  final libraries = RegExp(
    "'([^']+)'",
  ).allMatches(match[2]!).map((m) => m[1]!).toSet();
  if (libraries.isEmpty ||
      libraries.any(
        (name) => !RegExp(r'^[A-Za-z0-9_]+\.(dylib|so|dll)$').hasMatch(name),
      )) {
    throw StateError('Invalid LiteRT library inventory');
  }
  return (checksum: match[1]!, libraries: libraries);
}

/// Preserves upstream install names and the public runtime's executable-relative
/// cache layout, including files the macOS hook deliberately does not emit.
Future<void> bundleLiteRtRuntime(
  String root,
  Directory destination,
  Directory scratch,
  Map<String, dynamic> provenance, {
  CommandExecutor execute = executeCommand,
  Abi? abi,
}) async {
  final targetAbi = abi ?? Abi.current();
  final target = standaloneLiteRtTarget(targetAbi);
  provenance['litert_runtime_supported'] = target != null;
  if (target == null) {
    final platform = targetAbi == Abi.macosX64 ? 'macOS x64' : 'Windows arm64';
    provenance['litert_runtime_unavailable_reason'] =
        'No pinned LiteRT artifact for $platform; GGUF only';
    if ((provenance['profile'] as String).startsWith('chat-litert-')) {
      throw UnsupportedError('LiteRT profiles are unavailable on $platform');
    }
    return;
  }
  final parts = target.split('-');
  final os = parts.first;
  final arch = parts.last;
  final spec = liteRtArchiveSpec(
    File(
      p.join(root, 'lib/src/hook/native_release_pins.dart'),
    ).readAsStringSync(),
    target,
  );
  final version = provenance['litert_tag'] as String;
  final archive = File(
    p.join(
      root,
      '.dart_tool',
      'llamadart',
      'litert_lm',
      version,
      'litert-lm-native-runtime-$target-v$version.tar.gz',
    ),
  );
  if (!archive.existsSync() ||
      (await sha256.bind(archive.openRead()).first).toString() !=
          spec.checksum) {
    throw StateError(
      'Missing or changed pinned LiteRT archive; rerun the native build hook',
    );
  }
  final unpacked = Directory(p.join(scratch.path, 'litert-runtime'))
    ..createSync();
  final result = await execute('tar', [
    '-xzf',
    archive.path,
    '-C',
    unpacked.path,
  ], timeout: const Duration(minutes: 3));
  if (result.code != 0) {
    throw StateError('Cannot unpack verified LiteRT archive');
  }
  final targetDirectory = Directory(
    p.join(
      destination.path,
      '.dart_tool',
      'llamadart',
      'litert_lm',
      version,
      os,
      arch,
    ),
  )..createSync(recursive: true);
  for (final name in spec.libraries) {
    final source = File(p.join(unpacked.path, os, arch, name));
    if (FileSystemEntity.typeSync(source.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw StateError('Pinned LiteRT archive lacks a regular library: $name');
    }
    source.copySync(p.join(targetDirectory.path, name));
  }
  provenance['litert_archive_sha256'] = spec.checksum;
  provenance['litert_runtime_layout'] = p
      .relative(targetDirectory.path, from: destination.path)
      .replaceAll('\\', '/');
}
