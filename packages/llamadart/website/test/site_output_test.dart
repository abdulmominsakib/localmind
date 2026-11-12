import 'dart:io';

import 'package:llamadart_website/src/tooling/site_output.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late SiteOutput output;

  void write(String path, String content) {
    File(p.join(root.path, path))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('site_output_test');
    output = SiteOutput(root);
    write('index.html', '<a href="/docs/intro">i</a><link href="/styles.css">');
    write('styles.css', '');
    write(
      'docs/intro/index.html',
      '<h2 id="setup">S</h2><a href="./guide#usage">g</a>'
          '<a href="https://example.com/x">x</a>',
    );
    write('docs/guide/index.html', '<h2 id="usage">U</h2>');
    write(
      'docs/next/intro/index.html',
      '<meta name="robots" content="noindex, nofollow"><a href="/docs/intro#setup">l</a>',
    );
    write('packages/web/x.js', '');
    output
      ..removeBuildArtifacts()
      ..flattenPages();
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('flattens pages to route.html and drops build artifacts', () {
    expect(File(p.join(root.path, 'docs/intro.html')).existsSync(), isTrue);
    expect(Directory(p.join(root.path, 'docs/intro')).existsSync(), isFalse);
    expect(Directory(p.join(root.path, 'packages')).existsSync(), isFalse);
    expect(output.routes().keys.toSet(), {
      '/',
      '/docs/intro',
      '/docs/guide',
      '/docs/next/intro',
    });
  });

  test('the sitemap skips noindex pages', () {
    expect(output.writeSitemap(), ['/', '/docs/guide', '/docs/intro']);
    expect(
      File(p.join(root.path, 'sitemap.xml')).readAsStringSync(),
      contains('<loc>https://llamadart.leehack.com/docs/intro</loc>'),
    );
  });

  test('accepts valid links and reports missing pages, files and anchors', () {
    expect(output.brokenLinks(), isEmpty);
    write(
      'docs/bad.html',
      '<a href="/docs/missing">a</a><a href="/docs/guide#nope">b</a>'
          '<img src="/img/none.png">',
    );
    expect(output.brokenLinks(), [
      '/docs/bad -> /docs/missing (missing page)',
      '/docs/bad -> /docs/guide#nope (missing anchor)',
      '/docs/bad -> /img/none.png (missing file)',
    ]);
  });

  test('resolves relative links against <base> like a browser', () {
    write('docs/based.html', '<base href="/"><a href="./guide">g</a>');
    expect(output.brokenLinks(), ['/docs/based -> ./guide (missing page)']);
  });
}
