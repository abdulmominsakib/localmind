import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/models/chat/tool_result_parts.dart';
import 'package:test/test.dart';

const _marker = '<__media__>';
const _image = LlamaImageContent(path: '/photo.png');

LlamaChatMessage _tool(LlamaToolResultContent result) =>
    LlamaChatMessage.withContent(role: LlamaChatRole.tool, content: [result]);

void main() {
  group('toolResultWithMediaMarkers', () {
    // Expected strings are what llama-server 620d2225c renders for the same
    // parts (test/fixtures/qwen3_vl_tool_media_upstream.json).
    test('joins text parts by a newline and glues markers to text', () {
      final flattened = toolResultWithMediaMarkers(
        const LlamaToolResultContent(
          id: 'call_0',
          name: 'take_photo',
          result: {'ok': true},
          content: [LlamaTextContent('front camera'), _image],
        ),
        _marker,
      );

      expect(flattened.id, 'call_0');
      expect(flattened.name, 'take_photo');
      expect(flattened.result, '{"ok":true}\nfront camera<__media__>');
      expect(flattened.content, isEmpty);
    });

    test('puts no newline after a marker', () {
      expect(
        toolResultWithMediaMarkers(
          const LlamaToolResultContent(
            name: 't',
            result: '{"ok":true}',
            content: [_image, LlamaTextContent('done')],
          ),
          _marker,
        ).result,
        '{"ok":true}<__media__>done',
      );
    });

    test('leaves a null result out', () {
      expect(
        toolResultWithMediaMarkers(
          const LlamaToolResultContent(
            name: 't',
            result: null,
            content: [
              _image,
              LlamaAudioContent(path: '/a.wav'),
            ],
          ),
          _marker,
        ).result,
        '<__media__><__media__>',
      );
    });

    test('returns a result without media unchanged', () {
      const plain = LlamaToolResultContent(name: 't', result: 1);
      expect(toolResultWithMediaMarkers(plain, _marker), same(plain));
      // llama.cpp keeps text-only parts typed for the template.
      const textOnly = LlamaToolResultContent(
        name: 't',
        result: 1,
        content: [LlamaTextContent('a')],
      );
      expect(toolResultWithMediaMarkers(textOnly, _marker), same(textOnly));
    });
  });

  test('toolResultContentJson is the llama-server array shape', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    expect(
      toolResultContentJson(
        LlamaToolResultContent(
          name: 't',
          result: const {'ok': true},
          content: [
            const LlamaTextContent('caption'),
            LlamaImageContent(bytes: bytes),
          ],
        ),
      ),
      [
        {'type': 'text', 'text': '{"ok":true}'},
        {'type': 'text', 'text': 'caption'},
        {
          'type': 'image_url',
          'image_url': {'url': 'data:image/jpeg;base64,AQID'},
        },
      ],
    );
    expect(
      toolResultContentJson(
        const LlamaToolResultContent(
          name: 't',
          result: null,
          content: [_image],
        ),
      ),
      [
        {
          'type': 'image_url',
          'image_url': {'url': 'file:///photo.png'},
        },
      ],
    );
  });

  test('toolResultText keeps strings and encodes other results', () {
    expect(
      toolResultText(const LlamaToolResultContent(name: 't', result: 'x')),
      'x',
    );
    expect(
      toolResultText(const LlamaToolResultContent(name: 't', result: [1])),
      '[1]',
    );
    expect(
      toolResultText(LlamaToolResultContent(name: 't', result: Object())),
      "Instance of 'Object'",
    );
  });

  test('partsInPromptOrder puts each result content after the result', () {
    const result = LlamaToolResultContent(
      name: 't',
      result: 1,
      content: [LlamaTextContent('a'), _image],
    );
    const second = LlamaToolResultContent(name: 't', result: 2);
    final message = LlamaChatMessage.withContent(
      role: LlamaChatRole.tool,
      content: const [result, second],
    );
    expect(partsInPromptOrder(message), [
      same(result),
      same(result.content[0]),
      same(result.content[1]),
      same(second),
    ]);
  });

  test('carriesToolResultContent and toolResultMediaIn read nested parts', () {
    final textOnly = _tool(
      const LlamaToolResultContent(
        name: 't',
        result: 1,
        content: [LlamaTextContent('a')],
      ),
    );
    final media = _tool(
      const LlamaToolResultContent(
        name: 't',
        result: 1,
        content: [
          _image,
          LlamaAudioContent(path: '/a.wav'),
        ],
      ),
    );
    final plain = _tool(const LlamaToolResultContent(name: 't', result: 1));
    final userImage = LlamaChatMessage.withContent(
      role: LlamaChatRole.user,
      content: const [_image],
    );

    expect(carriesToolResultContent([plain, userImage]), isFalse);
    expect(carriesToolResultContent([plain, textOnly]), isTrue);
    expect(toolResultMediaIn([textOnly, userImage]), isEmpty);
    expect(toolResultMediaIn([media]), {
      LlamaToolResultMedia.image,
      LlamaToolResultMedia.audio,
    });
  });

  group('validateToolResultContent', () {
    void validate(LlamaContentPart part) => validateToolResultContent([
      _tool(LlamaToolResultContent(name: 't', result: 1, content: [part])),
    ]);

    test('accepts text, path or byte images, and audio', () {
      validate(const LlamaTextContent('a'));
      validate(_image);
      validate(LlamaImageContent(bytes: Uint8List(1)));
      validate(const LlamaAudioContent(path: '/a.wav'));
    });

    test('rejects a URL-only image without echoing the URL', () {
      const url = 'https://example.com/p.png?X-Amz-Signature=secret';
      expect(
        () => validate(const LlamaImageContent(url: url)),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            allOf(contains('path or bytes'), isNot(contains('secret'))),
          ),
        ),
      );
      expect(
        () => validate(const LlamaImageContent()),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });

    test('rejects video', () {
      expect(
        () => validate(LlamaVideoContent(path: '/v.mp4')),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('Video'),
          ),
        ),
      );
    });

    test('rejects a LlamaToolOutput result', () {
      expect(
        () => validateToolResultContent([
          _tool(
            const LlamaToolResultContent(
              name: 't',
              result: LlamaToolOutput(output: 1, content: [_image]),
            ),
          ),
        ]),
        throwsA(
          isA<LlamaArgumentException>().having(
            (error) => error.message,
            'message',
            contains('LlamaToolOutput'),
          ),
        ),
      );
    });

    test('rejects nested tool calls, tool results and thinking', () {
      for (final part in <LlamaContentPart>[
        const LlamaToolCallContent(name: 't', arguments: {}, rawJson: '{}'),
        const LlamaToolResultContent(name: 't', result: 1),
        const LlamaThinkingContent('hmm'),
      ]) {
        expect(
          () => validate(part),
          throwsA(isA<LlamaArgumentException>()),
          reason: '${part.runtimeType}',
        );
      }
    });
  });
}
