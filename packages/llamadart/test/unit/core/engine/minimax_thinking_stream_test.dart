import 'package:llamadart/src/core/engine/chat_completion_stream_parser.dart';
import 'package:llamadart/src/core/models/chat/completion_chunk.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:test/test.dart';

const _namespace = ']<]minimax[>[';
const _end = '</mm:think>';
const _envelope =
    '$_namespace<tool_call>$_namespace<invoke name="weather">'
    '$_namespace<city>Seoul$_namespace</city>'
    '$_namespace</invoke>$_namespace</tool_call>';
final _tool = ToolDefinition(
  name: 'weather',
  description: 'Get weather',
  handler: (params) async => 'sunny',
  parameters: [ToolParam.string('city', description: 'City', required: true)],
);

Future<List<LlamaCompletionChunk>> _parse(
  List<String> tokens, {
  bool forcedOpen = true,
  bool enableThinking = true,
  ToolChoice toolChoice = ToolChoice.required,
}) {
  final template = ChatTemplateEngine.render(
    // Synthetic routing fixture, not evidence of real MiniMax emissions.
    templateSource:
        '{# $_namespace<tool_call><invoke name= #}'
        '${forcedOpen ? '<mm:think>' : ''}',
    messages: const [],
    metadata: const {},
    tools: [_tool],
    toolChoice: toolChoice,
    enableThinking: true,
  );
  expect(template.format, ChatFormat.minimaxM3.index);
  expect(template.thinkingForcedOpen, forcedOpen);
  return ChatCompletionStreamParser.parse(
    tokenStream: Stream.fromIterable(tokens),
    templateResult: template,
    parseToolCallsEnabled: toolChoice != ToolChoice.none,
    enableThinking: enableThinking,
    modelName: 'synthetic-minimax-m3',
    completionId: 'partial-thinking',
    tools: [_tool],
  ).toList();
}

String _thinking(List<LlamaCompletionChunk> chunks) =>
    chunks.map((chunk) => chunk.choices.single.delta.thinking ?? '').join();
String _content(List<LlamaCompletionChunk> chunks) =>
    chunks.map((chunk) => chunk.choices.single.delta.content ?? '').join();

