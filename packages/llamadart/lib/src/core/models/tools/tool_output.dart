import '../chat/content_part.dart';

/// A tool result with text or media after its output, for a `ToolHandler` or
/// tool-loop callback to return.
///
/// `ChatSession.completeWithTools` and `sendWithTools` store it as a
/// [LlamaToolResultContent] with [output] as its `result` and [content] as
/// its `content`; see that class for which parts and runtimes are
/// supported. Any other return value is stored as the `result` unchanged.
///
/// ```dart
/// final cameraTool = ToolDefinition(
///   name: 'take_photo',
///   description: 'Takes a photo and returns it.',
///   parameters: const [],
///   handler: (params) async => LlamaToolOutput(
///     output: {'ok': true},
///     content: [LlamaImageContent(bytes: await camera.capture())],
///   ),
/// );
/// ```
final class LlamaToolOutput {
  /// Creates a tool output.
  const LlamaToolOutput({
    this.output,
    this.content = const <LlamaContentPart>[],
  });

  /// The tool's text or JSON-compatible result, rendered before [content];
  /// `null` renders nothing.
  final Object? output;

  /// Text and media parts that follow [output] in the tool turn, in order.
  final List<LlamaContentPart> content;
}
