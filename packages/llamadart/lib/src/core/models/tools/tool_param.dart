/// Represents a single parameter in a tool's input schema.
///
/// Use the static factory methods to create parameters of different types:
/// - [ToolParam.string] for string parameters
/// - [ToolParam.integer] for integer parameters
/// - [ToolParam.number] for floating-point parameters
/// - [ToolParam.boolean] for boolean parameters
/// - [ToolParam.nullType] for parameters whose only valid value is `null`
/// - [ToolParam.enumType] for enum parameters with allowed values
/// - [ToolParam.array] for array parameters
/// - [ToolParam.object] for nested object parameters
sealed class ToolParam {
  /// The parameter name.
  final String name;

  /// Human-readable description of the parameter.
  final String? description;

  /// Whether this parameter is required.
  final bool required;

  const ToolParam._({
    required this.name,
    this.description,
    this.required = false,
  });

  /// Creates a string parameter.
  static ToolParam string(
    String name, {
    String? description,
    bool required = false,
  }) => _StringParam(name: name, description: description, required: required);

  /// Creates an integer parameter.
  static ToolParam integer(
    String name, {
    String? description,
    bool required = false,
  }) => _IntegerParam(name: name, description: description, required: required);

  /// Creates a number (floating-point) parameter.
  static ToolParam number(
    String name, {
    String? description,
    bool required = false,
  }) => _NumberParam(name: name, description: description, required: required);

  /// Creates a boolean parameter.
  static ToolParam boolean(
    String name, {
    String? description,
    bool required = false,
  }) => _BooleanParam(name: name, description: description, required: required);

  /// Creates a parameter whose only valid JSON value is `null`.
  static ToolParam nullType(
    String name, {
    String? description,
    bool required = false,
  }) => _NullParam(name: name, description: description, required: required);

  /// Creates an enum parameter with a list of allowed values.
  static ToolParam enumType(
    String name, {
    required List<String> values,
    String? description,
    bool required = false,
  }) => _EnumParam(
    name: name,
    values: values,
    description: description,
    required: required,
  );

  /// Creates an array parameter with items of the specified type.
  static ToolParam array(
    String name, {
    required ToolParam itemType,
    String? description,
    bool required = false,
  }) => _ArrayParam(
    name: name,
    itemType: itemType,
    description: description,
    required: required,
  );

  /// Creates a nested object parameter with its own properties.
  static ToolParam object(
    String name, {
    required List<ToolParam> properties,
    String? description,
    bool required = false,
  }) => _ObjectParam(
    name: name,
    properties: properties,
    description: description,
    required: required,
  );

  /// Converts this parameter definition to a JSON Schema property map.
  Map<String, dynamic> toJsonSchema();
}

/// Returns an actionable identity error for [parameters], or `null` when every
/// object property name is non-empty and unique within its containing object.
///
/// Array item names are not represented in JSON Schema and are therefore not
/// validated, but object properties nested inside array items are.
String? toolParamIdentityError(
  List<ToolParam> parameters, {
  required String path,
}) {
  final names = <String>{};
  for (final parameter in parameters) {
    if (parameter.name.isEmpty) {
      return 'Structured tool schemas require non-empty parameter names at '
          '$path.';
    }
    if (!names.add(parameter.name)) {
      return 'Structured tool schemas require unique parameter names at '
          '$path; "${parameter.name}" is declared more than once.';
    }
  }

  for (final parameter in parameters) {
    final nestedPath = '$path.${parameter.name}';
    final error = _nestedToolParamIdentityError(parameter, nestedPath);
    if (error != null) {
      return error;
    }
  }
  return null;
}

String? _nestedToolParamIdentityError(ToolParam parameter, String path) {
  if (parameter is _ObjectParam) {
    return toolParamIdentityError(parameter.properties, path: path);
  }
  if (parameter is _ArrayParam) {
    return _nestedToolParamIdentityError(parameter.itemType, '$path[]');
  }
  return null;
}

final class _StringParam extends ToolParam {
  const _StringParam({required super.name, super.description, super.required})
    : super._();

  @override
  Map<String, dynamic> toJsonSchema() => {
    'type': 'string',
    if (description != null) 'description': description,
  };
}

final class _IntegerParam extends ToolParam {
  const _IntegerParam({required super.name, super.description, super.required})
    : super._();

  @override
  Map<String, dynamic> toJsonSchema() => {
    'type': 'integer',
    if (description != null) 'description': description,
  };
}

final class _NumberParam extends ToolParam {
  const _NumberParam({required super.name, super.description, super.required})
    : super._();

  @override
  Map<String, dynamic> toJsonSchema() => {
    'type': 'number',
    if (description != null) 'description': description,
  };
}

final class _BooleanParam extends ToolParam {
  const _BooleanParam({required super.name, super.description, super.required})
    : super._();

  @override
  Map<String, dynamic> toJsonSchema() => {
    'type': 'boolean',
    if (description != null) 'description': description,
  };
}

final class _NullParam extends ToolParam {
  const _NullParam({required super.name, super.description, super.required})
    : super._();

  @override
  Map<String, dynamic> toJsonSchema() => {
    'type': 'null',
    if (description != null) 'description': description,
  };
}

final class _EnumParam extends ToolParam {
  final List<String> values;

  const _EnumParam({
    required super.name,
    required this.values,
    super.description,
    super.required,
  }) : super._();

  @override
  Map<String, dynamic> toJsonSchema() => {
    'type': 'string',
    'enum': values,
    if (description != null) 'description': description,
  };
}

final class _ArrayParam extends ToolParam {
  final ToolParam itemType;

  const _ArrayParam({
    required super.name,
    required this.itemType,
    super.description,
    super.required,
  }) : super._();

  @override
  Map<String, dynamic> toJsonSchema() => {
    'type': 'array',
    'items': itemType.toJsonSchema(),
    if (description != null) 'description': description,
  };
}

final class _ObjectParam extends ToolParam {
  final List<ToolParam> properties;

  const _ObjectParam({
    required super.name,
    required this.properties,
    super.description,
    super.required,
  }) : super._();

  @override
  Map<String, dynamic> toJsonSchema() {
    final props = <String, dynamic>{};
    final requiredList = <String>[];

    for (final param in properties) {
      props[param.name] = param.toJsonSchema();
      if (param.required) {
        requiredList.add(param.name);
      }
    }

    return {
      'type': 'object',
      'properties': props,
      if (requiredList.isNotEmpty) 'required': requiredList,
      if (description != null) 'description': description,
    };
  }
}
