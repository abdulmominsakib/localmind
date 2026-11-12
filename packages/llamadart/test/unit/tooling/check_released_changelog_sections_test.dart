@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../../tool/testing/check_released_changelog_sections.dart';

const _script = 'tool/testing/check_released_changelog_sections.dart';
const _command = 'dart run $_script';
const _docsChangelog = 'website/docs/changelog/recent-releases.md';
const _repository = 'leehack/llamadart';
const _posixOnly = 'drives git in a temporary repository';

const _released = '## 1.1.0\n\n- New.\n\n## 1.0.0\n\n- Old.\n';
const _docsIntro = '---\ntitle: Recent releases\n---\n\nIntro.\n\n';
const _base = '## Unreleased\n\n- Pending.\n\n$_released';

void main() {
  group('releasedSectionChange', () {
    test('accepts any change above the first released heading', () {
      for (final head in [
        '## Unreleased\n\n- Pending.\n- Another.\n\n$_released',
        _released,
        '# Changelog\n\n## Unreleased\n\n$_released',
      ]) {
        expect(releasedSectionChange('CHANGELOG.md', _base, head), isNull);
      }
    });

    test('names the first differing line of a moved bullet', () {
      const head =
          '## Unreleased\n\n## 1.1.0\n\n- New.\n- Pending.\n\n'
          '## 1.0.0\n\n- Old.\n';
      expect(
        releasedSectionChange('CHANGELOG.md', _base, head),
        startsWith(
          'CHANGELOG.md:6 changes a released section: the base has ``, this '
          'PR has `- Pending.`.',
        ),
      );
    });

    test('rejects a new, removed or truncated released section', () {
      expect(
        releasedSectionChange('CHANGELOG.md', _base, '## 1.2.0\n\n$_released'),
        startsWith(
          'CHANGELOG.md:1 changes a released section: the base has '
          '`## 1.1.0`, this PR has `## 1.2.0`.',
        ),
      );
      expect(
        releasedSectionChange('CHANGELOG.md', _base, '## Unreleased\n'),
        'CHANGELOG.md no longer has the released section `## 1.1.0`.',
      );
      expect(
        releasedSectionChange(
          'CHANGELOG.md',
          _base,
          '## Unreleased\n\n## 1.1.0\n\n- New.\n',
        ),
        contains('the base has ``, this PR has the end of the file'),
      );
      expect(
        releasedSectionChange(
          'CHANGELOG.md',
          _base,
          _base.substring(0, _base.length - 1),
        ),
        isNotNull,
      );
    });

    test('has nothing to protect before the first release', () {
      expect(
        releasedSectionChange('CHANGELOG.md', '## Unreleased\n', '# Draft\n'),
        isNull,
      );
    });
  });

  group('releasedSectionChange on the docs changelog', () {
    const base =
        '## Unreleased\n\n$_released\n## 0.9.0\n\n- Older.\n\n'
        '## 0.8.0\n\n- Oldest.\n';

    String? change(String head, {String path = _docsChangelog}) =>
        releasedSectionChange(path, base, head);

    test('accepts cutting whole sections from the tail', () {
      for (final head in [
        '## Unreleased\n\n$_released\n## 0.9.0\n\n- Older.\n',
        '## Unreleased\n\n$_released\n## 0.9.0\n\n- Older.\n\n',
        '## Unreleased\n\n$_released',
        '## Unreleased\n\n$_released\n',
      ]) {
        expect(change(head), isNull, reason: head);
      }
    });

    test('rejects the same cut in CHANGELOG.md', () {
      expect(
        change('## Unreleased\n\n$_released', path: 'CHANGELOG.md'),
        contains('changes a released section'),
      );
    });

    test('rejects a cut inside a section', () {
      for (final head in [
        '## Unreleased\n\n## 1.1.0\n',
        '## Unreleased\n\n## 1.1.0\n\n- New.\n\n## 1.0.0\n',
        '## Unreleased\n\n$_released\n## 0.9.0\n\n- Older.\n\n## 0.8.0\n',
      ]) {
        expect(change(head), isNotNull, reason: head);
      }
    });

    test('rejects a cut that also edits a kept section or the tail', () {
      expect(change('## Unreleased\n\n## 1.1.0\n\n- New edited.\n'), isNotNull);
      expect(
        change(
          '## Unreleased\n\n## 1.1.0\n\n- New.\n\n## 1.0.0\n\n- Old.\n'
          '\n## 0.9.0\n\n- Older.\n\n## 0.8.0\n\n- Oldest.\n- Extra.\n',
        ),
        isNotNull,
      );
      expect(change('## Unreleased\n\n## 1.1.0\n\n- Pending.\n'), isNotNull);
    });

    test('rejects adding a section or removing every section', () {
      expect(change('## 1.2.0\n\n$_released'), isNotNull);
      expect(
        change('## Unreleased\n'),
        '$_docsChangelog no longer has the released section `## 1.1.0`.',
      );
    });
  });

  test('derives actual retained patches across minor and major boundaries', () {
    const headings = [
      '## 1.1.3',
      '## 1.1.0',
      '## 1.0.5',
      '## 1.0.0',
      '## 0.19.4',
      '## 0.19.1',
      '## 0.18.0',
    ];
    expect(
      retainedReleaseHeadings(headings, major: 1, minor: 1),
      headings.take(4),
    );
    expect(
      retainedReleaseHeadings(headings, major: 1, minor: 0),
      headings.skip(2).take(4),
    );
    expect(
      retainedReleaseHeadings(['## 0.0.3', '## 0.0.0'], major: 0, minor: 0),
      ['## 0.0.3', '## 0.0.0'],
    );
  });

  test('retains complete current and previous minor bodies', () {
    const sections = [
      '## 1.1.3\n\n- A.\n',
      '## 1.1.0\n\n- B.\n',
      '## 1.0.5\n\n- C.\n',
      '## 1.0.0\n\n- D.\n',
      '## 0.19.4\n\n- E.\n',
    ];
    final base = sections.join('\n');
    expect(
      releasedSectionChange(_docsChangelog, base, sections.take(4).join('\n')),
      isNull,
    );
    for (var count = 1; count < 4; count++) {
      expect(
        releasedSectionChange(
          _docsChangelog,
          base,
          sections.take(count).join('\n'),
        ),
        isNotNull,
      );
    }
    expect(
      releasedSectionChange(
        _docsChangelog,
        base,
        base.replaceFirst('- C.', '- Changed.'),
      ),
      isNotNull,
    );
    final majorBase = sections.skip(2).join('\n');
    expect(
      releasedSectionChange(
        _docsChangelog,
        majorBase,
        sections.skip(2).take(2).join('\n'),
      ),
      isNotNull,
    );
  });

  group('archivedSectionChange', () {
    const base =
        '## Unreleased\n\n$_released\n## 0.9.0\n\n- Older.\n\n'
        '## 0.8.0\n\n- Oldest.\n';
    const archiveIntro = '# Changelog archive\n\nOlder releases.\n\n';
    const archivePath = 'doc/changelog_archive.md';

    String? change(
      String head, {
      String? baseArchive,
      String? headArchive,
      String from = base,
    }) => archivedSectionChange(
      'CHANGELOG.md',
      archivePath,
      base: from,
      head: head,
      baseArchive: baseArchive,
      headArchive: headArchive,
    );

    test('accepts moving the oldest sections verbatim to a new archive', () {
      for (final (head, archive) in [
        (
          'Older releases: archive.\n\n## Unreleased\n\n$_released',
          '$archiveIntro## 0.9.0\n\n- Older.\n\n## 0.8.0\n\n- Oldest.\n',
        ),
        (
          '## Unreleased\n\n$_released\n## 0.9.0\n\n- Older.\n\n',
          '$archiveIntro## 0.8.0\n\n- Oldest.\n',
        ),
      ]) {
        expect(change(head, headArchive: archive), isNull, reason: head);
      }
    });

    test('accepts a later move to the start of the archive releases', () {
      const archive = '$archiveIntro## 0.8.0\n\n- Oldest.\n';
      expect(
        change(
          '## Unreleased\n\n$_released',
          from: '## Unreleased\n\n$_released\n## 0.9.0\n\n- Older.\n',
          baseArchive: archive,
          headArchive:
              '$archiveIntro## 0.9.0\n\n- Older.\n\n## 0.8.0\n\n- Oldest.\n',
        ),
        isNull,
      );
    });

    test('accepts editing the archive introduction only', () {
      const archived = '## 0.8.0\n\n- Oldest.\n';
      expect(
        change(
          '## Unreleased\n\n$_released\n## 0.9.0\n\n- Older.\n',
          from: '## Unreleased\n\n$_released\n## 0.9.0\n\n- Older.\n',
          baseArchive: '$archiveIntro$archived',
          headArchive: '# Archive\n\n$archived',
        ),
        isNull,
      );
    });

    test('names the line of a section edited while it moves', () {
      expect(
        change(
          '## Unreleased\n\n$_released',
          headArchive:
              '$archiveIntro## 0.9.0\n\n- Edited.\n\n## 0.8.0\n\n- Oldest.\n',
        ),
        startsWith(
          '$archivePath:7 changes a released section: the base has '
          '`- Older.`, this PR has `- Edited.`.',
        ),
      );
    });

    test('rejects a section dropped, reordered or cut in half', () {
      for (final archive in [
        '$archiveIntro## 0.9.0\n\n- Older.\n',
        '$archiveIntro## 0.8.0\n\n- Oldest.\n\n## 0.9.0\n\n- Older.\n',
        '$archiveIntro- Older.\n\n## 0.8.0\n\n- Oldest.\n',
        archiveIntro,
      ]) {
        expect(
          change('## Unreleased\n\n$_released', headArchive: archive),
          contains('changes a released section'),
          reason: archive,
        );
      }
      expect(
        change(
          '## Unreleased\n\n$_released\n## 0.9.0\n',
          headArchive: '$archiveIntro- Older.\n\n## 0.8.0\n\n- Oldest.\n',
        ),
        contains('changes a released section'),
      );
    });

    test('rejects a new section or an edit in the archive', () {
      const from = '## Unreleased\n\n$_released';
      const archive = '$archiveIntro## 0.9.0\n\n- Older.\n';
      for (final headArchive in [
        '$archiveIntro## 0.9.5\n\n- New.\n\n## 0.9.0\n\n- Older.\n',
        '$archiveIntro## 0.9.0\n\n- Older.\n- Extra.\n',
        null,
      ]) {
        expect(
          change(
            from,
            from: from,
            baseArchive: archive,
            headArchive: headArchive,
          ),
          contains('changes a released section'),
          reason: headArchive,
        );
      }
    });

    test('rejects moving every release out of the changelog', () {
      expect(
        change(
          '## Unreleased\n',
          headArchive:
              '$archiveIntro$_released\n## 0.9.0\n\n- Older.\n\n'
              '## 0.8.0\n\n- Oldest.\n',
        ),
        'CHANGELOG.md no longer has the released section `## 1.1.0`.',
      );
    });

    test('keeps the plain check while the archive is unchanged', () {
      expect(
        change('## Unreleased\n\n$_released'),
        contains('CHANGELOG.md:10 changes a released section'),
      );
    });
  });

  group('isCoreReleasePrep', () {
    bool prep({
      List<String> labels = const [],
      String headRef = 'fix/thing',
      String headRepository = _repository,
    }) => isCoreReleasePrep(
      labels: labels,
      headRef: headRef,
      headRepository: headRepository,
      repository: _repository,
    );

    test('matches the release-prep label and versioned prep branches', () {
      expect(prep(labels: ['release-prep']), isTrue);
      expect(prep(headRef: 'release/prep-0.15.6'), isTrue);
      expect(prep(headRef: 'release/0.15.6-prep'), isTrue);
      expect(prep(headRef: 'release/prep-0.16.0-dev.1'), isTrue);
    });

    test('rejects other branches, forks and Genkit release branches', () {
      expect(prep(), isFalse);
      expect(prep(labels: ['docs']), isFalse);
      expect(prep(headRef: 'release/prep-next'), isFalse);
      expect(prep(headRef: 'release/0.15.6'), isFalse);
      expect(
        prep(labels: ['release-prep'], headRepository: 'someone/llamadart'),
        isFalse,
      );
      expect(
        prep(labels: ['release-prep'], headRef: 'release/genkit_llamadart-0.6'),
        isFalse,
      );
    });

    test('mirrors the release_on_prep_merge.yml gate', () {
      final gate = File(
        '.github/workflows/release_on_prep_merge.yml',
      ).readAsStringSync();
      for (final fragment in [
        r'grep -Fxq "release-prep"',
        r'"$head_ref" =~ ^release/prep-[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9._-]+)?$',
        r'"$head_ref" =~ ^release/[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9._-]+)?-prep$',
        r'"$head_repo" != "$GITHUB_REPOSITORY"',
        r'"$head_ref" == release/genkit_llamadart-*',
      ]) {
        expect(gate, contains(fragment));
      }
    });
  });

  group('CLI', () {
    late Directory root;
    late _Repo repo;
    setUp(() {
      root = Directory.systemTemp.createTempSync('released-changelog-');
      repo = _Repo.init(root, {
        'CHANGELOG.md': _base,
        _docsChangelog: '$_docsIntro$_base',
      });
      repo.git(['update-ref', 'refs/remotes/origin/main', 'main']);
      repo.git(['checkout', '-q', '-b', 'feature']);
    });
    tearDown(() => root.deleteSync(recursive: true));

    ProcessResult run({
      List<String> labels = const [],
      String headRef = 'feature',
      String baseRef = 'main',
      String eventName = 'pull_request',
    }) {
      final event = File('${root.path}/event.json')
        ..writeAsStringSync(
          jsonEncode({
            'pull_request': {
              'labels': [
                for (final label in labels) {'name': label},
              ],
              'base': {'ref': baseRef},
              'head': {
                'ref': headRef,
                'repo': {'full_name': _repository},
              },
            },
          }),
        );
      return Process.runSync(
        Platform.resolvedExecutable,
        [File(_script).absolute.path],
        workingDirectory: repo.directory.path,
        environment: {
          ...repo.environment,
          'GITHUB_EVENT_NAME': eventName,
          'GITHUB_EVENT_PATH': event.path,
          'GITHUB_REPOSITORY': _repository,
        },
      );
    }

    test('passes a PR that only adds an Unreleased bullet', () {
      const head = '## Unreleased\n\n- Pending.\n- Mine.\n\n$_released';
      repo.commit({'CHANGELOG.md': head, _docsChangelog: '$_docsIntro$head'});

      final result = run();
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, contains('match the base'));
    });

    test('fails a bullet moved into a released section', () {
      const head =
          '## Unreleased\n\n## 1.1.0\n\n- New.\n- Pending.\n\n'
          '## 1.0.0\n\n- Old.\n';
      repo.commit({_docsChangelog: '$_docsIntro$head'});

      final result = run();
      expect(result.exitCode, 1);
      expect(
        result.stderr,
        contains(
          '$_docsChangelog:12 changes a released section: the base has ``, '
          'this PR has `- Pending.`.',
        ),
      );
      expect(result.stderr, isNot(contains('- CHANGELOG.md')));
    });

    test('rejects dropping the prior minor in either changelog', () {
      const head = '## Unreleased\n\n- Pending.\n\n## 1.1.0\n\n- New.\n';
      repo.commit({'CHANGELOG.md': head, _docsChangelog: '$_docsIntro$head'});

      final result = run();
      expect(result.exitCode, 1);
      expect(
        result.stderr,
        contains('CHANGELOG.md:8 changes a released section'),
      );
      expect(result.stderr, contains('- $_docsChangelog'));
    });

    test('rejects a retained minor trimmed at a version heading', () {
      repo.commit({
        _docsChangelog:
            '$_docsIntro## Unreleased\n\n- Pending.\n\n## 1.1.0\n\n- New.\n',
      });

      final result = run();
      expect(result.exitCode, 1, reason: '${result.stderr}');
      expect(result.stderr, contains('changes a released section'));
    });

    test('passes moving the oldest section verbatim to the archive', () {
      repo.commit({
        'CHANGELOG.md': '## Unreleased\n\n- Pending.\n\n## 1.1.0\n\n- New.\n',
        'doc/changelog_archive.md': '# Archive\n\n## 1.0.0\n\n- Old.\n',
      });

      final result = run();
      expect(result.exitCode, 0, reason: '${result.stderr}');
    });

    test('passes an archive introduction edit and fails a release edit', () {
      repo.git(['checkout', '-q', 'main']);
      repo.commit({
        'CHANGELOG.md': '## Unreleased\n\n- Pending.\n\n## 1.1.0\n\n- New.\n',
        'doc/changelog_archive.md': '# Archive\n\n## 1.0.0\n\n- Old.\n',
      });
      repo.git(['update-ref', 'refs/remotes/origin/main', 'main']);
      repo.git(['checkout', '-q', '-B', 'feature']);
      repo.commit({
        'doc/changelog_archive.md': '# Old\n\n## 1.0.0\n\n- Old.\n',
      });
      expect(run().exitCode, 0);

      repo.commit({
        'doc/changelog_archive.md': '# Old\n\n## 1.0.0\n\n- Odd.\n',
      });
      final result = run();
      expect(result.exitCode, 1);
      expect(
        result.stderr,
        contains('doc/changelog_archive.md:5 changes a released section'),
      );
    });

    test('fails a section edited while it moves to the archive', () {
      repo.commit({
        'CHANGELOG.md': '## Unreleased\n\n- Pending.\n\n## 1.1.0\n\n- New.\n',
        'doc/changelog_archive.md': '# Archive\n\n## 1.0.0\n\n- Edited.\n',
      });

      final result = run();
      expect(result.exitCode, 1);
      expect(
        result.stderr,
        contains(
          'doc/changelog_archive.md:5 changes a released section: the base '
          'has `- Old.`, this PR has `- Edited.`.',
        ),
      );
    });

    test('compares against the merge base, not the base branch tip', () {
      repo.git(['checkout', '-q', 'main']);
      const released = '## 1.2.0\n\n- Pending.\n\n$_released';
      repo.commit({
        'CHANGELOG.md': '## Unreleased\n\n$released',
        _docsChangelog: '$_docsIntro## Unreleased\n\n$released',
      });
      repo.git(['update-ref', 'refs/remotes/origin/main', 'main']);
      repo.git(['checkout', '-q', 'feature']);

      expect(run().exitCode, 0);
    });

    test('exempts release prep', () {
      repo.commit({'CHANGELOG.md': '## 1.2.0\n\n- Pending.\n\n$_released'});

      expect(run().exitCode, 1);
      for (final result in [
        run(labels: ['release-prep']),
        run(headRef: 'release/prep-1.2.0'),
      ]) {
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(result.stdout, contains('Release-prep PR'));
      }
    });

    test('fails closed when the base branch is not fetched', () {
      final result = run(baseRef: 'release-branch');
      expect(result.exitCode, 1);
      expect(
        result.stderr,
        contains(
          'Could not find the merge base of HEAD and origin/release-branch. '
          'Check out with `fetch-depth: 0`',
        ),
      );
    });

    test('skips events other than pull_request', () {
      repo.commit({'CHANGELOG.md': '## 1.2.0\n\n$_released'});
      final result = run(eventName: 'push');
      expect(result.exitCode, 0);
      expect(result.stdout, contains('Not a pull_request event'));
    });
  }, skip: Platform.isWindows ? _posixOnly : false);

  test(
    'ci.yml runs the check with full history wherever docs are verified',
    () {
      final jobs =
          (loadYaml(File('.github/workflows/ci.yml').readAsStringSync())
                  as YamlMap)['jobs']
              as YamlMap;
      for (final name in ['analyze', 'docs-versions']) {
        final steps = ((jobs[name] as YamlMap)['steps'] as YamlList)
            .cast<YamlMap>()
            .toList();
        final checkout = steps.singleWhere(
          (step) =>
              (step['uses'] as String? ?? '').startsWith('actions/checkout'),
        );
        expect((checkout['with'] as YamlMap)['fetch-depth'], 0, reason: name);
        final runs = steps.map((step) => step['run']).toList();
        final verify = runs.indexOf(
          'dart run tool/testing/verify_release_docs_versions.dart',
        );
        expect(verify, isNot(-1), reason: name);
        expect(runs.indexOf(_command), verify + 1, reason: name);
      }
    },
  );
}

