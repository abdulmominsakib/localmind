@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/release/companion_package_contents.dart';
import '../../../tool/release/companion_pub_preflight.dart';
import '../../../tool/release/stage_companion_package.dart';
import '../../../tool/testing/release_metadata_readiness.dart';

const _name = 'llamadart_llama_cpp_flutter';
const _version = '0.17.2';
const _companion = (name: _name, path: 'packages/$_name');
const _readme =
    '# Install\n\n```yaml\ndependencies:\n  llamadart: ^0.17.4\n```\n';

Map<String, List<int>> _files({String readme = _readme}) => {
  'pubspec.yaml': utf8.encode(
    'name: $_name\nversion: $_version\n'
    'environment:\n  sdk: ">=3.10.7 <4.0.0"\n'
    'dependencies:\n  llamadart: ">=0.17.0 <0.18.0"\n',
  ),
  'README.md': utf8.encode(readme),
  'darwin/$_name/Package.swift': utf8.encode('// package\n'),
  'lib/$_name.dart': utf8.encode('const value = 1;\n'),
  'assets/binary.dat': [0, 255, 128, 13, 10],
};

Directory _repo({Map<String, List<int>>? files}) {
  final root = Directory.systemTemp.createTempSync('companion-content-test-');
  addTearDown(() => root.deleteSync(recursive: true));
  // Running pub inside packages/ would incorrectly inherit this exclusion.
  File(p.join(root.path, '.pubignore')).writeAsStringSync('/packages/\n');
  for (final entry in (files ?? _files()).entries) {
    _write(root, entry.key, entry.value);
  }
  return root;
}

void _write(Directory root, String name, List<int> bytes) {
  File(p.join(root.path, _companion.path, name))
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);
}

List<int> _archive(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return GZipEncoder().encode(TarEncoder().encode(archive));
}

Future<PubDevResponse> _metadata(List<int> archive, Uri uri) async => (
  status: HttpStatus.ok,
  body: jsonEncode({
    'version': _version,
    'pubspec': {
      'name': _name,
      'version': _version,
      'dependencies': {'llamadart': '>=0.17.0 <0.18.0'},
    },
    'archive_url': '${pubDevArchiveUri(_name, _version)}',
    'archive_sha256': sha256.convert(archive).toString(),
  }),
);

Future<({int code, String out, String err})> _preflight(
  Directory root,
  List<int> archive, {
  Future<PubDevResponse> Function(Uri uri)? get,
  Future<List<int>> Function(Uri uri)? getArchive,
}) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runCompanionPubPreflight(
    root,
    get ?? (uri) => _metadata(archive, uri),
    getArchive: getArchive ?? (uri) async => archive,
    out: out,
    err: err,
  );
  return (code: code, out: '$out', err: '$err');
}

Map<String, ReadinessFilePair> _metadataCandidate() {
  ReadinessFile file(String text) => (mode: '100644', contents: text);
  ReadinessFilePair pair(String text) =>
      (base: file(text), head: file(text.replaceAll('0.17.4', '0.17.5')));
  return {
    'pubspec.yaml': pair('name: llamadart\nversion: 0.17.4\n'),
    for (final entry in releaseMetadataLocks.entries)
      entry.key: pair(
        'packages:\n  llamadart:\n    description:\n'
        '      path: "${entry.value}"\n      relative: true\n'
        '    source: path\n    version: "0.17.4"\n',
      ),
    for (final path in releaseMetadataDocs)
      path: path.contains('CHANGELOG') || path.contains('recent-releases')
          ? (
              base: file('## Unreleased\n\n* Fix.\n\n## 0.17.4\n\n* Old.\n'),
              head: file('## 0.17.5\n\n* Fix.\n\n## 0.17.4\n\n* Old.\n'),
            )
          : pair(_readme),
  };
}

