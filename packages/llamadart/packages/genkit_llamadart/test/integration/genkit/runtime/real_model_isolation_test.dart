@TestOn('vm')
@Tags(<String>['real-model', 'isolation-model'])
library;

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../test_support/real_model_test_support.dart';

const _sampling = GenerationParams(maxTokens: 8, temp: 0, seed: 42);
const _promptA = 'Once upon a time, in a quiet village near the mountains';
const _promptB = 'The planets of the solar system are';

void main() {
  test(
    'dedicated native contexts isolate raw prompt checkpoints and reuse KV',
    () async {
      if (Platform.environment['LLAMADART_RUN_ISOLATION_PROOF'] != '1') {
        markTestSkipped(
          'Set LLAMADART_RUN_ISOLATION_PROOF=1 for the bounded native proof.',
        );
        return;
      }
      final batchSize = int.parse(
        Platform.environment['LLAMADART_ISOLATION_BATCH_SIZE'] ?? '1',
      );
      if (batchSize != 0 && batchSize != 1) {
        throw ArgumentError(
          'The proof supports batch sizes 0 (automatic) or 1 only.',
        );
      }
      final params = ModelParams(
        device: ComputeDevice.cpu,
        contextSize: 512,
        numberOfThreads: 1,
        numberOfThreadsBatch: 1,
        batchSize: batchSize,
        microBatchSize: batchSize,
      );
      final path = await resolveIntegrationModelPath();
      if (path == null) return;
      final fixture = File(path);
      expect(await fixture.length(), integrationChatModel.expectedSizeBytes);
      expect(
        (await sha256.bind(fixture.openRead()).first).toString(),
        integrationChatModel.expectedSha256,
      );

      final directory = await Directory.systemTemp.createTemp(
        'genkit-kv-proof-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final observedA = _Usage();
      final observedB = _Usage();
      final a = LlamaEngine(LlamaBackend(), observers: [observedA]);
      final b = LlamaEngine(LlamaBackend(), observers: [observedB]);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await Future.wait([
        a.setModel(LlamaModel(ModelSource.path(path)), params: params),
        b.setModel(LlamaModel(ModelSource.path(path)), params: params),
      ]);
      expect(a.runtime, LlamaRuntime.llamaCpp);
      expect(b.runtime, LlamaRuntime.llamaCpp);
      expect(a.supportsStatePersistence && b.supportsStatePersistence, isTrue);
      expect(a.supportsNextTokenScoring && b.supportsNextTokenScoring, isTrue);

      final initial = await a.scoreNextToken(
        _promptA,
        topK: 5,
        reusePromptPrefix: false,
      );
      final tokensA = await a.tokenize(_promptA, addSpecial: true);
      expect(tokensA.length, initial.promptTokens);
      expect(tokensA.length, greaterThan(2));
      final checkpoint = '${directory.path}/a.bin';
      expect(await a.stateSaveFile(checkpoint, tokens: tokensA), isTrue);
      expect(await File(checkpoint).length(), greaterThan(0));

      final bScores = await b.scoreNextToken(
        _promptB,
        topK: 5,
        reusePromptPrefix: false,
      );
      final tokensB = await b.tokenize(_promptB, addSpecial: true);
      expect(tokensB.length, bScores.promptTokens);
      final bPerf = await b.getPerformanceContext();

      await a.scoreNextToken(
        'A completely unrelated prompt',
        topK: 5,
        reusePromptPrefix: false,
      );
      final restored = await a.stateLoadFile(
        checkpoint,
        tokenCapacity: params.contextSize,
      );
      expect(restored.tokens, tokensA);
      final restoredScores = await a.scoreNextToken(_promptA, topK: 5);
      _expectScores(restoredScores, initial);
      final unchangedB = await b.getPerformanceContext();
      expect(unchangedB!.promptEvalTokens, bPerf!.promptEvalTokens);
      expect(unchangedB.evalTokens, bPerf.evalTokens);

      await a.stateLoadFile(checkpoint, tokenCapacity: params.contextSize);
      final resumed = await a.generate(_promptA, params: _sampling).join();
      final resumedUsage = observedA.last!.usage!;
      expect(resumedUsage.cachedPromptTokens, tokensA.length - 1);
      expect(resumedUsage.promptTokens, tokensA.length);
      final fresh = await a
          .generate(
            _promptA,
            params: _sampling.copyWith(reusePromptPrefix: false),
          )
          .join();
      expect(resumed, isNotEmpty);
      expect(resumed, fresh);
      expect(observedA.last!.usage!.cachedPromptTokens, 0);

      final continuedB = await b
          .generate('$_promptB Mercury', params: _sampling)
          .join();
      expect(observedB.last!.usage!.cachedPromptTokens, tokensB.length);
      final freshB = await b
          .generate(
            '$_promptB Mercury',
            params: _sampling.copyWith(reusePromptPrefix: false),
          )
          .join();
      expect(continuedB, freshB);

      await a.dispose();
      final reopened = LlamaEngine(LlamaBackend(), observers: [observedA]);
      addTearDown(reopened.dispose);
      await reopened.setModel(
        LlamaModel(ModelSource.path(path)),
        params: params,
      );
      expect(
        (await reopened.stateLoadFile(
          checkpoint,
          tokenCapacity: params.contextSize,
        )).tokens,
        tokensA,
      );
      expect(
        await reopened.generate(_promptA, params: _sampling).join(),
        fresh,
      );
      expect(observedA.last!.usage!.cachedPromptTokens, tokensA.length - 1);

      final firstAChunk = Completer<void>();
      final firstBChunk = Completer<void>();
      final cancelledA = () async {
        await for (final _ in reopened.generate(
          'Count from one to one thousand:',
          params: _sampling.copyWith(
            maxTokens: 128,
            streamBatchTokenThreshold: 1,
            streamBatchByteThreshold: 1,
          ),
        )) {
          if (!firstAChunk.isCompleted) {
            firstAChunk.complete();
            await firstBChunk.future;
            reopened.cancelGeneration();
          }
        }
      }();
      await firstAChunk.future;
      final concurrentB = () async {
        final output = StringBuffer();
        await for (final chunk in b.generate(
          '$_promptB Mercury',
          params: _sampling.copyWith(
            reusePromptPrefix: false,
            streamBatchTokenThreshold: 1,
            streamBatchByteThreshold: 1,
          ),
        )) {
          output.write(chunk);
          if (!firstBChunk.isCompleted) firstBChunk.complete();
        }
        expect(firstBChunk.isCompleted, isTrue);
        return output.toString();
      }();
      final settled = await Future.wait<Object?>([cancelledA, concurrentB]);
      expect(observedA.last!.cancelled, isTrue);
      expect(observedB.last!.cancelled, isFalse);
      expect(settled[1], freshB);
      await expectLater(
        reopened.stateLoadFile(checkpoint, tokenCapacity: 1),
        throwsA(isA<LlamaException>()),
      );
      await reopened.dispose();
      final corrupt = File('${directory.path}/corrupt.bin');
      await corrupt.writeAsBytes([0, 1, 2, 3]);
      final failed = LlamaEngine(LlamaBackend());
      addTearDown(failed.dispose);
      await failed.setModel(LlamaModel(ModelSource.path(path)), params: params);
      await expectLater(
        failed.stateLoadFile(corrupt.path, tokenCapacity: params.contextSize),
        throwsA(isA<LlamaException>()),
      );
      await failed.dispose();
      final initializationFailure = LlamaEngine(LlamaBackend());
      addTearDown(initializationFailure.dispose);
      await expectLater(
        initializationFailure.setModel(
          LlamaModel(ModelSource.path('${directory.path}/missing.gguf')),
          params: params,
        ),
        throwsA(isA<LlamaException>()),
      );
      await initializationFailure.dispose();
      expect(
        await b
            .generate(
              '$_promptB Mercury',
              params: _sampling.copyWith(reusePromptPrefix: false),
            )
            .join(),
        freshB,
      );
      print(
        'raw checkpoint proof: promptTokens=${tokensA.length}, restoredCachedTokens=${resumedUsage.cachedPromptTokens}, independent B continuation and reopen pass',
      );
    },
  );
}

void _expectScores(LlamaNextTokenScores actual, LlamaNextTokenScores expected) {
  expect(actual.promptTokens, expected.promptTokens);
  expect(
    actual.top.map((score) => score.token),
    expected.top.map((score) => score.token),
  );
  for (var i = 0; i < actual.top.length; i++) {
    expect(actual.top[i].logprob, closeTo(expected.top[i].logprob, 1e-5));
  }
}

final class _Usage extends LlamaEngineObserver {
  LlamaOperationResult? last;

  @override
  LlamaOperationObserver onStart(LlamaOperation operation) => _Result(this);
}

final class _Result extends LlamaOperationObserver {
  _Result(this.owner);
  final _Usage owner;

  @override
  void onEnd(LlamaOperationResult result) => owner.last = result;
}
