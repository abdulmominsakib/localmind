@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'package:llamadart/src/hook/native_archive_digest.dart';

void main() {
  late Directory tempDir;
  late File archive;
  final bytes = utf8.encode('archive bytes');
  final digest = sha256.convert(bytes).toString();
  final otherDigest = sha256.convert(utf8.encode('other')).toString();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('native_archive_digest_');
    archive = File(path.join(tempDir.path, 'bundle.tar.gz'))
      ..writeAsBytesSync(bytes);
  });

  tearDown(() => tempDir.delete(recursive: true));

  test('fileSha256 hashes the whole file', () async {
    expect(await fileSha256(archive), digest);
  });

  test('a matching archive passes and is kept', () async {
    await requireNativeArchiveSha256(
      archive: archive,
      expectedSha256: digest,
      digestSource: 'the pin',
    );
    expect(archive.existsSync(), isTrue);
  });

  test(
    'a mismatched archive is deleted with a typed, actionable error',
    () async {
      await expectLater(
        requireNativeArchiveSha256(
          archive: archive,
          expectedSha256: otherDigest,
          digestSource: 'the pin',
        ),
        throwsA(
          isA<NativeArchiveDigestException>().having(
            (error) => error.toString(),
            'toString',
            allOf(
              startsWith('NativeArchiveDigestException: '),
              contains('bundle.tar.gz has SHA-256 $digest'),
              contains('the pin expects $otherDigest'),
              contains('Rebuild to download it again'),
            ),
          ),
        ),
      );
      expect(archive.existsSync(), isFalse);
    },
  );

  group('sha256SumsEntry', () {
    String? entry(String text) =>
        sha256SumsEntry(text, fileName: 'a.tar.gz', source: 'SUMS');

    test('returns the digest listed for the file', () {
      expect(entry('$otherDigest  b.tar.gz\n$digest  a.tar.gz\n'), digest);
      expect(entry('$digest *a.tar.gz\r\n'), digest);
    });

    test('accepts a leading BOM and uppercase hex as lowercase', () {
      expect(entry('\uFEFF${digest.toUpperCase()}  a.tar.gz\n'), digest);
      expect(entry('\uFEFF$digest  a.tar.gz'), digest);
    });

    test('rejects a BOM that does not lead the text', () {
      expect(
        () => entry('$otherDigest  b.tar.gz\n\uFEFF$digest  a.tar.gz'),
        throwsA(isA<NativeArchiveDigestException>()),
      );
    });

    test('returns null when the file is not listed', () {
      expect(entry('$digest  b.tar.gz\n\n'), isNull);
      expect(entry(''), isNull);
    });

    test('does not match a file name by prefix or suffix', () {
      expect(entry('$digest  a.tar.gz.sig\n$digest  xa.tar.gz'), isNull);
    });

    test('rejects malformed lines and duplicate entries', () {
      for (final text in [
        'not-a-digest  a.tar.gz',
        '$digest a.tar.gz',
        '$digest  a.tar.gz trailing',
      ]) {
        expect(
          () => entry(text),
          throwsA(isA<NativeArchiveDigestException>()),
          reason: text,
        );
      }
      expect(
        () => entry('$digest  a.tar.gz\n$otherDigest  a.tar.gz'),
        throwsA(
          isA<NativeArchiveDigestException>().having(
            (error) => error.message,
            'message',
            contains('more than once'),
          ),
        ),
      );
    });
  });
}
