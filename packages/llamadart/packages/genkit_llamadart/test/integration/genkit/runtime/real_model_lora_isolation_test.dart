@TestOn('vm')
@Tags(<String>['real-model', 'lora-model'])
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart' as genkit;
import 'package:test/test.dart';

const _params = ModelParams(
  device: ComputeDevice.cpu,
  contextSize: 256,
  numberOfThreads: 1,
  numberOfThreadsBatch: 1,
  batchSize: 1,
  microBatchSize: 1,
);
const _prompt = 'Is this';
const _baseSha =
    'cd144ca9826a7b009f8b841c247de6cf6c982735a1d13e9830cdd27447cfac16';
const _loraSha =
    'ecb2cbbbc49ad140b1be6c073a6221c785c4101aedc88e92e8029b67b7cbb50a';

void main() {
  test(
    'native live LoRA scale/remove/clear isolate A from B and restore baseline',
    () async {
      final base = Platform.environment['LLAMADART_TEST_LORA_BASE'];
      final adapter = Platform.environment['LLAMADART_TEST_LORA_ADAPTER'];
      if (base == null || adapter == null) {
        markTestSkipped(
          'Set both pinned LLAMADART_TEST_LORA_BASE and LLAMADART_TEST_LORA_ADAPTER paths.',
        );
        return;
      }
      await _verify(base, 76403584, _baseSha);
      await _verify(adapter, 19203744, _loraSha);
      final usageA = _Usage();
      final usageB = _Usage();
      final a = LlamaEngine(LlamaBackend(), observers: [usageA]);
      final b = LlamaEngine(LlamaBackend(), observers: [usageB]);
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await Future.wait([
        a.setModel(LlamaModel(ModelSource.path(base)), params: _params),
        b.setModel(LlamaModel(ModelSource.path(base)), params: _params),
      ]);
      expect(a.runtime, LlamaRuntime.llamaCpp);
      expect(b.runtime, LlamaRuntime.llamaCpp);
      expect((await a.capabilities).supportsNextTokenScoring, isTrue);
      final initial = await a.scoreNextToken(
        _prompt,
        topK: 8,
        reusePromptPrefix: false,
      );
      final candidates = initial.top.map((score) => score.token).toList();
      Future<LlamaNextTokenScores> score(LlamaEngine engine) =>
          engine.scoreNextToken(
            _prompt,
            candidates: candidates,
            topK: 8,
            reusePromptPrefix: false,
          );
      final baseline = await score(a);
      _sameScores(await score(b), baseline);
      final source = ModelSource.path(adapter);
      await a.setLoraSource(source);
      final applied = await score(a);
      expect(_difference(applied, baseline), greaterThan(0.01));
      _sameScores(await score(b), baseline);
      await a.setLoraSource(source, scale: 0.5);
      final half = await score(a);
      expect(_difference(half, applied), greaterThan(0.001));
      expect(_difference(half, baseline), greaterThan(0.001));
      _sameScores(await score(b), baseline);
      await a.setLoraSource(source, scale: 0);
      _sameScores(await score(a), baseline);
      await a.setLoraSource(source);
      _sameScores(await score(a), applied);
      await a.removeLoraSource(source);
      _sameScores(await score(a), baseline);
      await a.setLoraSource(source);
      await a.clearLoras();
      _sameScores(await score(a), baseline);
      _sameScores(await score(b), baseline);
      expect(usageA.loads, 1);
      expect(usageB.loads, 1);

      const generation = GenerationParams(maxTokens: 8, temp: 0, seed: 42);
      final baselineText = await a
          .generate(
            _prompt,
            params: generation.copyWith(reusePromptPrefix: false),
          )
          .join();
      await a.setLoraSource(source);
      final adaptedText = await a.generate(_prompt, params: generation).join();
      expect(usageA.last!.usage!.cachedPromptTokens, 0);
      expect(adaptedText, isNot(baselineText));
      await a.removeLoraSource(source);
      expect(
        await a.generate(_prompt, params: generation).join(),
        baselineText,
      );
      expect(usageA.last!.usage!.cachedPromptTokens, 0);
      expect(
        await b
            .generate(
              _prompt,
              params: generation.copyWith(reusePromptPrefix: false),
            )
            .join(),
        baselineText,
      );
      expect(usageA.loads, 1);
      expect(usageB.loads, 1);
      await expectLater(
        a.setLoraSource(ModelSource.path('$adapter.missing')),
        throwsA(isA<LlamaException>()),
      );
      await a.dispose();
      expect(
        await b
            .generate(
              _prompt,
              params: generation.copyWith(reusePromptPrefix: false),
            )
            .join(),
        baselineText,
      );
      print(
        'native LoRA proof: apply/half/zero/remove/clear, unchanged B and restored baseline pass without base reload',
      );
    },
  );
  test(
    'public owner live LoRA changes only A and invalidates cached prefixes',
    () async {
      final base = Platform.environment['LLAMADART_TEST_LORA_BASE'];
      final adapter = Platform.environment['LLAMADART_TEST_LORA_ADAPTER'];
      if (base == null || adapter == null) {
        markTestSkipped(
          'Set both pinned LLAMADART_TEST_LORA_BASE and LLAMADART_TEST_LORA_ADAPTER paths.',
        );
        return;
      }
      await _verify(base, 76403584, _baseSha);
      await _verify(adapter, 19203744, _loraSha);
      final usage = _Usage();
      final pool = genkit.LlamaDartRuntimePool(
        model: genkit.LlamaModelDefinition(
          name: 'lora',
          modelPath: base,
          modelParams: _params,
        ),
        observers: [usage],
      );
      addTearDown(pool.close);
      final a = await pool.open();
      final b = await pool.open();
      final initial = await a.scoreNextToken(
        _prompt,
        topK: 8,
        reusePromptPrefix: false,
      );
      final candidates = initial.top.map((value) => value.token).toList();
      Future<LlamaNextTokenScores> score(genkit.LlamaDartRuntimeOwner owner) =>
          owner.scoreNextToken(
            _prompt,
            candidates: candidates,
            topK: 8,
            reusePromptPrefix: false,
          );
      final baseline = await score(a);
      _sameScores(await score(b), baseline);
      final source = ModelSource.path(adapter);
      const generation = GenerationParams(maxTokens: 8, temp: 0, seed: 42);
      final baselineText = await a.generate(
        _prompt,
        params: generation.copyWith(reusePromptPrefix: false),
      );
      await a.setLoraSource(source);
      final appliedText = await a.generate(_prompt, params: generation);
      expect(appliedText, isNot(baselineText));
      expect(usage.last!.usage!.cachedPromptTokens, 0);
      final applied = await score(a);
      expect(_difference(applied, baseline), greaterThan(0.01));
      _sameScores(await score(b), baseline);
      await a.setLoraSource(source, scale: 0.5);
      expect(_difference(await score(a), applied), greaterThan(0.001));
      await a.setLoraSource(source, scale: 0);
      _sameScores(await score(a), baseline);
      await a.removeLoraSource(source);
      expect(await a.generate(_prompt, params: generation), baselineText);
      expect(usage.last!.usage!.cachedPromptTokens, 0);
      await a.setLoraSource(source);
      await a.clearLoras();
      expect(await a.generate(_prompt, params: generation), baselineText);
      expect(usage.last!.usage!.cachedPromptTokens, 0);
      _sameScores(await score(b), baseline);
      expect(usage.loads, 2);
      await expectLater(
        a.setLoraSource(ModelSource.path('$adapter.missing')),
        throwsA(isA<genkit.LlamaStateException>()),
      );
      expect(a.isClosed, isTrue);
      expect(
        await b.generate(
          _prompt,
          params: generation.copyWith(reusePromptPrefix: false),
        ),
        baselineText,
      );
      expect(usage.loads, 2);
      print(
        'public owner LoRA proof: all mutations, cache invalidation, failed A cleanup and unchanged B pass',
      );
    },
  );
}

