@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/release/companion_pub_preflight.dart';
import '../../support/dart_script_snapshot.dart';

const _preflightCommand = 'dart run tool/release/companion_pub_preflight.dart';
const _validateStep = '- name: Validate release state';
const _publishStep = '- name: Publish core tag and companion packages';

/// Why [workflow] could push a release tag before the companion preflight.
List<String> _preflightContractProblems(String workflow) {
  final problems = <String>[];
  final commands = RegExp(
    '^\\s+${RegExp.escape(_preflightCommand)}\\s*\$',
    multiLine: true,
  ).allMatches(workflow).toList();
  if (commands.length != 1) {
    problems.add(
      'expected exactly one bare companion preflight, found '
      '${commands.length}',
    );
    return problems;
  }
  final preflight = commands.single.start;
  final validate = workflow.indexOf(_validateStep);
  final publish = workflow.indexOf(_publishStep);
  final firstTagPush = workflow.indexOf(
    RegExp(r'^\s+push_tag "', multiLine: true),
  );
  if (validate == -1 || publish == -1 || firstTagPush == -1) {
    problems.add('release validation, publication or tag push is missing');
  } else if (!(validate < preflight && preflight < publish)) {
    problems.add(
      'the companion preflight must run in release validation, before any '
      'tag is pushed',
    );
  }
  return problems;
}

/// Why [workflow] could publish a companion before the core it constrains.
List<String> _publishOrderProblems(String workflow) {
  final problems = <String>[];
  final publish = workflow.indexOf(_publishStep);
  if (publish == -1) return ['the publication step is missing'];
  final step = workflow.substring(publish);
  final corePush = RegExp(
    r'^\s+push_tag "\$CORE_TAG"\s*$',
    multiLine: true,
  ).allMatches(step).toList();
  final coreWait = RegExp(
    r'^\s+wait_for_pub_version "llamadart" "\$CORE_VERSION"(?: \\)?$',
    multiLine: true,
  ).allMatches(step).toList();
  final companionPush = RegExp(
    r'^\s+push_tag "\$companion_tag"\s*$',
    multiLine: true,
  ).allMatches(step).toList();
  if (corePush.length != 1 ||
      coreWait.length != 1 ||
      companionPush.length != 1) {
    problems.add(
      'expected one core tag push, one core pub.dev wait and one companion '
      'tag push',
    );
    return problems;
  }
  if (!(corePush.single.start < coreWait.single.start &&
      coreWait.single.start < companionPush.single.start)) {
    problems.add(
      'companions must publish only after the core they constrain is on '
      'pub.dev',
    );
  }
  final listingWait = RegExp(
    r'local package_url="https://pub\.dev/api/packages/\$package_name"\s*$'
    r'[\s\S]*?curl -fsSL --max-time [0-9]+ "\$package_url" \|\s*'
    r'jq -e --arg version "\$package_version" '
    "'any\\(\\.versions\\[\\]; \\.version == \\\$version\\)'",
    multiLine: true,
  );
  if (!listingWait.hasMatch(step)) {
    problems.add('pub.dev waits must read the package listing pub resolves');
  }
  if (!workflow.contains(
    'if [[ "\$core_tag_sha" != "\$release_sha" ]]; then',
  )) {
    problems.add('a rerun must refuse a core tag at another commit');
  }
  return problems;
}

typedef _Fetch = Future<PubDevResponse> Function(Uri uri);

/// A repo holding one companion pubspec at [version] constraining core to
/// [core], or declaring no core dependency when [core] is null.
({Directory root, List<CompanionPackage> companions}) _repo({
  String version = '0.0.24',
  String? core = "'>=0.13.0 <0.14.0'",
}) {
  final root = Directory.systemTemp.createTempSync('companion_preflight_');
  addTearDown(() => root.deleteSync(recursive: true));
  const companion = (
    name: 'llamadart_llama_cpp_flutter',
    path: 'packages/llamadart_llama_cpp_flutter',
  );
  File(
    '${root.path}/${companion.path}/darwin/${companion.name}/Package.swift',
  ).createSync(recursive: true);
  File('${root.path}/${companion.path}/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      'name: ${companion.name}\nversion: $version\ndependencies:\n'
      '  flutter:\n    sdk: flutter\n'
      '${core == null ? '' : '  llamadart: $core\n'}',
    );
  return (root: root, companions: [companion]);
}

_Fetch _published(Object? core, {List<Uri>? asked}) => (uri) async {
  asked?.add(uri);
  return (
    status: HttpStatus.ok,
    body: jsonEncode({
      'version': '0.0.24',
      'pubspec': {
        'name': 'llamadart_llama_cpp_flutter',
        'dependencies': {
          'flutter': {'sdk': 'flutter'},
          'llamadart': ?core,
        },
      },
    }),
  );
};

