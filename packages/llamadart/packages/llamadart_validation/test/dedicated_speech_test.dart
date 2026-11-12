import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart_validation/src/speech_runner.dart';
import 'package:test/test.dart';

class Recognizer implements SpeechToTextEngine {
  final session = Session();
  @override
  final SpeechToTextAdapter adapter = const LiteRtLmAsrAdapter(
    LiteRtLmAsrModelPreset.moonshineTiny,
  );
  @override
  bool isDisposed = false;
  @override
  Future<void> dispose() async {
    isDisposed = true;
  }

  @override
  Future<SpeechToTextCapabilities> get capabilities async =>
      const SpeechToTextCapabilities(isSupported: true);
  @override
  Future<SpeechToTextStreamingSession> startStream({
    SpeechAudioFormat? format,
  }) async {
    if (format?.sampleRateHz == 8000) throw ArgumentError('unsupported');
    return session;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PartialOnListen extends Stream<SpeechToTextEvent> {
  PartialOnListen(this.source);
  final Stream<SpeechToTextEvent> source;
  @override
  StreamSubscription<SpeechToTextEvent> listen(
    void Function(SpeechToTextEvent event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    onData?.call(const SpeechToTextPartialEvent('partial'));
    return source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class Session implements SpeechToTextStreamingSession {
  final controller = StreamController<SpeechToTextEvent>();
  final completion = Completer<SpeechToTextCompletion>();
  int samples = 0;
  int largestPush = 0;
  bool omitFinal = false;
  bool emitError = false;
  bool cancelCalled = false;
  int? partialAfterSamples;
  bool partialOnListen = false;
  int? endAfterSamples;
  Duration? cancelAckDelay;
  bool finalOnCancel = false;
  @override
  Stream<SpeechToTextEvent> get events =>
      partialOnListen ? PartialOnListen(controller.stream) : controller.stream;
  @override
  Future<SpeechToTextCompletion> get done => completion.future;
  @override
  Future<void> addPcm(Float32List pcm) async {
    samples += pcm.length;
    if (pcm.length > largestPush) largestPush = pcm.length;
    final threshold = partialAfterSamples;
    if (threshold != null && samples >= threshold && !controller.isClosed) {
      partialAfterSamples = null;
      controller.add(const SpeechToTextPartialEvent('partial'));
    }
    final end = endAfterSamples;
    if (end != null && samples >= end) {
      endAfterSamples = null;
      await _end();
    }
  }

  @override
  Future<void> finish() async {
    const result = SpeechToTextResult(text: 'expected');
    completion.complete(SpeechToTextCompletion.completed(result));
    // Deliberately deliver after completion, testing stream draining.
    scheduleMicrotask(() {
      if (emitError) controller.addError(StateError('stream failure'));
      if (!omitFinal) controller.add(const SpeechToTextFinalEvent(result));
      controller.close();
    });
  }

  @override
  Future<void> cancel() async {
    cancelCalled = true;
    final delay = cancelAckDelay;
    if (delay == null) return _end();
    cancelAckDelay = null;
    unawaited(Future<void>.delayed(delay, _end));
  }

  Future<void> _end() async {
    if (completion.isCompleted) return;
    if (finalOnCancel) {
      controller.add(
        const SpeechToTextFinalEvent(SpeechToTextResult(text: 'expected')),
      );
    }
    completion.complete(const SpeechToTextCompletion.cancelled());
    await controller.close();
  }
}

void main() {
  PublicDedicatedSpeechAdapter adapter(Recognizer recognizer) =>
      PublicDedicatedSpeechAdapter(
        model: SpeechToTextModel(
          ModelSource.path('fixture'),
          tokenizer: ModelSource.path('fixture'),
          adapter: const LiteRtLmAsrAdapter(
            LiteRtLmAsrModelPreset.moonshineTiny,
          ),
        ),
        wav: File('assets/speech/jfk.wav').readAsBytesSync(),
        reference: 'expected',
        loadRecognizer: (_) async => recognizer,
      );
  test(
    'CPU adapter pushes bounded PCM and drains delayed final before passing',
    () async {
      final engine = Recognizer();
      final target = adapter(engine);
      await target.load();
      final result = await target.execute();
      expect(result['predicate_passed'], true);
      expect(engine.session.samples, 176000);
      expect(engine.session.largestPush, 1600);
      expect(engine.session.cancelCalled, true);
      await target.dispose();
      expect(engine.isDisposed, isTrue);
    },
  );
  test(
    'missing final and stream errors cannot be masked by completed future',
    () async {
      for (final error in [false, true]) {
        final engine = Recognizer();
        engine.session.omitFinal = !error;
        engine.session.emitError = error;
        final target = adapter(engine);
        await target.load();
        await expectLater(target.execute(), throwsStateError);
        expect(engine.session.cancelCalled, true);
        await target.dispose();
      }
    },
  );
  test('streaming cancellation is issued after audio is pushed', () async {
    final engine = Recognizer();
    final target = adapter(engine);
    await target.load();
    final cancelled = await target.execute(cancel: true);
    expect(cancelled['cancelled'], isTrue);
    expect(cancelled['cancel_in_flight'], isTrue);
    expect(cancelled['pcm_samples_before_cancel'], 176000);
    expect(cancelled['partial_events_before_cancel'], 0);
    expect(cancelled['cancel_after_ms'], greaterThan(0));
    expect(cancelled['cancel_latency_ms'], isA<double>());
    expect(cancelled['cancel_latency_ms'], greaterThanOrEqualTo(0));
    expect(engine.session.cancelCalled, isTrue);
    await target.dispose();
  });
  test('a first partial stops the push and cancels there', () async {
    final engine = Recognizer();
    engine.session.partialAfterSamples = 16000;
    final target = adapter(engine);
    await target.load();
    final cancelled = await target.execute(cancel: true);
    expect(cancelled['cancel_in_flight'], isTrue);
    expect(cancelled['partial_events_before_cancel'], 1);
    expect(cancelled['pcm_samples_before_cancel'], lessThan(176000));
    await target.dispose();
  });
  test(
    'a cancellation before any audio is accepted is not in flight',
    () async {
      final engine = Recognizer();
      engine.session.partialOnListen = true;
      final target = adapter(engine);
      await target.load();
      final cancelled = await target.execute(cancel: true);
      expect(cancelled['cancelled'], isTrue);
      expect(cancelled['partial_events_before_cancel'], 1);
      expect(cancelled['pcm_samples_before_cancel'], 0);
      expect(engine.session.samples, 0);
      expect(cancelled['cancel_in_flight'], isFalse);
      await target.dispose();
    },
  );
  test('streaming cancellation latency runs until the session ends', () async {
    const cancelAck = Duration(milliseconds: 100);
    for (final immediately in [false, true]) {
      final engine = Recognizer();
      engine.session.cancelAckDelay = cancelAck;
      final target = adapter(engine);
      await target.load();
      final cancelled = await target.execute(
        cancel: !immediately,
        cancelImmediately: immediately,
      );
      await target.dispose();
      expect(cancelled['cancelled'], isTrue);
      expect(
        cancelled['cancel_latency_ms'],
        greaterThan(cancelAck.inMilliseconds / 2),
        reason: 'immediately: $immediately',
      );
    }
  });
  test(
    'a stream that ended before the cancellation is not in flight',
    () async {
      final engine = Recognizer();
      engine.session.endAfterSamples = 16000;
      final target = adapter(engine);
      await target.load();
      final cancelled = await target.execute(cancel: true);
      await target.dispose();
      expect(cancelled['cancelled'], isTrue);
      expect(cancelled['pcm_samples_before_cancel'], greaterThan(0));
      expect(cancelled['cancel_in_flight'], isFalse);
    },
  );
  test('a cancelled stream that emitted a final result fails', () async {
    final engine = Recognizer();
    engine.session.finalOnCancel = true;
    final target = adapter(engine);
    await target.load();
    await expectLater(target.execute(cancel: true), throwsStateError);
    await target.dispose();
  });
  test('an immediate streaming cancellation pushes no audio', () async {
    final engine = Recognizer();
    final target = adapter(engine);
    await target.load();
    final cancelled = await target.execute(cancelImmediately: true);
    expect(cancelled['cancelled'], isTrue);
    expect(cancelled['cancel_immediate'], isTrue);
    expect(cancelled.containsKey('cancel_in_flight'), isFalse);
    expect(cancelled['pcm_samples_before_cancel'], 0);
    expect(engine.session.samples, 0);
    expect(cancelled['cancel_after_ms'], greaterThanOrEqualTo(0));
    expect(cancelled['cancel_latency_ms'], greaterThanOrEqualTo(0));
    expect(engine.session.cancelCalled, isTrue);
    await expectLater(
      target.execute(cancel: true, cancelImmediately: true),
      throwsArgumentError,
    );
    await target.dispose();
  });
  test(
    'invalid sample-rate is exercised through public streaming contract',
    () async {
      final target = adapter(Recognizer());
      await target.load();
      await expectLater(target.execute(invalid: true), throwsArgumentError);
      await target.dispose();
    },
  );
}
