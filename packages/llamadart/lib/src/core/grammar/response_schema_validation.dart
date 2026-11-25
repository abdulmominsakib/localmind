import '../exceptions.dart';
import 'json_schema_converter.dart';
import 'json_value_depth.dart';

/// Checks JSON safety before recursive schema copying.
void validateResponseSchemaJson(Map<String, dynamic> schema) {
  final depth = jsonValueDepth(schema);
  if (depth == null) {
    throw LlamaArgumentException(
      'Response schema at \$ must contain only JSON values: string keys, finite numbers and no cycles.',
    );
  }
  if (depth > 128) {
    _unsupported(r'$', 'JSON nesting must not exceed 128 levels');
  }
}

/// Checks assertions enforced by the response-schema converter.
void validateResponseSchema(Map<String, dynamic> schema) {
  validateResponseSchemaJson(schema);
  _validateSupportedSchemaSubset(schema, r'$');
  _validateReferences(
    schema,
    schema,
    r'$',
    _schemaPositions(schema),
    <String>{},
  );
}

const _supportedSchemaTypes = <String>{
  'object',
  'array',
  'string',
  'integer',
  'number',
  'boolean',
  'null',
};

// Unknown vocabulary and annotations do not assert constraints. Keep the
// assertion inventory explicit so extensions remain compatible with upstream.
const _unsupportedAssertionKeywords = <String>{
  'multipleOf',
  'uniqueItems',
  'contains',
  'minContains',
  'maxContains',
  'minProperties',
  'maxProperties',
  'patternProperties',
  'propertyNames',
  'dependentRequired',
  'dependentSchemas',
  'dependencies',
  'not',
  'if',
  'then',
  'else',
  'unevaluatedItems',
  'unevaluatedProperties',
  'additionalItems',
  r'$dynamicRef',
  r'$recursiveRef',
};
const _assertionKeywords = <String>{
  ..._unsupportedAssertionKeywords,
  r'$ref',
  'type',
  'properties',
  'required',
  'additionalProperties',
  'items',
  'prefixItems',
  'minItems',
  'maxItems',
  'minLength',
  'maxLength',
  'pattern',
  'format',
  'minimum',
  'maximum',
  'exclusiveMinimum',
  'exclusiveMaximum',
  'enum',
  'const',
  'allOf',
  'anyOf',
  'oneOf',
};

void _validateSupportedSchemaSubset(Map<String, dynamic> schema, String path) {
  for (final keyword in schema.keys) {
    if (_unsupportedAssertionKeywords.contains(keyword) &&
        !_isTrivialAssertion(schema, keyword)) {
      throw LlamaUnsupportedException(
        'Unsupported structured JSON schema: keyword "$path.$keyword" is not '
        'supported by the current JSON-schema-to-GBNF subset.',
      );
    }
  }

  for (final keyword in schema.keys) {
    if (!_isMetadata(keyword) &&
        schema[keyword] == null &&
        keyword != 'const') {
      _unsupported('$path.$keyword', 'must not be null');
    }
  }
  final schemaTypes = responseSchemaTypes(schema['type'], path);
  _validateDispatch(schema, schemaTypes, path);
  _validateRefSchemaShape(schema, path);
  _validateKeywordContexts(schema, schemaTypes, path);
  _validateKeywordValues(schema, path);
  _validateNestedSchemas(schema, path);
}

/// Parses and checks the schema type keyword at [path].
Set<String>? responseSchemaTypes(Object? type, String path) {
  if (type == null) {
    return null;
  }
  if (type is String) {
    _validateSchemaType(type, '$path.type');
    return {type};
  }
  if (type is List) {
    final types = <String>{};
    for (var i = 0; i < type.length; i++) {
      final item = type[i];
      if (item is! String) {
        throw LlamaUnsupportedException(
          'Unsupported structured JSON schema: $path.type[$i] must be a '
          'schema type string.',
        );
      }
      _validateSchemaType(item, '$path.type[$i]');
      types.add(item);
    }
    if (types.isEmpty) {
      throw LlamaUnsupportedException(
        'Unsupported structured JSON schema: $path.type must not be empty.',
      );
    }
    return types;
  }
  throw LlamaUnsupportedException(
    'Unsupported structured JSON schema: $path.type must be a string or list '
    'of strings.',
  );
}

void _validateSchemaType(String type, String path) {
  if (!_supportedSchemaTypes.contains(type)) {
    throw LlamaUnsupportedException(
      'Unsupported structured JSON schema: $path uses unsupported type '
      '"$type".',
    );
  }
}

