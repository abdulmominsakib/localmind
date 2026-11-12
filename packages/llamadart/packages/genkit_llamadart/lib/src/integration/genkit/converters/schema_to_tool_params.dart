import 'package:genkit/plugin.dart' as genkit;
import 'package:llamadart/llamadart.dart' as llama;

/// Maps an already owned, reference-resolved schema to legacy parameters.
List<llama.ToolParam> schemaToToolParams(Map<String, dynamic> schema) {
  _validateSchema(schema);
  if (_schemaType(schema) != 'object') {
    throw _schemaError('Tool input schemas must be object-shaped.');
  }
  return _mapObjectProperties(schema);
}

Map<String, dynamic> normalizeToolInputSchema(Map<String, dynamic> schema) {
  final copied =
      _copySchemaValue(schema, 0, _CopyBudget()) as Map<String, dynamic>;
  final modernDefinitions = copied[r'$defs'];
  final legacyDefinitions = copied['definitions'];
  if (modernDefinitions is Map &&
      legacyDefinitions is Map &&
      modernDefinitions.keys.any(legacyDefinitions.containsKey)) {
    throw _schemaError('Use unique names across local definition blocks.');
  }
  _checkReferences(copied, copied);
  return _resolveSchema(copied, copied, {}, 0, _CopyBudget());
}

Map<String, dynamic> _resolveSchema(
  Map<String, dynamic> schema,
  Map<String, dynamic> root,
  Set<String> references,
  int depth,
  _CopyBudget budget,
) {
  if (depth > 128 || ++budget.nodes > 16384) {
    throw _schemaError(
      'Resolved tool input schemas exceed the size or depth limit.',
    );
  }
  final ref = schema[r'$ref'];
  if (ref is String) {
    if (references.contains(ref)) {
      throw _schemaError('Local references must resolve without cycles.');
    }
    final parts = ref.split('/');
    final target = (root[parts[1]] as Map)[parts[2]] as Map<String, dynamic>;
    return {
      ..._resolveSchema(target, root, {...references, ref}, depth + 1, budget),
      for (final entry in schema.entries)
        if (_annotations.contains(entry.key) && entry.key != r'$schema')
          entry.key: entry.value,
    };
  }
  final result = <String, dynamic>{};
  for (final entry in schema.entries) {
    final value = entry.value;
    // This route uses the owner's fixed keyword subset, independent of dialect
    // annotations. Genkit injects a draft-07 URI which otherwise makes local
    // final validation fetch a meta-schema, breaking offline/browser use.
    if (entry.key == r'$defs' ||
        entry.key == 'definitions' ||
        entry.key == r'$schema') {
      continue;
    }
    if (entry.key == 'properties' && value is Map<String, dynamic>) {
      result[entry.key] = <String, dynamic>{
        for (final child in value.entries)
          child.key: child.value is Map<String, dynamic>
              ? _resolveSchema(
                  child.value as Map<String, dynamic>,
                  root,
                  references,
                  depth + 1,
                  budget,
                )
              : child.value,
      };
    } else if ({'items', 'additionalProperties'}.contains(entry.key) &&
        value is Map<String, dynamic>) {
      result[entry.key] = _resolveSchema(
        value,
        root,
        references,
        depth + 1,
        budget,
      );
    } else if ({'anyOf', 'oneOf', 'allOf'}.contains(entry.key) &&
        value is List) {
      result[entry.key] = [
        for (final child in value)
          child is Map<String, dynamic>
              ? _resolveSchema(child, root, references, depth + 1, budget)
              : child,
      ];
    } else {
      result[entry.key] = value;
    }
  }
  final type = result['type'];
  if (type is List && type.length == 1) result['type'] = type.single;
  if (!result.containsKey('type') && result['properties'] is Map) {
    result['type'] = 'object';
  }
  return result;
}

final class _CopyBudget {
  int nodes = 0;
}

