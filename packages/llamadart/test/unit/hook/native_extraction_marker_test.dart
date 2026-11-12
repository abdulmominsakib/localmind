@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'package:llamadart/src/hook/native_extraction_marker.dart';

void main() {
  late Directory cacheDir;
  late Directory extractedDir;
  late File archive;
  const archiveBytes = [1, 2, 3, 4];
  final archiveSha256 = sha256.convert(archiveBytes).toString();

  Future<bool> matches() => nativeExtractionMatchesArchive(
    extractedDir: extractedDir,
    archive: archive,
  );

  setUp(() async {
    cacheDir = await Directory.systemTemp.createTemp('extraction_marker_');
    extractedDir = Directory(path.join(cacheDir.path, 'extracted'));
    File(path.join(extractedDir.path, 'libllamadart.so'))
      ..createSync(recursive: true)
      ..writeAsStringSync('library');
    File(path.join(extractedDir.path, 'lib', 'libggml.so'))
      ..createSync(recursive: true)
      ..writeAsStringSync('ggml');
    archive = File(path.join(cacheDir.path, 'bundle.tar.gz'))
      ..writeAsBytesSync(archiveBytes);
    await writeNativeExtractionMarker(
      extractedDir: extractedDir,
      archive: archive,
      archiveSha256: archiveSha256,
    );
  });

  tearDown(() => cacheDir.delete(recursive: true));

  test('the marker sits beside extracted/', () {
    expect(
      nativeExtractionMarkerFile(extractedDir).path,
      path.join(cacheDir.path, 'extracted.json'),
    );
    expect(nativeExtractionMarkerFile(extractedDir).existsSync(), isTrue);
  });

  test('an untouched extraction matches its archive', () async {
    expect(await matches(), isTrue);
  });

  test('a library replaced by a stub of another size does not match', () async {
    File(
      path.join(extractedDir.path, 'libllamadart.so'),
    ).writeAsStringSync('fake-libllamadart.so');
    expect(await matches(), isFalse);
  });

  test('an added or removed file does not match', () async {
    final extra = File(path.join(extractedDir.path, 'libggml-cuda.so'))
      ..writeAsStringSync('stub');
    expect(await matches(), isFalse);
    extra.deleteSync();
    expect(await matches(), isTrue);
    File(path.join(extractedDir.path, 'lib', 'libggml.so')).deleteSync();
    expect(await matches(), isFalse);
  });

  test('an added link does not match', () async {
    Link(
      path.join(extractedDir.path, 'libggml-cuda.so'),
    ).createSync(path.join(extractedDir.path, 'libllamadart.so'));
    expect(await matches(), isFalse);
  }, testOn: '!windows');

  test('another archive does not match', () async {
    archive.writeAsBytesSync([4, 3, 2, 1]);
    archive.setLastModifiedSync(DateTime(2001));
    expect(await matches(), isFalse);
  });

  test(
    'a resized archive does not match at the same modification time',
    () async {
      final modified = archive.lastModifiedSync();
      archive.writeAsBytesSync([...archiveBytes, 5]);
      archive.setLastModifiedSync(modified);
      expect(await matches(), isFalse);
    },
  );

  test('the same archive with a new modification time matches', () async {
    archive.setLastModifiedSync(DateTime(2001));
    expect(await matches(), isTrue);
  });

  test('the same archive with a new modification time is not hashed again '
      'by the next build', () async {
    final modified = DateTime(2001);
    archive.setLastModifiedSync(modified);
    expect(await matches(), isTrue);

    archive.writeAsBytesSync([4, 3, 2, 1]);
    archive.setLastModifiedSync(modified);
    expect(await matches(), isTrue);
  });

  test(
    'the marker takes the new modification time and keeps the digest',
    () async {
      final modified = DateTime(2001);
      archive.setLastModifiedSync(modified);
      expect(await matches(), isTrue);

      expect(
        jsonDecode(nativeExtractionMarkerFile(extractedDir).readAsStringSync()),
        containsPair(
          'archive',
          allOf(
            containsPair('sha256', archiveSha256),
            containsPair('modified', modified.millisecondsSinceEpoch),
          ),
        ),
      );
      expect(
        File(
          '${nativeExtractionMarkerFile(extractedDir).path}.tmp',
        ).existsSync(),
        isFalse,
      );
    },
  );

  test('a marker that cannot be rewritten still matches', () async {
    archive.setLastModifiedSync(DateTime(2001));
    final marker = nativeExtractionMarkerFile(extractedDir);
    final before = marker.readAsStringSync();
    await Process.run('chmod', ['a-w', cacheDir.path]);
    addTearDown(() => Process.run('chmod', ['u+w', cacheDir.path]));
    expect(await matches(), isTrue);
    expect(marker.readAsStringSync(), before);
  }, testOn: '!windows');

  test(
    'an archive or extraction that cannot be read fails the check',
    () async {
      archive.setLastModifiedSync(DateTime(2001));
      await Process.run('chmod', ['a-r', archive.path]);
      await expectLater(matches(), throwsA(isA<FileSystemException>()));
      await Process.run('chmod', ['u+r', archive.path]);

      final lib = Directory(path.join(extractedDir.path, 'lib'));
      await Process.run('chmod', ['a-rx', lib.path]);
      addTearDown(() => Process.run('chmod', ['u+rx', lib.path]));
      await expectLater(matches(), throwsA(isA<FileSystemException>()));
    },
    testOn: '!windows',
  );

  test('a marker that cannot be renamed into place leaves no .tmp', () async {
    final marker = nativeExtractionMarkerFile(extractedDir);
    marker.deleteSync();
    File(path.join(marker.path, 'occupied')).createSync(recursive: true);
    await expectLater(
      writeNativeExtractionMarker(
        extractedDir: extractedDir,
        archive: archive,
        archiveSha256: archiveSha256,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(File('${marker.path}.tmp').existsSync(), isFalse);
  });

  test(
    'a marker write that fails leaves no .tmp and surfaces its error',
    () async {
      final failure = const FileSystemException('disk full');
      final marker = nativeExtractionMarkerFile(extractedDir);
      final before = marker.readAsStringSync();
      await expectLater(
        IOOverrides.runWithIOOverrides(
          () => writeNativeExtractionMarker(
            extractedDir: extractedDir,
            archive: archive,
            archiveSha256: archiveSha256,
          ),
          _FailingPendingWrite(failure),
        ),
        throwsA(same(failure)),
      );
      expect(File('${marker.path}.tmp').existsSync(), isFalse);
      expect(marker.readAsStringSync(), before);
    },
  );

  test('a .tmp that cannot be deleted does not hide the write error', () async {
    final failure = const FileSystemException('disk full');
    await expectLater(
      IOOverrides.runWithIOOverrides(
        () => writeNativeExtractionMarker(
          extractedDir: extractedDir,
          archive: archive,
          archiveSha256: archiveSha256,
        ),
        _FailingPendingWrite(failure, deleteFailure: true),
      ),
      throwsA(same(failure)),
    );
  });

  test('a missing archive, marker or extraction does not match', () async {
    archive.renameSync('${archive.path}.moved');
    expect(await matches(), isFalse);
    File('${archive.path}.moved').renameSync(archive.path);
    expect(await matches(), isTrue);

    nativeExtractionMarkerFile(extractedDir).deleteSync();
    expect(await matches(), isFalse);
  });

  test('a malformed marker does not match', () async {
    for (final body in [
      '',
      '{"archive":',
      '[]',
      '{"archive":{"sha256":"$archiveSha256"},"files":{}}',
      '{"files":{}}',
    ]) {
      nativeExtractionMarkerFile(extractedDir).writeAsStringSync(body);
      expect(await matches(), isFalse, reason: body);
    }
  });

  test('an empty extraction matches only an empty record', () async {
    extractedDir.deleteSync(recursive: true);
    expect(await matches(), isFalse);
    extractedDir.createSync();
    await writeNativeExtractionMarker(
      extractedDir: extractedDir,
      archive: archive,
      archiveSha256: archiveSha256,
    );
    expect(await matches(), isTrue);
  });
}

/// Makes the marker's `.tmp` fail its write after creating the file, as a full
/// disk does, which no permission on a real directory can reproduce.
final class _FailingPendingWrite extends IOOverrides {
  _FailingPendingWrite(this.failure, {this.deleteFailure = false});

  final FileSystemException failure;
  final bool deleteFailure;

  @override
  File createFile(String path) {
    final file = super.createFile(path);
    return path.endsWith('.tmp') ? _FailingPendingFile(file, this) : file;
  }
}

class _FailingPendingFile implements File {
  _FailingPendingFile(this._file, this._overrides);

  final File _file;
  final _FailingPendingWrite _overrides;

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    _file.writeAsStringSync(contents.substring(0, 1));
    throw _overrides.failure;
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) {
    if (_overrides.deleteFailure) {
      throw const FileSystemException('delete denied');
    }
    return _file.delete(recursive: recursive);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
