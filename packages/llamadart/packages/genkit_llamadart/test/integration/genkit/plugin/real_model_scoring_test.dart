@Tags(<String>['real-model'])
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:test/test.dart';

import '../test_support/real_model_test_support.dart';

void main() {
  test(
    'real decoder scores candidates/top-K and remains usable for chat',
    () async {
      final path = await resolveIntegrationModelPath();
      if (path == null) return;
      final plugin = LlamaDartPlugin(
        models: [
          LlamaModelDefinition(
            name: 'scoring',
            modelPath: path,
            supportsEmbeddings: false,
            modelParams: const ModelParams(
              device: ComputeDevice.cpu,
              contextSize: 512,
            ),
          ),
        ],
      );
      final ai = Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(() async {
        await plugin.dispose();
        await ai.shutdown();
      });
      final scorer = plugin.scorer('scoring');
      final registered = await ai.registry.lookupAction(
        LlamaDartPlugin.scoringActionType,
        scorer.name,
      );
      final top =
          (await registered!.runRaw({
                'prompt': 'Once upon a time',
                'topK': 5,
                'reusePromptPrefix': false,
              })).result
              as LlamaDartTokenScores;
      expect(top.promptTokens, greaterThan(0));
      expect(top.top, hasLength(5));
      expect(top.top.every((s) => s.logprob.isFinite && s.logprob <= 0), true);
      expect(top.top.map((s) => s.token).toSet(), hasLength(5));
      expect(
        top.top.fold<double>(0, (sum, s) => sum + math.exp(s.logprob)),
        lessThanOrEqualTo(1.000001),
      );
      final ids = [top.top[2].token, top.top.first.token, top.top[2].token];
      final candidates = await scorer(
        LlamaDartScoringRequest(prompt: 'Once upon a time', candidates: ids),
      );
      expect(candidates.candidates.map((s) => s.token), ids);
      expect(
        candidates.candidates[0].logprob,
        closeTo(top.top[2].logprob, 1e-5),
      );
      expect(
        candidates.candidates[1].logprob,
        closeTo(top.top.first.logprob, 1e-5),
      );
      expect(candidates.candidates[2].bytes, top.top[2].bytes);
      expect(
        jsonDecode(jsonEncode(candidates))['promptTokens'],
        top.promptTokens,
      );
      for (final request in [
        LlamaDartScoringRequest(
          prompt: 'Once upon a time',
          candidates: [2147483647],
        ),
        LlamaDartScoringRequest(prompt: 'Once upon a time', topK: 2147483647),
      ]) {
        await expectLater(
          scorer(request),
          throwsA(
            isA<GenkitException>().having(
              (e) => e.status,
              'vocabulary guard',
              StatusCode.invalidArgument,
            ),
          ),
        );
      }
      final chat = await ai.generate(
        model: llamaDart.model('scoring'),
        prompt: 'Say hello.',
        config: const LlamaDartGenerationConfig(maxTokens: 8, temperature: 0),
      );
      expect(chat.text.trim(), isNotEmpty);
      final fresh = await scorer(
        LlamaDartScoringRequest(
          prompt: 'Once upon a time',
          candidates: ids,
          topK: 5,
          reusePromptPrefix: false,
        ),
      );
      expect(fresh.top.map((s) => s.token), top.top.map((s) => s.token));
      for (var i = 0; i < ids.length; i++) {
        expect(
          fresh.candidates[i].logprob,
          closeTo(candidates.candidates[i].logprob, 1e-5),
        );
      }
    },
  );
}
