import 'jinja/jinja_analyzer.dart';
import 'template_caps_cache.dart';

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

  /// Whether the template reads tool-call `arguments` as an object, so
  /// earlier tool calls are rendered with their arguments parsed from JSON.
  final bool supportsObjectArguments;

  /// Whether the template renders a `tool` message after an assistant tool
  /// call.
  ///
  /// `false` only when the template raises on that message but renders it
  /// under the `user` role, as Gemma 2/3/3n and legacy Mistral templates do
  /// with their role-alternation check. When such a template fails to render
  /// a request with tool results, `ChatTemplateEngine` retries it with the
  /// results as user turns, as llama.cpp's minja-based
  /// `supports_tool_responses` polyfill sent them. Not part of [toMap], which
  /// matches llama.cpp's current caps.
  final bool supportsToolResponses;

  /// Creates a [TemplateCaps] with the specified capabilities.
  const TemplateCaps({
    this.supportsSystemRole = true,
    this.supportsToolCalls = false,
    this.supportsTools = false,
    this.supportsParallelToolCalls = false,
    this.supportsStringContent = true,
    this.supportsTypedContent = false,
    this.supportsThinking = false,
    this.supportsObjectArguments = false,
    this.supportsToolResponses = true,
  });

  /// Detects capabilities with llama.cpp's capability probes, as
  /// [JinjaAnalyzer.analyzeWithOutcome] describes.
  ///
  /// Results are cached in [TemplateCapsCache.shared], a per-isolate LRU keyed
  /// by exact [templateSource] and bounded at
  /// [TemplateCapsCache.sharedCapacity] entries. A detection that reports
  /// `failed` (see [JinjaAnalyzer.analyzeWithOutcome]) is not cached, so it
  /// runs and logs again on every call.
  factory TemplateCaps.detect(String templateSource) {
    final cache = TemplateCapsCache.shared;
    final cached = cache.lookup(templateSource);
    if (cached != null) {
      return cached;
    }
    final outcome = JinjaAnalyzer.analyzeWithOutcome(templateSource);
    if (!outcome.failed) {
      cache.store(templateSource, outcome.caps);
    }
    return outcome.caps;
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
    'supports_object_arguments': supportsObjectArguments,
  };

  @override
  String toString() => 'TemplateCaps(${toMap()})';
}
