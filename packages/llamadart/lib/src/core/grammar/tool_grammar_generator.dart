import '../models/tools/tool_definition.dart';
import 'json_schema_converter.dart';

/// Result of tool grammar generation.
class ToolGrammarResult {
  /// The GBNF grammar string.
  final String grammar;

  /// Whether grammar should be lazily applied.
  final bool grammarLazy;

  /// Trigger words/patterns that activate grammar constraints.
  final List<String> grammarTriggers;

  /// Creates a [ToolGrammarResult] with the given [grammar] and options.
  const ToolGrammarResult({
    required this.grammar,
    this.grammarLazy = false,
    this.grammarTriggers = const [],
  });
}

/// Controls how tool usage is enforced.
enum ToolChoice {
  /// Model decides whether to use tools (default).
  auto,

  /// Model MUST call a tool.
  required,

  /// Model MUST NOT use tools (grammar not applied).
  none,
}

/// Generates GBNF grammars for tool calling.
///
/// The generated schema intentionally matches llama.cpp's generic tool-call
/// contract:
/// - `{"tool_call": {...}}` for required/single-call output
/// - `{"response": "..."}` alternative when [ToolChoice.auto]
class ToolGrammarGenerator {
  const ToolGrammarGenerator._();

  /// Generate a grammar that constrains output to valid tool calls.
  ///
  /// When [toolChoice] is [ToolChoice.none], returns `null` (no constraint).
  /// When [ToolChoice.required], forces a tool call envelope.
  /// When [ToolChoice.auto], allows either a tool-call envelope or
  /// a textual response envelope.
  static ToolGrammarResult? generate(
    List<ToolDefinition> tools, {
    ToolChoice toolChoice = ToolChoice.auto,
  }) {
    if (tools.isEmpty || toolChoice == ToolChoice.none) {
      return null;
    }

    final schema = _buildGenericToolSchema(tools, toolChoice: toolChoice);
    final grammar = JsonSchemaConverter.convert(schema);
    return ToolGrammarResult(
      grammar: grammar,
      grammarLazy: false,
      grammarTriggers: const [],
    );
  }

  /// Generate a grammar for a single JSON schema (e.g. `response_format`).
  static String generateForSchema(Map<String, dynamic> schema) {
    return JsonSchemaConverter.convert(schema);
  }

  static Map<String, dynamic> _buildGenericToolSchema(
    List<ToolDefinition> tools, {
    required ToolChoice toolChoice,
  }) {
    final toolCallSchemas = tools
        .map(_buildSingleToolCallSchema)
        .toList(growable: false);

    final toolCallItem = toolCallSchemas.length == 1
        ? toolCallSchemas.first
        : <String, dynamic>{'anyOf': toolCallSchemas};

    final toolCallEnvelope = <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{'tool_call': toolCallItem},
      'required': <String>['tool_call'],
    };

    if (toolChoice == ToolChoice.required) {
      return toolCallEnvelope;
    }

    return <String, dynamic>{
      'anyOf': <Map<String, dynamic>>[
        toolCallEnvelope,
        <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'response': <String, dynamic>{'type': 'string'},
          },
          'required': <String>['response'],
        },
      ],
    };
  }

  static Map<String, dynamic> _buildSingleToolCallSchema(ToolDefinition tool) {
    final schema = <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'name': <String, dynamic>{'type': 'string', 'const': tool.name},
        'arguments': tool.toJsonSchema(),
      },
      'required': <String>['name', 'arguments'],
    };

    if (tool.description.isNotEmpty) {
      schema['description'] = tool.description;
    }

    return schema;
  }
}
