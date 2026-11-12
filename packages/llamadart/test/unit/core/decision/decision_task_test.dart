import 'dart:async';
import 'dart:typed_data';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  late _Backend backend;
  late LlamaEngine encoder;
  late DecisionEngine decisions;
  final questions = {'yes': DecisionQuestion.noul('Is this true?')};

  setUp(() async {
    backend = _Backend();
    encoder = LlamaEngine(backend);
    await encoder.loadModel('encoder.gguf');
    decisions = await DecisionEngine.attach(
      encoder,
      head: ModelSource.path('head.safetensors'),
    );
  });
  tearDown(() async {
    await decisions.dispose();
    await encoder.dispose();
  });

  DecisionTask<DecisionResult> start() =>
      decisions.systemOneTask(state: 'state', questions: questions);

  test(
    'done completes without observing events and late events contain one result',
    () async {
      final task = start();
      expect(task.done, same(task.done));
      final completion = await task.done;
      expect(completion.state, DecisionCompletionState.completed);
      expect(completion.error, isNull);
      expect(completion.stackTrace, isNull);
      expect(completion.result!.nouls.keys, ['yes']);
      expect(await task.result, same(completion.result));
      expect(await task.events.toList(), [same(completion.result)]);
      task.cancel();
      expect(task.isCancellationRequested, isFalse);
    },
  );

  test('immediate cancellation dispatches and tokenizes nothing', () async {
    final task = start()
      ..cancel()
      ..cancel();
    expect((await task.done).state, DecisionCompletionState.cancelled);
    expect(task.isCancellationRequested, isTrue);
    expect(backend.tokenized, isEmpty);
    expect(backend.runs, isEmpty);
    expect(await task.events.toList(), isEmpty);
    await expectLater(task.result, throwsA(isA<LlamaStateException>()));
  });

  test(
    'cancellation after tokenization waits and stops before the next piece',
    () async {
      final gate = Completer<void>();
      backend.tokenizeGate = gate;
      final task = start();
      await backend.tokenizeStarted.future;
      var finished = false;
      unawaited(task.done.then((_) => finished = true));
      task.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      gate.complete();
      expect((await task.done).state, DecisionCompletionState.cancelled);
      expect(backend.tokenized, ['state']);
      expect(backend.runs, isEmpty);
    },
  );

  test('cancellation at the last tokenization prevents dispatch', () async {
    late DecisionTask<DecisionResult> task;
    backend.onTokenize = (text) {
      if (text.startsWith(' true:')) task.cancel();
    };
    task = start();
    expect((await task.done).state, DecisionCompletionState.cancelled);
    expect(backend.tokenized, hasLength(4));
    expect(backend.runs, isEmpty);
  });

  test(
    'cancelled dispatched task retains head until backend finishes',
    () async {
      final gate = Completer<void>();
      backend.runGates.add(gate);
      final task = start();
      await backend.runStarted.future;
      task.cancel();
      var finished = false;
      unawaited(task.done.then((_) => finished = true));
      final disposal = decisions.dispose();
      expect(decisions.dispose(), same(disposal));
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      expect(backend.freed, isEmpty);
      expect(backend.globalCancels, 0);
      gate.complete();
      expect((await task.done).state, DecisionCompletionState.cancelled);
      expect(await task.events.toList(), isEmpty);
      await disposal;
      expect(backend.freed, [7]);
      expect(encoder.isReady, isTrue);
    },
  );

  test(
    'cancelling observation does not cancel operation or borrowed text',
    () async {
      final gate = Completer<void>();
      backend.runGates.add(gate);
      final task = start();
      final subscription = task.events.listen((_) => fail('observer detached'));
      await subscription.cancel();
      await backend.runStarted.future;
      expect(await encoder.generate('hi').join(), 'text');
      gate.complete();
      expect((await task.done).state, DecisionCompletionState.completed);
      expect(task.isCancellationRequested, isFalse);
      expect(backend.globalCancels, 0);
    },
  );

  test('paused observation does not block done', () async {
    final task = start();
    final subscription = task.events.listen((_) {})..pause();
    expect((await task.done).state, DecisionCompletionState.completed);
    await subscription.cancel();
  });

  test(
    'one cancellation preserves a sibling task and a legacy Future',
    () async {
      final firstGate = Completer<void>();
      final secondGate = Completer<void>();
      final thirdGate = Completer<void>();
      backend.runGates.addAll([firstGate, secondGate, thirdGate]);
      final first = start();
      await backend.runStarted.future;
      final second = start();
      await _until(() => backend.runs.length == 2);
      final legacy = decisions.systemOne(state: 'legacy', questions: questions);
      await _until(() => backend.runs.length == 3);
      first.cancel();
      firstGate.complete();
      secondGate.complete();
      thirdGate.complete();
      expect((await first.done).state, DecisionCompletionState.cancelled);
      expect((await second.done).state, DecisionCompletionState.completed);
      expect((await legacy).answers.keys, ['yes']);
      expect(backend.globalCancels, 0);
    },
  );

  test(
    'backend error wins over cancellation and result throws lazily with stack',
    () async {
      final gate = Completer<void>();
      backend.runGates.add(gate);
      final error = LlamaDecisionException('backend failed');
      backend.runError = error;
      final task = start();
      await backend.runStarted.future;
      task.cancel();
      gate.complete();
      final completion = await task.done;
      expect(completion.state, DecisionCompletionState.failed);
      expect(completion.error, same(error));
      expect(completion.stackTrace, isNotNull);
      expect(completion.result, isNull);
      expect(await task.events.toList(), isEmpty);
      await expectLater(task.result, throwsA(same(error)));
    },
  );

  test(
    'unknown tokenization error becomes typed failure without an event error',
    () async {
      backend.tokenizeError = StateError('tokenizer failed');
      final task = start();
      final completion = await task.done;
      expect(completion.state, DecisionCompletionState.failed);
      expect(completion.error, isA<LlamaDecisionException>());
      expect(await task.events.toList(), isEmpty);
      expect(backend.runs, isEmpty);
    },
  );

  test('single snapshots JSON and questions before caller mutation', () async {
    final state = {
      'value': ['original'],
    };
    final mutableQuestions = Map<String, DecisionQuestion>.of(questions);
    final task = decisions.systemOneTask(
      state: state,
      questions: mutableQuestions,
    );
    state['value']!.add('changed');
    mutableQuestions.clear();
    final result = await task.result;
    expect(result.answers.keys, ['yes']);
    expect(backend.tokenized.first, '{"value": ["original"]}');
  });

  test('batch snapshots request order and emits one final batch', () async {
    final requests = [
      DecisionRequest(state: 'first', questions: {'a': questions['yes']!}),
      DecisionRequest(state: 'second', questions: {'b': questions['yes']!}),
    ];
    final task = decisions.systemOneBatchTask(requests);
    requests.clear();
    final completion = await task.done;
    expect(completion.state, DecisionCompletionState.completed);
    expect(completion.result!.map((r) => r.answers.keys.single), ['a', 'b']);
    expect(backend.runs.single, hasLength(2));
    expect(await task.events.toList(), [same(completion.result)]);
  });

  test(
    'empty batch completes without dispatch and can be cancelled immediately',
    () async {
      expect(await decisions.systemOneBatchTask([]).result, isEmpty);
      final cancelled = decisions.systemOneBatchTask([])..cancel();
      expect((await cancelled.done).state, DecisionCompletionState.cancelled);
      expect(backend.runs, isEmpty);
      expect(backend.tokenized, isEmpty);
    },
  );

  test(
    'invalid request is a failed task and legacy validation still throws',
    () async {
      final task = decisions.systemOneTask(state: 'state', questions: {});
      expect((await task.done).error, isA<LlamaDecisionException>());
      await expectLater(
        decisions.systemOne(state: 'state', questions: {}),
        throwsA(isA<LlamaDecisionException>()),
      );
    },
  );

  test(
    'dispose cancels preflight without freeing the active head early',
    () async {
      final gate = Completer<void>();
      backend.tokenizeGate = gate;
      final task = start();
      await backend.tokenizeStarted.future;
      final disposal = decisions.dispose();
      expect(task.isCancellationRequested, isTrue);
      expect(backend.freed, isEmpty);
      gate.complete();
      expect((await task.done).state, DecisionCompletionState.cancelled);
      await disposal;
      expect(backend.runs, isEmpty);
    },
  );

  test(
    'model replacement cancels a dispatched task but keeps legacy result',
    () async {
      final firstGate = Completer<void>();
      final secondGate = Completer<void>();
      backend.runGates.addAll([firstGate, secondGate]);
      final task = start();
      await backend.runStarted.future;
      final legacy = decisions.systemOne(state: 'legacy', questions: questions);
      await _until(() => backend.runs.length == 2);
      await encoder.unloadModel();
      await encoder.loadModel('replacement.gguf');
      firstGate.complete();
      secondGate.complete();
      expect((await task.done).state, DecisionCompletionState.cancelled);
      expect(task.isCancellationRequested, isTrue);
      expect((await legacy).answers.keys, ['yes']);
    },
  );

  test('terminal observer can reenter cancellation and disposal', () async {
    final task = start();
    Future<void>? disposal;
    final observed = task.events.listen((_) {
      task.cancel();
      disposal = decisions.dispose();
    }).asFuture<void>();
    expect((await task.done).state, DecisionCompletionState.completed);
    await observed;
    await disposal;
    expect(task.isCancellationRequested, isFalse);
    expect(backend.freed, [7]);
  });

  test(
    'tokenization error still fails after cancellation was requested',
    () async {
      final gate = Completer<void>();
      backend.tokenizeGate = gate;
      final error = LlamaInferenceException('tokenizer failed');
      backend.tokenizeError = error;
      final task = start();
      await backend.tokenizeStarted.future;
      task.cancel();
      gate.complete();
      final completion = await task.done;
      expect(completion.state, DecisionCompletionState.failed);
      expect(completion.error, same(error));
      expect(backend.runs, isEmpty);
    },
  );

  test(
    'malformed backend outputs remain failures after cancellation',
    () async {
      final gate = Completer<void>();
      backend.runGates.add(gate);
      backend.dropOutputs = true;
      final task = start();
      await backend.runStarted.future;
      task.cancel();
      gate.complete();
      final completion = await task.done;
      expect(completion.state, DecisionCompletionState.failed);
      expect(completion.error, isA<LlamaDecisionException>());
      expect(await task.events.toList(), isEmpty);
    },
  );

  test('backend dispatch can reenter cancel and dispose safely', () async {
    final gate = Completer<void>();
    backend.runGates.add(gate);
    late DecisionTask<DecisionResult> task;
    Future<void>? disposal;
    backend.onRun = () {
      task.cancel();
      disposal = decisions.dispose();
      expect(decisions.dispose(), same(disposal));
    };
    task = start();
    await backend.runStarted.future;
    expect(backend.freed, isEmpty);
    gate.complete();
    expect((await task.done).state, DecisionCompletionState.cancelled);
    await disposal;
    expect(backend.freed, [7]);
  });

  test('batch cancellation stops before tokenizing the next request', () async {
    late DecisionTask<List<DecisionResult>> task;
    backend.onTokenize = (text) {
      if (text.startsWith(' true:')) task.cancel();
    };
    task = decisions.systemOneBatchTask([
      DecisionRequest(state: 'first', questions: questions),
      DecisionRequest(state: 'second', questions: questions),
    ]);
    expect((await task.done).state, DecisionCompletionState.cancelled);
    expect(backend.tokenized, isNot(contains('second')));
    expect(backend.runs, isEmpty);
  });

  test('task created after disposal fails with a typed state error', () async {
    await decisions.dispose();
    final task = start();
    expect((await task.done).state, DecisionCompletionState.failed);
    await expectLater(task.result, throwsA(isA<LlamaStateException>()));
    expect(backend.runs, isEmpty);
  });
}

