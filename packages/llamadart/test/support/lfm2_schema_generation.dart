import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';

import 'lfm2_schema_replay.dart';
import 'lfm2_recording_backend.dart';
import 'lfm2_public_completion_capture.dart';

/// Captures fresh generation from exact historical prompt/tool/sampling rows.
///
/// Usage: `dart run test/support/lfm2_schema_generation.dart manifest.json`
/// `output.json existing-model-directory python|absent [--dry-run]`.
/// Select CPU (default) or existing Metal with LLAMADART_LFM_GENERATION_BACKEND.
Future<void> main(List<String> arguments) async {
  if (arguments.length < 4 || !['python', 'absent'].contains(arguments[3])) {
    stderr.writeln(
      'Expected manifest, output, existing model directory and '
      'python|absent auto-grammar contract. Optional: --dry-run.',
    );
    exitCode = 64;
    return;
  }
  final rows = (jsonDecode(File(arguments[0]).readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final ids = <String>{};
  final toolsById = <String, List<ToolDefinition>>{};
  for (final row in rows) {
    final id = '${row['set']}/${row['key']}';
    if (!ids.add(id)) throw StateError('Duplicate capture identity.');
    final sampling = row['sampling'] as Map;
    for (final field in [
      'maxTokens',
      'temp',
      'seed',
      'topK',
      'topP',
      'minP',
      'penalty',
    ]) {
      if (!sampling.containsKey(field)) {
        throw StateError('Incomplete sampling metadata.');
      }
    }
    if (['maxTokens', 'topK'].any((field) => sampling[field] is! int) ||
        sampling['seed'] != null && sampling['seed'] is! int ||
        ['temp', 'topP', 'minP', 'penalty'].any(
          (field) =>
              sampling[field] is! num || !(sampling[field] as num).isFinite,
        ) ||
        row['parallel'] is! bool ||
        row['thinking'] is! bool) {
      throw StateError('Invalid original sampling or request metadata.');
    }
    final model = File('${arguments[2]}/${row['model']}');
    if (!model.existsSync()) {
      throw StateError('Required cached model is unavailable.');
    }
    toolsById[id] = [
      for (final encoded in row['tools'] as List) _tool(encoded as Map),
    ];
  }
  if (arguments.contains('--dry-run')) {
    stdout.writeln(
      jsonEncode({
        'rows': rows.length,
        'models': rows.map((r) => r['model']).toSet().length,
        'tools_and_sampling': 'validated',
        'auto_grammar_contract': arguments[3],
      }),
    );
    return;
  }
  final useMetal =
      Platform.environment['LLAMADART_LFM_GENERATION_BACKEND'] == 'metal';
  final captureIdentity = await _captureIdentity(arguments[0]);
  final output = File(arguments[1]);
  final captures = <Map<String, dynamic>>[];
  for (final model in rows.map((row) => row['model'] as String).toSet()) {
    final file = File('${arguments[2]}/$model');
    final hash = (await sha256.bind(file.openRead()).first).toString();
    final recorder = Lfm2RecordingBackend();
    final engine = LlamaEngine(recorder);
    try {
      await engine.loadModel(
        file.path,
        modelParams: ModelParams(
          contextSize: 4096,
          gpuLayers: useMetal ? ModelParams.maxGpuLayers : 0,
          preferredBackend: useMetal ? GpuBackend.metal : GpuBackend.cpu,
          device: useMetal ? ComputeDevice.gpu : ComputeDevice.cpu,
          numberOfThreads: 2,
          numberOfThreadsBatch: 2,
        ),
      );
      final backend = await engine.getBackendName();
      if (useMetal && !backend.toLowerCase().contains('metal')) {
        throw StateError('Explicit Metal generation did not use Metal.');
      }
      for (final row in rows.where((row) => row['model'] == model)) {
        final id = '${row['set']}/${row['key']}';
        final tools = toolsById[id]!;
        final rendered = await engine.chatTemplate(
          [
            LlamaChatMessage.fromText(
              role: LlamaChatRole.system,
              text: row['system'] as String,
            ),
            LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: row['prompt'] as String,
            ),
          ],
          tools: tools,
          toolChoice: ToolChoice.values.byName(row['choice'] as String),
          parallelToolCalls: row['parallel'] as bool,
          enableThinking: row['thinking'] as bool,
        );
        final plainLfmAuto =
            rendered.format == ChatFormat.lfm2.index &&
            row['choice'] == 'auto' &&
            !(row['system'] as String).toLowerCase().contains(
              'force json schema.',
            );
        if (plainLfmAuto) {
          final expected = arguments[3] == 'python';
          if (expected != rendered.grammarLazy ||
              expected != (rendered.grammar != null) ||
              expected != rendered.grammarTriggers.isNotEmpty) {
            throw StateError(
              'Rendered auto grammar does not match the declared capture contract.',
            );
          }
          if (expected && !(await engine.capabilities).supportsLazyGrammar) {
            throw StateError(
              'Runtime does not admit lazy grammar qualification.',
            );
          }
        }
        final sampling = row['sampling'] as Map;
        final params = GenerationParams(
          maxTokens: sampling['maxTokens'] as int,
          temp: (sampling['temp'] as num).toDouble(),
          seed: sampling['seed'] as int?,
          topK: sampling['topK'] as int,
          topP: (sampling['topP'] as num).toDouble(),
          minP: (sampling['minP'] as num).toDouble(),
          penalty: (sampling['penalty'] as num).toDouble(),
        );
        recorder.resetCapture();
        final watch = Stopwatch()..start();
        final publicCapture = Lfm2PublicCompletionCapture();
        await publicCapture.consume(
          engine.create(
            [
              LlamaChatMessage.fromText(
                role: LlamaChatRole.system,
                text: row['system'] as String,
              ),
              LlamaChatMessage.fromText(
                role: LlamaChatRole.user,
                text: row['prompt'] as String,
              ),
            ],
            params: params,
            tools: tools,
            toolChoice: ToolChoice.values.byName(row['choice'] as String),
            parallelToolCalls: row['parallel'] as bool,
            enableThinking: row['thinking'] as bool,
          ),
        );
        final completionError = publicCapture.error;
        final dispatched = recorder.lastParams;
        if (dispatched == null) {
          throw StateError(
            'Public completion did not dispatch: $completionError',
          );
        }
        if (dispatched.grammar != rendered.grammar ||
            dispatched.grammarLazy != rendered.grammarLazy ||
            jsonEncode(
                  dispatched.grammarTriggers
                      .map(
                        (trigger) => [
                          trigger.type,
                          trigger.value,
                          trigger.token,
                        ],
                      )
                      .toList(),
                ) !=
                jsonEncode(
                  rendered.grammarTriggers
                      .map(
                        (trigger) => [
                          trigger.type,
                          trigger.value,
                          trigger.token,
                        ],
                      )
                      .toList(),
                )) {
          throw StateError(
            'Public completion changed the expected rendered grammar state.',
          );
        }
        if (plainLfmAuto &&
            arguments[3] == 'python' &&
            !recorder.countedPromptPenalties) {
          throw StateError(
            'Public completion omitted required prompt penalties.',
          );
        }
        final raw = recorder.raw;
        final record = <String, dynamic>{
          ...row,
          'capture_identity': captureIdentity,
          'id': id,
          'raw': raw,
          'raw_byte_chunks': recorder.byteChunks,
          'native_outcome': recorder.capturedOutcome,
          ...publicCapture.toJson(),
          'raw_sha256': sha256.convert(utf8.encode(raw)).toString(),
          'model_sha256': hash,
          'backend': backend,
          'generation_ms': watch.elapsedMilliseconds,
          'format': rendered.format,
          'thinking_forced_open': rendered.thinkingForcedOpen,
          'rendered_prompt': rendered.prompt,
          'grammar': dispatched.grammar,
          'grammar_lazy': dispatched.grammarLazy,
          'grammar_root': dispatched.grammarRoot,
          'grammar_triggers': [
            for (final trigger in dispatched.grammarTriggers)
              {
                'type': trigger.type,
                'value': trigger.value,
                'token': trigger.token,
              },
          ],
          'preserved_tokens': dispatched.preservedTokens,
          'stop_sequences': dispatched.stopSequences,
          'prompt_penalties_with_grammar': recorder.countedPromptPenalties,
          if (completionError != null)
            'completion_error': completionError.toString(),
          'provenance':
              'Fresh public engine.create generation from exact manifest; raw backend bytes retained before parsing.',
        };
        recordLfm2Capture(output, captures, record);
        stdout.writeln(
          jsonEncode({
            'id': id,
            'format': rendered.format,
            'grammar_lazy': dispatched.grammarLazy,
            'triggers': dispatched.grammarTriggers.length,
            'generation_ms': record['generation_ms'],
          }),
        );
      }
    } finally {
      await engine.dispose();
      _publishCaptures(output, captures);
    }
  }
}

ToolDefinition _tool(Map encoded) {
  final function = Map<String, dynamic>.from(encoded['function'] as Map);
  final tool = lfm2CaptureTool({
    'tool': {
      'name': function['name'],
      'description': function['description'],
      'schema': function['parameters'],
      'origin': 'legacy_parameters',
    },
  });
  if (jsonEncode(tool.toJson()) != jsonEncode(encoded)) {
    throw StateError('Tool reconstruction changed the original declaration.');
  }
  return tool;
}

/// Journals raw evidence before replay and publishes only finalized rows.
void recordLfm2Capture(
  File output,
  List<Map<String, dynamic>> captures,
  Map<String, dynamic> latest, {
  Map<String, dynamic> Function(Map<String, dynamic>) replay =
      replayLfm2Capture,
}) {
  File(
    '${output.path}.jsonl',
  ).writeAsStringSync('${jsonEncode(latest)}\n', mode: FileMode.append);
  try {
    latest['result'] = replay(latest);
  } catch (error) {
    latest['error'] = {
      'type': error.runtimeType.toString(),
      'message': error.toString(),
    };
  }
  captures.add(latest);
  _publishCaptures(output, captures);
}

void _publishCaptures(File output, List<Map<String, dynamic>> captures) {
  // Monitors must never observe a row before replay finishes or a truncated JSON.
  final staging = File('${output.path}.tmp')
    ..writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(captures),
      flush: true,
    );
  staging.renameSync(output.path);
}

