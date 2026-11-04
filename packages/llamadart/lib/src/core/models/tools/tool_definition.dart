import 'tool_param.dart';
import 'tool_params.dart';

/// Signature for a tool handler function.
///
/// The handler receives parsed [ToolParams] and returns the tool's result
/// (e.g. String, Map, List) or throws an exception on error.
typedef ToolHandler = Future<Object?> Function(ToolParams params);

/// Defines a tool that the LLM can invoke.
///
/// A tool definition includes:
/// - A unique [name] that the model uses to reference the tool.
/// - A [description] explaining what the tool does (helps the model decide when to use it).
/// - A list of [parameters] defining the expected input schema.
/// - A [handler] function that executes the tool logic.
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

  /// The function that executes the tool logic.
  final ToolHandler handler;

  /// Creates a new [ToolDefinition].
  const ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
    required this.handler,
  });

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
  Future<Object?> invoke(Map<String, dynamic> args) async {
    return handler(ToolParams(args));
  }

  @override
  String toString() => 'ToolDefinition($name)';
}
