import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart_validation/llamadart_validation.dart';
import 'package:test/test.dart';

/// Protocol replay through the real public engine; no model or grammar proof.
class _ReplayBackend
    implements
        LlamaBackend,
        BackendGrammarConstraintsSupport,
        BackendLazyGrammarSupport {
  _ReplayBackend(this.marker);
  final String marker;
  String output = '';
  int chunkSize = 1;
  GenerationParams? request;
  @override
  bool get supportsUrlLoading => false;
  @override
  bool get supportsGrammarConstraints => true;
  @override
  bool get supportsLazyGrammar => true;
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
  Future<int> getContextSize(int handle) async => 2048;
  @override
  Future<Map<String, String>> modelMetadata(int handle) async => {
    'tokenizer.chat_template': '{# $marker #}{{ messages[0]["content"] }}',
    'llm.context_length': '2048',
  };
  @override
  Stream<List<int>> generate(
    int handle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async* {
    request = params;
    final bytes = utf8.encode(output);
    for (var i = 0; i < bytes.length; i += chunkSize) {
      yield bytes.sublist(i, min(i + chunkSize, bytes.length));
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final profile = ValidationProfile.fromJson(
    jsonDecode(File('assets/profiles/chat-gguf-cpu.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  final tool = ToolDefinition(
    name: 'weather',
    description: 'Weather for a city.',
    parameters: [ToolParam.string('city', required: true)],
  );
  for (final sample in [
    (
      family: 'GPT-OSS',
      marker: '<|channel|>',
      output:
          'Let me check.\n<|start|>assistant to=functions.weather<|channel|>commentary<|message|>{"city":"Paris"}<|end|>',
      content: 'Let me check.',
    ),
    (
      family: 'GPT-OSS header continuation',
      marker: '<|channel|>',
      output:
          '<|channel|>analysis to=functions.weather<|message|>{"city":"Paris"}<|end|>',
      content: '',
    ),
    (
      family: 'Llama 3',
      marker: '<|start_header_id|>ipython<|end_header_id|>',
      output: '{"name":"weather","parameters":{"city":"Paris"}}',
      content: '',
    ),
    (
      family: 'Llama 3 typed envelope',
      marker: '<|start_header_id|>ipython<|end_header_id|>',
      output:
          '{"type":"function","name":"weather","parameters":{"city":"Paris"}}\nDone.',
      content: 'Done.',
    ),
    (
      family: 'Gemma 4',
      marker: '<|turn><turn|>',
      output:
          '<|tool_call>call:weather{city:<|"|>Paris<|"|>}<tool_call|>\nDone.',
      content: '\nDone.',
    ),
  ]) {
    for (final mode in [ToolChoice.auto, ToolChoice.required]) {
      test(
        '${sample.family} ${mode.name} public tool stream keeps exact content',
        () async {
          final directory = Directory.systemTemp.createTempSync(
            'tool-stream-replay-',
          );
          addTearDown(() => directory.deleteSync(recursive: true));
          final model = File('${directory.path}/fixture.gguf')
            ..writeAsBytesSync([0, 0, 0, 0]);
          final backend = _ReplayBackend(sample.marker)..output = sample.output;
          final adapter = PublicValidationEngine(
            engineFactory: () => LlamaEngine(backend),
          );
          addTearDown(adapter.dispose);
          await adapter.load(model.path, profile);
          for (final size in [1, 2, 7, utf8.encode(sample.output).length]) {
            backend.chunkSize = size;
            final result = await adapter.generate(
              'Weather?',
              profile,
              tools: [tool],
              toolChoice: mode,
              enableThinking: false,
            );
            expect(
              result['content'],
              sample.content,
              reason: 'chunk size $size',
            );
            expect(result['thinking'], '');
            expect(result['stream_completed'], true);
            expect(result['completion_order_valid'], true);
            expect(result['finish_reasons'], ['tool_calls']);
            final call = (result['tool_call_deltas'] as List).single as Map;
            expect((call['function'] as Map)['name'], 'weather');
            expect(
              jsonDecode((call['function'] as Map)['arguments'] as String),
              {'city': 'Paris'},
            );
            if (sample.family == 'Gemma 4' && mode == ToolChoice.auto) {
              expect(backend.request!.grammar, isNull);
            } else {
              expect(backend.request!.grammar, isNotEmpty);
            }
          }
          backend.output = sample.family.startsWith('GPT-OSS')
              ? '<|channel|>analysis<|message|>Plan.<|end|>'
                    '<|start|>assistant<|channel|>final<|message|>Hello Paris.'
              : 'Hello Paris.';
          final plain = await adapter.generate(
            'Hello',
            profile,
            tools: [tool],
            toolChoice: ToolChoice.none,
            enableThinking: false,
          );
          expect(plain['content'], 'Hello Paris.');
          expect(plain['thinking'], '');
          expect(plain['tool_call_deltas'], isEmpty);
          expect(plain['finish_reasons'], ['stop']);
          expect(backend.request!.grammar, isNull);
          if (sample.family == 'GPT-OSS') {
            for (final literal in ['<think>unfinished', '<think>plan</thi']) {
              backend.output = literal;
              final reply = await adapter.generate(
                'Quote this text',
                profile,
                tools: [tool],
                toolChoice: ToolChoice.auto,
                enableThinking: true,
              );
              expect(reply['content'], literal);
              expect(reply['thinking'], isEmpty);
              expect(reply['tool_call_deltas'], isEmpty);
              expect(reply['finish_reasons'], ['stop']);
            }
          }
        },
      );
    }
  }

  test(
    'Llama 3 builtin public tool stream keeps prose before the tag',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'tool-stream-replay-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final model = File('${directory.path}/fixture.gguf')
        ..writeAsBytesSync([0, 0, 0, 0]);
      const output =
          'Let me check.\n<|python_tag|>code_interpreter.call(code="1+1")';
      final backend = _ReplayBackend(
        '<|start_header_id|>ipython<|end_header_id|><|python_tag|>',
      )..output = output;
      final adapter = PublicValidationEngine(
        engineFactory: () => LlamaEngine(backend),
      );
      addTearDown(adapter.dispose);
      await adapter.load(model.path, profile);
      final builtin = ToolDefinition(
        name: 'code_interpreter',
        description: 'Run code.',
        parameters: [ToolParam.string('code', required: true)],
      );
      for (final mode in [ToolChoice.auto, ToolChoice.required]) {
        for (final size in [1, 2, 7, utf8.encode(output).length]) {
          backend.chunkSize = size;
          final result = await adapter.generate(
            'Compute 1+1',
            profile,
            tools: [builtin],
            toolChoice: mode,
            enableThinking: false,
          );
          final reason = '${mode.name} chunk size $size';
          expect(result['content'], 'Let me check.\n', reason: reason);
          expect(result['finish_reasons'], ['tool_calls'], reason: reason);
          final call = (result['tool_call_deltas'] as List).single as Map;
          expect((call['function'] as Map)['name'], 'code_interpreter');
          expect(jsonDecode((call['function'] as Map)['arguments'] as String), {
            'code': '1+1',
          });
        }
      }
    },
  );
}
