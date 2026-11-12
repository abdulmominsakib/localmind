@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../../tool/ci/native_test_timing.dart';

Map<String, dynamic> event(
  String type,
  int time, [
  Map<String, dynamic>? data,
]) => {'type': type, 'time': time, ...?data};

void main() {
  late NativeTestTiming timing;
  setUp(() {
    timing = NativeTestTiming(Directory.current.path);
    timing.add(event('start', 0));
    timing.add(
      event('suite', 5, {
        'suite': {'id': 0, 'path': 'test/example_test.dart'},
      }),
    );
  });
  void start(int id, int time) => timing.add(
    event('testStart', time, {
      'test': {'id': id, 'suiteID': 0, 'line': 12, 'name': 'credential-secret'},
    }),
  );
  void finish(int id, int time, {bool hidden = false, bool skipped = false}) =>
      timing.add(
        event('testDone', time, {
          'testID': id,
          'result': 'success',
          'hidden': hidden,
          'skipped': skipped,
        }),
      );

  test(
    'retains overlapping, hidden and skipped intervals without adding them',
    () {
      start(0, 10);
      start(1, 20);
      finish(1, 30, hidden: true);
      finish(0, 50);
      start(2, 60);
      finish(2, 60, skipped: true);
      timing.add(event('done', 70, {'success': true}));
      final report = timing.toJson();
      expect(report['complete'], isTrue);
      expect(report['reporterElapsedMs'], 70);
      final tests = report['tests'] as List;
      expect(tests.map((test) => test['durationMs']), [40, 10, 0]);
      expect(tests[1]['hidden'], isTrue);
      expect(tests[2]['skipped'], isTrue);
      expect(jsonEncode(report), isNot(contains('credential-secret')));
    },
  );
  test('late errors invalidate hidden success without exposing messages', () {
    start(0, 10);
    finish(0, 20, hidden: true);
    timing.add(
      event('error', 30, {
        'testID': 0,
        'error': 'credential-secret',
        'stackTrace': '/sensitive/path',
      }),
    );
    timing.add(event('done', 40, {'success': false}));
    final report = timing.toJson();
    expect(report['success'], isFalse);
    expect((report['tests'] as List).single['result'], 'error');
    expect((report['tests'] as List).single['hidden'], isFalse);
    expect(jsonEncode(report), isNot(contains('credential-secret')));
    expect(jsonEncode(report), isNot(contains('/sensitive/path')));
  });
  test('interrupted streams remain incomplete', () {
    start(0, 10);
    expect(timing.toJson()['complete'], isFalse);
    expect((timing.toJson()['tests'] as List).single['durationMs'], isNull);
    timing.add(event('done', 20, {'success': null}));
    expect(timing.toJson()['complete'], isFalse);
    expect(timing.toJson()['success'], isNull);
  });
  test('redacts external suite paths and tolerates new events', () {
    timing.add(
      event('suite', 10, {
        'suite': {
          'id': 1,
          'path': '${Directory.current.parent.path}/secret.dart',
        },
      }),
    );
    timing.add(event('futureProtocolEvent', 20));
    final suites = timing.toJson()['suites'] as List;
    expect(suites.first['path'], 'test/example_test.dart');
    expect(suites.last['path'], '<external-or-loading-suite>');
  });
  test('rejects unpaired and backwards events', () {
    expect(() => finish(42, 10), throwsFormatException);
    final other = NativeTestTiming(Directory.current.path);
    other.add(event('start', 10));
    expect(() => other.add(event('done', 9)), throwsFormatException);
  });
  test('CLI writes sanitized output and rejects malformed input', () async {
    final directory = Directory.systemTemp.createTempSync('native-timing-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final input = File('${directory.path}/events.jsonl');
    final output = File('${directory.path}/summary.json');
    input.writeAsStringSync(
      [
        event('start', 0),
        event('print', 1, {'message': 'credential-secret'}),
        event('done', 2, {'success': false}),
      ].map(jsonEncode).join('\n'),
    );
    Future<ProcessResult> run() => Process.run(Platform.resolvedExecutable, [
      'tool/ci/native_test_timing.dart',
      input.path,
      output.path,
    ]);
    final valid = await run();
    expect(valid.exitCode, 0, reason: '${valid.stderr}');
    expect(jsonDecode(output.readAsStringSync())['success'], isFalse);
    expect(output.readAsStringSync(), isNot(contains('credential-secret')));
    input.writeAsStringSync('credential-secret malformed JSON');
    final malformed = await run();
    expect(malformed.exitCode, 1);
    expect(
      '${malformed.stdout}${malformed.stderr}',
      isNot(contains('credential-secret')),
    );
    expect(output.existsSync(), isFalse);
  });
  test('workflow preserves selection, canary, exit and separate cache gate', () {
    final workflow =
        loadYaml(File('.github/workflows/ci.yml').readAsStringSync())
            as YamlMap;
    final job = workflow['jobs']['test-other-os'];
    expect(
      (job['strategy']['matrix']['include'] as YamlList).map(
        (leg) => leg['os'],
      ),
      containsAll(['macos-latest', 'windows-latest']),
    );
    final steps = job['steps'] as YamlList;
    final run = steps.singleWhere((step) => step['name'] == 'Run native tests');
    expect(
      run['run'],
      r'dart test -p vm -j 1 --exclude-tags local-only --file-reporter=json:.dart_tool/test_events.jsonl ${{ steps.shard.outputs.files }}',
    );
    expect(run['env']['GGML_METAL_DEVICES'], '0');
    expect(run.containsKey('continue-on-error'), isFalse);
    final check = steps.singleWhere(
      (step) => step['name'] == 'Check the LiteRT-LM cache canary',
    );
    expect(check['if'], r'${{ !cancelled() }}');
    expect(check['run'], 'bash tool/ci/litert_lm_temp_canary.sh check');
    expect(
      (workflow['jobs']['companion-packages']['steps'] as YamlList).singleWhere(
        (step) =>
            step['name'] == 'Verify Flutter Apple companion cache transitions',
      )['run'],
      'dart test -p vm --run-skipped test/integration/apple_companion_flutter_cache_test.dart',
    );
    final upload = steps.singleWhere(
      (step) => step['name'] == 'Upload test timing',
    );
    expect(upload['with']['path'], '.dart_tool/test_timing.json');
    expect(upload['if'], contains('!cancelled()'));
  });
}
