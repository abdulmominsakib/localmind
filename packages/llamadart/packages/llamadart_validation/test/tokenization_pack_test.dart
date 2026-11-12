import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart_validation/llamadart_validation.dart';
import 'package:llamadart_validation/src/tokenization_evidence.dart';
import 'package:test/test.dart';

import 'validation_test.dart' as harness;

/// A reversible byte tokenizer verifies public API plumbing, not real model IDs.
class _TokenizerBackend implements LlamaBackend {
  final addSpecialCalls = <bool>[];
  final specialCalls = <bool>[];
  bool corruptDecode = false;
  bool unstable = false;
  int _calls = 0;

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
  Future<int> getContextSize(int handle) async => 1024;
  @override
  Future<Map<String, String>> modelMetadata(int handle) async => {};
  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async {
    addSpecialCalls.add(addSpecial);
    return [
      if (addSpecial) 9999,
      ...utf8.encode(text),
      if (unstable && text == 'Hello, world!') ++_calls,
    ];
  }

  @override
  Future<String> detokenize(
    int modelHandle,
    List<int> tokens, {
    bool special = false,
  }) async {
    specialCalls.add(special);
    if (corruptDecode) return 'lost text';
    return tokens.isEmpty ? '' : ' ${utf8.decode(tokens)}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Existing core fixtures stay model-free; token calls use a real LlamaEngine.
class _Engine extends harness.FakeEngine implements TokenCountValidationEngine {
  _Engine(this.adapter) {
    backendName = 'CPU';
  }
  final PublicValidationEngine adapter;
  bool wrongCount = false;
  bool emptyTokens = false;
  @override
  Future<void> load(String location, ValidationProfile profile) async {
    await super.load(location, profile);
    await adapter.load(location, profile);
  }

  @override
  Future<void> unload() async {
    await super.unload();
    await adapter.unload();
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    await adapter.dispose();
  }

  @override
  Future<List<int>> tokenize(String text) =>
      emptyTokens ? Future.value([]) : adapter.tokenize(text);
  @override
  Future<String> detokenize(List<int> tokens) => adapter.detokenize(tokens);
  @override
  Future<int> getTokenCount(String text) async =>
      await adapter.getTokenCount(text) + (wrongCount ? 1 : 0);
}

class _CountingPublicEngine implements LlamaEngine {
  String? counted;
  @override
  Future<int> getTokenCount(String text) async {
    counted = text;
    return 4321;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ValidationProfile _profile() => ValidationProfile.fromJson(
  jsonDecode(
        File('assets/profiles/tokenization-gguf-cpu.json').readAsStringSync(),
      )
      as Map<String, dynamic>,
);

Future<({ValidationReport report, List<Map<String, dynamic>> events})> _run({
  _TokenizerBackend? backend,
  bool wrongCount = false,
  bool emptyTokens = false,
}) async {
  final directory = Directory.systemTemp.createTempSync('tokenization-pack-');
  addTearDown(() => directory.deleteSync(recursive: true));
  final model = File('${directory.path}/fixture.gguf')..writeAsBytesSync([0]);
  final selected = _profile();
  final engine =
      _Engine(
          PublicValidationEngine(
            engineFactory: () => LlamaEngine(backend ?? _TokenizerBackend()),
          ),
        )
        ..wrongCount = wrongCount
        ..emptyTokens = emptyTokens;
  final events = <Map<String, dynamic>>[];
  await ValidationRunner(
    profile: selected,
    engine: engine,
    emit: (event) async => events.add(event),
    caseTimeout: const Duration(seconds: 10),
  ).run(
    model.path,
    runId: 'tokenization-fixture',
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
  // Emitted by the exact pre-pack base 081690b, before catalog 9 existed.
  const historicalTinyCatalogHashes = {
    1: '538eb5361baa632c940704fb30973af612751594bbb13bf01361e4f6695235b3',
    2: 'f25bf82db47382385a847a16d12361ccbb6d194f2351a1e2d92edac285d00013',
    3: '9579696c4d21f9df4d9c5235584c4ba7127b2af4592f7ba4ac365f6d6b5b5d04',
    4: '3505a18ad43f6e3d7a6153fa490690410ab806a09c2025d9d4b4f1bc2fb5acb3',
    5: '05bec0d6558dc528d0aab6895d9f7112bae25c928ca79d2eb500d8d921861ea0',
    6: '7ac28dc479424d5ec4b3b571e68d6dc31fc4d124962220eea76a11dbd0e5759e',
    7: '2327613cdb4b28ce938a1094fe7b7228275ae001986594d41fb764e7061623f5',
    8: '51c51d0f4e0112d5fd724350ebca7171c06cb39227c9b043c78e5bcb3e427d35',
  };

  test(
    'adapter calls public getTokenCount instead of retokenizing locally',
    () async {
      final engine = _CountingPublicEngine();
      final adapter = PublicValidationEngine(engineFactory: () => engine);
      expect(await adapter.getTokenCount('count this'), 4321);
      expect(engine.counted, 'count this');
    },
  );

  test(
    'catalog 9 selects the pack and earlier catalogs keep their inventory',
    () {
      final selected = _profile();
      expect(selected.caseIds, containsAll(['T01.roundtrip', 'T02.count']));
      expect(() => selected.catalogForVersion(8), throwsFormatException);
      final quick = ValidationProfile.fromJson(
        jsonDecode(
              File('assets/profiles/tiny-gguf-cpu.json').readAsStringSync(),
            )
            as Map<String, dynamic>,
      );
      for (var version = 1; version <= 8; version++) {
        final catalog = quick.catalogForVersion(version);
        expect(jsonHash(catalog), historicalTinyCatalogHashes[version]);
        expect(catalog['features'], isNot(contains('tokenization')));
        expect(catalog['fixtures'], isNot(contains('tokenization')));
        expect(
          (catalog['cases'] as List).map((c) => (c as Map)['id']),
          isNot(contains(startsWith('T'))),
        );
        expect(
          quick.caseIdsForCatalog(version).any((id) => id.startsWith('T')),
          false,
        );
      }
    },
  );

  test(
    'native reference profiles cannot claim public tokenization evidence',
    () {
      final data =
          jsonDecode(
                File(
                  'assets/profiles/npu-qualcomm-sm8650.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      data['execution_path'] = 'native_c_api';
      data['enable_thinking'] = true;
      data['selection'] = 'focused';
      data['focus_features'] = ['tokenization'];
      final selected = ValidationProfile.fromJson(data);
      expect(selected.caseIds.any((id) => id.startsWith('T')), false);
      final cases = (selected.catalog['cases'] as List).cast<Map>();
      for (final record in cases.where((c) => '${c['id']}'.startsWith('T'))) {
        expect(record['selected'], false);
        expect(record['omission_reason'], 'outside_native_reference_scope');
      }
    },
  );

  test(
    'fixed corpus reaches the public tokenizer, decoder and count API',
    () async {
      final backend = _TokenizerBackend();
      final result = await _run(backend: backend);
      for (final id in ['T01.roundtrip', 'T02.count']) {
        final record = _record(result.events, id);
        expect(record['status'], 'PASS', reason: jsonEncode(record));
        expect(validTokenizationCaseEvidence(id, record, _profile()), true);
        expect((record['trials'] as List).first['input'], '');
      }
      expect(backend.addSpecialCalls, isNotEmpty);
      expect(backend.addSpecialCalls.every((value) => !value), true);
      expect(backend.specialCalls, isNotEmpty);
      expect(backend.specialCalls.every((value) => !value), true);
      expect(
        result.report.problems.where((p) => p.contains('tokenization')),
        isEmpty,
      );
    },
  );

  for (final fault in ['decode', 'unstable', 'count', 'empty']) {
    test(
      'runner rejects $fault regression instead of claiming coverage',
      () async {
        final backend = _TokenizerBackend()
          ..corruptDecode = fault == 'decode'
          ..unstable = fault == 'unstable';
        final result = await _run(
          backend: backend,
          wrongCount: fault == 'count',
          emptyTokens: fault == 'empty',
        );
        final id = fault == 'count' ? 'T02.count' : 'T01.roundtrip';
        expect(_record(result.events, id)['status'], 'FAIL');
        expect(result.report.qualified, false);
      },
    );
  }

  test(
    'count-less reference adapter cannot claim a public count run',
    () async {
      final result = await harness.run(
        harness.FakeEngine(),
        selected: _profile(),
      );
      expect(_record(result.events, 'T02.count')['status'], 'NOT_RUN');
      expect(
        _record(result.events, 'T02.count')['reason'],
        contains('getTokenCount'),
      );
    },
  );

  test('importer rejects forged tokenization evidence', () async {
    final result = await _run();
    final mutations = <String, void Function(Map<String, dynamic>)>{
      'missing trials': (e) => e.remove('trials'),
      'malformed row': (e) => e['trials'][1] = null,
      'missing tokens': (e) => (e['trials'][1] as Map).remove('tokens'),
      'noninteger token': (e) => e['trials'][1]['tokens'][0] = 1.0,
      'noninteger repeat': (e) => e['trials'][1]['repeated_tokens'][0] = 72.0,
      'missing corpus row': (e) => (e['trials'] as List).removeLast(),
      'changed input': (e) => e['trials'][1]['input'] = 'different',
      'special insertion': (e) => e['trials'][1]['add_special'] = true,
      'invalid token ID': (e) => e['trials'][1]['tokens'][0] = -1,
      'empty nonempty encoding': (e) => e['trials'][1]['tokens'] = [],
      'changed repeat': (e) => e['trials'][1]['repeated_tokens'][0] = 999,
      'different repeat length': (e) => e['trials'][1]['repeated_tokens'] = [],
      'special decoding': (e) => e['trials'][1]['special'] = true,
      'lost whitespace': (e) =>
          e['trials'][2]['decoded'] = 'leading and trailing',
      'empty decodes prefix': (e) => e['trials'][0]['decoded'] = ' ',
      'wrong count': (e) => e['trials'][1]['count'] = 999,
      'noninteger count': (e) => e['trials'][1]['count'] = 13.0,
    };
    for (final entry in mutations.entries) {
      final events = (jsonDecode(jsonEncode(result.events)) as List)
          .cast<Map<String, dynamic>>();
      final id = entry.key.contains('count') ? 'T02.count' : 'T01.roundtrip';
      entry.value(_record(events, id));
      final report = ValidationReport.parse(events.map(jsonEncode).join('\n'));
      expect(
        report.problems,
        contains('Invalid tokenization case evidence: $id'),
        reason: entry.key,
      );
      expect(report.qualified, false, reason: entry.key);
    }
  });
}
