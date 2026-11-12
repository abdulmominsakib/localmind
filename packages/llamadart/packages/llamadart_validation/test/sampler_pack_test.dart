import 'dart:convert';
import 'dart:io';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart_validation/llamadart_validation.dart';
import 'package:llamadart_validation/src/sampler_evidence.dart';
import 'package:test/test.dart';

import 'validation_test.dart' as harness;

const cpuDiagnostics = {
  'backend_name': 'CPU',
  'context_size': 256,
  'reported_gpu_layers': 0,
};
const caseIds = [
  'G01.capability',
  'G02.min_p',
  'G03.repeat_penalty',
  'G04.presence_penalty',
  'G05.thinking_budget',
];
const greedy = ' Lily saw a ball. Lily saw a dog. Lily saw a cat.';
const free = ' and she was very happy about it today';

ValidationProfile profile([String id = 'sampler-gguf-cpu']) =>
    ValidationProfile.fromJson(
      jsonDecode(File('assets/profiles/$id.json').readAsStringSync())
          as Map<String, dynamic>,
    );

ValidationProfile focused(String id) => ValidationProfile.fromJson(
  profile(id).toJson()
    ..['selection'] = 'focused'
    ..['focus_features'] = ['sampler_controls'],
);

/// Word-level model of the public sampler semantics; [fault] breaks one.
class SamplerEngine extends harness.FakeEngine
    implements SamplerValidationEngine {
  String? fault;
  Map<String, bool> flags = {
    'penalty': true,
    'presence_penalty': true,
    'min_p': true,
    'thinking_budget': true,
  };
  Map<String, dynamic> diagnosticsValue = {...cpuDiagnostics};
  var penalizedRuns = 0;

  @override
  Future<Map<String, dynamic>> diagnostics() async => {...diagnosticsValue};

  @override
  Future<LlamaEngineCapabilities> samplerCapabilities() async =>
      LlamaEngineCapabilities(
        isSupported: true,
        supportsPenalty: flags['penalty']!,
        supportsPresencePenalty: flags['presence_penalty']!,
        supportsMinP: flags['min_p']! || fault == 'reports_min_p',
        supportsThinkingBudget: flags['thinking_budget']!,
      );

  @override
  Future<String> generateSampled(String prompt, GenerationParams params) async {
    final budget = params.thinkingBudget;
    void reject(String flag, bool requested) {
      if (!requested || flags[flag]! || fault == 'accepts_unsupported') return;
      if (fault == 'unsupported_wrong_type') throw StateError(flag);
      throw LlamaUnsupportedException('$flag unsupported');
    }

    reject('penalty', params.penalty != 1);
    reject('presence_penalty', params.presencePenalty != 0);
    reject('min_p', params.minP != 0);
    reject('thinking_budget', budget != null);
    if (prompt.endsWith('<think>')) {
      final words = free.split(' ').skip(1).toList();
      String take(int n) => n == 0 ? '' : ' ${words.take(n).join(' ')}';
      if (budget == null) {
        return fault == 'free_closes' && params.maxTokens > 4
            ? '$free</think>'
            : take(params.maxTokens);
      }
      if (budget.startTag == null) {
        if (fault == 'untagged_accepted') return free;
        throw ArgumentError('tags required');
      }
      if (fault == 'budget_ignored') return free;
      final prefix = fault == 'budget_late'
          ? take(budget.maxTokens + 1)
          : take(budget.maxTokens);
      return '$prefix ${budget.forcedMessage}${budget.endTag}. More text.';
    }
    if (params.temp > 0) {
      if (params.minP >= 1 && fault != 'min_p_ignored') return greedy;
      return fault == 'control_greedy' ? greedy : ' seed ${params.seed} story.';
    }
    if (params.penalty > 1 && fault != 'penalty_ignored') {
      penalizedRuns++;
      return fault == 'penalty_unstable' && penalizedRuns.isEven
          ? ' Lily saw a ball. Then rain came.'
          : ' Lily saw a ball. Then a dog ran.';
    }
    if (params.presencePenalty > 0) {
      return fault == 'presence_repeats'
          ? '$greedy Lily saw a ball. Lily saw a dog.'
          : ' Lily saw a ball. A dog ran away.';
    }
    return fault == 'baseline_unique' ? ' Lily saw one ball.' : greedy;
  }
}

