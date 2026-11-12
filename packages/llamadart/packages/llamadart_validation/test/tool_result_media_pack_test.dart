import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart_validation/llamadart_validation.dart';
import 'package:llamadart_validation/src/tool_result_media_evidence.dart';
import 'package:test/test.dart';

import 'validation_test.dart' as harness;

/// Answers from the image that the request carries, like a vision model would.
class _VisionEngine extends harness.FakeEngine
    implements ToolResultMediaValidationEngine {
  _VisionEngine() {
    backendName = 'CPU';
  }
  @override
  bool hasVisionProjector = true;
  List<String> kinds = ['image'];
  String? fault;
  final histories = <List<Map<String, dynamic>>>[];

  @override
  Future<List<String>> toolResultMediaKinds() async => kinds;

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
    final messages = history?.map((m) => m.toJson()).toList();
    if (messages != null) histories.add(messages.cast<Map<String, dynamic>>());
    final answer = messages == null ? '' : _answer(messages);
    return {
      'prompt': prompt,
      'messages': ?messages,
      'max_tokens': maxTokens,
      'enable_thinking': enableThinking,
      'tools': tools?.map((t) => t.toJson()).toList(),
      'tool_choice': toolChoice?.name,
      'content': answer,
      'thinking': '',
      'chunks': 1,
      'finish_reasons': messages == null && tools != null
          ? ['tool_calls']
          : ['stop'],
      'tool_call_deltas': messages == null && tools != null && fault != 'nocall'
          ? [
              {
                'index': 0,
                'id': 'call_0',
                'function': {'name': tools.single.name, 'arguments': '{}'},
              },
            ]
          : [],
      'stream_completed': true,
      'completion_order_valid': true,
      'metrics': <String, dynamic>{},
    };
  }

  String _answer(List<Map<String, dynamic>> messages) {
    if (fault == 'blind') return 'Green';
    if (fault == 'constant') return 'Red';
    if (fault == 'both') return 'Red and blue';
    final last = jsonEncode(messages.last);
    for (final color in toolResultMediaColors) {
      if (last.contains(toolResultMediaImage(color)['png_base64'] as String)) {
        return color[0].toUpperCase() + color.substring(1);
      }
    }
    return 'I cannot see an image';
  }
}

ValidationProfile _profile([String name = 'qwen3vl-gguf-cpu']) =>
    ValidationProfile.fromJson(
      jsonDecode(File('assets/profiles/$name.json').readAsStringSync())
          as Map<String, dynamic>,
    );

