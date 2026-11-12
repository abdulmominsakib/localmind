import 'dart:async';
import 'dart:convert';

import 'package:genkit/genkit.dart' as genkit;
import 'package:genkit/plugin.dart' as api;
import 'package:genkit/src/o11y/instrumentation.dart' show resetInstrumentation;
import 'package:genkit/telemetry.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

import '../../../core/runtime/test_support/fake_runtime.dart';

void main() {
  test(
    'result schema rejects malformed typed/JSON values with a safe error',
    () async {
      final plugin = _plugin(_ScoringRuntime());
      addTearDown(plugin.dispose);
      final schema = plugin.scorer('local').outputSchema!;
      for (final value in [
        LlamaDartTokenScores.fromScores(
          LlamaNextTokenScores(
            candidates: [],
            top: [_token(1, double.nan)],
            promptTokens: 1,
          ),
        ),
        {
          'candidates': [],
          'top': [true],
          'promptTokens': 1,
        },
        {
          'candidates': [],
          'top': [],
          'promptTokens': 1,
          'extra': 'private output',
        },
        {
          'candidates': [],
          'top': [
            {
              'token': 1,
              'bytes': [65],
              'logprob': -1,
              'extra': 'private output',
            },
          ],
          'promptTokens': 1,
        },
        {
          'candidates': [],
          'top': [
            {
              'token': 1,
              'bytes': [65.5],
              'logprob': -1,
            },
          ],
          'promptTokens': 1,
        },
      ]) {
        expect(
          () => schema.parse(value),
          throwsA(
            isA<genkit.GenkitException>()
                .having((e) => e.status, 'status', genkit.StatusCode.dataLoss)
                .having(
                  (e) => e.toString(),
                  'safe error',
                  isNot(contains('private output')),
                ),
          ),
        );
      }
    },
  );
  test(
    'registered typed/raw calls preserve scoring settings and JSON bytes',
    () async {
      final runtime = _ScoringRuntime();
      final plugin = _plugin(runtime);
      final ai = genkit.Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(() async {
        await plugin.dispose();
        await ai.shutdown();
      });
      final scorer = plugin.scorer('local');
      expect((await plugin.init()).last, same(scorer));
      final listed = (await plugin.list()).last;
      expect(listed, same(scorer));
      expect(runtime.initializeCount, 0);
      expect(listed.metadata['llamadartScoring'], {
        'state': 'unloaded',
        'supported': false,
      });
      final registered = await ai.registry.lookupAction(
        LlamaDartPlugin.scoringActionType,
        scorer.name,
      );
      expect(registered, same(scorer));
      final ids = [7, 2, 7];
      final request = LlamaDartScoringRequest(
        prompt: '<special>raw prompt',
        candidates: ids,
        topK: 2,
        reusePromptPrefix: false,
      );
      ids.clear();
      final result = await scorer(request);
      expect(runtime.requests.single.toJson(), request.toJson());
      expect(runtime.chatTemplateCallCount, 0);
      expect(runtime.createCallCount, 0);
      expect(result.candidates.map((s) => s.token), [7, 2, 7]);
      expect(result.candidates.first.bytes, [0xe2]);
      expect(result.candidates.first.text, '\uFFFD');
      expect(result.candidates.first.probability, closeTo(0.1353352832, 1e-9));
      expect(() => result.candidates.clear(), throwsUnsupportedError);
      expect(
        () => result.candidates.first.bytes.clear(),
        throwsUnsupportedError,
      );
      expect(listed.metadata['llamadartScoring'], {
        'state': 'verified',
        'supported': true,
      });
      expect(
        scorer.outputSchema!
            .parse(jsonDecode(jsonEncode(result.toJson())))
            .toJson(),
        result.toJson(),
      );
      final raw = await registered!.runRaw({'prompt': 'raw', 'topK': 1});
      expect(raw.result, isA<LlamaDartTokenScores>());
      expect(runtime.requests.last.reusePromptPrefix, true);
    },
  );

  test(
    'typed and JSON invalid requests fail before loading or probing',
    () async {
      final runtime = _ScoringRuntime();
      final plugin = _plugin(runtime);
      addTearDown(plugin.dispose);
      final scorer = plugin.scorer('local');
      for (final request in [
        null,
        LlamaDartScoringRequest(prompt: '', topK: 1),
        LlamaDartScoringRequest(prompt: 'private prompt'),
        LlamaDartScoringRequest(prompt: 'private prompt', candidates: [-1]),
        LlamaDartScoringRequest(prompt: 'private prompt', topK: -1),
        LlamaDartScoringRequest(prompt: 'private prompt', topK: 2147483648),
      ]) {
        await expectLater(
          scorer(request),
          _status(genkit.StatusCode.invalidArgument),
        );
        if (request != null) {
          expect(
            () => scorer.inputSchema!.parse(request),
            _status(genkit.StatusCode.invalidArgument),
          );
        }
      }
      for (final json in [
        'not an object',
        {'prompt': 'raw', 'topK': 1.5},
        {'prompt': 'raw', 'topK': double.nan},
        {'prompt': 'raw', 'topK': null},
        {
          'prompt': 'raw',
          'candidates': [1.5],
        },
        {'prompt': 'raw', 'candidates': null},
        {'prompt': 'raw', 'topK': 1, 'reusePromptPrefix': 'true'},
        {'prompt': 'raw', 'topK': 1, 'temperature': 0},
      ]) {
        await expectLater(
          scorer.runRaw(json),
          _status(genkit.StatusCode.invalidArgument),
        );
      }
      expect(runtime.initializeCount, 0);
      expect(runtime.capabilityReadCount, 0);
      expect(runtime.requests, isEmpty);
      expect(() => plugin.scorer('other'), throwsStateError);
    },
  );

  test(
    'capability revocation, missing implementation and probes fail closed',
    () async {
      for (final runtime in [_ScoringRuntime(), FakeRuntime()]) {
        final plugin = _plugin(runtime);
        addTearDown(plugin.dispose);
        final scorer = plugin.scorer('local');
        runtime.capabilitySnapshot = _supported;
        if (runtime is _ScoringRuntime) {
          await scorer(_request);
          expect(runtime.requests, hasLength(1));
        } else {
          await expectLater(
            scorer(_request),
            _status(genkit.StatusCode.unimplemented),
          );
        }
        runtime.capabilitySnapshot = const LlamaEngineCapabilities(
          isSupported: true,
        );
        await expectLater(
          scorer(_request),
          _status(genkit.StatusCode.unimplemented),
        );
        runtime.capabilitySnapshot = const LlamaEngineCapabilities(
          isSupported: false,
          supportsNextTokenScoring: true,
        );
        await expectLater(
          scorer(_request),
          _status(genkit.StatusCode.failedPrecondition),
        );
        runtime.capabilityError = StateError('/private/secret-model');
        await expectLater(
          scorer(_request),
          throwsA(
            isA<LlamaStateException>().having(
              (e) => e.toString(),
              'sanitized',
              isNot(contains('secret-model')),
            ),
          ),
        );
        if (runtime is _ScoringRuntime) expect(runtime.requests, hasLength(1));
      }
      final plugin = LlamaDartPlugin(
        models: [_definition],
        runtimeFactory: _UnverifiedRuntime.new,
      );
      addTearDown(plugin.dispose);
      await expectLater(
        plugin.scorer('local')(_request),
        _status(genkit.StatusCode.failedPrecondition),
      );
    },
  );

  test(
    'vocabulary failures are sanitized and do not poison the queue',
    () async {
      final runtime = _ScoringRuntime()
        ..error = RangeError('private prompt or /secret/path');
      final plugin = _plugin(runtime);
      addTearDown(plugin.dispose);
      final scorer = plugin.scorer('local');
      await expectLater(
        scorer(_request),
        throwsA(
          isA<genkit.GenkitException>()
              .having(
                (e) => e.status,
                'status',
                genkit.StatusCode.invalidArgument,
              )
              .having(
                (e) => e.toString(),
                'safe error',
                isNot(contains('secret')),
              ),
        ),
      );
      runtime.error = LlamaUnsupportedException('secret backend details');
      await expectLater(
        scorer(_request),
        _status(genkit.StatusCode.unimplemented),
      );
      runtime.error = null;
      expect((await scorer(_request)).top, hasLength(1));
    },
  );

  test(
    'invalid runtime results cannot escape the typed or JSON action',
    () async {
      final runtime = _ScoringRuntime();
      final plugin = _plugin(runtime);
      addTearDown(plugin.dispose);
      for (final result in [
        LlamaNextTokenScores(candidates: [], top: [], promptTokens: 2),
        LlamaNextTokenScores(
          candidates: [],
          top: [_token(1, double.nan)],
          promptTokens: 2,
        ),
        LlamaNextTokenScores(
          candidates: [],
          top: [_token(1, 0.1)],
          promptTokens: 2,
        ),
        LlamaNextTokenScores(
          candidates: [],
          top: [_token(1, -1)],
          promptTokens: 0,
        ),
        LlamaNextTokenScores(
          candidates: [],
          top: [
            LlamaTokenLogprob(token: 1, bytes: [256], logprob: -1),
          ],
          promptTokens: 2,
        ),
      ]) {
        runtime.output = result;
        await expectLater(
          plugin.scorer('local')(_request),
          _status(genkit.StatusCode.dataLoss),
        );
      }
      runtime.output = LlamaNextTokenScores(
        candidates: [_token(3, -1)],
        top: [],
        promptTokens: 2,
      );
      await expectLater(
        plugin.scorer('local')(
          LlamaDartScoringRequest(prompt: 'raw', candidates: [2]),
        ),
        _status(genkit.StatusCode.dataLoss),
      );
      runtime.output = LlamaNextTokenScores(
        candidates: [],
        top: [_token(1, -2), _token(2, -1)],
        promptTokens: 2,
      );
      await expectLater(
        plugin.scorer('local')(LlamaDartScoringRequest(prompt: 'raw', topK: 2)),
        _status(genkit.StatusCode.dataLoss),
      );
    },
  );

  test(
    'scoring queues with chat, preserves request zones and drains before disposal',
    () async {
      resetInstrumentation();
      final instrumentation = _ScoringInstrumentation();
      configureInstrumentation(instrumentation);
      addTearDown(resetInstrumentation);
      final runtime = _ScoringRuntime()..blockChat = true;
      final plugin = _plugin(runtime);
      final ai = genkit.Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(ai.shutdown);
      final chat = ai.generate(
        model: llamaDart.model('local'),
        prompt: 'hello',
      );
      await runtime.chatStarted.future;
      final scorer = plugin.scorer('local');
      final scored = runZoned(
        () => scorer(_request),
        zoneValues: {#requestMarker: 'score'},
      );
      final inspected = plugin.inspectModel('local');
      final disposal = plugin.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(runtime.requests, isEmpty);
      expect(runtime.disposeCount, 0);
      runtime.chatRelease.complete();
      expect((await chat).text, 'ready');
      expect((await scored).top, hasLength(1));
      expect(runtime.zones, ['score']);
      expect(runtime.spanZones, ['llamadart/local']);
      expect(instrumentation.scoredInputs, [_request.toJson()]);
      expect(instrumentation.scoredOutputs.single['promptTokens'], 3);
      expect((await inspected).capabilities!.supportsNextTokenScoring, true);
      await disposal;
      expect(runtime.disposeCount, 1);
      await expectLater(scorer(_request), throwsStateError);
    },
  );

  test(
    'queued cancellation avoids backend work; active scoring drains safely',
    () async {
      final runtime = _ScoringRuntime()..blockChat = true;
      final plugin = _plugin(runtime);
      addTearDown(plugin.dispose);
      final chatAction = (await plugin.init())
          .whereType<api.Model<LlamaDartGenerationConfig>>()
          .single;
      final chat = chatAction(
        genkit.ModelRequest(
          messages: [
            genkit.Message(
              role: genkit.Role.user,
              content: [genkit.TextPart(text: 'hello')],
            ),
          ],
        ),
      );
      await runtime.chatStarted.future;
      final cancellation = genkit.CancellationController();
      final queued = plugin.scorer('local')(
        _request,
        cancel: cancellation.token,
      );
      final expectation = expectLater(
        queued,
        throwsA(isA<genkit.CancelledException>()),
      );
      cancellation.cancel();
      runtime.chatRelease.complete();
      await chat;
      await expectation;
      expect(runtime.requests, isEmpty);
      expect(runtime.cancelGenerationCount, 0);
      runtime.blockScore = true;
      final activeCancellation = genkit.CancellationController();
      final active = plugin.scorer('local')(
        _request,
        cancel: activeCancellation.token,
      );
      final activeExpectation = expectLater(
        active,
        throwsA(isA<genkit.CancelledException>()),
      );
      await runtime.scoreStarted.future;
      activeCancellation.cancel();
      final disposal = plugin.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(runtime.disposeCount, 0);
      runtime.scoreRelease.complete();
      await activeExpectation;
      await disposal;
      expect(runtime.disposeCount, 1);
      expect(runtime.cancelGenerationCount, 0);
    },
  );
}

const _definition = LlamaModelDefinition(
  name: 'local',
  modelPath: '/private/model.gguf',
  supportsEmbeddings: false,
);
const _supported = LlamaEngineCapabilities(
  isSupported: true,
  supportsNextTokenScoring: true,
);
final _request = LlamaDartScoringRequest(prompt: 'raw prompt', topK: 1);
LlamaDartPlugin _plugin(FakeRuntime runtime) =>
    LlamaDartPlugin(models: [_definition], runtimeFactory: () => runtime);
Matcher _status(genkit.StatusCode status) => throwsA(
  isA<genkit.GenkitException>().having((e) => e.status, 'status', status),
);
LlamaTokenLogprob _token(int token, double logprob) =>
    LlamaTokenLogprob(token: token, bytes: [0xe2], logprob: logprob);

class _ScoringRuntime extends FakeRuntime
    implements LlamaRuntimeScoringProvider {
  _ScoringRuntime() {
    capabilitySnapshot = _supported;
  }
  final requests = <LlamaDartScoringRequest>[];
  final zones = <Object?>[];
  final spanZones = <Object?>[];
  Object? error;
  LlamaNextTokenScores? output;
  bool blockChat = false;
  bool blockScore = false;
  final chatStarted = Completer<void>();
  final chatRelease = Completer<void>();
  final scoreStarted = Completer<void>();
  final scoreRelease = Completer<void>();
  @override
  Future<LlamaNextTokenScores> scoreNextToken(
    String prompt, {
    List<int> candidates = const [],
    int topK = 0,
    bool reusePromptPrefix = true,
  }) async {
    requests.add(
      LlamaDartScoringRequest(
        prompt: prompt,
        candidates: candidates,
        topK: topK,
        reusePromptPrefix: reusePromptPrefix,
      ),
    );
    zones.add(Zone.current[#requestMarker]);
    spanZones.add(Zone.current[#testSpan]);
    if (blockScore) {
      scoreStarted.complete();
      await scoreRelease.future;
    }
    if (error != null) throw error!;
    return output ??
        LlamaNextTokenScores(
          candidates: candidates.map((id) => _token(id, -2)).toList(),
          top: List.generate(topK, (i) => _token(i, -1 - i.toDouble())),
          promptTokens: 3,
        );
  }

  @override
  Stream<llama.LlamaCompletionChunk> create(
    List<llama.LlamaChatMessage> messages, {
    llama.GenerationParams? params,
    List<llama.ToolDefinition>? tools,
    llama.ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = false,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
  }) async* {
    createCallCount++;
    if (blockChat) {
      chatStarted.complete();
      await chatRelease.future;
    }
    yield textChunk('ready', finishReason: 'stop');
  }
}

class _ScoringInstrumentation implements Instrumentation {
  final scoredInputs = <Object?>[];
  final scoredOutputs = <Map<String, dynamic>>[];
  @override
  Future<O> runInNewSpan<O>(
    SpanMetadata metadata,
    Future<O> Function([SpanContext? span]) next,
  ) async {
    final result = await runZoned(
      () => next(),
      zoneValues: {#testSpan: metadata.name},
    );
    if (metadata.actionType == LlamaDartPlugin.scoringActionType.value) {
      scoredInputs.add((metadata.input as LlamaDartScoringRequest).toJson());
      scoredOutputs.add(jsonDecode(jsonEncode(result)) as Map<String, dynamic>);
    }
    return result;
  }
}

class _UnverifiedRuntime implements LlamaDartRuntime {
  @override
  Future<void> initialize(LlamaModelDefinition definition) async {}
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected runtime call.');
}
