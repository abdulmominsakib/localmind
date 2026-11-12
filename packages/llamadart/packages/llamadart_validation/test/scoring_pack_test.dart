import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart_validation/llamadart_validation.dart';
import 'package:llamadart_validation/src/scoring_evidence.dart';
import 'package:test/test.dart';

import 'validation_test.dart' as harness;

const cpuDiagnostics = {
  'backend_name': 'CPU',
  'context_size': 256,
  'reported_gpu_layers': 0,
};
const caseIds = [
  'N01.capability',
  'N02.top_k',
  'N03.candidates',
  'N04.reuse',
  'N05.guards',
];

ValidationProfile profile([String id = 'scoring-gguf-cpu']) =>
    ValidationProfile.fromJson(
      jsonDecode(File('assets/profiles/$id.json').readAsStringSync())
          as Map<String, dynamic>,
    );

/// Deterministic softmax-shaped scores; [fault] breaks one public contract.
class ScoringEngine extends harness.FakeEngine
    implements StateValidationEngine {
  @override
  Future<LlamaStateIdentity> stateIdentity() async =>
      throw LlamaUnsupportedException('Identity outside this fake');

  String? fault;
  bool supported = true;
  Map<String, dynamic> diagnosticsValue = {...cpuDiagnostics};
  bool primed = false;

  @override
  bool get supportsStatePersistence => false;
  @override
  bool get supportsNextTokenScoring => supported;
  @override
  Future<Map<String, dynamic>> diagnostics() async => {...diagnosticsValue};

  int count(String text) => text.endsWith(' the wooden box')
      ? 62
      : text.startsWith(
          'Once upon a time there was a little girl named Lily. L',
        )
      ? 59
      : text.startsWith('Once')
      ? 40
      : 9;

  @override
  Future<List<int>> tokenizeStatePrompt(String text) async => [
    for (var i = 0; i < (fault == 'short_tokens' ? 3 : count(text)); i++) i,
  ];

  @override
  Future<Map<String, dynamic>> scoreStatePrompt(
    String text, {
    List<int> candidates = const [],
    int topK = 0,
    required bool reuse,
  }) async {
    if (!supported) {
      if (fault == 'unsupported_wrong_type') throw StateError('Scoring failed');
      throw LlamaUnsupportedException('Scoring unsupported');
    }
    if (fault == 'accepts_empty' && text.isEmpty) return {};
    if (text.isEmpty || topK < 0 || candidates.any((id) => id < 0)) {
      throw ArgumentError('invalid scoring request');
    }
    if (candidates.isEmpty && topK == 0) throw ArgumentError('empty request');
    final shift = text.hashCode % 7 * 0.01;
    final drift = reuse && fault == 'reuse_drift' ? 0.5 : 0.0;
    Map<String, dynamic> row(int id) => {
      'token': id,
      'logprob': -(id + 1) - shift - drift,
    };
    var ids = [for (var i = 0; i < topK; i++) i];
    if (fault == 'unsorted' && ids.length > 2) {
      ids = [ids[1], ids[0], ...ids.skip(2)];
    }
    if (fault == 'duplicate_top' && ids.length > 2) ids[1] = ids[0];
    return {
      'prompt_tokens': fault == 'prompt_tokens' ? 1 : count(text),
      'candidates': [
        for (final id in candidates.reversed.take(fault == 'order' ? 99 : 0))
          row(id),
        if (fault != 'order')
          for (final id in candidates) row(id),
      ],
      'top': [for (final id in ids) row(id)],
    };
  }

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
  }) async {
    final result = await super.generate(
      prompt,
      profile,
      raw: raw,
      maxTokens: maxTokens,
      streamBatchTokens: streamBatchTokens,
      streamBatchBytes: streamBatchBytes,
      cancelAfterFirst: cancelAfterFirst,
      cancelOnListen: cancelOnListen,
      cancelAfterMs: cancelAfterMs,
      history: history,
      stopSequences: stopSequences,
      enableThinking: enableThinking,
      tools: tools,
      toolChoice: toolChoice,
      grammar: grammar,
    );
    if (fault == 'recovery_incomplete') result['stream_completed'] = false;
    if (fault == 'recovery_empty') result['content'] = '';
    return result;
  }

  @override
  Future<bool> saveState(String path, List<int> tokens) =>
      throw UnimplementedError();
  @override
  Future<List<int>> loadState(String path, int capacity) =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> generateStatePrompt(
    String text, {
    required bool reuse,
  }) => throw UnimplementedError();
}

