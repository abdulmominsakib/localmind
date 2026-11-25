import '../exceptions.dart';
import '../models/tools/tool_definition.dart';
import '../models/tools/tool_input_schema.dart';
import '../models/tools/tool_param.dart';
import 'tool_call_parsing_utils.dart';

/// Result of reconstructing one tool argument against its declared schema.
typedef ToolSchemaValueResult = ({bool valid, Object? value});

/// Returns tool schemas keyed by the exact tool name emitted in the protocol.
Map<String, Map<String, dynamic>> toolSchemas(List<ToolDefinition>? tools) {
  if (tools == null || tools.isEmpty) {
    return const {};
  }
  final schemas = <String, Map<String, dynamic>>{};
  for (final tool in tools) {
    if (tool.name.isEmpty) {
      throw LlamaUnsupportedException(
        'Structured tool schemas require non-empty tool names.',
      );
    }
    if (schemas.containsKey(tool.name)) {
      throw LlamaUnsupportedException(
        'Structured tool schemas require unique tool names; '
        '"${tool.name}" is declared more than once.',
      );
    }
    validateToolParameterIdentities(tool);
    schemas[tool.name] = tool.toJsonSchema();
  }
  return schemas;
}

/// Rejects parameter definitions that would be lossy when converted to an
/// object schema.
void validateToolParameterIdentities(ToolDefinition tool) {
  final error = toolParamIdentityError(
    tool.parameters,
    path: 'tool "${tool.name}" parameters',
  );
  if (error != null) {
    throw LlamaUnsupportedException(error);
  }
}

/// Returns object-property schemas keyed by their exact protocol names.
Map<String, Map<String, dynamic>> schemaProperties(
  Map<String, dynamic> schema,
) {
  final raw = schema['properties'];
  if (raw is! Map) {
    return const {};
  }
  return <String, Map<String, dynamic>>{
    for (final entry in raw.entries)
      if (entry.key is String && entry.value is Map)
        entry.key as String: Map<String, dynamic>.from(entry.value as Map),
  };
}

/// Returns the required object-property names from [schema].
Set<String> schemaRequired(Map<String, dynamic> schema) {
  final raw = schema['required'];
  return raw is List ? raw.whereType<String>().toSet() : const {};
}

/// Whether a schema must preserve emitted text as a string.
bool schemaResolvesToString(Map<String, dynamic> schema) =>
    schema['type'] == 'string' ||
    schema['type'] == null &&
        schema['enum'] is List &&
        (schema['enum'] as List).every((value) => value is String);

/// Decodes protocol text according to [schema] without guessing string types.
ToolSchemaValueResult decodeToolSchemaText(
  String raw,
  Map<String, dynamic> schema,
) {
  if (schemaResolvesToString(schema)) {
    return validateToolSchemaValue(raw, schema);
  }
  final decoded = ToolCallParsingUtils.decodeJsonValue(raw);
  if (decoded == null && raw.trim() != 'null') {
    return (valid: false, value: null);
  }
  return validateToolSchemaValue(decoded, schema);
}

/// Validates and normalizes a decoded value according to [schema].
ToolSchemaValueResult validateToolSchemaValue(
  Object? value,
  Map<String, dynamic> schema,
) => validateToolInputValue(value, schema);

/// Rejects raw schemas that a fixed-argument protocol grammar cannot enforce.
/// Legacy parameter-helper callers retain their existing format support.
void validateFixedArgumentToolSchemas(
  List<ToolDefinition>? tools, {
  required String format,
  bool stringEnums = false,
}) {
  for (final tool in tools ?? const <ToolDefinition>[]) {
    if (!toolUsesJsonSchema(tool)) continue;
    final schema = tool.toJsonSchema();
    if (schema['additionalProperties'] != false) {
      throw LlamaUnsupportedException(
        '$format tool schemas need additionalProperties: false; this protocol names a fixed set of arguments.',
      );
    }
    for (final property in schemaProperties(schema).values) {
      final type = property['type'];
      final allowed = {
        'type',
        'description',
        'title',
        'default',
        'examples',
        r'$schema',
      };
      if (stringEnums && type == 'string') allowed.add('enum');
      if (!{'string', 'integer', 'number', 'boolean', 'null'}.contains(type) ||
          property.keys.any((key) => !allowed.contains(key))) {
        throw LlamaUnsupportedException(
          '$format currently supports scalar tool properties${stringEnums ? " and string enums" : ""}; use a JSON-envelope format for richer schemas.',
        );
      }
    }
  }
}
