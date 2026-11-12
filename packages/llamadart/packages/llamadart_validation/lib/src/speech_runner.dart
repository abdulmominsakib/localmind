import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';

import 'process_memory.dart';
import 'runner.dart' show redactDiagnostic;
import 'speech_edge_fixtures.dart';

/// Word edit distance divided by reference words; insertions can exceed 1.0.
/// Normalization lowercases, replaces `.,!?:;"—–` with spaces, then splits on
/// whitespace.
double speechWordErrorRate(String reference, String actual) {
  final expected = _speechWords(reference);
  final received = _speechWords(actual);
  if (expected.isEmpty) throw ArgumentError('Reference must contain words');
  var previous = List.generate(received.length + 1, (index) => index);
  for (var i = 1; i <= expected.length; i++) {
    final current = <int>[i];
    for (var j = 1; j <= received.length; j++) {
      final costs = [
        previous[j] + 1,
        current[j - 1] + 1,
        previous[j - 1] + (expected[i - 1] == received[j - 1] ? 0 : 1),
      ]..sort();
      current.add(costs.first);
    }
    previous = current;
  }
  return previous.last / expected.length;
}

List<String> _speechWords(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'''[.,!?:;"—–]'''), ' ')
    .trim()
    .split(RegExp(r'\s+'))
    .where((word) => word.isNotEmpty)
    .toList();

/// Whether [partial] is a non-empty strict prefix of [expected], comparing the
/// words [speechWordErrorRate] compares. The last word of [partial] may be cut
/// short.
bool speechTranscriptPrefixHolds(String expected, String partial) {
  final full = _speechWords(expected);
  final cut = _speechWords(partial);
  if (cut.isEmpty || cut.length > full.length) return false;
  for (var i = 0; i < cut.length - 1; i++) {
    if (cut[i] != full[i]) return false;
  }
  final word = full[cut.length - 1];
  return word.startsWith(cut.last) &&
      (cut.length < full.length || cut.last.length < word.length);
}

/// Validates generated audio, returning measurements without claiming quality.
Map<String, Object?> inspectSpeechAudio(TextToSpeechResult result) {
  if (result.sampleRateHz != 24000 ||
      result.channelCount != 1 ||
      result.samples.isEmpty ||
      result.samples.any((sample) => !sample.isFinite) ||
      result.samples.every((sample) => sample == 0) ||
      result.truncated) {
    throw StateError('Invalid, silent, nonfinite or truncated TTS output');
  }
  final seconds = result.samples.length / result.sampleRateHz;
  return {
    'sample_rate_hz': result.sampleRateHz,
    'channels': result.channelCount,
    'samples': result.samples.length,
    'audio_seconds': seconds,
    'truncated': result.truncated,
    'listening_check': 'NOT_RUN',
    'intelligibility': 'UNVERIFIED',
  };
}

/// Speech-only public API adapter; independent of chat-model generation.
abstract interface class SpeechValidationAdapter {
  Future<void> load();
  Future<void> dispose();

  /// With `cancel`, cancels after a wait and reports `cancel_latency_ms`,
  /// `cancel_after_ms` and `cancel_in_flight`, which is true only if the
  /// adapter had not seen the task finish when it cancelled. The TTS adapter
  /// also reports where the cancel landed: `progress_events_before_cancel`,
  /// `ms_since_last_progress_at_cancel`, `reference_progress_events` and
  /// `cancel_after_reference_last_progress`, true when it came after as many
  /// progress events as the reference generation emitted, so in its final
  /// step, which emits none. With
  /// `cancelImmediately`, cancels as soon as the task is handed back, without
  /// yielding first, and reports `cancel_latency_ms`, `cancel_after_ms` and
  /// `cancel_immediate`. Setting both throws [ArgumentError].
  Future<Map<String, Object?>> execute({
    bool cancel = false,
    bool cancelImmediately = false,
    bool invalid = false,
    bool bytesInput = false,
  });
}

/// Opt-in synthetic edge-case recognition; adapters without it keep their
/// existing check count.
abstract interface class SpeechEdgeCaseAdapter {
  /// Recognizes one synthetic fixture and reports the measured outcome.
  Future<Map<String, Object?>> executeEdge(SpeechEdgeFixture fixture);
}

/// Opt-in text-to-speech checks that interrupt a synthesis in flight; adapters
/// without it keep their existing check count.
abstract interface class SpeechSynthesisInterruptAdapter {
  /// Starts a synthesis and, once a progress event reports a generated frame,
  /// calls `LlamaEngine.unloadModel()`, or `LlamaEngine.dispose()` with
  /// [dispose]. Then reloads and runs a normal synthesis.
  ///
  /// Reports `in_flight`, true only if a frame was reported and the task had
  /// not finished when the call was made; `frames_before_teardown`; the task's
  /// `completion_state` and
  /// `final_events`; `teardown_latency_ms`, from the call to the task's
  /// terminal state; `teardown_call_ms`, until the call returned; and the
  /// normal synthesis as `after_teardown`.
  Future<Map<String, Object?>> executeTeardown({required bool dispose});

  /// Cancels [speechDecodeCancelOverheadRuns] syntheses capped at
  /// [speechDecodeCancelFrameCap] frames on hand-back, then one uncancelled
  /// capped synthesis as a warm-up, then
  /// [speechDecodeCancelReferenceRuns] uncancelled capped syntheses. After the
  /// first half of them, it runs one more, cancelled
  /// [speechDecodeCancelLeadFraction] of their shortest audio decode time
  /// after the progress event that reports the cap.
  ///
  /// Reports `frame_cap`; `uncapped_frames`, generated by the latest normal
  /// synthesis, or null; `overhead_probes`, each with its `completion_state`,
  /// `final_events` and `cancel_latency_ms`; `warm_up` and `references`, in
  /// run order, each with its `frames`, `truncated` and `decode_ms`, from that
  /// progress event to its terminal state; `references_before_cancel`; and,
  /// for the cancelled synthesis, `frames_before_cancel`,
  /// `cancel_after_decode_start_ms`, `cancel_in_flight`, `completion_state`,
  /// `final_events` and `cancel_latency_ms`. It stops early, reporting what it
  /// measured, when the cap would not truncate or the warm-up or a reference
  /// has no `decode_ms`.
  Future<Map<String, Object?>> executeDecodeCancel();
}

/// Opt-in speech-to-text checks for transcripts that reach a token limit;
/// adapters without it keep their existing check count.
abstract interface class SpeechTranscriptLimitAdapter {
  /// Recognizes audio whose transcript cannot fit [limit], then runs a normal
  /// recognition on the same engine.
  ///
  /// Reports `max_output_tokens`, `reference`, `reference_repeats`,
  /// `completion_state`, any `truncated_limit` and `partial_transcript` from
  /// `LlamaSpeechTranscriptTruncatedException`, and the normal recognition as
  /// `after_truncation`. At [LlamaSpeechTranscriptLimit.maxOutputTokens] it
  /// also reports `transcript_tokens`, the token count of the latest complete
  /// transcript; at [LlamaSpeechTranscriptLimit.contextSize], the loaded
  /// `context_size`. [LlamaSpeechTranscriptLimit.runtime] is a reported cause
  /// with no specified budget, so it cannot be requested as a fixture.
  Future<Map<String, Object?>> executeTranscriptLimit(
    LlamaSpeechTranscriptLimit limit,
  );
}

const _maxOutputTokens = 512;

