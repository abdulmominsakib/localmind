@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const _posixOnly = 'runs workflow scripts under a POSIX Bash runtime';

const _releaseWorkflow = '.github/workflows/release_on_prep_merge.yml';
const _companionWorkflow = '.github/workflows/publish_companion_pubdev.yml';
const _ciWorkflow = '.github/workflows/ci.yml';

const _releaseSha = '1111111111111111111111111111111111111111';
const _otherSha = '2222222222222222222222222222222222222222';
const _tagObjectSha = '3333333333333333333333333333333333333333';

const _companions = <String>[
  'llamadart_llama_cpp_flutter',
  'llamadart_litert_lm_flutter',
  'llamadart_stable_diffusion_flutter',
];

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

YamlMap _step(String workflow, String job, String name) {
  final jobs = (loadYaml(workflow) as YamlMap)['jobs'] as YamlMap;
  final steps = (jobs[job] as YamlMap)['steps'] as YamlList;
  return steps.cast<YamlMap>().singleWhere((step) => step['name'] == name);
}

/// Commands the workflow scripts call, replaced by stubs that log every call
/// to `$STUB_LOG` and answer from files under `$STUB_STATE`.
const _stubs = <String, String>{
  'dart': r'''
if [[ "$1" == tool/release/stage_companion_package.dart ]]; then
  exec "$STUB_REAL_DART" "$@"
fi
if [[ -f "$STUB_STATE/dart_failures" ]] && grep -Fxq "$2" "$STUB_STATE/dart_failures"; then
  exit 1
fi
''',
  'sleep': '',
  'gh': r'''
if [[ "$1" == release ]]; then
  exit 0
fi
''',
  'git': r'''
case "$1" in
  rev-parse)
    echo "$STUB_HEAD"
    ;;
  ls-remote)
    if [[ -f "$STUB_STATE/ls_remote_failures" ]]; then
      for arg in "$@"; do
        if grep -Fxq -- "$arg" "$STUB_STATE/ls_remote_failures"; then
          echo "fatal: unable to access origin" >&2
          exit 128
        fi
      done
    fi
    found=false
    for arg in "$@"; do
      [[ "$arg" == refs/tags/* ]] || continue
      while read -r sha ref; do
        if [[ "$ref" == "$arg" ]]; then
          printf '%s\t%s\n' "$sha" "$ref"
          found=true
        fi
      done < "$STUB_STATE/remote_tags"
    done
    if [[ "$found" == false && " $* " == *" --exit-code "* ]]; then
      exit 2
    fi
    ;;
  *)
    exit 1
    ;;
esac
''',
  'curl': r'''
url="${*: -1}"
body="$STUB_STATE/pub/${url//[!A-Za-z0-9]/_}"
out=""
write_out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift ;;
    -w) write_out="$2"; shift ;;
  esac
  shift
done
if [[ -n "$write_out" ]]; then
  if [[ -f "$body" ]]; then
    cat "$body" > "$out"
    echo 200
  else
    echo '{}' > "$out"
    echo 404
  fi
elif [[ -f "$body" ]]; then
  cat "$body"
else
  exit 22
fi
''',
  'flutter': r'''
failures="$STUB_STATE/pub_get_failures"
if [[ "$1 $2" == "pub get" && -f "$failures" ]]; then
  left="$(cat "$failures")"
  if (( left > 0 )); then
    echo "$((left - 1))" > "$failures"
    exit 1
  fi
fi
{
  echo "pwd=$PWD"
  if [[ -f pubspec_overrides.yaml ]]; then
    echo "--- pubspec_overrides.yaml"
    cat pubspec_overrides.yaml
  fi
} >> "$STUB_STATE/flutter_calls"
''',
};

/// Directory of the [_stubs], which every sandbox shares: they keep all state
/// under the sandbox's `$STUB_LOG` and `$STUB_STATE`.
late final String _stubBin;

/// Writes the [_stubs] once for the suite: a `chmod` per stub for every
/// sandbox would spawn more processes than the workflow scripts themselves.
String _writeStubs() {
  final bin = Directory.systemTemp
      .createTempSync('companion_release_workflow_stubs_')
      .resolveSymbolicLinksSync();
  addTearDown(() => Directory(bin).deleteSync(recursive: true));
  final paths = [
    for (final stub in _stubs.entries)
      (File('$bin/${stub.key}')..writeAsStringSync(
            '#!/usr/bin/env bash\n'
            'printf \'%s\\n\' "${stub.key} \$*" >> "\$STUB_LOG"\n'
            '${stub.value}',
          ))
          .path,
  ];
  final chmod = Process.runSync('chmod', ['+x', ...paths]);
  if (chmod.exitCode != 0) throw StateError('chmod failed: ${chmod.stderr}');
  return bin;
}

/// A scratch directory whose commands resolve to the [_stubs] first.
class _Sandbox {
  _Sandbox._(this.root);

  factory _Sandbox() {
    final root = Directory.systemTemp
        .createTempSync('companion_release_workflow_')
        .resolveSymbolicLinksSync();
    final sandbox = _Sandbox._(root);
    Directory('${sandbox.state}/pub').createSync(recursive: true);
    File('${sandbox.state}/remote_tags').writeAsStringSync('');
    addTearDown(() => Directory(root).deleteSync(recursive: true));
    return sandbox;
  }

  final String root;

  String get state => '$root/state';
  String get log => '$root/stub.log';

  List<String> get calls =>
      File(log).existsSync() ? File(log).readAsLinesSync() : const <String>[];

