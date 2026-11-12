import 'dart:convert';
import 'dart:io';

import 'package:llamadart_website/src/tooling/version_cut.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  String read(String path) => File(p.join(root.path, path)).readAsStringSync();
  void write(String path, String content) {
    File(p.join(root.path, path))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('version_cut_test');
    write('docs/intro.md', '# Intro');
    write('docs/guides/a.md', '# A');
    write('sidebars.json', '{"docsSidebar": ["intro", "guides/a"]}');
    write('versions.json', '["0.1.0"]');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('snapshots docs and sidebars and makes the version latest', () {
    expect(cutDocsVersion(root.path, '0.2.0'), isTrue);
    expect(read('versioned_docs/version-0.2.0/guides/a.md'), '# A');
    expect(jsonDecode(read('versioned_sidebars/version-0.2.0-sidebars.json')), {
      'docsSidebar': ['intro', 'guides/a'],
    });
    expect(jsonDecode(read('versions.json')), ['0.2.0', '0.1.0']);
  });

  test('skips a version that is already published', () {
    expect(cutDocsVersion(root.path, '0.1.0'), isFalse);
    expect(
      Directory(p.join(root.path, 'versioned_docs')).existsSync(),
      isFalse,
    );
  });

  test('rejects malformed versions and half-written snapshots', () {
    expect(() => cutDocsVersion(root.path, 'v0.2.0'), throwsArgumentError);
    expect(() => cutDocsVersion(root.path, '0.2.0-dev'), throwsArgumentError);
    write('versioned_docs/version-0.3.0/intro.md', '');
    expect(() => cutDocsVersion(root.path, '0.3.0'), throwsStateError);
    expect(jsonDecode(read('versions.json')), ['0.1.0']);
  });
}