/// Public GGUF speech adapter used by the portable speech runner.
class PublicSpeechValidationAdapter
    implements
        SpeechValidationAdapter,
        SpeechEdgeCaseAdapter,
        SpeechSynthesisInterruptAdapter,
        SpeechTranscriptLimitAdapter {
  PublicSpeechValidationAdapter({
    required this.model,
    required this.projector,
    required this.backend,
    required this.pack,
    required this.saveAudio,
    this.audio,
    this.audioSeconds,
    this.audioPath,
    this.reference,
    this.text = 'Hello from llamadart. The answer is forty two.',
    LlamaEngine Function()? createEngine,
    Stopwatch Function() newStopwatch = Stopwatch.new,
  }) : _createEngine = createEngine ?? (() => LlamaEngine(LlamaBackend())),
       _newStopwatch = newStopwatch;

  final String model;
  final String projector;
  final GpuBackend backend;
  final String pack;
  final Uint8List? audio;
  final double? audioSeconds;
  final String? audioPath;
  final String? reference;
  final String text;
  final Future<void> Function(Uint8List) saveAudio;
  final LlamaEngine Function() _createEngine;

  /// Creates every stopwatch this adapter times with; tests pass one that
  /// reads fake time.
  final Stopwatch Function() _newStopwatch;
  LlamaEngine? _engine;
  double? _lastGenerationMs;
  String? _lastTranscript;
  int? _lastFramesGenerated;
  int? _lastProgressEvents;

  /// Public diagnostics are selector hints, not accelerator execution proof.
  Map<String, Object?> observedRuntime = {};

  @override
  Future<void> load() => _load(contextSize: 4096);

  Future<void> _load({required int contextSize}) async {
    if (!['stt', 'tts'].contains(pack)) {
      throw ArgumentError('Unknown speech pack');
    }
    if (pack == 'stt' &&
        (audio == null ||
            reference == null ||
            audioSeconds == null ||
            !audioSeconds!.isFinite ||
            audioSeconds! <= 0)) {
      throw ArgumentError(
        'STT requires audio, transcript and measured duration',
      );
    }
    await _loadInto(_engine = _createEngine(), contextSize: contextSize);
  }

  Future<void> _loadInto(LlamaEngine engine, {int contextSize = 4096}) async {
    await LlamaLogging.configure(level: LlamaLogLevel.info);
    await engine.setModel(
      LlamaModel(
        ModelSource.path(model),
        projector: ModelSource.path(projector),
      ),
      params: ModelParams(
        contextSize: contextSize,
        preferredBackend: backend,
        gpuLayers: backend == GpuBackend.cpu ? 0 : 99,
      ),
    );
    observedRuntime = {
      'backend_name': await engine.getBackendName(),
      'resolved_gpu_layers': await engine.getResolvedGpuLayers(),
    };
  }

  @override
  Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    await engine?.dispose();
  }

  @override
  Future<Map<String, Object?>> executeEdge(SpeechEdgeFixture fixture) async {
    if (pack != 'stt') {
      throw StateError('Speech edge fixtures require the STT pack');
    }
    final engine = _engine ?? (throw StateError('Speech engine is not loaded'));
    final measured = <String, Object?>{
      'contract': fixture.contract.name,
      'rationale': fixture.rationale,
      'fixture_bytes': fixture.bytes.length,
      'sample_rate_hz': fixture.sampleRateHz,
      'channels': fixture.channelCount,
      'audio_seconds': fixture.seconds,
    };
    final recognizer = SpeechToTextEngine.attach(
      engine,
      adapter: const Qwen3AsrAdapter(),
    );
    final watch = _newStopwatch()..start();
    final String transcript;
    try {
      final task = await recognizer.transcribe(
        SpeechToTextRequest(
          audio: SpeechAudioBytesInput(
            fixture.bytes,
            format: const SpeechAudioFormat(encoding: 'wav'),
          ),
          maxOutputTokens: _maxOutputTokens,
        ),
      );
      final events = await task.events.toList();
      final result = await task.result;
      if (events.whereType<SpeechToTextFinalEvent>().length != 1) {
        throw StateError('Edge fixture did not emit one completed result');
      }
      transcript = result.text;
    } on LlamaSpeechException catch (error) {
      return {
        ...measured,
        'rejected_with': '${error.runtimeType}',
        'message': redactDiagnostic(error.message),
        'elapsed_ms': watch.elapsedMicroseconds / 1000,
        'predicate_passed': speechEdgeRejectionHolds(
          fixture,
          message: error.message,
          isAudioFormat: error is LlamaAudioFormatException,
        ),
      };
    }
    final expected = List.filled(
      fixture.referenceRepeats < 1 ? 1 : fixture.referenceRepeats,
      reference!,
    ).join(' ');
    final wer = speechWordErrorRate(expected, transcript);
    return {
      ...measured,
      'transcript': transcript,
      'reference_repeats': fixture.referenceRepeats,
      'wer': wer,
      'elapsed_ms': watch.elapsedMicroseconds / 1000,
      'predicate_passed': speechEdgeTranscriptHolds(fixture, wer),
    };
  }

  /// Dart timers can fire slightly before the stopwatch reaches their target,
  /// so a lead measured on [watch] is completed by re-arming.
  Future<void> _finishWaitingUntil(
    Stopwatch watch,
    int targetMicroseconds,
  ) async {
    while (watch.elapsedMicroseconds < targetMicroseconds) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  Future<Map<String, Object?>> _cancelTask(
    Stopwatch watch,
    Stopwatch cancelWatch,
    Future<Object?> done,
    void Function() cancelTask, {
    required bool immediately,
    Map<String, Object?> Function()? landing,
  }) async {
    if (immediately) {
      final afterMs = watch.elapsedMicroseconds / 1000;
      cancelWatch.start();
      cancelTask();
      return {'cancel_after_ms': afterMs, 'cancel_immediate': true};
    }
    final reference = _lastGenerationMs;
    if (reference == null) {
      throw StateError('No measured generation to cancel into');
    }
    var settled = false;
    unawaited(
      done.then<void>(
        (_) => settled = true,
        onError: (Object _) => settled = true,
      ),
    );
    final leadMicroseconds =
        (reference * speechCancelInFlightLeadFraction * 1000).ceil();
    await Future<void>.delayed(Duration(microseconds: leadMicroseconds));
    await _finishWaitingUntil(watch, leadMicroseconds);
    final afterMs = watch.elapsedMicroseconds / 1000;
    final inFlight = !settled;
    final landed = landing?.call();
    cancelWatch.start();
    cancelTask();
    return {
      'cancel_after_ms': afterMs,
      'cancel_in_flight': inFlight,
      'reference_generation_ms': reference,
      ...?landed,
    };
  }

  @override
  Future<Map<String, Object?>> execute({
    bool cancel = false,
    bool cancelImmediately = false,
    bool invalid = false,
    bool bytesInput = false,
  }) async {
    if (cancel && cancelImmediately) {
      throw ArgumentError('cancel and cancelImmediately are exclusive');
    }
    final engine = _engine ?? (throw StateError('Speech engine is not loaded'));
    final watch = _newStopwatch()..start();
    if (pack == 'stt') {
      final recognizer = SpeechToTextEngine.attach(
        engine,
        adapter: const Qwen3AsrAdapter(),
      );
      final capability = await recognizer.capabilities;
      if (!capability.isSupported) {
        throw StateError(capability.unsupportedReason ?? 'Speech unsupported');
      }
      final task = await recognizer.transcribe(
        SpeechToTextRequest(
          audio: !invalid && !bytesInput && audioPath != null
              ? SpeechAudioFileInput(audioPath!)
              : SpeechAudioBytesInput(
                  invalid ? Uint8List(0) : audio!,
                  format: const SpeechAudioFormat(encoding: 'wav'),
                ),
          maxOutputTokens: _maxOutputTokens,
        ),
      );
      final cancelWatch = _newStopwatch();
      final cancellation = cancel || cancelImmediately
          ? await _cancelTask(
              watch,
              cancelWatch,
              task.done,
              task.cancel,
              immediately: cancelImmediately,
            )
          : null;
      final events = await task.events.toList();
      final completion = await task.done;
      if (completion.state == SpeechToTextCompletionState.failed) {
        throw completion.error!;
      }
      if (cancellation != null) {
        cancelWatch.stop();
        if (completion.state != SpeechToTextCompletionState.cancelled ||
            events.whereType<SpeechToTextFinalEvent>().isNotEmpty) {
          throw StateError('STT cancellation emitted a final result');
        }
        return {
          'cancelled': true,
          'cancel_latency_ms': cancelWatch.elapsedMicroseconds / 1000,
          ...cancellation,
        };
      }
      if (completion.state != SpeechToTextCompletionState.completed ||
          events.whereType<SpeechToTextFinalEvent>().length != 1) {
        throw StateError('STT did not emit exactly one completed result');
      }
      final transcript = _lastTranscript = completion.result!.text;
      final wer = speechWordErrorRate(reference!, transcript);
      final elapsedMs = _lastGenerationMs = watch.elapsedMicroseconds / 1000;
      return {
        'transcript': transcript,
        'reference': reference,
        'wer': wer,
        'predicate_passed': wer == 0,
        'elapsed_ms': elapsedMs,
        'audio_seconds': audioSeconds,
        'real_time_factor': watch.elapsedMicroseconds / 1e6 / audioSeconds!,
        'first_partial_ms': null,
        'streaming_input': false,
      };
    }
    final synthesizer = TextToSpeechEngine.attach(
      engine,
      adapter: const Qwen3TtsAdapter(),
    );
    final capability = await synthesizer.capabilities;
    if (!capability.isSupported) {
      throw StateError(capability.unsupportedReason ?? 'Speech unsupported');
    }
    final task = await synthesizer.synthesize(
      _synthesisRequest(text: invalid ? '' : text),
    );
    final cancelWatch = _newStopwatch();
    double? firstAudioMs;
    double? lastProgressMs;
    var finals = 0;
    var progressEvents = 0;
    final drained = Completer<void>()..future.ignore();
    task.events.listen(
      (event) {
        if (event is TextToSpeechProgressEvent) {
          progressEvents++;
          lastProgressMs = watch.elapsedMicroseconds / 1000;
        } else if (event is TextToSpeechFinalEvent) {
          firstAudioMs ??= watch.elapsedMicroseconds / 1000;
          finals++;
        }
      },
      onError: drained.completeError,
      onDone: drained.complete,
    );
    final cancellation = cancel || cancelImmediately
        ? await _cancelTask(
            watch,
            cancelWatch,
            task.done,
            task.cancel,
            immediately: cancelImmediately,
            landing: () {
              final lastMs = lastProgressMs;
              final referenceEvents = _lastProgressEvents;
              return {
                'progress_events_before_cancel': progressEvents,
                'ms_since_last_progress_at_cancel': lastMs == null
                    ? null
                    : watch.elapsedMicroseconds / 1000 - lastMs,
                'reference_progress_events': referenceEvents,
                'cancel_after_reference_last_progress': referenceEvents == null
                    ? null
                    : progressEvents >= referenceEvents,
              };
            },
          )
        : null;
    await drained.future;
    final completion = await task.done;
    if (completion.state == TextToSpeechCompletionState.failed) {
      throw completion.error!;
    }
    if (cancellation != null) {
      cancelWatch.stop();
      if (completion.state != TextToSpeechCompletionState.cancelled ||
          finals != 0) {
        throw StateError('TTS cancellation emitted a final result');
      }
      return {
        'cancelled': true,
        'cancel_latency_ms': cancelWatch.elapsedMicroseconds / 1000,
        ...cancellation,
      };
    }
    if (completion.state != TextToSpeechCompletionState.completed ||
        finals != 1) {
      throw StateError('TTS did not emit exactly one completed result');
    }
    watch.stop();
    _lastGenerationMs = watch.elapsedMicroseconds / 1000;
    final result = completion.result!;
    _lastFramesGenerated = result.framesGenerated;
    _lastProgressEvents = progressEvents;
    final metrics = inspectSpeechAudio(result);
    await saveAudio(result.toWavBytes());
    return {
      ...metrics,
      'predicate_passed': true,
      'elapsed_ms': watch.elapsedMicroseconds / 1000,
      'first_playable_audio_ms': firstAudioMs,
      'real_time_factor':
          watch.elapsedMicroseconds /
          1e6 /
          (metrics['audio_seconds'] as double),
      'streaming_audio': false,
    };
  }

  TextToSpeechRequest _synthesisRequest({String? text, int maxFrames = 384}) =>
      TextToSpeechRequest(
        text: text ?? this.text,
        language: 'English',
        maxFrames: maxFrames,
        seed: 1,
      );

  Future<TextToSpeechTask> _synthesize({int maxFrames = 384}) async {
    if (pack != 'tts') {
      throw StateError('Synthesis interrupts require the TTS pack');
    }
    final engine = _engine ?? (throw StateError('Speech engine is not loaded'));
    return TextToSpeechEngine.attach(
      engine,
      adapter: const Qwen3TtsAdapter(),
    ).synthesize(_synthesisRequest(maxFrames: maxFrames));
  }

  @override
  Future<Map<String, Object?>> executeTeardown({required bool dispose}) async {
    final task = await _synthesize();
    final engine = _engine!;
    final firstFrame = Completer<int>();
    final drained = Completer<void>();
    var finals = 0;
    final events = task.events.listen((event) {
      if (event is TextToSpeechProgressEvent &&
          event.framesGenerated > 0 &&
          !firstFrame.isCompleted) {
        firstFrame.complete(event.framesGenerated);
      }
      if (event is TextToSpeechFinalEvent) finals++;
    }, onDone: drained.complete);
    var settled = false;
    final done = task.done.whenComplete(() => settled = true);
    final frames = await Future.any([firstFrame.future, done.then((_) => 0)]);
    final inFlight = !settled && frames > 0;
    final watch = _newStopwatch()..start();
    if (dispose) _engine = null;
    final teardown = (dispose ? engine.dispose() : engine.unloadModel()).then(
      (_) => watch.elapsedMicroseconds / 1000,
    );
    final completion = await done;
    final latencyMs = watch.elapsedMicroseconds / 1000;
    final callMs = await teardown;
    await drained.future;
    await events.cancel();
    if (dispose) {
      await load();
    } else {
      await _loadInto(engine);
    }
    return {
      'teardown': dispose ? 'dispose' : 'unload',
      'in_flight': inFlight,
      'frames_before_teardown': frames,
      'completion_state': completion.state.name,
      'final_events': finals,
      'teardown_latency_ms': latencyMs,
      'teardown_call_ms': callMs,
      'after_teardown': await execute(),
    };
  }

  @override
  Future<Map<String, Object?>> executeDecodeCancel() async {
    final uncapped = _lastFramesGenerated;
    final measured = <String, Object?>{
      'frame_cap': speechDecodeCancelFrameCap,
      'uncapped_frames': uncapped,
    };
    if (uncapped == null || uncapped <= speechDecodeCancelFrameCap) {
      return measured;
    }
    final probes = measured['overhead_probes'] = <Map<String, Object?>>[];
    for (var run = 0; run < speechDecodeCancelOverheadRuns; run++) {
      final task = await _synthesize(maxFrames: speechDecodeCancelFrameCap);
      final events = task.events.toList();
      final watch = _newStopwatch()..start();
      task.cancel();
      final completion = await task.done;
      final latencyMs = watch.elapsedMicroseconds / 1000;
      probes.add({
        'completion_state': completion.state.name,
        'final_events': (await events)
            .whereType<TextToSpeechFinalEvent>()
            .length,
        'cancel_latency_ms': latencyMs,
      });
    }
    Future<Map<String, Object?>> timedDecode() async {
      final run = await _cappedSynthesis();
      final capMs = run.capEventMs;
      return {
        'frames': run.completion.result?.framesGenerated,
        'truncated': run.completion.result?.truncated,
        'decode_ms': capMs == null ? null : run.doneMs - capMs,
      };
    }

    final warmUp = measured['warm_up'] = await timedDecode();
    if (warmUp['decode_ms'] == null) return measured;
    final references = measured['references'] = <Map<String, Object?>>[];
    Future<bool> reference() async {
      final decode = await timedDecode();
      references.add(decode);
      return decode['decode_ms'] != null;
    }

    const before = speechDecodeCancelReferenceRuns ~/ 2;
    measured['references_before_cancel'] = before;
    for (var run = 0; run < before; run++) {
      if (!await reference()) return measured;
    }
    final decodeMs = references
        .map((reference) => reference['decode_ms']! as double)
        .reduce(math.min);
    final cancelled = await _cappedSynthesis(
      cancelLeadMs: decodeMs * speechDecodeCancelLeadFraction,
    );
    for (var run = before; run < speechDecodeCancelReferenceRuns; run++) {
      if (!await reference()) break;
    }
    final capMs = cancelled.capEventMs;
    final cancelMs = cancelled.cancelAtMs;
    return {
      ...measured,
      'frames_before_cancel': cancelled.capFrames,
      'cancel_after_decode_start_ms': capMs == null || cancelMs == null
          ? null
          : cancelMs - capMs,
      'cancel_in_flight': cancelled.inFlight,
      'completion_state': cancelled.completion.state.name,
      'final_events': cancelled.finals,
      'cancel_latency_ms': cancelMs == null
          ? null
          : cancelled.doneMs - cancelMs,
    };
  }

  Future<
    ({
      double? capEventMs,
      int? capFrames,
      double? cancelAtMs,
      bool inFlight,
      double doneMs,
      TextToSpeechCompletion completion,
      int finals,
    })
  >
  _cappedSynthesis({double? cancelLeadMs}) async {
    final watch = _newStopwatch()..start();
    final task = await _synthesize(maxFrames: speechDecodeCancelFrameCap);
    var settled = false;
    final done = task.done.whenComplete(() => settled = true);
    double? capEventMs;
    int? capFrames;
    double? cancelAtMs;
    var inFlight = false;
    var finals = 0;
    Timer? timer;
    var finished = false;
    await for (final event in task.events) {
      if (event is TextToSpeechProgressEvent &&
          capEventMs == null &&
          event.framesGenerated >= speechDecodeCancelFrameCap) {
        final capMicroseconds = watch.elapsedMicroseconds;
        capEventMs = capMicroseconds / 1000;
        capFrames = event.framesGenerated;
        if (cancelLeadMs != null) {
          final leadMicroseconds = (cancelLeadMs * 1000).ceil();
          timer = Timer(Duration(microseconds: leadMicroseconds), () async {
            await _finishWaitingUntil(
              watch,
              capMicroseconds + leadMicroseconds,
            );
            if (finished) return;
            cancelAtMs = watch.elapsedMicroseconds / 1000;
            inFlight = !settled;
            task.cancel();
          });
        }
      }
      if (event is TextToSpeechFinalEvent) finals++;
    }
    final completion = await done;
    final doneMs = watch.elapsedMicroseconds / 1000;
    finished = true;
    timer?.cancel();
    return (
      capEventMs: capEventMs,
      capFrames: capFrames,
      cancelAtMs: cancelAtMs,
      inFlight: inFlight,
      doneMs: doneMs,
      completion: completion,
      finals: finals,
    );
  }

  @override
  Future<Map<String, Object?>> executeTranscriptLimit(
    LlamaSpeechTranscriptLimit limit,
  ) async {
    if (pack != 'stt') {
      throw StateError('Transcript limit checks require the STT pack');
    }
    switch (limit) {
      case LlamaSpeechTranscriptLimit.runtime:
        throw LlamaUnsupportedException(
          'An unspecified runtime transcript limit cannot be requested. '
          'Choose maxOutputTokens or contextSize to exercise a known budget.',
        );
      case LlamaSpeechTranscriptLimit.maxOutputTokens:
        final engine =
            _engine ?? (throw StateError('Speech engine is not loaded'));
        final transcript =
            _lastTranscript ??
            (throw StateError('No complete transcript to truncate'));
        final referenceTokens = (await engine.tokenize(
          reference!,
          addSpecial: false,
        )).length;
        final transcriptTokens = (await engine.tokenize(
          transcript,
          addSpecial: false,
        )).length;
        return {
          'reference_tokens': referenceTokens,
          'transcript_tokens': transcriptTokens,
          ...await _recognizeToLimit(
            engine,
            audio!,
            maxOutputTokens: (referenceTokens * speechTruncationTokenFraction)
                .floor(),
            repeats: 1,
          ),
          'after_truncation': await execute(),
        };
      case LlamaSpeechTranscriptLimit.contextSize:
        final long = buildSpeechEdgeFixtures(
          audio!,
        ).singleWhere((fixture) => fixture.id == 'edge_long_boundary');
        await dispose();
        await _load(contextSize: speechTruncationContextSize);
        final engine = _engine!;
        final measured = {
          'context_size': await engine.getContextSize(),
          ...await _recognizeToLimit(
            engine,
            long.bytes,
            maxOutputTokens: _maxOutputTokens,
            repeats: long.referenceRepeats,
          ),
          'after_truncation': await execute(),
        };
        await dispose();
        await load();
        return measured;
    }
  }

  Future<Map<String, Object?>> _recognizeToLimit(
    LlamaEngine engine,
    Uint8List wav, {
    required int maxOutputTokens,
    required int repeats,
  }) async {
    final watch = _newStopwatch()..start();
    final recognizer = SpeechToTextEngine.attach(
      engine,
      adapter: const Qwen3AsrAdapter(),
    );
    final task = await recognizer.transcribe(
      SpeechToTextRequest(
        audio: SpeechAudioBytesInput(
          wav,
          format: const SpeechAudioFormat(encoding: 'wav'),
        ),
        maxOutputTokens: maxOutputTokens,
      ),
    );
    await task.events.drain<void>();
    final completion = await task.done;
    final error = completion.error;
    return {
      'max_output_tokens': maxOutputTokens,
      'reference': reference,
      'reference_repeats': repeats,
      'completion_state': completion.state.name,
      if (completion.result != null)
        'completed_transcript': completion.result!.text,
      if (error != null) 'rejected_with': '${error.runtimeType}',
      if (error is LlamaSpeechTranscriptTruncatedException) ...{
        'truncated_limit': error.limit.name,
        'partial_transcript': error.partialTranscript,
      } else if (error != null)
        'message': redactDiagnostic(error.message),
      'elapsed_ms': watch.elapsedMicroseconds / 1000,
    };
  }
}

