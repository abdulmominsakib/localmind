import 'dart:convert';

import '../models/chat/chat_message.dart';
import '../models/chat/chat_role.dart';
import '../models/chat/content_part.dart';
import 'tool_call_parsing_utils.dart';

/// Tool-call serialization policy for template render contexts.
///
/// The policy describes the JSON shape a handler's Jinja template expects. It
/// keeps compatibility formatting at the render-context boundary instead of
/// mutating typed [LlamaChatMessage] instances before rendering.
class TemplateToolCallSerialization {
  /// Whether function-call `arguments` should be JSON objects rather than JSON
  /// strings.
  final bool normalizeArguments;

  /// Whether OpenAI-style tool-call entries should be converted to the shorter
  /// generic schema (`name`, `arguments`, `id`).
  final bool useGenericSchema;

  /// Whether tool calls should be appended to `content` as a JSON object and the
  /// top-level `tool_calls` field removed.
  final bool moveToolCallsToContent;

  /// Creates a template tool-call serialization policy.
  const TemplateToolCallSerialization({
    this.normalizeArguments = false,
    this.useGenericSchema = false,
    this.moveToolCallsToContent = false,
  });

  /// No tool-call serialization changes.
  static const none = TemplateToolCallSerialization();

  /// Normalize tool-call argument values to JSON objects.
  static const normalizeOnly = TemplateToolCallSerialization(
    normalizeArguments: true,
  );

  /// Normalize tool calls, convert to generic schema, then move the result into
  /// message content.
  static const genericSchemaInContent = TemplateToolCallSerialization(
    normalizeArguments: true,
    useGenericSchema: true,
    moveToolCallsToContent: true,
  );

  /// Whether no tool-call serialization transformations are enabled.
  bool get isEmpty =>
      !normalizeArguments && !useGenericSchema && !moveToolCallsToContent;

  @override
  bool operator ==(Object other) {
    return other is TemplateToolCallSerialization &&
        other.normalizeArguments == normalizeArguments &&
        other.useGenericSchema == useGenericSchema &&
        other.moveToolCallsToContent == moveToolCallsToContent;
  }

  @override
  int get hashCode =>
      Object.hash(normalizeArguments, useGenericSchema, moveToolCallsToContent);
}

/// Builds Jinja render-context values from typed chat messages.
///
/// This class owns template-facing JSON serialization. It deliberately avoids
/// converting the rendered JSON maps back into [LlamaChatMessage] instances so
/// typed multimodal parts remain first-class until the final context build.
class TemplateRenderContext {
  static const JsonEncoder _defaultToolCallEncoder = JsonEncoder.withIndent(
    '  ',
  );

  /// Serializes [messages] into the JSON shape expected by a template handler.
  static List<Map<String, dynamic>> messagesForTemplate(
    List<LlamaChatMessage> messages, {
    TemplateToolCallSerialization toolCallSerialization =
        TemplateToolCallSerialization.none,
    bool multimodal = false,
  }) {
    final renderedMessages = <Map<String, dynamic>>[];
    var hasToolCalls = false;
    for (final message in messages) {
      final rendered = multimodal
          ? message.toJsonMultimodal()
          : message.toJson();
      if (rendered['tool_calls'] is List) {
        hasToolCalls = true;
      }
      renderedMessages.add(rendered);
    }

    if (toolCallSerialization.isEmpty || !hasToolCalls) {
      return renderedMessages;
    }

    if (toolCallSerialization.normalizeArguments) {
      normalizeToolCallArgs(renderedMessages);
    }
    if (toolCallSerialization.useGenericSchema) {
      useGenericSchema(renderedMessages);
    }
    if (toolCallSerialization.moveToolCallsToContent) {
      moveToolCallsToContent(renderedMessages, preserveContentList: multimodal);
    }

    return renderedMessages;
  }

  /// Merges a leading system message into the next message when a template does
  /// not support the system role.
  static List<LlamaChatMessage> mergeLeadingSystemMessage(
    List<LlamaChatMessage> messages, {
    required bool supportsSystemRole,
  }) {
    if (supportsSystemRole) return messages;
    if (messages.isEmpty) return messages;
    if (messages.first.role != LlamaChatRole.system) return messages;

    final result = List<LlamaChatMessage>.from(messages);
    final systemMsg = result.removeAt(0);
    if (result.isEmpty) return result;

    final next = result.first;
    result[0] = _mergeSystemTextIntoMessage(systemMsg.content, next);
    return result;
  }