Object? _copySchemaValue(Object? value, int depth, _CopyBudget budget) {
  if (depth > 128 || ++budget.nodes > 16384) {
    throw _schemaError(
      'Tool input schemas exceed the supported size or depth.',
    );
  }
  if (value is Map) {
    if (value.keys.any((key) => key is! String)) {
      throw _schemaError('Schema object keys must be strings.');
    }
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key as String: _copySchemaValue(entry.value, depth + 1, budget),
    };
  }
  if (value is List) {
    return value
        .map((item) => _copySchemaValue(item, depth + 1, budget))
        .toList();
  }
  if (value != null && value is! String && value is! bool && value is! num) {
    throw _schemaError('Tool input schemas must contain JSON values.');
  }
  if (value is num && !value.isFinite) {
    throw _schemaError('Tool input schemas must contain finite JSON numbers.');
  }
  return value;
}

const _annotations = {
  r'$schema',
  r'$id',
  r'$comment',
  'title',
  'description',
  'default',
  'examples',
  'deprecated',
  'readOnly',
  'writeOnly',
};

void _checkReferences(Map<String, dynamic> schema, Map<String, dynamic> root) {
  if (schema.containsKey(r'$ref')) {
    final ref = schema[r'$ref'];
    if (ref is! String ||
        !RegExp(r'^#/(\$defs|definitions)/[^/~]+$').hasMatch(ref)) {
      throw _schemaError(
        'Only local named \$defs/definitions references are supported.',
      );
    }
    final parts = ref.split('/');
    final definitions = root[parts[1]];
    if (definitions is! Map || definitions[parts[2]] is! Map<String, dynamic>) {
      throw _schemaError(
        'Local references must name a schema in the specified root definition block.',
      );
    }
    if (schema.keys.any(
      (key) =>
          key != r'$ref' &&
          key != r'$defs' &&
          key != 'definitions' &&
          !_annotations.contains(key),
    )) {
      throw _schemaError(
        'Constraints beside a local reference cannot be preserved; place them in its definition.',
      );
    }
  }
  for (final key in [r'$defs', 'definitions', 'properties']) {
    final children = schema[key];
    if (children is Map) {
      for (final child in children.values) {
        if (child is Map<String, dynamic>) _checkReferences(child, root);
      }
    }
  }
  for (final key in ['items', 'additionalProperties']) {
    final child = schema[key];
    if (child is Map<String, dynamic>) _checkReferences(child, root);
  }
  for (final key in ['anyOf', 'oneOf', 'allOf']) {
    final children = schema[key];
    if (children is List) {
      for (final child in children) {
        if (child is Map<String, dynamic>) _checkReferences(child, root);
      }
    }
  }
  if (!identical(schema, root) &&
      (schema.containsKey(r'$defs') || schema.containsKey('definitions'))) {
    throw _schemaError('Local definitions must be declared at the root.');
  }
}

