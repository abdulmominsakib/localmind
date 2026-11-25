import 'package:dinja/dinja.dart';

import '../../grammar/json_schema_converter.dart';

import '../../models/chat/chat_message.dart';
import '../../models/chat/chat_template_result.dart';
import '../../models/inference/tool_choice.dart';
import '../../models/tools/tool_definition.dart';
import '../chat_format.dart';
import '../chat_parse_result.dart';
import '../chat_template_handler.dart';
import '../tool_call_grammar_utils.dart';
import 'specialized_handler_utils.dart';
import 'xml_argument_grammar.dart';
import '../template_internal_metadata.dart';
import '../thinking_utils.dart';
import '../tool_schema_utils.dart';
import '../xml_tool_call_format.dart';

/// Handler for Qwen Coder and Qwen3.6 XML tool-call formats.
///
/// Uses `<tool_call><function=...><parameter=...>` envelopes.
class Qwen3CoderXmlHandler extends ChatTemplateHandler
    implements ToolSchemaAwareChatTemplateHandler {
  static const List<String> _qwenPreservedTokens = <String>[
    '<think>',
    '</think>',
    '<tool_call>',
    '</tool_call>',
    '<function=',
    '</function>',
    '<parameter=',
    '</parameter>',
  ];

  @override
  ChatFormat get format => ChatFormat.qwen3CoderXml;

  @override
  TemplateToolCallSerialization get toolCallSerialization =>
      TemplateToolCallSerialization.normalizeOnly;

  @override
  List<String> get additionalStops => ['<|im_end|>', '</s>'];

  @override
  List<String> get preservedTokens => _qwenPreservedTokens;

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
        'enable_thinking': enableThinking,
        'bos_token': metadata['tokenizer.ggml.bos_token'] ?? '<|im_start|>',
        'eos_token': metadata['tokenizer.ggml.eos_token'] ?? '<|im_end|>',
      },
    );

    final toolChoice = metadata[internalToolChoiceMetadataKey];
    final parallelToolCalls =
        metadata[internalParallelToolCallsMetadataKey] == 'true';
    final toolChoiceRequired = toolChoice == ToolChoice.required.name;
    // llama.cpp takes no thought from a reply to a template without one, and
    // its first call may then leave out `<tool_call>`, as Qwen3-Coder does.
    // llamadart takes such a call only for a required call, so that another
    // reply may write a declared `<function=name>` as text: llama.cpp ends the
    // content there and its lazy grammar starts there.
    final templateHasThought = templateSource.contains('<think>');
    final thinkingForcedClosed =
        isThinkingForcedClosed(prompt) || !templateHasThought;
    var thinkingForcedOpen = false;
    var thoughtClosed = false;
    if (isThinkingForcedOpen(prompt, startTag: '<think>')) {
      if (!enableThinking) {
        prompt = '${prompt.trimRight()}</think>\n';
        thoughtClosed = true;
      } else {
        thinkingForcedOpen = true;
      }
    }

    final hasTools = tools != null && tools.isNotEmpty;
    final bareFirstCall = hasTools && toolChoiceRequired && !templateHasThought;
    final rendered = LlamaChatTemplateResult(
      prompt: prompt,
      format: format.index,
      grammar: _callGrammar(
        tools,
        parallelToolCalls: parallelToolCalls,
        textBeforeCalls: toolChoiceRequired,
        bareFirstCall: bareFirstCall,
      ),
      grammarLazy: hasTools,
      thinkingForcedOpen: thinkingForcedOpen,
      additionalStops: getStops(
        hasTools: hasTools,
        enableThinking: enableThinking,
      ),
      preservedTokens: preservedTokens,
      grammarTriggers: hasTools
          ? const [GrammarTrigger(type: 0, value: '<tool_call>')]
          : const [],
    );
    return withBareFirstCall(
      withSingleToolCall(
        withThoughtClosedForThinkingOff(
          withThinkingForcedClosed(rendered, closed: thinkingForcedClosed),
          closed: thoughtClosed,
        ),
        single: hasTools && !parallelToolCalls,
      ),
      bare: bareFirstCall,
    );
  }

  /// llama.cpp's Qwen3-Coder call grammar for [tools].
  ///
  /// Each call is in its own `<tool_call>` scope, only one without
  /// [parallelToolCalls], and framed by line breaks as the parser reads it:
  /// the required arguments first, in any order up to six of them, then the
  /// optional ones, in any order and possibly repeated. A value that may be a
  /// string is any text up to the first `\n</parameter>\n`; any other is
  /// JSON for its schema. With [textBeforeCalls], text without a call opening
  /// precedes the calls, and with [bareFirstCall], the first call may leave
  /// out `<tool_call>\n` and a declared tool's `<function=…>` is a call
  /// opening.
  static String? _callGrammar(
    List<ToolDefinition>? tools, {
    required bool parallelToolCalls,
    bool textBeforeCalls = false,
    bool bareFirstCall = false,
  }) {
    if (tools == null || tools.isEmpty) {
      return null;
    }
    const format = XmlToolCallFormat.qwen3Coder;
    const valueEnd = '\n</parameter>\n';
    final literal = ToolCallGrammarUtils.literal;
    final converter = JsonSchemaConverter();
    final rules = <String>[];
    final valueEnds = ValueEndRules(converter);
    String? stringValue;
    final toolRules = <String>[];
    for (var toolIndex = 0; toolIndex < tools.length; toolIndex++) {
      final tool = tools[toolIndex];
      final schema = tool.toJsonSchema();
      converter.resolveRefs(schema, schema);
      final requiredNames = schemaRequired(schema);
      final requiredRules = <String>[];
      final optionalRules = <String>[];
      var argumentIndex = 0;
      for (final MapEntry(:key, :value) in schemaProperties(schema).entries) {
        final argumentRule = 'tool-$toolIndex-arg-${argumentIndex++}';
        final valueRule = mayBeString(value)
            ? stringValue ??= addThroughRules(rules, 'xml-arg-string', valueEnd)
            : '${valueEnds.visit(value, '$argumentRule-schema')} '
                  '${literal(valueEnd)}';
        rules.add(
          '$argumentRule ::= ${literal('<parameter=$key>\n')} $valueRule',
        );
        (requiredNames.contains(key) ? requiredRules : optionalRules).add(
          argumentRule,
        );
      }
      final arguments = [
        if (requiredRules.isNotEmpty)
          permutedArguments(rules, 'tool-$toolIndex-args', requiredRules),
        if (optionalRules.isNotEmpty) '(${optionalRules.join(' | ')})*',
      ];
      final toolRule = 'tool-$toolIndex';
      rules.add(
        '$toolRule ::= ${literal('<function=${tool.name}>\n')} '
        '${arguments.isEmpty ? '' : '${arguments.join(' ')} '}'
        '${literal('</function>\n')}',
      );
      toolRules.add(toolRule);
    }

    final body =
        '(${toolRules.join(' | ')}) ${literal(format.scopeEnd)} tool-call-space';
    final scopeStart = literal('${format.scopeStart}\n');
    final firstCall = bareFirstCall ? 'tool-call-first' : 'tool-call';
    final buffer = StringBuffer()
      ..writeln(
        'root ::= ${textBeforeCalls ? 'text-before-calls ' : ''}$firstCall'
        '${parallelToolCalls ? ' tool-call*' : ''}',
      )
      ..writeln('tool-call ::= $scopeStart $body');
    if (bareFirstCall) {
      buffer.writeln('tool-call-first ::= $scopeStart? $body');
    }
    if (textBeforeCalls) {
      ToolCallGrammarUtils.excludingRules('text-before-calls', [
        format.scopeStart,
        if (bareFirstCall)
          for (final tool in tools) format.bareCallOpening(tool.name),
      ]).forEach(buffer.writeln);
    }
    buffer.writeln(r'tool-call-space ::= | " " | "\n"{1,2} [ \t]{0,20}');
    rules.forEach(buffer.writeln);
    valueEnds.writeTo(buffer);
    return buffer.toString();
  }

  @override
  ChatParseResult parse(
    String output, {
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
  }) {
    return parseWithTools(
      output,
      isPartial: isPartial,
      parseToolCalls: parseToolCalls,
      thinkingForcedOpen: thinkingForcedOpen,
    );
  }

  /// Parses Qwen XML using declared tool schemas when [tools] is supplied.
  ///
  /// As in llama.cpp, the content ends at the first `<tool_call>`, the calls
  /// are those of the valid scopes that follow it, only the first with
  /// [singleToolCall], and the rest of the reply is dropped, so an invalid
  /// call never becomes an executable tool delta. With [thoughtTagsAreText],
  /// all of [output] is content and tool calls. With [bareFirstCall], a
  /// declared tool's `<function=…>` also ends the content and starts the
  /// first call, as `<tool_call>` would.
  @override
  ChatParseResult parseWithTools(
    String output, {
    List<ToolDefinition>? tools,
    bool isPartial = false,
    bool parseToolCalls = true,
    bool thinkingForcedOpen = false,
    bool thoughtTagsAreText = false,
    bool singleToolCall = false,
    bool bareFirstCall = false,
  }) {
    final result = parseXmlToolCalls(
      bareFirstCall && parseToolCalls && tools != null
          ? _withFirstScopeStart(output, tools)
          : output,
      XmlToolCallFormat.qwen3Coder,
      schemas: tools == null ? null : toolSchemas(tools),
      isPartial: isPartial,
      parseToolCalls: parseToolCalls,
      thinkingForcedOpen: thinkingForcedOpen,
      extractsThought: !thoughtTagsAreText,
      // llama.cpp (`7fe450e1`) keeps escapes in Qwen3.5 reasoning, and
      // (`620d2225`) a forced-open thought as generated.
      unescapeReasoning: false,
      verbatimForcedThought: true,
      endsAtLastCall: true,
      maxToolCalls: singleToolCall ? 1 : null,
    );
    return ChatParseResult(
      content: result.content.trim(),
      reasoningContent: result.reasoningContent,
      toolCalls: result.toolCalls,
    );
  }

  /// [output] with `<tool_call>\n` before its first call opening when that is
  /// a declared tool's `<function=…>`.
  static String _withFirstScopeStart(
    String output,
    List<ToolDefinition> tools,
  ) {
    const format = XmlToolCallFormat.qwen3Coder;
    var first = output.indexOf(format.scopeStart);
    var bare = false;
    for (final tool in tools) {
      final index = output.indexOf(format.bareCallOpening(tool.name));
      if (index >= 0 && (first < 0 || index < first)) {
        first = index;
        bare = true;
      }
    }
    return bare
        ? '${output.substring(0, first)}${format.scopeStart}\n'
              '${output.substring(first)}'
        : output;
  }

  @override
  String? buildGrammar(List<ToolDefinition>? tools) {
    return _callGrammar(tools, parallelToolCalls: true);
  }
}