  /// Ensures tool-call arguments are JSON objects, not strings.
  static void normalizeToolCallArgs(List<Map<String, dynamic>> messages) {
    for (final message in messages) {
      final toolCalls = message['tool_calls'];
      if (toolCalls is! List) continue;

      for (var i = 0; i < toolCalls.length; i++) {
        final item = toolCalls[i];
        final toolCall = item is Map<String, dynamic>
            ? item
            : ToolCallParsingUtils.coerceMap(item);
        if (toolCall == null) continue;
        if (!identical(toolCall, item)) {
          toolCalls[i] = toolCall;
        }

        final function = ToolCallParsingUtils.coerceMap(toolCall['function']);
        if (function != null) {
          if (function.containsKey('arguments')) {
            function['arguments'] = _argumentsToObject(function['arguments']);
          }
          toolCall['function'] = function;
          continue;
        }

        if (toolCall.containsKey('arguments')) {
          toolCall['arguments'] = _argumentsToObject(toolCall['arguments']);
        }
      }
    }
  }

  /// Converts OpenAI-style tool-call schema into generic short schema.
  static void useGenericSchema(List<Map<String, dynamic>> messages) {
    for (final message in messages) {
      final toolCalls = message['tool_calls'];
      if (toolCalls is! List) continue;

      for (var i = 0; i < toolCalls.length; i++) {
        final call = toolCalls[i];
        if (call is! Map<String, dynamic>) continue;

        final type = call['type'];
        final function = call['function'];
        if (type != 'function' || function is! Map<String, dynamic>) {
          continue;
        }

        Object? name;
        Object? arguments;
        Object? id;
        if (function.containsKey('name')) {
          name = function['name'];
        }
        if (function.containsKey('arguments')) {
          arguments = function['arguments'];
        }
        if (call.containsKey('id')) {
          id = call['id'];
        }

        call.clear();
        if (name != null) {
          call['name'] = name;
        }
        if (arguments != null) {
          call['arguments'] = arguments;
        }
        if (id != null) {
          call['id'] = id;
        }
      }
    }
  }

  /// Moves tool calls into message content as a JSON string.
  static void moveToolCallsToContent(
    List<Map<String, dynamic>> messages, {
    int indentSpaces = 2,
    bool preserveContentList = false,
  }) {
    for (final message in messages) {
      final toolCalls = message['tool_calls'];
      if (toolCalls is! List) continue;

      final currentContent = message['content'];
      final payload = {'tool_calls': toolCalls};
      final toolCallsJson = indentSpaces <= 0
          ? jsonEncode(payload)
          : indentSpaces == 2
          ? _defaultToolCallEncoder.convert(payload)
          : JsonEncoder.withIndent(' ' * indentSpaces).convert(payload);

      if (preserveContentList) {
        final parts = _contentAsTextParts(currentContent);
        parts.add({'type': 'text', 'text': toolCallsJson});
        message['content'] = parts;
      } else {
        final contentText = _contentAsText(currentContent);
        message['content'] = '$contentText$toolCallsJson';
      }
      message.remove('tool_calls');
    }
  }

  static String _contentAsText(Object? content) {
    if (content == null) return '';
    if (content is List) {
      final buffer = StringBuffer();
      for (final item in content) {
        if (item is String) {
          buffer.write(item);
        } else if (item is Map<String, dynamic>) {
          final text = item['text'];
          if (text is String) {
            buffer.write(text);
          }
        }
      }
      return buffer.toString();
    }
    return content.toString();
  }

  static List<Map<String, dynamic>> _contentAsTextParts(Object? content) {
    if (content is List) {
      return [
        for (final item in content)
          if (item is Map<String, dynamic>) Map<String, dynamic>.from(item),
      ];
    }

    if (content == null) return <Map<String, dynamic>>[];
    final text = content.toString();
    if (text.isEmpty) return <Map<String, dynamic>>[];
    return [
      {'type': 'text', 'text': text},
    ];
  }

  static LlamaChatMessage _mergeSystemTextIntoMessage(
    String systemText,
    LlamaChatMessage message,
  ) {
    if (message.parts.isEmpty) {
      return LlamaChatMessage.fromText(role: message.role, text: systemText);
    }

    final firstPart = message.parts.first;
    if (firstPart is LlamaTextContent) {
      return LlamaChatMessage.withContent(
        role: message.role,
        content: [
          LlamaTextContent('$systemText\n${firstPart.text}'),
          ...message.parts.skip(1),
        ],
      );
    }

    return LlamaChatMessage.withContent(
      role: message.role,
      content: [LlamaTextContent(systemText), ...message.parts],
    );
  }

  static Map<String, dynamic> _argumentsToObject(Object? args) {
    final map = ToolCallParsingUtils.decodeJsonMapValue(args);
    if (map != null) {
      return map;
    }

    if (args is String) {
      throw const FormatException('Tool call arguments must be a JSON object.');
    }

    if (args == null) {
      return <String, dynamic>{};
    }

    throw FormatException(
      'Unsupported tool call argument type: ${args.runtimeType}',
    );
  }
}
