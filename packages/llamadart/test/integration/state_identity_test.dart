@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../support/dart_script_snapshot.dart';
import '../test_helper.dart';

const _prompt =
    'Once upon a time there was a little girl named Lily. She lived in a red '
    'house beside a forest and opened';
const _suffix = ' the wooden box';
const _maxLogprobDelta = 0.01;

/// A state saved by another process loads after its identity matches, and the
/// restored prefix scores the next token like a fresh evaluation within
/// numerical tolerance (#1003: batch shape differs, so not bit-exact).
void main() {
  late File modelFile;
  late String child;
  late Directory tmpDir;

  setUpAll(() async {
    modelFile = await TestHelper.getTestModel();
    child = await compileDartScriptWithBundledNativeAssets(
      'test/support/state_identity_child.dart',
    );
    tmpDir = Directory.systemTemp.createTempSync('llamadart_state_identity_');
  });

  tearDownAll(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  for (final (name, gpuLayers) in [
    ('default device', ModelParams.maxGpuLayers),
    ('CPU', 0),
  ]) {
    test(
      'another process loads a state whose identity matches ($name)',
      () async {
        final params = ModelParams(contextSize: 256, gpuLayers: gpuLayers);
        final statePath = '${tmpDir.path}/state-$gpuLayers.bin';
        final result = await Process.run(Platform.resolvedExecutable, [
          child,
          modelFile.path,
          '$gpuLayers',
          statePath,
          _prompt,
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        final saved =
            jsonDecode(
                  const LineSplitter()
                      .convert(result.stdout as String)
                      .lastWhere((line) => line.startsWith('{')),
                )
                as Map<String, Object?>;
        final savedIdentity = LlamaStateIdentity(
          runtimeBuild: saved['runtimeBuild']! as String,
          sessionFormatVersion: saved['sessionFormatVersion']! as int,
          contextSize: saved['contextSize']! as int,
          contextConfigDigest: saved['contextConfigDigest']! as String,
        );

        final engine = LlamaEngine(LlamaBackend());
        addTearDown(engine.dispose);
        await engine.loadModel(modelFile.path, modelParams: params);

        expect(savedIdentity.matches(await engine.stateIdentity()), isTrue);
        final loaded = await engine.stateLoadFile(
          statePath,
          tokenCapacity: 256,
        );
        expect(loaded.tokens, saved['tokens']);

        final resumed = await engine.scoreNextToken(
          _prompt + _suffix,
          topK: 8,
          reusePromptPrefix: true,
        );
        final resumedEval = (await engine.getPerformanceContext())!;
        final fresh = await engine.scoreNextToken(
          _prompt + _suffix,
          candidates: [for (final token in resumed.top) token.token],
          topK: 1,
          reusePromptPrefix: false,
        );
        final freshEval = (await engine.getPerformanceContext())!;
        expect(
          resumedEval.promptEvalTokens,
          lessThan(freshEval.promptEvalTokens),
          reason: 'the resumed score must reuse the restored prefix',
        );
        expect(resumed.top.first.token, fresh.top.first.token);
        for (var i = 0; i < resumed.top.length; i++) {
          expect(
            resumed.top[i].logprob,
            closeTo(fresh.candidates[i].logprob, _maxLogprobDelta),
            reason: 'token ${resumed.top[i].token}',
          );
        }
      },
    );
  }
  // Audit repro: a different RoPE base gave a matching identity, loaded, and
  // resumed scores diverged from a fresh evaluation by about 2.6 nats.
  test('a different RoPE frequency base changes the identity', () async {
    Future<LlamaStateIdentity> identityWith(ModelParams params) async {
      final engine = LlamaEngine(LlamaBackend());
      try {
        await engine.loadModel(modelFile.path, modelParams: params);
        return await engine.stateIdentity();
      } finally {
        await engine.dispose();
      }
    }

    const params = ModelParams(contextSize: 256, gpuLayers: 0);
    final base = await identityWith(params);
    final rope = await identityWith(params.copyWith(ropeFrequencyBase: 1000));
    expect(rope.runtimeBuild, base.runtimeBuild);
    expect(rope.matches(base), isFalse);
  });
}