  void remoteTag(String sha, String ref) => File(
    '$state/remote_tags',
  ).writeAsStringSync('$sha $ref\n', mode: FileMode.append);

  /// Makes `git ls-remote` exit 128 whenever it is asked for [ref].
  void lsRemoteFails(String ref) => File(
    '$state/ls_remote_failures',
  ).writeAsStringSync('$ref\n', mode: FileMode.append);

  void pub(String url, String body) => File(
    '$state/pub/${url.replaceAll(RegExp('[^A-Za-z0-9]'), '_')}',
  ).writeAsStringSync(body);

  void file(String path, String contents) => File('$root/$path')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(contents);

  /// Runs [step]'s script the way Actions runs it on Linux: `shell: bash`
  /// adds `-o pipefail` to the default `bash -e`.
  ProcessResult run(
    YamlMap step, {
    required String workingDirectory,
    Map<String, String> env = const {},
  }) {
    final path = '$root/step.sh';
    File(path).writeAsStringSync('${step['run']}');
    return Process.runSync(
      'bash',
      [
        '--noprofile',
        '--norc',
        '-e',
        if (step['shell'] == 'bash') ...['-o', 'pipefail'],
        path,
      ],
      workingDirectory: workingDirectory,
      environment: {
        'PATH': '$_stubBin:${Platform.environment['PATH']}',
        'STUB_LOG': log,
        'STUB_STATE': state,
        'STUB_HEAD': _releaseSha,
        ...env,
      },
    );
  }
}

/// Resolves a step's `env` the way Actions would, using [values] for the
/// expressions the step may reference.
({Map<String, String> env, List<String> problems}) _resolveEnv(
  YamlMap step,
  Map<String, String> values,
) {
  final env = <String, String>{};
  final problems = <String>[];
  final expression = RegExp(r'^\$\{\{\s*([^}\s]+)\s*\}\}$');
  for (final entry in ((step['env'] as YamlMap?) ?? YamlMap()).entries) {
    final raw = '${entry.value}';
    final match = expression.firstMatch(raw);
    if (match == null) {
      env['${entry.key}'] = raw;
      continue;
    }
    final value = values[match.group(1)];
    if (value == null) {
      problems.add('${step['name']} maps ${entry.key} to unknown $raw');
      continue;
    }
    env['${entry.key}'] = value;
  }
  return (env: env, problems: problems);
}

Map<String, String> _outputs(String path) => {
  for (final line in File(path).readAsLinesSync())
    if (line.contains('='))
      line.substring(0, line.indexOf('=')): line.substring(
        line.indexOf('=') + 1,
      ),
};

/// Remote state for one release run of core `0.13.0`, unless [version]
/// names another core; [failingDart] lists the `dart run` scripts that fail.
typedef _Release = ({
  String name,
  void Function(_Sandbox sandbox) remote,
  Set<String> missingCompanions,
  String? version,
  Set<String> failingDart,
});

/// A [_Release] of core `0.13.0` whose `dart run` scripts all pass.
_Release _release(
  String name, {
  void Function(_Sandbox sandbox)? remote,
  Set<String> missingCompanions = const {},
}) => (
  name: name,
  remote: remote ?? (_) {},
  missingCompanions: missingCompanions,
  version: null,
  failingDart: const {},
);

const _coreListing = 'https://pub.dev/api/packages/llamadart';
const _preflightScript = 'tool/release/companion_pub_preflight.dart';
const _verifierScript = 'tool/testing/verify_release_docs_versions.dart';

/// Whether Actions keeps running the job's later steps after [step] fails.
bool _continuesOnError(YamlMap step) =>
    step['continue-on-error'] != null && step['continue-on-error'] != false;

/// Whether [step]'s `if` overrides the implicit `success()` that skips it
/// after an earlier step failed.
bool _runsAfterFailure(YamlMap step) =>
    RegExp(r'\b(always|failure|cancelled)\(\)').hasMatch('${step['if']}');

