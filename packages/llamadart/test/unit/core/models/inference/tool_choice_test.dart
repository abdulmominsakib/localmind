import 'package:test/test.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';

void main() {
  group('ToolChoice Tests', () {
    test('names match OpenAI spec', () {
      expect(ToolChoice.none.name, 'none');
      expect(ToolChoice.auto.name, 'auto');
      expect(ToolChoice.required.name, 'required');
    });
  });
}