void main() {
  group('MiniMax M3 thinking stream', () {
    for (final forcedOpen in [true, false]) {
      for (final toolChoice in [ToolChoice.auto, ToolChoice.required]) {
        final prefix = '${forcedOpen ? '' : '<mm:think>'}reason';
        final output = '$prefix$_end$_envelope';
        final partitions = <String, List<String>>{
          'whole': [output],
          'characters': output.split(''),
          for (var split = 1; split < _end.length; split++)
            'closing split $split': [
              '$prefix${_end.substring(0, split)}',
              '${_end.substring(split)}$_envelope',
            ],
        };
        for (final partition in partitions.entries) {
          test(
            'forced=$forcedOpen choice=$toolChoice ${partition.key}',
            () async {
              final chunks = await _parse(
                partition.value,
                forcedOpen: forcedOpen,
                toolChoice: toolChoice,
              );
              expect(_thinking(chunks), 'reason');
              expect(_content(chunks), isEmpty);
              final call = chunks
                  .expand((c) => c.choices.single.delta.toolCalls ?? const [])
                  .single;
              expect(call.function?.name, 'weather');
              expect(call.function?.arguments, '{"city":"Seoul"}');
              expect(chunks.last.choices.single.finishReason, 'tool_calls');
            },
          );
        }
      }
    }

    test(
      'malformed final tool envelope rolls back without reasoning leakage',
      () async {
        final malformed = _envelope.replaceFirst(
          'name="weather"',
          'name="unknown"',
        );
        final chunks = await _parse('reason$_end$malformed'.split(''));
        expect(_thinking(chunks), 'reason');
        expect(_content(chunks), malformed);
        expect(
          chunks.expand((c) => c.choices.single.delta.toolCalls ?? const []),
          isEmpty,
        );
        expect(chunks.last.choices.single.finishReason, 'stop');
      },
    );

    for (final suffix in ['<', '</mm:th', '</mm:thX', '<mm:thX']) {
      test(
        'preserves genuine reasoning suffix $suffix at EOF and before close',
        () async {
          for (final ending in ['', '$_end$_envelope']) {
            final output = 'reason$suffix$ending';
            for (final tokens in [
              [output],
              output.split(''),
            ]) {
              final chunks = await _parse(tokens);
              expect(_thinking(chunks), 'reason$suffix');
              expect(_content(chunks), isEmpty);
            }
          }
        },
      );
    }

    test(
      'disabled thinking still suppresses split delimiters and emits tools',
      () async {
        final chunks = await _parse(
          'reason$_end$_envelope'.split(''),
          enableThinking: false,
        );
        expect(_thinking(chunks), isEmpty);
        expect(_content(chunks), isEmpty);
        expect(chunks.last.choices.single.finishReason, 'tool_calls');
      },
    );

    test(
      'tool choice none preserves ordinary answer after split thinking',
      () async {
        final chunks = await _parse(
          'reason${_end}answer'.split(''),
          toolChoice: ToolChoice.none,
        );
        expect(_thinking(chunks), 'reason');
        expect(_content(chunks), 'answer');
        expect(chunks.last.choices.single.finishReason, 'stop');
      },
    );

    for (final output in [
      '$_end$_end<mm:think>',
      '$_end<mm:think>a$_end$_envelope',
    ]) {
      test('a forced-open reply streams the same split by character: '
          '$output', () async {
        final whole = await _parse([output], toolChoice: ToolChoice.auto);
        final split = await _parse(
          output.split(''),
          toolChoice: ToolChoice.auto,
        );
        expect(_thinking(split), _thinking(whole));
        expect(_content(split), _content(whole));
        expect(
          split.expand((c) => c.choices.single.delta.toolCalls ?? const []),
          hasLength(
            whole
                .expand((c) => c.choices.single.delta.toolCalls ?? const [])
                .length,
          ),
        );
      });
    }

    // Results recorded from llama.cpp cd959bae9 for a forced-open thought
    // (test/fixtures/minimax_m3_forced_open_upstream.json).
    for (final toolChoice in [ToolChoice.none, ToolChoice.auto]) {
      for (final shape in const [
        ('$_end$_end<mm:think>', '', '$_end<mm:think>'),
        ('a$_end$_end<mm:think>b', 'a', '$_end<mm:think>b'),
        ('a$_end<mm:think>b$_end', 'a', '<mm:think>b$_end'),
      ]) {
        test('a forced-open reply ${shape.$1} streams as llama.cpp parses it '
            'at every split ($toolChoice)', () async {
          final output = shape.$1;
          final partitions = [
            [output],
            output.split(''),
            for (var at = 1; at < output.length; at++)
              [output.substring(0, at), output.substring(at)],
          ];
          for (final tokens in partitions) {
            final chunks = await _parse(tokens, toolChoice: toolChoice);
            expect(_thinking(chunks), shape.$2, reason: '$tokens');
            expect(_content(chunks), shape.$3, reason: '$tokens');
          }
        });
      }
    }

    // Only a forced-open prompt keeps later thinking tags as content when the
    // call is decided, so a call envelope followed by an end tag and JSON is
    // not suppressed as an envelope after an unforced prompt.
    test(
      'an unforced reply keeps text after a call envelope at every split',
      () async {
        const json = '{"tool_calls":[]}';
        const output = '$_envelope$_end$json';
        final partitions = [
          [output],
          output.split(''),
          for (var at = 1; at < output.length; at++)
            [output.substring(0, at), output.substring(at)],
        ];
        for (final tokens in partitions) {
          final chunks = await _parse(tokens, forcedOpen: false);
          expect(_thinking(chunks), '', reason: '$tokens');
          expect(_content(chunks), '$_end$json', reason: '$tokens');
        }
      },
    );

    for (final toolChoice in [ToolChoice.auto, ToolChoice.required]) {
      test('an empty leading thought leaves a later unfinished thought as '
          'content before a call ($toolChoice)', () async {
        final output = '<mm:think>$_end<mm:think>unfinished$_envelope';
        for (final tokens in [
          [output],
          output.split(''),
        ]) {
          final chunks = await _parse(
            tokens,
            forcedOpen: false,
            toolChoice: toolChoice,
          );
          expect(_thinking(chunks), isEmpty);
          expect(_content(chunks), '<mm:think>unfinished');
          final call = chunks
              .expand((c) => c.choices.single.delta.toolCalls ?? const [])
              .single;
          expect(call.function?.arguments, '{"city":"Seoul"}');
          expect(chunks.last.choices.single.finishReason, 'tool_calls');
        }
      });
    }
  });
}
