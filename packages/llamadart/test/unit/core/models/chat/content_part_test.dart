import 'dart:typed_data';

import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:test/test.dart';

void main() {
  test('LlamaTextContent serializes to JSON', () {
    const part = LlamaTextContent('hello');
    expect(part.toJson(), {'type': 'text', 'text': 'hello'});
  });

  test('LlamaThinkingContent serializes to JSON', () {
    const part = LlamaThinkingContent('reasoning');
    expect(part.toJson(), {'type': 'thinking', 'thinking': 'reasoning'});
  });

  test('LlamaVideoContent keeps path and bytes explicit', () {
    expect(LlamaVideoContent(path: '/tmp/clip.mp4').toJson(), {
      'type': 'input_video',
      'input_video': {'data': '', 'path': '/tmp/clip.mp4'},
    });
    expect(
      LlamaVideoContent(bytes: Uint8List.fromList(<int>[1, 2, 3])).toJson(),
      {
        'type': 'input_video',
        'input_video': {'data': 'AQID'},
      },
    );
  });

  test('LlamaToolResultContent serializes content as an array', () {
    const plain = LlamaToolResultContent(id: 'c', name: 't', result: 7);
    expect(plain.toJson(), {
      'type': 'tool_result',
      'tool_call_id': 'c',
      'content': '7',
    });
    const withContent = LlamaToolResultContent(
      id: 'c',
      name: 't',
      result: {'ok': true},
      content: [LlamaImageContent(path: '/p.png')],
    );
    expect(withContent.toJson(), {
      'type': 'tool_result',
      'tool_call_id': 'c',
      'content': [
        {'type': 'text', 'text': '{"ok":true}'},
        {
          'type': 'image_url',
          'image_url': {'url': 'file:///p.png'},
        },
      ],
    });
  });

  test('LlamaVideoContent requires a path or bytes', () {
    expect(() => LlamaVideoContent(), throwsArgumentError);
  });
}
