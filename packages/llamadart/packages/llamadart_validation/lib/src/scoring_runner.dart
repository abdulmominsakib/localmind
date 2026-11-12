part of 'runner.dart';

extension _ScoringValidation on ValidationRunner {
  Future<Map<String, dynamic>> _scoringCase(String id) async {
    if (engine is! StateValidationEngine) {
      return {'status': 'NOT_RUN', 'reason': 'scoring_adapter_unavailable'};
    }
    final scorer = engine as StateValidationEngine;
    final diagnostics = await _checked(engine.diagnostics);
    final expected = expectedScoringCapability(
      profile,
      web: engine.isWeb,
      diagnostics: diagnostics,
    );
    final evidence = <String, dynamic>{
      'supported': scorer.supportsNextTokenScoring,
      'diagnostics': diagnostics,
      'web': engine.isWeb,
    };
    _partialCaseEvidence = evidence;
    if (expected == null) {
      return {
        ...evidence,
        'status': 'NOT_RUN',
        'reason': 'scoring_profile_or_host_unqualified',
      };
    }
    Future<String> rejection(Future<Object?> Function() call) async {
      try {
        await call();
        return 'accepted';
      } catch (error) {
        return error.runtimeType.toString();
      }
    }

    if (id == 'N01.capability') {
      if (!expected) {
        evidence['rejection'] = await rejection(
          () => scorer.scoreStatePrompt('probe', topK: 1, reuse: false),
        );
        evidence['recovery'] = await _checked(
          () => engine.generate(_shortPrompt, profile, raw: !profile.isChat),
        );
      }
      return {
        ...evidence,
        'status': _validScoring(id, evidence, diagnostics) ? 'PASS' : 'FAIL',
      };
    }
    if (!expected || !scorer.supportsNextTokenScoring) {
      return {
        ...evidence,
        'status': 'FAIL',
        'reason': 'required_scoring_capability_missing',
      };
    }
    final fixture = profile.fixtures['next_token_scoring'] as Map;
    final topK = fixture['top_k'] as int;
    final prompts = (fixture['prompts'] as List).cast<String>();
    evidence['model_sha256'] = profile.model['sha256'];
    evidence['config_hash'] = jsonHash(profile.effectiveConfig);
    Future<Map<String, dynamic>> score(
      String text, {
      List<int> candidates = const [],
      int top = 0,
      bool reuse = false,
    }) => _checked(
      () => scorer.scoreStatePrompt(
        text,
        candidates: candidates,
        topK: top,
        reuse: reuse,
      ),
    );
    List<int> topIds(Map<String, dynamic> result) => [
      for (final row in result['top'] as List) (row as Map)['token'] as int,
    ];
    _operationPhase = 'scoring.$id';
    switch (id) {
      case 'N02.top_k':
        final trials = <Map<String, dynamic>>[];
        evidence['trials'] = trials;
        for (final prompt in prompts) {
          trials.add({
            'prompt': prompt,
            'tokens': await _checked(() => scorer.tokenizeStatePrompt(prompt)),
            'first': await score(prompt, top: topK),
            'repeat': await score(prompt, top: topK),
          });
        }
      case 'N03.candidates':
        final prompt = prompts.first;
        evidence['prompt'] = prompt;
        evidence['tokens'] = await _checked(
          () => scorer.tokenizeStatePrompt(prompt),
        );
        final baseline = await score(prompt, top: topK);
        final top = topIds(baseline);
        final ids = [
          for (final rank in (fixture['candidate_ranks'] as List).cast<int>())
            top[rank],
          scoringOutsider(top),
        ];
        evidence['baseline'] = baseline;
        evidence['candidate_ids'] = ids;
        evidence['candidates_only'] = await score(prompt, candidates: ids);
        evidence['combined'] = await score(prompt, candidates: ids, top: topK);
      case 'N04.reuse':
        final prefix = fixture['prefix'] as String;
        final full = '$prefix${fixture['suffix']}';
        evidence['prefix'] = prefix;
        evidence['full'] = full;
        evidence['prefix_tokens'] = await _checked(
          () => scorer.tokenizeStatePrompt(prefix),
        );
        evidence['full_tokens'] = await _checked(
          () => scorer.tokenizeStatePrompt(full),
        );
        final fresh = await score(full, top: topK);
        evidence['fresh'] = fresh;
        evidence['prime'] = await score(prefix, top: topK, reuse: true);
        evidence['reused'] = await score(
          full,
          candidates: topIds(fresh),
          reuse: true,
        );
      default:
        final prompt = prompts.first;
        evidence['prompt'] = prompt;
        evidence['tokens'] = await _checked(
          () => scorer.tokenizeStatePrompt(prompt),
        );
        evidence['baseline'] = await score(prompt, top: topK);
        evidence['rejections'] = {
          'empty_prompt': await rejection(() => score('', top: topK)),
          'negative_candidate': await rejection(
            () => score(prompt, candidates: const [-1]),
          ),
          'negative_top_k': await rejection(() => score(prompt, top: -1)),
          'no_selection': await rejection(() => score(prompt)),
        };
        evidence['recovery'] = await score(prompt, top: topK);
    }
    return {
      ...evidence,
      'status': _validScoring(id, evidence, diagnostics) ? 'PASS' : 'FAIL',
    };
  }

  bool _validScoring(
    String id,
    Map<String, dynamic> evidence,
    Map diagnostics,
  ) => validScoringCaseEvidence(
    id,
    evidence,
    profile,
    web: engine.isWeb,
    diagnostics: diagnostics,
  );
}
