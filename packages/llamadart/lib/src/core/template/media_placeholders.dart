/// Media markers and the placeholders a caller may write in its own prompt.
library;

import 'dart:math';

/// The marker a chat template renders where a media part was, and one of the
/// placeholders a caller may write in a prompt it passes to `generate`.
const String mtmdMediaMarker = '<__media__>';

/// The marker `LlamaEngine` renders a chat request with for a backend that
/// takes it through `BackendChatPromptGeneration`: one that message text
/// cannot hold by accident, as llama.cpp's server draws one for each process.
final String chatPromptMediaMarker = () {
  const alphabet =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final random = Random.secure();
  final id = String.fromCharCodes([
    for (var i = 0; i < 32; i++)
      alphabet.codeUnitAt(random.nextInt(alphabet.length)),
  ]);
  return '<__media_${id}__>';
}();

/// Model-specific media placeholders rewritten to [mtmdMediaMarker].
const List<String> mtmdMediaPlaceholders = <String>[
  '<image>', // SmolVLM, InternVL, etc.
  '[IMG]', // Some CLIP-based models
  '<|image|>', // Phi-3 vision
  '<|audio|>',
  '<|video|>',
  '<img>',
  '<|img|>',
  '<start_of_image>', // Gemma
  '<image_soft_token>',
  '<audio_soft_token>',
  '<video_soft_token>',
];

/// Indexed image placeholders such as `<|image_1|>`, used by some VLM templates.
final RegExp mtmdIndexedImagePlaceholder = RegExp(r'<\|image_\d+\|>');

/// What the WebGPU bridge reads as a media part wherever it is in a prompt
/// that comes with parts: its marker and the placeholders the pinned assets
/// rewrite to it. It has no option that turns this off.
final RegExp webGpuBridgeMediaPlaceholders = RegExp(
  r'<__media__>|<image>|\[IMG\]|<\|image\|>|<img>|<\|img\|>'
  r'|<\|vision_start\|><\|(?:image|video)_pad\|><\|vision_end\|>'
  r'|<audio>|<\|audio\|>|<\|(?:image|audio)_\d+\|>',
);

/// Every string that a backend's `generate` reads as a media part in a
/// prompt its caller wrote: what [normalizeMediaPlaceholders] rewrites and
/// what [webGpuBridgeMediaPlaceholders] matches, [mtmdMediaMarker] among it.
final RegExp callerPromptMediaPlaceholders = RegExp(
  [
    ...mtmdMediaPlaceholders.map(RegExp.escape),
    mtmdIndexedImagePlaceholder.pattern,
    webGpuBridgeMediaPlaceholders.pattern,
  ].join('|'),
);

/// Rewrites every media placeholder a caller wrote in its [prompt] to
/// [marker].
///
/// Not for a prompt a chat template rendered: there a placeholder string is
/// message text, and [chatPromptForMarkerRuntime] keeps it so.
String normalizeMediaPlaceholders(
  String prompt, {
  String marker = mtmdMediaMarker,
}) {
  var normalized = prompt;
  for (final placeholder in mtmdMediaPlaceholders) {
    normalized = normalized.replaceAll(placeholder, marker);
  }
  return normalized.replaceAll(mtmdIndexedImagePlaceholder, marker);
}

/// Turns a chat-rendered [prompt] into the one a runtime reads that finds
/// media by substring: [marker] where [chatMarker] stood for a media part.
///
/// Such a runtime has no way to take a string it matches as text, so each
/// match of [runtimePlaceholders] in the text between the parts gets a
/// zero-width space after its first character. llama.cpp's server leaves
/// that text as it is, having a marker of its own for each process.
String chatPromptForMarkerRuntime(
  String prompt, {
  required String chatMarker,
  required String marker,
  required Pattern runtimePlaceholders,
}) {
  return prompt
      .split(chatMarker)
      .map(
        (text) => text.replaceAllMapped(runtimePlaceholders, (match) {
          final placeholder = match[0]!;
          return '${placeholder[0]}\u200B${placeholder.substring(1)}';
        }),
      )
      .join(marker);
}

/// Turns a [prompt] that a chat template rendered with [chatMarker] into one
/// that reads the same as a caller's prompt: [mtmdMediaMarker] where each
/// part was, and no other string that `generate` would read as a part.
String chatPromptAsCallerPrompt(String prompt, {required String chatMarker}) =>
    chatPromptForMarkerRuntime(
      prompt,
      chatMarker: chatMarker,
      marker: mtmdMediaMarker,
      runtimePlaceholders: callerPromptMediaPlaceholders,
    );
