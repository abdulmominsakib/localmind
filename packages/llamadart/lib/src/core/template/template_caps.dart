import 'jinja/jinja_analyzer.dart';

/// Template capabilities detected from Jinja template source analysis.
///
/// Matches llama.cpp's `common_chat_template::caps`.
///
/// Detection uses an execution probe against the Jinja template with
/// llama.cpp-like synthetic message/tool payloads, with AST/regex fallbacks.
class TemplateCaps {
  /// Whether the template supports a system role.
  final bool supportsSystemRole;

  /// Whether the template references tool calls in output.
  final bool supportsToolCalls;

  /// Whether the template accepts a `tools` variable.
  final bool supportsTools;

  /// Whether the template supports parallel tool calls.
  final bool supportsParallelToolCalls;

  /// Whether the template expects content as a plain string.
  final bool supportsStringContent;

  /// Whether the template expects content as typed parts
  /// (e.g., `[{type: 'text', text: '...'}, {type: 'image'}]`).
  final bool supportsTypedContent;

  /// Whether the template supports thinking/reasoning tags.
  final bool supportsThinking;

  /// Creates a [TemplateCaps] with the specified capabilities.
  const TemplateCaps({
    this.supportsSystemRole = true,
    this.supportsToolCalls = false,
    this.supportsTools = false,
    this.supportsParallelToolCalls = false,
    this.supportsStringContent = true,
    this.supportsTypedContent = false,
    this.supportsThinking = false,
  });

  /// Detects capabilities by scanning the template source string.
  ///
  /// Uses the same approach as llama.cpp (`src.find()` on raw template text).
  factory TemplateCaps.detect(String templateSource) {
    return JinjaAnalyzer.analyze(templateSource);
  }

  /// Detects capabilities using regex/string matching (fallback method).
  factory TemplateCaps.detectRegex(String templateSource) {
    final src = templateSource;

    // System role: check for 'system' in role assignments
    final supportsSystemRole =
        src.contains("'system'") || src.contains('"system"');

    // Tool calls: template outputs tool_call markers
    final supportsToolCalls =
        src.contains('tool_call') ||
        src.contains('tool_calls') ||
        src.contains('TOOL_CALLS') ||
        src.contains('tool▁call');

    // Tools: template accepts tools variable
    final supportsTools = src.contains('tools');

    // Parallel tool calls: template iterates tool_calls
    final supportsParallelToolCalls =
        src.contains('tool_calls') && src.contains('for ');

    // Typed content: template accesses content as list/iterable
    final supportsTypedContent =
        src.contains("'content'][") ||
        src.contains('content is iterable') ||
        src.contains('content is not string') ||
        src.contains('content is mapping');

    // String content: most templates expect string content (default true
    // unless typed content is exclusively used)
    final supportsStringContent = true;

    // Thinking: template uses thinking/reasoning tags
    final supportsThinking =
        src.contains('<think>') ||
        src.contains('<|think|>') ||
        src.contains('<|channel>thought') ||
        src.contains('thinking') ||
        src.contains('<|START_THINKING|>') ||
        src.contains('[THINK]') ||
        src.contains('<seed:think>');

    return TemplateCaps(
      supportsSystemRole: supportsSystemRole,
      supportsToolCalls: supportsToolCalls,
      supportsTools: supportsTools,
      supportsParallelToolCalls: supportsParallelToolCalls,
      supportsStringContent: supportsStringContent,
      supportsTypedContent: supportsTypedContent,
      supportsThinking: supportsThinking,
    );
  }

  /// Converts to a map for reporting (matches llama.cpp's `caps.to_map()`).
  Map<String, bool> toMap() => {
    'supports_system_role': supportsSystemRole,
    'supports_tool_calls': supportsToolCalls,
    'supports_tools': supportsTools,
    'supports_parallel_tool_calls': supportsParallelToolCalls,
    'supports_string_content': supportsStringContent,
    'supports_typed_content': supportsTypedContent,
    'supports_thinking': supportsThinking,
  };

  @override
  String toString() => 'TemplateCaps(${toMap()})';
}
