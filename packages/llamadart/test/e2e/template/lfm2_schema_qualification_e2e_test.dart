@TestOn('vm')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/engine/chat_completion_stream_parser.dart';
import 'package:test/test.dart';

import '../../support/suite_system_temp.dart';
import '../../support/lfm2_recording_backend.dart';

// Captures actual emissions once; baseline/candidate replay must use these bytes.
void main() {
  useSuiteSystemTemp();
  for (final variable in [
    'LLAMADART_LFM2_SCHEMA_MODEL',
    'LLAMADART_LFM25_SCHEMA_MODEL',
  ]) {
    final path = Platform.environment[variable];
    test('capture schema qualification from $variable', () async {
      if (path == null || !File(path).existsSync()) {
        markTestSkipped('Set $variable to an existing LFM GGUF; no download.');
        return;
      }
      final recorder = Lfm2RecordingBackend();
      final engine = LlamaEngine(recorder);
      addTearDown(engine.dispose);
      await engine.loadModel(
        path,
        modelParams: const ModelParams(
          contextSize: 4096,
          gpuLayers: 0,
          numberOfThreads: 2,
          numberOfThreadsBatch: 2,
        ),
      );
      final modelHash = (await sha256.bind(File(path).openRead()).first)
          .toString();
      final captures = <Map<String, dynamic>>[];
      final filter = Platform.environment['LLAMADART_LFM_SCHEMA_CASES']
          ?.split(',')
          .toSet();
      final cases = _cases()
          .where((scenario) => filter == null || filter.contains(scenario.id))
          .toList();
      expect(cases, isNotEmpty);
      for (final scenario in cases) {
        final messages = [
          const LlamaChatMessage.fromText(
            role: LlamaChatRole.system,
            text: 'You must call a tool. Return only a tool call.',
          ),
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: scenario.prompt,
          ),
        ];
        final rendered = await engine.chatTemplate(
          messages,
          tools: [scenario.tool],
          toolChoice: ToolChoice.auto,
          enableThinking: false,
        );
        expect(rendered.format, ChatFormat.lfm2.index);
        expect(rendered.grammar, isNotNull);
        expect(rendered.grammarLazy, isTrue);
        expect(rendered.grammarTriggers, isNotEmpty);
        expect((await engine.capabilities).supportsLazyGrammar, isTrue);
        recorder.resetCapture();
        await engine
            .create(
              messages,
              tools: [scenario.tool],
              toolChoice: ToolChoice.auto,
              enableThinking: false,
              params: const GenerationParams(maxTokens: 200, temp: 0, seed: 1),
            )
            .drain<void>();
        expect(recorder.countedPromptPenalties, isTrue);
        final params = recorder.lastParams!;
        expect(params.grammar, rendered.grammar);
        expect(params.grammarLazy, isTrue);
        expect(params.grammarTriggers, isNotEmpty);
        final raw = recorder.raw;
        final capture = <String, dynamic>{
          'id': scenario.id,
          'model': File(path).uri.pathSegments.last,
          'model_sha256': modelHash,
          'backend': await engine.getBackendName(),
          'prompt': scenario.prompt,
          'rendered_prompt': rendered.prompt,
          'tool': {
            'name': scenario.tool.name,
            'description': scenario.tool.description,
            'schema': scenario.tool.toJsonSchema(),
            'origin': 'legacy_parameters',
          },
          'raw': raw,
          'format': rendered.format,
          'thinking_forced_open': rendered.thinkingForcedOpen,
          'grammar_lazy': params.grammarLazy,
          'prompt_penalties_with_grammar': recorder.countedPromptPenalties,
          'grammar_triggers': [
            for (final trigger in rendered.grammarTriggers)
              {
                'type': trigger.type,
                'value': trigger.value,
                'token': trigger.token,
              },
          ],
          'expected_arguments': scenario.expected,
          'sampling': {'temp': 0, 'seed': 1, 'max_tokens': 200, 'threads': 2},
        };
        // Persist before parsing: even a parser failure must retain the emission.
        captures.add(capture);
        _save(captures, variable);
        final parsed = ChatTemplateEngine.parseRendered(
          rendered,
          raw,
          tools: [scenario.tool],
        );
        capture['parsed'] = {
          'content': parsed.content,
          'reasoning': parsed.reasoningContent,
          'calls': [
            for (final call in parsed.toolCalls)
              {
                'name': call.function?.name,
                'arguments': call.function?.arguments,
              },
          ],
        };
        for (final size in [1, 7]) {
          final completion = await ChatCompletionStreamParser.parse(
            tokenStream: Stream.fromIterable([
              for (var i = 0; i < raw.length; i += size)
                raw.substring(i, i + size < raw.length ? i + size : raw.length),
            ]),
            templateResult: rendered,
            parseToolCallsEnabled: true,
            enableThinking: false,
            modelName: 'lfm-schema-qualification',
            completionId: '${scenario.id}-$size',
            tools: [scenario.tool],
          ).collect();
          expect(
            completion.text,
            parsed.content,
            reason: '${scenario.id}/$size',
          );
          expect(
            [
              for (final call in completion.toolCalls)
                [call.name, call.arguments],
            ],
            [
              for (final call in parsed.toolCalls)
                [call.function!.name, jsonDecode(call.function!.arguments!)],
            ],
            reason: '${scenario.id}/$size',
          );
        }
        capture['stream_chunk_sizes'] = [1, 7];
        _save(captures, variable);
        print('LFM_SCHEMA_CAPTURE ${jsonEncode(capture)}');
      }
      expect(captures, hasLength(cases.length));
    });
  }
}

