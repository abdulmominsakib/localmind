import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:test/test.dart';

void main() {
  test('LlamaDartGenerationConfig.fromJson parses supported fields', () {
    final config = LlamaDartGenerationConfig.fromJson(<String, dynamic>{
      'temperature': 0.2,
      'topP': 0.8,
      'topK': 12,
      'minP': 0.05,
      'penalty': 1.3,
      'maxTokens': 128,
      'stop': <String>['END'],
      'seed': 42,
      'enableThinking': true,
      'parallelToolCalls': true,
      'sourceLangCode': 'en',
      'targetLangCode': 'ko',
      'chatTemplateKwargs': <String, dynamic>{'mode': 'json'},
    });

    expect(config.temperature, 0.2);
    expect(config.topP, 0.8);
    expect(config.topK, 12);
    expect(config.minP, 0.05);
    expect(config.penalty, 1.3);
    expect(config.maxTokens, 128);
    expect(config.stop, <String>['END']);
    expect(config.seed, 42);
    expect(config.enableThinking, isTrue);
    expect(config.parallelToolCalls, isTrue);
    expect(config.sourceLangCode, 'en');
    expect(config.targetLangCode, 'ko');
    expect(config.chatTemplateKwargs, <String, dynamic>{'mode': 'json'});
  });
}
