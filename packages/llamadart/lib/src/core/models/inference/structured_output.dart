import 'dart:convert';

import '../../exceptions.dart';
import '../../grammar/response_schema_validation.dart';
import '../../grammar/json_schema_converter.dart';
import '../../template/response_format.dart';
import '../chat/completion_chunk.dart';

/// Converts a decoded JSON object into an application-specific value.
typedef LlamaJsonObjectDecoder<T> = T Function(Map<String, dynamic> json);

/// Converts any decoded JSON value into an application-specific value.
typedef LlamaJsonValueDecoder<T> = T Function(Object? value);

/// Describes a strict structured JSON response and final-output decoder.
///
/// Use [jsonObject] when any JSON object is acceptable. Use [jsonSchema] for
/// the common object-shaped JSON Schema case, or [jsonValueSchema] when the
/// schema returns a primitive or array. All schema helpers validate that the
/// schema can be converted to the GBNF subset used by `llamadart` before a
/// generation request is sent.
///
/// Example:
/// ```dart
/// final output = LlamaStructuredOutput<Contact>.jsonSchema(
///   schema: {
///     'type': 'object',
///     'properties': {
///       'name': {'type': 'string'},
///       'email': {'type': 'string'},
///     },
///     'required': ['name', 'email'],
///     'additionalProperties': false,
///   },
///   decoder: Contact.fromJson,
/// );
///
/// final contact = await engine.createStructuredJson(
///   messages,
///   output: output,
/// );
/// ```
class LlamaStructuredOutput<T> {
  LlamaStructuredOutput._({
    required Map<String, dynamic> responseFormat,
    required LlamaJsonValueDecoder<T> decoder,
    Map<String, dynamic>? schema,
  }) : _responseFormat = _copyJsonMap(responseFormat, 'responseFormat'),
       _schema = schema == null ? null : _copyJsonMap(schema, 'schema'),
       _decoder = decoder;

  /// Creates a strict `json_object` response format.
  ///
  /// The final model output must decode to a JSON object. [decoder] receives
  /// that object after parsing succeeds.
  factory LlamaStructuredOutput.jsonObject({
    required LlamaJsonObjectDecoder<T> decoder,
  }) {
    return LlamaStructuredOutput._(
      responseFormat: const {'type': 'json_object'},
      decoder: (value) => decoder(_expectJsonObject(value)),
    );
  }

  /// Creates a strict object-shaped `json_schema` response format.
  ///
  /// [schema] must be representable by the current JSON-schema-to-GBNF subset:
  /// primitives, objects with properties/required/additionalProperties, arrays
  /// with `items` or fixed `prefixItems`, enum/const, local `$ref`, `anyOf`,
  /// `oneOf`, additive object/enum `allOf`, integer bounds, `uuid`/`uuid1`–`uuid5`,
  /// date/time formats,
  /// compiled patterns, string length, and array item-count bounds. Unsupported
  /// constraint keywords throw [LlamaUnsupportedException] before generation.
  /// Annotations and unknown vocabulary are preserved but not
  /// enforced by constrained decoding.
  ///
  /// [decoder] receives the validated JSON object.
  factory LlamaStructuredOutput.jsonSchema({
    required Map<String, dynamic> schema,
    required LlamaJsonObjectDecoder<T> decoder,
    String? name,
    String? description,
    bool strict = true,
  }) {
    final normalizedSchema = _validateStructuredSchema(schema);
    _validateJsonSchemaRootObject(normalizedSchema);
    return LlamaStructuredOutput._(
      responseFormat: _schemaResponseFormat(
        normalizedSchema,
        name: name,
        description: description,
        strict: strict,
      ),
      schema: normalizedSchema,
      decoder: (value) => decoder(_expectJsonObject(value)),
    );
  }

  /// Creates a strict `json_schema` response format for any JSON value.
  ///
  /// Use this when the schema's root value is not a JSON object, such as an
  /// array or string classification label. Object-shaped results can usually
  /// use [jsonSchema] for a narrower decoder type.
  factory LlamaStructuredOutput.jsonValueSchema({
    required Map<String, dynamic> schema,
    required LlamaJsonValueDecoder<T> decoder,
    String? name,
    String? description,
    bool strict = true,
  }) {
    final normalizedSchema = _validateStructuredSchema(schema);
    return LlamaStructuredOutput._(
      responseFormat: _schemaResponseFormat(
        normalizedSchema,
        name: name,
        description: description,
        strict: strict,
      ),
      schema: normalizedSchema,
      decoder: decoder,
    );
  }