/// Runs the release workflow's validation and publication steps from
/// [workflow] against [release], and returns the step results and calls.
/// Publication runs after a failed validation only when Actions would run it.
({
  ProcessResult validate,
  ProcessResult? publish,
  List<String> calls,
  String output,
  List<String> problems,
})
_runRelease(String workflow, _Release release) {
  final version = release.version ?? '0.13.0';
  final sandbox = _Sandbox();
  final repo = '${sandbox.root}/repo';
  sandbox
    ..file('repo/pubspec.yaml', 'name: llamadart\nversion: $version\n')
    ..file('repo/CHANGELOG.md', '## $version\n\n- Release.\n')
    ..pub(_coreListing, '{"versions":[{"version":"$version"}]}');
  File(
    '${sandbox.state}/dart_failures',
  ).writeAsStringSync(release.failingDart.map((script) => '$script\n').join());
  for (final companion in _companions) {
    sandbox.file(
      'repo/packages/$companion/pubspec.yaml',
      'name: $companion\nversion: 0.13.0\n',
    );
    final listing = 'https://pub.dev/api/packages/$companion';
    sandbox.pub(listing, '{"versions":[{"version":"0.13.0"}]}');
    if (!release.missingCompanions.contains(companion)) {
      sandbox.pub('$listing/versions/0.13.0', '{}');
    }
  }
  release.remote(sandbox);

  final problems = <String>[];
  final validateStep = _step(workflow, 'release', 'Validate release state');
  final publishStep = _step(
    workflow,
    'release',
    'Publish core tag and companion packages',
  );
  final githubOutput = '${sandbox.root}/validate_output';
  File(githubOutput).createSync();
  final validate = sandbox.run(
    validateStep,
    workingDirectory: repo,
    env: {'GITHUB_OUTPUT': githubOutput},
  );
  if (validate.exitCode != 0 &&
      !_continuesOnError(validateStep) &&
      !_runsAfterFailure(publishStep)) {
    return (
      validate: validate,
      publish: null,
      calls: sandbox.calls,
      output: File(githubOutput).readAsStringSync(),
      problems: problems,
    );
  }

  final resolved = _resolveEnv(publishStep, {
    for (final output in _outputs(githubOutput).entries)
      'steps.${validateStep['id']}.outputs.${output.key}': output.value,
    'github.token': 'github-token',
    'secrets.RELEASE_AUTOMATION_TOKEN': 'release-token',
  });
  if (validate.exitCode == 0) problems.addAll(resolved.problems);
  final publish = sandbox.run(
    publishStep,
    workingDirectory: repo,
    env: {
      ...resolved.env,
      'GITHUB_REPOSITORY': 'leehack/llamadart',
      'PUBDEV_WAIT_ATTEMPTS': '1',
      'PUBDEV_WAIT_INTERVAL_SECONDS': '1',
      'GITHUB_RELEASE_WAIT_ATTEMPTS': '1',
      'GITHUB_RELEASE_WAIT_INTERVAL_SECONDS': '1',
    },
  );
  return (
    validate: validate,
    publish: publish,
    calls: sandbox.calls,
    output: File(githubOutput).readAsStringSync(),
    problems: problems,
  );
}

/// Why any of [steps] in [workflow]'s [job] could keep going past a failed
/// command: each script must start with `set -euo pipefail`.
List<String> _strictShellProblems(
  String workflow,
  String job,
  List<String> steps,
) => [
  for (final name in steps)
    if ('${_step(workflow, job, name)['run']}'.trimLeft().split('\n').first !=
        'set -euo pipefail')
      '$name must start with set -euo pipefail',
];

bool _pushed(List<String> calls, String tag) => calls.any(
  (call) =>
      call.startsWith('gh api') &&
      call.contains('ref=refs/tags/$tag ') &&
      call.contains('sha=$_releaseSha'),
);

bool _pushedAnyTag(List<String> calls) => calls.any(
  (call) => call.startsWith('gh api') && call.contains('ref=refs/tags/'),
);

