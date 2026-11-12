@TestOn('vm')
library;

import 'dart:async';

import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

import '../../core/runtime/test_support/fake_runtime.dart';

const _model = LlamaModelDefinition(
  name: 'local',
  modelPath: '/app/model.gguf',
);
const _native = llama.LlamaEngineCapabilities(
  isSupported: true,
  runtime: llama.LlamaRuntime.llamaCpp,
  supportsNextTokenScoring: true,
);

void main() {
  test(
    'owners are independent, capacity includes opening and closing',
    () async {
      final first = _Runtime('A')..loading = Completer<void>();
      final second = _Runtime('B');
      final runtimes = [first, second];
      final pool = LlamaDartRuntimePool(
        model: _model,
        runtimeFactory: () => runtimes.removeAt(0),
      );
      addTearDown(pool.close);
      final opening = pool.open();
      final b = await pool.open();
      await expectLater(pool.open(), throwsA(isA<LlamaStateException>()));
      first.loading!.complete();
      final a = await opening;
      expect(await a.generate('A input'), 'A');
      expect(await b.generate('B input'), 'B');
      await a.close();
      expect(first.disposeCount, 1);
      expect(second.disposeCount, 0);
      expect(await b.generate('still B'), 'B');
      expect(first.prompts, ['A input']);
      expect(second.prompts, ['B input', 'still B']);
    },
  );

  test(
    'factory reentrant opening reserves admission before allocation',
    () async {
      late LlamaDartRuntimePool pool;
      Future<void>? nestedRejected;
      var allocations = 0;
      pool = LlamaDartRuntimePool(
        model: _model,
        maxOwners: 1,
        runtimeFactory: () {
          allocations++;
          nestedRejected = expectLater(
            pool.open(),
            throwsA(isA<LlamaStateException>()),
          );
          return _Runtime('A');
        },
      );
      addTearDown(pool.close);
      final owner = await pool.open();
      await nestedRejected;
      expect(allocations, 1);
      expect(await owner.generate('safe'), 'A');
    },
  );

  test(
    'factory closing drains allocated cleanup before terminal close',
    () async {
      late LlamaDartRuntimePool pool;
      final runtime = _Runtime('A')..disposing = Completer<void>();
      Future<void>? closing;
      var closed = false;
      pool = LlamaDartRuntimePool(
        model: _model,
        runtimeFactory: () {
          closing = pool.close().then((_) => closed = true);
          return runtime;
        },
      );
      final rejected = expectLater(
        pool.open(),
        throwsA(isA<LlamaStateException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(runtime.disposeCount, 1);
      expect(closed, isFalse);
      expect(runtime.initializeCount, 0);
      runtime.disposing!.complete();
      await rejected;
      await closing;
      expect(closed, isTrue);
      await expectLater(pool.open(), throwsA(isA<LlamaStateException>()));
    },
  );

  test('factory allocation failure releases reserved admission', () async {
    var attempts = 0;
    final pool = LlamaDartRuntimePool(
      model: _model,
      maxOwners: 1,
      runtimeFactory: () {
        if (attempts++ == 0) throw StateError('/secret/factory');
        return _Runtime('A');
      },
    );
    addTearDown(pool.close);
    await expectLater(
      pool.open(),
      throwsA(
        predicate<Object>(
          (error) =>
              error is LlamaStateException &&
              !error.toString().contains('/secret'),
        ),
      ),
    );
    expect(await (await pool.open()).generate('recovered'), 'A');
  });

  test('factory cannot return an already owned runtime', () async {
    final runtime = _Runtime('A');
    final pool = LlamaDartRuntimePool(
      model: _model,
      runtimeFactory: () => runtime,
    );
    addTearDown(pool.close);
    final owner = await pool.open();
    await expectLater(pool.open(), throwsA(isA<LlamaStateException>()));
    expect(runtime.disposeCount, 0);
    expect(await owner.generate('safe'), 'A');
  });

  test('bounded queue drains accepted work and close is terminal', () async {
    final runtime = _Runtime('A')..blocked = Completer<void>();
    final pool = LlamaDartRuntimePool(
      model: _model,
      maxQueuedOperations: 1,
      runtimeFactory: () => runtime,
    );
    addTearDown(pool.close);
    final owner = await pool.open();
    final active = owner.generate('first');
    await runtime.started.future;
    final queued = owner.generate('second');
    await expectLater(
      owner.generate('overflow'),
      throwsA(isA<LlamaStateException>()),
    );
    final closing = owner.close();
    expect(identical(closing, owner.close()), isTrue);
    await expectLater(
      owner.generate('closed'),
      throwsA(isA<LlamaStateException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(runtime.disposeCount, 0);
    expect(runtime.prompts, ['first']);
    runtime.blocked!.complete();
    expect(await active, 'A');
    expect(await queued, 'A');
    await closing;
    expect(runtime.prompts, ['first', 'second']);
    expect(runtime.disposeCount, 1);
  });

  test(
    'queued cancellation skips native work and leaves owner usable',
    () async {
      final runtime = _Runtime('A')..blocked = Completer<void>();
      final pool = LlamaDartRuntimePool(
        model: _model,
        runtimeFactory: () => runtime,
      );
      addTearDown(pool.close);
      final owner = await pool.open();
      final active = owner.generate('first');
      await runtime.started.future;
      final token = CancellationController();
      final queued = owner.generate('never starts', cancellation: token.token);
      final rejected = expectLater(queued, throwsA(isA<CancelledException>()));
      token.cancel();
      runtime.blocked!.complete();
      await active;
      await rejected;
      expect(owner.isClosed, isFalse);
      expect(runtime.prompts, ['first']);
      expect(runtime.cancelGenerationCount, 0);
      expect(await owner.generate('later'), 'A');
    },
  );

  test(
    'active cancellation faults A and cannot cancel B or queued inference',
    () async {
      final a = _Runtime('A')..blocked = Completer<void>();
      final b = _Runtime('B');
      final runtimes = [a, b];
      final pool = LlamaDartRuntimePool(
        model: _model,
        runtimeFactory: () => runtimes.removeAt(0),
      );
      addTearDown(pool.close);
      final ownerA = await pool.open();
      final ownerB = await pool.open();
      final active = ownerA.generate('first');
      final rejectedActive = expectLater(
        active,
        throwsA(isA<CancelledException>()),
      );
      await a.started.future;
      final queued = ownerA.generate('never starts');
      final rejectedQueued = expectLater(
        queued,
        throwsA(isA<LlamaStateException>()),
      );
      ownerA.cancelActiveGeneration();
      await rejectedActive;
      await rejectedQueued;
      expect(a.cancelGenerationCount, 1);
      expect(a.disposeCount, 1);
      expect(a.prompts, ['first']);
      expect(ownerA.isClosed, isTrue);
      expect(await ownerB.generate('independent'), 'B');
      expect(b.cancelGenerationCount, 0);
      expect(b.disposeCount, 0);
    },
  );

  test('request token cancels active work and waits for cleanup', () async {
    final runtime = _Runtime('A')
      ..blocked = Completer<void>()
      ..cancelError = true;
    final pool = LlamaDartRuntimePool(
      model: _model,
      runtimeFactory: () => runtime,
    );
    addTearDown(pool.close);
    final owner = await pool.open();
    final token = CancellationController();
    final result = owner.generate('prompt', cancellation: token.token);
    final rejected = expectLater(result, throwsA(isA<CancelledException>()));
    await runtime.started.future;
    token.cancel();
    token.cancel();
    await rejected;
    expect(runtime.cancelGenerationCount, 1);
    expect(runtime.disposeCount, 1);
  });

  test('failed initialization settles cleanup and frees admission', () async {
    final failed = _Runtime('failed')
      ..initializeError = StateError('/secret/init');
    final good = _Runtime('good');
    final runtimes = [failed, good];
    final pool = LlamaDartRuntimePool(
      model: _model,
      maxOwners: 1,
      runtimeFactory: () => runtimes.removeAt(0),
    );
    addTearDown(pool.close);
    await expectLater(
      pool.open(),
      throwsA(
        predicate<Object>(
          (error) =>
              error is LlamaStateException &&
              !error.toString().contains('/secret'),
        ),
      ),
    );
    expect(failed.disposeCount, 1);
    expect(await (await pool.open()).generate('recovered'), 'good');
  });

  test('fresh probes prevent use after capability loss', () async {
    final runtime = _Runtime('A');
    final pool = LlamaDartRuntimePool(
      model: _model,
      runtimeFactory: () => runtime,
    );
    addTearDown(pool.close);
    final owner = await pool.open();
    runtime.capabilitySnapshot = const llama.LlamaEngineCapabilities(
      isSupported: false,
    );
    await expectLater(
      owner.generate('must not run'),
      throwsA(isA<LlamaUnsupportedException>()),
    );
    expect(runtime.prompts, isEmpty);
    expect(runtime.disposeCount, 1);
  });

  test(
    'non-GGUF rejected before allocation; unverified runtime disposed',
    () async {
      var allocations = 0;
      final unsupported = LlamaDartRuntimePool(
        model: const LlamaModelDefinition(
          name: 'lite',
          modelPath: '/missing/model.litertlm',
        ),
        runtimeFactory: () {
          allocations++;
          return _Runtime('unused');
        },
      );
      await expectLater(
        unsupported.open(),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(allocations, 0);
      await unsupported.close();
      final runtime = _Runtime('unverified')
        ..capabilitySnapshot = const llama.LlamaEngineCapabilities(
          isSupported: true,
        );
      final pool = LlamaDartRuntimePool(
        model: _model,
        runtimeFactory: () => runtime,
      );
      await expectLater(pool.open(), throwsA(isA<LlamaUnsupportedException>()));
      expect(runtime.disposeCount, 1);
      await pool.close();
    },
  );

  test(
    'scoring rejects missing providers and withdrawn scoring support',
    () async {
      final missing = FakeRuntime()..capabilitySnapshot = _native;
      final withdrawn = _Runtime('A');
      for (final runtime in [missing, withdrawn]) {
        final pool = LlamaDartRuntimePool(
          model: _model,
          runtimeFactory: () => runtime,
        );
        final owner = await pool.open();
        if (identical(runtime, withdrawn)) {
          withdrawn.capabilitySnapshot = const llama.LlamaEngineCapabilities(
            isSupported: true,
            runtime: llama.LlamaRuntime.llamaCpp,
            supportsNextTokenScoring: false,
          );
        }
        await expectLater(
          owner.scoreNextToken('must not evaluate', topK: 1),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(withdrawn.scoredCandidates, isNull);
        expect(owner.isClosed, isTrue);
        expect(runtime.disposeCount, 1);
        await pool.close();
      }
    },
  );

  test('scoring snapshots candidates and shares generation ordering', () async {
    final runtime = _Runtime('A')..blocked = Completer<void>();
    final pool = LlamaDartRuntimePool(
      model: _model,
      runtimeFactory: () => runtime,
    );
    addTearDown(pool.close);
    final owner = await pool.open();
    final active = owner.generate('first');
    await runtime.started.future;
    final candidates = [3, 1, 3];
    final score = owner.scoreNextToken(
      'score',
      candidates: candidates,
      reusePromptPrefix: false,
    );
    candidates.clear();
    await Future<void>.delayed(Duration.zero);
    expect(runtime.scoredCandidates, isNull);
    runtime.blocked!.complete();
    await active;
    expect((await score).promptTokens, 1);
    expect(runtime.scoredCandidates, [3, 1, 3]);
    expect(runtime.scoreReuse, isFalse);
    expect(runtime.capabilityReadCount, 3);
  });

  test(
    'idle expiration excludes running work and cancelled queued work still expires',
    () async {
      final runtime = _Runtime('A')..blocked = Completer<void>();
      final pool = LlamaDartRuntimePool(
        model: _model,
        idleTimeout: const Duration(milliseconds: 10),
        runtimeFactory: () => runtime,
      );
      addTearDown(pool.close);
      final owner = await pool.open();
      final active = owner.generate('running');
      await runtime.started.future;
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(owner.isClosed, isFalse);
      final token = CancellationController()..cancel();
      final cancelled = expectLater(
        owner.generate('cancelled', cancellation: token.token),
        throwsA(isA<CancelledException>()),
      );
      runtime.blocked!.complete();
      await active;
      await cancelled;
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(owner.isClosed, isTrue);
      expect(runtime.disposeCount, 1);
    },
  );

  test(
    'pool close drains opening; disposal failures keep admission reserved',
    () async {
      final loading = _Runtime('A')..loading = Completer<void>();
      final pool = LlamaDartRuntimePool(
        model: _model,
        runtimeFactory: () => loading,
      );
      final opening = pool.open();
      final rejected = expectLater(
        opening,
        throwsA(isA<LlamaStateException>()),
      );
      final closing = pool.close();
      loading.loading!.complete();
      await rejected;
      await closing;
      expect(loading.disposeCount, 1);
      await expectLater(pool.open(), throwsA(isA<LlamaStateException>()));
      final broken = _Runtime('broken')
        ..disposeError = StateError('/secret/dispose');
      final brokenPool = LlamaDartRuntimePool(
        model: _model,
        maxOwners: 1,
        runtimeFactory: () => broken,
      );
      final owner = await brokenPool.open();
      await expectLater(
        owner.close(),
        throwsA(
          predicate<Object>((error) => !error.toString().contains('/secret')),
        ),
      );
      await expectLater(brokenPool.open(), throwsA(isA<LlamaStateException>()));
      await expectLater(brokenPool.close(), throwsA(isA<ParallelWaitError>()));
      expect(broken.disposeCount, 1);
    },
  );
}

class _Runtime extends FakeRuntime implements LlamaRuntimeScoringProvider {
  _Runtime(this.output) {
    capabilitySnapshot = _native;
  }
  final String output;
  final List<String> prompts = [];
  final Completer<void> started = Completer<void>();
  Completer<void>? blocked;
  Completer<void>? loading;
  Completer<void>? disposing;
  List<int>? scoredCandidates;
  bool? scoreReuse;
  bool cancelError = false;

  @override
  Future<void> initialize(LlamaModelDefinition definition) async {
    await loading?.future;
    await super.initialize(definition);
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    await disposing?.future;
  }

  @override
  Stream<String> generate(
    String prompt, {
    llama.GenerationParams params = const llama.GenerationParams(),
    List<llama.LlamaContentPart>? parts,
  }) async* {
    prompts.add(prompt);
    if (!started.isCompleted) started.complete();
    await blocked?.future;
    yield output;
  }

  @override
  void cancelGeneration() {
    super.cancelGeneration();
    if (blocked?.isCompleted == false) blocked!.complete();
    if (cancelError) throw StateError('/secret/cancel');
  }

  @override
  Future<llama.LlamaNextTokenScores> scoreNextToken(
    String prompt, {
    List<int> candidates = const [],
    int topK = 0,
    bool reusePromptPrefix = true,
  }) async {
    scoredCandidates = candidates;
    scoreReuse = reusePromptPrefix;
    return llama.LlamaNextTokenScores(candidates: [], top: [], promptTokens: 1);
  }
}
