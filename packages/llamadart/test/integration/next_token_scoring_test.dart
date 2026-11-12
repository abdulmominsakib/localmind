@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  late LlamaEngine engine;
  const prompt = 'Once upon a time, there was a little';
  const vocabSize = 32000;

  setUpAll(() async {
    final modelFile = await TestHelper.getTestModel();
    engine = LlamaEngine(LlamaBackend());
    await engine.loadModel(
      modelFile.path,
      modelParams: const ModelParams(
        numberOfThreads: 2,
        numberOfThreadsBatch: 2,
        contextSize: 256,
      ),
    );
  });

  tearDownAll(() async {
    await engine.dispose();
  });

  Future<String> greedy(String text, int maxTokens, {bool reuse = false}) =>
      engine
          .generate(
            text,
            params: GenerationParams(
              maxTokens: maxTokens,
              temp: 0,
              reusePromptPrefix: reuse,
            ),
          )
          .join();

  test('reports support on the native backend', () {
    expect(engine.supportsNextTokenScoring, isTrue);
  });

  test('scores the whole vocabulary as a distribution', () async {
    final scores = await engine.scoreNextToken(prompt, topK: vocabSize);

    expect(scores.top, hasLength(vocabSize));
    expect(scores.top.map((t) => t.token).toSet(), hasLength(vocabSize));
    final total = scores.top.fold<double>(0, (sum, t) => sum + t.probability);
    expect(total, closeTo(1, 1e-3));
    for (var i = 1; i < scores.top.length; i++) {
      expect(
        scores.top[i].logprob,
        lessThanOrEqualTo(scores.top[i - 1].logprob),
      );
    }
    expect(scores.promptTokens, (await engine.tokenize(prompt)).length);
  });

  test('ranks the greedy next token first', () async {
    final scores = await engine.scoreNextToken(prompt, topK: 5);
    final next = await greedy(prompt, 1);

    expect(scores.top, hasLength(5));
    expect(scores.top.first.text, next);
  });

  test('returns candidates in request order with top-k values', () async {
    final top = (await engine.scoreNextToken(prompt, topK: 3)).top;
    final ids = [top[2].token, 13, top[0].token];

    final scores = await engine.scoreNextToken(prompt, candidates: ids);

    expect(scores.top, isEmpty);
    expect(scores.candidates.map((t) => t.token), ids);
    expect(scores.candidates[0].logprob, closeTo(top[2].logprob, 1e-5));
    expect(scores.candidates[2].logprob, closeTo(top[0].logprob, 1e-5));
    expect(scores.candidates[0].bytes, top[2].bytes);
  });

  test('gives the same scores with and without prompt reuse', () async {
    const shared = 'Once upon a time, there was a little girl named';
    final fresh = await engine.scoreNextToken(
      shared,
      topK: 10,
      reusePromptPrefix: false,
    );
    final ids = [for (final t in fresh.top) t.token];
    await engine.scoreNextToken(prompt, topK: 1, reusePromptPrefix: false);
    final reused = await engine.scoreNextToken(shared, candidates: ids);

    expect(reused.promptTokens, fresh.promptTokens);
    for (var i = 0; i < ids.length; i++) {
      expect(reused.candidates[i].logprob, closeTo(fresh.top[i].logprob, 1e-2));
    }
  });

  test('leaves generation unchanged', () async {
    final before = await greedy(prompt, 8);
    await engine.scoreNextToken('The dog ran to the', topK: 1);
    expect(await greedy(prompt, 8), before);

    await engine.scoreNextToken('$prompt girl named Lily', topK: 1);
    expect(await greedy(prompt, 8, reuse: true), before);
  });

  test('waits for a running generation', () async {
    final before = await greedy(prompt, 32);
    final scored = Completer<LlamaNextTokenScores>();
    final chunks = <String>[];
    await for (final chunk in engine.generate(
      prompt,
      params: const GenerationParams(
        maxTokens: 32,
        temp: 0,
        reusePromptPrefix: false,
      ),
    )) {
      chunks.add(chunk);
      if (!scored.isCompleted) {
        scored.complete(engine.scoreNextToken(prompt, topK: 1));
      }
    }

    expect(chunks.join(), before);
    expect((await scored.future).top, hasLength(1));
  });

  test('rejects arguments outside the vocabulary', () async {
    await expectLater(
      engine.scoreNextToken(prompt, candidates: [vocabSize]),
      throwsRangeError,
    );
    await expectLater(
      engine.scoreNextToken(prompt, topK: vocabSize + 1),
      throwsRangeError,
    );
    final scores = await engine.scoreNextToken(prompt, candidates: [0]);
    expect(scores.candidates.single.logprob, lessThan(math.log(1e-3)));
  });
}
