@TestOn('vm')
@Tags(<String>['real-model', 'isolation-model'])
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:schemantic/schemantic.dart';
import 'package:test/test.dart';

import '../test_support/real_model_test_support.dart';

const _promptA = 'Once upon a time, in a quiet village near the mountains';
const _promptB = 'The planets of the solar system are';
const _cancelPrompt = 'Count from one to one thousand:';
const _sampling = GenerationParams(maxTokens: 8, temp: 0, seed: 42);

void main() {
  test(
    'public owners route a Genkit flow and isolate native cache/cancellation',
    () async {
      if (Platform.environment['LLAMADART_RUN_OWNER_PROOF'] != '1') {
        markTestSkipped(
          'Set LLAMADART_RUN_OWNER_PROOF=1 for native owner qualification.',
        );
        return;
      }
      final path = await resolveIntegrationModelPath();
      if (path == null) return;
      final file = File(path);
      expect(await file.length(), integrationChatModel.expectedSizeBytes);
      expect(
        (await sha256.bind(file.openRead()).first).toString(),
        integrationChatModel.expectedSha256,
      );
      final observer = _Observer();
      final pool = LlamaDartRuntimePool(
        model: LlamaModelDefinition(
          name: 'raw',
          modelPath: path,
          modelParams: const ModelParams(
            device: ComputeDevice.cpu,
            contextSize: 512,
            numberOfThreads: 1,
            numberOfThreadsBatch: 1,
            batchSize: 1,
            microBatchSize: 1,
          ),
        ),
        observers: [observer],
      );
      addTearDown(pool.close);
      final a = await pool.open();
      final b = await pool.open();
      final ai = Genkit();
      addTearDown(ai.shutdown);
      final flow = ai.defineFlow<String, String, void, void>(
        name: 'ownedRawCompletion',
        inputSchema: SchemanticType.string(minLength: 1),
        outputSchema: SchemanticType.string(),
        fn: (prompt, context) =>
            a.generate(prompt, params: _sampling, cancellation: context.cancel),
      );
      final baselineA = await flow(_promptA);
      expect(baselineA, isNotEmpty);
      final prefix = await b.scoreNextToken(
        _promptB,
        topK: 3,
        reusePromptPrefix: false,
      );
      await a.scoreNextToken(
        'A completely unrelated prompt',
        topK: 3,
        reusePromptPrefix: false,
      );
      final continuedB = await b.generate(
        '$_promptB Mercury',
        params: _sampling,
      );
      expect(observer.last!.usage!.cachedPromptTokens, prefix.promptTokens);
      final baselineB = await b.generate(
        '$_promptB Mercury',
        params: _sampling.copyWith(reusePromptPrefix: false),
      );
      expect(continuedB, baselineB);
      observer.cancel = a.cancelActiveGeneration;
      final cancelled = a.generate(
        _cancelPrompt,
        params: _sampling.copyWith(
          maxTokens: 128,
          streamBatchTokenThreshold: 1,
          streamBatchByteThreshold: 1,
        ),
      );
      final rejected = expectLater(
        cancelled,
        throwsA(isA<CancelledException>()),
      );
      expect(
        await b.generate(
          '$_promptB Mercury',
          params: _sampling.copyWith(reusePromptPrefix: false),
        ),
        baselineB,
      );
      await rejected;
      expect(a.isClosed, isTrue);
      expect(b.isClosed, isFalse);
      final replacement = await pool.open();
      expect(
        await replacement.generate(
          _promptA,
          params: _sampling.copyWith(reusePromptPrefix: false),
        ),
        baselineA,
      );
      print(
        'native owner proof: Genkit flow, B prefix reuse, A cancellation/cleanup and replacement pass',
      );
    },
  );
}

final class _Observer extends llama.LlamaEngineObserver {
  llama.LlamaOperationResult? last;
  void Function()? cancel;
  @override
  llama.LlamaOperationObserver onStart(llama.LlamaOperation operation) =>
      _Operation(
        this,
        operation is llama.LlamaTextCompletionOperation &&
            operation.prompt == _cancelPrompt,
      );
}

final class _Operation extends llama.LlamaOperationObserver {
  _Operation(this.owner, this.cancelledRequest);
  final _Observer owner;
  final bool cancelledRequest;
  @override
  void onText(String text) {
    if (cancelledRequest && owner.cancel != null) {
      final cancel = owner.cancel!;
      owner.cancel = null;
      cancel();
    }
  }

  @override
  void onEnd(llama.LlamaOperationResult result) => owner.last = result;
}
