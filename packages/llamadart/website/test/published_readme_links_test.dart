import 'dart:convert';
import 'dart:io';

import 'package:jaspr_content/jaspr_content.dart';
import 'package:llamadart_website/src/site/docusaurus_markdown.dart';
import 'package:test/test.dart';

Future<List<Node>> parse(String markdown, String url) async {
  final page = Page(
    path: '${url.substring(1)}.md',
    url: url,
    content: markdown,
    config: PageConfig(
      templateEngine: const DocusaurusMarkdown(),
      parsers: const [MarkdownParser()],
      extensions: [HeadingAnchorsExtension()],
    ),
    loader: FilesystemLoader('docs'),
  );
  page.parseFrontmatter();
  await page.renderTemplate([page]);
  return page.applyExtensions(page.parseNodes());
}

Iterable<ElementNode> elements(Iterable<Node> nodes) sync* {
  for (final node in nodes.whereType<ElementNode>()) {
    yield node;
    yield* elements(node.children ?? []);
  }
}

List<String> destinationProblems(
  List<Node> nodes,
  String fragment,
  String destination,
) {
  final start = nodes.indexWhere(
    (node) => node is ElementNode && node.attributes['id'] == fragment,
  );
  if (start < 0) return ['missing anchor $fragment'];
  final section = nodes
      .skip(start + 1)
      .takeWhile(
        (node) =>
            node is! ElementNode || !RegExp(r'^h[1-6]$').hasMatch(node.tag),
      );
  if (!elements(section).any(
    (node) =>
        node.tag == 'a' &&
        node.attributes['href'] == destination &&
        node.innerText.isNotEmpty,
  )) {
    return ['missing visible migration link $fragment -> $destination'];
  }
  return [];
}

void main() {
  // These are occurrences from the four immutable 0.17.0 package READMEs;
  // archive byte identity was verified before extracting this fixture.
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/published_readme_links.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final links = (fixture['links'] as List).cast<Map<String, dynamic>>();

  test(
    'published occurrences retain duplicates and fourteen unique targets',
    () {
      expect(links.length, 17);
      expect(links.map((link) => link['url']).toSet().length, 14);
      expect(links.map((link) => link['readme']).toSet().length, 4);
    },
  );

  for (final prefix in ['/docs/next', '/docs']) {
    test(
      'published links have useful destinations at $prefix after cut',
      () async {
        for (final link in links) {
          final original = Uri.parse(link['url'] as String);
          final id = original.path.replaceFirst(RegExp(r'^/docs/(next/)?'), '');
          final destination = '$prefix/${link['destination']}';
          final nodes = await parse(
            File('docs/$id.md').readAsStringSync(),
            '$prefix/$id',
          );
          expect(
            destinationProblems(nodes, original.fragment, destination),
            isEmpty,
            reason: '${link['readme']}: $original',
          );
          final target = Uri.parse(destination);
          final targetId = target.path.substring(prefix.length + 1);
          final targetNodes = await parse(
            File('docs/$targetId.md').readAsStringSync(),
            target.path,
          );
          expect(
            elements(
              targetNodes,
            ).any((node) => node.attributes['id'] == target.fragment),
            isTrue,
            reason: 'migration destination $target',
          );
        }
      },
    );
  }

  test(
    'renaming a mapping or changing its destination fails the guard',
    () async {
      final source = File(
        'docs/platforms/native-build-hooks.md',
      ).readAsStringSync();
      const destination =
          '/docs/next/platforms/diagnose-setup#desktop-setup-report';
      final renamed = await parse(
        source.replaceFirst('### Desktop setup report', '### Renamed report'),
        '/docs/next/platforms/native-build-hooks',
      );
      expect(
        destinationProblems(renamed, 'desktop-setup-report', destination),
        ['missing anchor desktop-setup-report'],
      );
      final miswired = await parse(
        source.replaceFirst(
          './diagnose-setup#desktop-setup-report',
          './diagnose-setup#isolated-native-check',
        ),
        '/docs/next/platforms/native-build-hooks',
      );
      expect(
        destinationProblems(miswired, 'desktop-setup-report', destination),
        contains(startsWith('missing visible migration link')),
      );
    },
  );

  test('unchanged published fragments still have real content', () async {
    for (final (id, fragment) in [
      ('getting-started/installation', 'requirements'),
      ('guides/image-generation', 'bundle-the-runtime'),
    ]) {
      final nodes = await parse(
        File('docs/$id.md').readAsStringSync(),
        '/docs/next/$id',
      );
      expect(
        elements(nodes).any((node) => node.attributes['id'] == fragment),
        isTrue,
      );
    }
  });
}