void main() {
  final companions = discoverAppleCompanionPackages(Directory.current);

  test('discovers every Flutter Apple companion and nothing else', () {
    expect(companions, [
      (
        name: 'llamadart_litert_lm_flutter',
        path: 'packages/llamadart_litert_lm_flutter',
      ),
      (
        name: 'llamadart_llama_cpp_flutter',
        path: 'packages/llamadart_llama_cpp_flutter',
      ),
      (
        name: 'llamadart_stable_diffusion_flutter',
        path: 'packages/llamadart_stable_diffusion_flutter',
      ),
    ]);
  });

  test('packages pub.dev knows pass', () async {
    final asked = <Uri>[];
    final problems = await companionPubPreflightProblems(companions, (
      uri,
    ) async {
      asked.add(uri);
      return HttpStatus.ok;
    });

    expect(problems, isEmpty);
    expect(asked, [
      for (final companion in companions)
        Uri.parse('https://pub.dev/api/packages/${companion.name}'),
    ]);
  });

  test('a package missing from pub.dev gets the first-publish steps', () async {
    final problems = await companionPubPreflightProblems(
      companions,
      (uri) async => uri.path.endsWith('/llamadart_stable_diffusion_flutter')
          ? HttpStatus.notFound
          : HttpStatus.ok,
    );

    expect(problems, hasLength(1));
    expect(
      problems.single,
      allOf(
        startsWith('llamadart_stable_diffusion_flutter does not exist on pub'),
        contains('no release tags were pushed'),
        contains('packages/llamadart_stable_diffusion_flutter/'),
        contains('flutter pub publish)'),
        contains('transfer the package to the\n     leehack.com publisher'),
        contains(
          'repository leehack/llamadart with tag pattern '
          'llamadart_stable_diffusion_flutter-v{{version}}',
        ),
      ),
    );
  });

  test('an unconfirmed package fails closed', () async {
    final problems = await companionPubPreflightProblems(
      companions.take(2).toList(),
      (uri) async => uri.path.endsWith('/llamadart_litert_lm_flutter')
          ? throw const SocketException('offline')
          : HttpStatus.serviceUnavailable,
    );

    expect(problems, [contains('offline'), contains('HTTP 503')]);
  });

  group('companionPublishedConstraintProblems', () {
    test('an unpublished version passes', () async {
      final repo = _repo();
      final asked = <Uri>[];

      final problems = await companionPublishedConstraintProblems(
        repo.root,
        repo.companions,
        (uri) async {
          asked.add(uri);
          return (status: HttpStatus.notFound, body: '');
        },
      );

      expect(problems, isEmpty);
      expect(asked, [
        Uri.parse(
          'https://pub.dev/api/packages/llamadart_llama_cpp_flutter/'
          'versions/0.0.24',
        ),
      ]);
    });

    test('a published version with the same constraint passes', () async {
      final repo = _repo();

      expect(
        await companionPublishedConstraintProblems(
          repo.root,
          repo.companions,
          _published('>=0.13.0 <0.14.0'),
        ),
        isEmpty,
      );
    });

    test('a published version with no constraint, like the checkout, '
        'passes', () async {
      final repo = _repo(core: null);

      expect(
        await companionPublishedConstraintProblems(
          repo.root,
          repo.companions,
          _published(null),
        ),
        isEmpty,
      );
    });

    test('a constraint changed without a version bump fails', () async {
      for (final published in <Object?>[
        null,
        '>=0.12.2 <0.13.0',
        {'path': '../..'},
      ]) {
        final repo = _repo();

        final problems = await companionPublishedConstraintProblems(
          repo.root,
          repo.companions,
          _published(published),
        );

        expect(problems, [
          allOf(
            startsWith(
              'llamadart_llama_cpp_flutter 0.0.24 is already on pub.dev '
              'with `llamadart: ${published ?? '<none>'}`',
            ),
            contains('declares `llamadart: >=0.13.0 <0.14.0`'),
            contains('bump llamadart_llama_cpp_flutter past 0.0.24'),
            contains('No release tags were pushed.'),
          ),
        ], reason: '$published');
      }
    });

    test('an unconfirmed version fails closed', () async {
      for (final fetch in <_Fetch>[
        (uri) async => throw const SocketException('offline'),
        (uri) async => (status: HttpStatus.serviceUnavailable, body: ''),
        (uri) async => (status: HttpStatus.ok, body: '{"version":"0.0.24"}'),
        (uri) async => (status: HttpStatus.ok, body: 'not json'),
      ]) {
        final repo = _repo();

        expect(
          await companionPublishedConstraintProblems(
            repo.root,
            repo.companions,
            fetch,
          ),
          [contains('0.0.24')],
        );
      }
    });

    test('a pubspec without a version fails', () async {
      final repo = _repo();
      File(
        '${repo.root.path}/${repo.companions.single.path}/pubspec.yaml',
      ).writeAsStringSync('name: llamadart_llama_cpp_flutter\n');

      expect(
        await companionPublishedConstraintProblems(
          repo.root,
          repo.companions,
          _published(null),
        ),
        [contains('does not declare a version')],
      );
    });
  });

  test('the first-publish steps resolve core from pub.dev', () {
    final steps = firstPublishInstructions(companions.first);

    expect(steps, contains("--exclude='pubspec_overrides.yaml'"));
    expect(steps, contains('already released'));
  });

  group('runCompanionPubPreflight', () {
    /// Answers the package listing with [listing] and the version with
    /// [version], recording each [Uri] asked in [asked].
    _Fetch pubDev({
      int listing = HttpStatus.ok,
      PubDevResponse version = (status: HttpStatus.notFound, body: ''),
      List<Uri>? asked,
    }) => (uri) async {
      asked?.add(uri);
      return uri.pathSegments.contains('versions')
          ? version
          : (status: listing, body: '{}');
    };

    Future<({int code, String out, String err})> run(
      Directory root,
      _Fetch get,
    ) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCompanionPubPreflight(
        root,
        get,
        out: out,
        err: err,
      );
      return (code: code, out: '$out', err: '$err');
    }

    test('passes when both checks pass', () async {
      final repo = _repo();
      final asked = <Uri>[];

      final result = await run(repo.root, pubDev(asked: asked));

      expect(result.code, 0);
      expect(result.err, isEmpty);
      expect(result.out, contains('llamadart_llama_cpp_flutter'));
      expect(asked, [
        Uri.parse('https://pub.dev/api/packages/llamadart_llama_cpp_flutter'),
        Uri.parse(
          'https://pub.dev/api/packages/llamadart_llama_cpp_flutter/'
          'versions/0.0.24',
        ),
      ]);
    });

    test('fails on a package missing from pub.dev', () async {
      final result = await run(
        _repo().root,
        pubDev(listing: HttpStatus.notFound),
      );

      expect(result.code, 1);
      expect(
        result.err,
        allOf(
          startsWith('Companion pub.dev preflight failed:'),
          contains('does not exist on pub.dev yet'),
        ),
      );
    });

    test('fails on a published version with another constraint', () async {
      final result = await run(
        _repo().root,
        pubDev(version: await _published('>=0.12.0 <0.13.0')(Uri())),
      );

      expect(result.code, 1);
      expect(result.err, contains('bump llamadart_llama_cpp_flutter past'));
    });

    test('fails without companions', () async {
      final root = Directory.systemTemp.createTempSync('companion_preflight_');
      addTearDown(() => root.deleteSync(recursive: true));

      final result = await run(root, pubDev());

      expect(result.code, 1);
      expect(result.err, contains('No Flutter Apple companion packages'));
    });
  });

  group('getWithOneRetry', () {
    const ok = (status: HttpStatus.ok, body: 'ok');
    final uri = Uri.parse('https://pub.dev/api/packages/companion');

    Future<(PubDevResponse, int)> fetch(List<Object> answers) async {
      var calls = 0;
      final response = await getWithOneRetry(uri, (asked) async {
        expect(asked, uri);
        final answer = answers[calls++];
        if (answer is Exception) throw answer;
        return answer as PubDevResponse;
      }, retryDelay: Duration.zero);
      return (response, calls);
    }

    test('does not retry an answer below 500', () async {
      expect(await fetch([ok]), (ok, 1));
      const missing = (status: HttpStatus.notFound, body: '');
      expect(await fetch([missing]), (missing, 1));
    });

    test('retries a stalled body or a 5xx answer once', () async {
      expect(await fetch([TimeoutException('body'), ok]), (ok, 2));
      expect(await fetch([const SocketException('reset'), ok]), (ok, 2));
      expect(
        await fetch([(status: HttpStatus.serviceUnavailable, body: ''), ok]),
        (ok, 2),
      );
    });

    test('reports a second failure', () async {
      const unavailable = (status: HttpStatus.badGateway, body: '');
      expect(await fetch([unavailable, unavailable]), (unavailable, 2));
      await expectLater(
        fetch([TimeoutException('first'), TimeoutException('second')]),
        throwsA(
          isA<TimeoutException>().having(
            (error) => error.message,
            'message',
            'second',
          ),
        ),
      );
    });
  });

  test('pubDevGet times out a body that stalls after its headers', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response
        ..contentLength = 1024
        ..write('{"versions":');
      await request.response.flush();
    });

    await expectLater(
      pubDevGet(
        Uri.http('127.0.0.1:${server.port}', '/api/packages/companion'),
        bodyTimeout: const Duration(milliseconds: 200),
      ),
      throwsA(isA<TimeoutException>()),
    );
  }, timeout: const Timeout(Duration(seconds: 20)));

  group('the preflight CLI', () {
    const script = 'tool/release/companion_pub_preflight.dart';
    late String snapshot;
    setUpAll(() async => snapshot = await compileDartScript(script));

    ProcessResult runCli(List<String> arguments) {
      final cwd = Directory.systemTemp.createTempSync('companion_preflight_');
      addTearDown(() => cwd.deleteSync(recursive: true));
      return Process.runSync(Platform.resolvedExecutable, [
        '--packages=${File('.dart_tool/package_config.json').absolute.path}',
        snapshot,
        ...arguments,
      ], workingDirectory: cwd.path);
    }

    test('exits with the preflight result for the current directory', () {
      final result = runCli(const []);

      expect(result.exitCode, 1, reason: '${result.stderr}');
      expect(
        '${result.stderr}',
        contains('No Flutter Apple companion packages found under packages/.'),
      );
    });

    test('rejects arguments', () {
      expect(runCli(const ['--release-prep']).exitCode, 64);
    });

    test('fetches pub.dev with one retry', () {
      final source = File(script).readAsStringSync().replaceAll('\r\n', '\n');
      final wired = RegExp(
        r'exitCode = await runCompanionPubPreflight\(\s*Directory\.current,\s*'
        r'\(uri\) => getWithOneRetry\(uri, pubDevGet\),',
      );

      expect(wired.hasMatch(source), isTrue);
      for (final mutated in [
        source.replaceFirst(
          '(uri) => getWithOneRetry(uri, pubDevGet)',
          'pubDevGet',
        ),
        source.replaceFirst(
          'exitCode = await runCompanionPubPreflight(',
          'await runCompanionPubPreflight(',
        ),
        source.replaceFirst(
          'runCompanionPubPreflight(\n    Directory.current,',
          'runCompanionPubPreflight(\n    Directory.systemTemp,',
        ),
      ]) {
        expect(mutated, isNot(source));
        expect(wired.hasMatch(mutated), isFalse);
      }
    });
  });

  test('the release workflow publishes the core before any companion', () {
    final workflow = File(
      '.github/workflows/release_on_prep_merge.yml',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(_publishOrderProblems(workflow), isEmpty);
  });

  test('the publish-order contract rejects companions first', () {
    final workflow = File(
      '.github/workflows/release_on_prep_merge.yml',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final coreBlock = RegExp(
      r'^ +wait_for_pub_version "llamadart" .*\\\n.*\n',
      multiLine: true,
    ).firstMatch(workflow)![0]!;
    final companionWait = RegExp(
      r'^ +wait_for_pub_version "\$package_name" .*\\\n.*\n +done\n',
      multiLine: true,
    ).firstMatch(workflow)![0]!;

    for (final mutated in [
      workflow
          .replaceFirst(coreBlock, '')
          .replaceFirst(companionWait, '$companionWait$coreBlock'),
      workflow.replaceFirst(
        'curl -fsSL --max-time 30 "\$package_url" |',
        'curl -fsSL --max-time 30 "\$package_url/versions/\$package_version" |',
      ),
      workflow.replaceFirst(
        'if [[ "\$core_tag_sha" != "\$release_sha" ]]; then',
        'if false; then',
      ),
    ]) {
      expect(_publishOrderProblems(mutated), isNotEmpty);
    }
  });

  test('the release workflow runs the preflight before any tag push', () {
    final workflow = File(
      '.github/workflows/release_on_prep_merge.yml',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(_preflightContractProblems(workflow), isEmpty);
  });

  test('the preflight contract rejects deletion, bypass and late runs', () {
    final workflow = File(
      '.github/workflows/release_on_prep_merge.yml',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    for (final mutated in [
      workflow.replaceFirst(_preflightCommand, ''),
      workflow.replaceFirst(_preflightCommand, '$_preflightCommand || true'),
      workflow
          .replaceFirst(_preflightCommand, '')
          .replaceFirst(
            'push_tag "\$CORE_TAG"',
            '$_preflightCommand\n          push_tag "\$CORE_TAG"',
          ),
    ]) {
      expect(_preflightContractProblems(mutated), isNotEmpty);
    }
  });
}