/// Lifecycle checks every [runSpeechValidation] run executes.
const speechLifecycleCheckCount = 21;

/// Cleanup cycles that run before the `leak_slope_bound` window starts.
///
/// With `reload`, they cover the first two reloads, which took the largest
/// host resident step in six of nine Linux CUDA `tts` runs (#686).
const speechLeakWarmupCycles = 1;

/// Cleanup cycles after the warm-up whose footprints, with the last warm-up
/// cycle's, `leak_slope_bound` fits its slope to.
const speechLeakWindowCycles = 7;

/// Cancel/dispose/load/generate cycles run after the single-shot checks.
const speechCleanupCycles = speechLeakWarmupCycles + speechLeakWindowCycles;

/// Least-squares footprint slope per cycle above which `leak_slope_bound`
/// fails. A slope equal to it passes.
///
/// Half the smallest per-cycle resident set growth of the LiteRT ASR leak in
/// #634, 14.0 MiB over 12 warm cycles on macOS arm64.
const speechLeakCycleGrowthBytes = 7 * 1024 * 1024;

/// How long [PublicSpeechValidationAdapter] waits before cancelling with
/// `cancel`, as a fraction of the elapsed time of its most recent completed
/// generation. Its `cancel_after_ms` is never below that fraction, even when
/// timers fire early.
///
/// [PublicDedicatedSpeechAdapter] does not use it: that adapter pushes PCM
/// until the first partial transcript arrives, or until the fixture is
/// exhausted, and cancels there.
const speechCancelInFlightLeadFraction = 0.5;

