@TestOn('vm')
library;

import 'dart:async';

import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

import '../../core/runtime/test_support/fake_runtime.dart';

const _model = LlamaModelDefinition(name: 'raw', modelPath: '/model.gguf');
const _native = llama.LlamaEngineCapabilities(
  isSupported: true,
  runtime: llama.LlamaRuntime.llamaCpp,
);

void main() {
  test(
    'mutations serialize both ways with inference and forward source options',
    () async {
      final runtime = _LoraRuntime()..generationBlocked = Completer<void>();
      final pool = LlamaDartRuntimePool(
        model: _model,
        runtimeFactory: () => runtime,
      );
      addTearDown(pool.close);
      final owner = await pool.open();
      final generation = owner.generate('before');
      await runtime.generationStarted.future;
      final source = ModelSource.path('/adapter.gguf');
      final download = ModelLoadOptions(
        headers: {'Authorization': 'private-adapter'},
      );
      void progress(llama.ModelDownloadProgress _) {}
      runtime.mutationBlocked = Completer<void>();
      final mutation = owner.setLoraSource(
        source,
        scale: 0.5,
        download: download,
        onProgress: progress,
      );
      await Future<void>.delayed(Duration.zero);
      expect(runtime.events, ['generate']);
      runtime.generationBlocked!.complete();
      await generation;
      await runtime.mutationStarted.future;
      final next = owner.generate('after');
      await Future<void>.delayed(Duration.zero);
      expect(runtime.events, ['generate', 'apply']);
      expect(runtime.source, same(source));
      expect(runtime.scale, 0.5);
      expect(runtime.download, same(download));
      expect(runtime.progress, same(progress));
      runtime.mutationBlocked!.complete();
      await mutation;
      await next;
      await owner.removeLoraSource(source);
      expect(runtime.source, same(source));
      await owner.clearLoras();
      expect(runtime.events, [
        'generate',
        'apply',
        'generate',
        'remove',
        'clear',
      ]);
      expect(runtime.loraProbes, 3);
    },
  );

  test('missing or false live probe rejects before source loading', () async {
    for (final runtime in [
      FakeRuntime()..capabilitySnapshot = _native,
      _LoraRuntime()..supports = false,
    ]) {
      final pool = LlamaDartRuntimePool(
        model: _model,
        runtimeFactory: () => runtime,
      );
      final owner = await pool.open();
      await expectLater(
        owner.setLoraSource(
          ModelSource.url(Uri.parse('https://example.invalid/private')),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      if (runtime is _LoraRuntime) expect(runtime.events, isEmpty);
      expect(owner.isClosed, isTrue);
      expect(runtime.disposeCount, 1);
      await pool.close();
    }
  });

  test('fresh probe loss blocks subsequent mutations', () async {
    final runtime = _LoraRuntime();
    final pool = LlamaDartRuntimePool(
      model: _model,
      runtimeFactory: () => runtime,
    );
    addTearDown(pool.close);
    final owner = await pool.open();
    await owner.clearLoras();
    runtime.supports = false;
    await expectLater(
      owner.clearLoras(),
      throwsA(isA<LlamaUnsupportedException>()),
    );
    expect(runtime.events, ['clear']);
    expect(runtime.loraProbes, 2);
    expect(runtime.disposeCount, 1);
  });

  test(
    'invalid scale and queued cancellation do not mutate or fault',
    () async {
      final runtime = _LoraRuntime()..generationBlocked = Completer<void>();
      final pool = LlamaDartRuntimePool(
        model: _model,
        runtimeFactory: () => runtime,
      );
      addTearDown(pool.close);
      final owner = await pool.open();
      final source = ModelSource.path('/adapter.gguf');
      for (final scale in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => owner.setLoraSource(source, scale: scale),
          throwsArgumentError,
        );
      }
      final generation = owner.generate('first');
      await runtime.generationStarted.future;
      final controller = CancellationController();
      final mutation = expectLater(
        owner.setLoraSource(source, cancellation: controller.token),
        throwsA(isA<CancelledException>()),
      );
      controller.cancel();
      runtime.generationBlocked!.complete();
      await generation;
      await mutation;
      expect(runtime.events, ['generate']);
      expect(owner.isClosed, isFalse);
      await owner.setLoraSource(source, scale: 0);
      expect(runtime.scale, 0);
    },
  );

  test('mutation failure closes A while B remains usable', () async {
    final a = _LoraRuntime()..mutationError = StateError('/secret/adapter');
    final b = _LoraRuntime();
    final runtimes = [a, b];
    final pool = LlamaDartRuntimePool(
      model: _model,
      runtimeFactory: () => runtimes.removeAt(0),
    );
    addTearDown(pool.close);
    final ownerA = await pool.open();
    final ownerB = await pool.open();
    await expectLater(
      ownerA.setLoraSource(ModelSource.path('/secret/adapter')),
      throwsA(
        predicate<Object>(
          (error) =>
              error is LlamaStateException &&
              !error.toString().contains('/secret'),
        ),
      ),
    );
    expect(a.disposeCount, 1);
    await expectLater(
      ownerA.generate('unusable'),
      throwsA(isA<LlamaStateException>()),
    );
    expect(await ownerB.generate('independent'), 'ok');
    expect(b.disposeCount, 0);
    expect(b.events, ['generate']);
  });

  test(
    'active mutation cancellation waits for settlement and cleanup',
    () async {
      final runtime = _LoraRuntime()..mutationBlocked = Completer<void>();
      final pool = LlamaDartRuntimePool(
        model: _model,
        runtimeFactory: () => runtime,
      );
      addTearDown(pool.close);
      final owner = await pool.open();
      final controller = CancellationController();
      final mutation = expectLater(
        owner.setLoraSource(
          ModelSource.path('/adapter.gguf'),
          cancellation: controller.token,
        ),
        throwsA(isA<CancelledException>()),
      );
      await runtime.mutationStarted.future;
      controller.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(owner.isClosed, isTrue);
      expect(runtime.disposeCount, 0);
      expect(runtime.cancelGenerationCount, 0);
      runtime.mutationBlocked!.complete();
      await mutation;
      expect(runtime.disposeCount, 1);
    },
  );
}

class _LoraRuntime extends FakeRuntime implements LlamaRuntimeLoraProvider {
  _LoraRuntime() {
    capabilitySnapshot = _native;
  }
  final List<String> events = [];
  final Completer<void> generationStarted = Completer<void>();
  final Completer<void> mutationStarted = Completer<void>();
  Completer<void>? generationBlocked;
  Completer<void>? mutationBlocked;
  Object? mutationError;
  bool supports = true;
  int loraProbes = 0;
  ModelSource? source;
  double? scale;
  ModelLoadOptions? download;
  llama.ModelDownloadProgressCallback? progress;

  @override
  Future<bool> get supportsLiveLora async {
    loraProbes++;
    return supports;
  }

  @override
  Stream<String> generate(
    String prompt, {
    llama.GenerationParams params = const llama.GenerationParams(),
    List<llama.LlamaContentPart>? parts,
  }) async* {
    events.add('generate');
    if (!generationStarted.isCompleted) generationStarted.complete();
    await generationBlocked?.future;
    yield 'ok';
  }

  @override
  Future<void> setLoraSource(
    ModelSource source, {
    double scale = 1,
    ModelLoadOptions download = ModelLoadOptions.defaults,
    llama.ModelDownloadProgressCallback? onProgress,
  }) async {
    this.source = source;
    this.scale = scale;
    this.download = download;
    progress = onProgress;
    events.add('apply');
    if (!mutationStarted.isCompleted) mutationStarted.complete();
    await mutationBlocked?.future;
    if (mutationError != null) throw mutationError!;
  }

  @override
  Future<void> removeLoraSource(ModelSource source) async {
    this.source = source;
    events.add('remove');
  }

  @override
  Future<void> clearLoras() async {
    events.add('clear');
  }
}
