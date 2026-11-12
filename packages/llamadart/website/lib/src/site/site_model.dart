import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'sidebar.dart';

const siteUrl = 'https://llamadart.leehack.com';
const githubUrl = 'https://github.com/leehack/llamadart';
const pubUrl = 'https://pub.dev/packages/llamadart';
const apiUrl = 'https://pub.dev/documentation/llamadart/latest/';
const demoUrl = 'https://leehack-llamadart.static.hf.space';

enum VersionKind { next, latest, archived }

class DocMeta {
  const DocMeta({
    required this.title,
    required this.unlisted,
    this.description,
    this.sidebarLabel,
  });

  final String title;
  final String? description;
  final bool unlisted;
  final String? sidebarLabel;

  /// Short name for the sidebar and pager; the title stays descriptive.
  String get navLabel => sidebarLabel ?? title;
}

class DocVersion {
  DocVersion({
    required this.name,
    required this.urlPrefix,
    required this.directory,
    required this.sidebars,
    required this.kind,
    required this.docs,
  });

  /// `current` for the development docs, otherwise the release number.
  final String name;

  /// Route prefix without slashes, e.g. `docs/next`.
  final String urlPrefix;

  /// Content directory relative to the site root, e.g. `docs`.
  final String directory;
  final Map<String, List<SidebarEntry>> sidebars;
  final VersionKind kind;
  final Map<String, DocMeta> docs;

  String get label => kind == VersionKind.next ? 'Next' : 'v$name';
  String docUrl(String id) => '/$urlPrefix/$id';

  /// Only the latest release is indexed by search engines and site search.
  bool get indexable => kind == VersionKind.latest;
}

/// Every docs version the site serves, loaded from the Docusaurus-compatible
/// layout: `docs/` + `sidebars.json` for the next release, and
/// `versioned_docs/`, `versioned_sidebars/` and `versions.json` for releases.
class SiteModel {
  SiteModel(this.versions)
    : _byPrefixLength = [...versions]
        ..sort((a, b) => b.urlPrefix.length.compareTo(a.urlPrefix.length));

  static SiteModel? _instance;
  static SiteModel get instance => _instance ??= SiteModel.load('.');

  /// Next, latest, then archived releases newest first.
  final List<DocVersion> versions;

  // Longest prefix first, so `/docs/next/x` never resolves under `/docs`.
  final List<DocVersion> _byPrefixLength;

  DocVersion get latest =>
      versions.firstWhere((v) => v.kind == VersionKind.latest);

  /// Resolves the version and doc id served at [url].
  (DocVersion, String)? resolve(String url) {
    for (final version in _byPrefixLength) {
      final prefix = '/${version.urlPrefix}/';
      if (!url.startsWith(prefix)) continue;
      final id = url.substring(prefix.length);
      if (version.docs.containsKey(id)) return (version, id);
    }
    return null;
  }

  /// Loads every version under [root]. `DOCS_ARCHIVED=<n>` keeps only the
  /// newest n archived releases, for faster local iteration.
  factory SiteModel.load(String root, {int? archivedLimit}) {
    archivedLimit ??= int.tryParse(Platform.environment['DOCS_ARCHIVED'] ?? '');
    final names = (_readJson(p.join(root, 'versions.json')) as List)
        .cast<String>();
    if (names.isEmpty) {
      throw const FormatException('versions.json lists no released version.');
    }
    DocVersion released(String name, VersionKind kind) => DocVersion(
      name: name,
      urlPrefix: kind == VersionKind.latest ? 'docs' : 'docs/$name',
      directory: p.join('versioned_docs', 'version-$name'),
      sidebars: parseSidebars(
        _readJson(
              p.join(root, 'versioned_sidebars', 'version-$name-sidebars.json'),
            )
            as Map<String, Object?>,
      ),
      kind: kind,
      docs: _indexDocs(p.join(root, 'versioned_docs', 'version-$name')),
    );

    return SiteModel([
      DocVersion(
        name: 'current',
        urlPrefix: 'docs/next',
        directory: 'docs',
        sidebars: parseSidebars(
          _readJson(p.join(root, 'sidebars.json')) as Map<String, Object?>,
        ),
        kind: VersionKind.next,
        docs: _indexDocs(p.join(root, 'docs')),
      ),
      released(names.first, VersionKind.latest),
      for (final name in names.skip(1).take(archivedLimit ?? names.length))
        released(name, VersionKind.archived),
    ]);
  }

  static Object? _readJson(String path) =>
      jsonDecode(File(path).readAsStringSync());

  static Map<String, DocMeta> _indexDocs(String directory) {
    final docs = <String, DocMeta>{};
    final files =
        Directory(directory)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.md'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      final id = p.posix.withoutExtension(
        p.split(p.relative(file.path, from: directory)).join('/'),
      );
      final frontmatter = readFrontmatter(file.readAsStringSync());
      docs[id] = DocMeta(
        title: frontmatter['title'] ?? id,
        description: frontmatter['description'],
        unlisted: frontmatter['unlisted'] == 'true',
        sidebarLabel: frontmatter['sidebar_label'],
      );
    }
    return docs;
  }
}

/// Reads flat `key: value` frontmatter; the docs use no nested keys.
Map<String, String> readFrontmatter(String source) {
  final lines = const LineSplitter().convert(source);
  if (lines.isEmpty || lines.first.trim() != '---') return const {};
  final values = <String, String>{};
  for (final line in lines.skip(1)) {
    if (line.trim() == '---') break;
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    var value = line.substring(colon + 1).trim();
    if (value.length >= 2 &&
        (value.startsWith('"') || value.startsWith("'")) &&
        value.endsWith(value[0])) {
      value = value.substring(1, value.length - 1);
    }
    values[line.substring(0, colon).trim()] = value;
  }
  return values;
}
