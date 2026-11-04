import 'package:llamadart/src/core/models/chat/completion_chunk.dart';
import 'package:test/test.dart';

void main() {
  test('LlamaCompletionChunk can parse and serialize JSON', () {
    final chunk = LlamaCompletionChunk.fromJson({
      'id': 'abc',
      'object': 'chat.completion.chunk',
      'created': 1,
      'model': 'test-model',
      'choices': [
        {
          'index': 0,
          'delta': {'content': 'hi'},
        },
      ],
    });

    expect(chunk.choices, hasLength(1));
    expect(chunk.choices.first.delta.content, 'hi');
    expect(chunk.toJson()['id'], 'abc');
  });
}
