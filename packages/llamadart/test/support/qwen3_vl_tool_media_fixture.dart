import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';

/// The llama-server 620d2225c `/apply-template` emissions in
/// `test/fixtures/qwen3_vl_tool_media_upstream.json` and the llamadart
/// conversations that mirror their requests.
final class Qwen3VlToolMediaFixture {
  Qwen3VlToolMediaFixture._(this.json);

  /// Loads the fixture from the package root.
  factory Qwen3VlToolMediaFixture.load() => Qwen3VlToolMediaFixture._(
    jsonDecode(
          File(
            'test/fixtures/qwen3_vl_tool_media_upstream.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>,
  );

  /// The decoded fixture.
  final Map<String, dynamic> json;

  /// The pinned Qwen3-VL-2B-Instruct chat template.
  static String get template => File(
    'test/fixtures/templates/Qwen3-VL-2B-Instruct.jinja',
  ).readAsStringSync();

  /// The upstream prompt for [caseName].
  String prompt(String caseName) =>
      (json['cases'] as Map<String, dynamic>)[caseName]['prompt'] as String;

  /// The upstream text-only case [caseName]: its `template`, `request` and
  /// `prompt`.
  Map<String, dynamic> textOnlyCase(String caseName) =>
      (json['text_only_cases'] as Map<String, dynamic>)[caseName]
          as Map<String, dynamic>;

  /// Upstream text-only cases: a result [result] with text parts [parts].
  static List<LlamaChatMessage> textOnly({
    Object? result = 'abc',
    List<String> parts = const ['x'],
  }) => [
    const LlamaChatMessage.fromText(
      role: LlamaChatRole.user,
      text: 'Look up the code.',
    ),
    const LlamaChatMessage.withContent(
      role: LlamaChatRole.assistant,
      content: [
        LlamaToolCallContent(
          id: 'call_0',
          name: 'lookup',
          arguments: {},
          rawJson: '{}',
        ),
      ],
    ),
    LlamaChatMessage.withContent(
      role: LlamaChatRole.tool,
      content: [
        LlamaToolResultContent(
          id: 'call_0',
          name: 'lookup',
          result: result,
          content: [for (final part in parts) LlamaTextContent(part)],
        ),
      ],
    ),
  ];

  /// Stand-in for the red photo the upstream request sent as a data URI.
  static final LlamaImageContent red = LlamaImageContent(
    bytes: Uint8List.fromList([1]),
  );

  /// Stand-in for the blue photo the upstream request sent as a data URI.
  static final LlamaImageContent blue = LlamaImageContent(
    bytes: Uint8List.fromList([2]),
  );

  static const LlamaToolCallContent _front = LlamaToolCallContent(
    id: 'call_0',
    name: 'take_photo',
    arguments: {'camera': 'front'},
    rawJson: '{"camera": "front"}',
  );

  static const LlamaToolCallContent _back = LlamaToolCallContent(
    id: 'call_1',
    name: 'take_photo',
    arguments: {'camera': 'back'},
    rawJson: '{"camera": "back"}',
  );

  /// Upstream cases with one `take_photo` call whose result is [result] with
  /// content [parts].
  static List<LlamaChatMessage> singleResult({
    required Object? result,
    required List<LlamaContentPart> parts,
  }) => [
    const LlamaChatMessage.fromText(
      role: LlamaChatRole.user,
      text: 'Take a photo.',
    ),
    const LlamaChatMessage.withContent(
      role: LlamaChatRole.assistant,
      content: [_front],
    ),
    LlamaChatMessage.withContent(
      role: LlamaChatRole.tool,
      content: [
        LlamaToolResultContent(
          id: 'call_0',
          name: 'take_photo',
          result: result,
          content: parts,
        ),
      ],
    ),
  ];

  /// Upstream case `two_results`: two calls, the first result with JSON,
  /// a caption and the red photo, the second with only the blue photo.
  static List<LlamaChatMessage> twoResults() => [
    const LlamaChatMessage.fromText(
      role: LlamaChatRole.user,
      text: 'Take a photo with each camera.',
    ),
    const LlamaChatMessage.withContent(
      role: LlamaChatRole.assistant,
      content: [_front, _back],
    ),
    LlamaChatMessage.withContent(
      role: LlamaChatRole.tool,
      content: [
        LlamaToolResultContent(
          id: 'call_0',
          name: 'take_photo',
          result: const {'ok': true},
          content: [const LlamaTextContent('front camera'), red],
        ),
      ],
    ),
    LlamaChatMessage.withContent(
      role: LlamaChatRole.tool,
      content: [
        LlamaToolResultContent(
          id: 'call_1',
          name: 'take_photo',
          result: null,
          content: [blue],
        ),
      ],
    ),
  ];

  /// Upstream case `user_image_then_tool_image`: a user photo, then a tool
  /// result with text after its photo.
  static List<LlamaChatMessage> userImageThenToolImage() => [
    LlamaChatMessage.withContent(
      role: LlamaChatRole.user,
      content: [blue, const LlamaTextContent('Compare this with a new photo.')],
    ),
    const LlamaChatMessage.withContent(
      role: LlamaChatRole.assistant,
      content: [_front],
    ),
    LlamaChatMessage.withContent(
      role: LlamaChatRole.tool,
      content: [
        LlamaToolResultContent(
          id: 'call_0',
          name: 'take_photo',
          result: '{"ok":true}',
          content: [red, const LlamaTextContent('done')],
        ),
      ],
    ),
  ];
}