/// Milliseconds allowed from a `cancel` cancellation to the speech task's
/// terminal state.
///
/// It bounds when the task becomes terminal to its caller, not when native
/// work stops, so a cancellation honoured only after the generation finishes
/// can still pass it.
const speechCancelLatencyBudgetMs = 500.0;

/// Milliseconds allowed from a `cancelImmediately` cancellation to the speech
/// task's terminal state.
///
/// As with [speechCancelLatencyBudgetMs], a cancellation honoured only after
/// the generation finishes can still pass it.
const speechImmediateCancelLatencyBudgetMs = 500.0;

/// Ceiling on the largest memory footprint sampled after the checks between
/// `generate` and `peak_memory_bound`, as a multiple of the footprint sampled
/// right after `generate`. Growth equal to it passes.
///
/// Every check in that span contributes a sample, whatever phase it exercised,
/// so the peak is the maximum over heterogeneous phases rather than over
/// generations alone.
///
/// `interrupt_memory_bound` applies the same ceiling to the samples after
/// the interrupt checks, as a multiple of the one sampled after
/// `leak_slope_bound`. Neither is applied where [speechPeakRatioExemption]
/// names a reason.
const speechPeakFootprintGrowthBudget = 1.10;

/// Checks a run with `checkSynthesisInterrupts` adds.
const speechSynthesisInterruptCheckCount = 4;

const _memoryBoundIds = {
  'peak_memory_bound',
  'leak_slope_bound',
  'interrupt_memory_bound',
};

/// Checks a run with `checkTranscriptLimits` adds.
const speechTranscriptLimitCheckCount = 2;

/// Frame cap of every synthesis behind `decode_cancel`. When the uncapped
/// synthesis runs longer, the progress event that reports this many frames is
/// the last one before the audio decode.
const speechDecodeCancelFrameCap = 12;

/// Capped syntheses `decode_cancel` cancels on hand-back to measure the fixed
/// cost of a cancellation; the largest latency among them is the overhead.
const speechDecodeCancelOverheadRuns = 3;

/// Uncancelled capped syntheses `decode_cancel` times, half before the
/// cancelled synthesis and half after it, so that drift in load between them
/// widens the measured noise. An untimed one runs first: the first decode
/// after the hand-back cancellations is often the slowest (#759).
const speechDecodeCancelReferenceRuns = 8;

/// How far into the audio decode `decode_cancel` cancels, as a fraction of the
/// shortest decode time among the references run before it.
///
/// On CUDA about half of that time is a tail after the native decode that a
/// cancellation cannot skip. Once the decode graph runs it stops within a few
/// milliseconds of the cancel, so an early lead leaves more to save (#759).
const speechDecodeCancelLeadFraction = 0.1;

