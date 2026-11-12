@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('build_site.sh', () {
    late _BuildSiteFixture fixture;

    setUp(() {
      fixture = _BuildSiteFixture();
    });

    tearDown(() {
      fixture.root.deleteSync(recursive: true);
    });

    test('keeps the default build and all validation commands', () async {
      final result = await fixture.run(const []);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(fixture.calls, fixture.expectedCalls());
    });

    for (final port in ['1', '43831', '65535']) {
      test('forwards port $port only to the Jaspr build', () async {
        final result = await fixture.run(['--port', port]);
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
        expect(fixture.calls, fixture.expectedCalls(port: port));
      });
    }

    test('shows help before resolving or building anything', () async {
      final result = await fixture.run(const ['--help']);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('--port PORT'));
      expect(result.stdout, contains('1 to 65535'));
      expect(fixture.log.existsSync(), isFalse);
    });

    test('rejects invalid arguments before resolving dependencies', () async {
      for (final args in <List<String>>[
        ['--port'],
        ['--unknown'],
        ['--port', '0'],
        ['--port', '65536'],
        ['--port', '-1'],
        ['--port', '+80'],
        ['--port', '080'],
        ['--port', '1.5'],
        ['--port', 'abc'],
        ['--port', '999999999999999999999'],
        ['--port', '80\n'],
        ['--port', '80', '--port', '81'],
        ['--help', 'extra'],
      ]) {
        final result = await fixture.run(args);
        expect(result.exitCode, 64, reason: '$args: ${result.stderr}');
        expect(result.stderr, contains('Usage:'), reason: '$args');
        expect(fixture.log.existsSync(), isFalse, reason: '$args');
      }
    });

    test('removing forwarding loses the explicitly selected port', () async {
      final source = fixture.script.readAsStringSync();
      const forwarding = r'dart run jaspr_cli:jaspr build "$@"';
      expect(forwarding.allMatches(source), hasLength(1));
      fixture.script.writeAsStringSync(
        source.replaceFirst(forwarding, 'dart run jaspr_cli:jaspr build'),
      );

      final result = await fixture.run(const ['--port', '43831']);
      expect(result.exitCode, 0);
      expect(fixture.calls, fixture.expectedCalls());
      expect(fixture.calls, isNot(fixture.expectedCalls(port: '43831')));
    });
  }, skip: Platform.isWindows ? 'requires a POSIX Bash runtime' : false);
}

class _BuildSiteFixture {
  _BuildSiteFixture() {
    root = Directory.systemTemp.createTempSync('docs-build-port-');
    website = Directory(p.join(root.path, 'website'))..createSync();
    observability = Directory(p.join(website.path, 'examples', 'observability'))
      ..createSync(recursive: true);
    final docs = Directory(p.join(root.path, 'tool', 'docs'))
      ..createSync(recursive: true);
    script = File(
      'tool/docs/build_site.sh',
    ).copySync(p.join(docs.path, 'build_site.sh'));
    bin = Directory(p.join(root.path, 'bin'))..createSync();
    log = File(p.join(root.path, 'calls.log'));
    for (final command in ['dart', 'npx']) {
      final stub = File(p.join(bin.path, command));
      stub.writeAsStringSync('''#!/usr/bin/env bash
{
  printf 'tool=%s\\n' '$command'
  printf 'cwd=%s\\n' "\$PWD"
  printf 'arg=%s\\n' "\$@"
  printf 'end\\n'
} >> "\$CALL_LOG"
''');
      final chmod = Process.runSync('chmod', ['+x', stub.path]);
      expect(chmod.exitCode, 0, reason: '${chmod.stderr}');
    }
  }

  late final Directory root;
  late final Directory website;
  late final Directory observability;
  late final Directory bin;
  late final File script;
  late final File log;

  Future<ProcessResult> run(List<String> args) => Process.run(
    'bash',
    [script.path, ...args],
    workingDirectory: root.path,
    environment: {
      'PATH': '${bin.path}:${Platform.environment['PATH']}',
      'CALL_LOG': log.path,
    },
  );

  List<String> get calls => log.readAsLinesSync();

  List<String> expectedCalls({String? port}) => [
    ..._call('dart', observability, ['pub', 'get']),
    ..._call('dart', observability, [
      'format',
      '--output=none',
      '--set-exit-if-changed',
      '.',
    ]),
    ..._call('dart', observability, ['analyze', '--fatal-infos']),
    ..._call('dart', observability, ['test', '-p', 'vm']),
    ..._call('dart', website, ['pub', 'get']),
    ..._call('dart', website, [
      'run',
      'jaspr_cli:jaspr',
      'build',
      if (port != null) ...['--port', port],
    ]),
    ..._call('dart', website, [
      'run',
      'tool/finalize_site.dart',
      'build/jaspr',
    ]),
    ..._call('npx', website, [
      '--yes',
      'pagefind@1.5.2',
      '--site',
      'build/jaspr',
    ]),
  ];

  List<String> _call(String command, Directory cwd, List<String> args) => [
    'tool=$command',
    'cwd=${cwd.path}',
    for (final arg in args) 'arg=$arg',
    'end',
  ];
}
