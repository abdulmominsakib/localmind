@TestOn('vm')
@Tags(<String>['local-only', 'e2e'])
@Timeout(Duration(minutes: 15))
library;

import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../support/suite_system_temp.dart';

const _modelKey = 'LITERT_LM_MODEL';
const _backendKey = 'LITERT_LM_BACKEND';

/// Qualifies native LiteRT-LM penalties and thinking budgets on a real
/// bundle. Set `LITERT_LM_MODEL` to a bundle whose first response channel is
/// its thinking channel, such as Gemma 4 E2B, and optionally
/// `LITERT_LM_BACKEND` to `cpu` (default) or `gpu`.
void main() {
  final suiteTemp = useSuiteSystemTemp();
  final model = Platform.environment[_modelKey];
  final backend = Platform.environment[_backendKey] == 'gpu'
      ? LiteRtLmBackendPreference.gpu
      : LiteRtLmBackendPreference.cpu;
  late LlamaEngine engine;

  setUpAll(() async {
    if (model == null || !File(model).existsSync()) return;
    engine = LlamaEngine(LlamaBackend());
    await engine.loadModel(
      model,
      modelParams: ModelParams(
        contextSize: 4096,
        liteRtLmBackend: backend,
        liteRtLmCacheDir: suiteTemp().createTempSync('cache_').path,
      ),
    );
  });

  tearDownAll(() async {
    if (model == null || !File(model).existsSync()) return;
    await engine.dispose();
  });

  Future<({String content, String thinking})> chat(
    String prompt, {
    GenerationParams params = const GenerationParams(),
    bool enableThinking = false,
    int maxTokens = 96,
  }) async {
    final content = StringBuffer();
    final thinking = StringBuffer();
    await for (final chunk in engine.create(
      [LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt)],
      enableThinking: enableThinking,
      params: params.copyWith(maxTokens: maxTokens, temp: 0.0, seed: 1),
    )) {
      final delta = chunk.choices.first.delta;
      content.write(delta.content ?? '');
      thinking.write(delta.thinking ?? '');
    }
    return (content: content.toString(), thinking: thinking.toString());
  }

  int count(String text, String word) =>
      RegExp('\\b$word\\b', caseSensitive: false).allMatches(text).length;

  const repeatPrompt =
      'Write the word apple 40 times, separated by single spaces. '
      'Output nothing else.';
  const thinkingPrompt =
      'A train leaves at 9:40 and arrives at 13:05. How long is the trip? '
      'Think it through carefully before answering.';

  final skip = model != null && File(model).existsSync()
      ? false
      : 'Set $_modelKey to a .litertlm bundle with a thinking channel.';

  test('reports native penalties and thinking budgets', () async {
    final capabilities = await engine.capabilities;

    expect(engine.runtime, LlamaRuntime.liteRtLm);
    expect(capabilities.supportsPenalty, isTrue);
    expect(capabilities.supportsPresencePenalty, isTrue);
    expect(capabilities.supportsThinkingBudget, isTrue);
    expect(capabilities.supportsMinP, isFalse);
  }, skip: skip);

  test('penalties reach the sampler and leave later sends alone', () async {
    final baseline = await chat(repeatPrompt);
    final penalized = await chat(
      repeatPrompt,
      params: const GenerationParams(penalty: 2.0, presencePenalty: 2.0),
    );
    final after = await chat(repeatPrompt);

    expect(count(baseline.content, 'apple'), greaterThanOrEqualTo(20));
    expect(
      count(penalized.content, 'apple'),
      lessThan(count(baseline.content, 'apple') ~/ 2),
      reason: 'penalized: ${penalized.content}',
    );
    expect(after.content, baseline.content);
  }, skip: skip);

  test('penalties count only tokens the send generates', () async {
    const prompt =
        'banana banana banana banana banana banana banana banana. '
        'Which fruit did I name? Answer with that one word only.';
    final penalized = await chat(
      prompt,
      params: const GenerationParams(penalty: 2.0, presencePenalty: 2.0),
      maxTokens: 8,
    );

    expect(count(penalized.content, 'banana'), 1, reason: penalized.content);
  }, skip: skip);

  test('a thinking budget bounds the thinking channel', () async {
    const budget = 12;
    final unbounded = await chat(
      thinkingPrompt,
      enableThinking: true,
      maxTokens: 768,
    );
    final bounded = await chat(
      thinkingPrompt,
      enableThinking: true,
      maxTokens: 768,
      params: const GenerationParams(
        thinkingBudget: ThinkingBudget(maxTokens: budget),
      ),
    );
    final unboundedTokens = await engine.tokenize(
      unbounded.thinking,
      addSpecial: false,
    );
    final boundedTokens = await engine.tokenize(
      bounded.thinking,
      addSpecial: false,
    );

    expect(unboundedTokens.length, greaterThan(budget * 2));
    expect(boundedTokens.length, lessThanOrEqualTo(budget + 2));
    expect(bounded.content.trim(), isNotEmpty);
  }, skip: skip);

  test('a cancelled bounded send leaves the next send unbounded', () async {
    final unbounded = await chat(
      thinkingPrompt,
      enableThinking: true,
      maxTokens: 768,
    );
    final stream = engine.create(
      const [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: thinkingPrompt,
        ),
      ],
      enableThinking: true,
      params: const GenerationParams(
        maxTokens: 768,
        temp: 0.0,
        seed: 1,
        penalty: 1.5,
        thinkingBudget: ThinkingBudget(maxTokens: 4),
      ),
    );
    await stream.first;
    final again = await chat(
      thinkingPrompt,
      enableThinking: true,
      maxTokens: 768,
    );

    expect(again.thinking, unbounded.thinking);
    expect(again.content, unbounded.content);
  }, skip: skip);
}
