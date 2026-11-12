import 'package:genkit/plugin.dart' as genkit;
import 'package:genkit_llamadart/src/integration/genkit/converters/genkit_to_llama.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

void main() {
  final cases = <String, (List<dynamic>?, Object?, String)>{
    'missing parts': (null, {'answer': 42}, '{"answer":42}'),
    'empty parts': ([], 'output', 'output'),
    'no output': (
      [
        {'text': 'one'},
        {'text': 'two'},
      ],
      null,
      'one\ntwo',
    ),
    'output retained separately': (
      [
        {'text': 'one'},
        {'text': 'two'},
      ],
      {'answer': 42},
      'one\ntwo',
    ),
    'empty text': (
      [
        {'text': ''},
      ],
      'output',
      '',
    ),
    'empty text between parts': (
      [
        {'text': 'one'},
        {'text': ''},
        {'text': 'two'},
      ],
      null,
      'one\n\ntwo',
    ),
    'typed parts': (
      [genkit.TextPart(text: 'one'), genkit.TextPart(text: 'two')],
      'one\ntwo',
      'one\ntwo',
    ),
    'text metadata': (
      [
        {
          'text': 'one',
          'metadata': {'label': 'result'},
        },
      ],
      null,
      'one',
    ),
  };
  for (final entry in cases.entries) {
    test('${entry.key} keeps result identity and text for both roles', () {
      for (final role in [genkit.Role.tool, genkit.Role.user]) {
        final response = genkit.ToolResponse(
          ref: 'call-42',
          name: 'lookup',
          content: entry.value.$1,
          output: entry.value.$2,
        );
        final converted =
            toLlamaMessages([
                  genkit.Message(
                    role: role,
                    content: [genkit.ToolResponsePart(toolResponse: response)],
                  ),
                ]).single.parts.single
                as llama.LlamaToolResultContent;
        expect(converted.id, 'call-42');
        expect(converted.name, 'lookup');
        expect(converted.result, entry.value.$3);
        expect(response.output, entry.value.$2);
        expect(response.content, entry.value.$1);
      }
    });
  }

  for (final part in <Object?>[
    {
      'media': {'url': 'data:image/png;base64,AQID'},
    },
    {
      'resource': {'uri': 'private://secret'},
    },
    {
      'data': {'value': 1},
    },
    {'reasoning': 'not a tool result'},
    {
      'text': 'one',
      'media': {'url': 'private://secret'},
    },
    {'text': 42},
    genkit.TextPart(text: 'one', data: {'value': 1}),
    genkit.TextPart(text: 'one', custom: {'value': 1}),
    {},
    null,
    'untyped text',
  ]) {
    test('unsupported or ambiguous result shape is rejected', () {
      expect(
        () => toLlamaMessages([
          genkit.Message(
            role: genkit.Role.tool,
            content: [
              genkit.ToolResponsePart(
                toolResponse: genkit.ToolResponse(
                  name: 'lookup',
                  content: [
                    {'text': 'first'},
                    part,
                  ],
                ),
              ),
            ],
          ),
        ]),
        throwsA(
          isA<genkit.GenkitException>().having(
            (e) => e.status,
            'status',
            genkit.StatusCode.unimplemented,
          ),
        ),
      );
    });
  }
}
