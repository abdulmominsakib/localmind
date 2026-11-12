@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../support/synthetic_embedding_gguf.dart';

/// llama.cpp throws a C++ exception for the inputs below. Through
/// [LlamaEngine] and the worker isolate that is a typed error and the engine
/// keeps working; before `llamadart-native` `v0.6.0-1` it ended the process.
void main() {
  late Directory dir;
  late LlamaEngine engine;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('llamadart_barrier_engine_');
    final model = writeSyntheticLlamaGguf('${dir.path}/model.gguf');
    engine = LlamaEngine(LlamaBackend());
    await engine.loadModel(
      model.path,
      modelParams: const ModelParams(contextSize: 64, gpuLayers: 0),
    );
  });

  tearDownAll(() async {
    await engine.dispose();
    dir.deleteSync(recursive: true);
  });

  test('detokenize throws LlamaInferenceException for a token outside the '
      'vocabulary', () async {
    await expectLater(
      engine.detokenize([-1]),
      throwsA(
        isA<LlamaInferenceException>().having(
          (e) => e.message,
          'message',
          startsWith(
            'llama.cpp raised an exception in llama_token_to_piece. (',
          ),
        ),
      ),
    );
  }, skip: Platform.isWindows ? 'leaves the model free-only there' : false);

  test('a lazy-grammar trigger pattern that is not a regular expression '
      'fails the generation with LlamaInferenceException', () async {
    await expectLater(
      engine
          .generate(
            'ab',
            params: const GenerationParams(
              maxTokens: 2,
              grammar: 'root ::= "a"',
              grammarLazy: true,
              grammarTriggers: [
                GenerationGrammarTrigger.typed(
                  type: GrammarTriggerType.pattern,
                  value: '(',
                ),
              ],
            ),
          )
          .drain<void>(),
      throwsA(
        isA<LlamaInferenceException>().having(
          (e) => e.message,
          'message',
          startsWith(
            'llama.cpp raised an exception in '
            'llama_sampler_init_grammar_lazy_patterns. (',
          ),
        ),
      ),
    );
  }, skip: Platform.isWindows ? 'leaves the model free-only there' : false);

  test('the engine still tokenizes and generates afterwards', () async {
    expect(await engine.tokenize('ab'), isNotEmpty);
    await engine
        .generate('ab', params: const GenerationParams(maxTokens: 2))
        .drain<void>();
  });
}
