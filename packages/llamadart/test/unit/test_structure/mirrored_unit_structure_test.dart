@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('every lib/src file has a mirrored unit test file', () {
    final libSrcDir = Directory('lib/src');
    final unitDir = Directory('test/unit');

    final sourceFiles =
        libSrcDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    final missing = <String>[];

    for (final sourceFile in sourceFiles) {
      final relativeSourcePath = p.relative(
        sourceFile.path,
        from: libSrcDir.path,
      );
      if (_isGeneratedSource(sourceFile)) {
        continue;
      }

      final sourceDir = p.dirname(relativeSourcePath);
      final sourceStem = p.basenameWithoutExtension(relativeSourcePath);
      final expectedTestPath = p.normalize(
        p.join(unitDir.path, sourceDir, '${sourceStem}_test.dart'),
      );

      if (!File(expectedTestPath).existsSync()) {
        missing.add('$relativeSourcePath -> ${p.relative(expectedTestPath)}');
      }
    }

    expect(
      missing,
      isEmpty,
      reason: 'Missing mirrored unit test files:\n${missing.join('\n')}',
    );
  });
}

bool _isGeneratedSource(File sourceFile) {
  final header = sourceFile.readAsLinesSync().take(20).join('\n');

  return header.contains('coverage:ignore-file') ||
      header.contains('AUTO GENERATED FILE, DO NOT EDIT.');
}