Future<List<Map<String, dynamic>>> runSampler({
  String? fault,
  ValidationProfile? selected,
  bool adapter = true,
  Map<String, bool>? flags,
  Map<String, dynamic>? diagnostics,
}) async {
  final target = selected ?? profile();
  final engine = SamplerEngine()..fault = fault;
  if (flags != null) engine.flags = flags;
  if (target.runtime == 'litert') {
    engine.diagnosticsValue = {'backend_name': 'LiteRT-LM CPU'};
  }
  if (diagnostics != null) engine.diagnosticsValue = diagnostics;
  final events = <Map<String, dynamic>>[];
  await ValidationRunner(
    profile: target,
    engine: adapter ? engine : harness.FakeEngine(),
    emit: (event) async => events.add(event),
  ).run(
    'model.gguf',
    runId: 'sampler-test',
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

const liteRtFlags = {
  'penalty': true,
  'presence_penalty': false,
  'min_p': false,
  'thinking_budget': false,
};

class _SamplerBackend
    implements LlamaBackend, BackendGenerationCapabilitiesSupport {
  bool minP = true;
  GenerationParams? params;
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
  Future<BackendGenerationCapabilities> generationCapabilities() async =>
      BackendGenerationCapabilities(
        penalty: true,
        presencePenalty: true,
        minP: minP,
        thinkingBudget: true,
      );
  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) {
    this.params = params;
    return Stream.value(utf8.encode(' sampled'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('catalog 15 selects the pack and earlier catalogs omit it', () {
    final selected = profile();
    expect(selected.caseIds, containsAll(caseIds));
    expect(() => selected.catalogForVersion(14), throwsFormatException);
    final tiny = profile('tiny-gguf-cpu');
    for (var version = 1; version <= 14; version++) {
      final catalog = tiny.catalogForVersion(version);
      expect(catalog['features'], isNot(contains('sampler_controls')));
      expect(catalog['fixtures'], isNot(contains('sampler_controls')));
      expect(
        tiny.caseIdsForCatalog(version).any((id) => id.startsWith('G')),
        false,
      );
      expect(catalogDeclaresCase('G01.capability', version), false);
    }
    expect(catalogDeclaresCase('G01.capability', 15), true);
  });

  test('catalog 14 keeps its original hashes', () {
    const hashes = {
      'tiny-gguf-cpu':
          'aaaf748c266a7f3b5e0c80877bca14a455261f2347ccf2f08e9c24634db55d44',
      'state-gguf-cpu':
          '1e58fbdfb80677c7aeff848c1706510ec2ea834c812a503c3664bb5a07eaa607',
      'scoring-gguf-cpu':
          '3eb7afb4ac3809b2c38d1ec501e5d7da86e61e2f77b169ed7c80c6692cb3cd0a',
      'chat-litert-cpu':
          'c6ed22c003634eea5ea686daa89289ecb1b421268f2c4c1ccbd2c646cbb76d20',
    };
    for (final entry in hashes.entries) {
      expect(
        jsonHash(profile(entry.key).catalogForVersion(14)),
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('only the CPU native profile runs more than the capability case', () {
    for (final name in ['chat-gguf-metal', 'chat-litert-cpu']) {
      final selected = focused(name);
      expect(selected.caseIds.where((id) => id.startsWith('G')), [
        'G01.capability',
      ]);
      final omitted = (selected.catalog['cases'] as List)
          .cast<Map>()
          .singleWhere((c) => c['id'] == 'G02.min_p');
      expect(
        omitted['omission_reason'],
        'outside_initial_native_cpu_sampler_scope',
      );
    }
  });

  test('a profile cannot override the shared sampler fixture', () {
    final data = profile().toJson();
    (data['fixtures'] as Map)['sampler_controls'] = {'prompt': 'other'};
    expect(() => ValidationProfile.fromJson(data), throwsFormatException);
  });

  test(
    'complete model-free proof passes and the importer rechecks it',
    () async {
      final events = await runSampler();
      for (final id in caseIds) {
        expect(
          record(events, id)['status'],
          'PASS',
          reason: jsonEncode(record(events, id)),
        );
      }
      expect(record(events, 'G01.capability')['rejections'], isEmpty);
      expect(report(events).problems, isEmpty);
    },
  );

  test('each broken sampler contract fails its own case', () async {
    const expected = {
      'min_p_ignored': 'G02.min_p',
      'control_greedy': 'G02.min_p',
      'penalty_ignored': 'G03.repeat_penalty',
      'penalty_unstable': 'G03.repeat_penalty',
      'presence_repeats': 'G04.presence_penalty',
      'baseline_unique': 'G03.repeat_penalty',
      'budget_ignored': 'G05.thinking_budget',
      'budget_late': 'G05.thinking_budget',
      'free_closes': 'G05.thinking_budget',
      'untagged_accepted': 'G05.thinking_budget',
    };
    for (final entry in expected.entries) {
      final events = await runSampler(fault: entry.key);
      final failed = [
        for (final id in caseIds)
          if (record(events, id)['status'] != 'PASS') id,
      ];
      expect(failed, contains(entry.value), reason: entry.key);
      expect(report(events).qualified, false, reason: entry.key);
    }
  });

  test('LiteRT must reject Min-P typed and recover', () async {
    final litert = focused('chat-litert-cpu');
    final events = await runSampler(selected: litert, flags: liteRtFlags);
    final capability = record(events, 'G01.capability');
    expect(capability['status'], 'PASS', reason: jsonEncode(capability));
    expect(capability['rejections'], {'min_p': 'LlamaUnsupportedException'});
    expect((capability['recovery'] as Map)['content'], isNotEmpty);
    expect(report(events).problems, isEmpty);
    for (final fault in [
      'accepts_unsupported',
      'unsupported_wrong_type',
      'reports_min_p',
    ]) {
      final broken = await runSampler(
        selected: litert,
        flags: liteRtFlags,
        fault: fault,
      );
      expect(record(broken, 'G01.capability')['status'], 'FAIL', reason: fault);
    }
  });

  test(
    'missing adapter, unqualified host and false support stay honest',
    () async {
      expect(
        record(await runSampler(adapter: false), 'G02.min_p')['reason'],
        'sampler_adapter_unavailable',
      );
      final metal = await runSampler(
        diagnostics: {...cpuDiagnostics, 'backend_name': 'Metal'},
      );
      expect(record(metal, 'G02.min_p')['status'], 'NOT_RUN');
      expect(
        record(metal, 'G02.min_p')['reason'],
        'sampler_profile_or_host_unqualified',
      );
      final unsupported = await runSampler(
        flags: {
          'penalty': true,
          'presence_penalty': true,
          'min_p': false,
          'thinking_budget': true,
        },
      );
      expect(record(unsupported, 'G01.capability')['status'], 'FAIL');
      expect(
        record(unsupported, 'G02.min_p')['reason'],
        'required_sampler_capability_missing',
      );
    },
  );

  test('importer rejects forged sampler evidence', () async {
    final events = await runSampler();
    final mutations = <String, (String, void Function(Map<String, dynamic>))>{
      'forged capability': (
        'G01.capability',
        (e) => e['reported']['min_p'] = false,
      ),
      'invented recovery': ('G01.capability', (e) => e['recovery'] = {}),
      'other model': ('G02.min_p', (e) => e['model_sha256'] = 'f' * 64),
      'other config': ('G02.min_p', (e) => e['config_hash'] = 'f' * 64),
      'filtered drift': ('G02.min_p', (e) => e['filtered'][1] = ' other'),
      'missing seed': ('G02.min_p', (e) => (e['seeds'] as List).removeLast()),
      'unchanged penalty': (
        'G03.repeat_penalty',
        (e) => e['penalized'] = e['repeat'] = e['baseline'],
      ),
      'unstable presence': (
        'G04.presence_penalty',
        (e) => e['repeat'] = ' other',
      ),
      'missing budget trial': (
        'G05.thinking_budget',
        (e) => (e['trials'] as List).removeLast(),
      ),
      'forced text missing': (
        'G05.thinking_budget',
        (e) => e['trials'][1]['output'] = free,
      ),
      'recovery drift': ('G05.thinking_budget', (e) => e['recovery'] = free),
      'untagged accepted': (
        'G05.thinking_budget',
        (e) => e['untagged_rejection'] = 'accepted',
      ),
      'web host': ('G03.repeat_penalty', (e) => e['web'] = true),
    };
    for (final entry in mutations.entries) {
      final forged = copy(events);
      entry.value.$2(record(forged, entry.value.$1));
      expect(
        report(forged).problems,
        contains(contains(entry.value.$1)),
        reason: entry.key,
      );
    }
  });

  test('a fabricated greedy baseline is caught across cases', () async {
    final forged = copy(await runSampler());
    final g04 = record(forged, 'G04.presence_penalty');
    g04['baseline'] = '${g04['baseline']} Lily saw a ball.';
    expect(
      validSamplerCaseEvidence(
        'G04.presence_penalty',
        g04,
        profile(),
        web: false,
        diagnostics: cpuDiagnostics,
      ),
      true,
    );
    expect(
      report(forged).problems,
      contains('Sampler-control cases disagree on the greedy baseline'),
    );
  });

  test(
    'the public adapter reports and forwards every sampler control',
    () async {
      final directory = await Directory.systemTemp.createTemp('sampler-pack-');
      final model = File('${directory.path}/model.gguf')..writeAsBytesSync([1]);
      final backend = _SamplerBackend();
      final adapter = PublicValidationEngine(
        engineFactory: () => LlamaEngine(backend),
      );
      try {
        await adapter.load(model.path, profile());
        final capabilities = await adapter.samplerCapabilities();
        expect(capabilities.supportsPenalty, true);
        expect(capabilities.supportsPresencePenalty, true);
        expect(capabilities.supportsMinP, true);
        expect(capabilities.supportsThinkingBudget, true);
        const budget = ThinkingBudget(
          maxTokens: 4,
          startTag: '<think>',
          endTag: '</think>',
          forcedMessage: 'Time is up.',
        );
        final text = await adapter.generateSampled(
          'prompt',
          const GenerationParams(
            maxTokens: 7,
            temp: 1.5,
            seed: 3,
            topK: 0,
            topP: 1,
            minP: 1,
            penalty: 1.5,
            presencePenalty: 2,
            thinkingBudget: budget,
          ),
        );
        expect(text, ' sampled');
        final sent = backend.params!;
        expect(
          [sent.maxTokens, sent.temp, sent.seed, sent.topK, sent.topP],
          [7, 1.5, 3, 0, 1],
        );
        expect([sent.minP, sent.penalty, sent.presencePenalty], [1, 1.5, 2]);
        expect(sent.thinkingBudget?.maxTokens, 4);
        expect(sent.thinkingBudget?.endTag, '</think>');

        backend.minP = false;
        expect((await adapter.samplerCapabilities()).supportsMinP, false);
      } finally {
        await adapter.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  group('oracle gates', () {
    test('only the sealed native CPU profile expects every control', () {
      expect(
        expectedSamplerCapabilities(
          profile(),
          web: false,
          diagnostics: cpuDiagnostics,
        )!.values,
        everyElement(isTrue),
      );
      expect(
        expectedSamplerCapabilities(
          profile(),
          web: true,
          diagnostics: cpuDiagnostics,
        ),
        isNull,
      );
      for (final diagnostics in [
        {...cpuDiagnostics, 'backend_name': 'Metal'},
        {...cpuDiagnostics, 'context_size': 512},
        {...cpuDiagnostics, 'reported_gpu_layers': 1},
      ]) {
        expect(
          expectedSamplerCapabilities(
            profile(),
            web: false,
            diagnostics: diagnostics,
          ),
          isNull,
        );
      }
      for (final change in <void Function(Map<String, dynamic>)>[
        (data) => data['threads'] = 4,
        (data) => data['context_size'] = 512,
        (data) => data['focus_features'] = ['tokenization'],
        (data) => data['model']['bytes'] = 1,
      ]) {
        final data = profile().toJson();
        change(data);
        expect(
          expectedSamplerCapabilities(
            ValidationProfile.fromJson(data),
            web: false,
            diagnostics: cpuDiagnostics,
          ),
          isNull,
        );
      }
    });

    test('LiteRT asserts only Min-P, and only under its own backend', () {
      final litert = focused('chat-litert-cpu');
      expect(
        expectedSamplerCapabilities(
          litert,
          web: false,
          diagnostics: {'backend_name': 'LiteRT-LM CPU'},
        ),
        {
          'penalty': null,
          'presence_penalty': null,
          'min_p': false,
          'thinking_budget': null,
        },
      );
      expect(
        expectedSamplerCapabilities(
          litert,
          web: false,
          diagnostics: {'backend_name': 'CPU'},
        ),
        isNull,
      );
      expect(
        expectedSamplerCapabilities(
          litert,
          web: true,
          diagnostics: {'backend_name': 'LiteRT-LM CPU'},
        ),
        isNull,
      );
    });

    test('repeated word n-grams count each occurrence after the first', () {
      expect(repeatedWordNgrams(greedy, 3), 2);
      expect(repeatedWordNgrams(' a b c d', 3), 0);
      expect(repeatedWordNgrams('a b', 3), 0);
    });
  });
}
