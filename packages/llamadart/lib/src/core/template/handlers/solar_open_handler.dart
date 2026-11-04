import 'package:dinja/dinja.dart';

import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/inference/tool_choice.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../peg_parser_builder.dart';
import '../template_internal_metadata.dart';
import '../thinking_utils.dart';

/// Handler for Solar Open format.
///
/// Solar Open encodes reasoning in `<|think|> ...` channel blocks.
class SolarOpenHandler extends ChatTemplateHandler {
  static const List<String> _solarPreservedTokens = <String>[
    '<|think|>',
    '<|content|>',
    '<|begin|>',
    '<|end|>',
    '<|tool_calls|>',
    '<|tool_call:begin|>',
    '<|tool_call:end|>',
    '<|tool_call:name|>',
    '<|tool_call:args|>',
  ];

  @override
  ChatFormat get format => ChatFormat.solarOpen;

  @override
  String get thinkingStartTag => '<|think|>';

  @override
  String get thinkingEndTag => '<|end|><|begin|>assistant<|content|>';

  @override
  List<String> get additionalStops => [];

  @override
  List<String> get preservedTokens => _solarPreservedTokens;

  @override
  LlamaChatTemplateResult render({
    required String templateSource,
    required List<LlamaChatMessage> messages,
    required Map<String, String> metadata,
    bool addAssistant = true,
    List<ToolDefinition>? tools,
    bool enableThinking = true,
  }) {
    final renderedMessages = messages.map((m) {
      final json = m.toJson();
      final reasoning = json['reasoning_content'];
      if (reasoning is String && reasoning.isNotEmpty) {
        json['reasoning'] = reasoning;
        json.remove('reasoning_content');
      }
      return json;
    }).toList();

    final template = Template(templateSource);
    var prompt = renderTemplate(
      template,
      metadata: metadata,
      context: {
        'messages': renderedMessages,
        'add_generation_prompt': addAssistant,
        'tools': tools?.map((t) => t.toJson()).toList(),
        'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<s>',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '</s>',
      },
    );

    var thinkingForcedOpen = false;
    if (isThinkingForcedOpen(prompt, startTag: thinkingStartTag)) {
      if (!enableThinking) {
        prompt = '${prompt.trimRight()}$thinkingEndTag';
      } else {
        thinkingForcedOpen = true;
      }
    }

    final hasTools = tools != null && tools.isNotEmpty;
    final toolChoice = metadata[internalToolChoiceMetadataKey];
    final toolChoiceNone = toolChoice == ToolChoice.none.name;
    final toolChoiceRequired = toolChoice == ToolChoice.required.name;
    final parallelToolCalls =
        metadata[internalParallelToolCallsMetadataKey] == 'true';
    final allowToolCalls = hasTools && !toolChoiceNone;
    final parser = _buildParser(
      tools,
      allowToolCalls: allowToolCalls,
      toolCallsRequired: toolChoiceRequired,
      parallelToolCalls: parallelToolCalls,
    );
    return LlamaChatTemplateResult(
      prompt: prompt,
      format: format.index,
      grammar: buildGrammar(tools),
      grammarLazy: allowToolCalls && !toolChoiceRequired,
      thinkingForcedOpen: thinkingForcedOpen,
      additionalStops: getStops(
        hasTools: hasTools,
        enableThinking: enableThinking,
      ),
      preservedTokens: preservedTokens,
      grammarTriggers: allowToolCalls
          ? const [GrammarTrigger(type: 0, value: '<|tool_calls|>')]
          : const [],
      parser: parser,
    );
  }

  String _buildParser(
    List<ToolDefinition>? tools, {
    required bool allowToolCalls,
    required bool toolCallsRequired,
    required bool parallelToolCalls,
  }) {
    final p = ChatPegNativeBuilder();
    final hasTools = tools != null && tools.isNotEmpty;

    final litThink = p.atomic(p.literal('<|think|>'));
    final litAssistantBegin = p.atomic(p.literal('<|begin|>assistant'));
    final litContent = p.atomic(p.literal('<|content|>'));
    final litEnd = p.atomic(p.literal('<|end|>'));

    final parserUntilEnd = p.until('<|end|>');
    final parserReasoning = p.rule(
      'reasoning',
      litThink + p.reasoning(parserUntilEnd),
    );
    final parserContent = p.rule(
      'content',
      litContent + p.content(parserUntilEnd),
    );

    PegParser wrapChoice(List<PegParser> items) {
      final choice = p.choice(items);
      return choice + p.zeroOrMore(litEnd + litAssistantBegin + choice);
    }

    PegParser wrapSeq(List<PegParser> items) {
      var seq = p.sequence(<PegParser>[]);
      for (var i = 0; i < items.length; i++) {
        if (i == 0) {
          seq += items[i];
          continue;
        }
        seq += litEnd + litAssistantBegin + items[i];
      }
      return seq;
    }

    if (hasTools && allowToolCalls) {
      final litToolCallBegin = p.literal('<|tool_call:begin|>');
      final litToolCallName = p.literal('<|tool_call:name|>');
      final litToolCallArgs = p.literal('<|tool_call:args|>');
      final litToolCallEnd = p.literal('<|tool_call:end|>');

      var parserToolCall = p.choice(<PegParser>[]);
      for (final tool in tools) {
        final name = tool.name;
        final schema = tool.toJsonSchema();
        parserToolCall |= p.rule(
          'tool-$name',
          p.atomic(p.toolName(p.literal(name)) + litToolCallArgs) +
              p.toolArgs(p.schema(p.json(), 'tool-$name-schema', schema)),
        );
      }

      final parserToolCalls = p.triggerRule(
        'tool-calls',
        p.atomic(p.literal('<|tool_calls|>')) +
            p.repeat(
              p.toolOpen(
                    litToolCallBegin +
                        p.toolId(
                          p.chars('[a-zA-Z0-9_-]', minCount: 1, maxCount: -1),
                        ) +
                        litToolCallName +
                        p.peek(
                          p.chars('[^<]', minCount: 1, maxCount: -1) +
                              litToolCallArgs,
                        ),
                  ) +
                  parserToolCall +
                  p.toolClose(litToolCallEnd),
              1,
              parallelToolCalls ? -1 : 1,
            ),
      );

      if (toolCallsRequired) {
        p.setRoot(
          p.choice(<PegParser>[
            wrapSeq(<PegParser>[
              parserReasoning,
              parserContent,
              parserToolCalls,
            ]),
            wrapSeq(<PegParser>[parserReasoning, parserToolCalls]),
            wrapSeq(<PegParser>[parserContent, parserToolCalls]),
            wrapSeq(<PegParser>[parserToolCalls]),
          ]),
        );
      } else {
        p.setRoot(
          wrapChoice(<PegParser>[
            parserReasoning,
            parserContent,
            parserToolCalls,
          ]),
        );
      }
      return p.save();
    }

    p.setRoot(wrapChoice(<PegParser>[parserReasoning, parserContent]));
    return p.save();
  }

  @override
  ChatParseResult parse(
    String output, {
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    final thinking = extractThinking(
      output,
      thinkingForcedOpen: thinkingForcedOpen,
      startTag: thinkingStartTag,
      endTag: thinkingEndTag,
    );

    return ChatParseResult(
      content: thinking.content.trim(),
      reasoningContent: thinking.reasoning,
    );
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return null;
  }
}
