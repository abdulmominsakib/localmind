import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'stage_companion_package.dart';

/// SHA-256 of each selected file's bytes, keyed by its archive-relative name.
typedef CompanionContents = Map<String, String>;

/// Extracts identities without writing untrusted archive paths to disk.
CompanionContents publishedCompanionContents(List<int> compressed) {
  final contents = <String, String>{};
  final names = <String>{};
  final decoder = TarDecoder();
  decoder.decodeBytes(
    _uncompressedArchive(compressed),
    verify: true,
    callback: (entry) {
      final name = entry.isDirectory && entry.name.endsWith('/')
          ? entry.name.substring(0, entry.name.length - 1)
          : entry.name;
      _checkArchivePath(name);
      if (!names.add(name) || entry.isSymbolicLink) {
        throw const FormatException('Duplicate or linked archive input.');
      }
      if (entry.isFile) {
        contents[name] = sha256.convert(entry.content).toString();
      }
    },
  );
  // TarDecoder represents non-file types as directories. Admit only the
  // regular-file and directory types pub itself emits, including no hardlinks.
  if (decoder.files.any(
    (entry) => entry.typeFlag != '0' && entry.typeFlag != '5',
  )) {
    throw const FormatException('Non-regular archive input.');
  }
  if (!contents.containsKey('pubspec.yaml')) {
    throw const FormatException('Published archive has no pubspec.yaml.');
  }
  return contents;
}

List<int> _uncompressedArchive(List<int> compressed) {
  final output = _ArchiveBytes();
  final decoder = gzip.decoder.startChunkedConversion(output);
  decoder.add(compressed);
  decoder.close();
  return output.bytes.takeBytes();
}

class _ArchiveBytes implements Sink<List<int>> {
  final BytesBuilder bytes = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) {
    if (bytes.length + chunk.length > 256 * 1024 * 1024) {
      throw const FormatException('Expanded archive exceeds 256 MiB.');
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}

void _checkArchivePath(String name) {
  if (name.isEmpty ||
      name.contains('\\') ||
      name.contains(':') ||
      name.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
      p.posix.isAbsolute(name) ||
      name
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw const FormatException('Non-canonical archive path.');
  }
}

CompanionContents _snapshot(Directory stage) => {
  for (final entity in stage.listSync(recursive: true, followLinks: false))
    if (entity is File)
      p.relative(entity.path, from: stage.path).replaceAll('\\', '/'): sha256
          .convert(entity.readAsBytesSync())
          .toString()
    else if (entity is Link)
      p.relative(entity.path, from: stage.path).replaceAll('\\', '/'):
          'link:${sha256.convert(utf8.encode(entity.targetSync()))}',
};

/// Reads pub's archive selection from an unchanged publisher-staged snapshot.
///
/// Validation is skipped only for selection: a release's core may not exist on
/// pub.dev yet. The publisher still resolves, validates and dry-runs normally.
Future<CompanionContents> candidateCompanionContents(
  Directory package, {
  Future<ProcessResult> Function(Directory stage)? runPub,
}) async {
  final temporary = await Directory.systemTemp.createTemp('companion-content-');
  try {
    final stage = Directory(p.join(temporary.path, 'package'));
    stageCompanionPackage(package, stage);
    final before = _snapshot(stage);
    final result = await (runPub ?? _pubSelection)(stage);
    if (result.exitCode != 0) {
      throw StateError(
        'Pub archive selection failed (exit ${result.exitCode}).',
      );
    }
    final output = '${result.stdout}\n${result.stderr}'.replaceAll(
      '\r\n',
      '\n',
    );
    const marker = 'FINE: Creating .tar.gz stream containing:\n';
    if (marker.allMatches(output).length != 1) {
      throw const FormatException(
        'Pub archive inventory is missing or ambiguous.',
      );
    }
    final selected = <String>{};
    for (final line in output.split(marker).last.split('\n')) {
      if (!line.startsWith('    | ')) break;
      final path = line.substring(6);
      if (!p.isAbsolute(path)) {
        throw const FormatException('Pub archive path is not absolute.');
      }
      final resolved = File(path).resolveSymbolicLinksSync();
      final root = stage.resolveSymbolicLinksSync();
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (resolved == root && type == FileSystemEntityType.directory) continue;
      if (!p.isWithin(root, resolved)) {
        throw const FormatException('Pub archive input escapes staging.');
      }
      if (type == FileSystemEntityType.directory) continue;
      if (type != FileSystemEntityType.file) {
        throw const FormatException('Pub selected a non-regular input.');
      }
      final relative = p.relative(path, from: stage.path).replaceAll('\\', '/');
      _checkArchivePath(relative);
      if (!before.containsKey(relative) || !selected.add(relative)) {
        throw const FormatException('Unknown or duplicate pub archive input.');
      }
    }
    final after = _snapshot(stage);
    if (before.length != after.length ||
        before.entries.any((entry) => after[entry.key] != entry.value)) {
      throw StateError('Staged package changed during pub archive selection.');
    }
    if (!selected.contains('pubspec.yaml')) {
      throw const FormatException('Pub archive inventory has no pubspec.yaml.');
    }
    return {for (final name in selected) name: before[name]!};
  } finally {
    await temporary.delete(recursive: true);
  }
}

Future<ProcessResult> _pubSelection(Directory stage) async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    [
      'pub',
      '--directory=${stage.path}',
      '--verbose',
      'publish',
      '--dry-run',
      '--skip-validation',
    ],
    workingDirectory: stage.path,
    environment: {'PUB_CACHE': p.join(stage.parent.path, 'pub-cache')},
  );
  final output = process.stdout.transform(utf8.decoder).join();
  final errors = process.stderr.transform(utf8.decoder).join();
  try {
    final code = await process.exitCode.timeout(const Duration(minutes: 2));
    return ProcessResult(process.pid, code, await output, await errors);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
    rethrow;
  }
}
