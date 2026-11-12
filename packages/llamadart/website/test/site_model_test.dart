import 'dart:convert';
import 'dart:io';

import 'package:llamadart_website/src/site/sidebar.dart';
import 'package:llamadart_website/src/site/site_model.dart';
import 'package:test/test.dart';

void main() {
  final site = SiteModel.load('.', archivedLimit: 1 << 30);
  final released =
      (jsonDecode(File('versions.json').readAsStringSync()) as List)
          .cast<String>();

  test('serves next, the latest release, and every archived release', () {
    expect(released.length, greaterThan(1));
    expect(site.versions.map((v) => v.name), ['current', ...released]);
    expect(site.versions.first.urlPrefix, 'docs/next');
    expect(site.latest.name, released.first);
    expect(site.latest.urlPrefix, 'docs');
    for (final version in site.versions.skip(2)) {
      expect(version.urlPrefix, 'docs/${version.name}');
      expect(version.kind, VersionKind.archived);
    }
  });

  test('only the latest release is indexable', () {
    expect(site.versions.where((v) => v.indexable).map((v) => v.name), [
      released.first,
    ]);
  });

  test('resolves URLs to the version that owns the longest prefix', () {
    expect(site.resolve('/docs/intro'), (site.latest, 'intro'));
    expect(site.resolve('/docs/next/intro'), (site.versions.first, 'intro'));
    final archived = site.versions[2];
    expect(site.resolve('/docs/${archived.name}/intro'), (archived, 'intro'));
    expect(site.resolve('/docs/next/missing-page'), isNull);
  });

  test('every sidebar entry in every version names an existing doc', () {
    for (final version in site.versions) {
      for (final MapEntry(key: sidebar, value: entries)
          in version.sidebars.entries) {
        for (final (id, _) in flattenSidebar(entries)) {
          expect(
            version.docs,
            contains(id),
            reason: '${version.name} $sidebar lists missing doc $id',
          );
        }
      }
    }
  });

  test('the next sidebars list every listed doc exactly once', () {
    final next = site.versions.first;
    final listed = [
      for (final entries in next.sidebars.values)
        for (final (id, _) in flattenSidebar(entries)) id,
    ];
    expect(listed.toSet().length, listed.length, reason: 'duplicate entries');
    final expected = {
      for (final MapEntry(:key, :value) in next.docs.entries)
        if (!value.unlisted) key,
    };
    expect(listed.toSet(), expected);
  });

  test('navigation uses sidebar_label and falls back to the title', () {
    final root = Directory.systemTemp.createTempSync('site_model_test');
    addTearDown(() => root.deleteSync(recursive: true));
    void write(String path, String content) => File('${root.path}/$path')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
    write('versions.json', '["1.0.0"]');
    write('sidebars.json', '{"docsSidebar": ["a", "b"]}');
    write('versioned_sidebars/version-1.0.0-sidebars.json', '{}');
    write('versioned_docs/version-1.0.0/a.md', '# A');
    write('docs/a.md', '---\ntitle: Long A title\nsidebar_label: A\n---\n');
    write('docs/b.md', '---\ntitle: B title\n---\n');
    final docs = SiteModel.load(root.path).versions.first.docs;
    expect(docs['a']!.title, 'Long A title');
    expect(docs['a']!.navLabel, 'A');
    expect(docs['b']!.navLabel, 'B title');
  });

  test('reads flat frontmatter and strips quotes', () {
    expect(readFrontmatter('---\ntitle: "A: b"\nunlisted: true\n---\n# Body'), {
      'title': 'A: b',
      'unlisted': 'true',
    });
    expect(readFrontmatter('# No frontmatter'), isEmpty);
  });
}
