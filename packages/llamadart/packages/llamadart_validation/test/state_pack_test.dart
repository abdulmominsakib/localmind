import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/backend.dart';
import 'package:llamadart_validation/io.dart';
import 'package:llamadart_validation/llamadart_validation.dart';
import 'package:llamadart_validation/src/state_evidence.dart';
import 'package:test/test.dart';

import 'validation_test.dart' as harness;

ValidationProfile profile([String id = 'state-gguf-cpu']) =>
    ValidationProfile.fromJson(
      jsonDecode(File('assets/profiles/$id.json').readAsStringSync())
          as Map<String, dynamic>,
    );
const cpuDiagnostics = {
  'backend_name': 'CPU',
  'context_size': 256,
  'reported_gpu_layers': 0,
};

LlamaStateIdentity testIdentity() => LlamaStateIdentity(
  runtimeBuild: 'native-fixture-build',
  sessionFormatVersion: 11,
  contextSize: 256,
  contextConfigDigest: 'd' * 64,
);

class MemoryWorkspace implements StateValidationWorkspace {
  final files = <String, Uint8List>{};
  bool disposed = false;
  @override
  String path(String role) => role;
  @override
  Future<Uint8List> read(String role) async => files[role]!;
  @override
  Future<void> write(String role, List<int> bytes) async {
    files[role] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    files.clear();
  }
}

class StateEngine extends harness.FakeEngine implements StateValidationEngine {
  StateEngine(this.workspace);
  final MemoryWorkspace Function() workspace;
  String? fault;
  bool supported = true;
  @override
  Future<LlamaStateIdentity> stateIdentity() async {
    if (!supported) throw LlamaUnsupportedException('No native identity');
    return testIdentity();
  }

  @override
  bool get supportsStatePersistence => supported;
  @override
  bool get supportsNextTokenScoring => true;
  @override
  Future<Map<String, dynamic>> diagnostics() async => {...diagnosticsValue};
  Map<String, dynamic> diagnosticsValue = {...cpuDiagnostics};
  bool restored = false;
  @override
  Future<void> load(String location, ValidationProfile profile) async {
    await super.load(location, profile);
    restored = false;
  }

  @override
  Future<List<int>> tokenizeStatePrompt(String text) async => [
    for (var i = 0; i < (text.endsWith(' the wooden box') ? 62 : 59); i++) i,
  ];
  @override
  Future<Map<String, dynamic>> scoreStatePrompt(
    String text, {
    List<int> candidates = const [],
    int topK = 0,
    required bool reuse,
  }) async {
    final suffix = text == ' the wooden box';
    final full = text.endsWith(' the wooden box') && !suffix;
    final offset = suffix
        ? 10
        : full
        ? 2
        : 1;
    List<Map<String, dynamic>> scores(List<int> ids) => [
      for (final id in ids)
        {
          'token': id,
          'logprob':
              -id.toDouble() -
              (fault == 'token_echo' && restored ? 20 : offset),
        },
    ];
    return {
      'prompt_tokens': suffix
          ? 4
          : full
          ? 62
          : 59,
      'candidates': scores(candidates),
      'top': scores([for (var i = 0; i < topK; i++) i]),
    };
  }

  @override
  Future<bool> saveState(String path, List<int> tokens) async {
    if (!supported) throw LlamaUnsupportedException('State unsupported');
    final bytes = Uint8List(1000)..setAll(0, [110, 115, 103, 103, 11, 0, 0, 0]);
    await workspace().write(path, bytes);
    return fault != 'save_false';
  }

  @override
  Future<List<int>> loadState(String path, int capacity) async {
    if (!supported) throw LlamaUnsupportedException('State unsupported');
    if (capacity <= 0 || capacity > 256) {
      throw LlamaArgumentException('Invalid capacity');
    }
    if (path != 'valid' || capacity < 59) {
      throw LlamaStateException('Invalid state');
    }
    restored = true;
    return [for (var i = 0; i < 59; i++) i];
  }