/// `decode_cancel` margin as a multiple of the spread, longest minus
/// shortest, of all reference decode times.
///
/// With [speechDecodeCancelReferenceRuns] references, a cancellation that
/// saves nothing passes no more often than it did at twice the spread of four
/// references, for Gaussian, one-sided stall, mixed and heavy-tailed noise
/// (#759).
const speechDecodeCancelNoiseMultiple = 0.9;

/// Smallest `decode_cancel` margin, as a fraction of the shortest reference
/// decode time. It covers references that happen to agree closely and the
/// work a cancelled synthesis skips after its native call returns.
const speechDecodeCancelMarginFloorFraction = 0.1;

/// `maxOutputTokens` for `max_output_tokens_truncation`, as a fraction of the
/// locked reference transcript's token count, rounded down.
const speechTruncationTokenFraction = 0.5;

/// Context size loaded for `context_size_truncation`.
const speechTruncationContextSize = 512;

const _cancelLandingKeys = [
  'progress_events_before_cancel',
  'ms_since_last_progress_at_cancel',
  'reference_progress_events',
  'cancel_after_reference_last_progress',
];

Map<String, Object?> _landingFields(Map<String, Object?> cancelled) => {
  for (final key in _cancelLandingKeys)
    if (cancelled.containsKey(key)) key: cancelled[key],
};

Map<String, Object?> _teardownOutcome(Map<String, Object?> result) {
  final frames = result['frames_before_teardown'];
  if (result['in_flight'] != true || frames is! int || frames < 1) {
    throw StateError('Synthesis was not in flight at teardown');
  }
  if (result['completion_state'] != 'cancelled' ||
      result['final_events'] != 0) {
    throw StateError('Teardown did not cancel the synthesis');
  }
  final latency = result['teardown_latency_ms'];
  if (latency is! num || !latency.isFinite || latency < 0) {
    throw StateError('Teardown latency was not measured');
  }
  final after = result['after_teardown'];
  return {
    ...result,
    'budget_ms': speechCancelLatencyBudgetMs,
    'predicate_passed':
        latency <= speechCancelLatencyBudgetMs &&
        after is Map &&
        after['predicate_passed'] == true,
  };
}

bool _finiteNonNegative(Object? value) =>
    value is num && value.isFinite && value >= 0;

Map<String, Object?> _decodeCancelOutcome(Map<String, Object?> result) {
  Map<String, Object?> notRun(
    String reason, [
    Map<String, Object?> derived = const {},
  ]) => {...result, ...derived, 'not_run_reason': reason};
  final cap = result['frame_cap'];
  final uncapped = result['uncapped_frames'];
  if (cap != speechDecodeCancelFrameCap ||
      uncapped is! int ||
      uncapped <= speechDecodeCancelFrameCap) {
    return notRun('The frame cap does not truncate the synthesis');
  }
  final probes = result['overhead_probes'];
  if (probes is! List ||
      probes.length != speechDecodeCancelOverheadRuns ||
      probes.any(
        (probe) =>
            probe is! Map ||
            probe['completion_state'] != 'cancelled' ||
            probe['final_events'] != 0 ||
            !_finiteNonNegative(probe['cancel_latency_ms']),
      )) {
    return notRun('A hand-back cancellation did not measure the overhead');
  }
  final warmUp = result['warm_up'];
  if (warmUp is! Map ||
      warmUp['frames'] != cap ||
      warmUp['truncated'] != true ||
      !_finiteNonNegative(warmUp['decode_ms'])) {
    return notRun('The warm-up synthesis did not stop at the frame cap');
  }
  final references = result['references'];
  const before = speechDecodeCancelReferenceRuns ~/ 2;
  if (references is! List ||
      references.length != speechDecodeCancelReferenceRuns ||
      result['references_before_cancel'] != before ||
      references.any(
        (reference) =>
            reference is! Map ||
            reference['frames'] != cap ||
            reference['truncated'] != true ||
            reference['decode_ms'] is! num ||
            !(reference['decode_ms'] as num).isFinite ||
            (reference['decode_ms'] as num) <= 0,
      )) {
    return notRun('A reference synthesis did not stop at the frame cap');
  }
  final decodes = [
    for (final reference in references)
      ((reference as Map)['decode_ms'] as num).toDouble(),
  ];
  final lead = result['cancel_after_decode_start_ms'];
  if (lead is! num ||
      !lead.isFinite ||
      lead <
          decodes.take(before).reduce(math.min) *
              speechDecodeCancelLeadFraction) {
    return notRun('The cancellation was not issued at its lead');
  }
  if (result['frames_before_cancel'] != cap ||
      result['cancel_in_flight'] != true) {
    return notRun('Cancellation did not reach a decoding synthesis');
  }
  final latency = result['cancel_latency_ms'];
  if (!_finiteNonNegative(latency)) {
    return notRun('Cancellation latency was not measured');
  }
  final shortest = decodes.reduce(math.min);
  final spread = decodes.reduce(math.max) - shortest;
  final overhead = probes
      .map((probe) => ((probe as Map)['cancel_latency_ms'] as num).toDouble())
      .reduce(math.max);
  final margin = math.max(
    spread * speechDecodeCancelNoiseMultiple,
    shortest * speechDecodeCancelMarginFloorFraction,
  );
  final remaining = shortest - lead;
  final end = lead + (latency as num);
  final derived = {
    'lead_fraction': speechDecodeCancelLeadFraction,
    'noise_multiple': speechDecodeCancelNoiseMultiple,
    'margin_floor_fraction': speechDecodeCancelMarginFloorFraction,
    'reference_decode_ms': shortest,
    'reference_spread_ms': spread,
    'margin_ms': margin,
    'cancel_overhead_ms': overhead,
    'reference_remainder_ms': remaining,
    'cancel_end_ms': end,
    'saved_ms': shortest - end,
  };
  if (result['completion_state'] != 'cancelled' ||
      result['final_events'] != 0) {
    return {
      ...result,
      ...derived,
      'failure_reason': 'Decode cancellation emitted a final result',
      'predicate_passed': false,
    };
  }
  if (remaining - overhead <= margin) {
    return notRun(
      'The reference decode left after the cancellation, less the overhead, '
      'is within the margin',
      derived,
    );
  }
  return {...result, ...derived, 'predicate_passed': shortest - end > margin};
}

Map<String, Object?> _truncationOutcome(
  Map<String, Object?> result,
  LlamaSpeechTranscriptLimit limit,
) {
  final maxTokens = result['max_output_tokens'];
  switch (limit) {
    case LlamaSpeechTranscriptLimit.runtime:
      throw StateError(
        'An unspecified runtime limit cannot qualify a requested budget.',
      );
    case LlamaSpeechTranscriptLimit.maxOutputTokens:
      final needed = result['transcript_tokens'];
      if (maxTokens is! int ||
          maxTokens < 1 ||
          needed is! int ||
          needed <= maxTokens) {
        throw StateError('The complete transcript fits in maxOutputTokens');
      }
    case LlamaSpeechTranscriptLimit.contextSize:
      final contextSize = result['context_size'];
      if (contextSize != speechTruncationContextSize ||
          maxTokens is! int ||
          maxTokens < speechTruncationContextSize) {
        throw StateError(
          'The context size differs, or maxOutputTokens can stop first',
        );
      }
  }
  if (result['truncated_limit'] != limit.name) {
    throw StateError(
      'Recognition did not fail with '
      'LlamaSpeechTranscriptTruncatedException at ${limit.name}; '
      'reported ${result['truncated_limit'] ?? 'none'}.',
    );
  }
  final reference = result['reference'];
  final repeats = result['reference_repeats'];
  final partial = result['partial_transcript'];
  if (reference is! String || repeats is! int || repeats < 1) {
    throw StateError('The truncated recognition has no reference');
  }
  final after = result['after_truncation'];
  return {
    ...result,
    'predicate_passed':
        partial is String &&
        speechTranscriptPrefixHolds(
          List.filled(repeats, reference).join(' '),
          partial,
        ) &&
        after is Map &&
        after['predicate_passed'] == true,
  };
}

/// Least-squares slope of [samples] against their index, in sample units per
/// index. [samples] needs at least two values.
double leastSquaresSlope(List<int> samples) {
  final n = samples.length;
  final xMean = (n - 1) / 2;
  final yMean = samples.reduce((a, b) => a + b) / n;
  var covariance = 0.0;
  var variance = 0.0;
  for (var i = 0; i < n; i++) {
    covariance += (i - xMean) * (samples[i] - yMean);
    variance += (i - xMean) * (i - xMean);
  }
  return covariance / variance;
}