/// Why [workflow] could push the core tag twice, resume at another commit or
/// leave a core or companion half-published without saying how to recover.
List<String> _releaseResumeProblems(String workflow) {
  final problems = <String>[];
  void check(bool ok, String problem) {
    if (!ok) problems.add(problem);
  }

  final fresh = _runRelease(
    workflow,
    _release('fresh', missingCompanions: {_companions.first}),
  );
  problems.addAll(fresh.problems);
  check(
    fresh.validate.exitCode == 0 && fresh.publish?.exitCode == 0,
    'a fresh release must succeed: ${fresh.validate.stderr}'
    '${fresh.publish?.stderr}',
  );
  check(
    fresh.output.contains('core_tag_exists=false\n'),
    'a fresh release must report no existing core tag',
  );
  check(_pushed(fresh.calls, 'v0.13.0'), 'a fresh release must push v0.13.0');
  final corePush = fresh.calls.indexWhere(
    (call) => call.contains('ref=refs/tags/v0.13.0 '),
  );
  final companionPush = fresh.calls.indexWhere(
    (call) => call.contains('ref=refs/tags/${_companions.first}-v0.13.0 '),
  );
  check(
    corePush != -1 && corePush < companionPush,
    'a missing companion must be tagged after the core',
  );
  final curls = fresh.calls.where((call) => call.startsWith('curl '));
  check(
    curls.isNotEmpty && curls.every((call) => call.contains('--max-time ')),
    'every pub.dev request must set --max-time',
  );

  for (final resume in <_Release>[
    _release(
      'lightweight tag at the release commit',
      remote: (sandbox) => sandbox.remoteTag(_releaseSha, 'refs/tags/v0.13.0'),
    ),
    _release(
      'annotated tag at the release commit',
      remote: (sandbox) => sandbox
        ..remoteTag(_tagObjectSha, 'refs/tags/v0.13.0')
        ..remoteTag(_releaseSha, 'refs/tags/v0.13.0^{}'),
    ),
  ]) {
    final run = _runRelease(workflow, resume);
    problems.addAll(run.problems);
    check(
      run.validate.exitCode == 0 && run.publish?.exitCode == 0,
      'a rerun with an existing ${resume.name} must succeed: ${run.validate.stderr}'
      '${run.publish?.stderr}',
    );
    check(
      run.output.contains('core_tag_exists=true\n'),
      'a rerun with an existing ${resume.name} must report the existing core tag',
    );
    check(
      !run.calls.any((call) => call.contains('ref=refs/tags/v0.13.0 ')),
      'a rerun with an existing ${resume.name} must not push v0.13.0 again',
    );
  }

  final moved = _runRelease(
    workflow,
    _release(
      'tag at another commit',
      remote: (sandbox) => sandbox.remoteTag(_otherSha, 'refs/tags/v0.13.0'),
    ),
  );
  check(
    moved.validate.exitCode != 0 &&
        '${moved.validate.stderr}'.contains(
          'already exists at $_otherSha, not $_releaseSha',
        ),
    'a core tag at another commit must stop the release',
  );
  check(
    !moved.output.contains('core_tag_exists='),
    'a core tag at another commit must not reach publication',
  );

  final companionTag = 'refs/tags/${_companions[1]}-v0.13.0';
  for (final halfPublished in <_Release>[
    _release(
      'lightweight companion tag at the release commit',
      remote: (sandbox) => sandbox
        ..remoteTag(_releaseSha, 'refs/tags/v0.13.0')
        ..remoteTag(_releaseSha, companionTag),
      missingCompanions: {_companions[1]},
    ),
    _release(
      'annotated companion tag at the release commit',
      remote: (sandbox) => sandbox
        ..remoteTag(_releaseSha, 'refs/tags/v0.13.0')
        ..remoteTag(_tagObjectSha, companionTag)
        ..remoteTag(_releaseSha, '$companionTag^{}'),
      missingCompanions: {_companions[1]},
    ),
  ]) {
    final run = _runRelease(workflow, halfPublished);
    final stderr = '${run.publish?.stderr}';
    check(
      run.publish != null &&
          run.publish!.exitCode != 0 &&
          stderr.contains('rerun that run') &&
          stderr.contains('publish_companion_pubdev.yml') &&
          stderr.contains('bumps the core version') &&
          !stderr.contains('already exists at'),
      'a ${halfPublished.name} without its pub.dev version must stop with '
      'both recovery paths: $stderr',
    );
    check(
      !run.calls.any((call) => call.contains('ref=$companionTag ')),
      'a ${halfPublished.name} must not be pushed again',
    );
  }

  final strayCompanion = _runRelease(
    workflow,
    _release(
      'companion tag at another commit',
      remote: (sandbox) => sandbox
        ..remoteTag(_releaseSha, 'refs/tags/v0.13.0')
        ..remoteTag(_tagObjectSha, companionTag)
        ..remoteTag(_otherSha, '$companionTag^{}'),
      missingCompanions: {_companions[1]},
    ),
  );
  final strayStderr = '${strayCompanion.publish?.stderr}';
  check(
    strayCompanion.publish != null &&
        strayCompanion.publish!.exitCode != 0 &&
        strayStderr.contains(
          '${_companions[1]}-v0.13.0 already exists at $_otherSha, not '
          '$_releaseSha',
        ) &&
        strayStderr.contains('bumps the core version') &&
        !strayStderr.contains('rerun that run'),
    'a companion tag at another commit must stop without advising a rerun '
    'that would publish that commit: $strayStderr',
  );
  check(
    !strayCompanion.calls.any((call) => call.contains('ref=$companionTag ')),
    'a companion tag at another commit must not be pushed again',
  );

  final coreMissing = _runRelease(
    workflow,
    _release(
      'core publish failure',
      remote: (sandbox) => sandbox
        ..remoteTag(_releaseSha, 'refs/tags/v0.13.0')
        ..pub(_coreListing, '{"versions":[{"version":"0.12.9"}]}'),
    ),
  );
  final coreStderr = '${coreMissing.publish?.stderr}';
  check(
    coreMissing.publish != null &&
        coreMissing.publish!.exitCode != 0 &&
        coreStderr.contains('llamadart 0.13.0 did not appear on pub.dev') &&
        coreStderr.contains('publish_pubdev.yml run for v0.13.0 failed') &&
        !_pushedAnyTag(coreMissing.calls),
    'a core missing from pub.dev must stop before any companion and name '
    'publish_pubdev.yml: $coreStderr',
  );

  final companionMissing = _runRelease(
    workflow,
    _release(
      'companion publish failure',
      remote: (sandbox) => sandbox.pub(
        'https://pub.dev/api/packages/${_companions.first}',
        '{"versions":[{"version":"0.0.24"}]}',
      ),
      missingCompanions: {_companions.first},
    ),
  );
  final companionStderr = '${companionMissing.publish?.stderr}';
  check(
    companionMissing.publish != null &&
        companionMissing.publish!.exitCode != 0 &&
        companionStderr.contains(
          'publish_companion_pubdev.yml run for ${_companions.first}-v0.13.0 '
          'failed',
        ) &&
        companionStderr.contains('automated publishing is enabled'),
    'a companion missing from pub.dev after its tag must name its publish '
    'run and automated publishing: $companionStderr',
  );
  return problems;
}

