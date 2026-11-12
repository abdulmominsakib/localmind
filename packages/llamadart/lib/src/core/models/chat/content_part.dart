import 'dart:convert';
import 'dart:typed_data';

import 'tool_result_parts.dart';

/// Base class for all content types in a message.
///
/// Multi-modality allows a single message to contain different types of data,
/// such as text, images, audio, or video.
sealed class LlamaContentPart {
  /// Base constructor for content parts.
  const LlamaContentPart();

  /// Converts the content part to a JSON object.
  Map<String, dynamic> toJson();
}

/// A part of a message containing plain text.
class LlamaTextContent extends LlamaContentPart {
  /// The raw text string.
  final String text;

  /// Creates a text content part.
  const LlamaTextContent(this.text);

  @override
  Map<String, dynamic> toJson() => {'type': 'text', 'text': text};
}

/// A part of a message containing image data for vision models.
///
/// GGUF models need a compatible multimodal projector. Native LiteRT-LM
/// `.litertlm` bundles use the bundle's media processors instead.
class LlamaImageContent extends LlamaContentPart {
  /// Encoded image bytes, such as JPEG or PNG data.
  ///
  /// Local paths are preferred on native backends when available.
  final Uint8List? bytes;

  /// Width of the image in pixels.
  final int? width;

  /// Height of the image in pixels.
  final int? height;

  /// Local filesystem path to the image (e.g., JPEG, PNG).
  ///
  /// If provided, the native engine will load and decode the image automatically.
  final String? path;

  /// URL to a remote image (not yet supported).
  final String? url;

  /// Creates an image content part.
  ///
  /// Either [path] or [bytes] should be provided.
  const LlamaImageContent({
    this.bytes,
    this.width,
    this.height,
    this.path,
    this.url,
  });

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'image_url',
      'image_url': {
        'url':
            url ??
            (path != null
                ? 'file://$path'
                : (bytes != null
                      ? 'data:image/jpeg;base64,${base64Encode(bytes!)}'
                      : '')),
      },
    };
  }
}

/// A part of a message containing generic multimodal audio input.
///
/// This routes audio through normal generation. It does not by itself provide
/// the typed transcript contract of `SpeechToTextEngine`.
class LlamaAudioContent extends LlamaContentPart {
  /// Raw PCM Float32 audio samples.
  final Float32List? samples;

  /// Encoded audio bytes (for example WAV/MP3).
  final Uint8List? bytes;

  /// Local filesystem path to the audio file (e.g., WAV, MP3).
  ///
  /// If provided, the native engine will decode the audio automatically.
  final String? path;

  /// Creates an audio content part.
  const LlamaAudioContent({this.samples, this.bytes, this.path});

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'input_audio', // OpenAI draft format
      'input_audio': {
        'data': samples != null
            ? base64Encode(samples!.buffer.asUint8List())
            : (bytes != null ? base64Encode(bytes!) : ''),
        'format': samples != null ? 'pcm' : 'audio',
      },
    };
  }
}

/// A part of a message containing encoded video input.
///
/// Video is represented explicitly so unsupported requests fail with a typed,
/// actionable error instead of being flattened into text or treated as an
/// image. The current packaged runtimes do not expose a consumable video-input
/// pipeline; check [LlamaEngine.supportsVideo] before generation.
class LlamaVideoContent extends LlamaContentPart {
  /// Encoded video bytes, such as MP4 or WebM data.
  final Uint8List? bytes;

  /// Local filesystem path to an encoded video file.
  final String? path;

  /// Creates a video content part.
  ///
  /// At least one of [path] or [bytes] must be provided. Current runtimes reject
  /// both forms until native video packaging and Dart frame ingestion are
  /// complete.
  ///
  /// Throws [ArgumentError] when neither source is provided.
  factory LlamaVideoContent({Uint8List? bytes, String? path}) {
    if (bytes == null && path == null) {
      throw ArgumentError('LlamaVideoContent requires bytes or a path.');
    }
    return LlamaVideoContent._(bytes: bytes, path: path);
  }

  const LlamaVideoContent._({this.bytes, this.path});

  @override
  Map<String, dynamic> toJson() {
    if (bytes == null && path == null) {
      throw ArgumentError('LlamaVideoContent requires bytes or a path.');
    }
    return {
      'type': 'input_video',
      'input_video': {
        'data': bytes == null ? '' : base64Encode(bytes!),
        if (path != null) 'path': path,
      },
    };
  }
}

/// A part of a message containing a tool call solicitation from the model.
class LlamaToolCallContent extends LlamaContentPart {
  /// Unique identifier for this call (if provided by the template/model).
  final String? id;

  /// The name of the function to be called.
  final String name;

  /// The arguments for the function as a Map.
  final Map<String, dynamic> arguments;

  /// The raw JSON string generated by the model.
  final String rawJson;

  /// Creates a tool call content part.
  const LlamaToolCallContent({
    required this.name,
    required this.arguments,
    required this.rawJson,
    this.id,
  });

  @override
  Map<String, dynamic> toJson() {
    // Tool calls are handled specially in message serialization,
    // but if treated as content part, we return null or special type?
    // For now return proper structure just in case.
    return {
      'type': 'function',
      'function': {'name': name, 'arguments': rawJson},
      'id': id,
    };
  }
}

/// A part of a message containing the result of a tool execution.
class LlamaToolResultContent extends LlamaContentPart {
  /// The ID of the tool call this result corresponds to.
  final String? id;

  /// The name of the function that was called.
  final String name;

  /// The result of the function execution (e.g., String, Map, List).
  final Object? result;

  /// Text and media the tool returned after [result], in order.
  ///
  /// Each part is a [LlamaTextContent], a [LlamaImageContent] with a `path`
  /// or `bytes`, or a [LlamaAudioContent]. The tool turn holds [result] as
  /// text (a non-String result as JSON, a `null` result left out), then
  /// these parts, as llama.cpp's server renders a `tool` message whose
  /// `content` is an array. With a media part, the turn is one text: text
  /// parts joined by a newline, and a media marker at each media part.
  /// Media reach the model in that order. Without one, the template gets
  /// the text parts as typed parts, or joined by a newline when it reads
  /// only string content.
  ///
  /// Only formats qualified for tool-result content take a non-empty list;
  /// others throw [LlamaUnsupportedException]. Media also need the engine
  /// to report the modality in `LlamaEngineCapabilities.toolResultMedia`.
  /// A video part, a URL-only image, or a nested tool call, tool result or
  /// thinking part is rejected before rendering.
  final List<LlamaContentPart> content;

  /// Creates a tool result content part.
  const LlamaToolResultContent({
    required this.name,
    required this.result,
    this.id,
    this.content = const <LlamaContentPart>[],
  });

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': 'tool_result', // Internal use?
      'tool_call_id': id,
      'content': content.isEmpty
          ? result.toString()
          : toolResultContentJson(this),
    };
  }
}

/// A part of a message containing the model's Chain-of-Thought (reasoning).
///
/// This is typically used by reasoning models (e.g. DeepSeek-R1) to expose
/// their internal thought process before the final answer.
class LlamaThinkingContent extends LlamaContentPart {
  /// The thinking process text.
  final String thinking;

  /// Creates a thinking content part.
  const LlamaThinkingContent(this.thinking);

  @override
  Map<String, dynamic> toJson() {
    return {'type': 'thinking', 'thinking': thinking};
  }
}
