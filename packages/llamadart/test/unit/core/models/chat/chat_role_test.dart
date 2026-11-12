import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:test/test.dart';

void main() {
  test('LlamaChatRole wire names match the chat message JSON contract', () {
    expect(LlamaChatRole.values.map((role) => role.name), [
      'system',
      'user',
      'assistant',
      'tool',
    ]);
  });
}
