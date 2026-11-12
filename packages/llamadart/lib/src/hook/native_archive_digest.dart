/// SHA-256 verification for the runtime archives `hook/build.dart` downloads.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

final _sha256SumsLine = RegExp(r'^([0-9a-fA-F]{64}) [ *](\S+)$');

/// Thrown when a native runtime archive cannot be verified against the
/// SHA-256 it must have, or when no trusted SHA-256 exists for it.
///
/// The hook never extracts an archive that raised this.
final class NativeArchiveDigestException implements Exception {
  /// Creates an exception with an actionable [message].
  const NativeArchiveDigestException(this.message);

  /// Reports that the downloaded [archiveName] hashed to [actualSha256] where
  /// [digestSource] expects [expectedSha256], after the archive was deleted.
  NativeArchiveDigestException.mismatch({
    required String archiveName,
    required String expectedSha256,
    required String actualSha256,
    required String digestSource,
  }) : message =
           'Downloaded $archiveName has SHA-256 $actualSha256, but '
           '$digestSource expects $expectedSha256. The archive was deleted '
           'and not used. Rebuild to download it again; if the mismatch '
           'repeats, the published release asset differs from the one this '
           'build trusts, so do not use it and report it to the release '
           'owner.';

  /// Describes the archive, the expected and actual digests where known, and
  /// what to do next.
  final String message;

  @override
  String toString() => 'NativeArchiveDigestException: $message';
}

/// Returns the lowercase hex SHA-256 of [file], read as a stream so large
/// archives are not held in memory.
Future<String> fileSha256(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

/// Deletes [archive] and throws [NativeArchiveDigestException] unless its
/// SHA-256 is [expectedSha256].
///
/// [digestSource] names where [expectedSha256] came from, such as the pin
/// file or a release's `SHA256SUMS`.
Future<void> requireNativeArchiveSha256({
  required File archive,
  required String expectedSha256,
  required String digestSource,
}) async {
  final actualSha256 = await fileSha256(archive);
  if (actualSha256 == expectedSha256) {
    return;
  }
  await archive.delete();
  throw NativeArchiveDigestException.mismatch(
    archiveName: path.basename(archive.path),
    expectedSha256: expectedSha256,
    actualSha256: actualSha256,
    digestSource: digestSource,
  );
}

/// Returns the SHA-256 that a release's `SHA256SUMS` [checksumText] lists for
/// [fileName], or `null` when it lists none.
///
/// Each non-blank line must be `<sha256>  <file>` (or `<sha256> *<file>`), and
/// [fileName] may appear only once. A leading byte order mark and uppercase
/// hex are accepted; the returned digest is lowercase.
String? sha256SumsEntry(
  String checksumText, {
  required String fileName,
  required String source,
}) {
  String? entry;
  final text = checksumText.startsWith('\uFEFF')
      ? checksumText.substring(1)
      : checksumText;
  final lines = text.split('\n');
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index].trimRight();
    if (line.isEmpty) {
      continue;
    }
    final match = _sha256SumsLine.firstMatch(line);
    if (match == null) {
      throw NativeArchiveDigestException(
        '$source has a malformed line ${index + 1}: "$line". Expected '
        '"<sha256>  <file>".',
      );
    }
    if (match.group(2) != fileName) {
      continue;
    }
    if (entry != null) {
      throw NativeArchiveDigestException(
        '$source lists $fileName more than once.',
      );
    }
    entry = match.group(1)!.toLowerCase();
  }
  return entry;
}
