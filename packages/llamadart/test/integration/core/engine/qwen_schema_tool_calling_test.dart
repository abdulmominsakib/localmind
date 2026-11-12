@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../../support/qwen_tool_schema_fixture.dart';
import 'tool_calling_integration_test.dart';

class _QwenBackend extends MockLlamaBackend {
  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async => {
    'general.architecture': 'qwen35',
    'tokenizer.chat_template': File(qwenResultTemplatePath).readAsStringSync(),
  };
}

void main() {
  test('Qwen schema output agrees with pinned upstream parser emissions', () {
    final evidence =
        jsonDecode(
              File(
                'test/fixtures/qwen35_schema_upstream.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final rendered = renderQwenResultHistory(
      templateSource: File(qwenResultTemplatePath).readAsStringSync(),
      thinking: false,
    );
    for (final entry in evidence['cases'] as List) {
      final parsed = ChatTemplateEngine.parse(
        rendered.format,
        entry['emission'] as String,
        tools: [qwenResultTool],
      );
      final upstream = entry['upstream_result'] as Map;
      final expectedCalls = upstream['tool_calls'] as List? ?? [];
      expect(
        parsed.toolCalls.length,
        expectedCalls.length,
        reason: entry['name'],
      );
      for (var i = 0; i < expectedCalls.length; i++) {
        final expected = expectedCalls[i]['function'] as Map;
        expect(parsed.toolCalls[i].function!.name, expected['name']);
        expect(
          jsonDecode(parsed.toolCalls[i].function!.arguments!),
          jsonDecode(expected['arguments'] as String),
        );
      }
      expect(parsed.content, upstream['content'], reason: entry['name']);
    }
  });

  for (final choice in ToolChoice.values) {
    for (final thinking in [true, false]) {
      test(
        'public Qwen engine $choice thinking=$thinking preserves tool schema',
        () async {
          final backend = _QwenBackend();
          final engine = LlamaEngine(backend);
          addTearDown(engine.dispose);
          await engine.loadModel('mock-qwen.gguf');
          backend.queueResponse([
            if (thinking) 'reason</think>\n\n',
            ...qwenResultEnvelope.split(''),
          ]);
          final chunks = await engine
              .create(
                qwenResultHistory(),
                tools: [qwenResultTool],
                toolChoice: choice,
                enableThinking: thinking,
              )
              .toList();
          final calls = chunks
              .expand(
                (c) =>
                    c.choices.single.delta.toolCalls ??
                    const <LlamaCompletionChunkToolCall>[],
              )
              .toList();
          if (choice == ToolChoice.none) {
            expect(calls, isEmpty);
            expect(
              chunks.map((c) => c.choices.single.delta.content ?? '').join(),
              contains(qwenResultEnvelope),
            );
          } else {
            expect(calls, hasLength(1));
            expect(
              jsonDecode(calls.single.function!.arguments!),
              qwenResultPayload,
            );
          }
          expect(
            backend.prompts.single,
            contains(jsonEncode(qwenResultPayload)),
          );
        },
      );
    }
  }

  test('public Qwen engine rejects undeclared call and recovers', () async {
    final backend = _QwenBackend();
    final engine = LlamaEngine(backend);
    addTearDown(engine.dispose);
    await engine.loadModel('mock-qwen.gguf');
    final invalid = qwenResultEnvelope.replaceFirst(
      'function=inspect',
      'function=unknown',
    );
    backend.queueResponse(invalid.split(''));
    final chunks = await engine
        .create(
          qwenResultHistory(),
          tools: [qwenResultTool],
          toolChoice: ToolChoice.auto,
          enableThinking: false,
        )
        .toList();
    expect(
      chunks.expand(
        (c) =>
            c.choices.single.delta.toolCalls ??
            const <LlamaCompletionChunkToolCall>[],
      ),
      isEmpty,
    );
    expect(
      chunks
          .map((c) => c.choices.single.delta.content ?? '')
          .where((c) => c.isNotEmpty)
          .toList(),
      isEmpty,
    );
    backend.queueResponse(['OK']);
    final recovery = await engine.create([
      const LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: 'Reply OK',
      ),
    ], enableThinking: false).toList();
    expect(
      recovery.map((c) => c.choices.single.delta.content ?? '').join(),
      'OK',
    );
  });
}
