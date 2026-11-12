import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/models/tools/tool_param.dart';
import 'package:llamadart/src/core/template/handlers/llama_cpp_specialized_handlers.dart';
import 'package:test/test.dart';

void main() {
  test('specialized grammars reject nested duplicate parameter identities', () {
    final ambiguous = ToolDefinition(
      name: 'ambiguous',
      description: 'Ambiguous nested parameters',
      parameters: [
        ToolParam.object(
          'options',
          properties: [ToolParam.string('mode'), ToolParam.boolean('mode')],
        ),
      ],
      handler: (_) async => null,
    );
    final builders = <String? Function(List<ToolDefinition>?)>[
      KimiK3Handler().buildGrammar,
      MinimaxM3Handler().buildGrammar,
      DeepseekV32Handler().buildGrammar,
      MuseGlimmerHandler().buildGrammar,
    ];

    for (final buildGrammar in builders) {
      expect(
        () => buildGrammar([ambiguous]),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            allOf(contains('options'), contains('declared more than once')),
          ),
        ),
      );
    }
  });

  test('specialized any-order optional grammars enforce their state bound', () {
    ToolDefinition optionalTool(int count) => ToolDefinition(
      name: 'bounded',
      description: 'Optional state bound',
      parameters: [
        for (var index = 0; index < count; index++)
          ToolParam.string('option_$index'),
      ],
      handler: (_) async => null,
    );
    final builders = <String? Function(List<ToolDefinition>?)>[
      KimiK3Handler().buildGrammar,
      MinimaxM3Handler().buildGrammar,
      DeepseekV32Handler().buildGrammar,
      MuseGlimmerHandler().buildGrammar,
    ];

    for (final buildGrammar in builders) {
      expect(() => buildGrammar([optionalTool(10)]), returnsNormally);
      expect(
        () => buildGrammar([optionalTool(11)]),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('at most 10 optional properties'),
              contains('tool "bounded" arguments'),
              contains('declares 11'),
            ),
          ),
        ),
      );
    }

    final nested = ToolDefinition(
      name: 'nested_bounded',
      description: 'Nested optional state bound',
      parameters: [
        ToolParam.object(
          'options',
          properties: [
            for (var index = 0; index < 11; index++)
              ToolParam.string('nested_$index'),
          ],
        ),
      ],
      handler: (_) async => null,
    );
    expect(
      () => MinimaxM3Handler().buildGrammar([nested]),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          contains('tool "nested_bounded" arguments.options'),
        ),
      ),
    );
  });
}
