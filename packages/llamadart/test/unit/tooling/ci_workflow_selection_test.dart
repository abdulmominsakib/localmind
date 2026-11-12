@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../../tool/ci/test_shards.dart';

Map<String, dynamic> readWorkflow(String name) =>
    jsonDecode(
          jsonEncode(
            loadYaml(File('.github/workflows/$name.yml').readAsStringSync()),
          ),
        )
        as Map<String, dynamic>;

Future<Map<String, dynamic>> selected(List<String> paths) async {
  final result = await Process.run(Platform.isWindows ? 'python' : 'python3', [
    '-c',
    'import json,runpy,sys; m=runpy.run_path("tool/ci/select_jobs.py"); '
        'print(json.dumps(m["select"](json.loads(sys.argv[1]))))',
    jsonEncode(paths),
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

/// `SHARD_JOBS` of `tool/ci/select_jobs.py`: each matrix job outside the plan
/// mapped to the planned job whose selection it shares and that consumes it.
Future<Map<String, String>> shardJobs() async {
  final result = await Process.run(Platform.isWindows ? 'python' : 'python3', [
    '-c',
    'import json,runpy; '
        'print(json.dumps(runpy.run_path("tool/ci/select_jobs.py")["SHARD_JOBS"]))',
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return (jsonDecode(result.stdout as String) as Map).cast<String, String>();
}

/// The job checks out its own revision without credentials, the guard compares
/// that revision with `main`, the upload directly follows the guard, and nothing
/// after the guard runs unless it allowed the deploy.
void expectGuardedUpload(Map<String, dynamic> job, String demo) {
  final steps = job['steps'] as List;
  final checkout = steps.singleWhere(
    (step) => '${step['uses']}'.contains('checkout@'),
  );
  expect(checkout['with'], {
    'ref': r'${{ github.sha }}',
    'persist-credentials': false,
  });
  final guard = steps.indexWhere((step) => step['id'] == 'current');
  expect(guard, greaterThanOrEqualTo(0));
  expect(steps[guard]['run'], 'python3 tool/ci/deploy_guard.py $demo');
  final guardEnv = {...?job['env'] as Map?, ...?steps[guard]['env'] as Map?};
  expect(guardEnv['DEPLOY_SHA'], r'${{ github.sha }}');
  expect(guardEnv['GH_TOKEN'], r'${{ github.token }}');
  expect((steps[guard] as Map).containsKey('if'), isFalse);
  expect(jsonEncode(steps[guard]), isNot(contains('secrets.')));
  final upload = steps.indexWhere(
    (step) => jsonEncode(step).contains('secrets.HF_TOKEN'),
  );
  expect(upload, guard + 1);
  expect(steps.length, greaterThan(upload + 1));
  for (final step in steps.skip(guard + 1)) {
    expect(step['if'], "steps.current.outputs.deploy == 'true'");
  }
  for (final step in steps) {
    expect((step as Map).containsKey('continue-on-error'), isFalse);
  }
}

Future<Map<String, bool>> deploymentGuardVerdicts() async {
  final scratch = await Directory.systemTemp.createTemp('deploy-order-');
  addTearDown(() => scratch.delete(recursive: true));
  final origin = await Directory('${scratch.path}/origin').create();
  final work = '${scratch.path}/work';
  Future<String> git(List<String> args, {String? cwd}) async {
    final result = await Process.run(
      'git',
      args,
      workingDirectory: cwd ?? origin.path,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return '${result.stdout}'.trim();
  }

  await git(['init', '-q', '-b', 'main']);
  await git(['config', 'user.name', 'Test']);
  await git(['config', 'user.email', 'test@example.invalid']);
  final input = File('${origin.path}/lib/llamadart.dart');
  await input.parent.create();
  await input.writeAsString('older');
  await git(['add', '.']);
  await git(['commit', '-qm', 'older']);
  final older = await git(['rev-parse', 'HEAD']);
  await git(['clone', '-q', '--depth=1', origin.uri.toString(), work]);
  await input.writeAsString('newer');
  await git(['commit', '-qam', 'newer']);
  final newer = await git(['rev-parse', 'HEAD']);
  final verdicts = <String, bool>{};
  for (final entry in {'newer': newer, 'older': older}.entries) {
    final output = File('${scratch.path}/${entry.key}.output');
    final environment = {...Platform.environment}..remove('GH_TOKEN');
    environment.addAll({
      'DEPLOY_SHA': entry.value,
      'GITHUB_OUTPUT': output.path,
      'GITHUB_STEP_SUMMARY': '${scratch.path}/${entry.key}.summary',
    });
    final result = await Process.run(
      Platform.isWindows ? 'python' : 'python3',
      [File('tool/ci/deploy_guard.py').absolute.path, 'chat-app'],
      workingDirectory: work,
      environment: environment,
      includeParentEnvironment: false,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final value = (await output.readAsString()).replaceAll('\r\n', '\n');
    expect(value, entry.key == 'newer' ? 'deploy=true\n' : 'deploy=false\n');
    verdicts[entry.key] = value == 'deploy=true\n';
  }
  return verdicts;
}

/// The Linux VM shard command: coverage only when the selector asks for it.
const String linuxVmRun =
    'dart test -p vm -j 1 --exclude-tags local-only '
    r"${{ needs.changes.outputs.coverage == 'true' && '--coverage=coverage' || '' }} "
    '--file-reporter=json:.dart_tool/test_events.jsonl '
    r'${{ steps.shard.outputs.files }}';

void main() {
  test(
    'registered manual bootstrap calls the same-revision read-only qualifier',
    () {
      final ci = readWorkflow('ci');
      final jobs = ci['jobs'] as Map;
      final job = jobs['native-default-consumer-qualification'] as Map;
      expect(
        job['uses'],
        './.github/workflows/native_default_consumer_qualification.yml',
      );
      expect(job['permissions'], {'contents': 'read'});
      expect(job.containsKey('secrets'), isFalse);
      expect(job.containsKey('needs'), isFalse);
      expect(job.containsKey('steps'), isFalse);
      expect(job['with'], {
        'expected_sha': r'${{ inputs.native_default_expected_sha }}',
        'expected_native_tag':
            r'${{ inputs.native_default_expected_native_tag }}',
      });
      final qualifier = readWorkflow('native_default_consumer_qualification');
      expect(qualifier['on']['workflow_call'], {
        'inputs': {
          'expected_sha': {'required': true, 'type': 'string'},
          'expected_native_tag': {'required': true, 'type': 'string'},
        },
      });
      expect(qualifier['concurrency'], {
        'group': r'native-default-aot-${{ github.run_id }}',
        'cancel-in-progress': false,
      });
      expect(ci['name'], 'CI');
      expect(
        ci['concurrency']['group'],
        r'${{ github.workflow }}-${{ github.event.pull_request.number || github.run_id }}',
      );
      // Called workflows retain caller context; distinct prefixes avoid a caller
      // cancelling its own child while both hold the same run ID.
      expect(qualifier['concurrency']['group'], isNot(startsWith('CI-')));
      expect(
        (jobs['test-linux-web']['needs'] as List),
        isNot(contains('native-default-consumer-qualification')),
      );
      final ordinary = jobs.keys.toSet().difference({
        'changes',
        'test-linux-web',
        'deploy-chat-app',
        'windows-registry-qualification',
        'native-default-consumer-qualification',
      });
      for (final name in ordinary) {
        final needs = jobs[name]['needs'];
        expect(
          needs is String ? [needs] : needs,
          contains('changes'),
          reason: '$name',
        );
        expect(
          jobs[name]['if'],
          contains('needs.changes.outputs.'),
          reason: '$name',
        );
        expect(jobs[name]['if'], isNot(contains('always()')), reason: '$name');
      }
    },
  );

  test(
    'manual default qualification skips normal fanout and all deploy routes',
    () async {
      final jobs = readWorkflow('ci')['jobs'] as Map;
      final result = await Process.run(
        Platform.isWindows ? 'python' : 'python3',
        [
          '-c',
          r"""
import itertools,json,sys
changes,aggregate,qualification,registry,deploy=json.loads(sys.argv[1])
for event,mode,oldflag,owner,attempt,cancel,good,main in itertools.product(('push','pull_request','workflow_dispatch'),(False,True),(False,True),(False,True),(1,2),(False,True),(False,True),(False,True)):
 values={'github.event_name':repr(event),'inputs.native_default_qualification':repr(mode),'inputs.windows_registry_qualification':repr(oldflag),'github.repository':repr('leehack/llamadart' if owner else 'elsewhere/fork'),'github.run_attempt':repr(attempt),'cancelled()':repr(cancel),'always()':'True','github.ref':repr('refs/heads/main' if main else 'refs/heads/reviewed'),'needs.test-linux-web.result':repr('success' if good else 'failure'),'needs.web-chat-contract.result':repr('success' if good else 'failure')}
 def run(expression):
  expression=expression.removeprefix('${{').removesuffix('}}').strip()
  for key,value in sorted(values.items(),key=lambda item:-len(item[0])): expression=expression.replace(key,value)
  return eval(expression.replace('&&',' and ').replace('||',' or ').replace('!=','@NE@').replace('!',' not ').replace('@NE@','!=').replace('true','True').replace('false','False').strip(),{'__builtins__':{}},{})
 assert run(changes)==(not mode)
 assert run(aggregate)==(not mode)
 assert run(qualification)==(event=='workflow_dispatch' and mode and owner and attempt==1)
 assert run(registry)==(event=='workflow_dispatch' and oldflag and not mode)
 assert run(deploy)==(not cancel and not oldflag and not mode and event in ('push','workflow_dispatch') and owner and main and good)
""",
          jsonEncode([
            jobs['changes']['if'],
            jobs['test-linux-web']['if'],
            jobs['native-default-consumer-qualification']['if'],
            jobs['windows-registry-qualification']['if'],
            jobs['deploy-chat-app']['if'],
          ]),
        ],
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );

  group('CI run retention', () {
    // Evaluate the workflow's small expression subset; unknown syntax fails
    // rather than silently testing a policy different from the YAML.
    Object evaluate(Object input, Map<String, Object?> github) {
      if (input is! String) return input;
      return input.replaceAllMapped(RegExp(r'\$\{\{(.*?)\}\}'), (match) {
        final expression = match[1]!.trim();
        if (expression.contains(' == ')) {
          final parts = expression.split(' == ');
          expect(parts, hasLength(2));
          expect(parts[1], matches(r"^'[^']*'$"));
          expect(github.containsKey(parts[0]), isTrue);
          return '${github[parts[0]] == parts[1].substring(1, parts[1].length - 1)}';
        }
        for (final operand in expression.split(' || ')) {
          expect(github.containsKey(operand), isTrue, reason: operand);
          final value = github[operand];
          if (value != null && value != false && value != '' && value != 0) {
            return '$value';
          }
        }
        return '';
      });
    }

    Map<String, String> arrivals(String event, {int? pr}) {
      final concurrency = readWorkflow('ci')['concurrency'] as Map;
      final groups = <String, String>{};
      final states = <String, String>{};
      for (final id in ['101', '102', '103']) {
        final github = <String, Object?>{
          'github.workflow': 'CI',
          'github.event_name': event,
          'github.event.pull_request.number': pr,
          'github.ref': 'refs/heads/main',
          'github.run_id': id,
        };
        final group = '${evaluate(concurrency['group'], github)}';
        final cancel = '${evaluate(concurrency['cancel-in-progress'], github)}';
        expect(cancel, anyOf('true', 'false'));
        // Actions allows one pending run per group even when running-run
        // cancellation is disabled. Model one occupied runner so 102 queues.
        for (final previous in groups.keys) {
          if (groups[previous] == group &&
              (states[previous] == 'pending' || cancel == 'true')) {
            states[previous] = 'cancelled';
          }
        }
        groups[id] = group;
        states[id] = states.containsValue('running') ? 'pending' : 'running';
        if (pr != null && id == '102') break;
      }
      if (pr != null) {
        expect(groups.values.toSet(), hasLength(1));
      } else {
        expect(
          groups.values.toSet(),
          hasLength(3),
          reason: 'Run states: $states',
        );
      }
      return states;
    }

    test('two pushes to one PR cancel the superseded run', () {
      expect(arrivals('pull_request', pr: 1646), {
        '101': 'cancelled',
        '102': 'running',
      });
    });

    for (final event in ['push', 'workflow_dispatch']) {
      test('three $event runs retain running and pending main checks', () {
        expect(arrivals(event), {
          '101': 'running',
          '102': 'pending',
          '103': 'pending',
        });
      });
    }
  });

  group('retained CI deployment ordering', () {
    Future<void> reverseValidationCompletion({
      required bool newerPending,
    }) async {
      final concurrency =
          readWorkflow('chat_app_hf_static_deploy')['concurrency'] as Map;
      expect(concurrency['group'], 'chat-app-hf-static-deploy');
      final cancel = concurrency['cancel-in-progress'] ?? false;
      final queue = concurrency['queue'] ?? 'single';
      expect(cancel, isA<bool>());
      expect(queue, anyOf('single', 'max'));
      final verdicts = await deploymentGuardVerdicts();
      final cancelled = <String>[];
      final pending = <String>[];
      final uploaded = <String>[];
      String? running;

      void arrive(String id) {
        if (running != null && cancel == true) {
          cancelled.add(running!);
          running = null;
        }
        // GitHub's default single-pending group replaces waiting work even
        // when running-work cancellation is disabled.
        if (queue == 'single') {
          cancelled.addAll(pending);
          pending.clear();
        }
        if (running == null) {
          running = id;
        } else {
          pending.add(id);
        }
      }

      if (newerPending) arrive('occupied');
      arrive('newer');
      // Older validation finishes last, after the newer deploy has entered
      // the shared group but before its upload has finished.
      arrive('older');
      while (running != null) {
        final id = running!;
        if (verdicts[id] == true) uploaded.add(id);
        running = pending.isEmpty ? null : pending.removeAt(0);
      }
      expect(
        cancelled,
        isEmpty,
        reason: 'Newest deploy must survive: $cancelled',
      );
      expect(uploaded, ['newer']);
    }

    test('stale validation cannot cancel a running newer deployment', () async {
      await reverseValidationCompletion(newerPending: false);
    });

    test(
      'stale validation cannot replace a pending newer deployment',
      () async {
        await reverseValidationCompletion(newerPending: true);
      },
    );
  });

  // A Windows runner's first Python launch has taken up to 54 s (later ones
  // well under 1 s). It runs here, outside the 30 s budget of whichever test
  // would otherwise pay it, in case this suite starts Python first.
  setUpAll(() async {
    final warmUp =
        await Process.run(Platform.isWindows ? 'python' : 'python3', [
          '-c',
          'import sys; sys.path.insert(0, "tool/ci"); '
              'import deploy_guard, select_jobs',
        ]).timeout(const Duration(minutes: 2));
    expect(warmUp.exitCode, 0, reason: '${warmUp.stderr}');
  });

  test(
    'production deployment consumes the gated same-run artifact without rebuild',
    () {
      final jobs = readWorkflow('ci')['jobs'] as Map;
      final deploy = jobs['deploy-chat-app'] as Map;
      expect(deploy['needs'], ['test-linux-web', 'web-chat-contract']);
      // GitHub's implicit success() includes skipped ancestors of the aggregate.
      // Explicit cancellation status lets direct successful needs decide eligibility.
      expect(
        deploy['if'],
        startsWith(
          '!cancelled() && inputs.windows_registry_qualification != true &&',
        ),
      );
      const mainOnly =
          "(github.event_name == 'push' || "
          "github.event_name == 'workflow_dispatch') && "
          "github.ref == 'refs/heads/main'";
      for (final guard in [
        mainOnly,
        "github.repository == 'leehack/llamadart'",
        "needs.test-linux-web.result == 'success'",
        "needs.web-chat-contract.result == 'success'",
      ]) {
        expect(deploy['if'], contains(guard));
      }
      expect(
        deploy['with']['artifact_id'],
        r'${{ needs.web-chat-contract.outputs.artifact-id }}',
      );
      expect(
        deploy['with']['artifact_digest'],
        r'${{ needs.web-chat-contract.outputs.artifact-digest }}',
      );
      final steps = jobs['web-chat-contract']['steps'] as List;
      final smoke = steps.indexWhere(
        (step) => '${step['run']}'.contains(
          '--scenario chat-app-web-production-smoke',
        ),
      );
      final upload = steps.indexWhere(
        (step) => step['id'] == 'production-artifact',
      );
      expect(smoke, greaterThanOrEqualTo(0));
      expect(upload, greaterThan(smoke));
      expect(steps[upload]['if'], mainOnly);
      final workflow = readWorkflow('chat_app_hf_static_deploy');
      expect((workflow['on'] as Map).keys, ['workflow_call']);
      final callee = workflow['jobs']['deploy'];
      expect(
        callee['if'],
        "$mainOnly && github.repository == 'leehack/llamadart'",
      );
      final text = jsonEncode(callee);
      expect(text, contains('web_deployment.py verify'));
      expectGuardedUpload(callee as Map<String, dynamic>, 'chat-app');
      expect(text, isNot(contains('build_chat_app_web.sh')));
      expect(text, isNot(contains('flutter-action')));
    },
  );

  test(
    'Laya Tetris deploys only tested main commits of this repository',
    () async {
      final workflow = readWorkflow('laya_tetris_hf_static_deploy');
      final trigger = workflow['on'] as Map;
      expect(trigger.keys, unorderedEquals(['push', 'workflow_dispatch']));
      expect(trigger['push']['branches'], ['main']);
      final guardInputs = await Process.run(
        Platform.isWindows ? 'python' : 'python3',
        [
          '-c',
          'import json,sys; sys.path.insert(0, "tool/ci"); import deploy_guard; '
              'print(json.dumps(deploy_guard.LAYA_TETRIS_INPUTS))',
        ],
      );
      expect(guardInputs.exitCode, 0, reason: '${guardInputs.stderr}');
      // A commit outside these paths starts no deploy, so the guard must not
      // let it supersede one either.
      expect(
        trigger['push']['paths'],
        jsonDecode(guardInputs.stdout as String),
      );
      expect(workflow['permissions'], {'contents': 'read'});
      final deploy = workflow['jobs']['deploy'] as Map<String, dynamic>;
      expect(
        deploy['if'],
        "github.ref == 'refs/heads/main' && "
        "github.repository == 'leehack/llamadart'",
      );
      expect(deploy.containsKey('continue-on-error'), isFalse);
      final steps = deploy['steps'] as List;
      expectGuardedUpload(deploy, 'laya-tetris');
      final tests = steps.indexWhere(
        (step) => '${step['run']}'.contains('flutter test'),
      );
      final secretSteps = [
        for (var i = 0; i < steps.length; i++)
          if (jsonEncode(steps[i]).contains('secrets.')) i,
      ];
      expect(tests, greaterThanOrEqualTo(0));
      expect(secretSteps, hasLength(1));
      expect(secretSteps.single, greaterThan(tests));
      int secretReferences(Object? value) =>
          'secrets.'.allMatches(jsonEncode(value)).length;
      expect(
        secretReferences(workflow),
        secretReferences(steps[secretSteps.single]),
      );
      expect('${steps[secretSteps.single]['run']}', contains('--public'));
    },
  );

  test(
    'preview selection precedes SDK and secrets while close cleanup is unfiltered',
    () {
      final workflow = readWorkflow('chat_app_hf_pr_preview');
      final trigger = workflow['on']['pull_request'] as Map;
      expect(trigger.containsKey('paths'), isFalse);
      expect(
        trigger['types'],
        containsAll(['closed', 'ready_for_review', 'labeled', 'unlabeled']),
      );
      final build = workflow['jobs']['build'];
      expect(build['permissions'], {'contents': 'read'});
      expect(build['timeout-minutes'], 45);
      expect(jsonEncode(build), isNot(contains('secrets.')));
      final steps = build['steps'] as List;
      expect(steps.first['if'], "github.event.action == 'closed'");
      expect(steps.first['run'], contains('action=cleanup'));
      final select = steps.indexWhere((step) => step['id'] == 'select');
      final sdk = steps.indexWhere(
        (step) => '${step['uses']}'.contains('flutter-action'),
      );
      expect(select, lessThan(sdk));
      expect(steps[sdk]['if'], "steps.select.outputs.action == 'build'");
      final deploy = workflow['jobs']['preview'];
      expect(deploy['needs'], 'build');
      expect(deploy['if'], contains("needs.build.result == 'success'"));
      expect(deploy['env'].containsKey('HF_TOKEN'), isFalse);
      final checkout = (deploy['steps'] as List).singleWhere(
        (step) => '${step['uses']}'.contains('checkout@'),
      );
      expect(
        checkout['with']['ref'],
        r'${{ github.event.pull_request.base.sha }}',
      );
      expect(checkout.containsKey('if'), isFalse);
      expect(workflow.containsKey('concurrency'), isFalse);
      expect(build['if'], contains("github.event.label.name == 'preview'"));
      expect(deploy['concurrency']['cancel-in-progress'], isFalse);
      expect(deploy['concurrency']['queue'], 'max');
      expect(deploy['concurrency']['group'], contains('pull_request.number'));
      expect(deploy['permissions']['actions'], 'read');
      expect(deploy['permissions']['pull-requests'], 'write');
      final operation = (deploy['steps'] as List).singleWhere(
        (step) => '${step['run']}'.contains('preview_guard.py'),
      );
      expect(operation['env']['HF_TOKEN'], contains('secrets.HF_TOKEN'));
      expect(operation['env']['GH_TOKEN'], contains('github.token'));
      expect(deploy['env']['ARTIFACT_DIGEST'], contains('artifact-digest'));
      expect(jsonEncode(deploy), isNot(contains('download-artifact@')));
    },
  );

  test('model-store lane checks the package on its own selection', () async {
    final plan = await selected([
      'packages/llamadart_model_store/lib/src/model_store_io.dart',
    ]);
    expect(
      (plan['jobs'] as Map).entries
          .where((e) => e.value == true)
          .map((e) => e.key),
      ['model-store'],
    );

    final job = readWorkflow('ci')['jobs']['model-store'] as Map;
    final steps = (job['steps'] as List).cast<Map>();
    Map step(String name) => steps.singleWhere((s) => s['name'] == name);
    final checks = step('Analyze and test on VM');
    expect(checks['working-directory'], 'packages/llamadart_model_store');
    for (final command in [
      'dart format --output=none --set-exit-if-changed .',
      'flutter analyze --fatal-infos',
      'TMPDIR="\$(mktemp -d)" flutter test',
    ]) {
      expect(
        (checks['run'] as String).split('\n'),
        contains(command),
        reason: command,
      );
    }
    final chrome = step('Test on Chrome with bounded shutdown diagnostics');
    expect(chrome['working-directory'], 'packages/llamadart_model_store');
    expect(chrome.containsKey('continue-on-error'), isFalse);
    expect(
      chrome['run'],
      allOf(
        contains('python3 ../../tool/ci/supervise_chrome_test.py'),
        contains('--timeout-seconds 180 --'),
        contains('dart test -p chrome test/model_store_web_test.dart'),
      ),
    );
    final diagnostics = step('Upload Chrome process and phase diagnostics');
    expect(diagnostics['if'], 'always()');
    expect(diagnostics['uses'], 'actions/upload-artifact@v7');
    expect(steps.indexOf(diagnostics), steps.indexOf(chrome) + 1);
    final unchanged = step('Check the lane leaves the package unchanged');
    expect(unchanged.containsKey('if'), isFalse);
    expect(unchanged['working-directory'], 'packages/llamadart_model_store');
    expect(
      unchanged['run'],
      allOf(
        contains('git status --porcelain --untracked-files=all -- .'),
        contains('exit 1'),
      ),
    );
    expect(steps.where((s) => s.containsKey('if')), [diagnostics]);
  });

  test('dependabot updates every independently resolved package', () {
    final config =
        loadYaml(File('.github/dependabot.yml').readAsStringSync()) as Map;
    final pubDirectories = [
      for (final update in config['updates'] as List)
        if (update['package-ecosystem'] == 'pub') update['directory'] as String,
    ];
    for (final directory in pubDirectories) {
      expect(
        File('.$directory/pubspec.yaml'.replaceAll('//', '/')).existsSync(),
        isTrue,
        reason: directory,
      );
    }
    expect(pubDirectories, contains('/packages/llamadart_model_store'));
  });

  test(
    'core workflow wires every planned job into truthful always aggregate',
    () async {
      final workflow = readWorkflow('ci');
      final jobs = workflow['jobs'] as Map<String, dynamic>;
      final plan = await selected(['lib/llamadart.dart']);
      final planned = (plan['jobs'] as Map).keys.toSet();
      final shards = await shardJobs();
      expect(shards, {'test-linux-vm': 'test-linux-coverage'});
      expect(jobs.keys.toSet(), {
        ...planned,
        ...shards.keys,
        'changes',
        'test-linux-web',
        'deploy-chat-app',
        'windows-registry-qualification',
        'native-default-consumer-qualification',
      });
      final aggregate = jobs['test-linux-web'] as Map;
      expect(
        aggregate['if'],
        r'${{ always() && inputs.native_default_qualification != true }}',
      );
      expect((aggregate['needs'] as List).toSet(), {
        ...planned,
        ...shards.keys,
        'changes',
      });
      final steps = aggregate['steps'] as List;
      final check = steps.last as Map;
      expect(check['run'], 'python3 tool/ci/select_jobs.py aggregate');
      expect(check['env'], {
        'PLAN': r'${{ needs.changes.outputs.plan }}',
        'NEEDS': r'${{ toJSON(needs) }}',
      });
      final consumers = {for (final e in shards.entries) e.value: e.key};
      // The companion job hosts other macOS steps; see the test of its wiring.
      for (final name in planned.difference({'companion-packages'})) {
        final shard = consumers[name];
        // A consumer waits for its shards, so it is skipped when one fails.
        expect(
          jobs[name]['needs'],
          shard == null ? 'changes' : ['changes', shard],
          reason: '$name',
        );
        expect(
          jobs[name]['if'],
          shard == null
              ? "needs.changes.outputs.$name == 'true'"
              // Merging shard coverage runs after merge only.
              : "needs.changes.outputs.$name == 'true' && "
                    "needs.changes.outputs.coverage == 'true'",
          reason: '$name',
        );
        expect(
          jobs['changes']['outputs'][name],
          '\${{ steps.select.outputs.$name }}',
        );
      }
      for (final MapEntry(key: shard, value: consumer) in shards.entries) {
        expect(jobs[shard]['needs'], 'changes', reason: shard);
        expect(
          jobs[shard]['if'],
          "needs.changes.outputs.$consumer == 'true'",
          reason: shard,
        );
        expect(jobs[shard]['strategy']['fail-fast'], isFalse, reason: shard);
      }
      final triggers = workflow['on'] as Map;
      expect(triggers.keys.toSet(), {
        'push',
        'pull_request',
        'workflow_dispatch',
      });
      // Manual inputs bind source identity; they cannot supply commands,
      // model URLs, a different checkout ref or deploy artifacts.
      expect(triggers['workflow_dispatch']['inputs'], {
        'windows_registry_qualification': {
          'description':
              'Run the pinned Windows CPU registry qualification separately',
          'type': 'boolean',
          'required': false,
          'default': false,
        },
        'native_default_qualification': {
          'description':
              'Run only default native consumer and AOT qualification',
          'type': 'boolean',
          'required': false,
          'default': false,
        },
        'native_default_expected_sha': {
          'description':
              'Reviewed selected branch commit for default consumer qualification',
          'type': 'string',
          'required': false,
          'default': '',
        },
        'native_default_expected_native_tag': {
          'description':
              'Verify checked-in v0.8.0-2, v0.8.0-3 or v0.9.0 pin; never override it',
          'type': 'string',
          'required': false,
          'default': '',
        },
      });
      for (final name in ['push', 'pull_request']) {
        final trigger = triggers[name] as Map;
        expect(trigger.containsKey('paths'), isFalse);
        expect(trigger.containsKey('paths-ignore'), isFalse);
      }
    },
  );

  test(
    'qualification flag causally gates manual execution and deployment',
    () async {
      final jobs = readWorkflow('ci')['jobs'] as Map;
      final result = await Process.run(
        Platform.isWindows ? 'python' : 'python3',
        [
          '-c',
          r"""
import itertools,json,sys
qualification,deploy=json.loads(sys.argv[1])
for event,flag,native,cancel,good,main in itertools.product(('push','pull_request','workflow_dispatch'),(False,True),(False,True),(False,True),(False,True),(False,True)):
 values={'github.event_name':repr(event),'inputs.windows_registry_qualification':repr(flag),'inputs.native_default_qualification':repr(native),'cancelled()':repr(cancel),'github.ref':repr('refs/heads/main' if main else 'refs/heads/test'),'github.repository':repr('leehack/llamadart'),'needs.test-linux-web.result':repr('success' if good else 'failure'),'needs.web-chat-contract.result':repr('success' if good else 'failure')}
 def run(expression):
  for key,value in values.items(): expression=expression.replace(key,value)
  return eval(expression.replace('&&',' and ').replace('||',' or ').replace('!=','@NE@').replace('!',' not ').replace('@NE@','!=').replace('true','True').replace('false','False').strip(),{'__builtins__':{}},{})
 assert run(qualification)==(event=='workflow_dispatch' and flag and not native)
 assert run(deploy)==(not cancel and not flag and not native and event in ('push','workflow_dispatch') and main and good)
""",
          jsonEncode([
            jobs['windows-registry-qualification']['if'],
            jobs['deploy-chat-app']['if'],
          ]),
        ],
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );

  test('manual qualification is bounded and outside required aggregate', () {
    final jobs = readWorkflow('ci')['jobs'] as Map;
    final job = jobs['windows-registry-qualification'] as Map;
    expect(
      job['if'],
      "github.event_name == 'workflow_dispatch' && inputs.windows_registry_qualification == true && inputs.native_default_qualification != true",
    );
    expect(job['runs-on'], 'windows-2022');
    expect(job['permissions'], {'contents': 'read'});
    expect(job['timeout-minutes'], 75);
    expect(job.containsKey('needs'), isFalse);
    expect(job.containsKey('secrets'), isFalse);
    final steps = (job['steps'] as List).cast<Map>();
    expect(steps.first['with'], {
      'ref': r'${{ github.sha }}',
      'fetch-depth': 0,
      'persist-credentials': false,
    });
    expect(steps.any((s) => s.containsKey('continue-on-error')), isFalse);
    final upload = steps.singleWhere(
      (s) => s['uses'] == 'actions/upload-artifact@v7',
    );
    expect(upload['if'], r'${{ always() }}');
    expect(upload['with']['overwrite'], isFalse);
    expect(upload['with']['retention-days'], 1);
    expect(upload['with']['if-no-files-found'], 'error');
    expect(
      upload['with']['name'],
      r'windows-registry-${{ github.sha }}-${{ github.run_id }}-${{ github.run_attempt }}',
    );
    expect(jsonEncode(job), isNot(contains('secrets.')));
    expect(
      (jobs['test-linux-web']['needs'] as List),
      isNot(contains('windows-registry-qualification')),
    );
  });

  test('qualification evidence uses runner context only in supported steps', () {
    final job =
        readWorkflow('ci')['jobs']['windows-registry-qualification'] as Map;
    const root =
        r'${{ runner.temp }}/windows-registry-${{ github.run_id }}-${{ github.run_attempt }}';
    void lint(Map candidate) {
      // GitHub rejects runner in jobs.<job>.env before creating a run.
      if (jsonEncode(candidate['env']).contains('runner.')) {
        throw FormatException('runner context is unavailable in job env');
      }
      final steps = (candidate['steps'] as List).cast<Map>();
      for (final name in [
        'Prepare pinned qualification SDK',
        'List, inspect and execute the durable scenario',
        'Seal all qualification evidence',
      ]) {
        final step = steps.singleWhere((step) => step['name'] == name);
        if (step['env']?['LLAMADART_WINDOWS_QUALIFICATION'] != root) {
          throw FormatException('execution/sealing evidence root differs');
        }
      }
      final upload = steps.singleWhere(
        (step) => step['id'] == 'qualification-artifact',
      );
      if (upload['with']['path'] != '$root/evidence.zip') {
        throw FormatException('upload evidence root differs');
      }
    }

    lint(job);
    final invalidJob = Map.of(job)
      ..['env'] = {'LLAMADART_WINDOWS_QUALIFICATION': root};
    expect(() => lint(invalidJob), throwsFormatException);
    final invalidPath = jsonDecode(jsonEncode(job)) as Map;
    (invalidPath['steps'] as List).singleWhere(
      (step) => step['id'] == 'qualification-artifact',
    )['with']['path'] = 'evidence.zip';
    expect(() => lint(invalidPath), throwsFormatException);
  });

  test('one macOS job runs each selected companion and hosted check', () async {
    final jobs = readWorkflow('ci')['jobs'] as Map<String, dynamic>;
    final job = jobs['companion-packages'] as Map;
    expect(job['runs-on'], 'macos-latest');
    expect(job['if'], "needs.changes.outputs.companion-job == 'true'");
    expect(job.containsKey('strategy'), isFalse);
    expect(
      jobs['changes']['outputs']['companion-job'],
      r'${{ steps.select.outputs.companion-job }}',
    );
    final steps = (job['steps'] as List).cast<Map>();
    final companions = Directory('packages')
        .listSync()
        .whereType<Directory>()
        .where(
          (package) => File(
            '${package.path}/darwin/${package.path.split(Platform.pathSeparator).last}/Package.swift',
          ).existsSync(),
        )
        .map(
          (package) =>
              'packages/${package.path.split(Platform.pathSeparator).last}',
        )
        .toSet();
    final packageSteps = steps
        .where((s) => s['uses'] == './.github/actions/companion-package')
        .toList();
    expect(packageSteps.map((s) => s['with']['package']).toSet(), companions);
    expect(packageSteps, hasLength(companions.length));
    for (final step in packageSteps) {
      final package = step['with']['package'];
      expect(
        step['if'],
        "\${{ !cancelled() && contains(fromJSON(needs.changes.outputs.companions), '$package') }}",
      );
      expect(step.containsKey('continue-on-error'), isFalse);
    }
    final memory = steps.singleWhere(
      (s) => s['name'] == 'Test validation process memory',
    );
    expect(memory['working-directory'], 'packages/llamadart_validation');
    expect(
      '${memory['run']}',
      contains('dart test test/process_memory_test.dart'),
    );
    expect(
      memory['if'],
      "\${{ !cancelled() && needs.changes.outputs.validation-harness == 'true' }}",
    );
    final cache = steps.singleWhere(
      (s) => s['name'] == 'Verify Flutter Apple companion cache transitions',
    );
    expect(
      cache['if'],
      "\${{ !cancelled() && needs.changes.outputs.test-other-os == 'true' }}",
    );
  });

  test(
    'companion action runs every check and fails the lane on any of them',
    () {
      final action =
          jsonDecode(
                jsonEncode(
                  loadYaml(
                    File(
                      '.github/actions/companion-package/action.yml',
                    ).readAsStringSync(),
                  ),
                ),
              )
              as Map<String, dynamic>;
      final steps = (action['runs']['steps'] as List).cast<Map>();
      String run(String name) =>
          '${steps.singleWhere((s) => s['name'] == name)['run']}';
      expect(run('Install dependencies'), 'flutter pub get');
      expect(
        run('Check formatting'),
        'dart format --output=none --set-exit-if-changed .',
      );
      expect(run('Analyze'), 'flutter analyze');
      expect(run('Test'), 'flutter test');
      expect(run('Validate SwiftPM manifest'), contains('dump-package'));
      expect(
        run('Resolve SwiftPM binary targets'),
        allOf(contains('swift package'), contains(' resolve')),
      );
      expect(
        run('Check the lane leaves the package unchanged'),
        allOf(contains('git status --porcelain'), contains('exit 1')),
      );
      expect(run('Publish dry-run'), contains('flutter pub publish --dry-run'));
      for (final step in steps) {
        expect(step.containsKey('continue-on-error'), isFalse, reason: '$step');
        expect('${step['run']}', isNot(contains('|| true')), reason: '$step');
      }
    },
  );

  group('CI cannot mask a failure', () {
    final masksExit = RegExp(r'\|\|\s*(true|exit\s+0|:)\b|;\s*true\b');
    final neverRuns = {'false', '0', ''};

    Map<String, dynamic> job(String name) {
      final jobs = readWorkflow('ci')['jobs'] as Map<String, dynamic>;
      return jobs[name] as Map<String, dynamic>;
    }

    List<Map> stepsOf(String name) => (job(name)['steps'] as List).cast<Map>();

    List<Map> actionSteps() {
      final steps = <Map>[];
      for (final action in Directory('.github/actions').listSync()) {
        if (action is! Directory) continue;
        final manifest =
            jsonDecode(
                  jsonEncode(
                    loadYaml(
                      File('${action.path}/action.yml').readAsStringSync(),
                    ),
                  ),
                )
                as Map<String, dynamic>;
        steps.addAll(((manifest['runs'] as Map)['steps'] as List).cast<Map>());
      }
      return steps;
    }

    List<Map> allSteps() => [
      for (final entry in (readWorkflow('ci')['jobs'] as Map).entries)
        for (final step in (entry.value['steps'] as List? ?? const []))
          step as Map,
      ...actionSteps(),
    ];

    bool neverRunsStep(Map step) =>
        step.containsKey('if') &&
        neverRuns.contains(
          '${step['if']}'
              .replaceAll(RegExp(r'^\$\{\{|\}\}$'), '')
              .trim()
              .toLowerCase(),
        );

    test('no job continues past a failed step', () {
      final jobs = readWorkflow('ci')['jobs'] as Map<String, dynamic>;
      for (final name in const [
        'companion-packages',
        'test-other-os',
        'genkit',
      ]) {
        expect(jobs, contains(name));
      }
      jobs.forEach((name, job) {
        final continues = (job as Map)['continue-on-error'];
        expect(continues, anyOf(isNull, isFalse), reason: name);
      });
    });

    test('no step in a job or action is switched off', () {
      expect(actionSteps(), isNotEmpty);
      expect(allSteps().where(neverRunsStep), isEmpty);
    });

    test('the Genkit analysis and the dependency and publish checks run', () {
      final genkit = stepsOf('genkit');
      final checked = [
        ...genkit.where(
          (step) => '${step['run']}'.contains('dart analyze --fatal-infos'),
        ),
        genkit.singleWhere(
          (step) => step['name'] == 'Resolve independent minimum dependencies',
        ),
        genkit.singleWhere(
          (step) => '${step['run']}'.contains('dart pub publish --dry-run'),
        ),
        stepsOf(
          'model-store',
        ).singleWhere((step) => step['name'] == 'Publish dry-run'),
      ];
      expect(checked.length, greaterThanOrEqualTo(4));
      for (final step in checked) {
        expect(neverRunsStep(step), isFalse, reason: '$step');
        expect(step.containsKey('continue-on-error'), isFalse);
        expect(masksExit.hasMatch('${step['run']}'), isFalse, reason: '$step');
      }
    });

    test('no run script discards a failing exit status', () {
      for (final step in allSteps()) {
        expect(masksExit.hasMatch('${step['run']}'), isFalse, reason: '$step');
      }
    });

    test('the masking checks catch what they look for', () {
      expect(masksExit.hasMatch('dart analyze || exit 0'), isTrue);
      expect(masksExit.hasMatch('dart pub get || true'), isTrue);
      expect(masksExit.hasMatch('dart pub get; true'), isTrue);
      expect(masksExit.hasMatch('if [ -n "\$x" ]; then exit 1; fi'), isFalse);
      expect(neverRunsStep({'if': false}), isTrue);
      expect(neverRunsStep({'if': r'${{ false }}'}), isTrue);
      expect(neverRunsStep({'if': r'${{ !cancelled() }}'}), isFalse);
    });
  });

  test('macOS and Windows memory and cache steps cannot mask a failure', () {
    final jobs = readWorkflow('ci')['jobs'] as Map<String, dynamic>;
    final macos = (jobs['companion-packages']['steps'] as List).cast<Map>();
    final windows = (jobs['test-other-os']['steps'] as List).cast<Map>();
    final checked = [
      macos.singleWhere((s) => s['name'] == 'Test validation process memory'),
      macos.singleWhere(
        (s) => s['name'] == 'Verify Flutter Apple companion cache transitions',
      ),
      ...windows.where(
        (s) =>
            s['name'] == 'Test validation process memory' ||
            s['name'] == 'Install validation harness dependencies' ||
            s['name'] == 'Verify Flutter Apple companion cache transitions',
      ),
    ];
    expect(checked, hasLength(4));
    for (final step in checked) {
      expect(step.containsKey('continue-on-error'), isFalse, reason: '$step');
      expect('${step['run']}', isNot(contains('|| true')), reason: '$step');
    }
    expect(
      '${macos.singleWhere((s) => s['name'] == 'Test validation process memory')['run']}',
      contains('dart test test/process_memory_test.dart'),
    );
  });

  test(
    'Genkit lower bounds pin dependencies, test them and restore the tree',
    () {
      final jobs = readWorkflow('ci')['jobs'] as Map<String, dynamic>;
      final steps = (jobs['genkit']['steps'] as List).cast<Map>();
      final resolve = steps.singleWhere(
        (s) => s['name'] == 'Resolve independent minimum dependencies',
      );
      final analyze = steps.singleWhere(
        (s) => s['name'] == 'Analyze and test minimum dependencies',
      );
      final restore = steps.singleWhere(
        (s) =>
            s['name'] ==
            'Restore the package after the minimum dependency check',
      );
      expect(
        '${resolve['run']}',
        allOf(
          contains('dart pub add '),
          contains('crypto@3.0.7'),
          contains('genkit@1.0.0'),
          contains('http@1.6.0'),
          contains('llamadart@0.19.0'),
          contains('schemantic@1.0.0'),
        ),
      );
      expect(
        '${analyze['run']}',
        allOf(
          contains('dart analyze --fatal-infos'),
          contains('dart test -x real-model'),
        ),
      );
      expect(
        '${restore['run']}',
        allOf(
          contains('git restore -- packages/genkit_llamadart'),
          contains('git clean -fdxq -- packages/genkit_llamadart'),
        ),
      );
      for (final step in [resolve, analyze, restore]) {
        expect(step.containsKey('continue-on-error'), isFalse, reason: '$step');
        expect('${step['run']}', isNot(contains('|| true')), reason: '$step');
      }
    },
  );

  test('selector exposes the companion job and validation harness OS', () {
    final outputs = readWorkflow('ci')['jobs']['changes']['outputs'] as Map;
    expect(
      outputs['companion-job'],
      r'${{ steps.select.outputs.companion-job }}',
    );
    expect(
      outputs['validation-harness-os'],
      r'${{ steps.select.outputs.validation-harness-os }}',
    );
    expect(outputs.containsKey('genkit-lower-bounds'), isFalse);
  });

  test('Windows runs the validation process memory test in exactly one job', () {
    final jobs = readWorkflow('ci')['jobs'] as Map<String, dynamic>;
    final harness = jobs['validation-harness'] as Map;
    expect(
      harness['strategy']['matrix']['os'],
      r'${{ fromJSON(needs.changes.outputs.validation-harness-os) }}',
    );
    expect(harness['strategy']['fail-fast'], isFalse);
    expect(
      (harness['steps'] as List).map((s) => '${s['run']}'),
      contains(
        "dart test \${{ matrix.os == 'windows-latest' && 'test/process_memory_test.dart' || '' }}",
      ),
    );
    final native = (jobs['test-other-os']['steps'] as List).cast<Map>();
    final memory = native.singleWhere(
      (s) => s['name'] == 'Test validation process memory',
    );
    expect(memory['run'], 'dart test test/process_memory_test.dart');
    const selected =
        "\${{ !cancelled() && matrix.lane == 'windows-runtime' && matrix.shard == 2 && needs.changes.outputs.validation-harness == 'true' }}";
    final legs =
        (jobs['test-other-os']['strategy']['matrix']['include'] as List)
            .cast<Map>();
    expect(
      legs.where(
        (leg) => leg['lane'] == 'windows-runtime' && leg['shard'] == 2,
      ),
      hasLength(1),
    );
    expect(
      legs.singleWhere(
        (leg) => leg['lane'] == 'windows-runtime' && leg['shard'] == 2,
      )['os'],
      'windows-latest',
    );
    expect(memory['if'], selected);
    // PowerShell keeps only the last command's exit code, so this is a step.
    final install = native[native.indexOf(memory) - 1];
    expect(install['run'], 'dart pub get');
    expect(install['if'], selected);
  });

  test('Genkit lower bounds run on a fresh tree before Flutter is set up', () {
    final jobs = readWorkflow('ci')['jobs'] as Map<String, dynamic>;
    expect(jobs.containsKey('genkit-lower-bounds'), isFalse);
    final steps = (jobs['genkit']['steps'] as List).cast<Map>();
    int usesIndex(String action) =>
        steps.indexWhere((s) => '${s['uses']}'.startsWith(action));
    final dartSdk = usesIndex('dart-lang/setup-dart');
    final flutterSdk = usesIndex('subosito/flutter-action');
    final analyze = steps.indexWhere(
      (s) => s['name'] == 'Analyze and test minimum dependencies',
    );
    final restore = steps.indexWhere(
      (s) =>
          s['name'] == 'Restore the package after the minimum dependency check',
    );
    expect(steps[dartSdk]['with']['sdk'], '3.12.0');
    expect(dartSdk, lessThan(analyze));
    expect(analyze, lessThan(restore));
    expect(restore, lessThan(flutterSdk));
    expect('${steps[restore]['run']}', contains('git clean -fdxq'));
    const published = 'lower bounds and published';
    const localCore = 'local core';
    expect(jobs['genkit']['strategy'], {
      'fail-fast': false,
      'matrix': {
        'part': [published, localCore],
      },
    });
    // A lower-bound failure must not hide later checks of the same leg.
    for (final step in steps.skip(restore)) {
      expect(
        step['if'],
        anyOf(
          r'${{ !cancelled() }}',
          "\${{ !cancelled() && matrix.part == '$published' }}",
          "\${{ !cancelled() && matrix.part == '$localCore' }}",
          "\${{ always() && matrix.part == '$localCore' }}",
        ),
        reason: '$step',
      );
    }
    final legs = {
      for (final part in [published, localCore])
        part: [
          for (final step in steps)
            if (!'${step['if'] ?? ''}'.contains('matrix.part') ||
                '${step['if']}'.contains("'$part'"))
              step['name'] ?? step['uses'],
        ],
    };
    expect(
      legs[published],
      containsAll([
        'Resolve independent minimum dependencies',
        'Analyze and test minimum dependencies',
        'Verify published dependencies, docs and archive',
        'Verify standalone adapter archive and score',
      ]),
    );
    expect(
      legs[localCore],
      containsAll([
        'Test adapter against checkout core',
        'Run existing native real-model contracts',
        'Verify browser contracts against checkout core',
        'Remove local override',
      ]),
    );
    expect(
      legs[localCore],
      isNot(contains(startsWith('dart-lang/setup-dart'))),
    );
  });

  test(
    'bundles cover runtime inputs with target-aware matrices and final result',
    () async {
      final workflow = readWorkflow('validation_bundles');
      final jobs = workflow['jobs'] as Map;
      expect(jobs.keys.toSet(), {'changes', 'desktop', 'app', 'result'});
      expect(
        jobs['desktop']['if'],
        "needs.changes.outputs.desktops-enabled == 'true'",
      );
      expect(
        jobs['desktop']['strategy']['matrix']['os'],
        r'${{ fromJSON(needs.changes.outputs.desktops) }}',
      );
      expect(jobs['app']['if'], "needs.changes.outputs.apps-enabled == 'true'");
      expect(
        jobs['app']['strategy']['matrix']['target'],
        r'${{ fromJSON(needs.changes.outputs.apps) }}',
      );
      expect(jobs['result']['if'], r'${{ always() }}');
      expect((jobs['result']['needs'] as List).toSet(), {
        'changes',
        'desktop',
        'app',
      });
      expect(
        (jobs['result']['steps'] as List).last['run'],
        'python3 tool/ci/select_jobs.py aggregate --bundle',
      );
      expect(
        (workflow['on']['pull_request'] as Map).containsKey('paths'),
        isFalse,
      );
      // Main builds every target its push selects, including the macOS
      // desktop and Android builds a PR defers when it leaves their inputs.
      expect(workflow['on']['push'], {
        'branches': ['main'],
      });
      expect(
        workflow['concurrency']['cancel-in-progress'],
        r"${{ github.event_name == 'pull_request' }}",
      );
      expect(workflow['concurrency']['group'], contains('github.run_id'));
      expect((await selected(['hook/build.dart']))['desktops'], hasLength(3));
      expect(
        (await selected([
          'packages/llamadart_validation/assets/profiles/chat-gguf-cpu.json',
        ]))['desktops'],
        isEmpty,
      );
    },
  );

  test('selection uses complete checkout and safe event metadata boundary', () {
    for (final name in ['ci', 'validation_bundles']) {
      final job = readWorkflow(name)['jobs']['changes'];
      final checkout = (job['steps'] as List).first;
      expect(checkout['with']['fetch-depth'], 0);
      expect(checkout['with']['persist-credentials'], isFalse);
      final select = (job['steps'] as List).singleWhere(
        (step) => step['id'] == 'select',
      );
      expect(select['run'], 'python3 tool/ci/select_jobs.py select');
      expect(select['run'], isNot(contains('github.event')));
    }
  });

  test(
    'pinned tooling docs and chat-app VM tests select their gates',
    () async {
      Future<Set<String>> enabled(String path) async {
        final jobs = (await selected([path]))['jobs'] as Map;
        return {
          for (final entry in jobs.entries)
            if (entry.value == true) entry.key as String,
        };
      }

      for (final path in [
        'AGENTS.md',
        'CONTRIBUTING.md',
        'doc/testing_matrix.md',
        'README.md',
        'website/docs/guides/embeddings.md',
        'packages/llamadart_stable_diffusion_flutter/README.md',
        'example/chat_app/README.md',
      ]) {
        expect(await enabled(path), {
          'docs-check',
          'docs-versions',
          'markdown-tests',
        }, reason: path);
      }
      expect(
        await enabled('example/chat_app/test_vm/chat_settings_test.dart'),
        {'analyze', 'web-chat-contract'},
      );
    },
  );

  test(
    'Markdown reader helper changes select the guard without full coverage',
    () async {
      for (final path in [
        'tool/docs/build_site.sh',
        'tool/docs/new_reader.dart',
        'tool/testing/validation/remote.dart',
        'tool/testing/validation.dart',
      ]) {
        final jobs = (await selected([path]))['jobs'] as Map;
        expect(jobs['markdown-tests'], isTrue, reason: path);
        for (final job in [
          'test-linux-coverage',
          'test-web',
          'test-other-os',
        ]) {
          expect(jobs[job], isFalse, reason: '$path: $job');
        }
      }
    },
  );

  test(
    'capability registry changes select an unconditional inventory gate',
    () async {
      final jobs = readWorkflow('ci')['jobs'] as Map;
      for (final path in [
        'packages/llamadart_validation/assets/capability_coverage.json',
        'packages/llamadart_validation/lib/src/case_catalog.dart',
        'lib/src/core/engine/engine.dart',
      ]) {
        expect(
          (await selected([path]))['jobs']['analyze'],
          isTrue,
          reason: path,
        );
      }
      final gate =
          (jobs['analyze']['steps'] as List).singleWhere(
                (step) =>
                    step['name'] ==
                    'Verify public capability validation coverage',
              )
              as Map;
      expect(
        gate['run'],
        'dart test -p vm test/unit/tooling/validation_coverage_test.dart',
      );
      expect(gate.containsKey('if'), isFalse);
      expect(gate.containsKey('continue-on-error'), isFalse);
      final archive =
          (jobs['analyze']['steps'] as List).singleWhere(
                (step) => step['name'] == 'Pub Publish Dry Run',
              )
              as Map;
      expect(archive['run'], 'python3 tool/release/check_core_archive.py');
      expect(archive.containsKey('if'), isFalse);
      expect(archive.containsKey('continue-on-error'), isFalse);
    },
  );

  test(
    'isolated validation keeps root and Flutter consumer assertions',
    () async {
      final jobs = readWorkflow('ci')['jobs'];
      final plan = await selected([
        'packages/llamadart_validation/lib/src/runner.dart',
      ]);
      expect(plan['jobs']['validation-integration'], isTrue);
      final runs = (jobs['validation-integration']['steps'] as List)
          .where((step) => step['run'] != null)
          .map((step) => step['run'] as String)
          .join('\n');
      for (final assertion in [
        'validation_remote_test.dart',
        'validation_image_profile_test.dart',
        'validation_npu_test.dart',
        'prepare_workspace_test.dart',
        'validation_controller_test.dart',
        'validation_app_test.dart',
      ]) {
        expect(runs, contains(assertion));
      }
    },
  );

  test(
    'full graph substitution executes both root and all Flutter consumers',
    () async {
      final jobs = readWorkflow('ci')['jobs'];
      final rootRun = (jobs['validation-integration']['steps'] as List)
          .singleWhere(
            (s) => '${s['run']}'.contains('validation_remote_test.dart'),
          );
      expect(
        rootRun['if'],
        "needs.changes.outputs.test-linux-coverage != 'true'",
      );
      final appSteps = (jobs['web-chat-contract']['steps'] as List).where(
        (s) => s['working-directory'] == 'example/chat_app',
      );
      expect(
        appSteps.any(
          (s) => (s['run'] as String? ?? '')
              .split('\n')
              .contains('flutter test test test_vm'),
        ),
        isTrue,
      );
      final mixed = await selected([
        'packages/llamadart_validation/test/validation_test.dart',
        'test/unit/tooling/validation_remote_test.dart',
      ]);
      expect(mixed['jobs']['validation-integration'], isTrue);
      final integrationFlutter =
          (jobs['validation-integration']['steps'] as List).singleWhere(
            (s) => '${s['run']}'.contains('validation_controller_test.dart'),
          );
      expect(integrationFlutter.containsKey('if'), isFalse);
    },
  );

  test('Example Package Tests run every other example package', () {
    final job = readWorkflow('ci')['jobs']['example-packages'] as Map;
    final steps = job['steps'] as List;
    expect(job.containsKey('continue-on-error'), isFalse);
    for (final step in steps.cast<Map>()) {
      expect(step.containsKey('continue-on-error'), isFalse, reason: '$step');
    }
    final tested = {
      for (final step in steps.cast<Map>())
        if (step['working-directory'] case final String dir) dir: step,
    };
    final packages = Directory('example')
        .listSync()
        .whereType<Directory>()
        .map((dir) => dir.path.replaceAll(r'\', '/'))
        .where((dir) => File('$dir/pubspec.yaml').existsSync())
        .where((dir) => Directory('$dir/test').existsSync())
        .toSet();
    expect(packages, contains('example/chat_app'));
    expect(tested.keys.toSet(), packages.difference({'example/chat_app'}));
    for (final MapEntry(key: dir, value: step) in tested.entries) {
      final pubspec = File('$dir/pubspec.yaml').readAsStringSync();
      final runner =
          pubspec.contains(RegExp(r'^\s+sdk: flutter$', multiLine: true))
          ? 'flutter'
          : 'dart';
      expect(step['if'], r'${{ !cancelled() }}', reason: dir);
      expect('${step['run']}'.trim().split('\n'), [
        'flutter pub get',
        'TMPDIR="\$(mktemp -d)" $runner test --exclude-tags local-only',
      ], reason: dir);
    }
  });

  test('Web Chat Contract installs no system packages', () {
    final steps =
        readWorkflow('ci')['jobs']['web-chat-contract']['steps'] as List;
    for (final step in steps) {
      expect(_installsSystemPackages(step as Map), isFalse, reason: '$step');
    }
  });

  test('the system-package check catches apt, dpkg and apt actions', () {
    for (final step in <Map>[
      {'run': 'sudo apt-get install -y libfoo'},
      {'run': 'sudo apt install libfoo'},
      {'run': 'sudo apt -y install libfoo'},
      {'run': 'sudo dpkg -i foo.deb'},
      {'run': 'npx playwright install --with-deps chromium'},
      {'run': 'npx playwright install-deps'},
      {'uses': 'awalsh128/cache-apt-pkgs-action@v1'},
      {'uses': 'ConorMacBride/install-linux-deps@v1'},
    ]) {
      expect(_installsSystemPackages(step), isTrue, reason: '$step');
    }
    for (final step in <Map>[
      {'run': 'npx playwright install chromium'},
      {'uses': 'actions/checkout@v7'},
      {'uses': 'subosito/flutter-action@v2'},
    ]) {
      expect(_installsSystemPackages(step), isFalse, reason: '$step');
    }
  });

  test('Web Chat Contract opts the chat app out of stable_diffusion', () {
    final steps =
        readWorkflow('ci')['jobs']['web-chat-contract']['steps'] as List;
    int indexOfRun(Pattern needle) =>
        steps.indexWhere((s) => '${s['run']}'.contains(needle));
    final optOut = indexOfRun('llamadart_native_runtimes');
    final install = indexOfRun('flutter pub get');
    final tests = indexOfRun('flutter test test test_vm');
    final restore = indexOfRun('git checkout -- example/chat_app/pubspec.yaml');
    final build = indexOfRun('scripts/build_chat_app_web.sh');
    expect(optOut, isNonNegative);
    expect(optOut, lessThan(install));
    expect(install, lessThan(tests));
    expect(tests, lessThan(restore));
    expect(restore, lessThan(build));

    final lines = '${steps[optOut]['run']}'
        .split('\n')
        .map((l) => l.trim())
        .toList();
    expect(
      lines,
      contains(
        r"sed -i 's/^\( *llamadart_native_runtimes:\) all$/\1 both/' "
        'pubspec.yaml',
      ),
    );
    expect(
      lines,
      contains(r"grep -q '^ *llamadart_native_runtimes: both$' pubspec.yaml"),
    );
    expect(steps[optOut]['shell'], isNull);
    expect(steps[optOut]['continue-on-error'], isNull);
  });

  test(
    'runtime lanes retain full OS tests, model smoke, and coverage threshold',
    () {
      final jobs = readWorkflow('ci')['jobs'];
      final nativeSteps = jobs['test-other-os']['steps'] as List;
      expect(
        nativeSteps.any(
          (s) =>
              s['run'] ==
              'dart test -p vm -j 1 --exclude-tags local-only '
                  '--file-reporter=json:.dart_tool/test_events.jsonl '
                  r'${{ steps.shard.outputs.files }}',
        ),
        isTrue,
      );
      expect(
        (jobs['companion-packages']['steps'] as List).any(
          (s) => '${s['run']}'.contains(
            '--run-skipped test/integration/apple_companion_flutter_cache_test.dart',
          ),
        ),
        isTrue,
      );
      final shardSteps = jobs['test-linux-vm']['steps'] as List;
      final shardRuns = shardSteps.map((s) => '${s['run']}').toList();
      expect(shardRuns, contains(linuxVmRun));
      expect(
        jobs['changes']['outputs']['coverage'],
        r'${{ steps.select.outputs.coverage }}',
      );
      // Node-backed tooling fixtures bound each harness run; the runner's
      // cold first `node` start must happen before them.
      final loadNode = shardSteps.indexWhere(
        (s) => '${s['run']}'.contains('node -e '),
      );
      expect(loadNode, greaterThanOrEqualTo(0));
      expect(
        shardSteps[loadNode]['if'],
        'contains(steps.shard.outputs.files, '
        "'test/unit/tooling/playwright_chat_app_real_model_smoke_test.dart')",
      );
      expect(
        File(
          'test/unit/tooling/playwright_chat_app_real_model_smoke_test.dart',
        ).readAsStringSync(),
        contains("'node'"),
      );
      expect(
        loadNode,
        greaterThan(shardSteps.indexWhere((s) => s['id'] == 'shard')),
      );
      expect(
        loadNode,
        lessThan(
          shardRuns.indexWhere((run) => run.startsWith('dart test -p vm')),
        ),
      );
      final upload =
          shardSteps.singleWhere((s) => s['name'] == 'Upload raw coverage')
              as Map;
      expect('${upload['uses']}', startsWith('actions/upload-artifact@'));
      expect(upload['with'], {
        'name': r'linux-vm-coverage-${{ matrix.shard }}',
        'path': 'coverage/',
        'if-no-files-found': 'error',
        'retention-days': 1,
        'overwrite': true,
      });
      expect(upload['if'], "needs.changes.outputs.coverage == 'true'");

      final coverageSteps = jobs['test-linux-coverage']['steps'] as List;
      int index(bool Function(Map step) test) =>
          coverageSteps.indexWhere((s) => test(s as Map));
      final download = index(
        (s) => '${s['uses']}'.startsWith('actions/download-artifact@'),
      );
      expect(download, greaterThanOrEqualTo(0));
      expect(coverageSteps[download]['with'], {
        'pattern': 'linux-vm-coverage-*',
        'merge-multiple': true,
        'path': 'coverage/',
      });
      final format = index(
        (s) => '${s['run']}'.contains(
          'dart run tool/testing/format_lcov.dart --lcov '
          '--in=coverage/test --out=coverage/lcov.info --report-on=lib '
          '--check-ignore',
        ),
      );
      expect(format, greaterThan(download));
      expect(
        coverageSteps[format]['run'],
        contains(
          'dart run tool/testing/check_lcov_threshold.dart '
          'coverage/lcov.info 70',
        ),
      );
      // A failed post-merge gate names itself on the run and its summary.
      final report = index((s) => s['if'] == 'failure()');
      expect(report, greaterThan(format));
      expect(
        coverageSteps[report]['run'],
        allOf(contains('::error title='), contains(r'$GITHUB_STEP_SUMMARY')),
      );
      final codecov = index(
        (s) => '${s['uses']}'.startsWith('codecov/codecov-action@'),
      );
      expect(codecov, greaterThan(format));
      expect(coverageSteps[codecov]['with']['files'], 'coverage/lcov.info');
      for (final steps in [shardSteps, coverageSteps]) {
        expect(
          steps.any(
            (s) => '${s['run']}'.contains('pub global activate coverage'),
          ),
          isFalse,
        );
      }
      expect(
        coverageSteps.any((s) => '${s['run']}'.contains('dart test')),
        isFalse,
      );
    },
  );

  group('test lane shards', () {
    Map<String, dynamic> jobs() =>
        readWorkflow('ci')['jobs'] as Map<String, dynamic>;

    /// Each lane's matrix legs as (shard, shards) and the run step that
    /// selects its files.
    Map<String, ({List<(int, int)> legs, String select})> lanes() {
      final all = jobs();
      String selectOf(String job) =>
          '${(all[job]['steps'] as List).cast<Map>().singleWhere((s) => s['id'] == 'shard')['run']}';
      List<(int, int)> uniform(String job) {
        final shards = (all[job]['strategy']['matrix']['shard'] as List)
            .cast<int>();
        return [for (final shard in shards) (shard, shards.length)];
      }

      final native =
          (all['test-other-os']['strategy']['matrix']['include'] as List)
              .cast<Map>();
      for (final leg in native) {
        expect(
          leg['os'],
          '${leg['lane']}' == 'macos' ? 'macos-latest' : 'windows-latest',
        );
      }
      return {
        'linux-vm': (
          legs: uniform('test-linux-vm'),
          select: selectOf('test-linux-vm'),
        ),
        'chrome': (legs: uniform('test-web'), select: selectOf('test-web')),
        for (final lane in ['macos', 'windows-tooling', 'windows-runtime'])
          lane: (
            legs: [
              for (final leg in native)
                if (leg['lane'] == lane)
                  (leg['shard'] as int, leg['shards'] as int),
            ],
            select: selectOf('test-other-os'),
          ),
      };
    }

    test('every lane runs shards 1..n of one count through the selector', () {
      final all = lanes();
      expect(all.keys, unorderedEquals(testShardLanes.keys));
      for (final MapEntry(key: lane, value: (:legs, :select)) in all.entries) {
        expect(legs, isNotEmpty, reason: lane);
        final count = legs.first.$2;
        expect(legs, [
          for (var shard = 1; shard <= count; shard++) (shard, count),
        ], reason: lane);
        expect(
          select,
          anyOf(
            'dart tool/ci/test_shards.dart $lane '
                r'${{ matrix.shard }} ${{ strategy.job-total }}',
            'dart tool/ci/test_shards.dart '
                r'${{ matrix.lane }} ${{ matrix.shard }} ${{ matrix.shards }}',
          ),
          reason: lane,
        );
      }
      for (final job in ['test-linux-vm', 'test-web', 'test-other-os']) {
        expect(jobs()[job]['strategy']['fail-fast'], isFalse, reason: job);
      }
      // test-other-os is the only job that mixes lanes, so only it may take
      // the lane and count from the matrix rather than from the job total.
      expect((jobs()['test-other-os']['strategy']['matrix'] as Map).keys, [
        'include',
      ]);
      expect(
        jobs()['test-other-os']['name'],
        r'Test Native (${{ matrix.lane }}, ${{ matrix.shard }}/${{ matrix.shards }})',
      );
    });

    test('the selector enumerates every root test file', () {
      final listed = Directory('test')
          .listSync(recursive: true)
          .whereType<File>()
          .map((file) => file.path.replaceAll(r'\', '/'))
          .where((path) => path.endsWith('_test.dart'))
          .toSet();
      expect(listed, isNotEmpty);
      expect(rootTestFiles().toSet(), listed);
    });

    test('each run step tests exactly its shard and timing names are unique', () {
      final all = jobs();
      for (final (job, run) in [
        ('test-linux-vm', linuxVmRun),
        (
          'test-web',
          'dart test -p chrome --exclude-tags local-only '
              '--file-reporter=json:.dart_tool/test_events.jsonl '
              r'${{ steps.shard.outputs.files }}',
        ),
        (
          'test-other-os',
          'dart test -p vm -j 1 --exclude-tags local-only '
              '--file-reporter=json:.dart_tool/test_events.jsonl '
              r'${{ steps.shard.outputs.files }}',
        ),
      ]) {
        final steps = (all[job]['steps'] as List).cast<Map>();
        final select = steps.indexWhere((s) => s['id'] == 'shard');
        final tests = steps.indexWhere((s) => s['run'] == run);
        expect(select, greaterThanOrEqualTo(0), reason: job);
        expect(tests, greaterThan(select), reason: job);
        expect(
          steps.where((s) => '${s['run']}'.contains('dart test -p ')),
          hasLength(1),
          reason: job,
        );
        // Two legs sharing an artifact name would fail the second upload.
        expect(
          steps.singleWhere(
            (s) => s['name'] == 'Upload test timing',
          )['with']['name'],
          job == 'test-other-os'
              ? r'test-timing-${{ matrix.lane }}-${{ matrix.shard }}-${{ github.run_attempt }}'
              : 'test-timing-${job == 'test-web' ? 'chrome' : 'linux-vm'}-'
                    r'${{ matrix.shard }}-${{ github.run_attempt }}',
          reason: job,
        );
      }
    });
  });

  test('VM test lanes run against a temp directory guarded by a LiteRT-LM '
      'cache canary', () {
    final jobs = readWorkflow('ci')['jobs'];
    for (final job in ['test-linux-vm', 'test-other-os', 'markdown-tests']) {
      final steps = jobs[job]['steps'] as List;
      int index(String run) => steps.indexWhere((s) => s['run'] == run);
      final seed = index('bash tool/ci/litert_lm_temp_canary.sh seed');
      final tests = steps.indexWhere(
        (s) => '${s['run']}'.contains('dart test -p vm -j 1 '),
      );
      final check = index('bash tool/ci/litert_lm_temp_canary.sh check');
      expect(seed, greaterThanOrEqualTo(0), reason: job);
      expect(tests, greaterThan(seed), reason: job);
      expect(check, greaterThan(tests), reason: job);
      expect((steps[seed] as Map).containsKey('if'), isFalse, reason: job);
      expect(steps[check]['if'], r'${{ !cancelled() }}', reason: job);
    }
  });

  test('the coverage formatter version is pinned exactly in pubspec.yaml', () {
    final pubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    final constraint =
        (pubspec['dev_dependencies'] as YamlMap)['coverage'] as String;

    expect(constraint, _pinnedCoverageVersion);
  });

  test('the resolved coverage version matches the pin', () {
    final lock = File('pubspec.lock');
    if (!lock.existsSync()) {
      markTestSkipped('pubspec.lock is gitignored; run `dart pub get` first.');
      return;
    }
    final packages =
        (loadYaml(lock.readAsStringSync()) as YamlMap)['packages'] as YamlMap;
    final resolved = (packages['coverage'] as YamlMap)['version'] as String;

    expect(
      resolved,
      _pinnedCoverageVersion,
      reason:
          'coverage resolved to $resolved, not the pinned '
          '$_pinnedCoverageVersion the LCOV formatter was verified against.',
    );
  });
}

/// `coverage` version `pubspec.yaml` pins and the LCOV formatter was verified
/// against.
const _pinnedCoverageVersion = '1.16.0';

bool _installsSystemPackages(Map step) =>
    RegExp(
      r'\bapt(-get)?\b|dpkg|install-deps|--with-deps',
    ).hasMatch('${step['run']}') ||
    RegExp(r'apt|dpkg|install-.*deps').hasMatch('${step['uses']}');
