@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/src/platform/io/windows_delete_refusal.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('llamadart_delete_refusal_');
    addTearDown(() => root.delete(recursive: true));
  });

  group('a refused Windows delete', () {
    late File model;

    setUp(() {
      model = File(path.join(root.path, 'tiny.gguf'))
        ..writeAsStringSync('gguf');
    });

    void makeReadOnly() {
      final result = Platform.isWindows
          ? Process.runSync('attrib', ['+R', model.path])
          : Process.runSync('chmod', ['a-w', model.path]);
      expect(result.exitCode, 0);
      addTearDown(
        () => Platform.isWindows
            ? Process.runSync('attrib', ['-R', model.path])
            : Process.runSync('chmod', ['u+w', model.path]),
      );
    }

    test('is in use for a sharing, lock or mapped-file violation', () async {
      for (final code in <int>[32, 33, 1224]) {
        expect(await isWindowsDeleteRefusedForOpenFile(model, code), isTrue);
      }
    });

    test('is in use for an access denial on a writable file, as for a mapped '
        'model', () async {
      expect(await isWindowsDeleteRefusedForOpenFile(model, 5), isTrue);
    });

    test('is permanent for an access denial on a read-only file', () async {
      makeReadOnly();
      expect(await isWindowsDeleteRefusedForOpenFile(model, 5), isFalse);
    });

    test('is permanent for other errors', () async {
      for (final code in <int?>[null, 2, 3, 145]) {
        expect(await isWindowsDeleteRefusedForOpenFile(model, code), isFalse);
      }
    });
  });
}
