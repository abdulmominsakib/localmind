import 'package:dinja/dinja.dart';

import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/inference/tool_choice.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../template_internal_metadata.dart';
import '../thinking_utils.dart';
import '../tool_call_grammar_utils.dart';
import '../tool_schema_utils.dart';
import '../xml_tool_call_format.dart';

/// Handler for Seed-OSS format.
///
/// Uses `<seed:think>`/`</seed:think>` for reasoning and
/// `<seed:tool_call><function=...>...</function></seed:tool_call>` for tools.
class SeedOssHandler extends ChatTemplateHandler
    implements ToolSchemaAwareChatTemplateHandler {
  @override
  ChatFormat get format => ChatFormat.seedOss;

  @override
  TemplateToolCallSerialization get toolCallSerialization =>
      TemplateToolCallSerialization.normalizeOnly;

  @override
  String get thinkingStartTag => '<seed:think>';

  @override
  String get thinkingEndTag => '</seed:think>';

  @override
  List<String> get additionalStops => [];

  @override
  List<String> get preservedTokens => const [
    '<seed:think>',
    '</seed:think>',
    '<seed:tool_call>',
    '</seed:tool_call>',
    '<function=',
    '</function>',
    '<parameter=',
    '</parameter>',
  ];

  @override
  LlamaChatTemplateResult render({
    required String templateSource,
    required List<LlamaChatMessage> messages,
    required Map<String, String> metadata,
    bool addAssistant = true,
    List<ToolDefinition>? tools,
    bool enableThinking = true,
  }) {
    final template = Template(templateSource);
    var prompt = renderTemplate(
      template,
      metadata: metadata,
      context: {
        'messages': templateMessages(messages, templateSource: templateSource),
        'add_generation_prompt': addAssistant,
        'tools': tools?.map((t) => t.toJson()).toList(),
        'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<s>',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '</s>',
      },
    );

    var thinkingForcedOpen = false;
    var thoughtClosed = false;
    if (isThinkingForcedOpen(prompt, startTag: thinkingStartTag)) {
      if (!enableThinking) {
        prompt = '${prompt.trimRight()}$thinkingEndTag';
        thoughtClosed = true;
      } else {
        thinkingForcedOpen = true;
      }
    }

    final hasTools = tools != null && tools.isNotEmpty;
    final grammar = buildXmlToolCallGrammar(
      tools,
      XmlToolCallFormat.seedOss,
      parallelToolCalls:
          metadata[internalParallelToolCallsMetadataKey] == 'true',
    );
    final rendered = LlamaChatTemplateResult(
      prompt: prompt,
      format: format.index,
      grammar:
          grammar != null &&
              !thinkingForcedOpen &&
              metadata[internalToolChoiceMetadataKey] ==
                  ToolChoice.required.name
          ? _withThoughtAndTextBeforeCalls(grammar)
          : requiredGrammarAfterThought(
              grammar,
              metadata: metadata,
              thinkingForcedOpen: thinkingForcedOpen,
            ),
      grammarLazy: hasTools,
      thinkingForcedOpen: thinkingForcedOpen,
      additionalStops: getStops(
        hasTools: hasTools,
        enableThinking: enableThinking,
      ),
      preservedTokens: hasTools ? preservedTokens : const [],
      grammarTriggers: hasTools
          ? const [GrammarTrigger(type: 0, value: '<seed:tool_call>\n')]
          : const [],
    );
    return withThoughtClosedForThinkingOff(rendered, closed: thoughtClosed);
  }

  /// [grammar] after what llama.cpp's (`cd959bae9`) required-call grammar
  /// lets precede the calls: a thought that starts the reply, then any text
  /// without a scope start.
  static String _withThoughtAndTextBeforeCalls(String grammar) => [
    for (final line in grammar.trimRight().split('\n'))
      line.startsWith('root ::= ')
          ? 'root ::= seed-thought? text-before-calls '
                '(${line.substring('root ::= '.length)})'
          : line,
    'seed-thought ::= [ \\t\\n]* "<seed:think>" seed-thought-text '
        '"</seed:think>"',
    ...ToolCallGrammarUtils.excludingRules('seed-thought-text', [
      '</seed:think>',
    ]),
    ...ToolCallGrammarUtils.excludingRules('text-before-calls', [
      XmlToolCallFormat.seedOss.scopeStart,
    ]),
  ].join('\n');

  @override
  ChatParseResult parse(
    String output, {
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) => parseWithTools(
    output,
    isPartial: isPartial,
    parseToolCalls: parseToolCalls,
    thinkingForcedOpen: thinkingForcedOpen,
  );

  /// Parses Seed-OSS output, keeping as generated the value of each argument
  /// that [tools] declare as a string, as llama.cpp does.
  ///
  /// Other values are read as JSON when they are JSON, and the call's tool and
  /// arguments are not checked against [tools].
  @override
  ChatParseResult parseWithTools(
    String output, {
    List<ToolDefinition>? tools,
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    // As in llama.cpp, a thought the prompt opened is the reply up to the
    // first end tag, verbatim, and one it did not open exists only when the
    // reply starts with the start tag. Later thinking tags are content.
    final reply = trimLeftAsciiSpace(output);
    final thought = thinkingForcedOpen
        ? extractForcedOpenThoughtVerbatim(
            output,
            endTag: thinkingEndTag,
            isPartial: isPartial,
          )
        : reply.startsWith(thinkingStartTag)
        ? extractForcedOpenThoughtVerbatim(
            reply.substring(thinkingStartTag.length),
            endTag: thinkingEndTag,
            isPartial: isPartial,
          )
        : null;
    final body = thought?.content ?? output;
    final stringArguments = {
      for (final tool in tools ?? const <ToolDefinition>[])
        tool.name: {
          for (final MapEntry(:key, :value) in schemaProperties(
            tool.toJsonSchema(),
          ).entries)
            if (schemaResolvesToString(value)) key,
        },
    };
    ChatParseResult parseBody(String text) => parseXmlToolCalls(
      text,
      XmlToolCallFormat.seedOss,
      parseToolCalls: parseToolCalls,
      extractsThought: false,
      stringArguments: stringArguments,
    );
    final ended = isPartial || !parseToolCalls
        ? (text: body, endAdded: false)
        : _withLastScopeEnded(body);
    var parsed = parseBody(ended.text);
    var content = parsed.content;
    // When the calls still fail, or an earlier call leaves the added scope end
    // in content, the end would show in the reply.
    if (ended.endAdded) {
      final addedEndShows = content.trimRight().endsWith(
        XmlToolCallFormat.seedOss.scopeEnd,
      );
      if (parsed.toolCalls.isEmpty) {
        parsed = parseBody(body);
        content = parsed.content;
      } else if (addedEndShows &&
          parseBody(body).toolCalls.length == parsed.toolCalls.length) {
        content = parseBody(body).content;
      }
    }
    return ChatParseResult(
      content: content.trim(),
      reasoningContent: thought?.reasoning,
      toolCalls: parsed.toolCalls,
    );
  }

  /// [reply] as llama.cpp reads a finished one that ends inside its last
  /// scope: with the scope end that a complete call is missing, and without
  /// a scope that ends before its call does.
  ///
  /// A last scope whose text could not start a call is left as it is.
  /// [endAdded] tells whether the scope end was added.
  static ({String text, bool endAdded}) _withLastScopeEnded(String reply) {
    const format = XmlToolCallFormat.seedOss;
    final unchanged = (text: reply, endAdded: false);
    final start = reply.lastIndexOf(format.scopeStart);
    if (start < 0 || reply.contains(format.scopeEnd, start)) return unchanged;
    final callEnd = _unendedCallEnd(reply, start + format.scopeStart.length);
    if (callEnd == null) return unchanged;
    if (callEnd < 0) return (text: reply.substring(0, start), endAdded: false);
    final rest = reply.substring(callEnd).trimLeft();
    return format.scopeEnd.startsWith(rest)
        ? (
            text: '${reply.substring(0, callEnd)}${format.scopeEnd}',
            endAdded: true,
          )
        : unchanged;
  }

  /// Where the call that the scope opening before [from] in [reply] holds
  /// ends, after `</function>` and its line break; -1 when [reply] ends
  /// before it does; null when the text cannot be such a call.
  static int? _unendedCallEnd(String reply, int from) {
    const format = XmlToolCallFormat.seedOss;
    bool endsIn(int at, String token) =>
        reply.length - at < token.length &&
        token.startsWith(reply.substring(at));
    var pos = _skipSpace(reply, from);
    if (pos == reply.length || endsIn(pos, format.toolStart)) return -1;
    if (!reply.startsWith(format.toolStart, pos)) return null;
    final nameEnd = reply.indexOf(format.toolSep, pos);
    if (nameEnd < 0) return -1;
    pos = nameEnd + format.toolSep.length;
    while (true) {
      pos = _skipSpace(reply, pos);
      if (pos == reply.length ||
          endsIn(pos, format.keyStart) ||
          endsIn(pos, format.toolEnd)) {
        return -1;
      }
      if (reply.startsWith(format.toolEnd, pos)) {
        pos += format.toolEnd.length;
        if (pos == reply.length) return -1;
        return reply.codeUnitAt(pos) == 0x0A ? pos + 1 : null;
      }
      if (!reply.startsWith(format.keyStart, pos)) return null;
      final valueEnd = reply.indexOf(format.valEnd, pos);
      if (valueEnd < 0) return -1;
      pos = valueEnd + format.valEnd.length;
    }
  }

  static int _skipSpace(String text, int from) {
    var pos = from;
    while (pos < text.length && ' \t\n\r'.contains(text[pos])) {
      pos++;
    }
    return pos;
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return buildXmlToolCallGrammar(
      tools,
      XmlToolCallFormat.seedOss,
      parallelToolCalls: false,
    );
  }
}
