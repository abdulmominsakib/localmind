/// Controls which tool(s) the model should call.
///
/// Matches OpenAI's `tool_choice` parameter behavior.
enum ToolChoice {
  /// Model will not call any tool and generates a message instead.
  none,

  /// Model can choose between generating a message or calling tools.
  /// This is the default when tools are present.
  auto,

  /// Model must call one or more tools.
  required,
}