Future<Map<String, dynamic>> _captureIdentity(String manifestPath) async {
  Future<String> digest(String path) async =>
      (await sha256.bind(File(path).openRead()).first).toString();
  Future<String> git(List<String> arguments) async {
    final result = await Process.run('git', arguments);
    if (result.exitCode != 0) throw StateError('Cannot bind capture revision.');
    return (result.stdout as String).trim();
  }

  final runtimeArtifact =
      Platform.environment['LLAMADART_LFM_RUNTIME_ARTIFACT'];
  return {
    'head': await git(['rev-parse', 'HEAD']),
    'tree': await git(['rev-parse', 'HEAD^{tree}']),
    'tracked_dirty': (await git([
      'status',
      '--porcelain',
      '--untracked-files=no',
    ])).isNotEmpty,
    'manifest_sha256': await digest(manifestPath),
    'support_sha256': {
      for (final name in [
        'lfm2_schema_generation.dart',
        'lfm2_recording_backend.dart',
        'lfm2_public_completion_capture.dart',
        'lfm2_schema_replay.dart',
      ])
        name: await digest('test/support/$name'),
    },
    'package_config_sha256': await digest('.dart_tool/package_config.json'),
    'pubspec_lock_sha256': await digest('pubspec.lock'),
    'runtime_artifact': runtimeArtifact == null
        ? {'status': 'unavailable'}
        : {
            'status': 'caller_supplied_bytes_only',
            'sha256': await digest(runtimeArtifact),
          },
    'model_load': {
      'context_size': 4096,
      'number_of_threads': 2,
      'number_of_threads_batch': 2,
    },
  };
}