/// Why [workflow] could push a tag for a prerelease core, or after the
/// release verifier or companion preflight failed.
List<String> _releaseGuardProblems(String workflow) {
  final problems = <String>[
    ..._strictShellProblems(workflow, 'release', [
      'Check release-prep gate',
      'Validate release state',
      'Publish core tag and companion packages',
    ]),
  ];
  void check(bool ok, String problem) {
    if (!ok) problems.add(problem);
  }

  final prerelease = _runRelease(workflow, (
    name: 'prerelease core',
    remote: (_) {},
    missingCompanions: const {},
    version: '0.13.0-dev.1',
    failingDart: const {},
  ));
  check(
    prerelease.validate.exitCode != 0 &&
        '${prerelease.validate.stderr}'.contains(
          'publishes only stable core versions, but pubspec.yaml is the '
          'prerelease 0.13.0-dev.1',
        ) &&
        !prerelease.calls.any((call) => call.startsWith('dart ')) &&
        prerelease.publish == null &&
        !_pushedAnyTag(prerelease.calls),
    'a prerelease core must stop before the verifier and any tag: '
    '${prerelease.validate.stderr}${prerelease.publish?.stderr}',
  );

  final buildMetadata = _runRelease(workflow, (
    name: 'core with build metadata',
    remote: (_) {},
    missingCompanions: const {},
    version: '0.13.0+build-1',
    failingDart: const {},
  ));
  problems.addAll(buildMetadata.problems);
  check(
    buildMetadata.validate.exitCode == 0 &&
        buildMetadata.publish?.exitCode == 0 &&
        _pushed(buildMetadata.calls, 'v0.13.0+build-1'),
    'a core with build metadata is not a prerelease and must publish: '
    '${buildMetadata.validate.stderr}${buildMetadata.publish?.stderr}',
  );

  for (final script in [_verifierScript, _preflightScript]) {
    final run = _runRelease(workflow, (
      name: 'failing $script',
      remote: (_) {},
      missingCompanions: const {},
      version: null,
      failingDart: {script},
    ));
    check(
      run.calls.contains('dart run $script') ||
          run.calls.any((call) => call.startsWith('dart run $script ')),
      'release validation must run $script',
    );
    check(
      run.validate.exitCode != 0 &&
          run.publish == null &&
          !_pushedAnyTag(run.calls),
      'a failing $script must stop the release before any tag: '
      '${run.validate.stderr}${run.publish?.stderr}',
    );
  }

  final unreachableCore = _runRelease(
    workflow,
    _release(
      'unreachable core tag lookup',
      remote: (sandbox) => sandbox.lsRemoteFails('refs/tags/v0.13.0'),
    ),
  );
  check(
    unreachableCore.validate.exitCode != 0 &&
        unreachableCore.publish == null &&
        !unreachableCore.output.contains('core_tag_exists=') &&
        !_pushedAnyTag(unreachableCore.calls),
    'a failed core tag lookup must stop the release before any tag: '
    '${unreachableCore.validate.stderr}${unreachableCore.publish?.stderr}',
  );

  final companionTag = 'refs/tags/${_companions[1]}-v0.13.0';
  final unreachableCompanion = _runRelease(
    workflow,
    _release(
      'unreachable companion tag lookup',
      remote: (sandbox) => sandbox
        ..remoteTag(_releaseSha, 'refs/tags/v0.13.0')
        ..lsRemoteFails(companionTag),
      missingCompanions: {_companions[1]},
    ),
  );
  check(
    unreachableCompanion.validate.exitCode == 0 &&
        unreachableCompanion.publish != null &&
        unreachableCompanion.publish!.exitCode != 0 &&
        !_pushedAnyTag(unreachableCompanion.calls),
    'a failed companion tag lookup must stop before pushing the companion: '
    '${unreachableCompanion.validate.stderr}'
    '${unreachableCompanion.publish?.stderr}',
  );
  return problems;
}

/// Why [workflow]'s pub.dev checks could hang or misread a missing version.
List<String> _companionDecideProblems(String workflow) {
  final problems = <String>[
    ..._strictShellProblems(workflow, 'publish-companion', [
      'Resolve package from tag',
      'Decide whether to publish',
      'Install dependencies',
    ]),
  ];
  final step = _step(
    workflow,
    'publish-companion',
    'Decide whether to publish',
  );
  final resolved = _resolveEnv(step, {
    'steps.package.outputs.name': 'companion',
    'steps.package.outputs.version': '0.13.1',
  });
  problems.addAll(resolved.problems);
  for (final published in [false, true]) {
    final sandbox = _Sandbox();
    sandbox.pub('https://pub.dev/api/packages/companion', '{}');
    if (published) {
      sandbox.pub(
        'https://pub.dev/api/packages/companion/versions/0.13.1',
        '{}',
      );
    }
    final runnerTemp = '${sandbox.root}/runner';
    Directory(runnerTemp).createSync();
    final output = '${sandbox.root}/output';
    File(output).createSync();
    final result = sandbox.run(
      step,
      workingDirectory: sandbox.root,
      env: {
        ...resolved.env,
        'RUNNER_TEMP': runnerTemp,
        'GITHUB_OUTPUT': output,
      },
    );
    final curls = sandbox.calls.where((call) => call.startsWith('curl '));
    if (result.exitCode != 0 ||
        _outputs(output)['should_publish'] != '${!published}') {
      problems.add(
        'a ${published ? 'published' : 'missing'} version must set '
        'should_publish=${!published}: ${result.stderr}',
      );
    }
    if (curls.length != 2 ||
        !curls.every((call) => call.contains('--max-time '))) {
      problems.add('every pub.dev request must set --max-time');
    }
  }
  return problems;
}

/// Why [workflow]'s dependency install could fail on a pub.dev listing that
/// is still stale, or retry without end.
List<String> _companionInstallProblems(String workflow) {
  final problems = <String>[];
  final step = _step(workflow, 'publish-companion', 'Install dependencies');
  for (final (failures, succeeds) in [(0, true), (2, true), (3, false)]) {
    final sandbox = _Sandbox();
    File('${sandbox.state}/pub_get_failures').writeAsStringSync('$failures');
    final result = sandbox.run(step, workingDirectory: sandbox.root);
    final pubGets = sandbox.calls.where((call) => call == 'flutter pub get');
    final sleeps = sandbox.calls.where((call) => call == 'sleep 60');
    final attempts = succeeds ? failures + 1 : 3;
    if ((result.exitCode == 0) != succeeds ||
        pubGets.length != attempts ||
        sleeps.length != attempts - 1) {
      problems.add(
        '$failures failed flutter pub get runs must take $attempts attempts '
        'and ${succeeds ? 'succeed' : 'fail'}; ran ${pubGets.length}, slept '
        '${sleeps.length} times, exit ${result.exitCode}: ${result.stderr}',
      );
    }
  }
  return problems;
}