void _save(List<Map<String, dynamic>> captures, String variable) {
  final directory = Platform.environment['LLAMADART_LFM_SCHEMA_CAPTURE_DIR'];
  if (directory == null) return;
  final target = Directory(directory)..createSync(recursive: true);
  File(
    '${target.path}/$variable.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(captures));
}

typedef _Case = ({
  String id,
  String prompt,
  ToolDefinition tool,
  Map<String, dynamic> expected,
});

List<_Case> _cases() {
  ToolDefinition text(String name, String parameter) => ToolDefinition(
    name: name,
    description: name == 'save_note' ? 'Saves a note.' : 'Runs Python code.',
    parameters: [ToolParam.string(parameter, required: true)],
  );
  return [
    (
      id: 'winnew',
      prompt: r'Save a note with the exact text: C:\new\table.txt',
      tool: text('save_note', 'text'),
      expected: {'text': r'C:\new\table.txt'},
    ),
    (
      id: 'py_path',
      prompt: r"Run this Python code: print('C:\\temp\\x.txt')",
      tool: text('run_python', 'code'),
      expected: {'code': r"print('C:\\temp\\x.txt')"},
    ),
    (
      id: 'shell',
      prompt: r'Save a note with the exact text: echo \"hi\" > out.txt',
      tool: text('save_note', 'text'),
      expected: {'text': r'echo \"hi\" > out.txt'},
    ),
    (
      id: 'string_false',
      prompt: 'Fill the field discount with the value False.',
      tool: ToolDefinition(
        name: 'fill_field',
        description: 'Fill the specified field with a text value.',
        parameters: [
          ToolParam.string('field', required: true),
          ToolParam.string('value', required: true),
        ],
      ),
      expected: {'field': 'discount', 'value': 'False'},
    ),
    (
      id: 'typed_flag',
      prompt: 'Call set_flag with enabled True and note None.',
      tool: ToolDefinition(
        name: 'set_flag',
        description: 'Set a flag and its empty note.',
        parameters: [
          ToolParam.boolean('enabled', required: true),
          ToolParam.nullType('note', required: true),
        ],
      ),
      expected: {'enabled': true, 'note': null},
    ),
    (
      id: 'named_object',
      prompt:
          'Call save_config with config containing enabled True and retries 2.',
      tool: ToolDefinition(
        name: 'save_config',
        description: 'Save a configuration object.',
        parameters: [
          ToolParam.object(
            'config',
            required: true,
            properties: [
              ToolParam.boolean('enabled', required: true),
              ToolParam.integer('retries', required: true),
            ],
          ),
        ],
      ),
      expected: {
        'config': {'enabled': true, 'retries': 2},
      },
    ),
    (
      id: 'noargs',
      prompt: 'What time is it?',
      tool: ToolDefinition(
        name: 'get_time',
        description: 'Returns the time.',
        parameters: [],
      ),
      expected: {},
    ),
  ];
}