Future<List<Map<String, dynamic>>> runScoring({
  String? fault,
  ValidationProfile? selected,
  bool spi = true,
  bool supported = true,
}) async {
  final target = selected ?? profile();
  final engine = ScoringEngine()
    ..fault = fault
    ..supported = supported;
  if (target.runtime == 'litert') {
    engine.diagnosticsValue = {'backend_name': 'LiteRT-LM CPU'};
  }
  final events = <Map<String, dynamic>>[];
  await ValidationRunner(
    profile: target,
    engine: spi ? engine : harness.FakeEngine(),
    emit: (event) async => events.add(event),
  ).run(
    'model.gguf',
    runId: 'scoring-test',
    environment: {
      'source_commit': 'a' * 40,
      'source_dirty': false,
      'hook_sha256': 'b' * 64,
      'native_tag': 'v0.7.0-2',
    },
    preparation: {
      'verified': true,
      'sha256': target.modelHash,
      'bytes': target.model['bytes'],
    },
  );
  return events;
}

Map<String, dynamic> record(List<Map<String, dynamic>> events, String id) =>
    events.firstWhere((e) => e['case_id'] == id && e['type'] == 'case');
List<Map<String, dynamic>> copy(List<Map<String, dynamic>> events) =>
    (jsonDecode(jsonEncode(events)) as List).cast<Map<String, dynamic>>();
ValidationReport report(List<Map<String, dynamic>> events) =>
    ValidationReport.parse(events.map(jsonEncode).join('\n'));

