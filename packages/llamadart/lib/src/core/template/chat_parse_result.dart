import 'dart:convert';
import '../models/chat/chat_message.dart';
import '../models/chat/chat_role.dart';
import '../models/chat/completion_chunk.dart';
import '../models/chat/content_part.dart';

/// The result of parsing raw LLM output into structured components.
///
/// Each [ChatTemplateHandler] produces this from the model's raw text output.
class ChatParseResult {
  /// The main text content (with tool calls and thinking stripped).
  final String content;

  /// Reasoning/thinking content extracted from `<think>` tags or similar.
  final String? reasoningContent;

  /// Parsed tool calls extracted from format-specific delimiters.
  final List<LlamaCompletionChunkToolCall> toolCalls;

  /// Creates a new parse result.
  const ChatParseResult({
    this.content = '',
    this.reasoningContent,
    this.toolCalls = const [],
  });

  /// Whether this result contains any tool calls.
  bool get hasToolCalls => toolCalls.isNotEmpty;

  /// Whether this result contains reasoning content.
  bool get hasReasoning =>
      reasoningContent != null && reasoningContent!.isNotEmpty;

  @override
  String toString() {
    final buf = StringBuffer('ChatParseResult(');
    final preview = content.length > 200
        ? '${content.substring(0, 200)}...'
        : content;
    buf.write('content: "$preview"');
    if (hasReasoning) {
      final rPreview = reasoningContent!.length > 100
          ? '${reasoningContent!.substring(0, 100)}...'
          : reasoningContent!;
      buf.write(', reasoning: "$rPreview"');
    }
    if (hasToolCalls) {
      buf.write(', toolCalls: [');
      for (final tc in toolCalls) {
        buf.write('${tc.function?.name}(${tc.function?.arguments}), ');
      }
      buf.write(']');
    }
    buf.write(')');
    return buf.toString();
  }

  /// Converts this parse result into a structured [LlamaChatMessage].
  ///
  /// This ensures that reasoning content is stored separately from the response
  /// text using [LlamaThinkingContent] and [LlamaTextContent] parts.
  LlamaChatMessage toAssistantMessage() {
    return LlamaChatMessage.withContent(
      role: LlamaChatRole.assistant,
      content: [
        if (hasReasoning) LlamaThinkingContent(reasoningContent!),
        LlamaTextContent(content),
        for (final tc in toolCalls)
          LlamaToolCallContent(
            id: tc.id,
            name: tc.function?.name ?? 'unknown',
            arguments: jsonDecode(tc.function?.arguments ?? '{}'),
            rawJson: tc.function?.arguments ?? '{}',
          ),
      ],
    );
  }
}
