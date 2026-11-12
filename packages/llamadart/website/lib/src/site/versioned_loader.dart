import 'package:file/local.dart';
import 'package:jaspr_content/jaspr_content.dart';
import 'package:path/path.dart' as p;

import 'site_model.dart';

/// Serves one docs version from its content directory, mounted under the
/// version's URL prefix (`/docs`, `/docs/next`, `/docs/<release>`).
class VersionedDocsLoader extends FilesystemLoader {
  VersionedDocsLoader(this.version)
    : super(version.directory, filterExtensions: const {'.md'});

  final DocVersion version;

  static const _fs = LocalFileSystem();

  FilePageSource _source(String id) => FilePageSource(
    '${version.urlPrefix}/$id.md',
    _fs.file(p.join(version.directory, '$id.md')),
    this,
  );

  @override
  Future<List<FilePageSource>> loadPageSources() async => [
    for (final id in version.docs.keys) _source(id),
  ];

  @override
  void addFile(String path) {
    if (p.extension(path) != '.md') return;
    final id = p.posix.withoutExtension(
      p.split(p.relative(path, from: version.directory)).join('/'),
    );
    addSource(_source(id));
  }
}