/// Why [speechPeakFootprintGrowthBudget] is not applied on [operatingSystem]
/// with [backend], or null when it is, including for any unknown or null pair.
///
/// Linux CUDA keeps the weights in device memory, so its resident set after
/// `generate` was only about 1.13 GB, and reload overhead that plateaued at
/// 1.13-1.16x failed the ratio without a leak (#686). `leak_slope_bound`
/// still applies there.
String? speechPeakRatioExemption({
  required String? operatingSystem,
  required String? backend,
}) => operatingSystem == 'linux' && backend == 'cuda'
    ? 'Peak ratio not applied: Linux CUDA keeps the weights in device memory, '
          'so the host baseline excludes them'
    : null;

/// Executes bounded speech lifecycle checks; cleanup failures remain failures.
///
/// [edgeFixtures] adds one check per synthetic fixture and requires an adapter
/// that also implements [SpeechEdgeCaseAdapter]. Runs that pass none keep their
/// previous check count.
///
/// [checkTranscriptLimits] adds `max_output_tokens_truncation` and
/// `context_size_truncation`, and requires a [SpeechTranscriptLimitAdapter].
/// Each passes only if recognition fails with
/// `LlamaSpeechTranscriptTruncatedException` at that limit, its partial
/// transcript is a strict prefix of the expected one, and the following
/// recognition passes.
///
/// [checkSynthesisInterrupts] adds `unload_during_synthesis`,
/// `dispose_during_synthesis`, `decode_cancel` and `interrupt_memory_bound`
/// after `leak_slope_bound`, and requires a
/// [SpeechSynthesisInterruptAdapter]. The first two pass only if the synthesis
/// ends cancelled within [speechCancelLatencyBudgetMs] of the call and the
/// synthesis after the reload passes. `decode_cancel` compares the cancelled
/// synthesis with the shortest reference decode, both from the progress event
/// that reports the cap. The margin is [speechDecodeCancelNoiseMultiple] times
/// the reference spread, and at least [speechDecodeCancelMarginFloorFraction]
/// of that decode. The check passes only if the cancelled synthesis ends more
/// than the margin before that decode. It records `NOT_RUN` with a
/// `not_run_reason` when a precondition fails or when the decode left after
/// the cancellation, less the largest hand-back cancellation latency, is
/// within the margin, since then even an immediate cancellation could not
/// pass. It fails if the cancelled synthesis emits a final result.
/// `interrupt_memory_bound` bounds the footprint after those three checks
/// by [speechPeakFootprintGrowthBudget] times the one sampled after
/// `leak_slope_bound`, so reload overhead the lifecycle checks already
/// incurred is in its baseline, and growth the interrupts add is not.
///
/// The single-shot checks and every cleanup cycle each call
/// [SpeechValidationAdapter.execute] once with `cancelImmediately`, which must
/// report `cancel_immediate` as true, and once with `cancel`, which must report
/// `cancel_in_flight` as true. Each must report `cancelled` as true and a
/// finite, non-negative `cancel_latency_ms` and `cancel_after_ms`, and the
/// second a nonzero `cancel_after_ms`; otherwise that check fails.
///
/// [footprintBytes] is called after each check. If any call made before a
/// memory bound, `peak_memory_bound`, `leak_slope_bound` or
/// `interrupt_memory_bound`, runs returns null, that bound records `SKIP` with
/// a reason. `peak_memory_bound` and `interrupt_memory_bound` also record
/// `SKIP` when [speechPeakRatioExemption] names a reason for
/// [operatingSystem] and [backend]. The memory bounds are the only checks that
/// may `SKIP` in a run whose `functional_pass` is true, and no check may
/// record `NOT_RUN` in one.
///
/// `leak_slope_bound` fails when the [leastSquaresSlope] of the footprints
/// sampled after cleanup cycle [speechLeakWarmupCycles] and the
/// [speechLeakWindowCycles] cycles after it exceeds
/// [speechLeakCycleGrowthBytes] per cycle.
///
/// The result deliberately cannot assert hardware or perceptual qualification.
Future<Map<String, Object?>> runSpeechValidation(
  SpeechValidationAdapter adapter, {
  bool checkBytes = false,
  List<SpeechEdgeFixture> edgeFixtures = const [],
  bool checkTranscriptLimits = false,
  bool checkSynthesisInterrupts = false,
  int? Function() footprintBytes = memoryFootprintBytes,
  String? operatingSystem,
  String? backend,
}) async {
  final ratioExemption = speechPeakRatioExemption(
    operatingSystem: operatingSystem,
    backend: backend,
  );
  if (edgeFixtures.isNotEmpty && adapter is! SpeechEdgeCaseAdapter) {
    throw ArgumentError('Adapter cannot execute speech edge fixtures');
  }
  if (checkTranscriptLimits && adapter is! SpeechTranscriptLimitAdapter) {
    throw ArgumentError('Adapter cannot execute transcript limit checks');
  }
  if (checkSynthesisInterrupts && adapter is! SpeechSynthesisInterruptAdapter) {
    throw ArgumentError('Adapter cannot interrupt a synthesis');
  }
  final expectedChecks =
      speechLifecycleCheckCount +
      (checkBytes ? 1 : 0) +
      edgeFixtures.length +
      (checkTranscriptLimits ? speechTranscriptLimitCheckCount : 0) +
      (checkSynthesisInterrupts ? speechSynthesisInterruptCheckCount : 0);
  final results = <Map<String, Object?>>[];
  final cancelLatencies = <double>[];
  final cancelLeads = <double>[];
  final immediateLatencies = <double>[];
  final immediateLeads = <double>[];
  final cancelProgressEvents = <int?>[];
  final cancelAfterReferenceLastProgress = <bool?>[];
  final footprintSamples = <Map<String, Object?>>[];
  var footprintMeasurable = true;
  final unmeasured = <String, Object?>{
    'skipped': true,
    'measurement': memoryFootprintSource,
    'skip_reason': 'Memory footprint was not measurable',
  };
  Future<void> check(
    String id,
    Future<Map<String, Object?>> Function() action,
  ) async {
    try {
      final result = await action();
      results.add({
        'id': id,
        'status': result['predicate_passed'] == false
            ? 'FAIL'
            : result['not_run_reason'] is String
            ? 'NOT_RUN'
            : result['skipped'] == true
            ? 'SKIP'
            : 'PASS',
        ...result,
      });
    } catch (error) {
      // Error classes are safe diagnostics; raw errors may contain local paths.
      results.add({
        'id': id,
        'status': 'FAIL',
        'error_type': '${error.runtimeType}',
        'message': redactDiagnostic('$error'),
      });
    }
    final sampled = footprintBytes();
    if (sampled == null) {
      footprintMeasurable = false;
    } else {
      footprintSamples.add({'id': id, 'footprint_bytes': sampled});
    }
  }

  Map<String, Object?> recordCancellation(
    Map<String, Object?> result, {
    bool immediate = false,
  }) {
    if (result['cancelled'] != true) {
      throw StateError('Cancellation not confirmed');
    }
    if (immediate && result['cancel_immediate'] != true) {
      throw StateError('Cancellation was not issued on hand-back');
    }
    if (!immediate && result['cancel_in_flight'] != true) {
      throw StateError('Cancellation did not reach a running generation');
    }
    final latency = result['cancel_latency_ms'];
    if (latency is! num || !latency.isFinite || latency < 0) {
      throw StateError('Cancellation latency was not measured');
    }
    final lead = result['cancel_after_ms'];
    if (lead is! num || !lead.isFinite || lead < 0 || !immediate && lead == 0) {
      throw StateError('Cancellation lead time was not measured');
    }
    (immediate ? immediateLatencies : cancelLatencies).add(latency.toDouble());
    (immediate ? immediateLeads : cancelLeads).add(lead.toDouble());
    if (!immediate) {
      cancelProgressEvents.add(result['progress_events_before_cancel'] as int?);
      cancelAfterReferenceLastProgress.add(
        result['cancel_after_reference_last_progress'] as bool?,
      );
    }
    return result;
  }

  Map<String, Object?> latencyBound(
    List<double> samples,
    List<double> leads,
    double budget,
  ) {
    if (samples.length != speechCleanupCycles + 1) {
      throw StateError('Cancellation latency samples are incomplete');
    }
    final worst = samples.reduce(math.max);
    return {
      'samples_ms': [...samples],
      'lead_ms': [...leads],
      'worst_ms': worst,
      'budget_ms': budget,
      'predicate_passed': worst <= budget,
    };
  }

  Map<String, Object?> memoryBound(String baselineId, String baselineName) {
    final baselineIndex = footprintSamples.indexWhere(
      (sample) => sample['id'] == baselineId,
    );
    if (!footprintMeasurable || baselineIndex < 0) return unmeasured;
    final baseline = footprintSamples[baselineIndex]['footprint_bytes']! as int;
    final later = footprintSamples.skip(baselineIndex + 1);
    if (later.isEmpty) {
      throw StateError('No footprint samples follow $baselineName');
    }
    final peak = later
        .map((sample) => sample['footprint_bytes']! as int)
        .reduce(math.max);
    return {
      'measurement': memoryFootprintSource,
      'baseline_check': baselineId,
      'baseline_footprint_bytes': baseline,
      'peak_footprint_bytes': peak,
      'peak_footprint_growth': peak / baseline,
      'growth_budget': speechPeakFootprintGrowthBudget,
      'samples': [...footprintSamples],
      if (ratioExemption != null) ...{
        'skipped': true,
        'skip_reason': ratioExemption,
      } else
        'predicate_passed': peak / baseline <= speechPeakFootprintGrowthBudget,
    };
  }

  try {
    await check('load', () async {
      await adapter.load();
      return {};
    });
    if (results.last['status'] == 'PASS') {
      await check('generate', () => adapter.execute());
      if (checkBytes) {
        await check('bytes_input', () => adapter.execute(bytesInput: true));
      }
      await check(
        'cancel_immediate',
        () async => recordCancellation(
          await adapter.execute(cancelImmediately: true),
          immediate: true,
        ),
      );
      await check(
        'cancel',
        () async => recordCancellation(await adapter.execute(cancel: true)),
      );
      await check('after_cancel', () => adapter.execute());
      await check('invalid_input', () async {
        try {
          await adapter.execute(invalid: true);
        } on ArgumentError {
          return {'rejected': true};
        } on LlamaAudioFormatException {
          return {'rejected': true};
        } on LlamaTextToSpeechException catch (error) {
          // This exception also represents synthesis failures. Only the exact
          // empty-text contract exercised by this case is an input rejection.
          if (error.message != 'Text to synthesize must not be empty.') rethrow;
          return {'rejected': true};
        } on LlamaUnsupportedException {
          return {'rejected': true};
        }
        throw StateError('Invalid input did not produce a typed rejection');
      });
      await check('after_invalid', () => adapter.execute());
      for (final fixture in edgeFixtures) {
        await check(
          fixture.id,
          () => (adapter as SpeechEdgeCaseAdapter).executeEdge(fixture),
        );
      }
      if (checkTranscriptLimits) {
        final limits = adapter as SpeechTranscriptLimitAdapter;
        for (final (limit, id) in const [
          (
            LlamaSpeechTranscriptLimit.maxOutputTokens,
            'max_output_tokens_truncation',
          ),
          (LlamaSpeechTranscriptLimit.contextSize, 'context_size_truncation'),
        ]) {
          await check(
            id,
            () async => _truncationOutcome(
              await limits.executeTranscriptLimit(limit),
              limit,
            ),
          );
        }
      }
      await check('reload', () async {
        await adapter.dispose();
        await adapter.load();
        return await adapter.execute();
      });
      for (var cycle = 1; cycle <= speechCleanupCycles; cycle++) {
        await check('cleanup_cycle_$cycle', () async {
          final immediate = recordCancellation(
            await adapter.execute(cancelImmediately: true),
            immediate: true,
          );
          final cancelled = recordCancellation(
            await adapter.execute(cancel: true),
          );
          await adapter.dispose();
          await adapter.load();
          return {
            ...await adapter.execute(),
            'immediate_cancel_latency_ms': immediate['cancel_latency_ms'],
            'cancel_latency_ms': cancelled['cancel_latency_ms'],
            'cancel_after_ms': cancelled['cancel_after_ms'],
            'cancel_in_flight': cancelled['cancel_in_flight'],
            ..._landingFields(cancelled),
          };
        });
      }
      await check(
        'cancel_latency_bound',
        () async => {
          ...latencyBound(
            cancelLatencies,
            cancelLeads,
            speechCancelLatencyBudgetMs,
          ),
          'lead_fraction': speechCancelInFlightLeadFraction,
        },
      );
      await check(
        'immediate_cancel_latency_bound',
        () async => latencyBound(
          immediateLatencies,
          immediateLeads,
          speechImmediateCancelLatencyBudgetMs,
        ),
      );
      await check(
        'peak_memory_bound',
        () async => memoryBound('generate', 'the first generation'),
      );
      await check('leak_slope_bound', () async {
        if (!footprintMeasurable) return unmeasured;
        final window = [
          for (
            var cycle = speechLeakWarmupCycles;
            cycle <= speechCleanupCycles;
            cycle++
          )
            footprintSamples.singleWhere(
                  (sample) => sample['id'] == 'cleanup_cycle_$cycle',
                )['footprint_bytes']!
                as int,
        ];
        final slope = leastSquaresSlope(window);
        return {
          'measurement': memoryFootprintSource,
          'warmup_cycles': speechLeakWarmupCycles,
          'window_footprint_bytes': window,
          'cycle_growth_bytes': [
            for (var i = 1; i < window.length; i++) window[i] - window[i - 1],
          ],
          'slope_bytes_per_cycle': slope,
          'growth_threshold_bytes': speechLeakCycleGrowthBytes,
          'predicate_passed': slope <= speechLeakCycleGrowthBytes,
        };
      });
      if (checkSynthesisInterrupts) {
        final interrupts = adapter as SpeechSynthesisInterruptAdapter;
        for (final dispose in [false, true]) {
          await check(
            dispose ? 'dispose_during_synthesis' : 'unload_during_synthesis',
            () async => _teardownOutcome(
              await interrupts.executeTeardown(dispose: dispose),
            ),
          );
        }
        await check(
          'decode_cancel',
          () async =>
              _decodeCancelOutcome(await interrupts.executeDecodeCancel()),
        );
        await check(
          'interrupt_memory_bound',
          () async => memoryBound('leak_slope_bound', 'leak_slope_bound'),
        );
      }
    }
  } finally {
    await check('dispose', () async {
      await adapter.dispose();
      return {};
    });
  }
  Map<String, Object?> row(String id) => results.firstWhere(
    (entry) => entry['id'] == id,
    orElse: () => const <String, Object?>{},
  );
  final latencyRow = row('cancel_latency_bound');
  final immediateRow = row('immediate_cancel_latency_bound');
  final memoryRow = row('peak_memory_bound');
  bool measured(Map<String, Object?> row) =>
      row.isNotEmpty && row['skip_reason'] != unmeasured['skip_reason'];
  final memoryMeasured = measured(memoryRow);
  final leakRow = row('leak_slope_bound');
  final leakMeasured = measured(leakRow);
  return {
    'schema_version': 1,
    'kind': 'speech_validation',
    'functional_pass':
        results.length == expectedChecks &&
        results.every(
          (entry) =>
              entry['status'] == 'PASS' ||
              (_memoryBoundIds.contains(entry['id']) &&
                  entry['status'] == 'SKIP'),
        ),
    'expected_checks': expectedChecks,
    'edge_fixture_ids': [for (final fixture in edgeFixtures) fixture.id],
    'bounds': {
      'cleanup_cycles': speechCleanupCycles,
      'cancel_latency_ms': {
        'budget': speechCancelLatencyBudgetMs,
        'samples': [...cancelLatencies],
        'lead': [...cancelLeads],
        'progress_events_before_cancel': [...cancelProgressEvents],
        'after_reference_last_progress': [...cancelAfterReferenceLastProgress],
        'lead_fraction': speechCancelInFlightLeadFraction,
        'worst': latencyRow['worst_ms'],
        'within_budget': latencyRow.isEmpty
            ? null
            : latencyRow['status'] == 'PASS',
      },
      'immediate_cancel_latency_ms': {
        'budget': speechImmediateCancelLatencyBudgetMs,
        'samples': [...immediateLatencies],
        'lead': [...immediateLeads],
        'worst': immediateRow['worst_ms'],
        'within_budget': immediateRow.isEmpty
            ? null
            : immediateRow['status'] == 'PASS',
      },
      'peak_footprint_bytes': {
        'measurement': memoryFootprintSource,
        'measured': memoryMeasured,
        'skip_reason': memoryRow['skip_reason'],
        'baseline': memoryRow['baseline_footprint_bytes'],
        'peak': memoryRow['peak_footprint_bytes'],
        'growth': memoryRow['peak_footprint_growth'],
        'growth_budget': speechPeakFootprintGrowthBudget,
        'applies': ratioExemption == null,
        'within_budget': memoryMeasured && ratioExemption == null
            ? memoryRow['status'] == 'PASS'
            : null,
      },
      'leak_slope': {
        'measurement': memoryFootprintSource,
        'measured': leakMeasured,
        'skip_reason': leakRow['skip_reason'],
        'warmup_cycles': speechLeakWarmupCycles,
        'window_cycles': speechLeakWindowCycles,
        'growth_threshold_bytes': speechLeakCycleGrowthBytes,
        'cycle_growth_bytes': leakRow['cycle_growth_bytes'],
        'slope_bytes_per_cycle': leakRow['slope_bytes_per_cycle'],
        'within_budget': leakMeasured ? leakRow['status'] == 'PASS' : null,
      },
    },
    'qualified': false,
    'qualification_reason':
        'Requires reference, platform/accelerator and perceptual evidence; see individual cases.',
    'checks': results,
  };
}

