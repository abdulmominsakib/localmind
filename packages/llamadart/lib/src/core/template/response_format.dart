import 'dart:convert';

import '../exceptions.dart';
import '../grammar/json_schema_converter.dart';
import '../grammar/json_value_depth.dart';
import '../grammar/response_schema_validation.dart';

const _supportedTypes = "'text', 'json_object' or 'json_schema'";
const _jsonSchemaKeys = {'schema', 'name', 'description', 'strict'};

/// Returns the JSON schema that [responseFormat] constrains output to.
///
/// Returns null when [responseFormat] is null or requests plain text
/// (`{'type': 'text'}`). `{'type': 'json_object'}` maps to an object schema and
/// `{'type': 'json_schema', 'json_schema': {'schema': ...}}` to its schema.
///
/// A key whose value is null counts as absent, as JSON serializers that emit
/// null fields write it. Every other shape, including unknown types and
/// misspelled keys, throws [LlamaUnsupportedException] so a typo cannot
/// silently drop the constraint.
Map<String, dynamic>? responseFormatSchema(
  Map<String, dynamic>? responseFormat,
) {
  if (responseFormat == null) {
    return null;
  }
  final type = responseFormat['type'];
  if (type is! String) {
    throw LlamaUnsupportedException(
      'responseFormat.type must be one of $_supportedTypes; '
      'got ${type == null ? 'no type' : type.runtimeType}.',
    );
  }
  switch (type) {
    case 'text':
    case 'json_object':
      _rejectUnknownKeys(
        responseFormat,
        const {'type'},
        'responseFormat',
        type,
      );
      return type == 'text' ? null : const {'type': 'object'};
    case 'json_schema':
      _rejectUnknownKeys(
        responseFormat,
        const {'type', 'json_schema'},
        'responseFormat',
        type,
      );
      return _jsonSchemaSchema(responseFormat['json_schema']);
    default:
      throw LlamaUnsupportedException(
        "Unsupported responseFormat.type '$type'; expected $_supportedTypes.",
      );
  }
}

Map<String, dynamic> _jsonSchemaSchema(Object? jsonSchema) {
  if (jsonSchema is! Map) {
    throw LlamaUnsupportedException(
      "responseFormat.json_schema must be an object with a 'schema' JSON "
      "object for type 'json_schema'.",
    );
  }
  _rejectUnknownKeys(
    jsonSchema,
    _jsonSchemaKeys,
    'responseFormat.json_schema',
    'json_schema',
  );
  final schema = jsonSchema['schema'];
  if (schema is! Map<String, dynamic>) {
    throw LlamaUnsupportedException(
      'responseFormat.json_schema.schema must be a JSON object typed '
      'Map<String, dynamic>, as jsonDecode returns or a <String, dynamic>{} '
      'literal declares; got ${schema == null ? 'none' : schema.runtimeType}.',
    );
  }
  for (final key in const ['name', 'description']) {
    final value = jsonSchema[key];
    if (value != null && value is! String) {
      throw LlamaUnsupportedException(
        'responseFormat.json_schema.$key must be a string.',
      );
    }
  }
  final strict = jsonSchema['strict'];
  if (strict != null && strict is! bool) {
    throw LlamaUnsupportedException(
      'responseFormat.json_schema.strict must be a bool.',
    );
  }
  return schema;
}

/// Converts a `responseFormat` [schema] to GBNF.
///
/// When conversion fails, throws [LlamaArgumentException] if [schema] holds a
/// cycle or another value that is not JSON, and [LlamaUnsupportedException]
/// otherwise, such as for an unresolvable `$ref`, an unsupported constraint, or a
/// schema whose JSON nesting exceeds 128 levels.
String responseFormatGrammar(
  Map<String, dynamic> schema, {
  String schemaName = 'responseFormat',
}) {
  try {
    validateResponseSchema(schema);
    return JsonSchemaConverter.convert(
      jsonDecode(jsonEncode(schema)) as Map<String, dynamic>,
    );
  } on LlamaException {
    rethrow;
  } catch (error) {
    if (jsonValueDepth(schema) == null) {
      throw LlamaArgumentException(
        'responseFormat.json_schema.schema must contain only JSON values: '
        'string keys, finite numbers and no cycles.',
      );
    }
    // Reference chains can still exhaust converter recursion after the
    // document nesting check. Keep converter failures in the typed hierarchy.
    throw LlamaUnsupportedException(
      'Unsupported $schemaName JSON schema at \$: $error',
    );
  }
}

void _rejectUnknownKeys(
  Map<dynamic, dynamic> map,
  Set<String> allowed,
  String path,
  String type,
) {
  for (final MapEntry(:key, :value) in map.entries) {
    if (value != null && !allowed.contains(key)) {
      throw LlamaUnsupportedException(
        "Unsupported $path key '$key' for type '$type'; supported keys: "
        '${allowed.join(', ')}.',
      );
    }
  }
}