  @override
  Future<Map<String, dynamic>> generateStatePrompt(
    String text, {
    required bool reuse,
  }) async {
    final count = text.endsWith(' the wooden box') ? 62 : 59;
    final cached = fault == 'recompute'
        ? 0
        : restored && reuse
        ? count == 59
              ? 58
              : 59
        : 0;
    return {
      'output': 'x',
      'observer_present': true,
      'observer_error': null,
      'observer_cancelled': false,
      'finish_reason': 'length',
      'usage': fault == 'no_usage'
          ? null
          : LlamaGenerationUsage(
              promptTokens: count,
              completionTokens: 1,
              cachedPromptTokens: cached,
            ).toJson(),
      'prompt_eval_tokens': count - cached,
    };
  }
}

Future<List<Map<String, dynamic>>> runState({
  String? fault,
  bool workspaceAvailable = true,
  bool spi = true,
  ValidationProfile? selected,
  bool supported = true,
}) async {
  MemoryWorkspace? current;
  final state = StateEngine(() => current!)
    ..fault = fault
    ..supported = supported;
  if ((selected ?? profile()).runtime == 'litert') {
    state.diagnosticsValue = {'backend_name': 'LiteRT-LM CPU'};
  }
  final events = <Map<String, dynamic>>[];
  final target = selected ?? profile();
  await ValidationRunner(
    profile: target,
    engine: spi ? state : harness.FakeEngine(),
    emit: (event) async {
      events.add(event);
    },
    stateWorkspaceFactory: workspaceAvailable
        ? () async {
            current = MemoryWorkspace();
            return current!;
          }
        : null,
  ).run(
    'model.gguf',
    runId: 'state-test',
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
  if (current != null) expect(current!.disposed, true);
  return events;
}

Map<String, dynamic> caseRecord(List<Map<String, dynamic>> events, String id) =>
    events.firstWhere((e) => e['case_id'] == id && e['type'] == 'case');
List<Map<String, dynamic>> copyEvents(List<Map<String, dynamic>> events) =>
    (jsonDecode(jsonEncode(events)) as List).cast<Map<String, dynamic>>();
ValidationReport report(List<Map<String, dynamic>> events) =>
    ValidationReport.parse(events.map(jsonEncode).join('\n'));

class CaptureEngine implements LlamaEngine {
  int identities = 0;
  @override
  Future<LlamaStateIdentity> stateIdentity() async {
    identities++;
    return testIdentity();
  }

  String? prompt;
  bool? special;
  bool? reuse;
  List<int>? candidates;
  String? path;
  int? capacity;
  @override
  bool get supportsStatePersistence => true;
  @override
  bool get supportsNextTokenScoring => true;
  @override
  Future<List<int>> tokenize(String text, {bool addSpecial = true}) async {
    prompt = text;
    special = addSpecial;
    return [9];
  }

  @override
  Future<LlamaNextTokenScores> scoreNextToken(
    String text, {
    List<int> candidates = const [],
    int topK = 0,
    bool reusePromptPrefix = true,
  }) async {
    prompt = text;
    reuse = reusePromptPrefix;
    this.candidates = candidates;
    return LlamaNextTokenScores(candidates: [], top: [], promptTokens: 3);
  }

  @override
  Future<bool> stateSaveFile(String path, {required List<int> tokens}) async {
    this.path = path;
    candidates = tokens;
    return false;
  }

  @override
  Future<StateLoadResult> stateLoadFile(
    String path, {
    required int tokenCapacity,
  }) async {
    this.path = path;
    capacity = tokenCapacity;
    return StateLoadResult(tokens: [8, 9]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UnsupportedBackend implements LlamaBackend {
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
  Future<String> getBackendName() async => 'Unsupported state test';
  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) => Stream.value(utf8.encode('recovered'));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FalseSupportBackend extends UnsupportedBackend
    implements BackendStatePersistence, BackendStatePersistenceSupport {
  int forwarded = 0;
  @override
  bool get supportsStatePersistence => false;
  @override
  Future<bool> stateSaveFile(int handle, String path, List<int> tokens) async {
    forwarded++;
    return true;
  }

  @override
  Future<StateLoadResult> stateLoadFile(
    int handle,
    String path,
    int capacity,
  ) async {
    forwarded++;
    return const StateLoadResult(tokens: []);
  }
}

class PersistenceWithoutIdentityBackend extends UnsupportedBackend
    implements BackendStatePersistence, BackendStatePersistenceSupport {
  @override
  bool get supportsStatePersistence => true;
  @override
  Future<bool> stateSaveFile(int handle, String path, List<int> tokens) async =>
      true;
  @override
  Future<StateLoadResult> stateLoadFile(
    int handle,
    String path,
    int capacity,
  ) async => const StateLoadResult(tokens: [1]);
}

class IdentityBackend extends UnsupportedBackend
    implements
        BackendStateIdentity,
        BackendStatePersistence,
        BackendStatePersistenceSupport {
  final List<int> identities = [];
  int contexts = 0;
  @override
  bool get supportsStatePersistence => true;
  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async =>
      ++contexts;
  @override
  Future<LlamaStateIdentity> stateIdentity(int contextHandle) async {
    identities.add(contextHandle);
    return testIdentity();
  }

  @override
  Future<bool> stateSaveFile(int handle, String path, List<int> tokens) async =>
      true;
  @override
  Future<StateLoadResult> stateLoadFile(
    int handle,
    String path,
    int capacity,
  ) async => const StateLoadResult(tokens: [1]);
}

void main() {
  test(
    'public adapter can persist while identity independently rejects',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'identity-unsupported-',
      );
      final model = File('${directory.path}/model.gguf')..writeAsBytesSync([1]);
      final adapter = PublicValidationEngine(
        engineFactory: () => LlamaEngine(PersistenceWithoutIdentityBackend()),
      );
      try {
        await adapter.load(model.path, profile());
        expect(adapter.supportsStatePersistence, true);
        expect(await adapter.saveState('unused', [1]), true);
        await expectLater(
          adapter.stateIdentity(),
          throwsA(isA<LlamaUnsupportedException>()),
        );
      } finally {
        await adapter.dispose();
        directory.deleteSync(recursive: true);
      }
    },
  );

  test(
    'public identity adapter routes source and fresh target through exported API',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'identity-adapter-',
      );
      final model = File('${directory.path}/model.gguf')..writeAsBytesSync([1]);
      final backend = IdentityBackend();
      final adapter = PublicValidationEngine(
        engineFactory: () => LlamaEngine(backend),
      );
      try {
        await adapter.load(model.path, profile());
        expect(await adapter.stateIdentity(), testIdentity());
        await adapter.dispose();
        await adapter.load(model.path, profile());
        expect(await adapter.stateIdentity(), testIdentity());
        expect(backend.identities, [1, 2]);
      } finally {
        await adapter.dispose();
        directory.deleteSync(recursive: true);
      }
    },
  );
  test('catalogs 1 through 13 retain original quick-profile hashes', () {
    const hashes = {
      1: '538eb5361baa632c940704fb30973af612751594bbb13bf01361e4f6695235b3',
      2: 'f25bf82db47382385a847a16d12361ccbb6d194f2351a1e2d92edac285d00013',
      3: '9579696c4d21f9df4d9c5235584c4ba7127b2af4592f7ba4ac365f6d6b5b5d04',
      4: '3505a18ad43f6e3d7a6153fa490690410ab806a09c2025d9d4b4f1bc2fb5acb3',
      5: '05bec0d6558dc528d0aab6895d9f7112bae25c928ca79d2eb500d8d921861ea0',
      6: '7ac28dc479424d5ec4b3b571e68d6dc31fc4d124962220eea76a11dbd0e5759e',
      7: '2327613cdb4b28ce938a1094fe7b7228275ae001986594d41fb764e7061623f5',
      8: '51c51d0f4e0112d5fd724350ebca7171c06cb39227c9b043c78e5bcb3e427d35',
      9: 'bf29257c5a7f09bc6c57150b0c506901803202968c77cff0fbaa2187ad222ee7',
      10: '69007a80f3a1f387356c664fc401c4dc87c6d8ad69e064baa1e14423533e069f',
      11: '2c685738a85a8b86954fea2d9817cb95393f6c57ac575f8fde9c450c26f1bbb2',
      12: 'a68d804a81c3f5c3251197ddba86862d8294fc1fc8ef628a8053e84f91ecf8aa',
      13: '9a30c50db287e40e7016c43fd77c48388ebed7ea2d44eee7d945f6d298b61db9',
    };
    for (final entry in hashes.entries) {
      expect(
        jsonHash(profile('tiny-gguf-cpu').catalogForVersion(entry.key)),
        entry.value,
      );
    }
  });
  test('catalogs 11 through 13 retain the original state catalog hashes', () {
    const hashes = {
      11: 'f7e1fd98691ad903288db6855109210b3ab5e1fb5c659ca3f2ed4783136c4280',
      12: '9f53e93ec8eb99913551f8a3379b6087e2ca5694640f51d941aad85829c5cd61',
      13: '12ec54696ee8763fb11e61d7963b1fd59f49cb84547109d5d4a41fec6abbd6dd',
    };
    for (final entry in hashes.entries) {
      expect(jsonHash(profile().catalogForVersion(entry.key)), entry.value);
    }
  });

  test('catalog 14 adds identity without changing catalogs 1 through 13', () {
    for (var version = 1; version <= 13; version++) {
      expect(catalogDeclaresCase('P05.identity', version), false);
    }
    for (var version = 11; version <= 13; version++) {
      final cases = profile().catalogForVersion(version)['cases'] as List;
      expect(cases.any((c) => (c as Map)['id'] == 'P05.identity'), false);
    }
    expect(profile().caseIds, contains('P05.identity'));
  });
  test(
    'identity importer rejects forged match and every raw field or binding',
    () async {
      final original = await runState();
      final source = caseRecord(original, 'P05.identity');
      expect(source['status'], 'PASS');
      final mutations = <String, void Function(Map<String, dynamic>)>{
        for (final field in [
          'runtime_build',
          'session_format_version',
          'context_size',
          'context_config_digest',
        ])
          'missing $field': (row) =>
              ((row['phases'] as List)[1]['identity'] as Map).remove(field),
        for (final field in ['runtime_build', 'context_config_digest'])
          'empty $field': (row) =>
              (row['phases'] as List)[0]['identity'][field] = '',
        for (final entry in <String, Object>{
          'runtime_build': 'other-build',
          'session_format_version': 12,
          'context_size': 512,
          'context_config_digest': 'e' * 64,
        }.entries)
          'changed ${entry.key}': (row) =>
              (row['phases'] as List)[1]['identity'][entry.key] = entry.value,
        'forged match': (row) {
          row['matches'] = true;
          (row['phases'] as List)[1]['identity']['runtime_build'] = 'other';
        },
        'before-load skew': (row) =>
            (row['phases']
                    as List)[1]['identity_before_load']['context_config_digest'] =
                'e' * 64,
        'missing identity': (row) =>
            ((row['phases'] as List)[0] as Map).remove('identity'),
        'wrong model': (row) =>
            (row['phases'] as List)[1]['model_sha256'] = 'e' * 64,
        'wrong config': (row) => row['config_hash'] = 'e' * 64,
        'wrong artifact': (row) =>
            (row['phases'] as List)[1]['snapshot_sha256'] = 'e' * 64,
      };
      for (final entry in mutations.entries) {
        final copy = copyEvents(original);
        entry.value(caseRecord(copy, 'P05.identity'));
        expect(
          report(copy).problems,
          contains('Invalid state case evidence: P05.identity'),
          reason: entry.key,
        );
      }
    },
  );
  test('identity unsupported oracle is independent of Web persistence', () {
    final selected = profile();
    final evidence = <String, dynamic>{
      'web': true,
      'supported': true,
      'diagnostics': {'backend_name': 'WebGPU'},
      'identity_rejection': 'LlamaUnsupportedException',
      'recovery': {'stream_completed': true, 'content': 'recovered'},
    };
    expect(
      validStateCaseEvidence(
        'P05.identity',
        evidence,
        selected,
        web: true,
        diagnostics: evidence['diagnostics'] as Map,
      ),
      true,
    );
    evidence['identity_rejection'] = 'accepted';
    evidence['matches'] = true;
    expect(
      validStateCaseEvidence(
        'P05.identity',
        evidence,
        selected,
        web: true,
        diagnostics: evidence['diagnostics'] as Map,
      ),
      false,
    );
  });

  test(
    'public engine rejects interface absence and support false without forwarding',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'state-unsupported-test-',
      );
      final file = File('${directory.path}/model.gguf');
      await file.writeAsBytes([1]);
      try {
        for (final backend in [UnsupportedBackend(), FalseSupportBackend()]) {
          final engine = LlamaEngine(backend);
          try {
            await engine.setModel(LlamaModel(ModelSource.path(file.path)));
            expect(engine.supportsStatePersistence, false);
            await expectLater(
              engine.stateSaveFile(
                '${directory.path}/probe.state',
                tokens: [1],
              ),
              throwsA(isA<LlamaUnsupportedException>()),
            );
            await expectLater(
              engine.stateLoadFile(
                '${directory.path}/probe.state',
                tokenCapacity: 1,
              ),
              throwsA(isA<LlamaUnsupportedException>()),
            );
            expect(
              await engine
                  .generate(
                    'recover',
                    params: const GenerationParams(maxTokens: 1),
                  )
                  .join(),
              'recovered',
            );
            if (backend is FalseSupportBackend) expect(backend.forwarded, 0);
            expect(await File('${directory.path}/probe.state').exists(), false);
          } finally {
            await engine.dispose();
          }
        }
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'adapter forwards state public methods and special-token convention',
    () async {
      final capture = CaptureEngine();
      final adapter = PublicValidationEngine(engineFactory: () => capture);
      expect(adapter.supportsStatePersistence, true);
      expect(await adapter.stateIdentity(), testIdentity());
      expect(capture.identities, 1);
      expect(adapter.supportsNextTokenScoring, true);
      expect(await adapter.tokenizeStatePrompt('prefix'), [9]);
      expect(capture.special, true);
      await adapter.scoreStatePrompt(
        'prefix',
        candidates: [5, 7],
        reuse: false,
      );
      expect(capture.reuse, false);
      expect(capture.candidates, [5, 7]);
      expect(await adapter.saveState('valid', [3, 4]), false);
      expect(capture.path, 'valid');
      expect(capture.candidates, [3, 4]);
      expect(await adapter.loadState('valid', 11), [8, 9]);
      expect(capture.capacity, 11);
    },
  );
  test(
    'complete model-free proof passes and importer reconstructs every P case',
    () async {
      final events = await runState();
      for (final id in [
        'P01.capability',
        'P02.roundtrip',
        'P03.restore_reuse',
        'P04.invalid_recovery',
        'P05.identity',
      ]) {
        expect(caseRecord(events, id)['status'], 'PASS', reason: id);
      }
      expect(report(events).problems, isEmpty);
    },
  );
  test(
    'token-only echo and full recomputation fail distinct causal oracles',
    () async {
      for (final fault in ['token_echo', 'recompute', 'save_false']) {
        final events = await runState(fault: fault);
        expect(
          caseRecord(events, 'P03.restore_reuse')['status'],
          'FAIL',
          reason: fault,
        );
      }
    },
  );
  test(
    'absent optional adapter, workspace and public counters remain incomplete',
    () async {
      for (final events in [
        await runState(spi: false),
        await runState(workspaceAvailable: false),
        await runState(fault: 'no_usage'),
      ]) {
        expect(caseRecord(events, 'P03.restore_reuse')['status'], 'NOT_RUN');
        expect(report(events).assertionsPassed, false);
      }
    },
  );
  test(
    'unknown model/config is not unsupported and known unsupported recovers',
    () async {
      final changed = profile().toJson()..['context_size'] = 512;
      final unknown = await runState(
        selected: ValidationProfile.fromJson(changed),
      );
      expect(caseRecord(unknown, 'P01.capability')['status'], 'NOT_RUN');
      final litert = profile('chat-litert-cpu').toJson()
        ..['selection'] = 'focused'
        ..['focus_features'] = ['state_persistence'];
      final excluded = await runState(
        selected: ValidationProfile.fromJson(litert),
        supported: false,
      );
      expect(caseRecord(excluded, 'P01.capability')['status'], 'PASS');
      final falseClaim = await runState(
        selected: ValidationProfile.fromJson(litert),
        supported: true,
      );
      expect(caseRecord(falseClaim, 'P01.capability')['status'], 'FAIL');
      expect(excluded.any((e) => e['case_id'] == 'P02.roundtrip'), false);
      expect(caseRecord(excluded, 'P05.identity')['status'], 'PASS');
      expect(caseRecord(falseClaim, 'P05.identity')['status'], 'FAIL');
    },
  );
  test(
    'catalog 11 is additive and old catalogs reject state fixtures or focus',
    () {
      final selected = profile();
      for (var v = 1; v <= 10; v++) {
        expect(() => selected.catalogForVersion(v), throwsFormatException);
      }
      final quick = profile('tiny-gguf-cpu');
      for (var v = 1; v <= 10; v++) {
        final catalog = quick.catalogForVersion(v);
        expect(catalog['features'], isNot(contains('state_persistence')));
        expect(catalog['fixtures'], isNot(contains('state_persistence')));
        expect(
          (catalog['cases'] as List).any(
            (c) => '${(c as Map)['id']}'.startsWith('P'),
          ),
          false,
        );
      }
      final override = quick.toJson()
        ..['fixtures'] = {
          'state_persistence': {'max_abs_logprob_delta': 100},
        };
      expect(() => ValidationProfile.fromJson(override), throwsFormatException);
      final native = profile('npu-qualcomm-sm8650').toJson()
        ..['execution_path'] = 'native_c_api'
        ..['enable_thinking'] = true
        ..['selection'] = 'focused'
        ..['focus_features'] = ['state_persistence'];
      expect(
        ValidationProfile.fromJson(
          native,
        ).caseIds.any((id) => id.startsWith('P')),
        false,
      );
    },
  );
  test(
    'independent host oracle rejects provider outcome or missing diagnostics',
    () {
      final selected = profile();
      expect(
        expectedStateCapability(
          selected,
          web: false,
          diagnostics: cpuDiagnostics,
        ),
        true,
      );
      expect(
        expectedStateCapability(selected, web: false, diagnostics: {}),
        null,
      );
      expect(
        expectedStateCapability(
          selected,
          web: true,
          diagnostics: cpuDiagnostics,
        ),
        null,
      );
    },
  );
  test('journal mutations cannot claim state success', () async {
    final events = await runState();
    final mutations = <String, void Function(Map<String, dynamic>)>{
      'no scores': (r) => (r['phases'][3] as Map).remove('score'),
      'recompute': (r) =>
          r['phases'][6]['generation']['prompt_eval_tokens'] = 62,
      'no usage': (r) => (r['phases'][6]['generation'] as Map).remove('usage'),
      'no counters': (r) =>
          (r['phases'][6]['generation'] as Map).remove('prompt_eval_tokens'),
      'fake cache': (r) =>
          r['phases'][6]['generation']['usage']['prompt_tokens_details']['cached_tokens'] =
              58,
      'zero separation': (r) =>
          r['phases'][2]['score'] = r['phases'][1]['score'],
      'not cold': (r) => r['phases'][3]['lifetime'] = 1,
      'not disposed': (r) => r['phases'][0]['disposed'] = false,
      'model swapped': (r) => r['phases'][3]['model_sha256'] = 'c' * 64,
      'config swapped': (r) => r['phases'][3]['config_hash'] = 'd' * 64,
      'snapshot swapped': (r) => r['phases'][3]['snapshot_sha256'] = 'e' * 64,
      'oversized artifact': (r) =>
          r['artifact']['bytes'] = 16 * 1024 * 1024 + 1,
      'source stub': (r) => r['artifact']['bytes'] = 8,
      'tokens echoed': (r) => r['phases'][3]['loaded_tokens'] = [1],
      'phase missing': (r) => (r['phases'] as List).removeAt(2),
      'phase reordered': (r) =>
          (r['phases'] as List).insert(2, (r['phases'] as List).removeAt(3)),
      'candidates duplicate': (r) => r['candidates'][1] = r['candidates'][0],
      'nonfinite': (r) =>
          r['phases'][3]['score']['candidates'][0]['logprob'] = 'NaN',
      'producer threshold widened': (r) {
        r['max_abs_logprob_delta'] = 100;
        r['phases'][3]['score']['candidates'][0]['logprob'] = -99;
      },
      'unsupported success': (r) => r['supported'] = false,
      'web identity': (r) => r['web'] = true,
      'diagnostics swapped': (r) => r['diagnostics']['backend_name'] = 'Metal',
      'workspace leaked': (r) => r['workspace_disposed'] = false,
    };
    for (final entry in mutations.entries) {
      final copy = copyEvents(events);
      entry.value(caseRecord(copy, 'P03.restore_reuse'));
      expect(
        report(copy).problems,
        contains('Invalid state case evidence: P03.restore_reuse'),
        reason: entry.key,
      );
    }
    final negativeMutations = <String, void Function(Map<String, dynamic>)>{
      'generic exception': (r) => r['phases'][9]['rejection'] = 'Exception',
      'capacity widened': (r) => r['phases'][21]['capacity'] = 1,
      'negative bytes swapped': (r) =>
          r['negative_artifacts']['short']['inline_bytes'][0] = 0,
      'version recipe changed': (r) =>
          r['negative_artifacts']['incompatible']['recipe'] = 'none',
      'recovery omitted': (r) => (r['phases'] as List).removeLast(),
      'recovery semantic corrupt': (r) =>
          r['phases'][10]['score']['candidates'][0]['logprob'] = -200,
      'recovery work missing': (r) =>
          r['phases'][11]['generation']['prompt_eval_tokens'] = null,
    };
    for (final entry in negativeMutations.entries) {
      final copy = copyEvents(events);
      entry.value(caseRecord(copy, 'P04.invalid_recovery'));
      expect(
        report(copy).problems,
        contains('Invalid state case evidence: P04.invalid_recovery'),
        reason: entry.key,
      );
    }
  });
  test('original catalog 9 and 10 model-free journals replay unchanged', () {
    final quick = profile('tiny-gguf-cpu');
    expect(
      jsonHash(quick.catalogForVersion(9)),
      'bf29257c5a7f09bc6c57150b0c506901803202968c77cff0fbaa2187ad222ee7',
    );
    expect(
      jsonHash(quick.catalogForVersion(10)),
      '69007a80f3a1f387356c664fc401c4dc87c6d8ad69e064baa1e14423533e069f',
    );
    for (final version in [9, 10]) {
      final legacy = ValidationReport.parse(
        File(
          'test/fixtures/state_catalog_history/catalog_$version.jsonl',
        ).readAsStringSync(),
      );
      expect(legacy.problems, isEmpty);
      expect(legacy.assertionsPassed, true);
      expect(
        legacy.cases.any((row) => '${row['case_id']}'.startsWith('P')),
        false,
      );
    }
  });
  test(
    'IO workspace rejects arbitrary role and deletes all state files',
    () async {
      final workspace = await IoStateValidationWorkspace.create();
      expect(() => workspace.path('../escape'), throwsArgumentError);
      await workspace.write('garbage', [1, 2]);
      final file = File(workspace.path('garbage'));
      expect(await workspace.read('garbage'), [1, 2]);
      final handle = await file.open(mode: FileMode.append);
      try {
        await handle.truncate(16 * 1024 * 1024 + 1);
      } finally {
        await handle.close();
      }
      await expectLater(workspace.read('garbage'), throwsStateError);
      await workspace.dispose();
      expect(await file.exists(), false);
    },
  );
}
