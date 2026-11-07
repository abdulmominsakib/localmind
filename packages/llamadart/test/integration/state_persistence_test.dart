@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'package:test/test.dart';
import 'package:llamadart/llamadart.dart';
import '../test_helper.dart';

/// Round-trip integration test for `llama_state_save_file` and
/// `llama_state_load_file` exposed via [LlamaEngine].
///
/// Saves the KV-cache state of a tiny model after seeding it with a
/// known prompt, then verifies that [stateLoadFile] returns the same
/// token sequence and that the destination context can resume
/// generation without re-evaluating the prompt.
void main() async {
  late File modelFile;
  late LlamaEngine engine;
  late LlamaBackend backend;
  late Directory tmpDir;

  setUpAll(() async {
    modelFile = await TestHelper.getTestModel();
    backend = LlamaBackend();
    engine = LlamaEngine(backend);
    await engine.loadModel(
      modelFile.path,
      modelParams: const ModelParams(contextSize: 256),
    );
    tmpDir = Directory.systemTemp.createTempSync('llamadart_state_test_');
  });

  tearDownAll(() async {
    await engine.dispose();
    if (tmpDir.existsSync()) {
      tmpDir.deleteSync(recursive: true);
    }
  });

  test('reports state persistence support on the native backend', () {
    expect(engine.supportsStatePersistence, isTrue);
  });

  test('saves and loads KV state, recovering the original tokens', () async {
    // Tokenization alone does not populate the KV cache; seed it by running
    // a short generate so the persisted file actually contains real state.
    const prompt = 'Once upon a time in a quiet land';
    final tokens = await engine.tokenize(prompt);
    expect(tokens, isNotEmpty);

    await engine
        .generate(
          prompt,
          params: const GenerationParams(maxTokens: 2, reusePromptPrefix: true),
        )
        .drain<void>();

    final savePath = '${tmpDir.path}/state.bin';
    final saved = await engine.stateSaveFile(savePath, tokens: tokens);
    expect(saved, isTrue, reason: 'stateSaveFile should succeed');
    expect(File(savePath).existsSync(), isTrue);
    // A file holding real KV state for a non-empty prompt is far larger than
    // the bare token list; reject the trivial token-roundtrip case.
    expect(
      File(savePath).lengthSync(),
      greaterThan(tokens.length * 8),
      reason: 'saved state must contain KV data, not just the token header',
    );

    final result = await engine.stateLoadFile(savePath, tokenCapacity: 256);
    expect(result.tokens, equals(tokens));
  });

  test('rejects non-existent state files', () async {
    final missingPath = '${tmpDir.path}/does-not-exist.bin';
    expect(
      () => engine.stateLoadFile(missingPath, tokenCapacity: 256),
      throwsA(isA<Exception>()),
    );
  });

  test('rejects token capacity larger than context size', () async {
    final unusedPath = '${tmpDir.path}/oversized-capacity.bin';
    expect(
      () => engine.stateLoadFile(unusedPath, tokenCapacity: 257),
      throwsA(isA<Exception>()),
    );
  });

  test('round-trips an empty token sequence', () async {
    final savePath = '${tmpDir.path}/empty.bin';
    final saved = await engine.stateSaveFile(savePath, tokens: const []);
    expect(saved, isTrue);
    final loaded = await engine.stateLoadFile(savePath, tokenCapacity: 64);
    expect(loaded.tokens, isEmpty);
  });

  test(
    'fresh engine resumes from saved state without re-evaluating the prompt',
    () async {
      const prompt = 'Once upon a time in a land far away';

      // --- Engine A: seed the KV cache and persist it to disk. ---
      final engineA = LlamaEngine(LlamaBackend());
      var engineADisposed = false;
      LlamaEngine? engineB;
      try {
        await engineA.loadModel(
          modelFile.path,
          modelParams: const ModelParams(contextSize: 256),
        );

        final tokens = await engineA.tokenize(prompt);
        await engineA
            .generate(
              prompt,
              params: const GenerationParams(
                maxTokens: 3,
                reusePromptPrefix: true,
              ),
            )
            .drain<void>();
        final perfA = await engineA.getPerformanceContext();
        final fullEvalTokens = perfA?.promptEvalTokens ?? 0;
        expect(
          fullEvalTokens,
          greaterThan(1),
          reason: 'engine A must evaluate the prompt',
        );

        final savePath = '${tmpDir.path}/kv_reuse_fresh.bin';
        expect(await engineA.stateSaveFile(savePath, tokens: tokens), isTrue);

        // Drop engine A so the next decode genuinely starts cold — no
        // warmed KV cache in memory to mask a regression in stateLoadFile.
        await engineA.dispose();
        engineADisposed = true;

        // --- Engine B: cold start, load the persisted state, resume. ---
        engineB = LlamaEngine(LlamaBackend());
        await engineB.loadModel(
          modelFile.path,
          modelParams: const ModelParams(contextSize: 256),
        );

        final loadResult = await engineB.stateLoadFile(
          savePath,
          tokenCapacity: 256,
        );
        expect(
          loadResult.tokens,
          equals(tokens),
          reason: 'loaded tokens must round-trip on a fresh engine',
        );

        // Generate with prompt + a short suffix on the fresh engine. If
        // cachedPromptTokens was seeded by stateLoadFile, only the suffix
        // is decoded; otherwise the full prompt re-evaluates. We use the
        // native n_p_eval counter (returned when > 0) which reflects the
        // actual decode count for this call; the Dart fallback returns
        // the full prompt length so we need at least one suffix token to
        // get a native reading.
        const suffix = ' and they';
        await engineB
            .generate(
              prompt + suffix,
              params: const GenerationParams(
                maxTokens: 3,
                reusePromptPrefix: true,
              ),
            )
            .drain<void>();
        final perfB = await engineB.getPerformanceContext();
        final cachedEvalTokens = perfB?.promptEvalTokens ?? fullEvalTokens;

        expect(
          cachedEvalTokens,
          lessThan(fullEvalTokens),
          reason:
              'fresh-engine generate after stateLoadFile must reuse the '
              'KV prefix; only suffix tokens should be evaluated, not the '
              'full prompt',
        );
      } finally {
        // Dispose explicitly; do not use addTearDown to avoid a
        // double-dispose hang on the (already-disposed) engineA.
        if (engineB != null) {
          await engineB.dispose();
        }
        if (!engineADisposed) {
          await engineA.dispose();
        }
      }
    },
  );

  test(
    'exact-prompt resume samples without re-decoding the cached prefix',
    () async {
      const prompt = 'Once upon a time in a small village';

      final engineA = LlamaEngine(LlamaBackend());
      var engineADisposed = false;
      LlamaEngine? engineB;
      try {
        await engineA.loadModel(
          modelFile.path,
          modelParams: const ModelParams(contextSize: 256),
        );

        final tokens = await engineA.tokenize(prompt);
        await engineA
            .generate(
              prompt,
              params: const GenerationParams(
                maxTokens: 2,
                reusePromptPrefix: true,
              ),
            )
            .drain<void>();

        final savePath = '${tmpDir.path}/exact_match.bin';
        expect(await engineA.stateSaveFile(savePath, tokens: tokens), isTrue);
        await engineA.dispose();
        engineADisposed = true;

        engineB = LlamaEngine(LlamaBackend());
        await engineB.loadModel(
          modelFile.path,
          modelParams: const ModelParams(contextSize: 256),
        );

        await engineB.stateLoadFile(savePath, tokenCapacity: 256);

        // Re-issue the EXACT same prompt — reusedPrefix == nTokens. The
        // exact-match branch must NOT clear the restored KV cache; only the
        // final token is re-decoded so the sampler has fresh logits. We
        // assert this by checking that the native prompt-eval token count
        // is below the full prompt length (it should be 1, but allow slack
        // for the Dart fallback path).
        await engineB
            .generate(
              prompt,
              params: const GenerationParams(
                maxTokens: 2,
                reusePromptPrefix: true,
              ),
            )
            .drain<void>();
        final perf = await engineB.getPerformanceContext();
        final evalTokens = perf?.promptEvalTokens ?? tokens.length;
        expect(
          evalTokens,
          lessThan(tokens.length),
          reason:
              'exact-match resume must re-decode at most one trailing token, '
              'not the full restored prefix',
        );
      } finally {
        if (engineB != null) {
          await engineB.dispose();
        }
        if (!engineADisposed) {
          await engineA.dispose();
        }
      }
    },
  );
}