Future<void> _until(bool Function() condition) async {
  for (var n = 0; n < 100 && !condition(); n++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}

class _Backend implements LlamaBackend, BackendDecision {
  bool _ready = false;
  int _model = 0;
  final List<String> tokenized = [];
  final List<List<BackendDecisionSequence>> runs = [];
  final List<int> freed = [];
  final List<Completer<void>> runGates = [];
  final Completer<void> tokenizeStarted = Completer<void>();
  final Completer<void> runStarted = Completer<void>();
  Completer<void>? tokenizeGate;
  void Function(String)? onTokenize;
  Object? tokenizeError;
  Object? runError;
  bool dropOutputs = false;
  void Function()? onRun;
  int globalCancels = 0;
  @override
  bool get isReady => _ready;
  @override
  bool get supportsUrlLoading => true;
  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}
  @override
  Future<int> modelLoad(String path, ModelParams params) async {
    _ready = true;
    return ++_model;
  }

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    void Function(double)? onProgress,
  }) => modelLoad(url, params);
  @override
  Future<int> getContextSize(int contextHandle) async => 512;
  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async => 2;
  @override
  Future<void> contextFree(int handle) async {}
  @override
  Future<void> modelFree(int handle) async => _ready = false;
  @override
  Future<void> dispose() async {}
  @override
  void cancelGeneration() => globalCancels++;
  @override
  Future<String> getBackendName() async => 'CPU';
  @override
  Future<BackendDecisionCapabilities> decisionCapabilities(
    int modelHandle,
  ) async => const BackendDecisionCapabilities(isSupported: true);
  @override
  Future<BackendDecisionHeadInfo> decisionHeadLoad(
    int modelHandle,
    String headPath, {
    String? configPath,
  }) async => const BackendDecisionHeadInfo(
    handle: 7,
    hiddenSize: 4,
    clsToken: 1,
    sepToken: 2,
    maskToken: 3,
    maskText: '[MASK]',
    configJson: '{}',
    deviceName: 'CPU',
  );
  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async {
    tokenized.add(text);
    if (!tokenizeStarted.isCompleted) tokenizeStarted.complete();
    await tokenizeGate?.future;
    onTokenize?.call(text);
    if (tokenizeError case final error?) throw error;
    return text.codeUnits;
  }

  @override
  Future<List<BackendDecisionOutput>> decisionRun(
    int headHandle,
    List<BackendDecisionSequence> sequences,
  ) async {
    runs.add(sequences);
    onRun?.call();
    if (!runStarted.isCompleted) runStarted.complete();
    if (runGates.isNotEmpty) await runGates.removeAt(0).future;
    if (runError case final error?) throw error;
    if (dropOutputs) return [];
    return [
      for (final sequence in sequences)
        BackendDecisionOutput(
          logits: Float32List(sequence.markers.length),
          actLogits: Float32List(2),
        ),
    ];
  }

  @override
  Future<void> decisionHeadFree(int headHandle) async => freed.add(headHandle);
  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) => Stream.value('text'.codeUnits);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
