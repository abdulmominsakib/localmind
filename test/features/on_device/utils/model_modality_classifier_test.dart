import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/on_device/utils/model_modality_classifier.dart';

void main() {
  group('classifyModality', () {
    test('text-generation pipeline', () {
      expect(classifyModality(pipelineTag: 'text-generation'), ModelModality.text);
    });
    test('image pipeline -> vision', () {
      expect(classifyModality(pipelineTag: 'image-to-text'), ModelModality.vision);
    });
    test('audio tag', () {
      expect(classifyModality(tags: ['audio']), ModelModality.audio);
    });
    test('embedding', () {
      expect(classifyModality(pipelineTag: 'feature-extraction'), ModelModality.embedding);
    });
    test('unknown when no signals', () {
      expect(classifyModality(name: 'gemma-4-E2B-it'), ModelModality.unknown);
    });
  });
}
