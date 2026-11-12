import 'dart:convert';

import '../../exceptions.dart';
import '../../grammar/json_schema_converter.dart';
import '../../grammar/json_value_depth.dart';

/// Validates and owns the supported JSON tool-input schema subset.
///
/// Object defaults are made explicit so raw schemas retain JSON Schema's open
/// property policy without changing the legacy ToolParam constructor.
///
/// Schemas may come from untrusted sources, so their size is bounded before
/// any recursive walk; doc/tool_input_schemas.md lists the limits.
Map<String, dynamic> copyToolInputSchema(Map<String, dynamic> schema) {
  final depth = jsonValueDepth(schema);
  if (depth == null) {
    throw LlamaArgumentException(
      'Tool input schemas must contain JSON values.',
    );
  }
  if (depth > _maxJsonDepth) {
    throw LlamaUnsupportedException(
      'Tool input schemas may nest JSON values at most $_maxJsonDepth levels deep.',
    );
  }
  final owned = jsonDecode(jsonEncode(schema)) as Map<String, dynamic>;
  if (owned['type'] != 'object') {
    throw LlamaArgumentException(
      'Tool input schemas need an object root; tool handlers receive a Map.',
    );
  }
  _validate(owned, 'input', _SchemaBudget(), 0);
  final grammar = JsonSchemaConverter.convert(
    jsonDecode(jsonEncode(owned)) as Map<String, dynamic>,
  );
  if (grammar.length > _maxGrammarLength) {
    throw LlamaUnsupportedException(
      'Tool input schema grammar has ${grammar.length} characters; the limit is $_maxGrammarLength. Split the tool or simplify its schema.',
    );
  }
  return owned;
}

const _maxJsonDepth = 128;
const _maxSchemaDepth = 32;
const _maxSchemaNodes = 1024;
const _maxAlternatives = 64;
const _maxEnumValues = 1024;
const _maxPropertyNameLength = 128;
const _maxGrammarLength = 256 * 1024;

/// The shipped llama.cpp grammar parser accepts repetition counts up to
/// `MAX_REPETITION_THRESHOLD` (2000). Reject larger bounds rather than letting
/// the parser silently drop an upper bound.
const _maxRepetition = 2000;

/// Undeclared required names share the subschema budget: each adds a grammar
/// rule, and rule naming slows down quadratically when names collide.
final class _SchemaBudget {
  int _nodes = 0;

  void spend() {
    if (++_nodes > _maxSchemaNodes) {
      throw LlamaUnsupportedException(
        'Tool input schemas may contain at most $_maxSchemaNodes subschemas and undeclared required property names combined.',
      );
    }
  }
}

const _types = {
  'string',
  'integer',
  'number',
  'boolean',
  'null',
  'object',
  'array',
};
const _keywords = {
  'type',
  'properties',
  'required',
  'additionalProperties',
  'items',
  'minItems',
  'maxItems',
  'minLength',
  'maxLength',
  'enum',
  'const',
  'anyOf',
  'description',
  'title',
  'default',
  'examples',
  r'$schema',
};

const _annotations = {
  r'$comment',
  r'$id',
  'deprecated',
  'readOnly',
  'writeOnly',
  'description',
  'title',
  'default',
  'examples',
  r'$schema',
};
bool _isAnnotation(String key) =>
    _annotations.contains(key) || key.startsWith('x-');