/// Why [workflow]'s real companion publish could resolve `llamadart` from the
/// checkout instead of pub.dev.
List<String> _companionPublishProblems(String workflow) {
  final problems = <String>[];
  const job = 'publish-companion';
  const copy = r'${{ runner.temp }}/pub-package';
  final sandbox = _Sandbox();
  final package = '${sandbox.root}/checkout/packages/companion';
  sandbox
    ..file(
      'checkout/tool/release/stage_companion_package.dart',
      _read('tool/release/stage_companion_package.dart'),
    )
    ..file('checkout/packages/companion/pubspec.yaml', 'name: companion\n')
    ..file(
      'checkout/packages/companion/pubspec_overrides.yaml',
      'dependency_overrides:\n  llamadart:\n    path: ../..\n',
    )
    ..file('checkout/packages/companion/pubspec.lock', '')
    ..file('checkout/packages/companion/.dart_tool/state', '');
  final runnerTemp = '${sandbox.root}/runner';
  Directory(runnerTemp).createSync();

  final prepare = _step(workflow, job, 'Prepare package');
  final resolved = _resolveEnv(prepare, {
    'steps.package.outputs.path': package,
  });
  problems.addAll(resolved.problems);
  final result = sandbox.run(
    prepare,
    workingDirectory: '${sandbox.root}/checkout',
    env: {
      ...resolved.env,
      'RUNNER_TEMP': runnerTemp,
      'STUB_REAL_DART': Platform.resolvedExecutable,
    },
  );
  final published = '$runnerTemp/pub-package';
  if (result.exitCode != 0) {
    problems.add('Prepare package failed: ${result.stderr}');
  } else {
    if (!File('$published/pubspec.yaml').existsSync()) {
      problems.add('the prepared copy must hold the package');
    }
    for (final dropped in [
      'pubspec_overrides.yaml',
      'pubspec.lock',
      '.dart_tool',
    ]) {
      if (FileSystemEntity.typeSync('$published/$dropped') !=
          FileSystemEntityType.notFound) {
        problems.add('the prepared copy must not hold $dropped');
      }
    }
  }
  for (final name in [
    'Install dependencies',
    'Publish - dry run',
    'Publish to pub.dev',
  ]) {
    if (_step(workflow, job, name)['working-directory'] != copy) {
      problems.add('$name must run in the prepared copy, $copy');
    }
  }
  return problems;
}

/// Why [workflow]'s companion publish dry-run could resolve `llamadart` from
/// pub.dev, or from a path outside this checkout.
/// The CI jobs whose publish dry-run resolves llamadart from the checkout,
/// with the working directory each must start in.
const _ciDryRunJobs = <String, String>{
  'companion-packages': r'${{ inputs.package }}',
  'model-store': 'packages/llamadart_model_store',
};

/// The composite action holding the steps of the `companion-packages` job.
const _companionAction = '.github/actions/companion-package/action.yml';

/// The source holding [job]'s dry-run: the action for companions, else the job.
String _ciDryRunSource(String job) =>
    job == 'companion-packages' ? _read(_companionAction) : _read(_ciWorkflow);

/// [source] with [edit] applied only to [job]'s dry-run.
String _editCiDryRun(String source, String job, String Function(String) edit) =>
    job == 'companion-packages' ? edit(source) : _editJob(source, job, edit);

YamlMap _ciDryRunStep(String source, String job) => job == 'companion-packages'
    ? ((loadYaml(source) as YamlMap)['runs']['steps'] as YamlList)
          .cast<YamlMap>()
          .singleWhere((step) => step['name'] == 'Publish dry-run')
    : _step(source, job, 'Publish dry-run');

/// [workflow] with [edit] applied only to [job]'s block.
String _editJob(String workflow, String job, String Function(String) edit) {
  final start = workflow.indexOf('\n  $job:\n');
  final next = RegExp(
    r'\n  [a-z][a-z0-9-]*:\n',
  ).firstMatch(workflow.substring(start + 1));
  final end = next == null ? workflow.length : start + 1 + next.start;
  return workflow.substring(0, start) +
      edit(workflow.substring(start, end)) +
      workflow.substring(end);
}

List<String> _ciDryRunProblems(
  String workflow, {
  String job = 'companion-packages',
}) {
  final problems = <String>[];
  final sandbox = _Sandbox();
  final workspace = '${sandbox.root}/workspace';
  final package = '$workspace/packages/companion';
  sandbox
    ..file('workspace/packages/companion/pubspec.yaml', 'name: companion\n')
    ..file(
      'workspace/packages/companion/pubspec_overrides.yaml',
      'dependency_overrides:\n  llamadart:\n    path: ../..\n',
    );
  final runnerTemp = '${sandbox.root}/runner';
  Directory(runnerTemp).createSync();

  final step = _ciDryRunStep(workflow, job);
  if (step['working-directory'] != _ciDryRunJobs[job]) {
    problems.add('the dry-run must start in the package');
  }
  final result = sandbox.run(
    step,
    workingDirectory: package,
    env: {'RUNNER_TEMP': runnerTemp, 'GITHUB_WORKSPACE': workspace},
  );
  if (result.exitCode != 0) {
    return [...problems, 'Publish dry-run failed: ${result.stderr}'];
  }
  if (!sandbox.calls.contains('flutter pub publish --dry-run')) {
    problems.add('the step must run flutter pub publish --dry-run');
  }
  final calls = File('${sandbox.state}/flutter_calls');
  final record = calls.existsSync() ? calls.readAsStringSync() : '';
  final cwd = RegExp(r'^pwd=(.*)$', multiLine: true).firstMatch(record);
  if (cwd == null || !cwd.group(1)!.startsWith('$runnerTemp/')) {
    problems.add('the dry-run must publish a temporary copy');
  }
  final overrides = record.split('--- pubspec_overrides.yaml\n');
  final Object? parsed = overrides.length == 2
      ? loadYaml(overrides.last)
      : null;
  Object? path;
  if (parsed is YamlMap) {
    final dependencyOverrides = parsed['dependency_overrides'];
    final core = dependencyOverrides is YamlMap
        ? dependencyOverrides['llamadart']
        : null;
    path = core is YamlMap ? core['path'] : null;
  }
  if (path != workspace) {
    problems.add(
      'the dry-run copy must override llamadart with the checkout '
      '$workspace, not ${path ?? 'nothing'}',
    );
  }
  return problems;
}