Future<({ValidationReport report, List<Map<String, dynamic>> events})> _run(
  _VisionEngine engine,
) async {
  final profile = _profile();
  final projector = profile.toolResultProjector!;
  final events = <Map<String, dynamic>>[];
  await ValidationRunner(
    profile: profile,
    engine: engine,
    emit: (event) async => events.add(event),
    caseTimeout: const Duration(seconds: 10),
  ).run(
    'model.gguf',
    runId: 'tool-result-media-fixture',
    preparation: {
      'verified': true,
      'sha256': profile.modelHash,
      'bytes': profile.model['bytes'],
      'projector': {
        'verified': true,
        'sha256': projector['sha256'],
        'bytes': projector['bytes'],
      },
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

Map<String, dynamic> _record(List<Map<String, dynamic>> events) =>
    events.singleWhere(
      (e) => e['type'] == 'case' && e['case_id'] == 'M01.tool_result_image',
    );

void main() {
  const id = 'M01.tool_result_image';

  test('fixture images match their locked hashes', () {
    for (final color in toolResultMediaColors) {
      expect(toolResultMediaImage(color)['sha256'], hasLength(64));
    }
    expect(toolResultMediaColors, ['red', 'blue']);
  });

  test('catalog 12 selects the case only for a locked projector', () {
    for (final name in ['qwen3vl-gguf-cpu', 'qwen3vl-gguf-metal']) {
      final selected = _profile(name);
      expect(selected.caseIds, contains(id));
      expect(selected.toolResultProjector!['filename'], startsWith('mmproj-'));
      expect(() => selected.catalogForVersion(11), throwsFormatException);
    }
    final text = ValidationProfile.fromJson(
      jsonDecode(File('assets/profiles/chat-gguf-cpu.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    expect(text.caseIds, isNot(contains(id)));
    final omitted = (text.catalog['cases'] as List).cast<Map>().singleWhere(
      (c) => c['id'] == id,
    );
    expect(omitted['selected'], false);
    expect(omitted['omission_reason'], 'no_vision_projector_locked');
  });

  test('catalogs 1 to 11 keep their inventories', () {
    const pinned = {
      'tiny-gguf-cpu':
          '2c685738a85a8b86954fea2d9817cb95393f6c57ac575f8fde9c450c26f1bbb2',
      'chat-gguf-cpu':
          '23919985bad9b732c5cb3eb0e869a1b3000314fff303ae6ff1cc66177efd49bd',
    };
    for (final entry in pinned.entries) {
      final profile = _profile(entry.key);
      final catalog = profile.catalogForVersion(11);
      expect(jsonHash(catalog), entry.value);
      expect(catalog['features'], isNot(contains('tool_result_media')));
      expect(catalog['fixtures'], isNot(contains('tool_result_media')));
      expect(
        profile.caseIdsForCatalog(11).any((case_) => case_.startsWith('M')),
        false,
      );
    }
  });

  test(
    'a projector lock needs the focus, a native chat profile and a revision',
    () {
      Map<String, dynamic> data() =>
          jsonDecode(
                File(
                  'assets/profiles/qwen3vl-gguf-cpu.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final mutations = <String, void Function(Map<String, dynamic>)>{
        'no projector': (d) => d.remove('projector'),
        'no focus': (d) => d['focus_features'] = ['tools'],
        'wrong revision': (d) => d['projector']['revision'] = 'a' * 40,
        'webgpu': (d) => d['backend'] = 'webgpu',
        'raw model': (d) => d['model']['kind'] = 'raw',
        'extra field': (d) => d['projector']['extra'] = 1,
      };
      for (final entry in mutations.entries) {
        final changed = data();
        entry.value(changed);
        expect(
          () => ValidationProfile.fromJson(changed),
          throwsFormatException,
          reason: entry.key,
        );
      }
    },
  );

  test('the Web host cannot run the pack', () {
    expect(
      () => _profile().requireRunnable(web: true),
      throwsA(isA<LlamaUnsupportedException>()),
    );
  });

  test('a tool-result image reaches each next turn and is read back', () async {
    final engine = _VisionEngine();
    final result = await _run(engine);
    final record = _record(result.events);
    expect(record['status'], 'PASS', reason: jsonEncode(record));
    expect(validToolResultMediaCaseEvidence(id, record, _profile()), true);
    expect(
      engine.histories.where((history) => history.last['role'] == 'tool'),
      hasLength(2),
    );
    expect(result.report.problems.where((p) => p.contains('media')), isEmpty);
  });

  for (final fault in ['blind', 'constant', 'both', 'nocall']) {
    test('$fault model cannot pass the case', () async {
      final result = await _run(_VisionEngine()..fault = fault);
      expect(_record(result.events)['status'], 'FAIL');
      expect(result.report.qualified, false);
    });
  }

  test('a capability report without image tool results fails', () async {
    final result = await _run(_VisionEngine()..kinds = []);
    expect(_record(result.events)['status'], 'FAIL');
  });

  test('a host without the projector leaves the case NOT_RUN', () async {
    final result = await _run(_VisionEngine()..hasVisionProjector = false);
    expect(_record(result.events)['status'], 'NOT_RUN');
    expect(result.report.qualified, false);
  });

  test('importer rejects forged evidence', () async {
    final result = await _run(_VisionEngine());
    final mutations = <String, void Function(Map<String, dynamic>)>{
      'no capability': (e) => e['tool_result_media'] = <String>[],
      'wrong tool': (e) =>
          e['call']['tool_call_deltas'][0]['function']['name'] = 'other',
      'forged reconstructed name': (e) {
        e['call']['tool_call_deltas'] = [];
        e['call']['reconstructed_name'] = 'take_photo';
      },
      'changed call tools': (e) => e['call']['tools'] = [],
      'changed call budget': (e) => e['call']['max_tokens'] = 1,
      'changed answer budget': (e) => e['trials'][0]['max_tokens'] = 1,
      'word containing a color': (e) =>
          e['trials'][0]['content'] = 'Bored of the reddish photo',
      'extra other-color image in the user turn': (e) =>
          e['trials'][0]['messages'][0]['content'] = [
            {'type': 'text', 'text': 'x'},
            e['trials'][1]['messages'][2]['content'][1],
          ],
      'text hint in the tool content': (e) =>
          (e['trials'][0]['messages'][2]['content'] as List).insert(1, {
            'type': 'text',
            'text': 'red',
          }),
      'second image in the tool content': (e) =>
          (e['trials'][0]['messages'][2]['content'] as List).add(
            e['trials'][1]['messages'][2]['content'][1],
          ),
      'replaced assistant turn': (e) => e['trials'][0]['messages'][1] = {
        'role': 'assistant',
        'content': 'ok',
      },
      'wrong tool call id': (e) =>
          e['trials'][0]['messages'][2]['tool_call_id'] = 'call_9',
      'wrong tool name': (e) => e['trials'][0]['messages'][2]['name'] = 'other',
      'wrong image hash': (e) => e['trials'][0]['image_sha256'] = 'a' * 64,
      'text finish call': (e) => e['call']['finish_reasons'] = ['stop'],
      'missing trial': (e) => (e['trials'] as List).removeLast(),
      'swapped colors': (e) =>
          e['trials'] = (e['trials'] as List).reversed.toList(),
      'wrong answer': (e) => e['trials'][0]['content'] = 'Blue',
      'both colors': (e) => e['trials'][0]['content'] = 'Red or blue',
      'no image part': (e) => e['trials'][1]['messages'][2]['content'] = [
        {'type': 'text', 'text': '{"ok":true}'},
      ],
      'other image': (e) {
        final part = e['trials'][1]['messages'][2]['content'][1] as Map;
        part['image_url']['url'] = (part['image_url']['url'] as String)
            .replaceFirst('iVBOR', 'iVBOS');
      },
      'tool call in answer turn': (e) =>
          e['trials'][0]['tool_call_deltas'] = [<String, dynamic>{}],
      'incomplete stream': (e) => e['trials'][0]['stream_completed'] = false,
    };
    for (final entry in mutations.entries) {
      final events = (jsonDecode(jsonEncode(result.events)) as List)
          .cast<Map<String, dynamic>>();
      entry.value(_record(events));
      final report = ValidationReport.parse(events.map(jsonEncode).join('\n'));
      expect(
        report.problems,
        contains('Invalid tool-result media case evidence: $id'),
        reason: entry.key,
      );
      expect(report.qualified, false, reason: entry.key);
    }
  });

  test('provenance requires the verified projector', () async {
    final result = await _run(_VisionEngine());
    final events = (jsonDecode(jsonEncode(result.events)) as List)
        .cast<Map<String, dynamic>>();
    final manifest = events.firstWhere((e) => e['type'] == 'manifest');
    (manifest['preparation'] as Map).remove('projector');
    final report = ValidationReport.parse(events.map(jsonEncode).join('\n'));
    expect(
      report.provenanceProblems,
      contains(
        'Verified vision projector hash and byte size do not match the profile lock',
      ),
    );
  });

  test('a projector bytes or hash mismatch is a provenance problem', () async {
    final result = await _run(_VisionEngine());
    for (final field in ['bytes', 'sha256']) {
      final events = (jsonDecode(jsonEncode(result.events)) as List)
          .cast<Map<String, dynamic>>();
      final manifest = events.firstWhere((e) => e['type'] == 'manifest');
      (manifest['preparation']['projector'] as Map)[field] = field == 'bytes'
          ? 1
          : 'b' * 64;
      final report = ValidationReport.parse(events.map(jsonEncode).join('\n'));
      expect(
        report.provenanceProblems,
        contains(
          'Verified vision projector hash and byte size do not match the profile lock',
        ),
        reason: field,
      );
    }
  });

  test('a projector from another revision than the model is rejected', () {
    final data =
        jsonDecode(
              File('assets/profiles/qwen3vl-gguf-cpu.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final projector = data['projector'] as Map<String, dynamic>;
    projector['revision'] = 'b' * 40;
    projector['url'] = (projector['url'] as String).replaceFirst(
      'ea6a11058182570be6436b9a2e4ee7f7b49f908d',
      'b' * 40,
    );
    expect(() => ValidationProfile.fromJson(data), throwsFormatException);
  });

  test('the public adapter rejects a locked projector it was not given', () {
    expect(
      PublicValidationEngine().load('model.gguf', _profile()),
      throwsA(isA<LlamaUnsupportedException>()),
    );
  });
}