void _validate(
  Map<String, dynamic> schema,
  String path,
  _SchemaBudget budget,
  int depth,
) {
  budget.spend();
  if (depth > _maxSchemaDepth) {
    throw LlamaUnsupportedException(
      'Tool input schema at $path nests deeper than $_maxSchemaDepth levels.',
    );
  }
  for (final keyword in schema.keys) {
    if (!_keywords.contains(keyword) &&
        !keyword.startsWith('x-') &&
        !_annotations.contains(keyword)) {
      throw LlamaUnsupportedException(
        'Tool input schema keyword "$keyword" at $path is not supported. References, numeric bounds, patterns and oneOf/allOf are not enabled by this API.',
      );
    }
  }
  final alternatives = schema['anyOf'];
  if (schema.containsKey('anyOf')) {
    if (alternatives is! List || alternatives.isEmpty) {
      throw LlamaArgumentException(
        'anyOf at $path needs a nonempty schema list.',
      );
    }
    if (alternatives.length > _maxAlternatives) {
      throw LlamaUnsupportedException(
        'anyOf at $path has ${alternatives.length} alternatives; the limit is $_maxAlternatives.',
      );
    }
    if (schema.keys.any(
      (key) =>
          !{
            'anyOf',
            'description',
            'title',
            'default',
            'examples',
            r'$schema',
          }.contains(key) &&
          !_isAnnotation(key),
    )) {
      throw LlamaUnsupportedException(
        'anyOf constraint siblings at $path are not supported; put each complete alternative inside anyOf.',
      );
    }
    for (var i = 0; i < alternatives.length; i++) {
      final item = alternatives[i];
      if (item is! Map<String, dynamic>) {
        throw LlamaArgumentException(
          'anyOf alternatives at $path must be schemas.',
        );
      }
      _validate(item, '$path.anyOf[$i]', budget, depth + 1);
    }
    return;
  }
  final type = schema['type'];
  final types = type is String ? [type] : type;
  if (schema.containsKey('type') && type == null) {
    throw LlamaArgumentException('Invalid schema type at $path.');
  }
  if (types != null &&
      (types is! List ||
          types.isEmpty ||
          types.any((type) => !_types.contains(type)) ||
          types.toSet().length != types.length)) {
    throw LlamaArgumentException('Invalid schema type at $path.');
  }
  if (schema.isNotEmpty && schema.keys.every(_isAnnotation)) return;
  if (type == null &&
      !schema.containsKey('enum') &&
      !schema.containsKey('const')) {
    throw LlamaUnsupportedException(
      'Tool schema $path needs an explicit type, enum, const or anyOf.',
    );
  }
  if (schema.containsKey('enum')) {
    final values = schema['enum'];
    if (values is! List ||
        values.isEmpty ||
        values.map(jsonEncode).toSet().length != values.length) {
      throw LlamaArgumentException(
        'enum at $path needs nonempty unique values.',
      );
    }
    if (values.length > _maxEnumValues) {
      throw LlamaUnsupportedException(
        'enum at $path has ${values.length} values; the limit is $_maxEnumValues.',
      );
    }
    for (final value in values) {
      _literal(value, types, path);
    }
  }
  if (schema.containsKey('const')) {
    _literal(schema['const'], types, path);
    if (schema.containsKey('enum') &&
        !(schema['enum'] as List).contains(schema['const'])) {
      throw LlamaUnsupportedException('Conflicting const and enum at $path.');
    }
  }
  final object = types is List && types.contains('object');
  final array = types is List && types.contains('array');
  final string = types is List && types.contains('string');
  if (schema.containsKey('properties') ||
      schema.containsKey('required') ||
      schema.containsKey('additionalProperties')) {
    if (!object) {
      throw LlamaUnsupportedException(
        'Object constraints at $path require an object type.',
      );
    }
  }
  if (object) {
    final properties = schema.containsKey('properties')
        ? schema['properties']
        : <String, dynamic>{};
    if (properties is! Map<String, dynamic>) {
      throw LlamaArgumentException('properties at $path must be an object.');
    }
    schema['properties'] = properties;
    for (final entry in properties.entries) {
      if (entry.key.isEmpty || entry.value is! Map<String, dynamic>) {
        throw LlamaArgumentException(
          'Properties at $path need nonempty names and schemas.',
        );
      }
      if (entry.key.runes.length > _maxPropertyNameLength) {
        throw LlamaUnsupportedException(
          'Property names at $path may have at most $_maxPropertyNameLength characters.',
        );
      }
      _validate(
        entry.value as Map<String, dynamic>,
        '$path.${entry.key}',
        budget,
        depth + 1,
      );
    }
    final additional = schema.putIfAbsent('additionalProperties', () => true);
    if (additional is Map<String, dynamic>) {
      _validate(additional, '$path.additionalProperties', budget, depth + 1);
    } else if (additional is! bool) {
      throw LlamaArgumentException(
        'additionalProperties at $path needs a boolean or schema.',
      );
    }
    final required = schema.containsKey('required')
        ? schema['required']
        : const <String>[];
    if (required is! List ||
        required.toSet().length != required.length ||
        required.any((key) => key is! String || key.isEmpty)) {
      throw LlamaArgumentException(
        'required at $path must list unique nonempty property names.',
      );
    }
    for (final name in required.cast<String>()) {
      if (properties.containsKey(name)) continue;
      budget.spend();
      if (additional == false) {
        throw LlamaArgumentException(
          'required at $path names "$name", which additionalProperties: false forbids.',
        );
      }
      if (name.runes.length > _maxPropertyNameLength) {
        throw LlamaUnsupportedException(
          'Property names at $path may have at most $_maxPropertyNameLength characters.',
        );
      }
    }
  }
  if (array) {
    final items = schema['items'];
    if (items is! Map<String, dynamic>) {
      throw LlamaUnsupportedException(
        'Arrays at $path need one items schema; tuple schemas are not supported.',
      );
    }
    _validate(items, '$path.items', budget, depth + 1);
  } else if (schema.containsKey('items')) {
    throw LlamaUnsupportedException('items at $path requires an array type.');
  }
  _bounds(schema, path, 'Items', array);
  _bounds(schema, path, 'Length', string);
  if (schema.containsKey('enum') || schema.containsKey('const')) {
    if (schema.keys.any(
      (key) => {
        'properties',
        'required',
        'additionalProperties',
        'items',
        'minItems',
        'maxItems',
        'minLength',
        'maxLength',
      }.contains(key),
    )) {
      throw LlamaUnsupportedException(
        'Enum/const constraint combinations at $path are not supported.',
      );
    }
  }
}

