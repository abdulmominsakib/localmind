import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:test/test.dart';

void main() {
  test('GenerationParams copyWith updates selected fields', () {
    const params = GenerationParams(temp: 0.5, maxTokens: 10);
    final updated = params.copyWith(
      topK: 12,
      minP: 0.05,
      presencePenalty: 1.5,
      grammarRoot: 'main',
      grammarLazy: true,
      thinkingBudget: const ThinkingBudget(
        maxTokens: 64,
        startTag: '<think>',
        endTag: '</think>',
      ),
      speculativeDecoding: true,
      speculativeDecodingConfig: const SpeculativeDecodingConfig.mtp(
        draftTokenMax: 3,
        draftModelPath: 'draft.gguf',
      ),
      reusePromptPrefix: false,
      streamBatchTokenThreshold: 4,
      streamBatchByteThreshold: 256,
      grammarTriggers: [
        const GenerationGrammarTrigger(type: 0, value: '<tool_call>'),
      ],
      preservedTokens: const ['<tool_call>'],
    );

    expect(updated.temp, 0.5);
    expect(updated.maxTokens, 10);
    expect(updated.topK, 12);
    expect(updated.minP, 0.05);
    expect(updated.presencePenalty, 1.5);
    expect(updated.grammarRoot, 'main');
    expect(updated.grammarLazy, isTrue);
    expect(updated.thinkingBudget?.maxTokens, 64);
    expect(updated.thinkingBudget?.startTag, '<think>');
    expect(updated.thinkingBudget?.endTag, '</think>');
    expect(updated.speculativeDecoding, isTrue);
    expect(updated.isSpeculativeDecodingEnabled, isTrue);
    expect(
      updated.resolvedSpeculativeDecodingConfig?.strategy,
      SpeculativeDecodingStrategy.mtp,
    );
    expect(updated.resolvedSpeculativeDecodingConfig?.draftTokenMax, 3);
    expect(
      updated.resolvedSpeculativeDecodingConfig?.draftModelPath,
      'draft.gguf',
    );
    expect(updated.reusePromptPrefix, isFalse);
    expect(updated.streamBatchTokenThreshold, 4);
    expect(updated.streamBatchByteThreshold, 256);
    expect(updated.grammarTriggers, hasLength(1));
    expect(updated.preservedTokens, const ['<tool_call>']);
  });

  test('GenerationParams copyWith can clear thinking budget', () {
    const params = GenerationParams(
      thinkingBudget: ThinkingBudget(
        maxTokens: 64,
        startTag: '<think>',
        endTag: '</think>',
      ),
    );

    final updated = params.copyWith(clearThinkingBudget: true);

    expect(updated.thinkingBudget, isNull);
  });

  test('GenerationParams defaults minP to zero', () {
    const params = GenerationParams();

    expect(params.minP, 0.0);
    expect(params.presencePenalty, 0.0);
    expect(params.speculativeDecoding, isFalse);
    expect(params.speculativeDecodingConfig, isNull);
    expect(params.isSpeculativeDecodingEnabled, isFalse);
    expect(params.resolvedSpeculativeDecodingConfig, isNull);
  });

  test('GenerationParams defaults stream batching thresholds', () {
    const params = GenerationParams();

    expect(params.reusePromptPrefix, isTrue);
    expect(params.streamBatchTokenThreshold, 8);
    expect(params.streamBatchByteThreshold, 512);
  });

  test('GenerationParams resolves legacy speculative decoding as default', () {
    const params = GenerationParams(speculativeDecoding: true);

    expect(params.isSpeculativeDecodingEnabled, isTrue);
    expect(
      params.resolvedSpeculativeDecodingConfig?.strategy,
      SpeculativeDecodingStrategy.backendDefault,
    );
  });

  test('SpeculativeDecodingConfig.ngramSimple stores n-gram controls', () {
    const config = SpeculativeDecodingConfig.ngramSimple(
      draftTokenMax: 6,
      ngramSize: 10,
      ngramSizeM: 12,
      ngramMinHits: 2,
    );
    const params = GenerationParams(speculativeDecodingConfig: config);

    expect(params.isSpeculativeDecodingEnabled, isTrue);
    expect(
      params.resolvedSpeculativeDecodingConfig?.strategy,
      SpeculativeDecodingStrategy.ngramSimple,
    );
    expect(params.resolvedSpeculativeDecodingConfig?.draftTokenMax, 6);
    expect(params.resolvedSpeculativeDecodingConfig?.ngramSize, 10);
    expect(params.resolvedSpeculativeDecodingConfig?.ngramSizeN, 10);
    expect(params.resolvedSpeculativeDecodingConfig?.ngramSizeM, 12);
    expect(params.resolvedSpeculativeDecodingConfig?.ngramMinHits, 2);
    expect(params.resolvedSpeculativeDecodingConfig?.draftModelPath, isNull);
    expect(params.resolvedSpeculativeDecodingConfig?.draftTokenMin, isNull);
    expect(params.resolvedSpeculativeDecodingConfig?.minProbability, isNull);
  });

  test(
    'SpeculativeDecodingConfig resolves ngramSize alias from ngramSizeN',
    () {
      const simple = SpeculativeDecodingConfig.ngramSimple(
        ngramSize: 8,
        ngramSizeN: 4,
      );
      const mapK = SpeculativeDecodingConfig.ngramMapK(
        ngramSize: 8,
        ngramSizeN: 4,
      );
      const mapK4v = SpeculativeDecodingConfig.ngramMapK4v(
        ngramSize: 8,
        ngramSizeN: 4,
      );

      expect(simple.ngramSize, 4);
      expect(simple.ngramSizeN, 4);
      expect(mapK.ngramSize, 4);
      expect(mapK.ngramSizeN, 4);
      expect(mapK4v.ngramSize, 4);
      expect(mapK4v.ngramSizeN, 4);
    },
  );

  test('SpeculativeDecodingConfig stores draft model strategies', () {
    const eagle = SpeculativeDecodingConfig.draftEagle3(
      draftTokenMax: 4,
      draftTokenMin: 1,
      minProbability: 0.2,
      draftSplitProbability: 0.15,
      draftModelPath: 'eagle.gguf',
    );
    const dflash = SpeculativeDecodingConfig.draftDflash(
      draftModelPath: 'dflash.gguf',
    );

    expect(eagle.strategy, SpeculativeDecodingStrategy.draftEagle3);
    expect(eagle.strategies, [SpeculativeDecodingStrategy.draftEagle3]);
    expect(eagle.draftTokenMax, 4);
    expect(eagle.draftTokenMin, 1);
    expect(eagle.minProbability, 0.2);
    expect(eagle.draftSplitProbability, 0.15);
    expect(eagle.draftModelPath, 'eagle.gguf');
    expect(dflash.strategy, SpeculativeDecodingStrategy.draftDflash);
    expect(dflash.draftModelPath, 'dflash.gguf');
  });

  test('SpeculativeDecodingConfig stores ngram-mod and cache controls', () {
    const mod = SpeculativeDecodingConfig.ngramMod(
      draftTokenMax: 32,
      ngramMatch: 16,
      ngramTokenMin: 8,
      ngramTokenMax: 32,
    );
    const cache = SpeculativeDecodingConfig.ngramCache(
      ngramCacheStaticPath: 'static.ngram',
      ngramCacheDynamicPath: 'dynamic.ngram',
    );

    expect(mod.strategy, SpeculativeDecodingStrategy.ngramMod);
    expect(mod.ngramMatch, 16);
    expect(mod.ngramTokenMin, 8);
    expect(mod.ngramTokenMax, 32);
    expect(cache.strategy, SpeculativeDecodingStrategy.ngramCache);
    expect(cache.ngramCacheStaticPath, 'static.ngram');
    expect(cache.ngramCacheDynamicPath, 'dynamic.ngram');
  });

  test('SpeculativeDecodingConfig.mixed stores upstream strategy list', () {
    const config = SpeculativeDecodingConfig.mixed(
      strategies: [
        SpeculativeDecodingStrategy.ngramMod,
        SpeculativeDecodingStrategy.mtp,
      ],
      draftTokenMax: 4,
    );

    expect(config.strategy, SpeculativeDecodingStrategy.backendDefault);
    expect(config.effectiveStrategies, [
      SpeculativeDecodingStrategy.ngramMod,
      SpeculativeDecodingStrategy.mtp,
    ]);
    expect(config.draftTokenMax, 4);
  });

  test('GenerationParams copyWith can clear speculative decoding config', () {
    const params = GenerationParams(
      speculativeDecodingConfig: SpeculativeDecodingConfig.mtp(
        draftTokenMax: 3,
      ),
    );
    final updated = params.copyWith(clearSpeculativeDecodingConfig: true);

    expect(updated.speculativeDecodingConfig, isNull);
    expect(updated.isSpeculativeDecodingEnabled, isFalse);
  });
}