  final Map<String, dynamic> _responseFormat;
  final Map<String, dynamic>? _schema;
  final LlamaJsonValueDecoder<T> _decoder;

  /// OpenAI-compatible response format map for [LlamaEngine.create].
  Map<String, dynamic> get responseFormat =>
      _copyJsonMap(_responseFormat, 'responseFormat');

  /// JSON Schema used for final-output validation, if this helper has one.
  Map<String, dynamic>? get schema =>
      _schema == null ? null : _copyJsonMap(_schema, 'schema');

  /// Parses, validates, and decodes the final generated JSON text.
  ///
  /// This method is intentionally a final-output step. Streaming callers can
  /// still display chunks as they arrive, then call [parse] once the content
  /// stream has completed.
  T parse(String output) {
    final Object? decoded;
    try {
      decoded = jsonDecode(output);
    } on FormatException catch (error) {
      throw LlamaInferenceException(
        'Malformed structured JSON output.',
        error.message,
      );
    }

    final schema = _schema;
    if (schema == null) {
      _expectJsonObject(decoded);
    } else {
      try {
        _JsonSchemaOutputValidator(schema).validate(decoded);
      } on _JsonSchemaValidationFailure catch (error) {
        throw LlamaInferenceException(
          'Structured JSON output did not match the requested schema.',
          error.message,
        );
      }
    }

    try {
      return _decoder(decoded);
    } on LlamaException {
      rethrow;
    } catch (error) {
      throw LlamaInferenceException(
        'Failed to decode structured JSON output.',
        error,
      );
    }
  }
}

/// Collects streamed chat-completion content and parses it as structured JSON.
extension LlamaStructuredOutputStreamExtension on Stream<LlamaCompletionChunk> {
  /// Collects content deltas, then validates and decodes the final JSON value.
  Future<T> parseStructuredJson<T>(LlamaStructuredOutput<T> output) async {
    final buffer = StringBuffer();
    await for (final chunk in this) {
      for (final choice in chunk.choices) {
        final content = choice.delta.content;
        if (content != null) {
          buffer.write(content);
        }
      }
    }
    return output.parse(buffer.toString());
  }
}

Map<String, dynamic> _schemaResponseFormat(
  Map<String, dynamic> schema, {
  required String? name,
  required String? description,
  required bool strict,
}) {
  final jsonSchema = <String, dynamic>{'schema': schema, 'strict': strict};
  if (name != null) {
    jsonSchema['name'] = name;
  }
  if (description != null) {
    jsonSchema['description'] = description;
  }
  return {'type': 'json_schema', 'json_schema': jsonSchema};
}

Map<String, dynamic> _validateStructuredSchema(Map<String, dynamic> schema) {
  validateResponseSchemaJson(schema);
  final normalized = _copyJsonMap(schema, 'schema');
  responseFormatGrammar(normalized, schemaName: 'LlamaStructuredOutput.schema');
  return normalized;
}

void _validateJsonSchemaRootObject(Map<String, dynamic> schema) {
  if (_schemaRequiresJsonObject(schema, schema, <String>{})) {
    return;
  }
  throw LlamaUnsupportedException(
    'LlamaStructuredOutput.jsonSchema requires a JSON object root schema. Use '
    'LlamaStructuredOutput.jsonValueSchema for primitive, array, or mixed root '
    'schemas.',
  );
}

