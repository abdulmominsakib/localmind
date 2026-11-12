import 'dart:convert';

import '../../exceptions.dart';
import 'tool_input_schema.dart';
import 'tool_param.dart';
import 'tool_params.dart';

/// Signature for a tool handler function.
///
/// The handler receives parsed [ToolParams] and returns the tool's result
/// (e.g. String, Map, List), or a `LlamaToolOutput` for text or media after
/// it, or throws an exception on error.
typedef ToolHandler = Future<Object?> Function(ToolParams params);

/// Defines a tool that the LLM can invoke.
///
/// A tool definition includes:
/// - A unique [name] that the model uses to reference the tool.
/// - A [description] explaining what the tool does (helps the model decide when to use it).
/// - A list of [parameters] defining the expected input schema.
/// - An optional [handler] function that executes the tool logic.
///
/// `ChatSession.sendWithTools` runs the [handler] of each tool the model
/// calls. Leave it out for a tool the app runs itself, such as one that needs
/// user approval or is executed by a remote client.
///
/// Example:
/// ```dart
/// final weatherTool = ToolDefinition(
///   name: 'get_weather',
///   description: 'Get the current weather for a location',
///   parameters: [
///     ToolParam.string('location', description: 'City name', required: true),
///     ToolParam.enumType('unit', values: ['celsius', 'fahrenheit']),
///   ],
///   handler: (params) async {
///     final location = params.getRequiredString('location');
///     final unit = params.getString('unit') ?? 'celsius';
///     // Fetch weather...
///     return 'Weather in $location: 22°$unit';
///   },
/// );
/// ```
class ToolDefinition {
  /// Unique name for the tool (e.g., "get_weather").
  final String name;

  /// Human-readable description of what the tool does.
  final String description;

  /// List of parameter definitions for the tool's input.
  final List<ToolParam> parameters;

  /// The function that executes the tool logic, or `null` when the app runs
  /// the tool itself.
  final ToolHandler? handler;

  /// Creates a new [ToolDefinition].
  const ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
    this.handler,
  });

  /// Creates a tool with an owned JSON Schema rather than parameter helpers.
  ///
  /// The root must be an object. Scalar types, nested objects/arrays, scalar
  /// enum/const, type alternatives, anyOf and length/item bounds are supported.
  /// References, patterns, numeric bounds and oneOf/allOf throw
  /// [LlamaUnsupportedException]; malformed schemas throw [LlamaArgumentException].
  /// Missing object property policy follows JSON Schema (additionalProperties:
  /// true). The legacy constructor retains its existing closed-property policy.
  /// Specialized formats have a narrower supported subset and reject unsupported
  /// constraints before generation. Schemas beyond the documented size limits
  /// (nesting, subschema count, anyOf/enum size, length/item bounds above
  /// llama.cpp's repetition limit, generated grammar size) throw
  /// [LlamaUnsupportedException]. See doc/tool_input_schemas.md.
  ///
  /// [parameters] is empty for this constructor; consumers must use
  /// [toJsonSchema] as the canonical schema. Returned maps are fresh copies in
  /// which every object schema has explicit `properties` and
  /// `additionalProperties`.
  factory ToolDefinition.fromJsonSchema({
    required String name,
    required String description,
    required Map<String, dynamic> schema,
    ToolHandler? handler,
  }) => _JsonSchemaToolDefinition(
    name: name,
    description: description,
    schema: copyToolInputSchema(schema),
    handler: handler,
  );

  /// Converts the tool's parameters to a JSON Schema object.
  ///
  /// This is used internally to generate GBNF grammar or for API compatibility.
  Map<String, dynamic> toJsonSchema() {
    final properties = <String, dynamic>{};
    final requiredList = <String>[];

    for (final param in parameters) {
      properties[param.name] = param.toJsonSchema();
      if (param.required) {
        requiredList.add(param.name);
      }
    }

    return {
      'type': 'object',
      'properties': properties,
      if (requiredList.isNotEmpty) 'required': requiredList,
    };
  }

  /// Converts the tool definition to an OpenAI-compatible JSON object.
  Map<String, dynamic> toJson() {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': toJsonSchema(),
      },
    };
  }

  /// Invokes the tool's handler with the given [args].
  ///
  /// The [args] map is wrapped in [ToolParams] for type-safe access.
  ///
  /// Throws [LlamaStateException] when the tool has no [handler].
  Future<Object?> invoke(Map<String, dynamic> args) async {
    final handler = this.handler;
    if (handler == null) {
      throw LlamaStateException('Tool "$name" has no handler to invoke.');
    }
    return handler(ToolParams(args));
  }

  @override
  String toString() => 'ToolDefinition($name)';
}

/// Whether the tool opts into canonical JSON Schema input semantics.
/// Internal consumer seam; not exported by the package barrel.
bool toolUsesJsonSchema(ToolDefinition tool) =>
    tool is _JsonSchemaToolDefinition;

final class _JsonSchemaToolDefinition extends ToolDefinition {
  _JsonSchemaToolDefinition({
    required super.name,
    required super.description,
    required Map<String, dynamic> schema,
    super.handler,
  }) : _schema = schema,
       super(parameters: const []);
  final Map<String, dynamic> _schema;

  @override
  Future<Object?> invoke(Map<String, dynamic> args) async {
    if (handler != null && !validateToolInputValue(args, _schema).valid) {
      throw LlamaArgumentException(
        'Tool arguments do not match the input schema for "$name".',
      );
    }
    return await super.invoke(args);
  }

  @override
  Map<String, dynamic> toJsonSchema() =>
      jsonDecode(jsonEncode(_schema)) as Map<String, dynamic>;
}