/// Git with no user or system configuration, so signing, hooks and
/// templates on the host cannot change what the commands do.
class _Repo {
  _Repo(this.directory, this.environment);

  factory _Repo.init(Directory root, Map<String, String> files) {
    final config = File('${root.path}/gitconfig')..writeAsStringSync('');
    final repo = _Repo(Directory('${root.path}/repo')..createSync(), {
      'GIT_CONFIG_GLOBAL': config.path,
      'GIT_CONFIG_NOSYSTEM': '1',
      'GIT_AUTHOR_NAME': 'Test',
      'GIT_AUTHOR_EMAIL': 'test@example.com',
      'GIT_COMMITTER_NAME': 'Test',
      'GIT_COMMITTER_EMAIL': 'test@example.com',
    });
    repo.git(['init', '-q', '-b', 'main']);
    repo.commit(files);
    return repo;
  }

  final Directory directory;
  final Map<String, String> environment;

  void git(List<String> arguments) {
    final result = Process.runSync(
      'git',
      arguments,
      workingDirectory: directory.path,
      environment: environment,
    );
    if (result.exitCode != 0) {
      fail('git ${arguments.join(' ')} failed:\n${result.stderr}');
    }
  }

  void commit(Map<String, String> files) {
    for (final entry in files.entries) {
      File('${directory.path}/${entry.key}')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(entry.value);
    }
    git(['add', '-A']);
    git(['commit', '-q', '-m', 'change']);
  }
}
