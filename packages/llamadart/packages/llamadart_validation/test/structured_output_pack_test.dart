import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart_validation/llamadart_validation.dart';
import 'package:llamadart_validation/src/structured_output_evidence.dart';
import 'package:test/test.dart';

String _prompt(String section, [String field = 'prompt']) =>
    structuredFixture(section)[field] as String;

const _conformingMember =
    '{"name":"Ada","age":34,"rating":4.5,"active":true,"nickname":null,'
    '"tier":"gold","address":{"city":"Paris","zip":"75001"},'
    '"loans":[{"title":"Dune","days":14}],"fines":[],"notes":"",'
    '"preferences":{}}';

/// Public-engine backend that emits scripted replies. With [honorGrammar] it
/// returns grammar-conforming replies whenever a grammar reaches it, standing
/// in for constrained decoding; without it every request gets the reply an
/// unconstrained model would give.
class _ScriptedBackend
    implements
        LlamaBackend,
        BackendGrammarConstraintsSupport,
        BackendLazyGrammarSupport {
  _ScriptedBackend({
    this.honorGrammar = true,
    this.grammarSupport = true,
    this.controlConforms = false,
    this.malformedIsJson = false,
  });

  final bool honorGrammar;
  final bool grammarSupport;
  final bool controlConforms;
  final bool malformedIsJson;
  final requests = <GenerationParams>[];
  final prompts = <String>[];

  @override
  bool get supportsUrlLoading => false;
  @override
  bool get supportsGrammarConstraints => grammarSupport;
  @override
  bool get supportsLazyGrammar => grammarSupport;
  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}
  @override
  Future<int> modelLoad(String path, ModelParams params) async {
    if (!File(path).existsSync()) {
      throw LlamaModelException('Missing model', path);
    }
    return 1;
  }

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
  Future<String> getBackendName() async => 'CPU';
  @override
  Future<int> getContextSize(int handle) async => 2048;
  @override
  Future<Map<String, String>> modelMetadata(int handle) async => {
    'tokenizer.chat_template':
        '{# <tool_call> #}'
        '{{ messages[0]["content"] }}',
    'llm.context_length': '2048',
  };

  String _reply(String prompt, GenerationParams params) {
    final constrained = honorGrammar && params.grammar != null;
    if (prompt.contains(_prompt('json_object'))) {
      return constrained || controlConforms
          ? '{"description":"A red apple"}'
          : 'A red apple is crisp and sweet.';
    }
    if (prompt.contains(_prompt('json_schema'))) {
      return constrained ? _conformingMember : 'Ada borrows two books.';
    }
    if (prompt.contains(_prompt('grammar'))) {
      return constrained ? 'cedar-123' : 'The sea is calm today.';
    }
    if (prompt.contains(_prompt('lazy_grammar'))) {
      return constrained && params.grammarLazy
          ? 'It is sunny today.\nANSWER: alpha'
          : 'It is sunny today.\nANSWER: blue';
    }
    if (prompt.contains(_prompt('reject', 'mismatch_prompt'))) {
      return constrained ? '{"city":"Paris"}' : 'Paris is a city.';
    }
    if (prompt.contains(_prompt('reject', 'malformed_prompt'))) {
      return malformedIsJson ? '{"sea":"wide"}' : 'The sea is wide.';
    }
    if (prompt.contains(_prompt('tools'))) {
      final arguments = constrained
          ? '{"city":"Montréal","unit":"celsius","days":7}'
          : '{"city":"Montréal","unit":"fahrenheit","days":30}';
      return '<tool_call>\n{"name":"get_forecast","arguments":$arguments}'
          '\n</tool_call>';
    }
    return 'Hello there.';
  }

  @override
  Stream<List<int>> generate(
    int handle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async* {
    requests.add(params);
    prompts.add(prompt);
    final bytes = utf8.encode(_reply(prompt, params));
    for (var i = 0; i < bytes.length; i += 5) {
      yield bytes.sublist(i, min(i + 5, bytes.length));
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SchemaBackend extends _ScriptedBackend
    implements BackendJsonSchemaChatGeneration {
  _SchemaBackend({this.providerWorks = true}) : super(grammarSupport: false);
  final bool providerWorks;
  bool admitted = false;
  @override
  bool get supportsJsonSchemaChatGeneration => admitted;
  @override
  Future<void> prepareJsonSchemaChat() async {
    if (!providerWorks) {
      throw LlamaUnsupportedException('Provider unavailable.');
    }
    admitted = true;
  }

  @override
  Future<String> getBackendName() async => 'LiteRT-LM cpu';
  @override
  Stream<List<int>> generateChatWithJsonSchema(
    int handle,
    List<LlamaChatMessage> messages,
    GenerationParams params, {
    required Map<String, dynamic> jsonSchema,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) async* {
    yield utf8.encode('{}');
  }
}

const _schemaEnvironment = <String, dynamic>{
  'os': 'macos',
  'build_os': 'macos',
  'build_abi': 'macos_arm64',
  'litert_tag': 'v0.18.1-4',
  'runtime_payload_verified': true,
  'runtime_bundle_sha256':
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'source_commit': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'source_dirty': false,
  'hook_sha256':
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
};

Future<({ValidationReport report, List<Map<String, dynamic>> events})>
_runNativeSchema(
  bool providerWorks, {
  Map<String, dynamic> environment = _schemaEnvironment,
}) async {
  final directory = Directory.systemTemp.createTempSync('native-schema-pack-');
  addTearDown(() => directory.deleteSync(recursive: true));
  final model = File('${directory.path}/Qwen3-0.6B.litertlm')
    ..writeAsBytesSync([0, 0, 0, 0]);
  final selected = ValidationProfile.fromJson(
    (jsonDecode(File('assets/profiles/chat-litert-cpu.json').readAsStringSync())
          as Map<String, dynamic>)
      ..['selection'] = 'focused'
      ..['focus_features'] = ['structured_output'],
  );
  final events = <Map<String, dynamic>>[];
  await ValidationRunner(
    profile: selected,
    engine: PublicValidationEngine(
      engineFactory: () =>
          LlamaEngine(_SchemaBackend(providerWorks: providerWorks)),
    ),
    emit: (event) async => events.add(event),
    caseTimeout: const Duration(seconds: 10),
  ).run(
    model.path,
    runId: 'native-schema-test',
    environment: environment,
    preparation: {
      'verified': true,
      'sha256': selected.modelHash,
      'bytes': selected.model['bytes'],
    },
  );
  return (
    report: ValidationReport.parse(events.map(jsonEncode).join('\n')),
    events: events,
  );
}

ValidationProfile _profile(String backend) => ValidationProfile.fromJson(
  jsonDecode(
        File(
          'assets/profiles/structured-gguf-$backend.json',
        ).readAsStringSync(),
      )
      as Map<String, dynamic>,
);

const _structuredIds = [
  'S01.capabilities',
  'S02.json_object',
  'S03.json_schema',
  'S04.grammar',
  'S05.grammar.lazy',
  'S06.reject',
  'S07.stream',
  'S08.tools.schema',
];

Future<({ValidationReport report, List<Map<String, dynamic>> events})> _run(
  _ScriptedBackend backend,
) async {
  final directory = Directory.systemTemp.createTempSync('structured-pack-');
  addTearDown(() => directory.deleteSync(recursive: true));
  final model = File('${directory.path}/fixture.gguf')
    ..writeAsBytesSync([0, 0, 0, 0]);
  final selected = _profile('cpu');
  final events = <Map<String, dynamic>>[];
  await ValidationRunner(
    profile: selected,
    engine: PublicValidationEngine(engineFactory: () => LlamaEngine(backend)),
    emit: (event) async => events.add(event),
    caseTimeout: const Duration(seconds: 10),
  ).run(
    model.path,
    runId: 'structured-test',
    preparation: {
      'verified': true,
      'sha256': selected.modelHash,
      'bytes': selected.model['bytes'],
    },
    environment: {
      'source_commit': List.filled(40, 'a').join(),
      'source_dirty': false,
      'hook_sha256': List.filled(64, 'b').join(),
      'native_tag': 'v0.7.0',
    },
  );
  return (
    report: ValidationReport.parse(events.map(jsonEncode).join('\n')),
    events: events,
  );
}

Map<String, dynamic> _record(List<Map<String, dynamic>> events, String id) =>
    events.singleWhere((e) => e['type'] == 'case' && e['case_id'] == id);

void main() {
  test(
    'known excluded Gemma family is false while unprofiled model bytes remain unknown',
    () {
      final data =
          jsonDecode(
                File(
                  'assets/profiles/gemma3-litert-cpu.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(
        expectedStructuredCapabilities(
          'litert',
          profile: ValidationProfile.fromJson(data),
          environment: _schemaEnvironment,
          diagnostics: {'backend_name': 'LiteRT-LM cpu'},
        )['structured_output'],
        isFalse,
      );
      (data['model'] as Map)['sha256'] = List.filled(64, 'c').join();
      expect(
        expectedStructuredCapabilities(
          'litert',
          profile: ValidationProfile.fromJson(data),
          environment: _schemaEnvironment,
          diagnostics: {'backend_name': 'LiteRT-LM cpu'},
        )['structured_output'],
        isNull,
      );
    },
  );
  test(
    'catalog 10 native capability expectation uses locked identity, not provider outcome',
    () async {
      final supported = await _runNativeSchema(true);
      expect(_record(supported.events, 'S01.capabilities')['status'], 'PASS');
      expect(supported.report.problems, isEmpty);
      final missing = await _runNativeSchema(false);
      expect(_record(missing.events, 'S01.capabilities')['status'], 'FAIL');
      final manifest = supported.events.singleWhere(
        (event) => event['type'] == 'manifest',
      );
      final profile = ValidationProfile.fromJson(
        manifest['profile'] as Map<String, dynamic>,
      );
      for (var version = 8; version <= 9; version++) {
        expect(
          validationCase('S01.capabilities', catalogVersion: version).version,
          1,
        );
        expect(
          profile.catalogForVersion(version)['fixtures'],
          isNot(contains('native_json_schema_capability')),
        );
        expect(
          expectedStructuredCapabilities(
            'litert',
            catalogVersion: version,
          )['structured_output'],
          isFalse,
        );
      }
    },
  );
  test(
    'unverified JIT provenance is incomplete rather than unsupported false',
    () async {
      final result = await _runNativeSchema(
        true,
        environment: {..._schemaEnvironment, 'runtime_payload_verified': false},
      );
      final record = _record(result.events, 'S01.capabilities');
      expect(record['status'], 'NOT_RUN');
      expect((record['reported'] as Map)['structured_output'], isTrue);
      expect((record['expected'] as Map)['structured_output'], isNull);
      record['status'] = 'PASS';
      expect(
        ValidationReport.parse(
          result.events.map(jsonEncode).join('\n'),
        ).problems,
        contains('Invalid structured-output case evidence: S01.capabilities'),
      );
    },
  );
  test(
    'importer rejects forced capability/admission and altered native schema identity',
    () async {
      final result = await _runNativeSchema(true);
      for (final mutate in <void Function(List<Map<String, dynamic>>)>[
        (events) =>
            (_record(events, 'S01.capabilities')['reported']
                    as Map)['structured_output'] =
                false,
        (events) =>
            _record(events, 'S01.capabilities')['native_schema_admitted'] =
                false,
        (events) =>
            (events.firstWhere((e) => e['type'] == 'manifest')['environment']
                    as Map)['build_abi'] =
                'macos_x64',
        (events) =>
            (events.firstWhere((e) => e['type'] == 'manifest')['environment']
                    as Map)['litert_tag'] =
                'v0.17.0-6',
        (events) =>
            (events.firstWhere((e) => e['type'] == 'manifest')['environment']
                    as Map)
                .remove('runtime_bundle_sha256'),
        (events) =>
            (events.firstWhere((e) => e['type'] == 'manifest')['preparation']
                as Map)['sha256'] = List.filled(
              64,
              '0',
            ).join(),
        (events) =>
            (_record(events, 'C01.load')['diagnostics']
                    as Map)['backend_name'] =
                'LiteRT-LM gpu',
        (events) =>
            (_record(events, 'S01.capabilities')['diagnostics']
                    as Map)['backend_name'] =
                'LiteRT-LM gpu',
      ]) {
        final copy = (jsonDecode(jsonEncode(result.events)) as List)
            .cast<Map<String, dynamic>>();
        mutate(copy);
        expect(
          ValidationReport.parse(copy.map(jsonEncode).join('\n')).problems,
          contains('Invalid structured-output case evidence: S01.capabilities'),
        );
      }
    },
  );

  test('structured profiles select every structured case from catalog 8', () {
    for (final backend in ['cpu', 'metal']) {
      final selected = _profile(backend);
      expect(selected.caseIds, containsAll(_structuredIds));
      expect(
        () => selected.catalogForVersion(7),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('runtimes without a constraint keep only what they can run', () {
    ValidationProfile focused(String id) => ValidationProfile.fromJson(
      (jsonDecode(File('assets/profiles/$id.json').readAsStringSync())
            as Map<String, dynamic>)
        ..['selection'] = 'focused'
        ..['focus_features'] = ['structured_output'],
    );
    List<String> structured(ValidationProfile profile) =>
        profile.caseIds.where((id) => id.startsWith('S')).toList();
    Map<String, Object?> omissions(ValidationProfile profile) => {
      for (final entry in (profile.catalog['cases'] as List).cast<Map>())
        if ('${entry['id']}'.startsWith('S') && entry['selected'] == false)
          '${entry['id']}': entry['omission_reason'],
    };
    final litert = focused('chat-litert-cpu');
    expect(structured(litert), ['S01.capabilities']);
    expect(omissions(litert).values.toSet(), {'litert_grammar_unsupported'});
    final native = ValidationProfile.fromJson(
      (jsonDecode(
              File(
                'assets/profiles/npu-qualcomm-sm8650.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>)
        ..['execution_path'] = 'native_c_api'
        ..['enable_thinking'] = true
        ..['selection'] = 'focused'
        ..['focus_features'] = ['structured_output'],
    );
    expect(structured(native), isEmpty);
    expect(omissions(native).keys, _structuredIds);
    expect(omissions(native).values.toSet(), {
      'outside_native_reference_scope',
    });
    final webgpu = focused('chat-gguf-webgpu');
    expect(structured(webgpu), [
      for (final id in _structuredIds)
        if (id != 'S05.grammar.lazy') id,
    ]);
    expect(omissions(webgpu), {
      'S05.grammar.lazy': 'webgpu_lazy_grammar_unsupported',
    });
  });

  test(
    'constrained public requests pass and the journal rechecks them',
    () async {
      final backend = _ScriptedBackend();
      final result = await _run(backend);
      for (final id in _structuredIds) {
        expect(
          _record(result.events, id)['status'],
          'PASS',
          reason: jsonEncode(_record(result.events, id)),
        );
      }
      expect(
        result.report.problems.where((p) => p.contains('structured-output')),
        isEmpty,
      );
      final stream = _record(result.events, 'S07.stream');
      expect(
        ((stream['output'] as Map)['content_deltas'] as List).length,
        greaterThan(2),
      );
      expect(stream['partial_rejections'], isNotEmpty);
      final lazy = backend.requests.where((r) => r.grammarLazy).single;
      expect(lazy.grammarTriggers.single.value, 'ANSWER:');
      expect(lazy.grammarTriggers.single.triggerType, GrammarTriggerType.word);
      final reject = _record(result.events, 'S06.reject');
      expect(
        (reject['unsupported_schema'] as Map)['error_type'],
        ['LlamaUnsupportedException'].single,
      );
      expect((reject['unsupported_response_format'] as Map)['chunks'], 0);
    },
  );

  test('S03 records the createStructuredJson result as the helper', () async {
    final backend = _ScriptedBackend();
    final result = await _run(backend);
    final schemaPrompt = _prompt('json_schema');
    final requests = [
      for (var i = 0; i < backend.prompts.length; i++)
        if (backend.prompts[i].contains(schemaPrompt)) backend.requests[i],
    ];
    expect(requests.map((r) => r.grammar != null), [false, true, true, true]);
    final helper = _record(result.events, 'S03.json_schema')['helper'] as Map;
    expect(helper['value'], jsonDecode(_conformingMember));
    expect(helper, contains('wall_ms'));
    expect(helper, isNot(contains('parsed')));
  });

  test(
    'a backend that ignores grammars fails every constrained case',
    () async {
      final result = await _run(_ScriptedBackend(honorGrammar: false));
      expect(_record(result.events, 'S01.capabilities')['status'], 'PASS');
      for (final id in _structuredIds.skip(1)) {
        expect(_record(result.events, id)['status'], 'FAIL', reason: id);
      }
      expect(result.report.qualified, isFalse);
    },
  );

  test('a fixture whose control already conforms stays NOT_RUN', () async {
    final result = await _run(_ScriptedBackend(controlConforms: true));
    final record = _record(result.events, 'S02.json_object');
    expect(record['status'], 'NOT_RUN');
    expect(record['reason'], contains('unconstrained control'));
  });

  test('a malformed-output request that returns JSON stays NOT_RUN', () async {
    final result = await _run(_ScriptedBackend(malformedIsJson: true));
    final record = _record(result.events, 'S06.reject');
    expect(record['status'], 'NOT_RUN');
    expect(record['reason'], contains('produced valid JSON'));
  });

  test(
    'missing grammar support fails capabilities and skips the rest',
    () async {
      final result = await _run(_ScriptedBackend(grammarSupport: false));
      expect(_record(result.events, 'S01.capabilities')['status'], 'FAIL');
      for (final id in _structuredIds.skip(1)) {
        final record = _record(result.events, id);
        expect(record['status'], 'NOT_RUN', reason: id);
        expect(record['reason'], contains('reports no'));
      }
    },
  );

  test('a forged PASS without conforming evidence fails import', () async {
    final result = await _run(_ScriptedBackend());
    for (final (id, forge) in <(String, void Function(Map<String, dynamic>))>[
      (
        'S03.json_schema',
        (r) => (r['constrained'] as Map)['content'] = '{"name":"Ada"}',
      ),
      ('S03.json_schema', (r) => (r['helper'] as Map)['value'] = {'name': 1}),
      (
        'S03.json_schema',
        (r) => (r['constrained'] as Map)
          ..['content'] = '{"name":"Ada"}'
          ..['parsed'] = {'name': 'Ada'},
      ),
      (
        'S02.json_object',
        (r) => (r['control'] as Map)['content'] = '{"description":"apple"}',
      ),
      ('S02.json_object', (r) => r.remove('control')),
      (
        'S02.json_object',
        (r) => (r['constrained'] as Map)['parsed'] = {'other': 1},
      ),
      (
        'S04.grammar',
        (r) => (r['constrained'] as Map)['stream_completed'] = false,
      ),
      ('S04.grammar', (r) => (r['constrained'] as Map)['content'] = 'cedar-1'),
      (
        'S05.grammar.lazy',
        (r) => (r['constrained'] as Map)['content'] = 'ANSWER: alpha',
      ),
      (
        'S06.reject',
        (r) => (r['malformed'] as Map)['parse_error'] = {
          'error_type': 'FormatException',
        },
      ),
      (
        'S06.reject',
        (r) => (r['mismatch'] as Map)['content'] = '{"town":"Paris"}',
      ),
      (
        'S06.reject',
        (r) => (r['unsupported_schema'] as Map)['error_type'] =
            'LlamaArgumentException',
      ),
      (
        'S06.reject',
        (r) => (r['unsupported_response_format'] as Map)['error_type'] =
            'LlamaInferenceException',
      ),
      (
        'S06.reject',
        (r) => (r['unsupported_response_format'] as Map)['chunks'] = 3,
      ),
      ('S07.stream', (r) => r['partial_rejections'] = <Object>[]),
      (
        'S07.stream',
        (r) => r['partial_rejections'] = [
          for (final rejection in r['partial_rejections'] as List)
            {...rejection as Map, 'error_type': 'FormatException'},
        ],
      ),
      (
        'S07.stream',
        (r) {
          final output = r['output'] as Map;
          output['content_deltas'] = ['{"name":', '"Ada"}'];
          output['content'] = '{"name":"Ada"}';
          output['parsed'] = {'name': 'Ada'};
          r['partial_rejections'] = [
            {'length': 8, 'error_type': 'LlamaInferenceException'},
          ];
        },
      ),
      (
        'S08.tools.schema',
        (r) => (r['output'] as Map)['tool_call_deltas'] = [
          {
            'index': 0,
            'function': {
              'name': 'get_forecast',
              'arguments': '{"city":"Montréal","unit":"fahrenheit","days":30}',
            },
          },
        ],
      ),
      (
        'S08.tools.schema',
        (r) => (r['output'] as Map)['tool_call_deltas'] = [
          {
            'index': 0,
            'function': {
              'name': 'other_tool',
              'arguments': '{"city":"Montréal","unit":"celsius","days":7}',
            },
          },
        ],
      ),
      (
        'S08.tools.schema',
        (r) => (r['output'] as Map)['finish_reasons'] = ['stop'],
      ),
    ]) {
      final events = (jsonDecode(jsonEncode(result.events)) as List)
          .cast<Map<String, dynamic>>();
      forge(_record(events, id));
      expect(
        ValidationReport.parse(events.map(jsonEncode).join('\n')).problems,
        contains('Invalid structured-output case evidence: $id'),
      );
    }
  });

  group('independent fixture schema check', () {
    final schema = structuredFixture('json_schema')['schema'] as Map;
    Map<String, dynamic> member() =>
        jsonDecode(_conformingMember) as Map<String, dynamic>;

    test('accepts the optional property and rejects each violation', () {
      expect(conformsToFixtureSchema(member(), schema), isTrue);
      expect(
        conformsToFixtureSchema({...member(), 'email': 'a@b.c'}, schema),
        isTrue,
      );
      for (final (field, value) in <(String, Object?)>[
        ('tier', 'platinum'),
        ('age', 17),
        ('age', 34.5),
        ('rating', 'x'),
        (
          'loans',
          [
            {'title': 'Dune', 'days': 99},
          ],
        ),
        ('nickname', 'Ace'),
        ('fines', [1]),
        ('notes', 'late'),
        ('preferences', {'quiet': true}),
        ('loans', <Object>[]),
        ('address', {'city': 'Paris', 'zip': '7500'}),
        ('address', {'city': 'Paris'}),
        ('extra', 1),
      ]) {
        expect(
          conformsToFixtureSchema({...member(), field: value}, schema),
          isFalse,
          reason: '$field=$value',
        );
      }
      expect(
        conformsToFixtureSchema(member()..remove('rating'), schema),
        isFalse,
      );
    });

    test('rejects open objects and out-of-range numbers', () {
      expect(
        conformsToFixtureSchema(
          {'a': 1},
          {
            'type': 'object',
            'properties': {
              'a': {'type': 'integer'},
            },
          },
        ),
        isFalse,
      );
      final bounded = {'type': 'number', 'minimum': 0, 'maximum': 1};
      expect(conformsToFixtureSchema(0.5, bounded), isTrue);
      expect(conformsToFixtureSchema(1.5, bounded), isFalse);
      expect(conformsToFixtureSchema(-0.5, bounded), isFalse);
    });

    test('fails closed on keywords it does not check', () {
      expect(
        conformsToFixtureSchema(1, {'type': 'integer', 'multipleOf': 2}),
        isFalse,
      );
    });
  });
}