class _ScoringBackend implements LlamaBackend, BackendNextTokenScoring {
  bool? reuse;
  List<int>? candidates;
  @override
  bool get supportsUrlLoading => false;
  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}
  @override
  Future<int> modelLoad(String path, ModelParams params) async => 1;
  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async => 1;
  @override
  Future<void> contextFree(int handle) async {}
  @override
  Future<void> modelFree(int handle) async {}
  @override
  Future<void> dispose() async {}
  @override
  void cancelGeneration() {}
  @override
  Future<int> getContextSize(int handle) async => 256;
  @override
  Future<Map<String, String>> modelMetadata(int handle) async => {};
  @override
  Future<LlamaNextTokenScores> scoreNextToken(
    int contextHandle,
    String prompt, {
    required List<int> candidates,
    required int topK,
    required bool reusePromptPrefix,
  }) async {
    reuse = reusePromptPrefix;
    this.candidates = candidates;
    LlamaTokenLogprob score(int id) => LlamaTokenLogprob(
      token: id,
      bytes: [65 + id],
      logprob: -math.log(id + 2),
    );
    return LlamaNextTokenScores(
      candidates: candidates.map(score).toList(),
      top: [for (var i = 0; i < topK; i++) score(i)],
      promptTokens: prompt.length,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('catalog 13 selects the pack and earlier catalogs omit it', () {
    final selected = profile();
    expect(selected.caseIds, containsAll(caseIds));
    expect(() => selected.catalogForVersion(12), throwsFormatException);
    final tiny = profile('tiny-gguf-cpu');
    for (var version = 1; version <= 12; version++) {
      final catalog = tiny.catalogForVersion(version);
      expect(catalog['features'], isNot(contains('next_token_scoring')));
      expect(catalog['fixtures'], isNot(contains('next_token_scoring')));
      expect(
        tiny.caseIdsForCatalog(version).any((id) => id.startsWith('N')),
        false,
      );
    }
  });

  test('only the CPU native profile runs more than the capability case', () {
    for (final name in ['chat-gguf-metal', 'chat-litert-cpu']) {
      final data = profile(name).toJson()
        ..['selection'] = 'focused'
        ..['focus_features'] = ['next_token_scoring'];
      final selected = ValidationProfile.fromJson(data);
      expect(selected.caseIds.where((id) => id.startsWith('N')), [
        'N01.capability',
      ]);
      final omitted = (selected.catalog['cases'] as List)
          .cast<Map>()
          .singleWhere((c) => c['id'] == 'N02.top_k');
      expect(
        omitted['omission_reason'],
        'outside_initial_native_cpu_scoring_scope',
      );
    }
  });

  test('a profile cannot override the shared scoring fixture', () {
    final data = profile().toJson();
    (data['fixtures'] as Map)['next_token_scoring'] = {'prefix': 'other'};
    expect(() => ValidationProfile.fromJson(data), throwsFormatException);
  });

  test(
    'complete model-free proof passes and the importer rechecks it',
    () async {
      final events = await runScoring();
      for (final id in caseIds) {
        expect(
          record(events, id)['status'],
          'PASS',
          reason: jsonEncode(record(events, id)),
        );
      }
      expect(report(events).problems, isEmpty);
    },
  );

  test('each broken scoring contract fails its own case', () async {
    const expected = {
      'unsorted': 'N02.top_k',
      'duplicate_top': 'N02.top_k',
      'prompt_tokens': 'N02.top_k',
      'short_tokens': 'N02.top_k',
      'order': 'N03.candidates',
      'reuse_drift': 'N04.reuse',
      'accepts_empty': 'N05.guards',
    };
    for (final entry in expected.entries) {
      final events = await runScoring(fault: entry.key);
      final failed = [
        for (final id in caseIds)
          if (record(events, id)['status'] != 'PASS') id,
      ];
      expect(failed, contains(entry.value), reason: entry.key);
      expect(report(events).qualified, false, reason: entry.key);
    }
  });

  test('unsupported LiteRT runtime must reject typed and recover', () async {
    final litert = ValidationProfile.fromJson(
      (profile('chat-litert-cpu').toJson()
        ..['selection'] = 'focused'
        ..['focus_features'] = ['next_token_scoring']),
    );
    final events = await runScoring(selected: litert, supported: false);
    final capability = record(events, 'N01.capability');
    expect(capability['status'], 'PASS', reason: jsonEncode(capability));
    expect(capability['rejection'], 'LlamaUnsupportedException');
    final lying = await runScoring(selected: litert, supported: true);
    expect(record(lying, 'N01.capability')['status'], 'FAIL');
  });

  for (final fault in [
    'unsupported_wrong_type',
    'recovery_incomplete',
    'recovery_empty',
  ]) {
    test('LiteRT capability fails on $fault', () async {
      final events = await runScoring(
        selected: profile('scoring-litert-cpu'),
        supported: false,
        fault: fault,
      );
      final capability = record(events, 'N01.capability');
      expect(capability['status'], 'FAIL', reason: jsonEncode(capability));
      expect(
        capability['rejection'],
        fault == 'unsupported_wrong_type'
            ? 'StateError'
            : 'LlamaUnsupportedException',
      );
      final recovery = capability['recovery'] as Map;
      expect(recovery['stream_completed'], fault != 'recovery_incomplete');
      expect(
        recovery['content'],
        fault == 'recovery_empty' ? isEmpty : isNotEmpty,
      );
      expect(report(events).qualified, false);
    });
  }

  test(
    'missing adapter, unqualified host and false support stay honest',
    () async {
      expect(
        record(await runScoring(spi: false), 'N02.top_k')['reason'],
        'scoring_adapter_unavailable',
      );
      final unqualified = ScoringEngine()
        ..diagnosticsValue = {...cpuDiagnostics, 'backend_name': 'Metal'};
      final events = <Map<String, dynamic>>[];
      await ValidationRunner(
        profile: profile(),
        engine: unqualified,
        emit: (event) async => events.add(event),
      ).run(
        'model.gguf',
        runId: 'unqualified',
        environment: {
          'source_commit': 'a' * 40,
          'source_dirty': false,
          'hook_sha256': 'b' * 64,
          'native_tag': 'v0.7.0-2',
        },
        preparation: {
          'verified': true,
          'sha256': profile().modelHash,
          'bytes': profile().model['bytes'],
        },
      );
      expect(record(events, 'N02.top_k')['status'], 'NOT_RUN');
      final unsupported = await runScoring(supported: false);
      expect(record(unsupported, 'N02.top_k')['status'], 'FAIL');
    },
  );

  test('importer rejects forged scoring evidence', () async {
    final events = await runScoring();
    final mutations = <String, (String, void Function(Map<String, dynamic>))>{
      'forged capability': ('N01.capability', (e) => e['supported'] = false),
      'other model': ('N02.top_k', (e) => e['model_sha256'] = 'f' * 64),
      'other config': ('N02.top_k', (e) => e['config_hash'] = 'f' * 64),
      'missing trial': ('N02.top_k', (e) => (e['trials'] as List).removeLast()),
      'changed prompt': ('N02.top_k', (e) => e['trials'][0]['prompt'] = 'x'),
      'positive logprob': (
        'N02.top_k',
        (e) => e['trials'][0]['first']['top'][0]['logprob'] = 0.1,
      ),
      'probability mass': (
        'N02.top_k',
        (e) {
          for (final key in ['first', 'repeat']) {
            for (final row in e['trials'][0][key]['top'] as List) {
              row['logprob'] = -0.01;
            }
          }
        },
      ),
      'unstable repeat order': (
        'N02.top_k',
        (e) => e['trials'][0]['repeat']['top'][0]['token'] = 99,
      ),
      'nondeterministic repeat': (
        'N02.top_k',
        (e) => e['trials'][0]['repeat']['top'][0]['logprob'] -= 0.5,
      ),
      'prompt token count': (
        'N02.top_k',
        (e) => e['trials'][0]['first']['prompt_tokens'] += 1,
      ),
      'candidate id': (
        'N03.candidates',
        (e) => e['candidates_only']['candidates'][0]['token'] = 77,
      ),
      'candidate mismatch': (
        'N03.candidates',
        (e) => e['candidates_only']['candidates'][1]['logprob'] -= 0.5,
      ),
      'outsider beats top': (
        'N03.candidates',
        (e) {
          for (final key in ['candidates_only', 'combined']) {
            e[key]['candidates'].last['logprob'] = -0.001;
          }
        },
      ),
      'candidates-only top': (
        'N03.candidates',
        (e) => e['candidates_only']['top'] = e['baseline']['top'],
      ),
      'reuse drift': (
        'N04.reuse',
        (e) => e['reused']['candidates'][0]['logprob'] -= 0.5,
      ),
      'no common prefix': ('N04.reuse', (e) => e['full_tokens'][0] = 999),
      'accepted guard': (
        'N05.guards',
        (e) => e['rejections']['empty_prompt'] = 'accepted',
      ),
      'wrong guard type': (
        'N05.guards',
        (e) => e['rejections']['negative_top_k'] = 'StateError',
      ),
      'recovery drift': (
        'N05.guards',
        (e) => e['recovery']['top'][0]['logprob'] -= 0.5,
      ),
    };
    for (final entry in mutations.entries) {
      final forged = copy(events);
      entry.value.$2(record(forged, entry.value.$1));
      final result = report(forged);
      expect(
        result.problems,
        contains('Invalid scoring case evidence: ${entry.value.$1}'),
        reason: entry.key,
      );
      expect(result.qualified, false, reason: entry.key);
    }
  });

  test(
    'adapter reaches the real engine guards and forwards arguments',
    () async {
      final directory = await Directory.systemTemp.createTemp('scoring-pack-');
      final model = File('${directory.path}/model.gguf')..writeAsBytesSync([1]);
      final backend = _ScoringBackend();
      final adapter = PublicValidationEngine(
        engineFactory: () => LlamaEngine(backend),
      );
      try {
        await adapter.load(model.path, profile());
        expect(adapter.supportsNextTokenScoring, true);
        final scored = await adapter.scoreStatePrompt(
          'abc',
          candidates: [4],
          topK: 2,
          reuse: false,
        );
        expect(backend.reuse, false);
        expect(backend.candidates, [4]);
        expect(scored['prompt_tokens'], 3);
        expect((scored['top'] as List).length, 2);
        for (final call in <Future<Object?> Function()>[
          () => adapter.scoreStatePrompt('', topK: 1, reuse: false),
          () => adapter.scoreStatePrompt('a', candidates: [-1], reuse: false),
          () => adapter.scoreStatePrompt('a', topK: -1, reuse: false),
          () => adapter.scoreStatePrompt('a', reuse: false),
        ]) {
          await expectLater(call(), throwsArgumentError);
        }
      } finally {
        await adapter.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  group('oracle gates', () {
    Map<String, dynamic> capability(bool supported, {bool web = false}) => {
      'web': web,
      'supported': supported,
      'diagnostics': {...cpuDiagnostics},
    };
    bool accepts(
      ValidationProfile target,
      Map<String, dynamic> data, {
      bool web = false,
      Map? diagnostics,
    }) => validScoringCaseEvidence(
      'N01.capability',
      data,
      target,
      web: web,
      diagnostics: diagnostics ?? data['diagnostics'] as Map,
    );

    test('only the sealed native CPU configuration expects support', () {
      expect(accepts(profile(), capability(true)), true);
      expect(accepts(profile(), capability(false)), false);
    });

    test('web never expects support', () {
      expect(accepts(profile(), capability(true, web: true), web: true), false);
    });

    test('each diagnostic and profile field gates the expectation', () {
      for (final key in [
        'backend_name',
        'context_size',
        'reported_gpu_layers',
      ]) {
        final data = capability(true);
        (data['diagnostics'] as Map)[key] = key == 'backend_name'
            ? 'Metal'
            : key == 'context_size'
            ? 512
            : 1;
        expect(accepts(profile(), data), false, reason: key);
      }
      final unfocused = ValidationProfile.fromJson(
        profile().toJson()
          ..['selection'] = 'quick'
          ..remove('focus_features'),
      );
      expect(accepts(unfocused, capability(true)), false);
    });

    test('LiteRT is expected unsupported only under its own backend name', () {
      final litert = ValidationProfile.fromJson(
        profile('scoring-litert-cpu').toJson(),
      );
      final data = {
        'web': false,
        'supported': false,
        'diagnostics': {'backend_name': 'LiteRT-LM CPU'},
        'rejection': 'LlamaUnsupportedException',
        'recovery': {'stream_completed': true, 'content': 'hello'},
      };
      expect(accepts(litert, data), true);
      final other = {
        ...data,
        'diagnostics': {'backend_name': 'CPU'},
      };
      expect(accepts(litert, other), false);
    });

    test('LiteRT rejection must be typed and followed by a recovery', () {
      final litert = ValidationProfile.fromJson(
        profile('scoring-litert-cpu').toJson(),
      );
      final data = <String, dynamic>{
        'web': false,
        'supported': false,
        'diagnostics': {'backend_name': 'LiteRT-LM CPU'},
        'rejection': 'LlamaUnsupportedException',
        'recovery': {'stream_completed': true, 'content': 'hello'},
      };
      final broken = <String, void Function(Map<String, dynamic>)>{
        'rejection': (e) => e['rejection'] = 'StateError',
        'no recovery': (e) => e['recovery'] = null,
        'stream': (e) => (e['recovery'] as Map)['stream_completed'] = false,
        'empty content': (e) => (e['recovery'] as Map)['content'] = '',
        'missing content': (e) => (e['recovery'] as Map).remove('content'),
      };
      for (final entry in broken.entries) {
        final copy = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
        entry.value(copy);
        expect(accepts(litert, copy), false, reason: entry.key);
      }
    });

    test(
      'record must match the manifest web flag and load diagnostics',
      () async {
        final events = copy(await runScoring());
        final data = record(events, 'N02.top_k');
        bool check({required bool web, required Map diagnostics}) =>
            validScoringCaseEvidence(
              'N02.top_k',
              data,
              profile(),
              web: web,
              diagnostics: diagnostics,
            );
        expect(check(web: false, diagnostics: cpuDiagnostics), true);
        expect(check(web: true, diagnostics: cpuDiagnostics), false);
        expect(
          check(
            web: false,
            diagnostics: {...cpuDiagnostics, 'context_size': 512},
          ),
          false,
        );
      },
    );
  });

  group('validator predicates', () {
    final forgeries = <String, (String, void Function(Map<String, dynamic>))>{
      'candidates-only prompt tokens': (
        'N03.candidates',
        (e) => e['candidates_only']['prompt_tokens'] += 1,
      ),
      'combined top shape': (
        'N03.candidates',
        (e) => (e['combined']['top'] as List).removeLast(),
      ),
      'combined top ids differ from baseline': (
        'N03.candidates',
        (e) => e['combined']['top'][0]['token'] = 99,
      ),
      'combined top scores differ from baseline': (
        'N03.candidates',
        (e) => e['combined']['top'][0]['logprob'] -= 0.5,
      ),
      'prime prompt tokens': (
        'N04.reuse',
        (e) => e['prime']['prompt_tokens'] += 1,
      ),
      'reused prompt tokens': (
        'N04.reuse',
        (e) => e['reused']['prompt_tokens'] += 1,
      ),
      'first carries candidates': (
        'N02.top_k',
        (e) => e['trials'][0]['first']['candidates'] = [
          e['trials'][0]['first']['top'][0],
        ],
      ),
      'repeat carries candidates': (
        'N02.top_k',
        (e) => e['trials'][0]['repeat']['candidates'] = [
          e['trials'][0]['repeat']['top'][0],
        ],
      ),
      'too few N02 tokens': (
        'N02.top_k',
        (e) {
          final trial = e['trials'][0];
          trial['tokens'] = (trial['tokens'] as List).take(7).toList();
          trial['first']['prompt_tokens'] = 7;
          trial['repeat']['prompt_tokens'] = 7;
        },
      ),
      'too few N03 tokens': (
        'N03.candidates',
        (e) {
          e['tokens'] = (e['tokens'] as List).take(7).toList();
          for (final key in ['baseline', 'candidates_only', 'combined']) {
            e[key]['prompt_tokens'] = 7;
          }
        },
      ),
      'too few N05 tokens': (
        'N05.guards',
        (e) {
          e['tokens'] = (e['tokens'] as List).take(7).toList();
          for (final key in ['baseline', 'recovery']) {
            e[key]['prompt_tokens'] = 7;
          }
        },
      ),
    };

    for (final entry in forgeries.entries) {
      test('importer rejects: ${entry.key}', () async {
        final forged = copy(await runScoring());
        entry.value.$2(record(forged, entry.value.$1));
        expect(
          report(forged).problems,
          contains('Invalid scoring case evidence: ${entry.value.$1}'),
        );
      });
    }

    test('N04 rejects fewer than eight shared tokens', () async {
      final forged = copy(await runScoring());
      final e = record(forged, 'N04.reuse');
      for (var i = 7; i < (e['prefix_tokens'] as List).length; i++) {
        e['full_tokens'][i] = 1000 + i;
      }
      expect(
        report(forged).problems,
        contains('Invalid scoring case evidence: N04.reuse'),
      );
    });

    test('the fixture probability-mass bound is the one enforced', () async {
      final events = await runScoring();
      final strict = _FixtureProfile(profile(), {'max_probability_mass': 0.5});
      expect(
        validScoringCaseEvidence(
          'N02.top_k',
          record(events, 'N02.top_k'),
          strict,
          web: false,
          diagnostics: cpuDiagnostics,
        ),
        false,
      );
    });

    test('N03 combined top enforces its own probability-mass bound', () async {
      final events = await runScoring();
      final evidence = record(events, 'N03.candidates');
      final baseline = evidence['baseline']['top'] as List;
      final mass = baseline.fold<double>(
        0,
        (sum, row) => sum + math.exp((row['logprob'] as num).toDouble()),
      );
      final strict = _FixtureProfile(profile(), {
        'max_probability_mass': mass + 0.0001,
      });
      bool accepts() => validScoringCaseEvidence(
        'N03.candidates',
        evidence,
        strict,
        web: false,
        diagnostics: cpuDiagnostics,
      );
      expect(accepts(), true);
      // Stay within the baseline delta tolerance while crossing the mass bound.
      for (final row in evidence['combined']['top'] as List) {
        row['logprob'] += 0.001;
      }
      expect(accepts(), false);
    });

    test('catalog 12 does not declare the scoring cases', () {
      for (final id in caseIds) {
        expect(catalogDeclaresCase(id, 12), false, reason: id);
        expect(catalogDeclaresCase(id, 13), true, reason: id);
      }
    });
  });

  group('cross-case agreement on the fresh first prompt', () {
    const message = 'Scoring cases disagree on the same fresh prompt';
    final mutations = <String, void Function(List<Map<String, dynamic>>)>{
      'consistently permuted N02 token IDs': (events) {
        for (final key in ['first', 'repeat']) {
          for (final row
              in record(events, 'N02.top_k')['trials'][0][key]['top'] as List) {
            row['token'] += 100;
          }
        }
      },
      'consistently permuted N05 token IDs': (events) {
        final e = record(events, 'N05.guards');
        for (final key in ['baseline', 'recovery']) {
          for (final row in e[key]['top'] as List) {
            row['token'] += 100;
          }
        }
      },
      'N03 tokenizes the same prompt differently': (events) {
        record(events, 'N03.candidates')['tokens'][0] = 500;
      },
      'N05 scores drift from N02': (events) {
        final e = record(events, 'N05.guards');
        for (final key in ['baseline', 'recovery']) {
          e[key]['top'][0]['logprob'] -= 0.5;
        }
      },
    };

    test('a coherent run raises no cross-case problem', () async {
      expect(report(await runScoring()).problems, isNot(contains(message)));
    });

    for (final id in ['N02.top_k', 'N03.candidates', 'N05.guards']) {
      for (final status in ['NOT_RUN', 'FAIL', 'ERROR', 'UNSUPPORTED']) {
        test('excludes $status $id from cross-case agreement', () async {
          final events = copy(await runScoring());
          final excluded = record(events, id)..['status'] = status;
          if (id == 'N02.top_k') {
            excluded['trials'][0]['tokens'][0] = 500;
          } else {
            excluded['tokens'][0] = 500;
          }
          final result = report(events);
          expect(result.problems, isNot(contains(message)));
          expect(result.qualified, false);
          // The same disagreement must be detected when the case passes.
          excluded['status'] = 'PASS';
          expect(report(events).problems, contains(message));
        });
      }
    }

    for (final entry in mutations.entries) {
      test('reports ${entry.key}', () async {
        final forged = copy(await runScoring());
        entry.value(forged);
        expect(report(forged).problems, contains(message));
      });
    }
  });

  group('LiteRT scoring profile', () {
    test('runs only the expected-unsupported capability case', () {
      final litert = profile('scoring-litert-cpu');
      expect(litert.runtime, 'litert');
      expect(litert.caseIds.where((id) => id.startsWith('N')), [
        'N01.capability',
      ]);
    });

    test('is the registry profile for the LiteRT scoring claim', () {
      final registry =
          jsonDecode(File('assets/capability_coverage.json').readAsStringSync())
              as Map;
      final row = (registry['packs'] as List).cast<Map>().singleWhere(
        (c) => c['id'] == 'next_token_scoring',
      );
      expect(
        row['profiles'],
        contains('assets/profiles/scoring-litert-cpu.json'),
      );
      expect(row['notes'], contains('1158'));
    });

    test('a passing run needs the typed rejection', () async {
      final litert = profile('scoring-litert-cpu');
      final events = await runScoring(selected: litert, supported: false);
      expect(record(events, 'N01.capability')['status'], 'PASS');
      expect(report(events).problems, isEmpty);
    });
  });
}

class _FixtureProfile implements ValidationProfile {
  _FixtureProfile(this.inner, this.overrides);
  final ValidationProfile inner;
  final Map<String, Object> overrides;

  @override
  Map<String, dynamic> get fixtures => {
    ...inner.fixtures,
    'next_token_scoring': {
      ...inner.fixtures['next_token_scoring'] as Map,
      ...overrides,
    },
  };
  @override
  String get runtime => inner.runtime;
  @override
  String get backend => inner.backend;
  @override
  Map<String, dynamic> get model => inner.model;
  @override
  int get contextSize => inner.contextSize;
  @override
  int get threads => inner.threads;
  @override
  List<String> get focusFeatures => inner.focusFeatures;
  @override
  Map<String, dynamic> get effectiveConfig => inner.effectiveConfig;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
