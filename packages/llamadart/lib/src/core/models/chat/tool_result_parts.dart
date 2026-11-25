import 'dart:convert';

import '../../engine/engine_capabilities.dart';
import '../../exceptions.dart';
import '../tools/tool_output.dart';
import 'chat_message.dart';
import 'content_part.dart';

/// Whether [part] is an image, audio or video part.
bool isMediaPart(LlamaContentPart part) =>
    part is LlamaImageContent ||
    part is LlamaAudioContent ||
    part is LlamaVideoContent;

/// [result]'s `result` as prompt text: a String as it is, anything else as
/// JSON, or its `toString()` when it cannot be encoded.
String toolResultText(LlamaToolResultContent result) {
  final value = result.result;
  if (value is String) return value;
  try {
    return jsonEncode(value);
  } on Object {
    return value.toString();
  }
}

/// [result] as an OpenAI-style content array, the shape llama.cpp's server
/// takes in a `tool` message: its `result` as a text part unless it is
/// `null`, then each part of its `content`.
List<Map<String, dynamic>> toolResultContentJson(
  LlamaToolResultContent result,
) => [
  if (result.result != null) {'type': 'text', 'text': toolResultText(result)},
  for (final part in result.content) part.toJson(),
];

/// The parts of [message] in prompt order, each tool result followed by the
/// parts of its `content`.
Iterable<LlamaContentPart> partsInPromptOrder(LlamaChatMessage message) =>
    message.parts.expand(
      (part) =>
          part is LlamaToolResultContent ? [part, ...part.content] : [part],
    );

/// Whether a tool result in [messages] has `content`.
bool carriesToolResultContent(List<LlamaChatMessage> messages) =>
    _toolResults(messages).any((result) => result.content.isNotEmpty);

/// The media types in the `content` of the tool results in [messages].
Set<LlamaToolResultMedia> toolResultMediaIn(List<LlamaChatMessage> messages) =>
    {
      for (final result in _toolResults(messages))
        for (final part in result.content)
          if (part is LlamaImageContent)
            LlamaToolResultMedia.image
          else if (part is LlamaAudioContent)
            LlamaToolResultMedia.audio,
    };

/// Throws when a tool result in [messages] has a `content` part no runtime
/// takes there.
///
/// A nested tool call, tool result or thinking part, or a [LlamaToolOutput]
/// `result`, throws [LlamaArgumentException]. A video part, or an image without a `path` or
/// `bytes`, throws [LlamaUnsupportedException]; its message never holds the
/// image URL, which may be signed.
void validateToolResultContent(List<LlamaChatMessage> messages) {
  for (final result in _toolResults(messages)) {
    if (result.result is LlamaToolOutput) {
      throw LlamaArgumentException(
        'LlamaToolResultContent.result holds a LlamaToolOutput. Pass its '
        'output as result and its content as content.',
      );
    }
    for (final part in result.content) {
      switch (part) {
        case LlamaTextContent() || LlamaAudioContent():
          break;
        case LlamaImageContent(:final path, :final bytes):
          if (path == null && bytes == null) {
            throw LlamaUnsupportedException(
              'An image in LlamaToolResultContent.content needs a path or '
              'bytes. Remote image URLs are not fetched: resolve the image in '
              'the application and pass its bytes or a local path.',
            );
          }
        case LlamaVideoContent():
          throw LlamaUnsupportedException(
            'Video in LlamaToolResultContent.content is unsupported on all '
            'runtimes. Return text, JSON or an image from the tool instead.',
          );
        case LlamaToolCallContent() ||
            LlamaToolResultContent() ||
            LlamaThinkingContent():
          throw LlamaArgumentException(
            'LlamaToolResultContent.content holds only text, image and audio '
            'parts, not ${part.runtimeType}.',
          );
      }
    }
  }
}

/// [result] as one tool result whose `result` is the prompt text of the
/// tool turn, with [mediaMarker] at each media part; [result] itself when
/// its `content` has no media part.
///
/// The text is built as llama.cpp's `common_chat_msg::to_json_oaicompat`
/// joins a message's content parts when one is media: text parts are joined
/// by a newline, and no newline goes before or after a marker. The `result`
/// text comes first, and a `null` result is left out. llama.cpp keeps
/// text-only parts typed, so they are left to the template render.
LlamaToolResultContent toolResultWithMediaMarkers(
  LlamaToolResultContent result,
  String mediaMarker,
) {
  if (!result.content.any(isMediaPart)) return result;
  final text = ContentTextBuffer();
  if (result.result != null) text.addText(toolResultText(result));
  for (final part in result.content) {
    if (part is LlamaTextContent) {
      text.addText(part.text);
    } else if (isMediaPart(part)) {
      text.addMarker(mediaMarker);
    }
  }
  return LlamaToolResultContent(
    id: result.id,
    name: result.name,
    result: text.toString(),
  );
}

/// Prompt text built as llama.cpp's `concat_content_parts` joins content
/// parts: a newline goes before a text part only when the text so far is not
/// empty and does not end in a media marker.
final class ContentTextBuffer {
  final StringBuffer _text = StringBuffer();
  bool _lastWasMarker = false;

  /// Appends [value] as a text part.
  void addText(String value) {
    if (!_lastWasMarker && _text.isNotEmpty) _text.write('\n');
    _text.write(value);
    _lastWasMarker = false;
  }

  /// Appends [marker] for a media part, with no newline before it.
  void addMarker(String marker) {
    _text.write(marker);
    _lastWasMarker = true;
  }

  @override
  String toString() => _text.toString();
}

Iterable<LlamaToolResultContent> _toolResults(
  List<LlamaChatMessage> messages,
) => messages.expand(
  (message) => message.parts.whereType<LlamaToolResultContent>(),
);
