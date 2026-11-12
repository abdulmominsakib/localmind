import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart_validation/io.dart';
import 'package:llamadart_validation/llamadart_validation.dart';
import 'package:llamadart_validation/src/placement.dart';
import 'package:test/test.dart';

ValidationProfile profile({String backend = 'cpu', bool release = false}) {
  final json =
      jsonDecode(
            File('assets/profiles/chat-litert-cpu.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  json['backend'] = backend;
  json['selection'] = release ? 'release' : 'quick';
  return ValidationProfile.fromJson(json);
}

class FakeEngine implements ValidationEngine, StructuredValidationEngine {
  @override
  bool isWeb = false;

  /// Models the excluded-platform LiteRT contract; unprofiled hosts remain
  /// incomplete in catalog 10.
  @override
  Future<LlamaEngineCapabilities> structuredCapabilities() async =>
      const LlamaEngineCapabilities(isSupported: true);
  @override
  Future<Map<String, dynamic>> generateStructured(
    String prompt,
    ValidationProfile profile, {
    required int maxTokens,
    Map<String, dynamic>? responseFormat,
    LlamaStructuredOutput<Object?>? parseWith,
    String? grammar,
    bool grammarLazy = false,
    List<GenerationGrammarTrigger> grammarTriggers = const [],
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
  }) => throw UnimplementedError('LiteRT profiles omit constrained cases');
  @override
  Future<Map<String, dynamic>> createStructuredJson(
    String prompt,
    ValidationProfile profile,
    LlamaStructuredOutput<Object?> output, {
    required int maxTokens,
  }) => throw UnimplementedError('LiteRT profiles omit constrained cases');
  bool rejectBatching = false;
  String? batchingFault;
  bool _batchingSeen = false;
  var disposed = false;
  var cancelled = false;
  var loads = 0;
  var ready = false;
  bool ignoresReadiness = false;
  bool ignoresStop = false;
  int? failOnLoad;
  var disposeCalls = 0;
  var generated = 0;
  var wrongArithmetic = false;
  var wrongHistory = false;
  final requests = <Map<String, dynamic>>[];
  var ignoresCancellation = false;
  String? cancellationFault;
  String backendName = 'LiteRT-LM CPU';
  Map<String, dynamic> metadata = {};
  int? switchAfterLoad;
  Completer<void>? pauseReload;
  var timeout = false;
  bool tokenizeTimeout = false;
  Duration? tokenizeDelay;
  String? featureFault;
  bool toolsSeen = false;
  var cleanupFails = false;
  String? earlyFault;
  num earlyCancelMs = 1;
  bool _earlyCancelSeen = false;
  bool _grammarSeen = false;
  String? overlapFault;
  final overlapCalls = <bool>[];
  String? grammarFault;
  String? requiredFault;
  @override
  Future<void> load(String location, ValidationProfile profile) async {
    if (location.endsWith('.missing')) {
      throw LlamaModelException('missing model');
    }
    loads++;
    ready = true;
    if (loads == failOnLoad) throw LlamaModelException('reload failed');
    if (loads == 2) await pauseReload?.future;
  }

  @override
  Future<void> unload() async {
    ready = false;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    disposed = true;
    if (cleanupFails) throw StateError('cleanup failure');
  }

  @override
  void cancel() {
    cancelled = true;
  }

  @override
  Future<Map<String, dynamic>> diagnostics() async => {
    'model_metadata': metadata,
    'backend_name': switchAfterLoad != null && loads >= switchAfterLoad!
        ? 'Metal'
        : backendName,
  };
  @override
  Future<List<int>> tokenize(String text) async {
    if (tokenizeTimeout) await Completer<void>().future;
    if (tokenizeDelay != null) await Future<void>.delayed(tokenizeDelay!);
    return utf8.encode(text);
  }

  @override
  Future<String> detokenize(List<int> tokens) async => utf8.decode(tokens);
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
    generated++;
    if (grammar != null) {
      _grammarSeen = true;
      final fixture = profile.fixtures['invalid_grammar'] as Map;
      switch (grammarFault) {
        case 'accepted':
          break;
        case 'wrong_type':
          throw LlamaStateException(fixture['native_message'] as String);
        case 'wrong_message':
          throw LlamaInferenceException('Generation failed', 'other failure');
        default:
          throw isWeb
              ? LlamaInferenceException(
                  'Generation failed',
                  'Failed to start generation: Failed to initialize sampler '
                      'chain (invalid grammar): unexpected end of input',
                )
              : LlamaInferenceException(fixture['native_message'] as String);
      }
    }
    if (requiredFault != null && toolChoice == ToolChoice.required) {
      throw LlamaUnsupportedException(
        requiredFault == 'documented'
            ? 'ToolChoice.required for Qwen3-Coder XML tool calling needs a '
                  'lazy tool-call grammar, but the active backend applies '
                  'grammars from the first token (for example, WebGPU).'
            : 'ToolChoice.required is unsupported',
      );
    }
    if (cancelOnListen) {
      _earlyCancelSeen = true;
      final output = earlyFault == 'output';
      return {
        'content': output ? 'hello' : '',
        'thinking': '',
        'chunks': output ? 1 : 0,
        'finish_reasons': raw ? [] : ['stop'],
        'tool_call_deltas': [],
        'stream_completed': true,
        'completion_order_valid': true,
        'cancel_requested': true,
        'cancel_on_listen': true,
        'chunks_before_cancel': earlyFault == 'late_cancel' ? 1 : 0,
        'cancel_to_done_ms': earlyCancelMs,
        'metrics': {'native_decode_tokens': output ? 8 : null},
      };
    }
    if ((_earlyCancelSeen && earlyFault == 'lingering') ||
        (_grammarSeen && grammarFault == 'recovery')) {
      _grammarSeen = false;
      _earlyCancelSeen = false;
      return {
        'content': '',
        'thinking': '',
        'chunks': 0,
        'finish_reasons': raw ? [] : ['stop'],
        'tool_call_deltas': [],
        'stream_completed': true,
        'completion_order_valid': true,
        'cancel_requested': false,
        'metrics': {'native_decode_tokens': null},
      };
    }
    if (featureFault == 'tool_followup_error' &&
        prompt.contains('temperature_celsius from the tool result')) {
      throw StateError('synthetic tool followup failure');
    }
    if (tools != null) toolsSeen = true;
    if (!ready && !ignoresReadiness) throw LlamaContextException('Not loaded');
    final adjusted = streamBatchTokens != null || streamBatchBytes != null;
    requests.add({
      'prompt': prompt,
      'history': history,
      'batch_tokens': streamBatchTokens,
      'batch_bytes': streamBatchBytes,
      'stop_sequences': stopSequences,
    });
    if (adjusted && rejectBatching) {
      _batchingSeen = true;
      if (batchingFault == 'wrong_error') throw StateError('failed');
      throw LlamaUnsupportedException(
        batchingFault == 'wrong_option'
            ? 'unrelated option'
            : 'streamBatchTokenThreshold streamBatchByteThreshold',
      );
    }
    final recovering = _batchingSeen && !adjusted;
    if (adjusted) _batchingSeen = true;
    if (timeout) return Completer<Map<String, dynamic>>().future;
    return {
      'enable_thinking': featureFault == 'thinking_config'
          ? false
          : enableThinking ?? profile.enableThinking,
      'tools': tools?.map((t) => t.toJson()).toList(),
      'tool_choice': featureFault == 'tool_config' ? null : toolChoice?.name,
      'stop_sequences': stopSequences ?? const <String>[],
      'content': cancelAfterMs != null && cancellationFault == 'empty'
          ? ''
          : cancelAfterMs != null && cancellationFault == 'prefix'
          ? 'wrong'
          : prompt.contains('temperature_celsius from the tool result')
          ? featureFault == 'tool_followup'
                ? '18'
                : '17'
          : prompt == profile.fixtureText('unicode_generation', 'prompt')
          ? featureFault == 'unicode'
                ? 'Montréal �'
                : profile.fixtureText('unicode_generation', 'expected')
          : prompt.contains('alpha cedar17 omega')
          ? stopSequences != null && !ignoresStop
                ? 'alpha '
                : 'alpha cedar17 omega'
          : (adjusted && batchingFault == 'content') ||
                (recovering && batchingFault == 'recovery')
          ? 'corrupted'
          : history != null ||
                prompt.contains(profile.fixtureText('history', 'user'))
          ? wrongHistory
                ? '77777777777777777777777777777777'
                : profile.fixtureText('history', 'expected')
          : prompt.contains('3 + 4')
          ? wrongArithmetic
                ? '2'
                : '3 + 4 = 7'
          : prompt.contains('2 + 2')
          ? wrongArithmetic
                ? '2'
                : '4'
          : 'hello',
      'thinking': featureFault == 'thinking_leak'
          ? 'leaked'
          : enableThinking == true && featureFault != 'thinking_missing'
          ? 'Two plus two is four.'
          : adjusted && batchingFault == 'thinking'
          ? 'changed'
          : '',
      'chunks': adjusted ? 32 : 5,
      'stream_batch_tokens': batchingFault == 'config'
          ? 8
          : streamBatchTokens ?? 8,
      'stream_batch_bytes': streamBatchBytes ?? 512,
      'stream_completed':
          !(adjusted && batchingFault == 'incomplete') &&
          !(recovering && batchingFault == 'recovery'),
      'completion_order_valid': !(adjusted && batchingFault == 'order'),
      'tool_call_deltas':
          featureFault == 'tool_recovery' && toolsSeen && tools == null
          ? [
              {
                'index': featureFault == 'tool_index' ? 1 : 0,
                'function': {'name': 'get_weather'},
              },
            ]
          : _callsTool(profile, prompt, tools, toolChoice)
          ? [
              {
                'index': featureFault == 'tool_index' ? 1 : 0,
                'function': {
                  'name': 'get_weather',
                  'arguments': featureFault == 'tool_malformed'
                      ? '{broken'
                      : featureFault == 'tool_arguments'
                      ? '{"city":"Paris"}'
                      : '{"city":"Montréal"}',
                },
              },
            ]
          : adjusted && batchingFault == 'tools'
          ? [
              {'index': 0},
            ]
          : [],
      'finish_reasons': _callsTool(profile, prompt, tools, toolChoice)
          ? [featureFault == 'tool_finish' ? 'length' : 'tool_calls']
          : raw
          ? []
          : [
              (adjusted && batchingFault == 'finish') ||
                      (featureFault == 'tool_text_length' &&
                          toolsSeen &&
                          (tools == null || toolChoice == ToolChoice.none) &&
                          !prompt.contains(
                            'temperature_celsius from the tool result',
                          ))
                  ? 'length'
                  : 'stop',
            ],
      'prompt': prompt,
      'cancel_requested': cancelAfterFirst || cancelAfterMs != null,
      'cancel_on_listen': false,
      'cancel_after_ms': cancelAfterMs,
      'chunks_before_cancel': cancelAfterFirst ? 1 : null,
      'cancel_to_done_ms': cancelAfterFirst || cancelAfterMs != null ? 1 : null,
      'metrics': {
        'native_decode_tokens':
            maxTokens == 1 ||
                ((cancelAfterFirst || cancelAfterMs != null) &&
                    !ignoresCancellation)
            ? cancellationFault == 'zero'
                  ? 0
                  : 1
            : 8,
        'wall_ms': 16,
        'native_decode_tps': 12,
        'estimated_wall_tps': 10,
        'ttfa_ms': 5,
      },
    };
  }

  bool _callsTool(
    ValidationProfile profile,
    String prompt,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
  ) =>
      tools != null &&
      (prompt == profile.fixtureText('tools', 'prompt')
          ? toolChoice != ToolChoice.none || featureFault == 'tool_none'
          : featureFault == 'auto_text_tool');

  @override
  Future<Map<String, dynamic>> generateOverlapping(
    String first,
    String second,
    ValidationProfile profile, {
    required bool raw,
    required int firstMaxTokens,
    required bool cancelFirst,
    int? secondAfterMs,
  }) async {
    generated++;
    overlapCalls.add(cancelFirst);
    final fault = overlapFault;
    Map<String, dynamic> completed(String content, num firstDelta, num ended) =>
        {
          'content': content,
          'thinking': '',
          'chunks': 2,
          'finish_reasons': raw ? [] : ['stop'],
          'tool_call_deltas': [],
          'stream_completed': true,
          'completion_order_valid': true,
          'cancel_requested': false,
          'timeline_ms': {'first_delta': firstDelta, 'ended': ended},
        };
    Map<String, dynamic> failed(String type, {required bool state}) => {
      'error_type': type,
      'state_exception': state,
      'message': 'LlamaException: generation is already in progress',
      'content': '',
      'chunks': 0,
      'stream_completed': false,
    };
    if (cancelFirst) {
      return {
        'first': completed('Once', 1, 3),
        'second': fault == 'restart_error'
            ? failed('LlamaInferenceException', state: false)
            : fault == 'restart_empty'
            ? completed('', 4, 5)
            : completed('hello', fault == 'restart_interleave' ? 2 : 4, 5),
        'cancel_first': true,
        'second_issued': true,
        'first_ended_before_second_issued': fault == 'restart_late',
        'first_cancelled_before_second_issued': true,
        'first_deltas_after_second_ended': 0,
        'timeline_ms': {
          'first_cancel': 1,
          'second_issued': 1,
          'second_ended': 5,
          'first_ended': 3,
        },
      };
    }
    return {
      'first': completed('hello', 1, fault == 'overlap_late' ? 1.5 : 4),
      'second': fault == 'overlap_accepted'
          ? completed('hello', 2, 3)
          : failed(
              fault == 'overlap_wrong_type'
                  ? 'LlamaInferenceException'
                  : 'LlamaStateException',
              state: fault != 'overlap_wrong_type',
            ),
      'cancel_first': false,
      'second_issued': true,
      'first_ended_before_second_issued': false,
      'first_cancelled_before_second_issued': false,
      'first_deltas_after_second_ended': fault == 'overlap_stalled' ? 0 : 1,
      'timeline_ms': {
        'first_cancel': 3,
        'second_issued': 1,
        'second_ended': 2,
        'first_ended': fault == 'overlap_late' ? 1.5 : 4,
      },
    };
  }
}

/// Release-selection double includes the new public token-count boundary.
class CountingFakeEngine extends FakeEngine
    implements
        TokenCountValidationEngine,
        StateValidationEngine,
        SamplerValidationEngine {
  @override
  Future<LlamaEngineCapabilities> samplerCapabilities() async =>
      const LlamaEngineCapabilities(isSupported: true, supportsPenalty: true);
  @override
  Future<String> generateSampled(String prompt, GenerationParams params) async {
    if (params.minP != 0) {
      throw LlamaUnsupportedException('LiteRT Min-P unsupported');
    }
    throw UnimplementedError();
  }

  @override
  Future<LlamaStateIdentity> stateIdentity() async =>
      throw LlamaUnsupportedException('Identity outside this fake');

  @override
  Future<int> getTokenCount(String text) async => (await tokenize(text)).length;
  @override
  bool get supportsStatePersistence => false;
  @override
  bool get supportsNextTokenScoring => false;
  @override
  Future<List<int>> tokenizeStatePrompt(String text) =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> scoreStatePrompt(
    String text, {
    List<int> candidates = const [],
    int topK = 0,
    required bool reuse,
  }) async => throw LlamaUnsupportedException('LiteRT scoring unsupported');
  @override
  Future<bool> saveState(String path, List<int> tokens) async =>
      throw LlamaUnsupportedException('LiteRT state unsupported');
  @override
  Future<List<int>> loadState(String path, int capacity) async =>
      throw LlamaUnsupportedException('LiteRT state unsupported');
  @override
  Future<Map<String, dynamic>> generateStatePrompt(
    String text, {
    required bool reuse,
  }) => throw UnimplementedError();
}

/// Removes the records that catalog [version] did not derive for [selected],
/// renumbering events as that catalog's runner would have written them.
void dropUndeclared(
  List<Map<String, dynamic>> events,
  ValidationProfile selected,
  int version,
) {
  final inventory = version == 0
      ? selected.legacyCaseIds
      : selected.caseIdsForCatalog(version);
  events.removeWhere(
    (e) =>
        (e['type'] == 'case' || e['type'] == 'case_start') &&
        !inventory.contains(e['case_id']),
  );
  if (version > 0) {
    for (final event in events.where((e) => e['type'] == 'case')) {
      final id = event['case_id'] as String;
      event['case_version'] = validationCase(
        id,
        catalogVersion: version,
      ).version;
      event['fixture_hash'] = jsonHash(
        selected.caseFixtures(id, catalogVersion: version),
      );
    }
  }
  var sequence = 0;
  for (final event in events.skip(1)) {
    event['sequence'] = sequence++;
  }
  events.first['case_ids'] = inventory;
}

Future<({ValidationReport report, List<Map<String, dynamic>> events})> run(
  FakeEngine engine, {
  ValidationProfile? selected,
  Map<String, dynamic> environment = const {},
}) async {
  final events = <Map<String, dynamic>>[];
  await ValidationRunner(
    profile: selected ?? profile(),
    engine: engine,
    emit: (event) async {
      events.add(event);
    },
    caseTimeout: const Duration(milliseconds: 30),
  ).run(
    'model.litertlm',
    runId: 'test-run',
    preparation: {
      'verified': true,
      'sha256': (selected ?? profile()).modelHash,
      'bytes': (selected ?? profile()).model['bytes'],
    },
    environment: {
      'source_commit': List.filled(40, 'a').join(),
      'source_dirty': false,
      'hook_sha256': List.filled(64, 'b').join(),
      'native_tag': 'v0.4.0',
      'litert_tag': '0.17.0-3',
      ...environment,
    },
  );
  return (
    report: ValidationReport.parse(events.map(jsonEncode).join('\n')),
    events: events,
  );
}

void main() {
  test('LiteRT profiles preserve automatic and explicit device selection', () {
    for (final device in ComputeDevice.values) {
      final selected = profile(backend: device.name);
      final params = selected.loadParams;
      expect(params, isA<LiteRtLmModelParams>());
      expect(params.device, device);
      expect(
        params.preferredBackend,
        device == ComputeDevice.cpu ? GpuBackend.cpu : GpuBackend.auto,
      );
      expect(
        params.gpuLayers,
        device == ComputeDevice.cpu ? 0 : ModelParams.maxGpuLayers,
      );
      expect(
        selected.requiresAcceleratorProof,
        device == ComputeDevice.gpu || device == ComputeDevice.npu,
      );
      expect(selected.effectiveConfig['backend'], device.name);
      expect(selected.effectiveConfig['gpu_layers_hint'], params.gpuLayers);
      expect(params.numberOfThreads, device == ComputeDevice.cpu ? 4 : 0);
      expect(selected.effectiveConfig['batch_threads'], 0);
      expect(
        selected.effectiveConfig['sampling_application'],
        device == ComputeDevice.npu
            ? 'runtime_defaults_requested_sampler_not_applied'
            : 'requested_sampler',
      );
    }
  });

  test(
    'tool followup errors retain successful call evidence and phase',
    () async {
      final result = await run(
        FakeEngine()..featureFault = 'tool_followup_error',
        selected: profile(release: true),
      );
      final record = result.report.cases.singleWhere(
        (c) => c['case_id'] == 'C07.tools',
      );
      expect(record['status'], 'ERROR');
      expect(record['operation_phase'], 'tools.auto.tool_result_followup');
      expect((record['trials'] as List).single['mode_passed'], true);
      expect((record['trials'] as List).single['tool_choice'], 'auto');
      expect(result.report.qualified, false);
    },
  );

  test('native control cannot execute public release feature cases', () async {
    final data =
        jsonDecode(
              File(
                'assets/profiles/npu-qualcomm-sm8650.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    data['execution_path'] = 'native_c_api';
    data['selection'] = 'release';
    data['enable_thinking'] = true;
    final result = await run(
      FakeEngine(),
      selected: ValidationProfile.fromJson(data),
    );
    for (final id in [
      'C02.generate',
      'C05.thinking',
      'C07.tools',
      'C07.tools.auto_text',
    ]) {
      final record = result.report.cases.singleWhere((c) => c['case_id'] == id);
      expect(record['status'], 'NOT_RUN');
      expect(record['reason'], 'Requires public chat feature controls');
    }
  });

  for (final entry in {
    'unicode': 'C02.generate',
    'thinking_config': 'C05.thinking',
    'thinking_leak': 'C05.thinking',
    'thinking_missing': 'C05.thinking',
    'tool_config': 'C07.tools',
    'tool_arguments': 'C07.tools',
    'tool_finish': 'C07.tools',
    'tool_followup': 'C07.tools',
    'tool_recovery': 'C07.tools',
    'tool_none': 'C07.tools',
    'tool_index': 'C07.tools',
    'tool_malformed': 'C07.tools',
  }.entries) {
    test('release feature rejects ${entry.key}', () async {
      final result = await run(
        FakeEngine()..featureFault = entry.key,
        selected: profile(release: true),
      );
      expect(
        result.report.cases.singleWhere(
          (c) => c['case_id'] == entry.value,
        )['status'],
        'FAIL',
      );
      expect(result.report.qualified, false);
    });
  }

  test('release tools accept a text answer that reaches its budget', () async {
    final result = await run(
      FakeEngine()..featureFault = 'tool_text_length',
      selected: profile(release: true),
    );
    final tools = result.report.cases.singleWhere(
      (c) => c['case_id'] == 'C07.tools',
    );
    final trials = (tools['trials'] as List).cast<Map>();

    expect(
      trials.singleWhere((t) => t['tool_choice'] == 'none')['finish_reasons'],
      ['length'],
    );
    expect((tools['recovery'] as Map)['finish_reasons'], ['length']);
    expect(tools['status'], 'PASS');
  });

  test('catalog three preserves unimplemented feature obligations', () async {
    final selected = profile(release: true);
    final result = await run(FakeEngine(), selected: selected);
    final events = result.events;
    dropUndeclared(events, selected, 3);
    events.first['catalog'] = selected.catalogForVersion(3);
    events.first['catalog_hash'] = jsonHash(events.first['catalog']);
    for (final record in events.where((e) => e['type'] == 'case')) {
      final id = record['case_id'] as String;
      record['fixture_hash'] = jsonHash(
        selected.caseFixtures(id, catalogVersion: 3),
      );
      if (['C05.thinking', 'C07.tools', 'C02.generate'].contains(id)) {
        record['case_version'] = 1;
        record['status'] = 'NOT_RUN';
      }
    }
    final historical = ValidationReport.parse(
      events.map(jsonEncode).join('\n'),
    );
    expect(historical.problems, isEmpty);
    expect(historical.qualified, false);
    events.firstWhere(
      (e) => e['type'] == 'case' && e['case_id'] == 'C07.tools',
    )['status'] = 'PASS';
    expect(
      ValidationReport.parse(events.map(jsonEncode).join('\n')).problems,
      contains(
        'Unimplemented catalog case cannot claim an executed result: C07.tools',
      ),
    );
  });

  test(
    'first-use timeout preserves deferred initialization attribution',
    () async {
      final result = await run(FakeEngine()..tokenizeTimeout = true);
      final load = result.report.cases.first;
      expect(load['load_scope'], 'public_load_and_readiness');
      expect(load['native_initialization_proven'], false);
      final failed = result.report.cases.singleWhere(
        (c) => c['case_id'] == 'C02.unicode',
      );
      expect(failed['status'], 'ERROR');
      expect(failed['reason'], 'case_timeout');
      expect(
        failed['operation_phase'],
        'tokenize_including_possible_deferred_initialization',
      );
      expect(failed['timeout_ms'], 30);
      expect(failed['elapsed_ms'], greaterThanOrEqualTo(30));
      expect(
        result.report.cases.skip(2).every((c) => c['status'] == 'NOT_RUN'),
        true,
      );
      expect(result.report.qualified, false);

      final success = await run(FakeEngine());
      final unicode = success.report.cases.singleWhere(
        (c) => c['case_id'] == 'C02.unicode',
      );
      expect(unicode['tokenize_call_ms'], isNonNegative);
      expect(unicode['detokenize_call_ms'], isNonNegative);
      expect(
        unicode['tokenize_timing_scope'],
        'public_call_including_possible_deferred_initialization',
      );
    },
  );

  test('report separates missing GPU proof from functional failures', () async {
    final passing = await run(
      FakeEngine()..backendName = 'LiteRT-LM GPU',
      selected: profile(backend: 'gpu'),
    );
    expect(passing.report.assertionsPassed, true);
    expect(passing.report.qualified, false);
    expect(passing.report.qualificationGaps, ['accelerator_evidence_missing']);
    expect((passing.report.toJson()['summary'] as Map)['qualification_gaps'], [
      'accelerator_evidence_missing',
    ]);
    expect(
      passing.report.toHtml(),
      contains('does not by itself establish incompatibility'),
    );

    final failed = await run(FakeEngine()..wrongArithmetic = true);
    expect(failed.report.qualificationGaps, contains('assertion_failure'));
    expect(
      failed.report.qualificationGaps,
      isNot(contains('accelerator_evidence_missing')),
    );

    final complete = await run(
      CountingFakeEngine(),
      selected: profile(release: true),
      environment: {'os': 'android'},
    );
    expect(complete.report.qualificationGaps, isEmpty);
    final broken = await run(FakeEngine()..failOnLoad = 1);
    expect(
      broken.report.qualificationGaps,
      containsAll(['execution_error', 'cases_not_run']),
    );
    expect((await run(FakeEngine())).report.qualificationGaps, isEmpty);
  });

  ValidationProfile focused(List<String> features) =>
      ValidationProfile.fromJson(
        profile().toJson()
          ..['selection'] = 'focused'
          ..['focus_features'] = features,
      );

  test(
    'focused lifecycle runs a second dispose/load/generation cycle',
    () async {
      final engine = FakeEngine();
      final result = await run(engine, selected: focused(['lifecycle']));
      expect(result.report.qualified, true);
      expect(
        engine.loads,
        4,
      ); // Initial, first cycle, invalid-file recovery, second.
      expect(engine.disposeCalls, 3); // Both cycles and final cleanup.
      expect(result.report.cases.last['case_id'], 'C09.reload.second');
      expect(result.report.cases.last['status'], 'PASS');
      expect(
        result.report.cases.map((c) => c['case_id']),
        isNot(contains('C07.tools')),
      );
    },
  );

  test(
    'second-cycle load failure stays visible and cleanup still runs',
    () async {
      final engine = FakeEngine()..failOnLoad = 4;
      final result = await run(engine, selected: focused(['lifecycle']));
      expect(result.report.qualified, false);
      expect(result.report.cases.last['status'], 'ERROR');
      expect(result.report.cases.last['error_type'], 'LlamaModelException');
      expect(engine.disposeCalls, 3);
      expect(result.report.cleanupPassed, true);
    },
  );

  test(
    'focused selection adds only matching obligations to the quick core',
    () async {
      final selected = focused(['streaming', 'tools']);
      expect(selected.caseIds, [
        ...profile().caseIds,
        'C07.tools',
        'C07.tools.auto_text',
        'C10.stop',
        'C11.batching',
      ]);
      expect(selected.focusFeatures, ['streaming', 'tools']);
      final result = await run(FakeEngine(), selected: selected);
      expect(result.report.qualified, true);
      expect(
        result.report.cases
            .where((c) => c['status'] == 'NOT_RUN')
            .map((c) => c['case_id']),
        isEmpty,
      );
      expect(result.report.problems, isEmpty);
    },
  );

  test(
    'focused batching verifies reconstruction, configuration and recovery',
    () async {
      final engine = FakeEngine();
      final result = await run(engine, selected: focused(['batching']));
      final record = result.report.cases.last;
      expect(record['case_id'], 'C11.batching');
      expect(result.report.qualified, true);
      expect(record['case_version'], 2);
      expect((record['batched'] as Map)['chunks'], 32);
      expect((record['control'] as Map)['chunks'], 5);
      expect(
        engine.requests.where(
          (r) => r['batch_tokens'] == 1 && r['batch_bytes'] == 1,
        ),
        hasLength(1),
      );
      expect(record['reconstruction_equal'], true);
      expect(record['configurations_verified'], true);
    },
  );

  for (final fault in [
    'content',
    'thinking',
    'finish',
    'config',
    'incomplete',
    'order',
    'recovery',
  ]) {
    test('batching rejects $fault mismatch', () async {
      final result = await run(
        FakeEngine()..batchingFault = fault,
        selected: focused(['batching']),
      );
      expect(result.report.cases.last['status'], 'FAIL');
      expect(result.report.qualified, false);
      expect(result.report.cleanupPassed, true);
    });
  }

  test(
    'unqualified tool output and NPU defaults remain explicit gaps',
    () async {
      final tool = await run(
        FakeEngine()..batchingFault = 'tools',
        selected: focused(['batching']),
      );
      expect(tool.report.cases.last['status'], 'NOT_RUN');
      expect(tool.report.qualified, false);
      final webData =
          jsonDecode(
                File(
                  'assets/profiles/tiny-gguf-batching.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final web = await run(
        FakeEngine()
          ..isWeb = true
          ..backendName = 'CPU',
        selected: ValidationProfile.fromJson(webData),
      );
      expect(web.report.cases.last['status'], 'NOT_RUN');
      expect(web.report.cases.last['reason'], contains('browser'));
      final data = focused(['batching']).toJson()..['backend'] = 'npu';
      for (final native in [false, true]) {
        if (native) data['execution_path'] = 'native_c_api';
        final result = await run(
          FakeEngine()..backendName = 'LiteRT-LM NPU',
          selected: ValidationProfile.fromJson(data),
        );
        expect(result.report.cases.last['status'], 'NOT_RUN');
        expect(
          result.report.cases.last['reason'],
          contains(native ? 'bypasses' : 'sampling'),
        );
      }
    },
  );

  test(
    'LiteRT Web requires both named typed rejections and recovery',
    () async {
      for (final fault in [null, 'wrong_option', 'wrong_error', 'recovery']) {
        final result = await run(
          FakeEngine()
            ..isWeb = true
            ..rejectBatching = true
            ..batchingFault = fault,
          selected: focused(['batching']),
        );
        expect(
          result.report.cases.last['status'],
          fault == null
              ? 'PASS'
              : fault == 'wrong_error'
              ? 'ERROR'
              : 'FAIL',
        );
        if (fault == null) {
          expect(
            (result.report.cases.last['rejected_options'] as List),
            hasLength(2),
          );
          expect(
            result.report.cases.last['coverage'],
            'litert_web_native_option_rejection_and_recovery',
          );
        }
      }
      final ignored = await run(
        FakeEngine()..isWeb = true,
        selected: focused(['batching']),
      );
      expect(ignored.report.cases.last['status'], 'FAIL');
    },
  );

  test(
    'previous schema-2 catalog preserves its original obligations',
    () async {
      final selected = focused(['streaming']);
      final result = await run(FakeEngine(), selected: selected);
      final events = result.events;
      dropUndeclared(events, selected, 1);
      events.first['catalog'] = selected.catalogForVersion(1);
      events.first['catalog_hash'] = jsonHash(events.first['catalog']);
      final batching = events.singleWhere(
        (e) => e['type'] == 'case' && e['case_id'] == 'C11.batching',
      );
      batching['case_version'] = 1;
      batching['fixture_hash'] = jsonHash(
        selected.caseFixtures('C11.batching', catalogVersion: 1),
      );
      batching['status'] = 'NOT_RUN';
      final stop = events.singleWhere(
        (e) => e['type'] == 'case' && e['case_id'] == 'C10.stop',
      );
      stop['case_version'] = 1;
      stop['fixture_hash'] = jsonHash(
        selected.caseFixtures('C10.stop', catalogVersion: 1),
      );
      stop['status'] = 'NOT_RUN';
      final report = ValidationReport.parse(events.map(jsonEncode).join('\n'));
      expect(report.problems, isEmpty);
      expect(report.cases.last['status'], 'NOT_RUN');
      events.first['catalog'] = selected.catalogForVersion(1)
        ..['version'] = 999;
      events.first['catalog_hash'] = jsonHash(events.first['catalog']);
      expect(
        ValidationReport.parse(events.map(jsonEncode).join('\n')).qualified,
        false,
      );
    },
  );

  test(
    'stop marker requires the exact prefix, forwarded control and recovery',
    () async {
      for (final ignored in [false, true]) {
        final engine = FakeEngine()..ignoresStop = ignored;
        final result = await run(engine, selected: focused(['streaming']));
        final record = result.report.cases.singleWhere(
          (c) => c['case_id'] == 'C10.stop',
        );
        expect(record['status'], ignored ? 'FAIL' : 'PASS');
        expect(record['expected_prefix'], 'alpha ');
        expect(
          engine.requests.any(
            (r) =>
                r['stop_sequences'] is List &&
                (r['stop_sequences'] as List).contains('cedar17'),
          ),
          true,
        );
        expect(record['recovery']['content'], isNotEmpty);
      }
    },
  );
  test(
    'readiness guard cannot pass when unloaded generation is accepted',
    () async {
      for (final ignored in [false, true]) {
        final result = await run(
          FakeEngine()..ignoresReadiness = ignored,
          selected: focused(['guards']),
        );
        final record = result.report.cases.singleWhere(
          (c) => c['case_id'] == 'C12.guards',
        );
        expect(record['status'], ignored ? 'FAIL' : 'PASS');
        expect(record['recovery']['content'], isNotEmpty);
        expect(result.report.cleanupPassed, true);
      }
    },
  );
  test(
    'catalog two cannot claim new stop and readiness guard execution',
    () async {
      final selected = profile(release: true);
      final result = await run(FakeEngine(), selected: selected);
      final events = result.events;
      dropUndeclared(events, selected, 2);
      events.first['catalog'] = selected.catalogForVersion(2);
      events.first['catalog_hash'] = jsonHash(events.first['catalog']);
      expect(
        (events.first['catalog']['fixtures'] as Map).containsKey('stop'),
        false,
      );
      final report = ValidationReport.parse(events.map(jsonEncode).join('\n'));
      expect(report.qualified, false);
      expect(
        report.problems,
        contains(
          'Unimplemented catalog case cannot claim an executed result: C10.stop',
        ),
      );
      expect(
        report.problems,
        contains(
          'Unimplemented catalog case cannot claim an executed result: C12.guards',
        ),
      );
    },
  );

  test('batching feature cannot downgrade to old catalog', () async {
    final selected = focused(['batching']);
    expect(() => selected.catalogForVersion(1), throwsFormatException);
  });

  test(
    'catalog three requires guard reload placement without changing old logs',
    () async {
      final data =
          jsonDecode(
                File('assets/profiles/chat-gguf-metal.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      data['selection'] = 'focused';
      data['focus_features'] = ['guards'];
      final selected = ValidationProfile.fromJson(data);
      final engine = FakeEngine()..backendName = 'Metal';
      final result = await run(engine, selected: selected);
      final cases = result.report.cases;
      const load =
          'load_tensors: offloaded 7/7 layers to GPU\nMTL0 compute buffer size = 64.0 MiB\n';
      final manifest = result.events.first;
      expect(engine.loads, 4);
      expect(inspectPlacement(manifest, cases, load * 4)['verified'], true);
      expect(inspectPlacement(manifest, cases, load * 3)['verified'], false);
      expect(
        inspectPlacement(
          manifest,
          cases.where((c) => c['case_id'] != 'C12.guards').toList(),
          load * 4,
        )['verified'],
        false,
      );
      final old = {...manifest, 'catalog': selected.catalogForVersion(2)};
      expect(
        inspectPlacement(
          old,
          cases.where((c) => c['case_id'] != 'C12.guards').toList(),
          load * 3,
        )['verified'],
        true,
      );
    },
  );

  test(
    'invalid feature selections and fixture overrides fail before execution',
    () {
      for (final patch in <Map<String, dynamic>>[
        {'selection': 'focused'},
        {'selection': 'focused', 'focus_features': []},
        {
          'selection': 'focused',
          'focus_features': ['tools', 'tools'],
        },
        {
          'selection': 'focused',
          'focus_features': ['unknown'],
        },
        {'focus_features': []},
        {
          'focus_features': ['tools'],
        },
        {
          'fixtures': {
            'hello': {'prompt': 3},
          },
        },
        {
          'fixtures': {
            'hello': {'unknown': 'ignored'},
          },
        },
        {
          'fixtures': {
            'unknown': {'prompt': 'ignored'},
          },
        },
      ]) {
        expect(
          () => ValidationProfile.fromJson(profile().toJson()..addAll(patch)),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'catalog records resolved prompts, versions and explicit omissions',
    () async {
      final data = profile().toJson();
      (data['fixtures'] as Map)['hello'] = {'prompt': 'Please answer hello.'};
      final selected = ValidationProfile.fromJson(data);
      final engine = FakeEngine();
      final result = await run(engine, selected: selected);
      expect(result.report.qualified, true);
      final manifest = result.events.first;
      expect(manifest['schema_version'], 2);
      expect(manifest['catalog_hash'], jsonHash(selected.catalog));
      expect((manifest['catalog'] as Map)['fixtures'], selected.fixtures);
      expect(
        engine.requests
            .where((r) => r['prompt'] == 'Please answer hello.')
            .length,
        greaterThan(1),
      );
      final omitted = ((manifest['catalog'] as Map)['cases'] as List)
          .cast<Map>()
          .singleWhere((c) => c['id'] == 'C07.tools');
      expect(omitted['selected'], false);
      expect(omitted['omission_reason'], 'outside_selected_features');
      for (final record in result.report.cases) {
        expect(
          record['case_version'],
          validationCase(record['case_id'] as String).version,
        );
        expect(
          record['fixture_hash'],
          jsonHash(selected.caseFixtures(record['case_id'] as String)),
        );
      }
    },
  );

  test('rehashed catalog edits and missing metadata cannot qualify', () async {
    for (final omit in [false, true]) {
      final result = await run(FakeEngine());
      final manifest = result.events.first;
      if (omit) {
        manifest.remove('catalog');
      } else {
        final catalog = jsonDecode(jsonEncode(manifest['catalog'])) as Map;
        (catalog['fixtures'] as Map)['history']['expected'] =
            'a different code';
        manifest['catalog'] = catalog;
      }
      manifest['catalog_hash'] = jsonHash(manifest['catalog']);
      final report = ValidationReport.parse(
        result.events.map(jsonEncode).join('\n'),
      );
      expect(report.qualified, false);
      expect(
        report.problems,
        contains('Catalog does not match the executable profile'),
      );
    }
  });

  test('case version and fixture identity are independently checked', () async {
    for (final field in ['case_version', 'fixture_hash']) {
      final result = await run(FakeEngine());
      result.events.firstWhere((e) => e['type'] == 'case')[field] =
          field == 'case_version' ? 2 : '0' * 64;
      final report = ValidationReport.parse(
        result.events.map(jsonEncode).join('\n'),
      );
      expect(report.qualified, false);
      expect(
        report.problems,
        contains('Case version or fixture identity mismatch: C01.load'),
      );
    }
  });

  test(
    'legacy quick journals remain readable without invented catalog metadata',
    () async {
      final result = await run(FakeEngine());
      dropUndeclared(result.events, profile(), 0);
      result.events.first
        ..['schema_version'] = 1
        ..remove('catalog')
        ..remove('catalog_hash');
      for (final event in result.events) {
        event
          ..remove('case_version')
          ..remove('fixture_hash');
      }
      final report = ValidationReport.parse(
        result.events.map(jsonEncode).join('\n'),
      );
      expect(report.qualified, true);
      expect(report.manifest.containsKey('catalog'), false);
    },
  );

  test('legacy schema cannot claim unchecked catalog provenance', () async {
    final result = await run(FakeEngine());
    result.events.first['schema_version'] = 1;
    final report = ValidationReport.parse(
      result.events.map(jsonEncode).join('\n'),
    );
    expect(report.qualified, false);
    expect(
      report.problems,
      contains('Catalog metadata requires result schema 2'),
    );
    expect(
      report.toHtml(),
      contains('catalog version: unavailable in legacy journal'),
    );
  });

  test(
    'focused journals cannot downgrade to legacy selection semantics',
    () async {
      final result = await run(FakeEngine(), selected: focused(['lifecycle']));
      result.events.first['schema_version'] = 1;
      final report = ValidationReport.parse(
        result.events.map(jsonEncode).join('\n'),
      );
      expect(report.qualified, false);
      expect(
        report.problems,
        contains('Focused selection requires result schema 2'),
      );
    },
  );

  test('Gemma CPU control locks identity and matches NPU prompt settings', () {
    final selected = ValidationProfile.fromJson(
      jsonDecode(
            File('assets/profiles/gemma3-litert-cpu.json').readAsStringSync(),
          )
          as Map<String, dynamic>,
    );
    expect(selected.backend, 'cpu');
    expect(selected.contextSize, 1280);
    expect(selected.threads, 4);
    expect(selected.maxTokens, 32);
    expect(selected.enableThinking, true);
    expect(selected.effectiveConfig['enable_thinking'], true);
    expect(
      selected.effectiveConfig['sampling_application'],
      'requested_sampler',
    );
    expect(selected.historyControls, true);
    expect(selected.nativeReference, false);
    expect(
      selected.modelHash,
      '1325ae366d31950f137c9c357b9fa89448b176d76998180c08ceaca78bba98be',
    );
    expect(profile().enableThinking, false);
    expect(profile().historyControls, false);
    expect(profile(backend: 'npu').enableThinking, true);
  });

  test('Gemma3 q4 profiles use the int4-qualified history fixture', () {
    for (final name in ['gemma3-litert-cpu', 'npu-qualcomm-sm8650']) {
      final gemma = ValidationProfile.fromJson(
        jsonDecode(File('assets/profiles/$name.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      expect(gemma.fixtures['history'], {
        'system': 'Remember the secret code exactly.',
        'user': 'The secret code is K7Q2.',
        'assistant': 'I will remember the code.',
        'prompt': 'What is the secret code? Reply with only the code.',
        'expected': 'K7Q2',
      }, reason: name);
    }
  });

  test('history controls and thinking overrides reject invalid contracts', () {
    for (final patch in <Map<String, dynamic>>[
      {'enable_thinking': 'true'},
      {'history_controls': 1},
      {'history_controls': true, 'backend': 'gpu'},
      {'history_controls': true, 'backend': 'npu'},
      {
        'execution_path': 'native_c_api',
        'backend': 'npu',
        'enable_thinking': false,
      },
    ]) {
      expect(
        () => ValidationProfile.fromJson(profile().toJson()..addAll(patch)),
        throwsFormatException,
      );
    }
  });

  for (final native in [false, true]) {
    test(
      'history controls preserve distinct input and strict oracle: native=$native',
      () async {
        final data = profile(backend: native ? 'npu' : 'cpu').toJson()
          ..['execution_path'] = native ? 'native_c_api' : 'public_api';
        if (!native) data['history_controls'] = true;
        final engine = FakeEngine()
          ..backendName = native
              ? 'LiteRT-LM NPU direct C API'
              : 'LiteRT-LM CPU';
        final result = await run(
          engine,
          selected: ValidationProfile.fromJson(data),
        );
        expect(result.report.cases.length, native ? 12 : 20);
        expect(result.report.assertionsPassed, true);
        final histories = engine.requests
            .where((r) => r['history'] != null)
            .toList();
        expect(histories, hasLength(3));
        final canonical = histories[0]['history'] as List<LlamaChatMessage>;
        expect(canonical.map((m) => m.role.name), [
          'system',
          'user',
          'assistant',
          'user',
        ]);
        expect(canonical.map((m) => m.content), [
          'Remember the secret code exactly.',
          'The secret code is cedar17.',
          'I will remember the code.',
          'What is the secret code? Reply with only the code.',
        ]);
        final literal = histories[1]['history'] as List<LlamaChatMessage>;
        expect(jsonDecode(literal.first.content), {
          'role': 'system',
          'content': [
            {'type': 'text', 'text': canonical.first.content},
          ],
        });
        expect(
          literal.skip(1).map((m) => m.content),
          canonical.skip(1).map((m) => m.content),
        );
        final noSystem = histories[2]['history'] as List<LlamaChatMessage>;
        expect(noSystem.map((m) => m.role.name), ['user', 'assistant', 'user']);
        final combined = engine.requests.singleWhere(
          (r) =>
              r['history'] == null &&
              (r['prompt'] as String).contains('cedar17'),
        );
        expect(combined['prompt'], canonical.map((m) => m.content).join('\n'));

        final failed = await run(
          FakeEngine()
            ..wrongHistory = true
            ..backendName = native
                ? 'LiteRT-LM NPU direct C API'
                : 'LiteRT-LM CPU',
          selected: ValidationProfile.fromJson(data),
        );
        expect(failed.report.assertionsPassed, false);
        expect(
          failed.report.cases
              .where((c) => (c['case_id'] as String).startsWith('C06.'))
              .map((c) => c['status']),
          ['FAIL', 'FAIL', 'FAIL', 'FAIL'],
        );
      },
    );
  }
  test('WebGPU chat profiles load every layer on WebGPU and run only on the '
      'Web host', () async {
    for (final (id, cpu) in [('chat-gguf-webgpu', 'chat-gguf-cpu')]) {
      Map<String, dynamic> read(String id) =>
          jsonDecode(File('assets/profiles/$id.json').readAsStringSync())
              as Map<String, dynamic>;
      final json = read(id);
      expect({...json, 'id': cpu, 'backend': 'cpu'}, read(cpu), reason: id);
      final selected = ValidationProfile.fromJson(json);
      expect(selected.loadParams.preferredBackend, GpuBackend.auto);
      expect(selected.loadParams.gpuLayers, ModelParams.maxGpuLayers);
      expect(selected.requiresAcceleratorProof, true);
      selected.requireRunnable(web: true);
      expect(
        selected.requireRunnable,
        throwsA(isA<LlamaUnsupportedException>()),
        reason: id,
      );
      final directory = Directory.systemTemp.createTempSync('webgpu-native-');
      try {
        await expectLater(
          prepareModel(selected, directory),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              contains('only in the Web validation host'),
            ),
          ),
          reason: id,
        );
        expect(directory.listSync(), isEmpty, reason: id);
      } finally {
        directory.deleteSync();
      }
    }
  });
  test(
    'NPU candidates are locked and reject preparation before any download',
    () async {
      for (final target in ['qualcomm-sm8650', 'tensor-g5']) {
        final selected = ValidationProfile.fromJson(
          jsonDecode(
                File('assets/profiles/npu-$target.json').readAsStringSync(),
              )
              as Map<String, dynamic>,
        );
        expect(selected.backend, 'npu');
        expect(selected.contextSize, 1280);
        expect(selected.requiresAcceleratorProof, true);
        final directory = Directory.systemTemp.createTempSync(
          'npu-no-download-',
        );
        try {
          await expectLater(
            prepareModel(selected, directory),
            throwsA(isA<LlamaUnsupportedException>()),
          );
          expect(directory.listSync(), isEmpty);
        } finally {
          directory.deleteSync();
        }
      }
    },
  );
  test(
    'WASM CPU diagnostics require a CPU-only core and zero GPU layers',
    () async {
      final selected = profile().toJson()..['runtime'] = 'gguf';
      final model = Map<String, dynamic>.from(selected['model'] as Map);
      model['filename'] = 'model.gguf';
      model['url'] = (model['url'] as String).replaceAll('.litertlm', '.gguf');
      selected['model'] = model;
      for (final layers in ['0', '1', null]) {
        final engine = FakeEngine()
          ..backendName = 'WASM (Prototype bridge)'
          ..metadata = {
            'llamadart.webgpu.n_gpu_layers': layers,
            'llamadart.webgpu.core_variant': 'wasm32',
          };
        final result = await run(
          engine,
          selected: ValidationProfile.fromJson(selected),
        );
        for (final id in ['C01.load', 'C09.reload', 'C12.recovery']) {
          expect(
            result.report.cases.firstWhere(
              (record) => record['case_id'] == id,
            )['status'],
            layers == '0' ? 'PASS' : 'FAIL',
          );
        }
      }
    },
  );
  test(
    'missing or dirty provenance preserves assertions but cannot qualify',
    () async {
      final result = await run(FakeEngine());
      expect(result.report.assertionsPassed, true);
      for (final key in [
        'source_commit',
        'source_dirty',
        'hook_sha256',
        'litert_tag',
      ]) {
        final events = (jsonDecode(jsonEncode(result.events)) as List)
            .cast<Map>();
        (events.first['environment'] as Map).remove(key);
        final report = ValidationReport.parse(
          events.map(jsonEncode).join('\n'),
        );
        expect(report.assertionsPassed, true);
        expect(report.qualified, false);
        expect(report.toJUnit(), contains('run-integrity'));
        expect(report.provenanceProblems, isNotEmpty);
      }
      (result.events.first['environment'] as Map)['source_dirty'] = true;
      expect(
        ValidationReport.parse(
          result.events.map(jsonEncode).join('\n'),
        ).qualified,
        false,
      );
    },
  );
  test('model preparation must prove the exact locked hash and size', () async {
    final result = await run(FakeEngine());
    expect(result.report.qualified, true);
    final valid = result.events.first['preparation'] as Map;
    for (final preparation in [
      null,
      {},
      {...valid, 'verified': false},
      {...valid, 'sha256': '0' * 64},
      {...valid, 'bytes': 1},
      {...valid, 'bytes': '${valid['bytes']}'},
    ]) {
      final events = (jsonDecode(jsonEncode(result.events)) as List)
          .cast<Map>();
      events.first['preparation'] = preparation;
      final report = ValidationReport.parse(events.map(jsonEncode).join('\n'));
      expect(report.assertionsPassed, true);
      expect(report.qualified, false);
      expect(report.provenanceProblems, contains(contains('model hash')));
    }
  });
  test(
    'desktop payload verification is required even for complete assertions',
    () async {
      final result = await run(FakeEngine());
      final environment = result.events.first['environment'] as Map;
      environment['os'] = 'macos';
      ValidationReport report() =>
          ValidationReport.parse(result.events.map(jsonEncode).join('\n'));
      expect(report().qualified, false);
      environment['runtime_payload_verified'] = true;
      expect(report().qualified, false);
      environment['runtime_bundle_sha256'] = 'a' * 64;
      expect(report().qualified, true);
      environment['runtime_payload_verified'] = false;
      expect(report().qualified, false);
      environment.remove('os');
      environment['platform'] = 'macOS';
      expect(
        report().provenanceProblems,
        contains(contains('Desktop runtime')),
      );
      environment['web'] = true;
      environment['platform'] = 'linux';
      environment['bridge_tag'] = 'fixture-bridge';
      expect(report().provenanceProblems, isEmpty);
    },
  );
  test(
    'CPU backend changes during reload or recovery cannot qualify TPS',
    () async {
      for (final threshold in [2, 3, 4]) {
        final result = await run(
          FakeEngine()..switchAfterLoad = threshold,
          selected: focused(['lifecycle']),
        );
        expect(
          result.report.cases.singleWhere(
            (c) =>
                c['case_id'] ==
                (threshold == 2
                    ? 'C09.reload'
                    : threshold == 3
                    ? 'C12.recovery'
                    : 'C09.reload.second'),
          )['status'],
          'FAIL',
        );
        expect(result.report.qualified, false);
      }
    },
  );

  test(
    'native GPU evidence requires matching backend and all load allocations',
    () {
      final manifest = <String, dynamic>{
        'schema_version': 1,
        'profile':
            (jsonDecode(
                    File(
                      'assets/profiles/tiny-gguf-cpu.json',
                    ).readAsStringSync(),
                  )
                  as Map<String, dynamic>)
              ..['backend'] = 'metal',
        'accelerator_evidence_required': true,
      };
      final cases = <Map<String, dynamic>>[
        {
          'case_id': 'C01.load',
          'status': 'PASS',
          'diagnostics': {'backend_name': 'Metal'},
        },
        {
          'case_id': 'C09.reload',
          'status': 'PASS',
          'diagnostics': {'backend_name': 'Metal'},
        },
        {
          'case_id': 'C12.recovery',
          'status': 'PASS',
          'diagnostics': {'backend_name': 'Metal'},
        },
      ];
      const load =
          'load_tensors: offloaded 7/7 layers to GPU\nsched_reserve: MTL0 compute buffer size = 63.62 MiB\n';
      expect(inspectPlacement(manifest, cases, load * 3)['verified'], true);
      expect(inspectPlacement(manifest, cases, load * 2)['verified'], false);
      expect(
        inspectPlacement(
          manifest,
          cases,
          load.replaceAll('7/7', '0/7') * 3,
        )['verified'],
        false,
      );
      expect(
        inspectPlacement(
          manifest,
          cases,
          load.replaceAll('MTL0', 'CPU') * 3,
        )['verified'],
        false,
      );
      expect(
        inspectPlacement(manifest, cases, 'GPU found: Metal')['verified'],
        false,
      );
      cases.first['diagnostics'] = {'backend_name': 'CPU'};
      expect(inspectPlacement(manifest, cases, load * 3)['verified'], false);
    },
  );

  test('software Vulkan cannot qualify despite positive offload records', () {
    final profile =
        jsonDecode(
              File('assets/profiles/tiny-gguf-cpu.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    profile['backend'] = 'vulkan';
    final manifest = <String, dynamic>{'schema_version': 1, 'profile': profile};
    final cases = [
      for (final id in ['C01.load', 'C09.reload', 'C12.recovery'])
        <String, dynamic>{
          'case_id': id,
          'status': 'PASS',
          'diagnostics': {'backend_name': 'Vulkan0'},
        },
    ];
    final allocations =
        'load_tensors: offloaded 7/7 layers to GPU\n'
            'Vulkan0 compute buffer size = 64.0 MiB\n' *
        3;
    final hardware = 'ggml_vulkan: 0 = NVIDIA L4\n$allocations';
    expect(inspectPlacement(manifest, cases, hardware)['verified'], true);
    String selected(String name, {int index = 0, int free = 21831}) =>
        'llama_prepare_model_devices: using device Vulkan$index '
        '($name) (0000:00:03.0) - $free MiB free\n';
    final selectedHardware = selected('NVIDIA L4');
    for (final valid in [
      '$selectedHardware$allocations',
      '${selected('NVIDIA L4', free: 21760)}$selectedHardware$allocations',
      '$selectedHardware$hardware',
      'ggml_vulkan: 0 = NVIDIA L4 (NVIDIA) | uma: 0\n'
          '$selectedHardware$allocations',
      '${selected('Intel(R) Arc(TM) A770')}$allocations',
    ]) {
      expect(inspectPlacement(manifest, cases, valid)['verified'], true);
    }
    for (final invalid in [
      allocations,
      'ggml_vulkan: 1 = NVIDIA L4\n$allocations',
      'ggml_vulkan: 0 = unknown device\n$allocations',
      'ggml_vulkan: 0 = Intel CPU\n$allocations',
      '$hardware\nggml_vulkan: 0 = AMD Radeon',
      '${selected('AMD Radeon')}$hardware',
      '${selected('NVIDIA L4', index: 1)}$allocations',
      '${selected('Intel CPU')}$allocations',
      '${selected('NVIDIA virtual device')}$allocations',
      '${selected('NVIDIA L4 | virtual device')}$allocations',
      'ggml_vulkan: 0 = NVIDIA L4 | virtual device\n$allocations',
      'ggml_vulkan: 0 = NVIDIA L4 | CPU\n$allocations',
      'ggml_vulkan: 0 = NVIDIA L4 | software\n$allocations',
      '${selected('unknown device')}$allocations',
      '${selected('NVIDIA (L4')}$allocations',
      '${selectedHardware.replaceFirst(' MiB free', '')}$allocations',
      'unrecognized: $selectedHardware$allocations',
      '$selectedHardware${allocations.replaceFirst('7/7', '0/7')}',
      '$selectedHardware${allocations.replaceFirst('64.0', '0.0')}',
      '$selectedHardware$allocations$allocations',
    ]) {
      expect(inspectPlacement(manifest, cases, invalid)['verified'], false);
    }
    for (final device in [
      'llvmpipe (LLVM 20.1.2, 256 bits)',
      'Lavapipe',
      'SwiftShader Device',
      'Microsoft Basic Render Driver',
      'Software Rasterizer',
    ]) {
      final result = inspectPlacement(
        manifest,
        cases,
        'ggml_vulkan: 0 = $device\n$allocations',
      );
      expect(result['verified'], false, reason: device);
      expect(result['reason'], contains('software Vulkan'));
      expect(
        inspectPlacement(
          manifest,
          cases,
          '${selected(device)}$allocations',
        )['verified'],
        false,
      );
      // Mixed inventory cannot identify which physical device executed work.
      expect(
        inspectPlacement(manifest, cases, '$hardware\n$device')['verified'],
        false,
      );
    }
    profile['backend'] = 'cpu';
    expect(inspectPlacement(manifest, cases, 'llvmpipe')['required'], false);
  });

  for (final selection in ['focused', 'release']) {
    test('$selection GPU proof includes every selected reload', () {
      final data =
          jsonDecode(
                File('assets/profiles/tiny-gguf-cpu.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      data['backend'] = 'metal';
      data['selection'] = selection;
      if (selection == 'focused') data['focus_features'] = ['lifecycle'];
      final manifest = <String, dynamic>{
        'schema_version': 2,
        'profile': data,
        // A producer cannot waive the fourth load by omitting it here.
        'case_ids': ['C01.load', 'C09.reload', 'C12.recovery'],
        'accelerator_evidence_required': false,
      };
      final cases = <Map<String, dynamic>>[
        for (final id in [
          'C01.load',
          'C09.reload',
          'C12.recovery',
          'C09.reload.second',
        ])
          {
            'case_id': id,
            'status': 'PASS',
            'diagnostics': {'backend_name': 'Metal'},
          },
      ];
      const load =
          'load_tensors: offloaded 7/7 layers to GPU\nsched_reserve: MTL0 compute buffer size = 63.62 MiB\n';
      final proof = inspectPlacement(manifest, cases, load * 4);
      expect(proof['verified'], true);
      expect(proof['expected_loads'], 4);
      expect(inspectPlacement(manifest, cases, load * 3)['verified'], false);
      expect(
        inspectPlacement(
          manifest,
          cases.take(3).toList(),
          load * 4,
        )['verified'],
        false,
      );
      expect(
        inspectPlacement(manifest, [
          ...cases.take(3),
          cases.first,
        ], load * 4)['verified'],
        false,
      );
      cases.last['diagnostics'] = {'backend_name': 'CPU'};
      expect(inspectPlacement(manifest, cases, load * 4)['verified'], false);
      cases.last['diagnostics'] = {'backend_name': 'Metal'};
      cases.last['status'] = 'FAIL';
      expect(inspectPlacement(manifest, cases, load * 4)['verified'], false);
    });
  }

  test(
    'late timed-out reload cannot start more inference after cleanup',
    () async {
      final paused = Completer<void>();
      final engine = FakeEngine()..pauseReload = paused;
      final result = await run(engine);
      final generated = engine.generated;
      expect(result.report.cleanupPassed, false);
      paused.complete();
      await Future<void>.delayed(Duration.zero);
      expect(engine.generated, generated);
      expect(engine.loads, 2);
    },
  );
  test('explicit CPU case rejects accelerator diagnostics', () async {
    final result = await run(FakeEngine()..backendName = 'Metal');
    expect(result.report.cases.first['status'], 'FAIL');
    expect(result.report.qualified, false);
  });

  test(
    'ignored cancellation cannot pass the cancellation obligation',
    () async {
      final result = await run(FakeEngine()..ignoresCancellation = true);
      expect(
        result.report.cases.singleWhere(
          (c) => c['case_id'] == 'C08.cancel',
        )['status'],
        'NOT_RUN',
      );
      expect(result.report.qualified, false);
    },
  );
  test('journal sink failure still disposes the engine', () async {
    final engine = FakeEngine();
    await expectLater(
      ValidationRunner(
        profile: profile(),
        engine: engine,
        emit: (_) async => throw StateError('disk full'),
      ).run('model', runId: 'test', environment: {}),
      throwsStateError,
    );
    expect(engine.disposed, true);
  });
  test('validated profile cannot be mutated through nested JSON', () {
    final selected = profile();
    expect(() => selected.model['sha256'] = 'changed', throwsUnsupportedError);
  });

  test('rejects floating or unchecked model inputs', () {
    for (final field in ['revision', 'sha256']) {
      final json = profile().toJson();
      (json['model'] as Map)[field] = 'main';
      expect(() => ValidationProfile.fromJson(json), throwsFormatException);
    }
  });
  test('canonical identity is independent of JSON key order', () {
    expect(jsonHash({'b': 2, 'a': 1}), jsonHash({'a': 1, 'b': 2}));
  });
  test('one warmup and three measured samples; lifecycle loads only', () async {
    final engine = FakeEngine();
    final result = await run(engine);
    expect(result.report.qualified, isTrue);
    expect(result.report.samples, hasLength(3));
    expect(engine.loads, 3);
    expect(engine.disposed, isTrue);
  });
  test('semantic failure preserves output and still measures TPS', () async {
    final result = await run(FakeEngine()..wrongArithmetic = true);
    final failure = result.report.cases.singleWhere(
      (c) => c['case_id'] == 'C04.arithmetic',
    );
    expect(failure['status'], 'FAIL');
    expect(failure['content'], '2');
    expect(result.report.samples, hasLength(3));
    expect(result.report.assertionsPassed, isFalse);
  });
  test('Qwen3 LiteRT arithmetic oracle accepts only the correct sum', () {
    for (final backend in ['cpu', 'gpu']) {
      final litert = ValidationProfile.fromJson(
        jsonDecode(
              File(
                'assets/profiles/chat-litert-$backend.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>,
      );
      expect(
        litert.fixtureText('arithmetic', 'prompt'),
        'What is 3 + 4? Reply with only the number.',
      );
      final oracle = RegExp(litert.fixtureText('arithmetic', 'regex'));
      for (final output in ['7', '7.', '3 + 4 = 7']) {
        expect(oracle.hasMatch(output), isTrue, reason: output);
      }
      for (final output in ['2', '4', '17', '3 + 4 = 8', '7 + 3 = 10']) {
        expect(oracle.hasMatch(output), isFalse, reason: output);
      }
    }
  });
  test('engine create deadline override rejects invalid contracts', () {
    for (final patch in <Map<String, dynamic>>[
      {'backend': 'gpu', 'engine_create_case_timeout_ms': '120000'},
      {'backend': 'gpu', 'engine_create_case_timeout_ms': 59999},
      {'backend': 'gpu', 'engine_create_case_timeout_ms': 180001},
      {'backend': 'cpu', 'engine_create_case_timeout_ms': '120000'},
      {'backend': 'cpu', 'engine_create_case_timeout_ms': 59999},
      {'backend': 'cpu', 'engine_create_case_timeout_ms': 180001},
      {'backend': 'npu', 'engine_create_case_timeout_ms': 120000},
    ]) {
      expect(
        () => ValidationProfile.fromJson(profile().toJson()..addAll(patch)),
        throwsFormatException,
      );
    }
    final gguf =
        jsonDecode(
                File('assets/profiles/chat-gguf-cpu.json').readAsStringSync(),
              )
              as Map<String, dynamic>
          ..['engine_create_case_timeout_ms'] = 120000;
    expect(() => ValidationProfile.fromJson(gguf), throwsFormatException);
  });

  test('engine create deadline override is accepted for LiteRT CPU', () {
    final cpu = ValidationProfile.fromJson(
      profile().toJson()..['engine_create_case_timeout_ms'] = 90000,
    );
    expect(cpu.engineCreateCaseTimeout, const Duration(seconds: 90));
    final runner = ValidationRunner(
      profile: cpu,
      engine: FakeEngine(),
      emit: (_) async {},
    );
    expect(runner.caseDeadline('C09.reload'), const Duration(seconds: 90));
    expect(runner.caseDeadline('C03.raw'), const Duration(seconds: 60));
  });

  test('only measured LiteRT profiles extend engine create deadlines', () {
    const measured = {
      'qwen35-litert-gpu': Duration(seconds: 120),
      'qwen35-litert-cpu': Duration(seconds: 180),
    };
    for (final file in Directory(
      'assets/profiles',
    ).listSync().whereType<File>()) {
      final selected = ValidationProfile.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
      );
      final extended = measured[selected.id];
      expect(selected.engineCreateCaseTimeout, extended, reason: selected.id);
      final runner = ValidationRunner(
        profile: selected,
        engine: FakeEngine(),
        emit: (_) async {},
      );
      for (final id in selected.caseIds) {
        expect(
          runner.caseDeadline(id),
          selected.isEmbedding
              ? const Duration(seconds: 300)
              : extended != null &&
                    ValidationRunner.engineReloadCaseIds.contains(id)
              ? extended
              : const Duration(seconds: 60),
          reason: '${selected.id} $id',
        );
      }
      expect(
        runner.caseDeadline('C02.unicode', firstUse: true),
        selected.isEmbedding
            ? const Duration(seconds: 300)
            : extended ?? const Duration(seconds: 60),
        reason: selected.id,
      );
    }
  });

  test('engine create deadline override leaves other cases bounded', () async {
    Future<Map<String, dynamic>> reload(ValidationProfile selected) async {
      final paused = Completer<void>();
      final engine = FakeEngine()..pauseReload = paused;
      Timer(const Duration(milliseconds: 120), paused.complete);
      final result = await run(engine, selected: selected);
      return result.report.cases.singleWhere(
        (c) => c['case_id'] == 'C09.reload',
      );
    }

    final base = await reload(profile(backend: 'gpu'));
    expect(base['reason'], 'case_timeout');
    expect(base['timeout_ms'], 30);

    final extended = await reload(
      ValidationProfile.fromJson(
        profile(backend: 'gpu').toJson()
          ..['engine_create_case_timeout_ms'] = 60000,
      ),
    );
    expect(extended['reason'], isNot('case_timeout'));
    expect(extended['status'], isNot('ERROR'));

    Future<Map<String, dynamic>> firstUse(ValidationProfile selected) async {
      final result = await run(
        FakeEngine()..tokenizeDelay = const Duration(milliseconds: 120),
        selected: selected,
      );
      return result.report.cases.singleWhere(
        (c) => c['case_id'] == 'C02.unicode',
      );
    }

    expect((await firstUse(profile(backend: 'gpu')))['reason'], 'case_timeout');
    expect(
      (await firstUse(
        ValidationProfile.fromJson(
          profile(backend: 'gpu').toJson()
            ..['engine_create_case_timeout_ms'] = 60000,
        ),
      ))['status'],
      'PASS',
    );

    final hung = await run(
      FakeEngine()..timeout = true,
      selected: ValidationProfile.fromJson(
        profile(backend: 'gpu').toJson()
          ..['engine_create_case_timeout_ms'] = 60000,
      ),
    );
    final raw = hung.report.cases.singleWhere((c) => c['case_id'] == 'C03.raw');
    expect(raw['reason'], 'case_timeout');
    expect(raw['timeout_ms'], 30);
  });

  test(
    'timeout cancels and prevents overlapping subsequent inference',
    () async {
      final engine = FakeEngine()..timeout = true;
      final result = await run(engine);
      expect(engine.generated, 1);
      expect(engine.cancelled, isTrue);
      expect(engine.disposed, isTrue);
      expect(result.report.assertionsPassed, isFalse);
      expect(
        result.report.cases.where((c) => c['status'] == 'NOT_RUN'),
        isNotEmpty,
      );
    },
  );
  test('cleanup failure cannot produce a passing report', () async {
    final result = await run(FakeEngine()..cleanupFails = true);
    expect(result.report.qualified, isFalse);
    expect(result.report.toJUnit(), contains('run-integrity'));
  });
  test(
    'GPU preference and reported layers are not accelerator proof',
    () async {
      final result = await run(FakeEngine(), selected: profile(backend: 'gpu'));
      expect(result.report.assertionsPassed, isTrue);
      expect(result.report.qualified, isFalse);
      expect(result.report.toHtml(), contains('unverified'));
    },
  );
  test('release selection executes every implemented obligation', () async {
    final result = await run(
      CountingFakeEngine(),
      selected: profile(release: true),
      environment: {'os': 'android'},
    );
    expect(result.report.qualified, isTrue);
    expect(
      result.report.cases.singleWhere(
        (c) => c['case_id'] == 'C07.tools',
      )['status'],
      'PASS',
    );
  });
  test(
    'removing an obligation and its inventory entry cannot qualify',
    () async {
      final result = await run(FakeEngine());
      final events = result.events;
      (events.first['case_ids'] as List).remove('C06.history');
      events.removeWhere((event) => event['case_id'] == 'C06.history');
      for (var index = 1; index < events.length; index++) {
        events[index]['sequence'] = index - 1;
      }
      final report = ValidationReport.parse(events.map(jsonEncode).join('\n'));
      expect(report.qualified, false);
      expect(
        report.problems,
        contains('Case inventory does not match the profile'),
      );
      expect(
        report.cases.singleWhere(
          (c) => c['case_id'] == 'C06.history',
        )['status'],
        'NOT_RUN',
      );
    },
  );
  test('rehashed configuration must match the executable profile', () async {
    final result = await run(FakeEngine());
    final manifest = result.events.first;
    (manifest['effective_config'] as Map)['temperature'] = 0.8;
    manifest['config_hash'] = jsonHash(manifest['effective_config']);
    final report = ValidationReport.parse(
      result.events.map(jsonEncode).join('\n'),
    );
    expect(report.qualified, false);
    expect(
      report.problems,
      contains('Effective configuration does not match the profile'),
    );
  });
  test('report rejects a self-hashed invalid profile', () async {
    final result = await run(FakeEngine());
    final manifest = result.events.first;
    (manifest['profile'] as Map)['runtime'] = 'invalid';
    manifest['profile_hash'] = jsonHash(manifest['profile']);
    final report = ValidationReport.parse(
      result.events.map(jsonEncode).join('\n'),
    );
    expect(report.qualified, false);
    expect(report.problems, contains('Invalid validation profile'));
  });
  test('manifest flag cannot waive accelerator evidence', () async {
    for (final flag in [false, null]) {
      final result = await run(FakeEngine(), selected: profile(backend: 'gpu'));
      result.events.first['accelerator_evidence_required'] = flag;
      final report = ValidationReport.parse(
        result.events.map(jsonEncode).join('\n'),
      );
      expect(report.qualified, false);
      expect(report.acceleratorVerified, false);
      expect(
        report.problems,
        contains('Accelerator evidence requirement does not match the profile'),
      );
    }
  });
  test('record cannot declare its own unsupported exemption', () async {
    final result = await run(FakeEngine());
    result.events.firstWhere((e) => e['type'] == 'case')
      ..['status'] = 'UNSUPPORTED'
      ..['expected_unsupported'] = true;
    final report = ValidationReport.parse(
      result.events.map(jsonEncode).join('\n'),
    );
    expect(report.qualified, false);
    expect(report.assertionsPassed, false);
  });
  test(
    'duplicate, missing, malformed or truncated records fail closed',
    () async {
      final result = await run(FakeEngine());
      final lines = result.events.map(jsonEncode).toList();
      for (final altered in [
        [
          ...lines,
          jsonEncode(result.events.firstWhere((e) => e['type'] == 'case')),
        ],
        lines.take(lines.length - 1).toList(),
        [...lines, '{"type":'],
        lines
            .where((s) => !s.contains('C02.unicode') || s.contains('manifest'))
            .toList(),
      ]) {
        expect(ValidationReport.parse(altered.join('\n')).qualified, isFalse);
      }
    },
  );
  test('reports escape generated markup and retain warmup exclusion', () async {
    final result = await run(FakeEngine());
    result.report.cases.first['content'] = '<script>alert(1)</script>';
    expect(result.report.toHtml(), isNot(contains('<script>alert')));
    expect(result.report.toCsv(), isNot(contains('warmup')));
    expect(result.report.toJUnit(), contains('&lt;script&gt;'));
  });
  ValidationProfile gguf([String id = 'chat-gguf-cpu']) =>
      ValidationProfile.fromJson(
        jsonDecode(File('assets/profiles/$id.json').readAsStringSync())
            as Map<String, dynamic>,
      );
  FakeEngine ggufEngine() => FakeEngine()..backendName = 'CPU';
  Map<String, dynamic> record(
    ({ValidationReport report, List<Map<String, dynamic>> events}) result,
    String id,
  ) => result.report.cases.singleWhere((c) => c['case_id'] == id);

  group('catalog 6 in-flight evidence', () {
    test('empty visible output needs positive native interruption', () async {
      final engine = ggufEngine()..cancellationFault = 'empty';
      final result = await run(engine, selected: gguf());
      final cancelled = record(result, 'C08.cancel');
      expect(cancelled['status'], 'PASS');
      expect(cancelled['content'], '');
      expect(cancelled['cancel_after_ms'], 4);
      expect(result.report.problems, isEmpty);
      for (final fault in ['zero', 'prefix']) {
        final failed = await run(
          ggufEngine()..cancellationFault = fault,
          selected: gguf(),
        );
        expect(
          record(failed, 'C08.cancel')['status'],
          'NOT_RUN',
          reason: fault,
        );
      }
      final ignored = await run(
        ggufEngine()..ignoresCancellation = true,
        selected: gguf(),
      );
      expect(record(ignored, 'C08.cancel')['status'], 'NOT_RUN');
    });

    test(
      'import rejects unsupported PASS claims and completion/recovery failures',
      () async {
        final selected = gguf();
        final result = await run(ggufEngine(), selected: selected);
        expect(result.report.qualified, true);
        final mutations = <String, void Function(Map<String, dynamic>)>{
          'missing counters': (e) =>
              e['metrics']['native_decode_tokens'] = null,
          'zero tokens': (e) => e['metrics']['native_decode_tokens'] = 0,
          'ignored cancel': (e) => e['metrics']['native_decode_tokens'] =
              e['uncancelled_control']['metrics']['native_decode_tokens'],
          'wrong prefix': (e) => e['content'] = 'wrong',
          'unordered': (e) => e['completion_order_valid'] = false,
          'recovery cancelled': (e) => e['recovery']['cancel_requested'] = true,
          'late': (e) => e['cancel_to_done_ms'] = 5001,
        };
        for (final entry in mutations.entries) {
          final events = (jsonDecode(jsonEncode(result.events)) as List)
              .cast<Map<String, dynamic>>();
          final cancelled = events.singleWhere(
            (e) => e['case_id'] == 'C08.cancel' && e['type'] == 'case',
          );
          entry.value(cancelled);
          final report = ValidationReport.parse(
            events.map(jsonEncode).join('\n'),
          );
          expect(
            report.problems,
            contains('Invalid in-flight case evidence: C08.cancel'),
            reason: entry.key,
          );
          expect(report.qualified, false, reason: entry.key);
        }
        final overlapMutations = <String, void Function(Map<String, dynamic>)>{
          'no issue': (e) => e['second_issued'] = false,
          'late': (e) => e['timeline_ms']['second_ended'] =
              e['timeline_ms']['first_ended'] + 1,
          'accepted': (e) => e['second']['state_exception'] = false,
          'wrong type': (e) =>
              e['second']['error_type'] = 'LlamaInferenceException',
          'stalled': (e) => e['first_deltas_after_second_ended'] = 0,
          'unordered': (e) => e['first']['completion_order_valid'] = false,
          'recovery empty': (e) => e['recovery']['content'] = '',
        };
        for (final entry in overlapMutations.entries) {
          final events = (jsonDecode(jsonEncode(result.events)) as List)
              .cast<Map<String, dynamic>>();
          entry.value(
            events.singleWhere(
              (e) => e['case_id'] == 'C08.overlap' && e['type'] == 'case',
            ),
          );
          expect(
            ValidationReport.parse(events.map(jsonEncode).join('\n')).problems,
            contains('Invalid in-flight case evidence: C08.overlap'),
            reason: entry.key,
          );
        }
      },
    );

    test(
      'catalog 5 keeps version-1 C08 cases and historical classifications',
      () async {
        final selected = gguf();
        final result = await run(ggufEngine(), selected: selected);
        final events = (jsonDecode(jsonEncode(result.events)) as List)
            .cast<Map<String, dynamic>>();
        dropUndeclared(events, selected, 5);
        events.first['catalog'] = selected.catalogForVersion(5);
        events.first['catalog_hash'] = jsonHash(events.first['catalog']);
        for (final id in ['C08.cancel', 'C08.overlap']) {
          expect(validationCase(id).version, 2);
          expect(validationCase(id, catalogVersion: 5).version, 1);
          expect(
            selected.caseFixtures(id, catalogVersion: 5).keys,
            isNot(contains('inflight')),
          );
          final old = events.singleWhere(
            (e) => e['type'] == 'case' && e['case_id'] == id,
          );
          old['status'] = 'NOT_RUN';
          old.remove('cancel_after_ms');
          old.remove('second_after_ms');
        }
        expect(
          (events.first['catalog']['fixtures'] as Map).keys,
          isNot(contains('inflight')),
        );
        final report = ValidationReport.parse(
          events.map(jsonEncode).join('\n'),
        );
        expect(report.problems, isEmpty);
        expect(report.cases.where((e) => e['status'] == 'NOT_RUN').length, 2);
        expect(report.qualified, false);
      },
    );
  });

  group('catalog 5 cancellation, restart, overlap and grammar cases', () {
    test('GGUF quick core adds them; LiteRT adds restart and overlap', () {
      expect(gguf('tiny-gguf-cpu').caseIds, [
        'C01.load',
        'C02.unicode',
        'C03.raw',
        'C08.cancel',
        'C08.cancel.early',
        'C08.cancel.restart',
        'C08.overlap',
        'C09.reload',
        'C10.limit',
        'C12.grammar',
        'C12.recovery',
        'B01.warmup',
        'B01.1',
        'B01.2',
        'B01.3',
      ]);
      final litert = profile();
      expect(litert.caseIds.where(catalogFiveCaseIds.contains), [
        'C08.cancel.early',
        'C08.cancel.restart',
        'C08.overlap',
      ]);
      Map<Object?, Object?> omitted(int version) => {
        for (final entry
            in (litert.catalogForVersion(version)['cases'] as List).cast<Map>())
          if (entry['selected'] == false) entry['id']: entry['omission_reason'],
      };
      expect(omitted(7).keys, isNot(contains('C08.cancel.restart')));
      expect(omitted(7).keys, isNot(contains('C08.overlap')));
      expect(omitted(7)['C12.grammar'], 'litert_grammar_unsupported');
      for (final version in [5, 6]) {
        expect(
          litert.caseIdsForCatalog(version).where(catalogFiveCaseIds.contains),
          ['C08.cancel.early'],
        );
        expect(
          omitted(version)['C08.cancel.restart'],
          'litert_restart_contract_undefined',
        );
        expect(
          omitted(version)['C08.overlap'],
          'litert_restart_contract_undefined',
        );
      }
      expect(litert.caseIdsForCatalog(4), isNot(contains('C08.cancel.early')));
      expect(
        gguf().caseIdsForCatalog(4).where(catalogFiveCaseIds.contains),
        isEmpty,
      );
    });

    test('catalog 4 journals keep their inventory and C07 contract', () async {
      final selected = gguf();
      final current = await run(ggufEngine(), selected: selected);
      expect(current.report.qualified, true);
      final events = [
        for (final event in current.events)
          jsonDecode(jsonEncode(event)) as Map<String, dynamic>,
      ];
      dropUndeclared(events, selected, 4);
      events.first['catalog'] = selected.catalogForVersion(4);
      events.first['catalog_hash'] = jsonHash(events.first['catalog']);
      for (final event in events.where((e) => e['type'] == 'case')) {
        final id = event['case_id'] as String;
        event['case_version'] = validationCase(id, catalogVersion: 4).version;
        event['fixture_hash'] = jsonHash(
          selected.caseFixtures(id, catalogVersion: 4),
        );
      }
      expect(
        (events.first['catalog']['fixtures'] as Map).keys,
        isNot(contains('invalid_grammar')),
      );
      expect(validationCase('C07.tools', catalogVersion: 4).version, 2);
      expect(validationCase('C07.tools', catalogVersion: 4).fixtures, [
        'tools',
      ]);
      final historical = ValidationReport.parse(
        events.map(jsonEncode).join('\n'),
      );
      expect(historical.problems, isEmpty);
      expect(
        historical.cases.map((c) => c['case_id']),
        isNot(contains('C08.cancel.early')),
      );
      events.insert(
        events.length - 2,
        current.events.singleWhere(
          (e) => e['type'] == 'case' && e['case_id'] == 'C08.cancel.early',
        ),
      );
      var sequence = 0;
      for (final event in events.skip(1)) {
        event['sequence'] = sequence++;
      }
      expect(
        ValidationReport.parse(events.map(jsonEncode).join('\n')).problems,
        contains('Unexpected case record: C08.cancel.early'),
      );
      final override = selected.toJson()
        ..['fixtures'] = {
          'invalid_grammar': {'grammar': 'root ::= x'},
        };
      expect(
        () => ValidationProfile.fromJson(override).catalogForVersion(4),
        throwsFormatException,
      );
    });

    test(
      'early cancel passes only for a stream that never produced output',
      () async {
        for (final selected in [profile(), gguf(), gguf('tiny-gguf-cpu')]) {
          final engine = selected.runtime == 'gguf'
              ? ggufEngine()
              : FakeEngine();
          final result = await run(engine, selected: selected);
          final early = record(result, 'C08.cancel.early');
          expect(early['status'], 'PASS', reason: selected.id);
          expect(early['cancel_before_first_delta'], true);
          expect((early['cancelled'] as Map)['content'], '');
          expect((early['uncancelled_control'] as Map)['content'], isNotEmpty);
        }
        for (final entry in {
          'output': 'FAIL',
          'lingering': 'FAIL',
          'late_cancel': 'NOT_RUN',
        }.entries) {
          final result = await run(
            ggufEngine()..earlyFault = entry.key,
            selected: gguf(),
          );
          expect(
            record(result, 'C08.cancel.early')['status'],
            entry.value,
            reason: entry.key,
          );
          expect(result.report.qualified, false);
        }
      },
    );

    test('early cancel deadline is the cancel fixture deadline', () async {
      expect((gguf().fixtures['cancel'] as Map)['deadline_ms'], 5000);
      for (final entry in {5000: 'PASS', 5001: 'FAIL'}.entries) {
        final result = await run(
          ggufEngine()..earlyCancelMs = entry.key,
          selected: gguf(),
        );
        expect(
          record(result, 'C08.cancel.early')['status'],
          entry.value,
          reason: '${entry.key} ms',
        );
      }
    });

    test('restart after cancel needs the queued request to complete', () async {
      final engine = ggufEngine();
      final result = await run(engine, selected: gguf());
      final restart = record(result, 'C08.cancel.restart');
      expect(restart['status'], 'PASS');
      expect(restart['first_cancelled_before_second_issued'], true);
      expect(restart['first_ended_before_second_issued'], false);
      expect(engine.overlapCalls, [true, false]);
      for (final entry in {
        'restart_error': 'FAIL',
        'restart_empty': 'FAIL',
        'restart_interleave': 'FAIL',
        'restart_late': 'NOT_RUN',
      }.entries) {
        final failed = await run(
          ggufEngine()..overlapFault = entry.key,
          selected: gguf(),
        );
        expect(
          record(failed, 'C08.cancel.restart')['status'],
          entry.value,
          reason: entry.key,
        );
        expect(failed.report.qualified, false);
      }
    });

    test(
      'overlap needs a typed rejection while the first keeps streaming',
      () async {
        final result = await run(ggufEngine(), selected: gguf());
        final overlap = record(result, 'C08.overlap');
        expect(overlap['status'], 'PASS');
        expect((overlap['second'] as Map)['state_exception'], true);
        expect(overlap['first_deltas_after_second_ended'], 1);
        expect((overlap['recovery'] as Map)['content'], isNotEmpty);
        for (final entry in {
          'overlap_accepted': 'FAIL',
          'overlap_wrong_type': 'FAIL',
          'overlap_stalled': 'FAIL',
          'overlap_late': 'NOT_RUN',
        }.entries) {
          final failed = await run(
            ggufEngine()..overlapFault = entry.key,
            selected: gguf(),
          );
          expect(
            record(failed, 'C08.overlap')['status'],
            entry.value,
            reason: entry.key,
          );
        }
      },
    );

    test('GGUF Web records restart and overlap as NOT_RUN', () async {
      final engine = ggufEngine()..isWeb = true;
      final result = await run(engine, selected: gguf());
      for (final id in ['C08.cancel.restart', 'C08.overlap']) {
        final web = record(result, id);
        expect(web['status'], 'NOT_RUN');
        expect(web['reason'], contains('Only native llama.cpp'));
      }
      expect(engine.overlapCalls, isEmpty);
      expect(record(result, 'C08.cancel.early')['status'], 'PASS');
    });

    test('LiteRT runs restart and overlap on native and Web', () async {
      for (final web in [false, true]) {
        final engine = FakeEngine()..isWeb = web;
        final result = await run(engine);
        expect(engine.overlapCalls, [true, false], reason: 'web=$web');
        for (final id in ['C08.cancel.restart', 'C08.overlap']) {
          expect(record(result, id)['status'], 'PASS', reason: '$id web=$web');
        }
        final failed = await run(
          FakeEngine()
            ..isWeb = web
            ..overlapFault = 'overlap_accepted',
        );
        expect(record(failed, 'C08.overlap')['status'], 'FAIL');
        expect(failed.report.qualified, false);
      }
    });

    test(
      'catalog 7 journals import without the structured-output pack',
      () async {
        for (final (selected, engine) in [
          (profile(), FakeEngine()),
          (gguf(), ggufEngine()),
        ]) {
          final result = await run(engine, selected: selected);
          final events = (jsonDecode(jsonEncode(result.events)) as List)
              .cast<Map<String, dynamic>>();
          dropUndeclared(events, selected, 7);
          final catalog = selected.catalogForVersion(7);
          events.first['catalog'] = catalog;
          events.first['catalog_hash'] = jsonHash(catalog);
          expect(
            ValidationReport.parse(events.map(jsonEncode).join('\n')).problems,
            isEmpty,
            reason: selected.id,
          );
          expect(catalog['features'], isNot(contains('structured_output')));
          expect(catalog['fixtures'], isNot(contains('structured_output')));
          expect(
            (catalog['cases'] as List).map((c) => (c as Map)['id']),
            isNot(contains(startsWith('S0'))),
          );
          expect(
            (selected.catalog['cases'] as List)
                .cast<Map>()
                .where((c) => '${c['id']}'.startsWith('S0'))
                .map((c) => c['omission_reason'])
                .toSet(),
            selected.runtime == 'litert'
                ? {'outside_selected_features', 'litert_grammar_unsupported'}
                : {'outside_selected_features'},
          );
        }
      },
    );

    test('catalog 6 LiteRT journals keep their restart omissions', () async {
      final selected = profile();
      final result = await run(FakeEngine(), selected: selected);
      final events = (jsonDecode(jsonEncode(result.events)) as List)
          .cast<Map<String, dynamic>>();
      dropUndeclared(events, selected, 6);
      events.first['catalog'] = selected.catalogForVersion(6);
      events.first['catalog_hash'] = jsonHash(events.first['catalog']);
      final report = ValidationReport.parse(events.map(jsonEncode).join('\n'));
      expect(report.problems, isEmpty);
      expect(
        report.cases.map((e) => e['case_id']),
        isNot(anyOf(contains('C08.cancel.restart'), contains('C08.overlap'))),
      );
      events.first['case_ids'] = selected.caseIds;
      expect(
        ValidationReport.parse(events.map(jsonEncode).join('\n')).problems,
        contains('Case inventory does not match the profile'),
      );
    });

    test(
      'invalid grammar needs the backend-specific typed rejection',
      () async {
        for (final web in [false, true]) {
          final result = await run(ggufEngine()..isWeb = web, selected: gguf());
          final grammar = record(result, 'C12.grammar');
          expect(grammar['status'], 'PASS', reason: 'web=$web');
          expect((grammar['rejection'] as Map)['inference_exception'], true);
          expect((grammar['recovery'] as Map)['content'], isNotEmpty);
        }
        for (final fault in [
          'accepted',
          'wrong_message',
          'wrong_type',
          'recovery',
        ]) {
          for (final web in [false, true]) {
            final result = await run(
              ggufEngine()
                ..isWeb = web
                ..grammarFault = fault,
              selected: gguf(),
            );
            expect(
              record(result, 'C12.grammar')['status'],
              'FAIL',
              reason: '$fault web=$web',
            );
          }
        }
      },
    );

    test(
      'auto tool choice must answer a prompt that needs no tool in text',
      () async {
        final selected = gguf();
        expect(
          selected.caseIds,
          containsAll(['C07.tools', 'C07.tools.auto_text']),
        );
        final passing = await run(ggufEngine(), selected: selected);
        expect(record(passing, 'C07.tools.auto_text')['status'], 'PASS');
        expect(record(passing, 'C07.tools')['status'], 'PASS');
        final forced = await run(
          ggufEngine()..featureFault = 'auto_text_tool',
          selected: selected,
        );
        expect(record(forced, 'C07.tools.auto_text')['status'], 'FAIL');
      },
    );

    test(
      'only Web accepts the documented lazy required-tool rejection',
      () async {
        final web = await run(
          ggufEngine()
            ..isWeb = true
            ..requiredFault = 'documented',
          selected: gguf(),
        );
        final tools = record(web, 'C07.tools');
        expect(tools['status'], 'PASS');
        expect(tools['required_documented_web_rejection'], true);
        for (final entry in {
          'native documented': (false, 'documented'),
          'web undocumented': (true, 'other'),
        }.entries) {
          final result = await run(
            ggufEngine()
              ..isWeb = entry.value.$1
              ..requiredFault = entry.value.$2,
            selected: gguf(),
          );
          final failed = record(result, 'C07.tools');
          expect(failed['status'], 'ERROR', reason: entry.key);
          expect(failed['error_type'], 'LlamaUnsupportedException');
        }
      },
    );
  });

  test('diagnostics redact bearer tokens and signed URLs', () {
    expect(
      redactDiagnostic('Bearer secret https://x.test/a?token=secret'),
      isNot(contains('secret')),
    );
  });
}