bool _schemaRequiresJsonObject(
  Map<String, dynamic> schema,
  Map<String, dynamic> rootSchema,
  Set<String> resolvingRefs,
) {
  final ref = schema[r'$ref'];
  if (ref is String) {
    if (resolvingRefs.contains(ref)) {
      return false;
    }
    final target = _resolveLocalSchemaRef(rootSchema, ref);
    return target != null &&
        _schemaRequiresJsonObject(target, rootSchema, {...resolvingRefs, ref});
  }

  final schemaTypes = responseSchemaTypes(schema['type'], r'$');
  if (schemaTypes != null) {
    if (schemaTypes.length != 1 || !schemaTypes.contains('object')) {
      return false;
    }
  }

  final constValue = schema['const'];
  if (schema.containsKey('const')) {
    return constValue is Map;
  }

  final enumValues = schema['enum'];
  if (enumValues is List) {
    return enumValues.every((value) => value is Map);
  }

  final oneOf = schema['oneOf'];
  if (oneOf is List) {
    return oneOf.every(
      (value) => _schemaRequiresJsonObject(
        responseSchemaMap(value, r'$.oneOf'),
        rootSchema,
        resolvingRefs,
      ),
    );
  }

  final anyOf = schema['anyOf'];
  if (anyOf is List) {
    return anyOf.every(
      (value) => _schemaRequiresJsonObject(
        responseSchemaMap(value, r'$.anyOf'),
        rootSchema,
        resolvingRefs,
      ),
    );
  }

  final allOf = schema['allOf'];
  if (allOf is List) {
    return allOf.any(
      (value) => _schemaRequiresJsonObject(
        responseSchemaMap(value, r'$.allOf'),
        rootSchema,
        resolvingRefs,
      ),
    );
  }

  return schemaTypes?.contains('object') ??
      (schema.containsKey('properties') ||
          schema.containsKey('additionalProperties'));
}

Map<String, dynamic>? _resolveLocalSchemaRef(
  Map<String, dynamic> rootSchema,
  String ref,
) {
  final target = JsonSchemaConverter.resolvePointer(rootSchema, ref);
  return target is Map ? responseSchemaMap(target, ref) : null;
}

Map<String, dynamic> _copyJsonMap(
  Map<String, dynamic> value,
  String valueName,
) {
  try {
    final decoded = jsonDecode(jsonEncode(value));
    return _toStringKeyedMap(decoded, valueName);
  } catch (error) {
    throw LlamaUnsupportedException(
      '$valueName must be a JSON-encodable object: $error',
    );
  }
}

Map<String, dynamic> _toStringKeyedMap(Object? value, String valueName) {
  if (value is! Map) {
    throw LlamaUnsupportedException('$valueName must be a JSON object.');
  }
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw LlamaUnsupportedException(
        '$valueName must contain only string keys.',
      );
    }
    result[key] = entry.value;
  }
  return result;
}

Map<String, dynamic> _expectJsonObject(Object? value) {
  if (value is! Map) {
    throw LlamaInferenceException(
      'Structured JSON output did not decode to a JSON object.',
    );
  }
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw LlamaInferenceException(
        'Structured JSON object contains a non-string key.',
      );
    }
    result[key] = entry.value;
  }
  return result;
}

class _JsonSchemaOutputValidator {
  _JsonSchemaOutputValidator(this.rootSchema);

  final Map<String, dynamic> rootSchema;

  void validate(Object? value) {
    _validate(value, rootSchema, r'$');
  }

  void _validate(Object? value, Map<String, dynamic> schema, String path) {
    final ref = schema[r'$ref'];
    if (ref != null) {
      _validate(value, _resolveRef(ref, path), path);
      return;
    }

    if (schema.containsKey('const') && !_jsonEquals(value, schema['const'])) {
      throw _JsonSchemaValidationFailure(
        '$path must equal ${jsonEncode(schema['const'])}.',
      );
    }

    final enumValues = schema['enum'];
    if (enumValues != null) {
      if (enumValues is! List) {
        throw _JsonSchemaValidationFailure('$path schema enum must be a list.');
      }
      final matches = enumValues.any(
        (enumValue) => _jsonEquals(value, enumValue),
      );
      if (!matches) {
        throw _JsonSchemaValidationFailure(
          '$path must be one of ${jsonEncode(enumValues)}.',
        );
      }
    }

    final oneOf = schema['oneOf'];
    if (oneOf != null) {
      final matches = _countMatchingAlternatives(value, oneOf, path, 'oneOf');
      if (matches != 1) {
        throw _JsonSchemaValidationFailure(
          '$path must match exactly one oneOf schema; matched $matches.',
        );
      }
    }

    final anyOf = schema['anyOf'];
    if (anyOf != null &&
        _countMatchingAlternatives(value, anyOf, path, 'anyOf') == 0) {
      throw _JsonSchemaValidationFailure(
        '$path must match at least one anyOf schema.',
      );
    }

    final allOf = schema['allOf'];
    if (allOf != null) {
      if (allOf is! List) {
        throw _JsonSchemaValidationFailure(
          '$path schema allOf must be a list.',
        );
      }
      for (var i = 0; i < allOf.length; i++) {
        _validate(value, _schemaMap(allOf[i], '$path.allOf[$i]'), path);
      }
    }

    final pattern = schema['pattern'];
    if (value is String &&
        pattern is String &&
        RegExp(pattern).stringMatch(value) != value) {
      throw _JsonSchemaValidationFailure(
        '$path must match the requested pattern.',
      );
    }

    final schemaType = schema['type'];
    if (schemaType is List) {
      final matched = schemaType.any(
        (type) => _matchesType(value, type, schema, path),
      );
      if (!matched) {
        throw _JsonSchemaValidationFailure(
          '$path did not match any allowed type ${jsonEncode(schemaType)}.',
        );
      }
      return;
    }

    if (schemaType is String) {
      _validateType(value, schemaType, schema, path);
      return;
    }

    if (schema.containsKey('properties') ||
        schema.containsKey('additionalProperties')) {
      _validateType(value, 'object', schema, path);
      return;
    }

    if (schema.containsKey('pattern') || schema.containsKey('format')) {
      _validateType(value, 'string', schema, path);
      return;
    }

    if (schema.containsKey('items') || schema.containsKey('prefixItems')) {
      _validateType(value, 'array', schema, path);
    }
  }

