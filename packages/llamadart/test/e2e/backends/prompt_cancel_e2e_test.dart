@TestOn('vm')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

/// Cancels a native llama.cpp generation while its ~1,600-token prompt is
/// being evaluated, as in issues #660 and #663.
void main() {
  final model = Platform.environment['PROMPT_CANCEL_MODEL'];
  final backendName = Platform.environment['PROMPT_CANCEL_BACKEND'] ?? 'cpu';
  final threads = int.parse(
    Platform.environment['PROMPT_CANCEL_THREADS'] ?? '4',
  );
  final backend = GpuBackend.values.byName(backendName);
  const fullPrompt = GenerationParams(
    maxTokens: 16,
    temp: 0,
    seed: 1,
    reusePromptPrefix: false,
  );

  late LlamaEngine engine;
  late String prompt;
  late Duration promptTime;
  late String uncancelled;

  Future<(String, Duration)> timedRun(GenerationParams params) async {
    final stopwatch = Stopwatch()..start();
    Duration? firstToken;
    final text = StringBuffer();
    await for (final token in engine.generate(prompt, params: params)) {
      firstToken ??= stopwatch.elapsed;
      text.write(token);
    }
    return (text.toString(), firstToken ?? stopwatch.elapsed);
  }

  void report(String name, Duration latency) {
    print(
      jsonEncode({
        'case': name,
        'backend': backendName,
        'threads': threads,
        'prompt_ms': promptTime.inMilliseconds,
        'cancel_to_end_ms': latency.inMilliseconds,
      }),
    );
  }

  setUpAll(() async {
    expect(model, isNotNull, reason: 'Set PROMPT_CANCEL_MODEL to a GGUF');
    engine = LlamaEngine(LlamaBackend());
    await engine.loadModel(
      model!,
      modelParams: ModelParams(
        contextSize: 2048,
        gpuLayers: backend == GpuBackend.cpu ? 0 : 99,
        preferredBackend: backend,
        numberOfThreads: threads,
        numberOfThreadsBatch: threads,
      ),
    );
    final lines = <String>[];
    var tokens = 0;
    while (tokens < 1600) {
      lines.add(
        'Note ${lines.length + 1}: the river keeps its own slow time, and '
        'the lanterns along the bank count every boat that passes by.',
      );
      tokens = await engine.getTokenCount(lines.join('\n'));
    }
    prompt = lines.join('\n');
    await timedRun(fullPrompt);
    final (text, firstToken) = await timedRun(fullPrompt);
    uncancelled = text;
    promptTime = firstToken;
    print(
      jsonEncode({
        'prompt_tokens': tokens,
        'backend': backendName,
        'prompt_ms': promptTime.inMilliseconds,
        'uncancelled': uncancelled,
      }),
    );
  });

  tearDownAll(() => engine.dispose());

  Future<void> duringPrompt() => Future<void>.delayed(promptTime * 0.2);

  /// Cancels [stream] during prompt evaluation and returns the cancel's
  /// latency and the callbacks that ran after the cancel was called.
  Future<(Duration, List<String>)> cancelDuringPrompt(
    Stream<Object?> stream,
  ) async {
    final events = <String>[];
    var cancelCalled = false;
    final subscription = stream.listen(
      (event) {
        if (cancelCalled) events.add('data $event');
      },
      onError: (Object error) {
        if (cancelCalled) events.add('error $error');
      },
      onDone: () {
        if (cancelCalled) events.add('done');
      },
    );
    await duringPrompt();
    final stopwatch = Stopwatch()..start();
    cancelCalled = true;
    await subscription.cancel();
    final cancelled = stopwatch.elapsed;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return (cancelled, events);
  }

  test('cancelGeneration during prompt evaluation ends the stream before '
      'the prompt is evaluated', () async {
    final done = Completer<void>();
    engine
        .generate(prompt, params: fullPrompt)
        .listen((_) {}, onDone: done.complete);
    await duringPrompt();
    final stopwatch = Stopwatch()..start();
    engine.cancelGeneration();
    await done.future;
    final cancelled = stopwatch.elapsed;
    report('cancelGeneration', cancelled);
    final (text, _) = await timedRun(fullPrompt);

    expect(cancelled, lessThan(promptTime * 0.6));
    expect(text, uncancelled);
  });

  test('an awaited subscription cancel during prompt evaluation returns '
      'before the prompt is evaluated and delivers no events', () async {
    final (cancelled, events) = await cancelDuringPrompt(
      engine.generate(prompt, params: fullPrompt),
    );
    report('subscription.cancel', cancelled);
    final (text, _) = await timedRun(fullPrompt);

    expect(events, isEmpty);
    expect(cancelled, lessThan(promptTime * 0.6));
    expect(text, uncancelled);
  });

  test(
    'an awaited create() subscription cancel during prompt evaluation '
    'returns before the prompt is evaluated and delivers no events',
    () async {
      final (cancelled, events) = await cancelDuringPrompt(
        engine.create([
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt),
        ], params: fullPrompt),
      );
      report('create subscription.cancel', cancelled);
      final (text, _) = await timedRun(fullPrompt);

      expect(events, isEmpty);
      expect(cancelled, lessThan(promptTime * 0.6));
      expect(text, uncancelled);
    },
  );

  test('a generation right after an un-awaited subscription cancel during '
      'prompt evaluation matches an uncancelled run', () async {
    const reusing = GenerationParams(maxTokens: 16, temp: 0, seed: 1);
    final subscription = engine
        .generate(prompt, params: reusing)
        .listen((_) {});
    await duringPrompt();
    unawaited(subscription.cancel());
    final (text, _) = await timedRun(reusing);

    expect(text, uncancelled);
  });
}
