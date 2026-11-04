@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'package:test/test.dart';
import 'package:llamadart/llamadart.dart';
import '../../../test_helper.dart';

void main() async {
  late File modelFile;
  late LlamaEngine engine;
  late LlamaBackend backend;

  setUpAll(() async {
    modelFile = await TestHelper.getTestModel();
    backend = LlamaBackend();
    engine = LlamaEngine(backend);
  });

  tearDownAll(() async {
    await engine.dispose();
  });

  group('Grammar Regression Tests', () {
    test('Fixed string constraint (root ::= "BOO")', () async {
      if (!engine.isReady) {
        await engine.loadModel(
          modelFile.path,
          modelParams: const ModelParams(contextSize: 256),
        );
      }

      final stream = engine.create(
        [
          const LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'Say the word BOO',
          ),
        ],
        params: const GenerationParams(
          grammar: 'root ::= "BOO"',
          maxTokens: 10,
          temp: 0,
        ),
      );
      final result = await stream
          .map((c) => c.choices.first.delta.content ?? '')
          .join();
      expect(result, equals('BOO'));
    });

    test('Choice constraint (root ::= "yes" | "no")', () async {
      if (!engine.isReady) {
        await engine.loadModel(
          modelFile.path,
          modelParams: const ModelParams(contextSize: 256),
        );
      }

      final stream = engine.create(
        [
          const LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'Is the sky blue? Answer yes or no.',
          ),
        ],
        params: const GenerationParams(
          grammar: 'root ::= "yes" | "no"',
          maxTokens: 10,
          temp: 0,
        ),
      );
      final result = await stream
          .map((c) => c.choices.first.delta.content ?? '')
          .join();
      expect(['yes', 'no'], contains(result.trim().toLowerCase()));
    });

    test('Longer structured output constraint', () async {
      if (!engine.isReady) {
        await engine.loadModel(
          modelFile.path,
          modelParams: const ModelParams(contextSize: 256),
        );
      }

      // Grammar that forces a specific sentence structure
      const grammar =
          'root ::= "The " ("cat" | "dog") " is " ("happy" | "sad") "."';

      final stream = engine.create(
        [
          const LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'Describe the animal',
          ),
        ],
        params: const GenerationParams(
          grammar: grammar,
          maxTokens: 20,
          temp: 0,
        ),
      );
      final result = await stream
          .map((c) => c.choices.first.delta.content ?? '')
          .join();

      final regex = RegExp(r'^The (cat|dog) is (happy|sad)\.$');
      expect(
        regex.hasMatch(result),
        isTrue,
        reason: 'Output "$result" does not match grammar',
      );
    });
  });
}