void _validateRefSchemaShape(Map<String, dynamic> schema, String path) {
  if (!schema.containsKey(r'$ref')) {
    return;
  }
  final ref = schema[r'$ref'];
  if (ref is! String || !ref.startsWith('#/')) {
    throw LlamaUnsupportedException(
      'Unsupported structured JSON schema: $path.\$ref must be a local "#/..." '
      'reference.',
    );
  }

  final siblingKeywords = schema.keys.where(
    (keyword) =>
        keyword != r'$ref' &&
        keyword != 'definitions' &&
        keyword != r'$defs' &&
        !_isMetadata(keyword) &&
        !_isTrivialAssertion(schema, keyword),
  );
  if (siblingKeywords.isNotEmpty) {
    throw LlamaUnsupportedException(
      'Unsupported structured JSON schema: $path.\$ref cannot be combined with '
      'sibling validation keywords.',
    );
  }
}

void _validateKeywordContexts(
  Map<String, dynamic> schema,
  Set<String>? schemaTypes,
  String path,
) {
  final hasObjectKeywords =
      schema.containsKey('properties') ||
      schema.containsKey('required') ||
      schema.containsKey('additionalProperties');
  final objectContext =
      schemaTypes?.contains('object') ??
      (schema.containsKey('properties') ||
          schema.containsKey('additionalProperties'));
  if (hasObjectKeywords && !objectContext) {
    throw LlamaUnsupportedException(
      'Unsupported structured JSON schema: object keyword at $path requires '
      'type "object" or object-shaped properties.',
    );
  }

  final hasArrayKeywords =
      schema.containsKey('items') ||
      schema.containsKey('prefixItems') ||
      schema.containsKey('minItems') ||
      schema.containsKey('maxItems');
  final arrayContext =
      schemaTypes?.contains('array') ??
      (schema.containsKey('items') || schema.containsKey('prefixItems'));
  if (hasArrayKeywords && !arrayContext) {
    throw LlamaUnsupportedException(
      'Unsupported structured JSON schema: array keyword at $path requires '
      'type "array" or an item schema.',
    );
  }

  final hasStringKeywords =
      schema.containsKey('pattern') ||
      schema.containsKey('minLength') ||
      schema.containsKey('maxLength') ||
      schema.containsKey('format');
  final stringContext =
      schemaTypes?.contains('string') ??
      (schema.containsKey('pattern') || schema.containsKey('format'));
  if (hasStringKeywords && !stringContext) {
    throw LlamaUnsupportedException(
      'Unsupported structured JSON schema: string length keyword at $path '
      'requires type "string".',
    );
  }
}

void _validateKeywordValues(Map<String, dynamic> schema, String path) {
  final enumValues = schema['enum'];
  if (enumValues != null) {
    if (enumValues is! List || enumValues.isEmpty) {
      throw LlamaUnsupportedException(
        'Unsupported structured JSON schema: $path.enum must be a non-empty '
        'list.',
      );
    }
  }

  final required = schema['required'];
  if (required != null) {
    if (required is! List) {
      throw LlamaUnsupportedException(
        'Unsupported structured JSON schema: $path.required must be a list.',
      );
    }
    for (var i = 0; i < required.length; i++) {
      if (required[i] is! String) {
        throw LlamaUnsupportedException(
          'Unsupported structured JSON schema: $path.required[$i] must be a '
          'property name string.',
        );
      }
    }
  }

  _validateNonNegativeIntKeyword(schema, 'minItems', path);
  _validateNonNegativeIntKeyword(schema, 'maxItems', path);
  _validateNonNegativeIntKeyword(schema, 'minLength', path);
  _validateNonNegativeIntKeyword(schema, 'maxLength', path);
  _validateBounds(schema, 'minItems', 'maxItems', path);
  _validateBounds(schema, 'minLength', 'maxLength', path);
  _validateNumericBounds(schema, path);
}

void _validateNonNegativeIntKeyword(
  Map<String, dynamic> schema,
  String keyword,
  String path,
) {
  if (!schema.containsKey(keyword)) {
    return;
  }
  final value = schema[keyword];
  if (value is! int || value < 0 || value > 2000) {
    throw LlamaUnsupportedException(
      'Unsupported structured JSON schema: $path.$keyword must be a '
      'non-negative integer at most 2000.',
    );
  }
}

void _validateBounds(
  Map<String, dynamic> schema,
  String minKeyword,
  String maxKeyword,
  String path,
) {
  final min = schema[minKeyword];
  final max = schema[maxKeyword];
  if (min is int && max is int && max < min) {
    throw LlamaUnsupportedException(
      'Unsupported structured JSON schema: $path.$maxKeyword must be greater '
      'than or equal to $path.$minKeyword.',
    );
  }
}