void main() {
  setUpAll(() {
    if (!Platform.isWindows) _stubBin = _writeStubs();
  });

  group('release_on_prep_merge.yml', () {
    final workflow = _read(_releaseWorkflow);

    test('resumes companion publication only at the release commit', () {
      expect(_releaseResumeProblems(workflow), isEmpty);
    });

    test('rejects a miswired core tag resume', () {
      final mutations = <String, String Function(String)>{
        'W1 always skips the core tag push': (source) => source.replaceFirst(
          'if [[ "\$CORE_TAG_EXISTS" == "true" ]]; then',
          'if true; then',
        ),
        'W2 continues past a core tag at another commit': (source) =>
            source.replaceFirst(
              'Refusing to publish again." >&2\n'
                  '              exit 1\n',
              'Refusing to publish again." >&2\n',
            ),
        'W3 assumes the core tag exists': (source) => source.replaceFirst(
          'core_tag_exists=false',
          'core_tag_exists=true',
        ),
        'W4 maps CORE_TAG_EXISTS to another output': (source) =>
            source.replaceFirst(
              r'CORE_TAG_EXISTS: ${{ steps.release.outputs.core_tag_exists }}',
              r'CORE_TAG_EXISTS: ${{ steps.release.outputs.core_tag }}',
            ),
        'pub.dev requests without --max-time': (source) =>
            source.replaceAll('curl -fsSL --max-time 30 ', 'curl -fsSL '),
        'no recovery steps for a half-published companion': (source) =>
            source.replaceFirst(
              RegExp(r'^.*rerun that run.*\n', multiLine: true),
              '',
            ),
        'trusts a companion tag at another commit': (source) =>
            source.replaceFirst(
              'if [[ "\$companion_tag_sha" != "\$RELEASE_SHA" ]]; then',
              'if false; then',
            ),
        'reads the companion tag object, not its commit': (source) =>
            source.replaceFirst(' "refs/tags/\$companion_tag^{}"', ''),
        'pushes a companion tag that already exists': (source) =>
            source.replaceFirst(
              'if [[ -n "\$companion_tag_sha" ]]; then',
              'if false; then',
            ),
        'no recovery for a core publish failure': (source) =>
            source.replaceFirst(
              'If the publish_pubdev.yml run for \$CORE_TAG failed, ',
              '',
            ),
        'no automated publishing hint for a companion': (source) =>
            source.replaceFirst(
              'confirm pub.dev automated publishing is enabled for '
                  '\$package_name with tag pattern '
                  '\$package_name-v{{version}}, ',
              '',
            ),
      };
      for (final mutation in mutations.entries) {
        final mutated = mutation.value(workflow);
        expect(mutated, isNot(workflow), reason: mutation.key);
        expect(
          _releaseResumeProblems(mutated),
          isNotEmpty,
          reason: mutation.key,
        );
      }
    });

    test('stops a prerelease core or a failed check before any tag', () {
      expect(_releaseGuardProblems(workflow), isEmpty);
    });

    test('rejects a bypassed release guard', () {
      const preflight = 'dart run $_preflightScript\n';
      final mutations = <String, String Function(String)>{
        'accepts a prerelease core': (source) => source.replaceFirst(
          'if [[ "\${version%%+*}" == *-* ]]; then',
          'if false; then',
        ),
        'treats build metadata as a prerelease': (source) => source
            .replaceFirst('"\${version%%+*}" == *-*', '"\$version" == *[-+]*'),
        'skips the companion preflight': (source) => source.replaceFirst(
          '          $preflight',
          '          if false; then\n            $preflight          fi\n',
        ),
        'ignores a failed companion preflight': (source) => source.replaceFirst(
          preflight,
          'dart run $_preflightScript || true\n',
        ),
        'ignores a failed release verifier': (source) => source.replaceFirst(
          'dart run $_verifierScript --release-prep\n',
          'dart run $_verifierScript --release-prep || true\n',
        ),
        'continues past a failed validation': (source) => source.replaceFirst(
          '        id: release\n',
          '        id: release\n        continue-on-error: true\n',
        ),
        'publishes after a failed validation': (source) => source.replaceFirst(
          "      - name: Publish core tag and companion packages\n"
              "        if: steps.gate.outputs.should_release == 'true'\n",
          "      - name: Publish core tag and companion packages\n"
              "        if: \${{ always() && steps.gate.outputs.should_release == 'true' }}\n",
        ),
        'validates without set -euo pipefail': (source) => source.replaceFirst(
          '          set -euo pipefail\n\n          version=',
          '          version=',
        ),
        'publishes without set -euo pipefail': (source) => source.replaceFirst(
          '          set -euo pipefail\n\n          if [[ -z "\${RELEASE_TOKEN:-}" ]]',
          '          if [[ -z "\${RELEASE_TOKEN:-}" ]]',
        ),
        'ignores a failed core tag lookup': (source) => source.replaceFirst(
          '            git ls-remote --tags origin "refs/tags/\$core_tag" '
              '"refs/tags/\$core_tag^{}" |\n',
          '            { git ls-remote --tags origin "refs/tags/\$core_tag" '
              '"refs/tags/\$core_tag^{}" || true; } |\n',
        ),
        'ignores a failed companion tag lookup': (source) => source.replaceFirst(
          '              git ls-remote --tags origin '
              '"refs/tags/\$companion_tag" "refs/tags/\$companion_tag^{}" |\n',
          '              { git ls-remote --tags origin '
              '"refs/tags/\$companion_tag" "refs/tags/\$companion_tag^{}" '
              '|| true; } |\n',
        ),
      };
      for (final mutation in mutations.entries) {
        final mutated = mutation.value(workflow);
        expect(mutated, isNot(workflow), reason: mutation.key);
        expect(
          _releaseGuardProblems(mutated),
          isNotEmpty,
          reason: mutation.key,
        );
      }
    });
  }, skip: Platform.isWindows ? _posixOnly : false);

  group('publish_companion_pubdev.yml', () {
    final workflow = _read(_companionWorkflow);

    test('publishes a copy without the checkout override', () {
      expect(_companionPublishProblems(workflow), isEmpty);
    });

    test('bounds pub.dev requests and retries a stale listing', () {
      expect(_companionDecideProblems(workflow), isEmpty);
      expect(_companionInstallProblems(workflow), isEmpty);
    });

    test('rejects unbounded or unretried pub.dev access', () {
      final decide = <String, String Function(String)>{
        'pub.dev requests without --max-time': (source) =>
            source.replaceAll('curl -sS --max-time 30 ', 'curl -sS '),
        'decides without set -euo pipefail': (source) => source.replaceFirst(
          '          set -euo pipefail\n          package_status=',
          '          package_status=',
        ),
      };
      final install = <String, String Function(String)>{
        'no flutter pub get retry': (source) =>
            source.replaceFirst('attempts=3\n', 'attempts=1\n'),
        'retries without a pause': (source) =>
            source.replaceFirst('              sleep 60\n', ''),
        'reports success after every attempt failed': (source) =>
            source.replaceFirst(
              '          echo "flutter pub get failed \$attempts times." >&2\n'
                  '          exit 1\n',
              '',
            ),
      };
      for (final (mutations, problems) in [
        (decide, _companionDecideProblems),
        (install, _companionInstallProblems),
      ]) {
        for (final mutation in mutations.entries) {
          final mutated = mutation.value(workflow);
          expect(mutated, isNot(workflow), reason: mutation.key);
          expect(problems(mutated), isNotEmpty, reason: mutation.key);
        }
      }
    });

    test('rejects a publish that keeps the checkout override', () {
      final mutations = <String, String Function(String)>{
        'W5 copies pubspec_overrides.yaml': (source) => source.replaceFirst(
          '          dart tool/release/stage_companion_package.dart \\\n'
              '            "\$PACKAGE_PATH" "\$RUNNER_TEMP/pub-package"',
          '          cp -R "\$PACKAGE_PATH" "\$RUNNER_TEMP/pub-package"',
        ),
        'publishes from the checkout': (source) => source.replaceFirst(
          'run: flutter pub publish --force\n'
              r'        working-directory: ${{ runner.temp }}/pub-package',
          'run: flutter pub publish --force\n'
              r'        working-directory: ${{ steps.package.outputs.path }}',
        ),
      };
      for (final mutation in mutations.entries) {
        final mutated = mutation.value(workflow);
        expect(mutated, isNot(workflow), reason: mutation.key);
        expect(
          _companionPublishProblems(mutated),
          isNotEmpty,
          reason: mutation.key,
        );
      }
    });
  }, skip: Platform.isWindows ? _posixOnly : false);

  group('ci.yml publish dry-runs', () {
    for (final job in _ciDryRunJobs.keys) {
      final workflow = _ciDryRunSource(job);

      test('$job resolves llamadart from this checkout', () {
        expect(_ciDryRunProblems(workflow, job: job), isEmpty);
      });

      test('$job rejects a dry-run without the checkout override', () {
        final override = RegExp(
          r" *printf 'dependency_overrides:.*\n"
          r'.*/pubspec_overrides\.yaml"\n',
        );
        final exclude = RegExp(r" *--exclude='pubspec_overrides\.yaml' \\\n");
        final mutations = <String, String Function(String)>{
          'W6 drops the override': (source) =>
              source.replaceFirst(override, ''),
          'W7 keeps the checkout override in the copy': (source) =>
              source.replaceFirst(override, '').replaceFirst(exclude, ''),
        };
        for (final mutation in mutations.entries) {
          final mutated = _editCiDryRun(workflow, job, mutation.value);
          expect(mutated, isNot(workflow), reason: mutation.key);
          expect(
            _ciDryRunProblems(mutated, job: job),
            isNotEmpty,
            reason: mutation.key,
          );
        }
      });
    }
  }, skip: Platform.isWindows ? _posixOnly : false);
}
