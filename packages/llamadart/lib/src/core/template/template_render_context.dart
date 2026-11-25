import 'dart:convert';

import '../models/chat/chat_message.dart';
import '../models/chat/chat_role.dart';
import '../models/chat/content_part.dart';
import '../models/chat/tool_result_parts.dart';
import 'media_placeholders.dart';
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

  /// Serializes [messages] into the JSON shape expected by a template handler,
  /// as llama.cpp's `common_chat_msg::to_json_oaicompat` builds template input.
  ///
  /// An absent `content` becomes an empty string. Typed tool results become
  /// JSON text; string results and the original typed messages are
  /// unchanged. A message with several tool results becomes one message per
  /// result, as [splitToolResults] describes.
  ///
  /// With [multimodal], the text of a message holds [mediaMarker] where each
  /// image, audio or video part was. llama.cpp also gives a template the
  /// marker and never the media part: the placeholder a template writes for a
  /// typed image part is not the marker mtmd matches, and mtmd adds the image
  /// begin and end tokens itself.
  ///
  /// When [typedContentOnly] marks a template that reads content only as a
  /// list of parts, every string `content` becomes a list holding one text
  /// part, as llama.cpp's `messages_inp_normalizer` does.
  ///
  /// A tool result's `content` becomes text with [mediaMarker] at each
  /// media part, as [withToolResultMediaMarkers] describes. Text-only
  /// `content` stays a list of text parts, or, when [stringContentOnly] marks
  /// a template that reads only string content, one string joined as the
  /// same normalizer's `concat_content_parts` joins it: a newline goes before
  /// a part only when the text so far is not empty.
  ///
  /// With [objectArguments], tool-call `arguments` that decode to a JSON
  /// object are passed as that object, as llama.cpp does for templates with
  /// `supports_object_arguments`; other arguments stay strings.
  ///
  /// With [toolResultsAsUser], for a template that rejects the `tool` role,
  /// each run of consecutive `tool` messages and an immediately following
  /// user message become one `user` message, as [toolResultsAsUserTurns]
  /// describes. When one is converted and
  /// [toolCallsAsContent] is set, tool calls the serialization left in place
  /// move into `content` in the generic schema, as llama.cpp's minja
  /// `polyfill_tool_calls` did for templates that cannot render them:
  /// arguments that decode to a JSON object become that object, and others
  /// stay strings.
  static List<Map<String, dynamic>> messagesForTemplate(
    List<LlamaChatMessage> messages, {
    TemplateToolCallSerialization toolCallSerialization =
        TemplateToolCallSerialization.none,
    bool multimodal = false,
    String mediaMarker = mtmdMediaMarker,
    bool objectArguments = false,
    bool typedContentOnly = false,
    bool stringContentOnly = false,
    bool toolResultsAsUser = false,
    bool toolCallsAsContent = false,
  }) {
    var renderedMessages = <Map<String, dynamic>>[];
    var hasToolCalls = false;
    for (var message in splitToolResults(messages)) {
      message = multimodal
          ? _withMediaMarkers(message, mediaMarker)
          : withToolResultMediaMarkers(message, mediaMarker);
      final rendered = message.toJson();
      rendered['content'] ??= '';
      final toolResults = message.parts.whereType<LlamaToolResultContent>();
      if (toolResults.isNotEmpty) {
        rendered['content'] = _toolResultContent(
          toolResults.first,
          stringContentOnly: stringContentOnly,
        );
      }
      if (rendered['tool_calls'] is List) {
        hasToolCalls = true;
      }
      renderedMessages.add(rendered);
    }

    if (hasToolCalls) {
      if (toolCallSerialization.normalizeArguments) {
        normalizeToolCallArgs(renderedMessages);
      } else if (objectArguments) {
        _decodeObjectArguments(renderedMessages);
      }
      if (toolCallSerialization.useGenericSchema) {
        useGenericSchema(renderedMessages);
      }
      if (toolCallSerialization.moveToolCallsToContent) {
        moveToolCallsToContent(
          renderedMessages,
          preserveContentList: multimodal,
        );
      }
    }

    if (toolResultsAsUser &&
        renderedMessages.any((message) => message['role'] == 'tool')) {
      if (hasToolCalls && toolCallsAsContent) {
        _decodeObjectArguments(renderedMessages);
        useGenericSchema(renderedMessages);
        moveToolCallsToContent(
          renderedMessages,
          preserveContentList: multimodal,
        );
      }
      renderedMessages = toolResultsAsUserTurns(renderedMessages);
    }

    if (typedContentOnly) {
      for (final message in renderedMessages) {
        final content = message['content'];
        if (content is String) {
          message['content'] = [
            {'type': 'text', 'text': content},
          ];
        }
      }
    }

    return renderedMessages;
  }

  /// Replaces each run of consecutive `tool` messages in [messages] with one
  /// `user` message, for templates that reject the `tool` role.
  ///
  /// Each result is written as llama.cpp's minja `polyfill_tool_responses`
  /// wrote it, `{"tool_response": {"tool": name, "content": content,
  /// "tool_call_id": id}}` with two-space indentation and absent fields
  /// left out. Results in one run are joined with a newline, so templates
  /// that require alternating user and assistant turns accept several
  /// results. An immediately following user message is appended with a
  /// newline to that result turn, preserving role alternation on the retry.
  static List<Map<String, dynamic>> toolResultsAsUserTurns(
    List<Map<String, dynamic>> messages,
  ) {
    final turns = <Map<String, dynamic>>[];
    final results = <String>[];
    void flush() {
      if (results.isEmpty) return;
      turns.add({'role': 'user', 'content': results.join('\n')});
      results.clear();
    }

    for (final message in messages) {
      if (message['role'] != 'tool') {
        if (message['role'] == 'user' && results.isNotEmpty) {
          turns.add({
            ...message,
            'content': '${results.join('\n')}\n${message['content']}',
          });
          results.clear();
        } else {
          flush();
          turns.add(message);
        }
        continue;
      }
      final name = message['name'];
      final id = message['tool_call_id'];
      results.add(
        _defaultToolCallEncoder.convert({
          'tool_response': {
            'tool': ?name,
            'content': message['content'],
            'tool_call_id': ?id,
          },
        }),
      );
    }
    flush();
    return turns;
  }

  static LlamaChatMessage _withMediaMarkers(
    LlamaChatMessage message,
    String mediaMarker,
  ) {
    message = withToolResultMediaMarkers(message, mediaMarker);
    if (!message.parts.any(isMediaPart)) return message;
    return message.copyWith(
      parts: [
        for (final part in message.parts)
          isMediaPart(part) ? LlamaTextContent(mediaMarker) : part,
      ],
    );
  }

  /// [message] with each tool result that has a media part turned into one
  /// whose result is the tool turn's text, with [mediaMarker] at each media
  /// part, as llama.cpp's server renders an array `tool` message.
  static LlamaChatMessage withToolResultMediaMarkers(
    LlamaChatMessage message,
    String mediaMarker,
  ) {
    if (!message.parts.any(
      (part) => part is LlamaToolResultContent && part.content.isNotEmpty,
    )) {
      return message;
    }
    return message.copyWith(
      parts: [
        for (final part in message.parts)
          part is LlamaToolResultContent
              ? toolResultWithMediaMarkers(part, mediaMarker)
              : part,
      ],
    );
  }

  /// [result] as template `content`: its result text, or with text-only
  /// `content`, the text parts llama.cpp keeps typed, joined by a newline
  /// for a template that reads only string content.
  static Object _toolResultContent(
    LlamaToolResultContent result, {
    required bool stringContentOnly,
  }) {
    if (result.content.isEmpty) {
      final value = result.result;
      return value is String ? value : jsonEncode(value);
    }
    final parts = toolResultContentJson(result);
    if (!stringContentOnly) return parts;
    final text = ContentTextBuffer();
    for (final part in parts) {
      text.addText(part['text'] as String);
    }
    return text.toString();
  }

  static void _decodeObjectArguments(List<Map<String, dynamic>> messages) {
    for (final message in messages) {
      final toolCalls = message['tool_calls'];
      if (toolCalls is! List) continue;
      for (final call in toolCalls) {
        final function = call is Map ? call['function'] : null;
        if (function is! Map) continue;
        final arguments = ToolCallParsingUtils.decodeJsonMapValue(
          function['arguments'],
        );
        if (arguments == null) continue;
        call['function'] = <String, dynamic>{
          ...ToolCallParsingUtils.coerceMap(function)!,
          'arguments': arguments,
        };
      }
    }
  }

  /// Splits each message holding several [LlamaToolResultContent] parts into
  /// one message per result, as llama.cpp's OpenAI-style input has one `tool`
  /// message per tool call.
  ///
  /// The first message keeps the original's other parts; each following
  /// message holds only its result. Messages with fewer than two results are
  /// returned unchanged.
  static List<LlamaChatMessage> splitToolResults(
    List<LlamaChatMessage> messages,
  ) {
    if (!messages.any(_hasSeveralToolResults)) return messages;
    return [
      for (final message in messages)
        if (_hasSeveralToolResults(message))
          ..._splitToolResultMessage(message)
        else
          message,
    ];
  }

  static bool _hasSeveralToolResults(LlamaChatMessage message) =>
      message.parts.whereType<LlamaToolResultContent>().skip(1).isNotEmpty;

  static List<LlamaChatMessage> _splitToolResultMessage(
    LlamaChatMessage message,
  ) {
    final first = <LlamaContentPart>[];
    final rest = <LlamaChatMessage>[];
    for (final part in message.parts) {
      if (part is LlamaToolResultContent &&
          first.any((kept) => kept is LlamaToolResultContent)) {
        rest.add(message.copyWith(parts: [part]));
      } else {
        first.add(part);
      }
    }
    return [message.copyWith(parts: first), ...rest];
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