void _validateNestedSchemas(Map<String, dynamic> schema, String path) {
  final properties = schema['properties'];
  if (properties != null) {
    final propertySchemas = responseSchemaMap(properties, '$path.properties');
    for (final entry in propertySchemas.entries) {
      _validateSupportedSchemaSubset(
        responseSchemaMap(entry.value, '$path.properties.${entry.key}'),
        '$path.properties.${entry.key}',
      );
    }
  }

  final additionalProperties = schema['additionalProperties'];
  if (additionalProperties != null &&
      additionalProperties != true &&
      additionalProperties != false) {
    _validateSupportedSchemaSubset(
      responseSchemaMap(additionalProperties, '$path.additionalProperties'),
      '$path.additionalProperties',
    );
  }

  final items = schema['items'];
  if (items is List) {
    _validateSchemaList(items, '$path.items', allowEmpty: true);
  } else if (items != null) {
    _validateSupportedSchemaSubset(
      responseSchemaMap(items, '$path.items'),
      '$path.items',
    );
  }

  final prefixItems = schema['prefixItems'];
  if (prefixItems != null) {
    _validateSchemaList(prefixItems, '$path.prefixItems', allowEmpty: true);
  }

  for (final keyword in const ['oneOf', 'anyOf', 'allOf']) {
    final alternatives = schema[keyword];
    if (alternatives != null) {
      _validateSchemaList(alternatives, '$path.$keyword');
    }
  }
}

void _validateSchemaList(
  Object? value,
  String path, {
  bool allowEmpty = false,
}) {
  if (value is! List || (!allowEmpty && value.isEmpty)) {
    throw LlamaUnsupportedException(
      'Unsupported structured JSON schema: $path must be a non-empty list of '
      'schemas.',
    );
  }
  for (var i = 0; i < value.length; i++) {
    _validateSupportedSchemaSubset(
      responseSchemaMap(value[i], '$path[$i]'),
      '$path[$i]',
    );
  }
}

/// Reads a schema-bearing object with string keys, reporting errors at [path].
Map<String, dynamic> responseSchemaMap(Object? value, String path) {
  if (value is! Map) {
    throw LlamaUnsupportedException(
      'Unsupported structured JSON schema: $path must be a JSON object.',
    );
  }
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw LlamaUnsupportedException(
        'Unsupported structured JSON schema: $path must contain only string '
        'keys.',
      );
    }
    result[key] = entry.value;
  }
  return result;
}

bool _isTrivialAssertion(Map<String, dynamic> schema, String key) =>
    switch (key) {
      'uniqueItems' => schema[key] == false,
      'minProperties' => schema[key] == 0,
      'multipleOf' => schema[key] == 1 && schema['type'] == 'integer',
      _ => false,
    };

bool _isMetadata(String key) => !_assertionKeywords.contains(key);

Never _unsupported(String path, String reason) =>
    throw LlamaUnsupportedException(
      'Unsupported structured JSON schema: $path $reason.',
    );

void _validateDispatch(
  Map<String, dynamic> schema,
  Set<String>? types,
  String path,
) {
  for (final dispatch in ['anyOf', 'oneOf', 'const', 'enum']) {
    if (!schema.containsKey(dispatch)) continue;
    for (final key in schema.keys) {
      if (key == dispatch ||
          _isMetadata(key) ||
          _isTrivialAssertion(schema, key) ||
          (key == 'type' && (dispatch == 'const' || dispatch == 'enum'))) {
        continue;
      }
      _unsupported('$path.$key', 'is shadowed by $dispatch');
    }
    if ((dispatch == 'const' || dispatch == 'enum') && types != null) {
      final values = dispatch == 'const' ? [schema['const']] : schema['enum'];
      if (values is List) {
        for (final value in values) {
          final matches = types.any(
            (type) => switch (type) {
              'null' => value == null,
              'boolean' => value is bool,
              'integer' => value is num && value.isFinite && value % 1 == 0,
              'number' => value is num,
              'string' => value is String,
              'object' => value is Map,
              'array' => value is List,
              _ => false,
            },
          );
          if (!matches) _unsupported('$path.$dispatch', 'conflicts with type');
        }
      }
    }
  }
  if (schema.containsKey('pattern')) {
    final pattern = schema['pattern'];
    if (pattern is! String || !JsonSchemaConverter.supportsPattern(pattern)) {
      _unsupported('$path.pattern', 'is outside the compiled pattern subset');
    }
    for (final key in ['minLength', 'maxLength']) {
      if (schema.containsKey(key)) {
        _unsupported('$path.$key', 'is shadowed by pattern');
      }
    }
  }
  final tuple = schema['items'] is List
      ? schema['items']
      : schema['prefixItems'];
  if (schema.containsKey('prefixItems') && schema.containsKey('items')) {
    _unsupported('$path.items', 'cannot be combined with prefixItems');
  }
  if (tuple is List) {
    final min = schema['minItems'];
    final max = schema['maxItems'];
    if (min is num && min > tuple.length) {
      _unsupported('$path.minItems', 'exceeds the fixed tuple length');
    }
    if (max is num && max < tuple.length) {
      _unsupported('$path.maxItems', 'is below the fixed tuple length');
    }
  }
  final format = schema['format'];
  if (schema.containsKey('format')) {
    if (!{
      'uuid',
      'uuid1',
      'uuid2',
      'uuid3',
      'uuid4',
      'uuid5',
      'date',
      'time',
      'date-time',
    }.contains(format)) {
      _unsupported(
        '$path.format',
        'is not uuid, uuid1–uuid5, date, time or date-time',
      );
    }
    for (final key in ['pattern', 'minLength', 'maxLength']) {
      if (schema.containsKey(key)) {
        _unsupported('$path.$key', 'cannot be combined with format');
      }
    }
  }
  final required = schema['required'];
  if (required is List) {
    final properties = schema['properties'];
    for (final name in required) {
      if (properties is! Map || !properties.containsKey(name)) {
        _unsupported('$path.required', 'may only name declared properties');
      }
    }
  }
}