/// Duration from validated mono 16 kHz PCM16 RIFF/WAVE fixture bytes.
double speechFixtureSeconds(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  String tag(int start) =>
      String.fromCharCodes(bytes.sublist(start, start + 4));
  if (bytes.length < 44 ||
      bytes.length > speechFixtureByteCap ||
      tag(0) != 'RIFF' ||
      tag(8) != 'WAVE' ||
      data.getUint32(4, Endian.little) + 8 != bytes.length) {
    throw const FormatException('Invalid bounded RIFF/WAVE fixture');
  }
  var formatSeen = false;
  int? pcmBytes;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final size = data.getUint32(offset + 4, Endian.little);
    final start = offset + 8;
    if (start + size > bytes.length) {
      throw const FormatException('Truncated WAV chunk');
    }
    if (tag(offset) == 'fmt ') {
      if (formatSeen ||
          size < 16 ||
          data.getUint16(start, Endian.little) != 1 ||
          data.getUint16(start + 2, Endian.little) != 1 ||
          data.getUint32(start + 4, Endian.little) != 16000 ||
          data.getUint32(start + 8, Endian.little) != 32000 ||
          data.getUint16(start + 12, Endian.little) != 2 ||
          data.getUint16(start + 14, Endian.little) != 16) {
        throw const FormatException('Expected mono 16 kHz PCM16 WAV');
      }
      formatSeen = true;
    }
    if (tag(offset) == 'data') {
      if (pcmBytes != null || size == 0 || size.isOdd) {
        throw const FormatException('Invalid PCM data');
      }
      pcmBytes = size;
    }
    offset = start + size + (size.isOdd ? 1 : 0);
  }
  if (!formatSeen || pcmBytes == null || offset != bytes.length) {
    throw const FormatException('Incomplete WAV fixture');
  }
  return pcmBytes / 32000;
}

