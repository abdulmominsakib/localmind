import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:test/test.dart';

void main() {
  test('LlamaChatRole defines expected roles', () {
    expect(LlamaChatRole.values, contains(LlamaChatRole.system));
    expect(LlamaChatRole.values, contains(LlamaChatRole.user));
    expect(LlamaChatRole.values, contains(LlamaChatRole.assistant));
    expect(LlamaChatRole.values, contains(LlamaChatRole.tool));
  });
}