  int _countMatchingAlternatives(
    Object? value,
    Object? alternatives,
    String path,
    String keyword,
  ) {
    if (alternatives is! List) {
      throw _JsonSchemaValidationFailure(
        '$path schema $keyword must be a list.',
      );
    }
    var matches = 0;
    for (var i = 0; i < alternatives.length; i++) {
      try {
        _validate(
          value,
          _schemaMap(alternatives[i], '$path.$keyword[$i]'),
          path,
        );
        matches += 1;
      } on _JsonSchemaValidationFailure {
        // Keep checking other alternatives.
      }
    }
    return matches;
  }

  bool _matchesType(
    Object? value,
    Object? type,
    Map<String, dynamic> schema,
    String path,
  ) {
    if (type is! String) {
      return false;
    }
    try {
      _validateType(value, type, schema, path);
      return true;
    } on _JsonSchemaValidationFailure {
      return false;
    }
  }

  void _validateType(
    Object? value,
    String type,
    Map<String, dynamic> schema,
    String path,
  ) {
    switch (type) {
      case 'object':
        _validateObject(value, schema, path);
        return;
      case 'array':
        _validateArray(value, schema, path);
        return;
      case 'string':
        _validateString(value, schema, path);
        return;
      case 'integer':
        if (!_isJsonInteger(value)) {
          throw _JsonSchemaValidationFailure('$path must be an integer.');
        }
        _validateIntegerBounds(value as num, schema, path);
        return;
      case 'number':
        if (value is! num) {
          throw _JsonSchemaValidationFailure('$path must be a number.');
        }
        return;
      case 'boolean':
        if (value is! bool) {
          throw _JsonSchemaValidationFailure('$path must be a boolean.');
        }
        return;
      case 'null':
        if (value != null) {
          throw _JsonSchemaValidationFailure('$path must be null.');
        }
        return;
      default:
        throw _JsonSchemaValidationFailure(
          '$path has unsupported schema type "$type".',
        );
    }
  }

  void _validateObject(
    Object? value,
    Map<String, dynamic> schema,
    String path,
  ) {
    final object = _jsonObjectValue(value, path);
    final required = schema['required'];
    if (required != null) {
      if (required is! List) {
        throw _JsonSchemaValidationFailure(
          '$path schema required must be a list.',
        );
      }
      for (final key in required) {
        if (key is! String) {
          throw _JsonSchemaValidationFailure(
            '$path schema required entries must be strings.',
          );
        }
        if (!object.containsKey(key)) {
          throw _JsonSchemaValidationFailure('$path.$key is required.');
        }
      }
    }

    final properties = schema['properties'];
    final propertySchemas = properties == null
        ? const <String, dynamic>{}
        : _schemaMap(properties, '$path.properties');
    for (final entry in propertySchemas.entries) {
      if (object.containsKey(entry.key)) {
        _validate(
          object[entry.key],
          _schemaMap(entry.value, '$path.${entry.key}'),
          '$path.${entry.key}',
        );
      }
    }

    final additionalProperties = schema['additionalProperties'];
    final knownKeys = propertySchemas.keys.toSet();
    final extraKeys = object.keys.where((key) => !knownKeys.contains(key));
    if (additionalProperties == false) {
      if (extraKeys.isNotEmpty) {
        throw _JsonSchemaValidationFailure(
          '$path contains unsupported property "${extraKeys.first}".',
        );
      }
      return;
    }
    if (additionalProperties is Map) {
      final additionalSchema = _schemaMap(
        additionalProperties,
        '$path.additionalProperties',
      );
      for (final key in extraKeys) {
        _validate(object[key], additionalSchema, '$path.$key');
      }
    }
  }

