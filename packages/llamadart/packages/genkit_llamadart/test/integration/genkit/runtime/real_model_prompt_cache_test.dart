@TestOn('vm')
@Tags(['real-model', 'prompt-cache-model'])
library;

import 'dart:io';

import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

import '../test_support/real_model_test_support.dart';

const _prompt = 'Once upon a time, in a quiet village near the mountains';
const _sampling = GenerationParams(maxTokens: 8, temp: 0, seed: 42);

void main() {
  test(
    'public raw prompt caches isolate, restore, bound and clean native state',
    () async {
      if (Platform.environment['LLAMADART_RUN_PROMPT_CACHE_PROOF'] != '1') {
        markTestSkipped(
          'Set LLAMADART_RUN_PROMPT_CACHE_PROOF=1 for native prompt-cache qualification.',
        );
        return;
      }
      final path = await resolveIntegrationModelPath();
      if (path == null) return;
      final observer = _Observer();
      LlamaDartRuntimePool makePool({int maxBytes = 64 * 1024 * 1024}) =>
          LlamaDartRuntimePool(
            model: LlamaModelDefinition(
              name: 'cache',
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
            enablePromptCache: true,
            maxPromptCaches: 1,
            maxPromptCacheBytes: maxBytes,
            observers: [observer],
          );
      final pool = makePool();
      addTearDown(pool.close);
      final a = await pool.open();
      final b = await pool.open();
      final cache = await a.cachePrompt(_prompt);
      expect(cache.tokenCount, greaterThan(2));
      expect('$cache', isNot(contains(_prompt)));
      await b.scoreNextToken(
        'The planets of the solar system are',
        topK: 1,
        reusePromptPrefix: false,
      );
      final resumed = await a.generateFromCache(cache, params: _sampling);
      expect(resumed, isNotEmpty);
      expect(observer.last!.usage!.cachedPromptTokens, cache.tokenCount - 1);
      final baseline = await a.generate(
        _prompt,
        params: _sampling.copyWith(reusePromptPrefix: false),
      );
      expect(resumed, baseline);
      await a.clearLoras();
      await expectLater(
        a.generateFromCache(cache, params: _sampling),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(a.isClosed, isTrue);
      final reopened = await pool.open();
      expect(
        await reopened.generateFromCache(cache, params: _sampling),
        baseline,
      );
      expect(observer.last!.usage!.cachedPromptTokens, cache.tokenCount - 1);
      final controller = CancellationController()..cancel();
      await expectLater(
        reopened.generateFromCache(cache, cancellation: controller.token),
        throwsA(isA<CancelledException>()),
      );
      expect(reopened.isClosed, isFalse);
      await expectLater(
        b.cachePrompt('over quota'),
        throwsA(isA<LlamaStateException>()),
      );
      expect(b.isClosed, isTrue);
      expect(
        await reopened.generateFromCache(cache, params: _sampling),
        baseline,
      );
      cache.dispose();
      cache.dispose();
      await expectLater(
        reopened.generateFromCache(cache),
        throwsA(isA<LlamaStateException>()),
      );
      expect(reopened.isClosed, isTrue);
      final replacement = await pool.open();
      final next = await replacement.cachePrompt(_prompt);
      await replacement.close();
      final otherPool = makePool();
      addTearDown(otherPool.close);
      final foreign = await otherPool.open();
      await expectLater(
        foreign.generateFromCache(next),
        throwsA(isA<LlamaStateException>()),
      );
      final tinyPool = makePool(maxBytes: 1);
      addTearDown(tinyPool.close);
      final tiny = await tinyPool.open();
      await expectLater(
        tiny.cachePrompt(_prompt),
        throwsA(isA<LlamaStateException>()),
      );
      expect(tiny.isClosed, isTrue);
      await pool.close();
      expect(next.isDisposed, isTrue);
      final example = await Process.run(Platform.resolvedExecutable, [
        'run',
        'example/genkit_llamadart_prompt_cache_example.dart',
        path,
      ]);
      expect(
        example.exitCode,
        0,
        reason: 'The prompt-cache CLI must complete successfully.',
      );
      expect('${example.stdout}'.trim(), isNotEmpty);
      final directory = await Directory.systemTemp.createTemp(
        'genkit-cache-identity-proof-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final changedFile = await File(path).copy('${directory.path}/model.gguf');
      final identityPool = LlamaDartRuntimePool(
        model: LlamaModelDefinition(
          name: 'identity',
          modelPath: changedFile.path,
          modelParams: const ModelParams(
            device: ComputeDevice.cpu,
            contextSize: 512,
            numberOfThreads: 1,
            numberOfThreadsBatch: 1,
          ),
        ),
        enablePromptCache: true,
      );
      addTearDown(identityPool.close);
      final identityOwner = await identityPool.open();
      final identityCache = await identityOwner.cachePrompt(_prompt);
      await changedFile.writeAsBytes([0], mode: FileMode.append, flush: true);
      await expectLater(
        identityOwner.generateFromCache(identityCache),
        throwsA(
          predicate<Object>(
            (e) =>
                e is LlamaStateException &&
                !e.toString().contains(changedFile.path),
          ),
        ),
      );
      expect(identityOwner.isClosed, isTrue);
      print(
        'native prompt-cache proof: same-pool reopen/KV reuse, isolated B, quotas, cancellation, disposed/foreign handles and cleanup pass',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

final class _Observer extends llama.LlamaEngineObserver {
  llama.LlamaOperationResult? last;
  @override
  llama.LlamaOperationObserver onStart(llama.LlamaOperation operation) =>
      _Operation(this);
}

final class _Operation extends llama.LlamaOperationObserver {
  _Operation(this.owner);
  final _Observer owner;
  @override
  void onEnd(llama.LlamaOperationResult result) => owner.last = result;
}