Future<void> _verify(String path, int size, String hash) async {
  final file = File(path);
  expect(await file.length(), size);
  expect((await sha256.bind(file.openRead()).first).toString(), hash);
}

void _sameScores(LlamaNextTokenScores actual, LlamaNextTokenScores expected) {
  expect(
    actual.top.map((value) => value.token),
    expected.top.map((value) => value.token),
  );
  expect(actual.promptTokens, expected.promptTokens);
  expect(
    actual.candidates.map((value) => value.token),
    expected.candidates.map((value) => value.token),
  );
  for (var i = 0; i < actual.candidates.length; i++) {
    expect(
      actual.candidates[i].logprob,
      closeTo(expected.candidates[i].logprob, 1e-5),
    );
  }
}

double _difference(LlamaNextTokenScores actual, LlamaNextTokenScores baseline) {
  return [
    for (var i = 0; i < actual.candidates.length; i++)
      (actual.candidates[i].logprob - baseline.candidates[i].logprob).abs(),
  ].reduce(math.max);
}

final class _Usage extends LlamaEngineObserver {
  int loads = 0;
  LlamaOperationResult? last;
  @override
  LlamaOperationObserver onStart(LlamaOperation operation) {
    if (operation is LlamaModelLoadOperation) loads++;
    return _Result(this);
  }
}

final class _Result extends LlamaOperationObserver {
  _Result(this.owner);
  final _Usage owner;
  @override
  void onEnd(LlamaOperationResult result) => owner.last = result;
}
