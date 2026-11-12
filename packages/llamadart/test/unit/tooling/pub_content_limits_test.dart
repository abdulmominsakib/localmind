@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/release/pub_content_limits.dart';
import '../../support/dart_script_snapshot.dart';

const _packages = <String, String>{
  'llamadart': '.',
  'llamadart_llama_cpp_flutter': 'packages/llamadart_llama_cpp_flutter',
  'llamadart_litert_lm_flutter': 'packages/llamadart_litert_lm_flutter',
  'llamadart_stable_diffusion_flutter':
      'packages/llamadart_stable_diffusion_flutter',
};

const _genkitPackages = <String, String>{
  'genkit_llamadart': 'packages/genkit_llamadart',
};

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('pub-content-'));
  tearDown(() => root.deleteSync(recursive: true));

  void write(String path, int bytes) {
    File('${root.path}/$path')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('a' * bytes);
  }

  test('matches the limit pub.dev enforces', () {
    expect(pubContentLimitBytes, 262144);
  });

  test('matches the pubspec limit pub.dev enforces', () {
    expect(pubPubspecLimitBytes, 131072);
  });

  test('limits pubspec.yaml to 128 KiB, not the content limit', () {
    write('pubspec.yaml', pubPubspecLimitBytes);
    write(
      'packages/llamadart_litert_lm_flutter/pubspec.yaml',
      1 + pubPubspecLimitBytes,
    );
    write('packages/genkit_llamadart/pubspec.yaml', 1 + pubPubspecLimitBytes);

    final result = checkPubContentLimits(root, {
      ..._packages,
      ..._genkitPackages,
    });
    expect(result.errors, [
      'packages/llamadart_litert_lm_flutter/pubspec.yaml is 131073 bytes; '
          'pub.dev rejects llamadart_litert_lm_flutter when it exceeds '
          '131072 bytes. Shorten it before publishing.',
      'packages/genkit_llamadart/pubspec.yaml is 131073 bytes; pub.dev '
          'rejects genkit_llamadart when it exceeds 131072 bytes. Shorten it '
          'before publishing.',
    ]);
    expect(result.warnings, [
      'pubspec.yaml is 131072 bytes, within 10% of the 131072-byte limit '
          'pub.dev applies when publishing llamadart.',
    ]);
  });

  test('warns on pubspec.yaml only above 90% of its limit', () {
    write('pubspec.yaml', pubPubspecLimitBytes * 9 ~/ 10);
    expect(checkPubContentLimits(root, {'llamadart': '.'}).warnings, isEmpty);

    write('pubspec.yaml', pubPubspecLimitBytes * 9 ~/ 10 + 1);
    final result = checkPubContentLimits(root, {'llamadart': '.'});
    expect(result.errors, isEmpty);
    expect(result.warnings, [startsWith('pubspec.yaml is 117965 bytes')]);
  });

  test('accepts a file at the limit and fails one byte over', () {
    write('CHANGELOG.md', pubContentLimitBytes);
    write(
      'packages/llamadart_litert_lm_flutter/README.md',
      1 + pubContentLimitBytes,
    );

    final result = checkPubContentLimits(root, _packages);
    expect(result.errors, [
      'packages/llamadart_litert_lm_flutter/README.md is 262145 bytes; pub.dev '
          'rejects llamadart_litert_lm_flutter when it exceeds 262144 bytes. '
          'Shorten it before publishing (the core CHANGELOG.md moves its '
          'oldest releases, verbatim, to doc/changelog_archive.md).',
    ]);
    expect(result.warnings, [
      'CHANGELOG.md is 262144 bytes, within 10% of the 262144-byte limit '
          'pub.dev applies when publishing llamadart.',
    ]);
  });

  test('warns only above 90% of the limit', () {
    write('README.md', pubContentWarningBytes);
    write('LICENSE', pubContentWarningBytes + 1);

    final result = checkPubContentLimits(root, {'llamadart': '.'});
    expect(result.errors, isEmpty);
    expect(result.warnings, [startsWith('LICENSE is 235930 bytes')]);
  });

  test('counts UTF-8 bytes, not characters', () {
    // 131073 two-byte characters: under the limit in characters, over in bytes.
    File('${root.path}/CHANGELOG.md').writeAsStringSync('é' * 131073);

    expect(checkPubContentLimits(root, {'llamadart': '.'}).errors, [
      startsWith('CHANGELOG.md is 262146 bytes'),
    ]);
  });

  test('checks the example file pub.dev shows, in its priority order', () {
    write('packages/demo/example/README.md', 300000);
    write('packages/demo/example/lib/demo_example.dart', 10);
    expect(pubContentFiles(root, 'packages/demo', 'demo'), [
      'packages/demo/example/lib/demo_example.dart',
    ]);
    expect(
      checkPubContentLimits(root, {'demo': 'packages/demo'}).errors,
      isEmpty,
    );

    File(
      '${root.path}/packages/demo/example/lib/demo_example.dart',
    ).deleteSync();
    expect(pubContentFiles(root, 'packages/demo', 'demo'), [
      'packages/demo/example/README.md',
    ]);
    expect(
      checkPubContentLimits(root, {'demo': 'packages/demo'}).errors.single,
      startsWith('packages/demo/example/README.md is 300000 bytes'),
    );
  });

  test('follows pub.dev\'s full example priority order', () {
    // pub-dev's `exampleFileCandidates`, highest priority first.
    const candidates = [
      'example/example.md',
      'example/lib/main.dart',
      'example/main.dart',
      'example/lib/demo.dart',
      'example/demo.dart',
      'example/lib/demo_example.dart',
      'example/demo_example.dart',
      'example/lib/example.dart',
      'example/example.dart',
      'example/README.md',
    ];
    for (final candidate in candidates) {
      write(candidate, 1);
    }
    for (final candidate in candidates) {
      expect(pubContentFiles(root, '.', 'demo'), [candidate]);
      File('${root.path}/$candidate').deleteSync();
    }
    expect(pubContentFiles(root, '.', 'demo'), isEmpty);
  });

  test('keeps the repository\'s published content under the limit', () {
    final result = checkPubContentLimits(Directory.current, _packages);
    expect(result.errors, isEmpty);
    expect(result.warnings, isEmpty);
    expect(pubContentFiles(Directory.current, '.', 'llamadart'), [
      'README.md',
      'CHANGELOG.md',
      'LICENSE',
      'example/README.md',
    ]);
    for (final MapEntry(key: name, value: path) in _packages.entries.skip(1)) {
      expect(pubContentFiles(Directory.current, path, name), [
        '$path/README.md',
        '$path/CHANGELOG.md',
        '$path/LICENSE',
        '$path/example/README.md',
      ]);
    }
  });

  test('archive cut matches the CHANGELOG note', () {
    final changelog = File('CHANGELOG.md').readAsStringSync();
    final archive = File('doc/changelog_archive.md').readAsStringSync();
    final headings = RegExp(r'^## (\d+\.\d+\.\d+)', multiLine: true);
    final oldest = headings.allMatches(changelog).last.group(1)!;
    final newest = headings.allMatches(archive).first.group(1)!;

    expect(changelog, startsWith('Releases before $oldest are in the'));
    expect(
      archive,
      contains('Releases of `llamadart` before $oldest, moved verbatim'),
    );
    expect(
      int.parse(newest.split('.')[1]),
      lessThan(int.parse(oldest.split('.')[1])),
    );
  });

  test('keeps the genkit_llamadart content files under the limit', () {
    final result = checkPubContentLimits(Directory.current, _genkitPackages);
    expect(result.errors, isEmpty);
    expect(result.warnings, isEmpty);
    expect(
      pubContentFiles(
        Directory.current,
        'packages/genkit_llamadart',
        'genkit_llamadart',
      ),
      [
        'packages/genkit_llamadart/README.md',
        'packages/genkit_llamadart/CHANGELOG.md',
        'packages/genkit_llamadart/LICENSE',
        'packages/genkit_llamadart/example/genkit_llamadart_example.dart',
      ],
    );
  });

  group('verify_release_docs_versions.dart', () {
    final packages = File('.dart_tool/package_config.json').absolute.path;
    late String verifier;
    setUpAll(
      () async => verifier = await compileDartScript(
        'tool/testing/verify_release_docs_versions.dart',
      ),
    );

    ProcessResult verify({required bool releasePrep}) {
      for (final MapEntry(key: name, value: path) in _packages.entries) {
        final pubspec = File('${root.path}/$path/pubspec.yaml');
        if (pubspec.existsSync()) continue;
        pubspec
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('name: $name\nversion: 0.14.0\n');
      }
      write('website/docs/changelog/recent-releases.md', 10);
      return Process.runSync(Platform.resolvedExecutable, <String>[
        '--packages=$packages',
        verifier,
        if (releasePrep) '--release-prep',
      ], workingDirectory: root.path);
    }

    for (final releasePrep in [false, true]) {
      test('fails an oversized changelog (releasePrep: $releasePrep)', () {
        write('CHANGELOG.md', pubContentLimitBytes + 1);
        final result = verify(releasePrep: releasePrep);
        expect(result.exitCode, 1);
        expect(
          result.stderr,
          contains('- CHANGELOG.md is 262145 bytes; pub.dev rejects llamadart'),
        );
      });
    }

    for (final MapEntry(key: name, value: path) in _packages.entries.skip(1)) {
      test('fails an oversized $name README', () {
        write('$path/README.md', pubContentLimitBytes + 1);
        final result = verify(releasePrep: false);
        expect(result.exitCode, 1);
        expect(
          result.stderr,
          contains('- $path/README.md is 262145 bytes; pub.dev rejects $name'),
        );
      });
    }

    test('fails an oversized genkit_llamadart pubspec and README', () {
      write('packages/genkit_llamadart/pubspec.yaml', pubPubspecLimitBytes + 1);
      write('packages/genkit_llamadart/README.md', pubContentLimitBytes + 1);
      final result = verify(releasePrep: false);
      expect(result.exitCode, 1);
      expect(
        result.stderr,
        allOf(
          contains(
            '- packages/genkit_llamadart/pubspec.yaml is 131073 bytes; '
            'pub.dev rejects genkit_llamadart',
          ),
          contains(
            '- packages/genkit_llamadart/README.md is 262145 bytes; '
            'pub.dev rejects genkit_llamadart',
          ),
        ),
      );
    });

    test('fails an oversized companion pubspec', () {
      write(
        'packages/llamadart_llama_cpp_flutter/pubspec.yaml',
        pubPubspecLimitBytes + 1,
      );
      final result = verify(releasePrep: false);
      expect(result.stderr, contains('pubspec.yaml is 131073 bytes'));
    });

    test('does not require genkit_llamadart to exist or share versions', () {
      final result = verify(releasePrep: false);
      expect(result.stderr, isNot(contains('genkit_llamadart')));
    });

    test('passes a changelog under the limit', () {
      write('CHANGELOG.md', pubContentLimitBytes);
      final result = verify(releasePrep: false);
      expect(result.stderr, isNot(contains('pub.dev rejects')));
      expect(
        result.stdout,
        contains('Warning: CHANGELOG.md is 262144 bytes, within 10%'),
      );
    });
  });
}
