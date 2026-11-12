import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart_validation/io.dart';
import 'package:llamadart_validation/llamadart_validation.dart';
import 'package:llamadart_validation/src/placement.dart';
import 'package:test/test.dart';

const _referencePath = 'assets/decision/laya_0_3_5_reference.json';
final _referenceText = File(_referencePath).readAsStringSync();
final _reference = jsonDecode(_referenceText) as Map<String, dynamic>;
final _rows = (_reference['rows'] as List).cast<Map<String, dynamic>>();

Map<String, dynamic> _profileJson(String backend) =>
    jsonDecode(
          File(
            'assets/profiles/decision-gguf-$backend.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

ValidationProfile _profile([String backend = 'cpu']) =>
    ValidationProfile.fromJson(_profileJson(backend));

Object? _copy(Object? value) => jsonDecode(jsonEncode(value));

class FakeDecisionEngine implements ValidationEngine, DecisionValidationEngine {
  FakeDecisionEngine({this.device = 'CPU', this.backendName = 'CPU'});

  String device;
  String backendName;
  bool supported = true;
  bool modelLoaded = false;
  bool decisionDisposed = false;
  bool disposedRejects = true;
  bool unloadRejects = true;
  bool missingHeadRejects = true;
  bool invalidInputRejects = true;
  String? wrongTokenText;
  String? logitRow;
  double logitOffset = 0;
  int usageOffset = 0;
  String? answerRow;
  void Function(Map<String, dynamic> answer)? perturb;
  final calls = <String>[];

  @override
  bool get isWeb => false;

  @override
  Future<void> load(String location, ValidationProfile profile) async {
    calls.add('load');
    modelLoaded = true;
  }

  @override
  Future<void> unload() async {
    calls.add('unload');
    modelLoaded = false;
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    modelLoaded = false;
  }

  @override
  void cancel() {}

  @override
  Future<Map<String, dynamic>> diagnostics() async => {
    'backend_name': backendName,
    'model_metadata': <String, dynamic>{},
  };

  @override
  Future<List<int>> tokenize(String text) async {
    final ids = ((_reference['pieces'] as Map)[text] as List).cast<int>();
    return text == wrongTokenText || wrongTokenText == '*' ? [...ids, 0] : ids;
  }

  @override
  Future<String> detokenize(List<int> tokens) async => '';

  @override
  Future<Map<String, dynamic>> generate(
    String prompt,
    ValidationProfile profile, {
    bool raw = false,
    int? maxTokens,
    int? streamBatchTokens,
    int? streamBatchBytes,
    bool cancelAfterFirst = false,
    bool cancelOnListen = false,
    int? cancelAfterMs,
    List<LlamaChatMessage>? history,
    List<String>? stopSequences,
    bool? enableThinking,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    String? grammar,
  }) => throw StateError('decision profiles do not generate text');

  @override
  Future<Map<String, dynamic>> generateOverlapping(
    String first,
    String second,
    ValidationProfile profile, {
    required bool raw,
    required int firstMaxTokens,
    required bool cancelFirst,
    int? secondAfterMs,
  }) => throw StateError('decision profiles do not generate text');

  Map<String, dynamic> _head() => {
    'supported': supported,
    'backend_name': backendName,
    if (supported) 'device_name': device,
  };

  @override
  Future<Map<String, dynamic>> loadDecision({bool missingHead = false}) async {
    calls.add(missingHead ? 'load_missing_head' : 'load_head');
    if (missingHead && missingHeadRejects) {
      throw LlamaModelException('Cannot open safetensors file');
    }
    if (!missingHead) decisionDisposed = false;
    return _head();
  }

  @override
  Future<Map<String, dynamic>> decisionLogits(
    List<Map<String, dynamic>> sequences,
  ) async {
    calls.add('raw');
    return {
      'device_name': device,
      'outputs': [
        for (final sequence in sequences)
          () {
            final row = _rows.singleWhere(
              (row) => jsonEncode(row['ids']) == jsonEncode(sequence['tokens']),
            );
            final logits = [
              for (final value in row['rawLogits'] as List)
                (value as num).toDouble(),
            ];
            if (row['id'] == logitRow) logits[0] += logitOffset;
            return {'logits': logits, 'act_logits': row['rawActLogits']};
          }(),
      ],
    };
  }

  @override
  Future<List<Map<String, dynamic>>> decide(
    List<Map<String, dynamic>> requests, {
    bool batch = false,
  }) async {
    calls.add(batch ? 'batch' : 'decide');
    if (!supported) throw StateError('No DecisionEngine is loaded');
    if (decisionDisposed && disposedRejects) {
      throw LlamaStateException('This DecisionEngine was disposed.');
    }
    if (!modelLoaded && unloadRejects) {
      throw LlamaStateException('The model was unloaded.');
    }
    return [
      for (final request in requests)
        () {
          if (request['state'] is String &&
              (request['state'] as String).contains('\u0000') &&
              invalidInputRejects) {
            throw LlamaDecisionException('Decision text contains U+0000');
          }
          final questions = request['questions'] as Map;
          final answers = <String, dynamic>{};
          var tokens = usageOffset;
          for (final MapEntry(:key, :value) in questions.entries) {
            final row = _rows.singleWhere(
              (row) =>
                  (row['id'] as String).endsWith('/$key') &&
                  jsonEncode(row['question']) == jsonEncode(value) &&
                  jsonEncode(row['state']) == jsonEncode(request['state']),
              orElse: () => _rows.firstWhere(
                (row) => (row['id'] as String).endsWith('/$key'),
              ),
            );
            tokens += (row['ids'] as List).length;
            final answer = _copy(row['answer']) as Map<String, dynamic>;
            if (row['id'] == answerRow) perturb?.call(answer);
            answers[key as String] = answer;
          }
          return {
            'model': 'laya-rl-agent',
            'answers': answers,
            'usage': {'input_tokens': tokens, 'output_tokens': 0},
          };
        }(),
    ];
  }

  @override
  Future<void> disposeDecision() async {
    calls.add('dispose_head');
    decisionDisposed = true;
  }
}

Map<String, dynamic> _preparation(ValidationProfile profile) => {
  'verified': true,
  'sha256': profile.modelHash,
  'bytes': profile.model['bytes'],
  for (final MapEntry(:key, :value) in profile.decisionArtifacts.entries)
    'decision_$key': {
      'verified': true,
      'sha256': (value as Map)['sha256'],
      'bytes': value['bytes'],
    },
};

Future<({ValidationReport report, List<Map<String, dynamic>> events})> _run(
  ValidationEngine engine, {
  ValidationProfile? profile,
  String? reference,
  Map<String, dynamic>? preparation,
  String? nativeLog,
}) async {
  final selected = profile ?? _profile();
  final events = <Map<String, dynamic>>[];
  await ValidationRunner(
    profile: selected,
    engine: engine,
    emit: (event) async => events.add(_copy(event) as Map<String, dynamic>),
    decisionReference: reference ?? _referenceText,
  ).run(
    'laya-F16.gguf',
    runId: 'decision-test',
    preparation: preparation ?? _preparation(selected),
    environment: {
      'source_commit': List.filled(40, 'a').join(),
      'source_dirty': false,
      'hook_sha256': List.filled(64, 'b').join(),
      'native_tag': 'v0.5.0',
    },
  );
  return (
    report: ValidationReport.parse(
      events.map(jsonEncode).join('\n'),
      nativeLog: nativeLog,
    ),
    events: events,
  );
}

Map<String, String> _statuses(ValidationReport report) => {
  for (final record in report.cases)
    record['case_id'] as String: record['status'] as String,
};

Map<String, dynamic> _case(ValidationReport report, String id) =>
    report.cases.singleWhere((record) => record['case_id'] == id);

const _decisionIds = [
  'D01.head',
  'D02.tokenizer',
  'D03.logits',
  'D04.answers',
  'D05.batch',
  'D06.reload',
  'D07.guards',
];

void main() {
  test('decision profiles select only load and decision cases', () {
    for (final backend in ['cpu', 'metal', 'vulkan', 'cuda', 'webgpu']) {
      final profile = _profile(backend);
      expect(profile.isDecision, isTrue);
      expect(profile.caseIds, ['C01.load', ..._decisionIds]);
      expect(profile.requiresAcceleratorProof, backend != 'cpu');
      expect(profile.loadParams.contextSize, 512);
      expect(profile.loadParams.numberOfThreadsBatch, 4);
      expect(
        profile.loadParams.gpuLayers,
        backend == 'cpu' ? 0 : ModelParams.maxGpuLayers,
      );
      expect(
        profile.loadParams.preferredBackend,
        backend == 'webgpu'
            ? GpuBackend.auto
            : GpuBackend.values.byName(backend),
      );
      final cases = (profile.catalog['cases'] as List).cast<Map>();
      for (final entry in cases) {
        final selected = profile.caseIds.contains(entry['id']);
        expect(entry['selected'], selected, reason: '${entry['id']}');
        if (!selected) {
          expect(
            entry['omission_reason'],
            'decision_model_has_no_text_generation',
          );
        }
      }
      expect(
        cases.where((entry) => '${entry['id']}'.startsWith('D')).length,
        _decisionIds.length,
      );
    }
  });

  test('chat catalogs are unchanged by the decision pack', () {
    final chat = ValidationProfile.fromJson(
      jsonDecode(File('assets/profiles/chat-gguf-cpu.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    final catalog = chat.catalog;
    expect(
      (catalog['cases'] as List).map((entry) => (entry as Map)['id']),
      isNot(contains(startsWith('D0'))),
    );
    expect((catalog['fixtures'] as Map).containsKey('decision'), isFalse);
    expect((catalog['features'] as Map).containsKey('decision'), isFalse);
  });

  test('decision cases require catalog 5 or newer', () {
    for (var version = 1; version < 5; version++) {
      expect(
        () => _profile().catalogForVersion(version),
        throwsFormatException,
      );
      for (final id in _decisionIds) {
        expect(catalogDeclaresCase(id, version), isFalse, reason: id);
        expect(
          () => validationCase(id, catalogVersion: version),
          throwsFormatException,
        );
      }
    }
    for (final id in _decisionIds) {
      expect(catalogDeclaresCase(id, validationCatalogVersion), isTrue);
    }
  });

  test('decision profiles reject incomplete or conflicting locks', () {
    Map<String, dynamic> patched(void Function(Map<String, dynamic>) change) {
      final json = _profileJson('cpu');
      change(json);
      return json;
    }

    Map<String, dynamic> head() =>
        (_profileJson('cpu')['decision'] as Map)['head']
            as Map<String, dynamic>;
    final invalid = <String, Map<String, dynamic>>{
      'no head': patched((json) => json['decision'] = <String, dynamic>{}),
      'no decision block': patched((json) => json.remove('decision')),
      'decision block on a chat model': patched(
        (json) => (json['model'] as Map)['kind'] = 'chat',
      ),
      'LiteRT runtime': patched((json) => json['runtime'] = 'litert'),
      'focused selection': patched(
        (json) => json
          ..['selection'] = 'focused'
          ..['focus_features'] = ['text'],
      ),
      'fixture override': patched(
        (json) => json['fixtures'] = {
          'hello': {'prompt': 'x'},
        },
      ),
      'unknown decision key': patched(
        (json) => (json['decision'] as Map)['tokenizer'] = head(),
      ),
      'mutable head URL': patched(
        (json) => ((json['decision'] as Map)['head'] as Map)['url'] =
            'https://huggingface.co/fr0stbit3/laya-gguf/resolve/main/laya-head.safetensors',
      ),
      'head URL query': patched(
        (json) => ((json['decision'] as Map)['head'] as Map)['url'] =
            '${head()['url']}?download=true',
      ),
      'head filename mismatch': patched(
        (json) => ((json['decision'] as Map)['head'] as Map)['filename'] =
            'other.safetensors',
      ),
      'head extension': patched(
        (json) => (json['decision'] as Map)['head'] = {
          ...head(),
          'filename': 'laya-head.bin',
          'url': (head()['url'] as String).replaceFirst(
            'laya-head.safetensors',
            'laya-head.bin',
          ),
        },
      ),
      'head size': patched(
        (json) => ((json['decision'] as Map)['head'] as Map)['bytes'] = 0,
      ),
      'head hash': patched(
        (json) => ((json['decision'] as Map)['head'] as Map)['sha256'] = 'ab',
      ),
      'config extension': patched(
        (json) => (json['decision'] as Map)['config'] = head(),
      ),
    };
    for (final entry in invalid.entries) {
      expect(
        () => ValidationProfile.fromJson(entry.value),
        throwsFormatException,
        reason: entry.key,
      );
    }
    final config = {
      ...head(),
      'filename': 'rl_agent_config.json',
      'url': (head()['url'] as String).replaceFirst(
        'laya-head.safetensors',
        'rl_agent_config.json',
      ),
    };
    final withConfig = ValidationProfile.fromJson(
      patched((json) => (json['decision'] as Map)['config'] = config),
    );
    expect(withConfig.decisionArtifacts.keys, ['head', 'config']);
  });

  test('bundled reference matches the pinned hash and row count', () {
    final fixture = _profile().fixtures['decision'] as Map;
    expect(fixture['reference'], _referencePath);
    expect(
      sha256.convert(File(_referencePath).readAsBytesSync()).toString(),
      fixture['reference_sha256'],
    );
    expect(_rows, hasLength(fixture['rows'] as int));
  });

  test('tolerances match the decision E2E defaults', () {
    final source = File(
      '../../test/e2e/backends/decision_engine_e2e_test.dart',
    ).readAsStringSync();
    final fixture = _profile().fixtures['decision'] as Map;
    expect(
      source,
      contains('_tolerance(_logitToleranceKey, ${fixture['logit_tolerance']})'),
    );
    expect(
      source,
      contains(
        '_tolerance(_probToleranceKey, ${fixture['probability_tolerance']})',
      ),
    );
    // The native E2E passes these to DecisionParity; the Web E2E uses its
    // defaults.
    final parity = File(
      '../../test/support/decision_fixture.dart',
    ).readAsStringSync();
    expect(
      parity,
      contains('this.logitTolerance = ${fixture['logit_tolerance']}'),
    );
    expect(
      parity,
      contains('this.probTolerance = ${fixture['probability_tolerance']}'),
    );
    expect(parity, contains("expected['score'], 2 * probTolerance"));
    expect(
      fixture['score_tolerance'],
      2 * (fixture['probability_tolerance'] as double),
    );
  });

  test('catalog 5 decision journals retain their qualification', () async {
    final selected = _profile();
    final result = await _run(FakeDecisionEngine());
    final events = (jsonDecode(jsonEncode(result.events)) as List)
        .cast<Map<String, dynamic>>();
    events.first['catalog'] = selected.catalogForVersion(5);
    events.first['catalog_hash'] = jsonHash(events.first['catalog']);
    final old = ValidationReport.parse(events.map(jsonEncode).join('\n'));
    expect(old.problems, isEmpty);
    expect(old.qualified, result.report.qualified);
  });

  test('reference answers pass every decision case', () async {
    final engine = FakeDecisionEngine();
    final result = await _run(engine);
    expect(_statuses(result.report), {
      'C01.load': 'PASS',
      for (final id in _decisionIds) id: 'PASS',
    });
    expect(result.report.assertionsPassed, isTrue);
    expect(result.report.qualified, isTrue);
    expect(engine.calls, containsAllInOrder(['load', 'load_head', 'raw']));
    expect(
      engine.calls,
      containsAllInOrder([
        'dispose_head',
        'decide',
        'load_head',
        'decide',
        'unload',
        'decide',
        'load',
        'load_head',
        'decide',
        'load_missing_head',
      ]),
    );
    expect(engine.calls.where((call) => call == 'batch'), hasLength(1));
    expect(_case(result.report, 'D04.answers')['questions'], 24);
    expect(_case(result.report, 'D04.answers')['requests'], 15);
  });

  group('bounds', () {
    test('raw logits pass within 0.25 and fail beyond it', () async {
      for (final (offset, status) in [(0.2499, 'PASS'), (0.2501, 'FAIL')]) {
        for (final sign in [1, -1]) {
          final engine = FakeDecisionEngine()
            ..logitRow = 'squeeze/plan'
            ..logitOffset = sign * offset;
          final report = (await _run(engine)).report;
          expect(
            _statuses(report)['D03.logits'],
            status,
            reason: 'offset ${sign * offset}',
          );
        }
      }
    });

    final fields = <String, (String, double, void Function(Map, double))>{
      'confidence': (
        'readme/department',
        0.05,
        (answer, delta) => answer['confidence'] += delta,
      ),
      'act_probability': (
        'readme/refund',
        0.05,
        (answer, delta) => answer['action']['act_probability'] -= delta,
      ),
      'choice probability': (
        'readme/department',
        0.05,
        (answer, delta) => answer['probabilities']['sales'] += delta,
      ),
      'score probability': (
        'readme/urgency',
        0.05,
        (answer, delta) => answer['probabilities']['1'] -= delta,
      ),
      'noul': (
        'readme/churn_risk',
        0.05,
        (answer, delta) => answer['noul'] += delta,
      ),
      'score': (
        'plain_text/urgency5',
        0.1,
        (answer, delta) => answer['score'] += delta,
      ),
    };
    for (final MapEntry(key: field, value: (row, bound, apply))
        in fields.entries) {
      test('$field passes within $bound and fails beyond it', () async {
        for (final (delta, status) in [
          (bound - 1e-4, 'PASS'),
          (bound + 1e-4, 'FAIL'),
        ]) {
          final engine = FakeDecisionEngine()
            ..answerRow = row
            ..perturb = ((answer) => apply(answer, delta));
          final report = (await _run(engine)).report;
          for (final id in ['D04.answers', 'D05.batch']) {
            expect(
              _statuses(report)[id],
              status,
              reason: '$id $field delta $delta',
            );
          }
        }
      });
    }

    test('a changed choice fails unless the reference top-2 gap is within '
        'the probability tolerance', () async {
      for (final (row, choice, status) in [
        ('readme/department', 'sales', 'FAIL'),
        ('squeeze/plan', 'plan_2', 'PASS'),
      ]) {
        final engine = FakeDecisionEngine()
          ..answerRow = row
          ..perturb = ((answer) => answer['choice'] = choice);
        final report = (await _run(engine)).report;
        expect(_statuses(report)['D04.answers'], status, reason: row);
        expect(_statuses(report)['D05.batch'], status, reason: row);
      }
    });
  });

  test('tokenizer, usage, key order and type mismatches fail', () async {
    final tokens = FakeDecisionEngine()
      ..wrongTokenText = (_reference['pieces'] as Map).keys.first as String;
    final tokenReport = (await _run(tokens)).report;
    expect(_case(tokenReport, 'D02.tokenizer')['status'], 'FAIL');
    expect(_case(tokenReport, 'D02.tokenizer')['mismatch_count'], 1);
    final allTokens = FakeDecisionEngine()..wrongTokenText = '*';
    final tokenizer = _case((await _run(allTokens)).report, 'D02.tokenizer');
    expect(tokenizer['mismatch_count'], 97);
    expect(tokenizer['first_mismatches'], hasLength(5));

    final usage = FakeDecisionEngine()..usageOffset = 1;
    final usageReport = (await _run(usage)).report;
    expect(_statuses(usageReport)['D04.answers'], 'FAIL');
    expect(_statuses(usageReport)['D05.batch'], 'FAIL');

    final order = FakeDecisionEngine()
      ..answerRow = 'readme/department'
      ..perturb = ((answer) {
        final probabilities = answer['probabilities'] as Map;
        answer['probabilities'] = Map.fromEntries(
          probabilities.entries.toList().reversed,
        );
      });
    expect(_statuses((await _run(order)).report)['D04.answers'], 'FAIL');

    final type = FakeDecisionEngine()
      ..answerRow = 'readme/refund'
      ..perturb = ((answer) => answer['type'] = 'choice');
    expect(_statuses((await _run(type)).report)['D04.answers'], 'FAIL');
  });

  test('non-finite logits fail and still journal', () async {
    final engine = FakeDecisionEngine()
      ..logitRow = 'readme/department'
      ..logitOffset = double.nan;
    final result = await _run(engine);
    final record = _case(result.report, 'D03.logits');
    expect(record['status'], 'FAIL');
    expect(record['worst_logit_diff'], {
      'value': 'Infinity',
      'row': 'readme/department',
    });
  });

  test('head placement must match the profile backend', () async {
    expect(
      _statuses(
        (await _run(FakeDecisionEngine(device: 'MTL0'))).report,
      )['D01.head'],
      'FAIL',
    );
    final metal = _profile('metal');
    for (final (device, backend, status) in [
      ('MTL0', 'Metal', 'PASS'),
      ('CPU', 'Metal', 'FAIL'),
      ('MTL0', 'CPU', 'FAIL'),
    ]) {
      final report = (await _run(
        FakeDecisionEngine(device: device, backendName: backend),
        profile: metal,
      )).report;
      expect(_statuses(report)['D01.head'], status, reason: '$device $backend');
    }
  });

  test('a WebGPU profile needs a WebGPU head', () async {
    final webgpu = _profile('webgpu');
    for (final (device, backend, status) in [
      ('WebGPU: WebGPU', 'WebGPU, CPU', 'PASS'),
      ('CPU', 'WebGPU, CPU', 'FAIL'),
      ('WebGPU: WebGPU', 'WASM (Prototype bridge)', 'FAIL'),
    ]) {
      final report = (await _run(
        FakeDecisionEngine(device: device, backendName: backend),
        profile: webgpu,
      )).report;
      expect(_statuses(report)['D01.head'], status, reason: '$device $backend');
    }
  });

  test('WebGPU profiles run only on the Web host, which runs no other '
      'decision profile', () async {
    Matcher rejects(String message) => throwsA(
      isA<LlamaUnsupportedException>().having(
        (error) => error.message,
        'message',
        contains(message),
      ),
    );
    final webgpu = _profile('webgpu');
    expect(webgpu.requireRunnable, rejects('only in the Web'));
    webgpu.requireRunnable(web: true);
    for (final backend in ['cpu', 'metal', 'vulkan', 'cuda']) {
      final profile = _profile(backend)..requireRunnable();
      expect(
        () => profile.requireRunnable(web: true),
        rejects('cross_platform_validation.md#decision-profiles'),
      );
    }
    ValidationProfile.fromJson(
      jsonDecode(File('assets/profiles/tiny-gguf-cpu.json').readAsStringSync())
          as Map<String, dynamic>,
    ).requireRunnable(web: true);
    expect(
      () => PublicValidationEngine(
        engineFactory: () => fail('created an engine'),
      ).load('model.gguf', webgpu),
      rejects('only in the Web'),
    );
    expect(
      () => prepareModel(webgpu, Directory.systemTemp),
      rejects('only in the Web'),
    );
  });

  test('an unsupported model fails D01 and errors later cases', () async {
    final engine = FakeDecisionEngine()..supported = false;
    final statuses = _statuses((await _run(engine)).report);
    expect(statuses['D01.head'], 'FAIL');
    expect(statuses['D04.answers'], 'ERROR');
    expect(statuses['D05.batch'], 'ERROR');
  });

  test('lifecycle and guard cases fail without typed rejections', () async {
    for (final (change, id) in <(void Function(FakeDecisionEngine), String)>[
      ((engine) => engine.disposedRejects = false, 'D06.reload'),
      ((engine) => engine.unloadRejects = false, 'D06.reload'),
      ((engine) => engine.missingHeadRejects = false, 'D07.guards'),
      ((engine) => engine.invalidInputRejects = false, 'D07.guards'),
    ]) {
      final engine = FakeDecisionEngine();
      change(engine);
      expect(_statuses((await _run(engine)).report)[id], 'FAIL');
    }
  });

  test('a missing or altered reference errors every decision case', () async {
    for (final reference in [
      '',
      _referenceText.replaceFirst('0.9653', '0.9654'),
    ]) {
      final statuses = _statuses(
        (await _run(FakeDecisionEngine(), reference: reference)).report,
      );
      expect(statuses['C01.load'], 'PASS');
      for (final id in _decisionIds) {
        expect(statuses[id], 'ERROR', reason: id);
      }
    }
  });

  test(
    'an engine without the decision adapter errors decision cases',
    () async {
      final statuses = _statuses((await _run(_LoadOnlyEngine())).report);
      expect(statuses['C01.load'], 'PASS');
      expect(statuses['D02.tokenizer'], 'PASS');
      for (final id in _decisionIds.where((id) => id != 'D02.tokenizer')) {
        expect(statuses[id], 'ERROR', reason: id);
      }
    },
  );

  test('provenance requires the verified head lock', () async {
    final profile = _profile();
    for (final preparation in [
      {..._preparation(profile)}..remove('decision_head'),
      {
        ..._preparation(profile),
        'decision_head': {
          'verified': true,
          'sha256': List.filled(64, 'c').join(),
          'bytes': 106052840,
        },
      },
      {
        ..._preparation(profile),
        'decision_head': {
          ...(_preparation(profile)['decision_head'] as Map),
          'verified': false,
        },
      },
    ]) {
      final report = (await _run(
        FakeDecisionEngine(),
        preparation: preparation,
      )).report;
      expect(
        report.provenanceProblems,
        contains(
          'Verified decision head hash and byte size do not match the profile lock',
        ),
      );
      expect(report.qualified, isFalse);
    }
  });

  group('GPU placement', () {
    String log({int offloads = 2, int buffers = 6}) => [
      for (var i = 0; i < offloads; i++)
        'load_tensors: offloaded 29/29 layers to GPU',
      for (var i = 0; i < buffers; i++)
        'sched_reserve:       MTL0 compute buffer size =    22.44 MiB',
    ].join('\n');

    Future<ValidationReport> metal({
      String device = 'MTL0',
      String? nativeLog,
    }) async => (await _run(
      FakeDecisionEngine(device: device, backendName: 'Metal'),
      profile: _profile('metal'),
      nativeLog: nativeLog ?? log(),
    )).report;

    test('counts model loads and every successful head load', () async {
      final report = await metal();
      expect(report.placement['verified'], isTrue);
      expect(report.placement['expected_loads'], 2);
      expect(report.qualified, isTrue);
    });

    test('missing or extra records cannot verify placement', () async {
      for (final nativeLog in [
        log(buffers: 5),
        log(buffers: 7),
        log(offloads: 1),
        log(offloads: 3),
      ]) {
        expect(
          (await metal(nativeLog: nativeLog)).placement['verified'],
          isFalse,
          reason: nativeLog,
        );
      }
    });

    test('a head on the CPU cannot verify placement', () async {
      final report = await metal(device: 'CPU');
      expect(report.placement['verified'], isFalse);
      expect(
        report.placement['reason'],
        'decision head placement evidence incomplete',
      );
    });

    test('the native log of an iPhone XCTest run verifies Metal', () {
      const fixtures = 'test/fixtures/ios_xctest/decision-gguf-metal';
      final events = [
        for (final line in File('$fixtures.events.jsonl').readAsLinesSync())
          jsonDecode(line) as Map<String, dynamic>,
      ];
      final cases = events.where((event) => event['type'] == 'case').toList();
      final nativeLog = File('$fixtures.native.txt').readAsStringSync();
      final placement = inspectPlacement(events.first, cases, nativeLog);
      expect(placement['verified'], isTrue, reason: '$placement');
      expect(placement['offload_records'], [
        'load_tensors: offloaded 29/29 layers to GPU',
        'load_tensors: offloaded 29/29 layers to GPU',
      ]);
      expect(inspectPlacement(events.first, cases, null)['verified'], isFalse);
    });

    test('schema-1 decision journals cannot verify placement', () {
      final manifest = <String, dynamic>{
        'schema_version': 1,
        'profile': _profile('metal').toJson(),
      };
      expect(inspectPlacement(manifest, const [], log())['verified'], isFalse);
    });
  });

  group('decision asset preparation', () {
    late Directory cache;
    final head = utf8.encode('head bytes');
    final config = utf8.encode('{"max_len": 512}');
    late ValidationProfile profile;

    setUp(() {
      cache = Directory.systemTemp.createTempSync('decision-assets-');
      final json = _profileJson('cpu');
      Map<String, dynamic> lock(String name, List<int> bytes) => {
        'filename': name,
        'revision': 'ce2afdc0a8766af56a29a22dcf4a781e1f5c7d3c',
        'url':
            'https://huggingface.co/fr0stbit3/laya-gguf/resolve/'
            'ce2afdc0a8766af56a29a22dcf4a781e1f5c7d3c/$name',
        'sha256': sha256.convert(bytes).toString(),
        'bytes': bytes.length,
      };
      json['decision'] = {
        'head': lock('laya-head.safetensors', head),
        'config': lock('rl_agent_config.json', config),
      };
      profile = ValidationProfile.fromJson(json);
    });
    tearDown(() => cache.deleteSync(recursive: true));

    test('downloads, verifies and reports every locked file', () async {
      final requested = <String>[];
      final progress = <Map<String, dynamic>>[];
      final prepared = await prepareDecisionAssets(
        profile,
        cache,
        client: () => MockClient((request) async {
          requested.add(request.url.pathSegments.last);
          return http.Response.bytes(
            request.url.path.endsWith('.json') ? config : head,
            200,
          );
        }),
        onProgress: (event) async => progress.add(event),
      );
      expect(requested, ['laya-head.safetensors', 'rl_agent_config.json']);
      expect(File(prepared.head).readAsBytesSync(), head);
      expect(File(prepared.config!).readAsBytesSync(), config);
      expect(prepared.evidence.keys, ['decision_head', 'decision_config']);
      expect(
        prepared.evidence['decision_head'],
        containsPair('verified', true),
      );
      expect(progress.map((event) => event['artifact']).toSet(), {
        'decision_head',
        'decision_config',
      });
      expect(
        progress.every((event) => !'$event'.contains('huggingface')),
        isTrue,
      );
    });

    test('rejects a file that does not match its lock', () async {
      await expectLater(
        prepareDecisionAssets(
          profile,
          cache,
          client: () => MockClient(
            (_) async => http.Response.bytes(utf8.encode('x'), 200),
          ),
        ),
        throwsFormatException,
      );
    });
  });
}

class _LoadOnlyEngine implements ValidationEngine {
  final _delegate = FakeDecisionEngine();

  @override
  bool get isWeb => false;

  @override
  Future<void> load(String location, ValidationProfile profile) =>
      _delegate.load(location, profile);

  @override
  Future<void> unload() => _delegate.unload();

  @override
  Future<void> dispose() => _delegate.dispose();

  @override
  void cancel() {}

  @override
  Future<Map<String, dynamic>> diagnostics() => _delegate.diagnostics();

  @override
  Future<List<int>> tokenize(String text) => _delegate.tokenize(text);

  @override
  Future<String> detokenize(List<int> tokens) => _delegate.detokenize(tokens);

  @override
  Future<Map<String, dynamic>> generate(
    String prompt,
    ValidationProfile profile, {
    bool raw = false,
    int? maxTokens,
    int? streamBatchTokens,
    int? streamBatchBytes,
    bool cancelAfterFirst = false,
    bool cancelOnListen = false,
    int? cancelAfterMs,
    List<LlamaChatMessage>? history,
    List<String>? stopSequences,
    bool? enableThinking,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    String? grammar,
  }) => _delegate.generate(prompt, profile);

  @override
  Future<Map<String, dynamic>> generateOverlapping(
    String first,
    String second,
    ValidationProfile profile, {
    required bool raw,
    required int firstMaxTokens,
    required bool cancelFirst,
    int? secondAfterMs,
  }) => _delegate.generateOverlapping(
    first,
    second,
    profile,
    raw: raw,
    firstMaxTokens: firstMaxTokens,
    cancelFirst: cancelFirst,
  );
}
