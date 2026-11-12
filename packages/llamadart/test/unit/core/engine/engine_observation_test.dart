import 'dart:async';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/engine/engine_observation.dart';
import 'package:test/test.dart';

final class _Recorder extends LlamaEngineObserver {
  final List<String> log = <String>[];
  final List<LlamaOperationResult> results = <LlamaOperationResult>[];
  final bool ignore;

  _Recorder({this.ignore = false});

  @override
  LlamaOperationObserver? onStart(LlamaOperation operation) {
    log.add('start');
    return ignore ? null : _OperationRecorder(this);
  }
}

final class _OperationRecorder extends LlamaOperationObserver {
  final _Recorder recorder;

  _OperationRecorder(this.recorder);

  @override
  void onText(String text) => recorder.log.add('text $text');

  @override
  void onEnd(LlamaOperationResult result) {
    recorder.log.add('end');
    recorder.results.add(result);
  }
}

final _operation = LlamaTextCompletionOperation(
  model: 'm',
  runtime: null,
  prompt: 'p',
  params: GenerationParams(),
);

Stream<String> _observe(
  Stream<String> source,
  List<LlamaEngineObserver> observers,
) => observeStream(
  source,
  observers: observers,
  zone: Zone.current,
  operation: _operation,
  onItem: (observation, text) => observation.text(text),
  result: () => const LlamaOperationResult(finishReason: 'stop'),
  cancelResult: () => const LlamaOperationResult(cancelled: true),
);

void main() {
  test('reports items before the listener and one completion', () async {
    final recorder = _Recorder();
    final seen = <String>[];

    await _observe(Stream<String>.fromIterable(['a', 'b']), [
      recorder,
    ]).forEach((text) => seen.add('listener $text'));

    expect(recorder.log, ['start', 'text a', 'text b', 'end']);
    expect(seen, ['listener a', 'listener b']);
    expect(recorder.results.single.finishReason, 'stop');
    expect(recorder.results.single.cancelled, isFalse);
  });

  test('reports the first error once, not the later completion', () async {
    final recorder = _Recorder();
    final source = StreamController<String>();
    final errors = <Object>[];
    final done = Completer<void>();
    _observe(source.stream, [
      recorder,
    ]).listen(null, onError: errors.add, onDone: done.complete);

    source
      ..addError(StateError('first'))
      ..addError(StateError('second'));
    await source.close();
    await done.future;

    expect(errors, hasLength(2));
    expect(recorder.results, hasLength(1));
    expect(
      recorder.results.single.error,
      isA<StateError>().having((e) => e.message, 'message', 'first'),
    );
  });

  test('forwards pause, resume and cancel to the source', () async {
    final calls = <String>[];
    final source = StreamController<String>(
      onPause: () => calls.add('pause'),
      onResume: () => calls.add('resume'),
      onCancel: () => calls.add('cancel'),
    );
    final recorder = _Recorder();
    final subscription = _observe(source.stream, [recorder]).listen(null);

    subscription.pause();
    subscription.resume();
    await subscription.cancel();
    await source.close();

    expect(calls, ['pause', 'resume', 'cancel']);
    expect(recorder.results.single.cancelled, isTrue);
  });

  test('does not start before it is listened to', () async {
    final recorder = _Recorder();

    final stream = _observe(Stream<String>.value('a'), [recorder]);
    await Future<void>.delayed(Duration.zero);
    expect(recorder.log, isEmpty);

    await stream.drain<void>();
    expect(recorder.log.first, 'start');
  });

  test(
    'an observer that ignores the operation gets no further calls',
    () async {
      final ignoring = _Recorder(ignore: true);
      final recording = _Recorder();

      await _observe(Stream<String>.value('a'), [
        ignoring,
        recording,
      ]).drain<void>();

      expect(ignoring.log, ['start']);
      expect(recording.log, ['start', 'text a', 'end']);
    },
  );

  test('a future operation starts before its body runs', () async {
    final recorder = _Recorder();
    final order = <String>[];

    final value = await observeFuture(
      () async {
        order.addAll(recorder.log);
        return 42;
      },
      observers: [recorder],
      operation: _operation,
    );

    expect(value, 42);
    expect(order, ['start']);
    expect(recorder.log, ['start', 'end']);
  });

  test('a failed future operation reports and rethrows its error', () async {
    final recorder = _Recorder();

    await expectLater(
      observeFuture<void>(
        () async => throw StateError('boom'),
        observers: [recorder],
        operation: _operation,
      ),
      throwsStateError,
    );

    expect(recorder.results.single.error, isStateError);
  });
}
