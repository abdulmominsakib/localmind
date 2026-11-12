part of 'runner.dart';

/// Optional public sampler-control boundary; reference adapters need not
/// expose raw generation parameters.
abstract interface class SamplerValidationEngine {
  /// The loaded engine's reported generation controls.
  Future<LlamaEngineCapabilities> samplerCapabilities();

  /// Streams raw [prompt] with exactly [params] and returns the joined text.
  Future<String> generateSampled(String prompt, GenerationParams params);
}

mixin _PublicSamplerValidation implements SamplerValidationEngine {
  LlamaEngine get _engine;

  @override
  Future<LlamaEngineCapabilities> samplerCapabilities() => _engine.capabilities;

  @override
  Future<String> generateSampled(
    String prompt,
    GenerationParams params,
  ) async => (await _engine.generate(prompt, params: params).toList()).join();
}

extension _SamplerValidation on ValidationRunner {
  Future<Map<String, dynamic>> _samplerCase(String id) async {
    if (engine is! SamplerValidationEngine) {
      return {'status': 'NOT_RUN', 'reason': 'sampler_adapter_unavailable'};
    }
    final sampler = engine as SamplerValidationEngine;
    final diagnostics = await _checked(engine.diagnostics);
    final capabilities = await _checked(sampler.samplerCapabilities);
    final expected = expectedSamplerCapabilities(
      profile,
      web: engine.isWeb,
      diagnostics: diagnostics,
    );
    final evidence = <String, dynamic>{
      'reported': {
        'penalty': capabilities.supportsPenalty,
        'presence_penalty': capabilities.supportsPresencePenalty,
        'min_p': capabilities.supportsMinP,
        'thinking_budget': capabilities.supportsThinkingBudget,
      },
      'diagnostics': diagnostics,
      'web': engine.isWeb,
    };
    _partialCaseEvidence = evidence;
    if (expected == null) {
      return {
        ...evidence,
        'status': 'NOT_RUN',
        'reason': 'sampler_profile_or_host_unqualified',
      };
    }
    final fixture = profile.fixtures['sampler_controls'] as Map;
    final base = profile.generationParams.copyWith(
      maxTokens: fixture['max_tokens'] as int,
      temp: 0,
      topK: 0,
      topP: 1,
      minP: 0,
      penalty: 1,
      presencePenalty: 0,
    );
    final prompt = fixture['prompt'] as String;
    final budgetPrompt = fixture['budget_prompt'] as String;
    ThinkingBudget budget(int tokens, {bool tagged = true}) => ThinkingBudget(
      maxTokens: tokens,
      startTag: tagged ? fixture['start_tag'] as String : null,
      endTag: tagged ? fixture['end_tag'] as String : null,
      forcedMessage: fixture['forced_message'] as String,
    );
    Future<String> run(String text, GenerationParams params) =>
        _checked(() => sampler.generateSampled(text, params));
    Future<String> rejection(GenerationParams params) async {
      try {
        await sampler.generateSampled(prompt, params);
        return 'accepted';
      } catch (error) {
        return error.runtimeType.toString();
      }
    }

    _operationPhase = 'sampler.$id';
    if (id == 'G01.capability') {
      final probes = <String, GenerationParams>{
        'penalty': base.copyWith(penalty: fixture['repeat_penalty'] as double),
        'presence_penalty': base.copyWith(
          presencePenalty: fixture['presence_penalty'] as double,
        ),
        'min_p': base.copyWith(minP: fixture['unsupported_min_p'] as double),
        'thinking_budget': base.copyWith(
          thinkingBudget: budget((fixture['budgets'] as List).last as int),
        ),
      };
      final rejections = <String, String>{
        for (final flag in samplerCapabilityFlags)
          if (expected[flag] == false) flag: await rejection(probes[flag]!),
      };
      evidence['rejections'] = rejections;
      if (rejections.isNotEmpty) {
        evidence['recovery'] = await _checked(
          () => engine.generate(_shortPrompt, profile, raw: !profile.isChat),
        );
      }
      return {
        ...evidence,
        'status': _validSampler(id, evidence, diagnostics) ? 'PASS' : 'FAIL',
      };
    }
    if (expected.values.any((flag) => flag != true) ||
        (evidence['reported'] as Map).values.any((flag) => flag != true)) {
      return {
        ...evidence,
        'status': 'FAIL',
        'reason': 'required_sampler_capability_missing',
      };
    }
    evidence['model_sha256'] = profile.model['sha256'];
    evidence['config_hash'] = jsonHash(profile.effectiveConfig);
    switch (id) {
      case 'G02.min_p':
        final seeds = (fixture['seeds'] as List).cast<int>();
        final sampled = base.copyWith(
          temp: fixture['sampling_temperature'] as double,
        );
        evidence['seeds'] = seeds;
        evidence['greedy'] = await run(prompt, base);
        evidence['filtered'] = [
          for (final seed in seeds)
            await run(
              prompt,
              sampled.copyWith(seed: seed, minP: fixture['min_p'] as double),
            ),
        ];
        evidence['control'] = [
          for (final seed in seeds)
            await run(prompt, sampled.copyWith(seed: seed)),
        ];
      case 'G03.repeat_penalty' || 'G04.presence_penalty':
        final penalized = id == 'G03.repeat_penalty'
            ? base.copyWith(penalty: fixture['repeat_penalty'] as double)
            : base.copyWith(
                presencePenalty: fixture['presence_penalty'] as double,
              );
        evidence['baseline'] = await run(prompt, base);
        evidence['penalized'] = await run(prompt, penalized);
        evidence['repeat'] = await run(prompt, penalized);
      default:
        final budgeted = base.copyWith(
          maxTokens: fixture['budget_max_tokens'] as int,
        );
        evidence['free'] = await run(budgetPrompt, budgeted);
        final trials = <Map<String, dynamic>>[];
        evidence['trials'] = trials;
        for (final tokens in (fixture['budgets'] as List).cast<int>()) {
          trials.add({
            'budget': tokens,
            'prefix': tokens == 0
                ? ''
                : await run(budgetPrompt, budgeted.copyWith(maxTokens: tokens)),
            'output': await run(
              budgetPrompt,
              budgeted.copyWith(thinkingBudget: budget(tokens)),
            ),
          });
        }
        try {
          await sampler.generateSampled(
            budgetPrompt,
            budgeted.copyWith(
              thinkingBudget: budget(
                trials.last['budget'] as int,
                tagged: false,
              ),
            ),
          );
          evidence['untagged_rejection'] = 'accepted';
        } catch (error) {
          evidence['untagged_rejection'] = error.runtimeType.toString();
        }
        evidence['recovery'] = await run(
          budgetPrompt,
          budgeted.copyWith(
            thinkingBudget: budget(trials.last['budget'] as int),
          ),
        );
    }
    return {
      ...evidence,
      'status': _validSampler(id, evidence, diagnostics) ? 'PASS' : 'FAIL',
    };
  }

  bool _validSampler(
    String id,
    Map<String, dynamic> evidence,
    Map diagnostics,
  ) => validSamplerCaseEvidence(
    id,
    evidence,
    profile,
    web: engine.isWeb,
    diagnostics: diagnostics,
  );
}
