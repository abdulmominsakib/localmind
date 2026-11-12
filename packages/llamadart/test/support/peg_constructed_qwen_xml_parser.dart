import 'package:llamadart/src/core/models/tools/tool_definition.dart';
import 'package:llamadart/src/core/template/peg_parser_builder.dart';
import 'package:llamadart/src/core/template/tool_schema_utils.dart';

/// A `pegConstructed` parser for one Qwen3-Coder XML call to [tools], after a
/// thought the prompt opened when [thinkingForcedOpen], as llamadart built
/// one for Nemotron-3-Nano before it took llama.cpp's Qwen3-Coder parser.
///
/// No handler emits such a parser now, but a template result may carry one.
String pegConstructedQwenXmlParser(
  List<ToolDefinition> tools, {
  required bool thinkingForcedOpen,
}) {
  final p = ChatPegConstructedBuilder();
  final reasoning = thinkingForcedOpen
      ? p.reasoning(p.until('</think>')) + (p.literal('</think>') | p.end())
      : p.eps();

  PegParser toolChoice = p.choice(<PegParser>[]);
  for (final tool in tools) {
    final schema = tool.toJsonSchema();
    final requiredNames = schemaRequired(schema);
    PegParser args = p.eps();
    for (final MapEntry(key: name, value: property) in schemaProperties(
      schema,
    ).entries) {
      final ruleName = 'tool-${tool.name}-arg-$name';
      final value = schemaResolvesToString(property)
          ? p.toolArgStringValue(
                  p.untilOneOf(<String>[
                    '\n</parameter>',
                    '\n<parameter=',
                    '\n</function>',
                  ]),
                ) +
                p.literal('\n')
          : p.toolArgJsonValue(
              p.schema(p.json(), '$ruleName-schema', property),
            );
      final argument = p.rule(
        ruleName,
        p.toolArgOpen(
              p.literal('<parameter=') +
                  p.toolArgName(p.literal(name)) +
                  p.literal('>\n'),
            ) +
            value +
            p.optional(p.toolArgClose(p.literal('</parameter>\n'))),
      );
      args += p.repeat(argument, requiredNames.contains(name) ? 1 : 0, 1);
    }
    toolChoice |= p.rule(
      'tool-${tool.name}',
      p.toolOpen(
            p.literal('<function=') +
                p.toolName(p.literal(tool.name)) +
                p.literal('>\n'),
          ) +
          args +
          p.toolClose(p.literal('</function>\n')),
    );
  }

  final toolCall = p.rule(
    'tool-call',
    p.literal('<tool_call>\n') +
        toolChoice +
        p.literal('</tool_call>') +
        p.space(),
  );
  p.setRoot(
    reasoning +
        p.content(p.until('<tool_call>')) +
        p.triggerRule('tool-call-root', p.repeat(toolCall, 0, 1)),
  );
  return p.save();
}