void _literal(Object? value, Object? types, String path) {
  if (value is Map || value is List) {
    throw LlamaUnsupportedException(
      'Container enum/const values at $path are not supported.',
    );
  }
  if (types is! List) return;
  final compatible = types.any(
    (type) => switch (type) {
      'string' => value is String,
      'integer' => value is int,
      'number' => value is num,
      'boolean' => value is bool,
      'null' => value == null,
      _ => false,
    },
  );
  if (!compatible) {
    throw LlamaUnsupportedException(
      'Enum/const values at $path must match the declared types.',
    );
  }
}

void _bounds(
  Map<String, dynamic> schema,
  String path,
  String suffix,
  bool applicable,
) {
  final minimum = schema['min$suffix'];
  final maximum = schema['max$suffix'];
  if (!schema.containsKey('min$suffix') && !schema.containsKey('max$suffix')) {
    return;
  }
  if (!applicable) {
    throw LlamaUnsupportedException(
      '$suffix bounds at $path require the corresponding type.',
    );
  }
  if ((schema.containsKey('min$suffix') && (minimum is! int || minimum < 0)) ||
      (schema.containsKey('max$suffix') && (maximum is! int || maximum < 0)) ||
      minimum is int && maximum is int && minimum > maximum) {
    throw LlamaArgumentException('Invalid $suffix bounds at $path.');
  }
  for (final keyword in ['min$suffix', 'max$suffix']) {
    final bound = schema[keyword];
    if (bound is int && bound > _maxRepetition) {
      throw LlamaUnsupportedException(
        '$keyword at $path is $bound; llama.cpp grammars accept at most $_maxRepetition.',
      );
    }
  }
}

/// Validates a tool value using the same schema consumed by templates.
({bool valid, Object? value}) validateToolInputValue(
  Object? value,
  Map<String, dynamic> schema,
) => jsonValueDepth(value) == null
    ? (valid: false, value: null)
    : _validateValue(value, schema);

({bool valid, Object? value}) _validateValue(
  Object? value,
  Map<String, dynamic> schema,
) {
  final alternatives = schema['anyOf'];
  if (alternatives is List) {
    for (final alternative in alternatives) {
      final candidate = _validateValue(
        value,
        Map<String, dynamic>.from(alternative as Map),
      );
      if (candidate.valid) return candidate;
    }
    return (valid: false, value: null);
  }
  final type = schema['type'];
  if (type is List) {
    for (final alternative in type) {
      final candidate = _validateValue(value, {...schema, 'type': alternative});
      if (candidate.valid) return candidate;
    }
    return (valid: false, value: null);
  }
  if (schema.containsKey('const') && schema['const'] != value) {
    return (valid: false, value: null);
  }
  Object? normalized = value;

  if (type == 'string') {
    if (value is! String) return (valid: false, value: null);
    final length = value.runes.length;
    if (schema['minLength'] is int && length < (schema['minLength'] as int) ||
        schema['maxLength'] is int && length > (schema['maxLength'] as int)) {
      return (valid: false, value: null);
    }
  } else if (type == 'integer') {
    if (value is! int) return (valid: false, value: null);
  } else if (type == 'number') {
    if (value is! num) return (valid: false, value: null);
  } else if (type == 'boolean') {
    if (value is! bool) return (valid: false, value: null);
  } else if (type == 'null') {
    if (value != null) return (valid: false, value: null);
  } else if (type == 'object') {
    if (value is! Map) return (valid: false, value: null);
    final properties = schema['properties'] is Map
        ? schema['properties'] as Map
        : const <String, dynamic>{};
    final required = (schema['required'] as List? ?? const [])
        .whereType<String>()
        .toSet();
    final additional = schema['additionalProperties'];
    final object = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is! String) return (valid: false, value: null);
      final declared = properties[entry.key];
      final propertySchema = declared is Map
          ? Map<String, dynamic>.from(declared)
          : null;
      if (propertySchema == null && additional == true) {
        object[entry.key as String] = entry.value;
        continue;
      }
      final effective =
          propertySchema ??
          (additional is Map ? Map<String, dynamic>.from(additional) : null);
      if (effective == null) return (valid: false, value: null);
      final nested = _validateValue(entry.value, effective);
      if (!nested.valid) return (valid: false, value: null);
      object[entry.key as String] = nested.value;
    }
    if (!object.keys.toSet().containsAll(required)) {
      return (valid: false, value: null);
    }
    normalized = object;
  } else if (type == 'array') {
    if (value is! List) return (valid: false, value: null);
    if (schema['minItems'] is int &&
            value.length < (schema['minItems'] as int) ||
        schema['maxItems'] is int &&
            value.length > (schema['maxItems'] as int)) {
      return (valid: false, value: null);
    }
    final itemSchema = schema['items'];
    if (itemSchema is Map) {
      final items = <Object?>[];
      for (final item in value) {
        final nested = _validateValue(
          item,
          Map<String, dynamic>.from(itemSchema),
        );
        if (!nested.valid) return (valid: false, value: null);
        items.add(nested.value);
      }
      normalized = items;
    }
  }
  final enumValues = schema['enum'];
  if (enumValues is List && !enumValues.contains(normalized)) {
    return (valid: false, value: null);
  }
  return (valid: true, value: normalized);
}