  void _validateArray(Object? value, Map<String, dynamic> schema, String path) {
    if (value is! List) {
      throw _JsonSchemaValidationFailure('$path must be an array.');
    }

    final minItems = schema['minItems'];
    if (minItems is int && value.length < minItems) {
      throw _JsonSchemaValidationFailure(
        '$path must contain at least $minItems items.',
      );
    }

    final maxItems = schema['maxItems'];
    if (maxItems is int && value.length > maxItems) {
      throw _JsonSchemaValidationFailure(
        '$path must contain at most $maxItems items.',
      );
    }

    final prefixItems = schema['items'] is List
        ? schema['items']
        : schema['prefixItems'];
    if (prefixItems is List) {
      if (value.length != prefixItems.length) {
        throw _JsonSchemaValidationFailure(
          '$path must contain exactly ${prefixItems.length} tuple items.',
        );
      }
      for (var i = 0; i < prefixItems.length; i++) {
        _validate(
          value[i],
          _schemaMap(prefixItems[i], '$path[$i]'),
          '$path[$i]',
        );
      }
      return;
    }

    final items = schema['items'];
    if (items != null) {
      final itemSchema = _schemaMap(items, '$path.items');
      for (var i = 0; i < value.length; i++) {
        _validate(value[i], itemSchema, '$path[$i]');
      }
    }
  }

  void _validateIntegerBounds(
    num value,
    Map<String, dynamic> schema,
    String path,
  ) {
    final (min, max) = JsonSchemaConverter.integerBounds(schema);
    if ((min != null && value < min) || (max != null && value > max)) {
      throw _JsonSchemaValidationFailure(
        '$path is outside the integer bounds.',
      );
    }
  }

  void _validateString(
    Object? value,
    Map<String, dynamic> schema,
    String path,
  ) {
    if (value is! String) {
      throw _JsonSchemaValidationFailure('$path must be a string.');
    }
    final format = schema['format'];
    if (format is String && !JsonSchemaConverter.matchesFormat(format, value)) {
      throw _JsonSchemaValidationFailure('$path must match format $format.');
    }
    final minLength = schema['minLength'];
    if (minLength is int && value.length < minLength) {
      throw _JsonSchemaValidationFailure(
        '$path must contain at least $minLength characters.',
      );
    }
    final maxLength = schema['maxLength'];
    if (maxLength is int && value.length > maxLength) {
      throw _JsonSchemaValidationFailure(
        '$path must contain at most $maxLength characters.',
      );
    }
  }

  Map<String, dynamic> _resolveRef(Object? ref, String path) {
    if (ref is! String || !ref.startsWith('#/')) {
      throw _JsonSchemaValidationFailure(
        '$path schema uses unsupported ref "$ref".',
      );
    }
    final target = JsonSchemaConverter.resolvePointer(rootSchema, ref);
    return _schemaMap(target, '$path.$ref');
  }

  Map<String, dynamic> _schemaMap(Object? value, String path) {
    if (value is! Map) {
      throw _JsonSchemaValidationFailure('$path schema must be a JSON object.');
    }
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw _JsonSchemaValidationFailure(
          '$path schema must contain only string keys.',
        );
      }
      result[key] = entry.value;
    }
    return result;
  }

  Map<String, dynamic> _jsonObjectValue(Object? value, String path) {
    if (value is! Map) {
      throw _JsonSchemaValidationFailure('$path must be an object.');
    }
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw _JsonSchemaValidationFailure(
          '$path object contains a non-string key.',
        );
      }
      result[key] = entry.value;
    }
    return result;
  }
}

class _JsonSchemaValidationFailure implements Exception {
  const _JsonSchemaValidationFailure(this.message);

  final String message;
}

bool _isJsonInteger(Object? value) {
  if (value is int) {
    return true;
  }
  return value is num && value.isFinite && value % 1 == 0;
}

bool _jsonEquals(Object? a, Object? b) {
  if (a is num && b is num) {
    return a == b;
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEquals(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) ||
          !_jsonEquals(entry.value, b[entry.key])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}