void _validateSchema(Map<String, dynamic> schema) {
  final type = _schemaType(schema);
  final allowed = {
    ..._annotations,
    'type',
    if (type == 'string') 'enum',
    if (type == 'object') ...['properties', 'required', 'additionalProperties'],
    if (type == 'array') 'items',
  };
  for (final key in schema.keys) {
    if (!allowed.contains(key)) {
      throw _schemaError(
        'The "$key" keyword cannot be preserved by llamadart ToolParam.',
      );
    }
  }
  if (schema.containsKey('description') && schema['description'] is! String) {
    throw _schemaError('Descriptions must be strings.');
  }
  if (schema.containsKey('enum')) {
    final values = schema['enum'];
    if (values is! List ||
        values.isEmpty ||
        values.any((value) => value is! String)) {
      throw _schemaError('Only nonempty string enums are supported.');
    }
  }
  if (type == 'object') {
    if (schema.containsKey('additionalProperties') &&
        schema['additionalProperties'] != true) {
      throw _schemaError(
        'additionalProperties constraints cannot be preserved by llamadart ToolParam.',
      );
    }
    final properties = schema['properties'];
    if (schema.containsKey('properties') &&
        properties is! Map<String, dynamic>) {
      throw _schemaError('Object properties must be a map of schemas.');
    }
    final required = schema['required'];
    if (schema.containsKey('required') &&
        (required is! List ||
            required.any(
              (name) =>
                  name is! String ||
                  (properties as Map?)?.containsKey(name) != true,
            ) ||
            required.toSet().length != required.length)) {
      throw _schemaError('Required names must be unique declared properties.');
    }
    for (final entry in (properties as Map<String, dynamic>? ?? {}).entries) {
      if (entry.key.isEmpty || entry.value is! Map<String, dynamic>) {
        throw _schemaError('Properties need nonempty names and typed schemas.');
      }
      _validateSchema(entry.value as Map<String, dynamic>);
    }
  }
  if (type == 'array') {
    final items = schema['items'];
    if (items is! Map<String, dynamic>) {
      throw _schemaError('Arrays require a single typed items schema.');
    }
    _validateSchema(items);
  }
}

String _schemaType(Map<String, dynamic> schema) {
  final raw = schema['type'];
  final type = raw is List && raw.length == 1 ? raw.single : raw;
  if (type is String &&
      const {
        'string',
        'integer',
        'number',
        'boolean',
        'null',
        'object',
        'array',
      }.contains(type)) {
    return type;
  }
  if (!schema.containsKey('type')) {
    if (schema['properties'] is Map) return 'object';
    final values = schema['enum'];
    if (values is List &&
        values.isNotEmpty &&
        values.every((value) => value is String)) {
      return 'string';
    }
  }
  throw _schemaError(
    'A supported single type is required; nullable unions and unknown types cannot be preserved.',
  );
}

llama.ToolParam _mapSchemaToToolParam(
  String name,
  Map<String, dynamic> schema, {
  required bool required,
}) {
  final description = schema['description'] as String?;
  final values = schema['enum'];
  if (values is List) {
    return llama.ToolParam.enumType(
      name,
      values: values.cast<String>(),
      description: description,
      required: required,
    );
  }
  return switch (_schemaType(schema)) {
    'string' => llama.ToolParam.string(
      name,
      description: description,
      required: required,
    ),
    'integer' => llama.ToolParam.integer(
      name,
      description: description,
      required: required,
    ),
    'number' => llama.ToolParam.number(
      name,
      description: description,
      required: required,
    ),
    'boolean' => llama.ToolParam.boolean(
      name,
      description: description,
      required: required,
    ),
    'null' => llama.ToolParam.nullType(
      name,
      description: description,
      required: required,
    ),
    'array' => llama.ToolParam.array(
      name,
      itemType: _mapSchemaToToolParam(
        '${name}_item',
        schema['items'] as Map<String, dynamic>,
        required: false,
      ),
      description: description,
      required: required,
    ),
    'object' => llama.ToolParam.object(
      name,
      properties: _mapObjectProperties(schema),
      description: description,
      required: required,
    ),
    _ => throw _schemaError('Unsupported parameter type.'),
  };
}

List<llama.ToolParam> _mapObjectProperties(Map<String, dynamic> schema) {
  final properties = schema['properties'] as Map<String, dynamic>? ?? {};
  final required = (schema['required'] as List? ?? []).cast<String>().toSet();
  return [
    for (final entry in properties.entries)
      _mapSchemaToToolParam(
        entry.key,
        entry.value as Map<String, dynamic>,
        required: required.contains(entry.key),
      ),
  ];
}

genkit.GenkitException _schemaError(String detail) => genkit.GenkitException(
  'llamadart tool input schema: $detail Use object inputs with primitive types, string enums, nested objects or typed arrays.',
  status: genkit.StatusCode.invalidArgument,
);