/// Dedicated native CPU ASR: PCM streaming is separate from GGUF prompt ASR.
class PublicDedicatedSpeechAdapter implements SpeechValidationAdapter {
  PublicDedicatedSpeechAdapter({
    required this.model,
    required this.wav,
    required this.reference,
    Future<SpeechToTextEngine> Function(SpeechToTextModel)? loadRecognizer,
  }) : _loadRecognizer = loadRecognizer ?? SpeechToTextEngine.load;
  final Future<SpeechToTextEngine> Function(SpeechToTextModel) _loadRecognizer;
  final SpeechToTextModel model;
  final Uint8List wav;
  final String reference;
  SpeechToTextEngine? _recognizer;
  SpeechToTextStreamingSession? _active;
  late Float32List _pcm;
  late double _seconds;

  @override
  Future<void> load() async {
    _seconds = speechFixtureSeconds(wav);
    final data = ByteData.sublistView(wav);
    var offset = 12;
    while (offset + 8 <= wav.length) {
      final size = data.getUint32(offset + 4, Endian.little);
      if (String.fromCharCodes(wav.sublist(offset, offset + 4)) == 'data') {
        _pcm = Float32List(size ~/ 2);
        for (var i = 0; i < _pcm.length; i++) {
          _pcm[i] = data.getInt16(offset + 8 + i * 2, Endian.little) / 32768;
        }
        break;
      }
      offset += 8 + size + (size.isOdd ? 1 : 0);
    }
    _recognizer = await _loadRecognizer(model);
    final capabilities = await _recognizer!.capabilities;
    if (!capabilities.isSupported) {
      throw StateError(capabilities.unsupportedReason ?? 'ASR unsupported');
    }
  }

  @override
  Future<void> dispose() async {
    await _active?.cancel();
    _active = null;
    await _recognizer?.dispose();
    _recognizer = null;
  }

  @override
  Future<Map<String, Object?>> execute({
    bool cancel = false,
    bool cancelImmediately = false,
    bool invalid = false,
    bool bytesInput = false,
  }) async {
    if (cancel && cancelImmediately) {
      throw ArgumentError('cancel and cancelImmediately are exclusive');
    }
    final watch = Stopwatch()..start();
    final recognizer = _recognizer ?? (throw StateError('ASR is not loaded'));
    if (invalid) {
      final rejected = await recognizer.startStream(
        format: const SpeechAudioFormat(
          sampleRateHz: 8000,
          channelCount: 1,
          encoding: 'pcm-f32le',
        ),
      );
      await rejected.cancel();
      throw StateError('Unsupported PCM format was accepted');
    }
    final session = _active = await recognizer.startStream();
    double? firstPartial;
    var partials = 0;
    var finals = 0;
    final drained = Completer<void>();
    Object? streamError;
    final events = session.events.listen(
      (event) {
        if (event is SpeechToTextPartialEvent) {
          firstPartial ??= watch.elapsedMicroseconds / 1000;
          partials++;
        }
        if (event is SpeechToTextFinalEvent) finals++;
      },
      onError: (Object error) {
        streamError = error;
      },
      onDone: drained.complete,
    );
    final cancelWatch = Stopwatch();
    var pushed = 0;
    var cancelAfterMs = 0.0;
    var cancelInFlight = false;
    final cancelling = cancel || cancelImmediately;
    try {
      if (cancelling) {
        var settled = false;
        unawaited(
          session.done.then<void>(
            (_) => settled = true,
            onError: (Object _) => settled = true,
          ),
        );
        for (
          var offset = 0;
          !cancelImmediately && offset < _pcm.length && partials == 0;
          offset += 1600
        ) {
          final end = offset + 1600 < _pcm.length ? offset + 1600 : _pcm.length;
          await session.addPcm(Float32List.sublistView(_pcm, offset, end));
          pushed = end;
        }
        cancelAfterMs = watch.elapsedMicroseconds / 1000;
        cancelInFlight = pushed > 0 && !settled;
        cancelWatch.start();
        await session.cancel();
      } else {
        for (var offset = 0; offset < _pcm.length; offset += 1600) {
          final end = offset + 1600 < _pcm.length ? offset + 1600 : _pcm.length;
          await session.addPcm(Float32List.sublistView(_pcm, offset, end));
        }
        await session.finish();
      }
      final completion = await session.done;
      await drained.future;
      if (streamError != null) throw streamError!;
      if (cancelling) {
        cancelWatch.stop();
        if (completion.state != SpeechToTextCompletionState.cancelled ||
            finals != 0) {
          throw StateError('ASR cancellation did not complete cleanly');
        }
        return {
          'cancelled': true,
          'cancel_latency_ms': cancelWatch.elapsedMicroseconds / 1000,
          'cancel_after_ms': cancelAfterMs,
          if (cancelImmediately)
            'cancel_immediate': true
          else
            'cancel_in_flight': cancelInFlight,
          'pcm_samples_before_cancel': pushed,
          'partial_events_before_cancel': partials,
        };
      }
      if (completion.state != SpeechToTextCompletionState.completed ||
          completion.result == null ||
          finals != 1) {
        throw StateError('ASR stream did not complete');
      }
      final text = completion.result!.text;
      final wer = speechWordErrorRate(reference, text);
      return {
        'transcript': text,
        'reference': reference,
        'wer': wer,
        'predicate_passed': wer == 0,
        'first_partial_ms': firstPartial,
        'partial_events': partials,
        'elapsed_ms': watch.elapsedMicroseconds / 1000,
        'audio_seconds': _seconds,
        'real_time_factor': watch.elapsedMicroseconds / 1e6 / _seconds,
        'backend': 'cpu',
        'streaming_input': true,
      };
    } finally {
      await session.cancel();
      await events.cancel();
      _active = null;
    }
  }
}
