import '../grammar/json_schema_converter.dart';
import '../models/tools/tool_definition.dart';

/// Utilities for building tool-call grammars from [ToolDefinition] schemas.
class ToolCallGrammarUtils {
  const ToolCallGrammarUtils._();

  /// Escapes [value] as a grammar string literal.
  static String literal(String value) => _literal(value);

  /// Builds a grammar for an array of tool calls and wraps it with literals.
  static String? buildWrappedArrayGrammar({
    required List<ToolDefinition>? tools,
    required String prefix,
    required String suffix,
    String nameKey = 'name',
    String argumentsKey = 'arguments',
    String? idKey,
    String? idPattern,
    bool allowParallelToolCalls = true,
  }) {
    if (tools == null || tools.isEmpty) {
      return null;
    }

    final schema = _buildToolArraySchema(
      tools,
      nameKey: nameKey,
      argumentsKey: argumentsKey,
      idKey: idKey,
      idPattern: idPattern,
      allowParallelToolCalls: allowParallelToolCalls,
    );

    final grammar = JsonSchemaConverter.convert(schema);
    return wrapRootGrammar(grammar, prefix: prefix, suffix: suffix);
  }

  /// Builds a grammar for a single tool call object and wraps it.
  static String? buildWrappedObjectGrammar({
    required List<ToolDefinition>? tools,
    required String prefix,
    required String suffix,
    String nameKey = 'name',
    String argumentsKey = 'arguments',
    String? idKey,
    String? idPattern,
  }) {
    if (tools == null || tools.isEmpty) {
      return null;
    }

    final itemSchemas = tools
        .map(
          (tool) => _buildToolObjectSchema(
            tool,
            nameKey: nameKey,
            argumentsKey: argumentsKey,
            idKey: idKey,
            idPattern: idPattern,
          ),
        )
        .toList(growable: false);

    final schema = itemSchemas.length == 1
        ? itemSchemas.first
        : <String, dynamic>{'anyOf': itemSchemas};
    final grammar = JsonSchemaConverter.convert(schema);
    return wrapRootGrammar(grammar, prefix: prefix, suffix: suffix);
  }

  /// Rewrites the grammar `root` rule with wrapper literals.
  static String wrapRootGrammar(
    String grammar, {
    String prefix = '',
    String suffix = '',
  }) {
    final lines = grammar.trimRight().split('\n');
    final rootIndex = lines.indexWhere((line) => line.startsWith('root ::= '));
    if (rootIndex == -1) {
      return grammar;
    }

    final rootExpr = lines[rootIndex].substring('root ::= '.length).trim();
    final prefixExpr = prefix.isEmpty ? '' : '${literal(prefix)} ';
    final suffixExpr = suffix.isEmpty ? '' : ' ${literal(suffix)}';
    lines[rootIndex] = 'root ::= $prefixExpr$rootExpr$suffixExpr';

    return '${lines.join('\n')}\n';
  }

  static Map<String, dynamic> _buildToolArraySchema(
    List<ToolDefinition> tools, {
    required String nameKey,
    required String argumentsKey,
    String? idKey,
    String? idPattern,
    required bool allowParallelToolCalls,
  }) {
    final itemSchemas = tools
        .map(
          (tool) => _buildToolObjectSchema(
            tool,
            nameKey: nameKey,
            argumentsKey: argumentsKey,
            idKey: idKey,
            idPattern: idPattern,
          ),
        )
        .toList(growable: false);

    final schema = <String, dynamic>{
      'type': 'array',
      'items': itemSchemas.length == 1
          ? itemSchemas.first
          : <String, dynamic>{'anyOf': itemSchemas},
      'minItems': 1,
    };

    if (!allowParallelToolCalls) {
      schema['maxItems'] = 1;
    }

    return schema;
  }

  static Map<String, dynamic> _buildToolObjectSchema(
    ToolDefinition tool, {
    required String nameKey,
    required String argumentsKey,
    String? idKey,
    String? idPattern,
  }) {
    final properties = <String, dynamic>{
      nameKey: <String, dynamic>{'type': 'string', 'const': tool.name},
      argumentsKey: tool.toJsonSchema(),
    };
    final required = <String>[nameKey, argumentsKey];

    if (idKey != null) {
      properties[idKey] = <String, dynamic>{
        'type': 'string',
        if (idPattern != null && idPattern.isNotEmpty) 'pattern': idPattern,
      };
      required.add(idKey);
    }

    return <String, dynamic>{
      'type': 'object',
      'properties': properties,
      'required': required,
    };
  }

  static String _literal(String value) {
    final escaped = value
        .replaceAll('\\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r');
    return '"$escaped"';
  }
}
