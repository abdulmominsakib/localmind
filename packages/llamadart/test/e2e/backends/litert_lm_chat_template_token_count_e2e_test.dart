@TestOn('vm')
@Tags(<String>['local-only', 'e2e'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../support/suite_system_temp.dart';

/// Checks `chatTemplate().tokenCount` against the input the native runtime
/// prefills, on an existing `.litertlm` bundle such as Gemma 4, Qwen3.5 or
/// Qwen3; never downloads weights.
void main() {
  final systemTemp = useSuiteSystemTemp();
  final modelPath = Platform.environment['LITERT_LM_MODEL'];
  final skip = modelPath == null || !File(modelPath).existsSync()
      ? 'Set LITERT_LM_MODEL to an existing .litertlm model.'
      : false;

  late LlamaEngine engine;

  setUpAll(() async {
    if (skip != false) return;
    engine = LlamaEngine(LlamaBackend());
    await engine.loadModel(
      modelPath!,
      modelParams: ModelParams(
        contextSize: 1024,
        liteRtLmBackend: LiteRtLmBackendPreference.cpu,
        liteRtLmCacheDir: '${systemTemp().path}/cache',
        numberOfThreads: 2,
      ),
    );
  });

  tearDownAll(() async {
    if (skip != false) return;
    await engine.dispose();
  });

  const requests = {
    'user': [LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi')],
    'system and user': [
      LlamaChatMessage.fromText(
        role: LlamaChatRole.system,
        text: 'You are helpful.',
      ),
      LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
    ],
  };

  for (final MapEntry(key: name, value: messages) in requests.entries) {
    for (final thinking in [true, false]) {
      test('counts the $name prompt the runtime prefills, '
          'thinking ${thinking ? 'on' : 'off'}', () async {
        final shown = await engine.chatTemplate(
          messages,
          enableThinking: thinking,
        );
        await engine
            .create(
              messages,
              enableThinking: thinking,
              params: const GenerationParams(maxTokens: 1, temp: 0, seed: 1),
            )
            .drain<void>();
        final prefilled =
            (await engine.getPerformanceContext())?.promptEvalTokens;

        expect(prefilled, isNotNull);
        expect(shown.tokenCount, prefilled, reason: shown.prompt);
      }, skip: skip);
    }
  }
}
