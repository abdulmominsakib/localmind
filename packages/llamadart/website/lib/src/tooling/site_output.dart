import 'dart:io';

import 'package:path/path.dart' as p;

import '../site/site_model.dart';

/// Post-processes `jaspr build` output into the deployed layout and checks
/// it: every internal link and fragment must resolve.
class SiteOutput {
  SiteOutput(this.directory);

  final Directory directory;

  static const _assetExtensions = {
    '.css',
    '.js',
    '.mjs',
    '.json',
    '.svg',
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.ico',
    '.txt',
    '.xml',
    '.woff',
    '.woff2',
    '.pdf',
  };

  /// Removes build-tool output the pages never reference.
  void removeBuildArtifacts() {
    final packages = Directory(p.join(directory.path, 'packages'));
    if (packages.existsSync()) packages.deleteSync(recursive: true);
  }

  /// Moves every `route/index.html` to `route.html`, the layout Docusaurus
  /// used with `trailingSlash: false`, so hosts serve `/docs/intro` without
  /// redirecting to `/docs/intro/`.
  void flattenPages() {
    for (final file in _htmlFiles()) {
      final relative = p.relative(file.path, from: directory.path);
      if (p.basename(relative) != 'index.html' || relative == 'index.html') {
        continue;
      }
      final dir = file.parent;
      file.renameSync('${dir.path}.html');
      if (dir.listSync().isEmpty) dir.deleteSync();
    }
  }

  /// Every page route, e.g. `/`, `/docs/intro`, mapped to its file.
  Map<String, File> routes() => {
    for (final file in _htmlFiles()) routeOf(file): file,
  };

  String routeOf(File file) {
    final relative = p
        .split(p.relative(file.path, from: directory.path))
        .join('/');
    if (relative == 'index.html') return '/';
    if (relative.endsWith('/index.html')) {
      return '/${relative.substring(0, relative.length - '/index.html'.length)}';
    }
    return '/${p.posix.withoutExtension(relative)}';
  }

  /// Writes `sitemap.xml` listing every page that allows indexing.
  List<String> writeSitemap() {
    final indexed = [
      for (final MapEntry(key: route, value: file) in routes().entries)
        if (!_noindex.hasMatch(file.readAsStringSync())) route,
    ]..sort();
    final xml = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">');
    for (final route in indexed) {
      xml
        ..writeln('  <url>')
        ..writeln('    <loc>$siteUrl${route == '/' ? '/' : route}</loc>')
        ..writeln('    <changefreq>weekly</changefreq>')
        ..writeln('    <priority>0.6</priority>')
        ..writeln('  </url>');
    }
    xml.writeln('</urlset>');
    File(p.join(directory.path, 'sitemap.xml')).writeAsStringSync('$xml');
    return indexed;
  }

  static final _noindex = RegExp(
    r'<meta[^>]*name="robots"[^>]*content="[^"]*noindex',
  );
  static final _base = RegExp(r'<base[^>]*href="([^"]*)"');
  static final _reference = RegExp(r'''\s(?:href|src)="([^"]*)"''');
  static final _id = RegExp(r'''\s(?:id|name)="([^"]*)"''');

  /// Returns one message per internal link whose page, file or fragment does
  /// not exist, resolving links the way a browser does (honoring `<base>`).
  List<String> brokenLinks() {
    final pages = routes();
    final ids = <String, Set<String>>{};
    Set<String> idsOf(String route) => ids[route] ??= {
      for (final m in _id.allMatches(pages[route]!.readAsStringSync()))
        _unescape(m[1]!),
    };

    final problems = <String>[];
    for (final MapEntry(key: route, value: file) in pages.entries) {
      final html = file.readAsStringSync();
      var pageUri = Uri.parse('https://site$route');
      if (_base.firstMatch(html) case final base?) {
        pageUri = pageUri.resolve(_unescape(base[1]!));
      }
      for (final match in _reference.allMatches(html)) {
        final raw = _unescape(match[1]!);
        if (raw.isEmpty ||
            raw.startsWith(RegExp('(mailto|javascript|data):'))) {
          continue;
        }
        final target = pageUri.resolve(raw);
        if (target.host != 'site') continue;
        var path = Uri.decodeFull(target.path);
        if (path.length > 1 && path.endsWith('/')) {
          path = path.substring(0, path.length - 1);
        }
        final String? error;
        if (_assetExtensions.contains(p.extension(path))) {
          error = File(p.join(directory.path, path.substring(1))).existsSync()
              ? null
              : 'missing file';
        } else if (!pages.containsKey(path)) {
          error = 'missing page';
        } else if (target.hasFragment &&
            target.fragment.isNotEmpty &&
            !idsOf(path).contains(Uri.decodeComponent(target.fragment))) {
          error = 'missing anchor';
        } else {
          error = null;
        }
        if (error != null) problems.add('$route -> $raw ($error)');
      }
    }
    return problems;
  }

  Iterable<File> _htmlFiles() => directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.html'));

  static String _unescape(String value) => value
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}