void _validateReferences(
  Map<String, dynamic> schema,
  Map<String, dynamic> root,
  String path,
  Set<String> positions,
  Set<String> visited,
) {
  final ref = schema[r'$ref'];
  if (ref is String) {
    if (!positions.contains(ref)) {
      _unsupported('$path.\$ref', 'must resolve to a local schema position');
    }
    if (visited.add(ref)) {
      final targetPath = '$path.\$ref';
      final target = responseSchemaMap(
        JsonSchemaConverter.resolvePointer(root, ref),
        targetPath,
      );
      _validateSupportedSchemaSubset(target, targetPath);
      _validateReferences(target, root, targetPath, positions, visited);
    }
  }
  final properties = schema['properties'];
  if (properties is Map) {
    for (final entry in properties.entries) {
      final childPath = '$path.properties.${entry.key}';
      _validateReferences(
        responseSchemaMap(entry.value, childPath),
        root,
        childPath,
        positions,
        visited,
      );
    }
  }
  for (final key in ['items', 'additionalProperties']) {
    final child = schema[key];
    if (child is Map) {
      _validateReferences(
        responseSchemaMap(child, '$path.$key'),
        root,
        '$path.$key',
        positions,
        visited,
      );
    }
  }
  for (final key in ['items', 'prefixItems', 'anyOf', 'oneOf', 'allOf']) {
    final children = schema[key];
    if (children is List) {
      for (var i = 0; i < children.length; i++) {
        _validateReferences(
          responseSchemaMap(children[i], '$path.$key[$i]'),
          root,
          '$path.$key[$i]',
          positions,
          visited,
        );
      }
    }
  }
  // allOf reads component enum lists only after reference targets are validated.
  _validateAllOf(schema, root, path);
}

Set<String> _schemaPositions(Map<String, dynamic> root) {
  final result = <String>{};
  void walk(Object? node, String pointer) {
    if (node is! Map) return;
    final schema = node;
    result.add(pointer);
    for (final key in ['properties', r'$defs', 'definitions']) {
      final children = schema[key];
      if (children is Map) {
        for (final entry in children.entries) {
          final escaped = (entry.key as String)
              .replaceAll('~', '~0')
              .replaceAll('/', '~1');
          walk(entry.value, '$pointer/$key/$escaped');
        }
      }
    }
    for (final key in ['items', 'additionalProperties']) {
      final child = schema[key];
      if (child is Map) walk(child, '$pointer/$key');
    }
    for (final key in ['items', 'prefixItems', 'anyOf', 'oneOf', 'allOf']) {
      final children = schema[key];
      if (children is List) {
        for (var i = 0; i < children.length; i++) {
          walk(children[i], '$pointer/$key/$i');
        }
      }
    }
  }

  walk(root, '#');
  return result;
}

