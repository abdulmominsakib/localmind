import 'dart:async';
import 'dart:convert';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/engine/chat_completion_stream_parser.dart';
import 'package:llamadart/src/core/template/handlers/qwen3_coder_xml_handler.dart';
import 'package:test/test.dart';

import '../../../support/qwen_tool_schema_fixture.dart';

void main() {
  test(
    'production routing preserves schema string and scalar/container types',
    () {
      final rendered = renderQwenResultHistory();
      final parsed = ChatTemplateEngine.parse(
        rendered.format,
        qwenResultEnvelope,
        tools: [qwenResultTool],
      );
      expect(parsed.toolCalls, hasLength(1));
      expect(
        jsonDecode(parsed.toolCalls.single.function!.arguments!),
        qwenResultPayload,
      );
      // Proves the new schema-aware dispatch differs from legacy schema-free use.
      final legacy = Qwen3CoderXmlHandler().parse(qwenResultEnvelope);
      expect(
        jsonDecode(legacy.toolCalls.single.function!.arguments!)['code'],
        123,
      );
    },
  );

  for (final value in [
    '123',
    'true',
    'null',
    '{}',
    '[]',
    'Montréal 👋',
    'a\nb',
  ]) {
    test('schema-declared string preserves literal $value', () {
      final input = qwenResultEnvelope.replaceFirst(
        '>\n123\n</parameter>',
        '>\n$value\n</parameter>',
      );
      final parsed = ChatTemplateEngine.parse(
        renderQwenResultHistory().format,
        input,
        tools: [qwenResultTool],
      );
      expect(parsed.toolCalls, hasLength(1));
      expect(
        jsonDecode(parsed.toolCalls.single.function!.arguments!)['code'],
        value,
      );
    });
  }

  final invalid = <String, String>{
    'undeclared function': qwenResultEnvelope.replaceFirst(
      'function=inspect',
      'function=unknown',
    ),
    'undeclared parameter': qwenResultEnvelope.replaceFirst(
      'parameter=code',
      'parameter=unknown',
    ),
    'duplicate parameter': qwenResultEnvelope.replaceFirst(
      '</function>',
      '<parameter=code>duplicate</parameter>\n</function>',
    ),
    'missing required parameter': qwenResultEnvelope.replaceFirst(
      '<parameter=count>\n7\n</parameter>\n',
      '',
    ),
    'wrong integer': qwenResultEnvelope.replaceFirst(
      '>\n7\n</parameter>',
      '>\nwrong\n</parameter>',
    ),
    'wrong boolean': qwenResultEnvelope.replaceFirst(
      '>\ntrue\n</parameter>',
      '>\n7\n</parameter>',
    ),
    'wrong null': qwenResultEnvelope.replaceFirst(
      '>\nnull\n</parameter>',
      '>\nfalse\n</parameter>',
    ),
    'wrong container': qwenResultEnvelope.replaceFirst(
      '>\n[]\n</parameter>',
      '>\n{}\n</parameter>',
    ),
    'wrong array element': qwenResultEnvelope.replaceFirst(
      '>\n[]\n</parameter>',
      '>\n[7]\n</parameter>',
    ),
    'unknown object property': qwenResultEnvelope.replaceFirst(
      '>\n{}\n</parameter>',
      '>\n{"extra":1}\n</parameter>',
    ),
    'malformed later call': qwenResultEnvelope.replaceFirst(
      '</tool_call>',
      '<function=unknown></function>\n</tool_call>',
    ),
  };
  // As in llama.cpp, the reply ends before an invalid call.
  for (final entry in invalid.entries) {
    test('production parser atomically rejects ${entry.key}', () {
      final parsed = ChatTemplateEngine.parse(
        renderQwenResultHistory().format,
        entry.value,
        tools: [qwenResultTool],
      );
      expect(parsed.toolCalls, isEmpty);
      expect(parsed.content, isEmpty);
    });
  }

  test('a call whose reply ends before its scope end counts', () {
    final parsed = ChatTemplateEngine.parse(
      renderQwenResultHistory().format,
      qwenResultEnvelope.replaceFirst('</tool_call>', ''),
      tools: [qwenResultTool],
    );
    expect(parsed.toolCalls, hasLength(1));
    expect(
      jsonDecode(parsed.toolCalls.single.function!.arguments!),
      qwenResultPayload,
    );
  });

  test('explicit empty tools cannot create an undeclared call', () {
    final parsed = ChatTemplateEngine.parse(
      renderQwenResultHistory().format,
      qwenResultEnvelope,
      tools: [],
    );
    expect(parsed.toolCalls, isEmpty);
    expect(parsed.content, isEmpty);
  });

  test('zero-argument and optional schemas remain valid', () {
    final tool = ToolDefinition(
      name: 'ping',
      description: 'Optional argument control',
      parameters: [ToolParam.string('label')],
      handler: (_) async => null,
    );
    final parsed = ChatTemplateEngine.parse(
      renderQwenResultHistory().format,
      '<tool_call>\n<function=ping>\n</function>\n</tool_call>',
      tools: [tool],
    );
    expect(
      jsonDecode(parsed.toolCalls.single.function!.arguments!),
      <String, dynamic>{},
    );
  });

  for (final choice in ToolChoice.values) {
    for (final thinking in [true, false]) {
      for (final malformed in [false, true]) {
        test(
          'stream $choice thinking=$thinking malformed=$malformed is atomic',
          () async {
            final rendered = renderQwenResultHistory(
              choice: choice,
              thinking: thinking,
            );
            final body = malformed
                ? invalid['undeclared function']!
                : qwenResultEnvelope;
            final source = StreamController<String>();
            final chunks = <LlamaCompletionChunk>[];
            final done = ChatCompletionStreamParser.parse(
              tokenStream: source.stream,
              templateResult: rendered,
              parseToolCallsEnabled: choice != ToolChoice.none,
              enableThinking: thinking,
              modelName: 'qwen-schema-fixture',
              completionId: 'schema',
              tools: [qwenResultTool],
            ).forEach(chunks.add);
            if (thinking) source.add('reason</think>\n\n');
            for (final character in body.split('')) {
              source.add(character);
            }
            await Future<void>.delayed(Duration.zero);
            expect(
              chunks.expand(
                (c) =>
                    c.choices.single.delta.toolCalls ??
                    const <LlamaCompletionChunkToolCall>[],
              ),
              isEmpty,
              reason: 'No executable call before final validation',
            );
            await source.close();
            await done;
            final calls = chunks
                .expand(
                  (c) =>
                      c.choices.single.delta.toolCalls ??
                      const <LlamaCompletionChunkToolCall>[],
                )
                .toList();
            final content = chunks
                .map((c) => c.choices.single.delta.content ?? '')
                .where((v) => v.isNotEmpty)
                .toList();
            final reasoning = chunks
                .map((c) => c.choices.single.delta.thinking ?? '')
                .join();
            expect(reasoning.trim(), thinking ? 'reason' : '');
            if (choice == ToolChoice.none) {
              expect(calls, isEmpty);
              expect(content.join().trim(), body);
              expect(chunks.last.choices.single.finishReason, 'stop');
            } else if (malformed) {
              expect(calls, isEmpty);
              expect(content, isEmpty);
              expect(chunks.last.choices.single.finishReason, 'stop');
            } else {
              expect(content, isEmpty);
              expect(calls, hasLength(1));
              expect(
                jsonDecode(calls.single.function!.arguments!),
                qwenResultPayload,
              );
              expect(chunks.last.choices.single.finishReason, 'tool_calls');
            }
          },
        );
      }
    }
  }
}
