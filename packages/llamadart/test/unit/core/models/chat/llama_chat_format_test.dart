import 'package:llamadart/src/core/models/chat/llama_chat_format.dart';
import 'package:test/test.dart';

void main() {
  test('LlamaChatFormat enum contains expected variants', () {
    expect(LlamaChatFormat.values, contains(LlamaChatFormat.contentOnly));
    expect(LlamaChatFormat.values, contains(LlamaChatFormat.llama3));
    expect(LlamaChatFormat.values, contains(LlamaChatFormat.functionGemma));
  });
}