void _validateNumericBounds(Map<String, dynamic> schema, String path) {
  const keys = ['minimum', 'maximum', 'exclusiveMinimum', 'exclusiveMaximum'];
  if (!keys.any(schema.containsKey)) return;
  final types = responseSchemaTypes(schema['type'], path);
  if (types == null || types.length != 1 || !types.contains('integer')) {
    _unsupported(
      '$path.${keys.firstWhere(schema.containsKey)}',
      'numeric bounds require type "integer"',
    );
  }
  for (final key in keys) {
    if (!schema.containsKey(key)) continue;
    final value = schema[key];
    // abs() of the VM's minimum int overflows to itself.
    if (value is! num ||
        value < -9007199254740991 ||
        value > 9007199254740991) {
      _unsupported(
        '$path.$key',
        'must be a number within the exact VM/Web integer range',
      );
    }
  }
  final (min, max) = JsonSchemaConverter.integerBounds(schema);
  if (min != null && max != null && min > max) {
    _unsupported(path, 'integer bounds have no supported integer interval');
  }
  if (!JsonSchemaConverter.supportsIntegerBounds(schema)) {
    _unsupported(
      path,
      'one-sided integer bounds are not enforced by the upstream suffix builder',
    );
  }
  if (schema.containsKey('minimum') &&
      schema.containsKey('exclusiveMinimum') &&
      min! <= (schema['exclusiveMinimum'] as num)) {
    _unsupported('$path.exclusiveMinimum', 'is shadowed by minimum');
  }
  if (schema.containsKey('maximum') &&
      schema.containsKey('exclusiveMaximum') &&
      max! >= (schema['exclusiveMaximum'] as num)) {
    _unsupported('$path.exclusiveMaximum', 'is shadowed by maximum');
  }
}

void _validateAllOf(
  Map<String, dynamic> schema,
  Map<String, dynamic> root,
  String path,
) {
  final components = schema['allOf'];
  if (components is! List) return;
  for (final key in schema.keys) {
    if (key != 'allOf' &&
        !_isMetadata(key) &&
        !_isTrivialAssertion(schema, key) &&
        key != 'type') {
      _unsupported('$path.$key', 'is shadowed by allOf');
    }
  }
  String? kind;
  final names = <String>{};
  Set<String>? intersection;
  var hasUnconstrained = false;
  for (var i = 0; i < components.length; i++) {
    var component = responseSchemaMap(components[i], '$path.allOf[$i]');
    final visited = <String>{};
    while (component[r'$ref'] is String) {
      final ref = component[r'$ref'] as String;
      if (!visited.add(ref)) {
        _unsupported('$path.allOf[$i]', 'has a cyclic component reference');
      }
      final target = JsonSchemaConverter.resolvePointer(root, ref);
      component = responseSchemaMap(target, '$path.allOf[$i].\$ref');
    }
    // Upstream's merge skips components without properties or enum values,
    // which is exact only for an object merge: its enum intersection still
    // counts the skipped component.
    if (component.keys.every(_isMetadata)) {
      hasUnconstrained = true;
      continue;
    }
    final componentKind = component.containsKey('enum') ? 'enum' : 'object';
    kind ??= componentKind;
    if (kind != componentKind) {
      _unsupported('$path.allOf[$i]', 'mixes enum and object components');
    }
    if (componentKind == 'enum') {
      if (schema['type'] != null &&
          (schema['type'] != 'string' ||
              !(component['enum'] as List).every((value) => value is String))) {
        _unsupported('$path.type', 'conflicts with an enum allOf');
      }
      final values = (component['enum'] as List)
          .map(JsonSchemaConverter.literalKey)
          .toSet();
      intersection = intersection == null
          ? values
          : intersection.intersection(values);
      continue;
    }
    final properties =
        component['properties'] ??
        (component['type'] == 'object' ? <String, dynamic>{} : null);
    if ((schema['type'] != null && schema['type'] != 'object') ||
        properties is! Map ||
        (component['type'] != null && component['type'] != 'object')) {
      _unsupported(
        '$path.allOf[$i]',
        'requires object properties or an enum intersection',
      );
    }
    if (component.containsKey('additionalProperties') &&
        component['additionalProperties'] != true &&
        !(component['additionalProperties'] == false &&
            components.length == 1)) {
      _unsupported(
        '$path.allOf[$i].additionalProperties',
        'is not enforced by the allOf property merge',
      );
    }
    for (final name in properties.keys.cast<String>()) {
      if (!names.add(name)) {
        _unsupported(
          '$path.allOf[$i].properties.$name',
          'duplicates a merged property',
        );
      }
    }
  }
  if (intersection != null && intersection.isEmpty) {
    _unsupported('$path.allOf', 'has an empty enum intersection');
  }
  if (hasUnconstrained && kind != 'object') {
    _unsupported(
      '$path.allOf',
      'needs an object properties component beside annotation-only components',
    );
  }
}
