/// IO verification for the private, source-bound Pixel Qwen3.5 qualifier.
library;

import 'dart:convert';
import 'dart:io';

import 'android_litert_qualification_io.dart';

/// Verifies every tracked mapping, then hashes each file once per capture.
///
/// [hashFile] exposes only the content-read boundary for model-free fixtures.
Future<Map<String, dynamic>> verifyPixelQwen35Mappings(
  List<int> raw,
  Directory directory,
  Map binding, {
  required bool gpu,
  Future<String> Function(File file)? hashFile,
}) async {
  final inventory = binding['libraries'] as Map;
  final canonicalDirectory = await directory.resolveSymbolicLinks();
  if (directory.path != canonicalDirectory) {
    throw StateError('Noncanonical Android native directory');
  }
  final observed = <String, String>{};
  for (final line in utf8.decode(raw).split('\n')) {
    final match = RegExp(r'(/[^\n]*\.so)(?: \(deleted\))?$').firstMatch(line);
    if (match == null) continue;
    final path = match[1]!;
    final name = Uri.file(path).pathSegments.last;
    if (!inventory.containsKey(name)) continue;
    final file = File(path);
    if (line.endsWith(' (deleted)') ||
        path != '$canonicalDirectory/$name' ||
        FileSystemEntity.typeSync(path, followLinks: false) !=
            FileSystemEntityType.file ||
        await file.resolveSymbolicLinks() != path) {
      throw StateError('Unbound or deleted native mapping');
    }
    observed[name] = path;
  }
  for (final name in [
    'libllamadart.so',
    'libllama.so',
    if (gpu) 'libggml-vulkan.so',
  ]) {
    if (!observed.containsKey(name)) {
      throw StateError('Missing runtime mapping');
    }
  }
  // Validate all paths before deduplicating expensive content reads. This map
  // belongs to one capture: a later capture must recheck the admitted bytes.
  for (final entry in observed.entries) {
    final file = File(entry.value);
    final lock = inventory[entry.key] as Map;
    if (await file.length() != lock['bytes'] ||
        await (hashFile ?? s24LiteRtFileHash)(file) != lock['sha256']) {
      throw const FormatException('Pixel native bytes differ from binding');
    }
  }
  return {'capture': captureS24LiteRtBytes(raw), 'verified_paths': observed};
}

/// Embeds exact native bytes so collection does not depend on file permissions.
/// A lifetime is accepted only after native disposal and stderr restoration.
Future<Map<String, dynamic>> capturePixelQwen35Stderr(
  File file, {
  required int journalRemainingBytes,
}) async {
  const maximum = 8 * 1024 * 1024;
  const recordReserve = 64 * 1024;
  if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
          FileSystemEntityType.file ||
      await file.resolveSymbolicLinks() != file.path) {
    throw StateError('Native stderr must be a canonical regular file');
  }
  final length = await file.length();
  final encodedLength = ((length + 2) ~/ 3) * 4;
  if (length > maximum ||
      encodedLength + recordReserve > journalRemainingBytes) {
    throw StateError('Native stderr capture exceeds native or journal bound');
  }
  final input = await file.open();
  late List<int> raw;
  try {
    raw = await input.read(length + 1);
    if (raw.length != length || await input.length() != length) {
      throw StateError('Native stderr changed after disposal');
    }
  } finally {
    await input.close();
  }
  return {
    'schema': 'pixel-native-stderr.v1',
    'file': file.uri.pathSegments.last,
    ...captureS24LiteRtBytes(raw),
  };
}
