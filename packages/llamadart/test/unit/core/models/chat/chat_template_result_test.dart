import 'package:llamadart/src/core/models/chat/chat_template_result.dart';
import 'package:test/test.dart';

void main() {
  test('LlamaChatTemplateResult supports JSON conversion', () {
    final result = LlamaChatTemplateResult.fromJson({
      'prompt': 'hello',
      'format': 1,
      'additional_stops': ['</s>'],
      'grammar_triggers': [
        {'type': 0, 'value': '{'},
      ],
    });

    expect(result.prompt, 'hello');
    expect(result.format, 1);
    expect(result.additionalStops, contains('</s>'));
    expect(result.grammarTriggers.first.value, '{');
  });
}
