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
}
