/// Represents a single parameter in a tool's input schema.
///
/// Use the static factory methods to create parameters of different types:
/// - [ToolParam.string] for string parameters
/// - [ToolParam.integer] for integer parameters
/// - [ToolParam.number] for floating-point parameters
/// - [ToolParam.boolean] for boolean parameters
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
