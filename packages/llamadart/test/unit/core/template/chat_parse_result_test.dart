import 'package:llamadart/src/core/template/chat_parse_result.dart';
import 'package:test/test.dart';

void main() {
  test('ChatParseResult toAssistantMessage keeps content and reasoning', () {
    const result = ChatParseResult(
      content: 'final answer',
      reasoningContent: 'thoughts',
    );

    final message = result.toAssistantMessage();
    expect(message.content, 'final answer');
    expect(message.reasoning, 'thoughts');
  });
}