void main() {
  test(
    'unchanged bytes pass using real pub selection outside ancestor ignores',
    () async {
      final files = _files();
      final archive = _archive(files);
      final asked = <Uri>[];
      expect(publishedCompanionContents(archive), {
        for (final entry in files.entries)
          entry.key: sha256.convert(entry.value).toString(),
      });
      expect(
        await candidateCompanionContents(
          Directory(p.join(_repo(files: files).path, _companion.path)),
        ),
        publishedCompanionContents(archive),
      );
      final result = await _preflight(
        _repo(files: files),
        archive,
        get: (uri) {
          asked.add(uri);
          return _metadata(archive, uri);
        },
      );
      expect(result.code, 0, reason: result.err);
      expect(asked.toSet(), hasLength(2));
      expect(asked, hasLength(2));
    },
  );

  test(
    'README-only and accumulated changes fail the public pre-tag entry point',
    () async {
      final published = _files();
      final repo = _repo(files: published);
      _write(repo, 'README.md', utf8.encode('Updated README\n'));
      var result = await _preflight(repo, _archive(published));
      expect(result.code, 1);
      expect(result.err, contains('publishable contents changed'));
      // No Git/base comparison: an older accumulated source change also fails.
      _write(repo, 'README.md', published['README.md']!);
      _write(repo, 'lib/$_name.dart', utf8.encode('const value = 2;\n'));
      result = await _preflight(repo, _archive(published));
      expect(result.code, 1);
      expect(result.err, contains('publishable contents changed'));
    },
  );

  test(
    'metadata-route admission cannot exempt an unchanged companion version',
    () async {
      final metadata = _metadataCandidate();
      expect(validateReleaseMetadata(metadata), isNull);
      final published = _files();
      final repo = _repo(files: published);
      _write(
        repo,
        'README.md',
        utf8.encode(metadata['${_companion.path}/README.md']!.head.contents),
      );
      final result = await _preflight(repo, _archive(published));
      expect(result.code, 1);
      expect(result.err, contains('publishable contents changed'));
    },
  );

  test(
    'publisher exclusions and package ignore rules do not require bumps',
    () async {
      final files = _files();
      final repo = _repo(files: files);
      for (final path in [
        '.dart_tool/state',
        'build/output',
        'pubspec.lock',
        'pubspec_overrides.yaml',
        'darwin/$_name/Artifacts/cache.bin',
        'ignored/generated.bin',
      ]) {
        _write(repo, path, [255, 0, 127]);
      }
      _write(
        repo,
        '.pubignore',
        utf8.encode('darwin/*/Artifacts/\nignored/\n'),
      );
      if (!Platform.isWindows) {
        Link(
          p.join(repo.path, _companion.path, 'ignored', 'cache-link'),
        ).createSync(repo.path);
      }
      final result = await _preflight(repo, _archive(files));
      expect(result.code, 0, reason: result.err);
    },
  );

  test(
    'added, removed and non-UTF8 byte changes are content changes',
    () async {
      final files = _files();
      final repo = _repo(files: files);
      for (final change in ['added', 'removed', 'binary']) {
        if (change == 'added') {
          _write(repo, 'assets/extra.dat', [1]);
        } else if (change == 'removed') {
          File(
            p.join(repo.path, _companion.path, 'assets/extra.dat'),
          ).deleteSync();
          File(p.join(repo.path, _companion.path, 'README.md')).deleteSync();
        } else {
          _write(repo, 'README.md', files['README.md']!);
          _write(repo, 'assets/binary.dat', [0, 255, 129, 13, 10]);
        }
        final result = await _preflight(repo, _archive(files));
        expect(result.code, 1, reason: change);
        expect(
          result.err,
          contains('publishable contents changed'),
          reason: change,
        );
      }
    },
  );

  test(
    'a confirmed new version passes without downloading a nonexistent archive',
    () async {
      final repo = _repo();
      final pubspec = File(p.join(repo.path, _companion.path, 'pubspec.yaml'));
      pubspec.writeAsStringSync(
        pubspec.readAsStringSync().replaceFirst(
          'version: $_version',
          'version: 0.17.3',
        ),
      );
      _write(repo, 'README.md', utf8.encode('New version contents\n'));
      final result = await _preflight(
        repo,
        const [],
        get: (uri) async {
          if (uri.pathSegments.contains('versions')) {
            expect(uri.pathSegments.last, '0.17.3');
            return (status: 404, body: '{}');
          }
          return (status: 200, body: '{}');
        },
        getArchive: (_) async =>
            throw StateError('Must not fetch an unpublished archive'),
      );
      expect(result.code, 0, reason: result.err);
    },
  );

  test(
    'failed metadata, archive and checksum verification fail closed',
    () async {
      final repo = _repo();
      final archive = _archive(_files());
      final responses = [
        (status: 503, body: '{}'),
        (status: 200, body: '{bad json'),
        (
          status: 200,
          body: (await _metadata(
            archive,
            Uri(),
          )).body.replaceFirst(_name, 'other_package'),
        ),
        (
          status: 200,
          body: (await _metadata(archive, Uri())).body.replaceFirst(
            'https://pub.dev/api/archives/',
            'https://untrusted.invalid/',
          ),
        ),
      ];
      for (final response in responses) {
        final result = await _preflight(
          repo,
          archive,
          get: (_) async => response,
        );
        expect(result.code, 1);
        expect(result.err, contains('Could not verify published contents'));
      }
      for (final fetch in <Future<List<int>> Function(Uri)>[
        (_) async => [1, 2, 3],
        (_) async => throw const SocketException('offline-secret'),
      ]) {
        final result = await _preflight(repo, archive, getArchive: fetch);
        expect(result.code, 1);
        expect(result.err, contains('Could not verify published contents'));
        expect(result.err, isNot(contains('offline-secret')));
      }
    },
  );

  test('untrusted archive paths and links are rejected without extraction', () {
    for (final name in [
      '../escape',
      '/absolute',
      'C:/absolute',
      r'a\b',
      './alias',
    ]) {
      expect(
        () => publishedCompanionContents(
          _archive({
            'pubspec.yaml': [1],
            name: [2],
          }),
        ),
        throwsFormatException,
        reason: name,
      );
    }
    final archive = Archive()
      ..addFile(ArchiveFile.string('pubspec.yaml', 'name: package\n'))
      ..addFile(ArchiveFile.symlink('link', '../outside'));
    expect(
      () => publishedCompanionContents(
        GZipEncoder().encode(TarEncoder().encode(archive)),
      ),
      throwsFormatException,
    );
  });

  test(
    'duplicate published file names cannot overwrite an earlier payload',
    () {
      List<int> entry(String name, String value) {
        final bytes = utf8.encode(value);
        final encoded = TarEncoder().encode(
          Archive()..addFile(ArchiveFile(name, bytes.length, bytes)),
        );
        return encoded.sublist(0, 512 + ((bytes.length + 511) ~/ 512) * 512);
      }

      expect(
        () => publishedCompanionContents(
          gzip.encode([
            ...entry('pubspec.yaml', 'name: package\n'),
            ...entry('README.md', 'first'),
            ...entry('README.md', 'second'),
            ...List<int>.filled(1024, 0),
          ]),
        ),
        throwsFormatException,
      );
    },
  );

  test('pub selection must describe the same unchanged staged bytes', () async {
    final repo = _repo();
    final package = Directory(p.join(repo.path, _companion.path));
    await expectLater(
      candidateCompanionContents(
        package,
        runPub: (stage) async {
          File(p.join(stage.path, 'README.md')).writeAsStringSync('raced');
          return ProcessResult(
            0,
            0,
            '',
            'FINE: Creating .tar.gz stream containing:\n'
                '    | ${p.join(stage.path, 'pubspec.yaml')}\n'
                '    | ${p.join(stage.path, 'README.md')}\n',
          );
        },
      ),
      throwsStateError,
    );
  });

  test('pub-selected links cannot replace regular file bytes', () async {
    if (Platform.isWindows) return;
    final repo = _repo();
    final package = Directory(p.join(repo.path, _companion.path));
    Link(p.join(package.path, 'linked')).createSync('README.md');
    await expectLater(
      candidateCompanionContents(
        package,
        runPub: (stage) async {
          return ProcessResult(
            0,
            0,
            '',
            'FINE: Creating .tar.gz stream containing:\n'
                '    | ${p.join(stage.path, 'pubspec.yaml')}\n'
                '    | ${p.join(stage.path, 'linked')}\n',
          );
        },
      ),
      throwsFormatException,
    );
  });

  test(
    'publisher staging copies links without following and refuses existing destinations',
    () {
      final repo = _repo();
      final package = Directory(p.join(repo.path, _companion.path));
      expect(() => stageCompanionPackage(package, package), throwsStateError);
      final output = Directory(p.join(repo.path, 'staged'));
      stageCompanionPackage(package, output);
      expect(() => stageCompanionPackage(package, output), throwsStateError);
      if (!Platform.isWindows) {
        Link(p.join(package.path, 'linked')).createSync(repo.path);
        final linkedStage = Directory(p.join(repo.path, 'linked-stage'));
        stageCompanionPackage(package, linkedStage);
        expect(
          Link(p.join(linkedStage.path, 'linked')).targetSync(),
          repo.path,
        );
      }
    },
  );
}
