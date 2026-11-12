@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../support/suite_system_temp.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('suite_system_temp_test_');
    File(path.join(root.path, 'a.bin')).writeAsStringSync('a');
    File(path.join(root.path, 'model', 'b.xnnpack_cache'))
      ..createSync(recursive: true)
      ..writeAsStringSync('b');
    File(path.join(root.path, 'model', 'c.bin')).writeAsStringSync('c');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// Deletes like the host, except that [locked] files and every directory
  /// holding one cannot be deleted, as on Windows while a file is open.
  void Function(FileSystemEntity) lockedDelete(Set<String> locked) => (entity) {
    final blocked = locked.any(
      (file) => file == entity.path || path.isWithin(entity.path, file),
    );
    if (blocked) {
      throw FileSystemException('locked', entity.path);
    }
    entity.deleteSync(recursive: true);
  };

  String file(String relative) => path.join(root.path, relative);

  test('an unlocked root is deleted', () {
    deleteSuiteRoot(root);
    expect(root.existsSync(), isFalse);
  });

  test('Windows deletes all but the open XNNPack caches', () {
    final cache = file(path.join('model', 'b.xnnpack_cache'));
    deleteSuiteRoot(root, isWindows: true, delete: lockedDelete({cache}));
    expect(File(file('a.bin')).existsSync(), isFalse);
    expect(File(file(path.join('model', 'c.bin'))).existsSync(), isFalse);
    expect(File(cache).existsSync(), isTrue);
  });

  test('Windows still fails on any other undeletable file', () {
    expect(
      () => deleteSuiteRoot(
        root,
        isWindows: true,
        delete: lockedDelete({
          file(path.join('model', 'b.xnnpack_cache')),
          file(path.join('model', 'c.bin')),
        }),
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('other hosts fail on an undeletable XNNPack cache', () {
    expect(
      () => deleteSuiteRoot(
        root,
        isWindows: false,
        delete: lockedDelete({file(path.join('model', 'b.xnnpack_cache'))}),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(File(file('a.bin')).existsSync(), isTrue);
  });
}
