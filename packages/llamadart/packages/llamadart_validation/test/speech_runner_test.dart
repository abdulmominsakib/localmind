import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fake_async/fake_async.dart';
import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/speech/speech_engine_lease.dart';
import 'package:llamadart_validation/llamadart_validation.dart';
import 'package:llamadart_validation/src/process_memory.dart';
import 'package:llamadart_validation/src/speech_edge_fixtures.dart';
import 'package:llamadart_validation/src/speech_runner.dart';
import 'package:test/test.dart';

class FakeSpeech implements SpeechValidationAdapter {
  final calls = <String>[];
  bool ignoreInvalid = false;
  bool wrongWords = false;
  bool failLoad = false;
  bool failCleanup = false;
  bool reportCancelLatency = true;
  bool reportInFlight = true;
  bool reportImmediate = true;
  bool skipGenerate = false;
  double cancelLatencyMs = 1;
  double immediateCancelLatencyMs = 1;
  List<double>? cancelLatenciesMs;
  List<double>? immediateCancelLatenciesMs;
  Map<String, Object?> inFlightReport = {};
  double inFlightLeadMs = 100;
  int? unmeasuredInFlightCancel;
  int inFlightCancels = 0;
  int immediateCancels = 0;
  Object? invalidError;
  @override
  Future<void> load() async {
    calls.add('load');
    if (failLoad) throw StateError('load failure');
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    if (failCleanup) throw StateError('cleanup failure');
  }

  @override
  Future<Map<String, Object?>> execute({
    bool cancel = false,
    bool cancelImmediately = false,
    bool invalid = false,
    bool bytesInput = false,
  }) async {
    calls.add(
      cancel
          ? 'cancel'
          : cancelImmediately
          ? 'cancel_immediate'
          : invalid
          ? 'invalid'
          : 'execute',
    );
    if (invalid && !ignoreInvalid) {
      throw invalidError ?? ArgumentError('invalid');
    }
    if (cancelImmediately) {
      final index = immediateCancels++;
      return {
        'cancelled': true,
        if (reportCancelLatency)
          'cancel_latency_ms':
              immediateCancelLatenciesMs?[index] ?? immediateCancelLatencyMs,
        'cancel_after_ms': 0.0,
        'cancel_immediate': reportImmediate,
      };
    }
    if (skipGenerate && !cancel && !invalid) {
      return {'skipped': true, if (wrongWords) 'predicate_passed': false};
    }
    final unmeasured = cancel && ++inFlightCancels == unmeasuredInFlightCancel;
    return {
      'predicate_passed': !wrongWords,
      if (cancel) 'cancelled': true,
      if (cancel && reportCancelLatency && !unmeasured)
        'cancel_latency_ms':
            cancelLatenciesMs?[inFlightCancels - 1] ?? cancelLatencyMs,
      if (cancel) 'cancel_after_ms': inFlightLeadMs,
      if (cancel) 'cancel_in_flight': reportInFlight,
      if (cancel) ...inFlightReport,
    };
  }
}

class FakeEdgeSpeech extends FakeSpeech implements SpeechEdgeCaseAdapter {
  FakeEdgeSpeech({this.failEdge});
  final String? failEdge;

  @override
  Future<Map<String, Object?>> executeEdge(SpeechEdgeFixture fixture) async {
    calls.add('edge:${fixture.id}');
    return {'predicate_passed': fixture.id != failEdge};
  }
}

const qwen3TtsCapabilities = BackendTextToSpeechCapabilities(
  isSupported: true,
  model: BackendTextToSpeechModel.qwen3Tts,
  sampleRateHz: 24000,
  channelCount: 1,
  supportsLanguage: true,
  supportsCancellation: true,
);

/// Serves fake model, context and projector handles, and runs text-to-speech
/// through [onSynthesize] and [onCancel].
class FakeSpeechBackend
    implements LlamaBackend, BackendMultimodalSupport, BackendTextToSpeech {
  BackendTextToSpeechCapabilities textToSpeech =
      const BackendTextToSpeechCapabilities(
        isSupported: false,
        unsupportedReason: 'This fake does not synthesize speech.',
      );
  Future<BackendTextToSpeechResult> Function(
    BackendTextToSpeechRequest request,
    void Function(BackendTextToSpeechProgress progress)? onProgress,
  )?
  onSynthesize;
  void Function()? onCancel;

  @override
  bool get isReady => true;

  @override
  bool get supportsUrlLoading => false;

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}

  @override
  Future<int> modelLoad(String path, ModelParams params) async => 1;

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async => 2;

  @override
  Future<int?> multimodalContextCreate(
    int modelHandle,
    String mmProjPath,
  ) async => 3;

  @override
  Future<void> multimodalContextFree(int mmContextHandle) async {}

  @override
  Future<void> contextFree(int contextHandle) async {}

  @override
  Future<void> modelFree(int modelHandle) async {}

  @override
  void cancelGeneration() {}

  @override
  Future<void> dispose() async {}

  @override
  Future<BackendTextToSpeechCapabilities> textToSpeechCapabilities(
    int contextHandle,
    int mmContextHandle,
  ) async => textToSpeech;

  @override
  Future<BackendTextToSpeechResult> synthesizeTextToSpeech(
    int contextHandle,
    int mmContextHandle,
    BackendTextToSpeechRequest request, {
    void Function(BackendTextToSpeechProgress progress)? onProgress,
  }) {
    final synthesize = onSynthesize;
    if (synthesize == null) {
      throw UnsupportedError('This fake does not synthesize speech');
    }
    return synthesize(request, onProgress);
  }

  @override
  void cancelTextToSpeech() => onCancel?.call();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Takes every local path as an existing file, so a fake engine loads model
/// files that are only names.
class FakeModelFiles extends ThrowingModelDownloadManager {
  @override
  Future<ModelCacheEntry> ensureModel(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async => ModelCacheEntry(
    sourceCanonicalKey: source.metadataSourceKey,
    cacheKey: source.cacheKey,
    fileName: source.fileName,
    filePath: source.path!,
    bytes: 1,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

/// Loads its model and projector through [FakeSpeechBackend] once and keeps
/// them, so a teardown fake can model its own unload and dispose.
class FakeSpeechEngine extends LlamaEngine {
  FakeSpeechEngine({
    this.deltas = const <String>[],
    this.failure,
    this.tokenDelay = Duration.zero,
    this.laterTokenDelay,
  }) : super(FakeSpeechBackend(), modelDownloadManager: FakeModelFiles());
  final List<String> deltas;
  final Object? failure;
  final Duration tokenDelay;
  final Duration? laterTokenDelay;
  final loaded = <String>[];
  final audioParts = <LlamaAudioContent>[];
  var generations = 0;
  var disposals = 0;

  FakeSpeechBackend get speechBackend => backend as FakeSpeechBackend;

  @override
  Future<bool> get supportsAudio async => true;

  @override
  Future<String> getBackendName() async => 'cpu';

  @override
  Future<int?> getResolvedGpuLayers() async => 0;

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}

  @override
  Future<void> setModel(
    LlamaModel model, {
    ModelParams params = const ModelParams(),
    ModelLoadOptions download = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    loaded.addAll([model.source.path!, ?model.projector?.path]);
    if (!isReady) {
      await super.setModel(
        model,
        params: params,
        download: download,
        onProgress: onProgress,
      );
    }
  }

  @override
  void cancelGeneration() {}

  @override
  Future<void> dispose() async => disposals++;

  @override
  Stream<LlamaCompletionChunk> create(
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? responseFormat,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) async* {
    generations++;
    audioParts.addAll(
      messages
          .expand((message) => message.parts)
          .whereType<LlamaAudioContent>(),
    );
    if (failure != null) throw failure!;
    final delay = generations > 1 ? laterTokenDelay ?? tokenDelay : tokenDelay;
    for (final delta in deltas) {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      yield completionChunk(delta);
    }
  }
}

LlamaCompletionChunk completionChunk(String delta) => LlamaCompletionChunk(
  id: 'edge',
  object: 'chat.completion.chunk',
  created: 0,
  model: 'fake',
  choices: [
    LlamaCompletionChunkChoice(
      index: 0,
      delta: LlamaCompletionChunkDelta(content: delta),
    ),
  ],
);

class CancellableSpeechEngine extends FakeSpeechEngine {
  CancellableSpeechEngine({
    required this.completedTokenDelays,
    this.cancelAckDelay = Duration.zero,
  }) : super(deltas: const ['and ', 'so ', 'my ', 'fellow ', 'americans']) {
    speechBackend
      ..textToSpeech = qwen3TtsCapabilities
      ..onSynthesize = _synthesize
      ..onCancel = _acknowledgeCancel;
  }
  final List<Duration> completedTokenDelays;
  final Duration cancelAckDelay;
  Completer<void>? _running;

  Future<bool> _awaitToken(int generation) async {
    if (generation >= completedTokenDelays.length) {
      await (_running = Completer<void>()).future;
      return false;
    }
    final delay = completedTokenDelays[generation];
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return true;
  }

  void _acknowledgeCancel() {
    final running = _running;
    if (running == null) return;
    Future<void>.delayed(cancelAckDelay, () {
      if (!running.isCompleted) running.complete();
    });
  }

  @override
  void cancelGeneration() => _acknowledgeCancel();

  @override
  Stream<LlamaCompletionChunk> create(
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? responseFormat,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) {
    late final StreamController<LlamaCompletionChunk> controller;
    controller = StreamController<LlamaCompletionChunk>(
      onListen: () async {
        final generation = generations++;
        for (final delta in deltas) {
          if (!await _awaitToken(generation)) break;
          controller.add(completionChunk(delta));
        }
        await controller.close();
      },
      // A subscription cancel stops only this generation, as on llama.cpp,
      // and completes once the generation acknowledges it.
      onCancel: () {
        final running = _running;
        _acknowledgeCancel();
        return running?.future;
      },
    );
    return controller.stream;
  }

  Future<BackendTextToSpeechResult> _synthesize(
    BackendTextToSpeechRequest request,
    void Function(BackendTextToSpeechProgress progress)? onProgress,
  ) async {
    final generation = generations++;
    for (var frame = 0; frame < deltas.length; frame++) {
      if (!await _awaitToken(generation)) break;
    }
    return BackendTextToSpeechResult(
      samples: Float32List.fromList([.25, -.25]),
      sampleRateHz: 24000,
      channelCount: 1,
      framesGenerated: deltas.length,
      truncated: false,
    );
  }
}

class FakeInterruptSpeech extends FakeSpeech
    implements SpeechSynthesisInterruptAdapter {
  Map<String, Object?> teardownReport = {};
  Map<String, Object?> decodeReport = {};

  /// Shortest reference 400 ms (run after the cancel), spread 100 ms, so the
  /// margin is 90 ms. The lead is 0.1 of the 450 ms shortest reference run
  /// before the cancel, leaving 355 ms; less the 3 ms overhead, that is
  /// 352 ms. The cancelled synthesis must end before 310 ms, a latency below
  /// 265 ms.
  static Map<String, Object?> passingDecode() => {
    'frame_cap': speechDecodeCancelFrameCap,
    'uncapped_frames': speechDecodeCancelFrameCap + 1,
    'overhead_probes': [
      for (final latency in [1.0, 3.0, 2.0])
        {
          'completion_state': 'cancelled',
          'final_events': 0,
          'cancel_latency_ms': latency,
        },
    ],
    'warm_up': {
      'frames': speechDecodeCancelFrameCap,
      'truncated': true,
      'decode_ms': 520.0,
    },
    'references': [
      for (final decode in [
        500.0,
        450.0,
        460.0,
        470.0,
        400.0,
        420.0,
        430.0,
        440.0,
      ])
        {
          'frames': speechDecodeCancelFrameCap,
          'truncated': true,
          'decode_ms': decode,
        },
    ],
    'references_before_cancel': 4,
    'frames_before_cancel': speechDecodeCancelFrameCap,
    'cancel_after_decode_start_ms': 45.0,
    'cancel_in_flight': true,
    'completion_state': 'cancelled',
    'final_events': 0,
    'cancel_latency_ms': 1.0,
  };

  @override
  Future<Map<String, Object?>> executeTeardown({required bool dispose}) async {
    calls.add(dispose ? 'dispose_synthesis' : 'unload_synthesis');
    return {
      'teardown': dispose ? 'dispose' : 'unload',
      'in_flight': true,
      'frames_before_teardown': 1,
      'completion_state': 'cancelled',
      'final_events': 0,
      'teardown_latency_ms': 1.0,
      'teardown_call_ms': 2.0,
      'after_teardown': {'predicate_passed': true},
      ...teardownReport,
    };
  }

  @override
  Future<Map<String, Object?>> executeDecodeCancel() async {
    calls.add('decode_cancel');
    return {...passingDecode(), ...decodeReport};
  }
}

class FakeLimitSpeech extends FakeSpeech
    implements SpeechTranscriptLimitAdapter {
  final reports = <LlamaSpeechTranscriptLimit, Map<String, Object?>>{};

  static Map<String, Object?> passingLimit(LlamaSpeechTranscriptLimit limit) =>
      {
        'max_output_tokens': limit == LlamaSpeechTranscriptLimit.maxOutputTokens
            ? 11
            : 512,
        if (limit == LlamaSpeechTranscriptLimit.maxOutputTokens)
          'transcript_tokens': 12,
        if (limit == LlamaSpeechTranscriptLimit.contextSize)
          'context_size': speechTruncationContextSize,
        'reference': 'and so my fellow americans',
        'reference_repeats': 1,
        'completion_state': 'failed',
        'truncated_limit': limit.name,
        'partial_transcript': 'And so, my',
        'after_truncation': {'predicate_passed': true},
      };

  @override
  Future<Map<String, Object?>> executeTranscriptLimit(
    LlamaSpeechTranscriptLimit limit,
  ) async {
    calls.add('limit:${limit.name}');
    return {...passingLimit(limit), ...?reports[limit]};
  }
}

class DelegatingSpeech extends FakeSpeech
    implements SpeechSynthesisInterruptAdapter, SpeechTranscriptLimitAdapter {
  DelegatingSpeech(this.inner);
  final PublicSpeechValidationAdapter inner;

  @override
  Future<void> load() async {
    await super.load();
    await inner.load();
  }

  @override
  Future<void> dispose() async {
    await super.dispose();
    await inner.dispose();
  }

  @override
  Future<Map<String, Object?>> execute({
    bool cancel = false,
    bool cancelImmediately = false,
    bool invalid = false,
    bool bytesInput = false,
  }) => cancel || cancelImmediately || invalid
      ? super.execute(
          cancel: cancel,
          cancelImmediately: cancelImmediately,
          invalid: invalid,
        )
      : inner.execute(bytesInput: bytesInput);

  @override
  Future<Map<String, Object?>> executeTeardown({required bool dispose}) =>
      inner.executeTeardown(dispose: dispose);

  @override
  Future<Map<String, Object?>> executeDecodeCancel() =>
      inner.executeDecodeCancel();

  @override
  Future<Map<String, Object?>> executeTranscriptLimit(
    LlamaSpeechTranscriptLimit limit,
  ) => inner.executeTranscriptLimit(limit);
}

class SynthesisSpeechEngine extends FakeSpeechEngine {
  SynthesisSpeechEngine({
    this.decodeHonoursCancel = true,
    this.teardownCancels = true,
    this.frameStep = frameDelay,
    this.decodeStep = decodeDelay,
    this.decodeTail = Duration.zero,
    this.coldDecode = Duration.zero,
  }) {
    speechBackend
      ..textToSpeech = qwen3TtsCapabilities
      ..onSynthesize = _synthesize
      ..onCancel = _cancel;
  }
  final bool decodeHonoursCancel;
  final bool teardownCancels;
  final Duration frameStep;
  final Duration decodeStep;

  /// Work after the decode that a cancellation cannot skip, as on CUDA.
  final Duration decodeTail;

  /// Extra time the first decode takes after syntheses that never decoded.
  final Duration coldDecode;
  var _decoded = false;
  static const naturalFrames = 20;
  static const frameDelay = Duration(milliseconds: 4);
  static const decodeDelay = Duration(milliseconds: 300);
  final teardowns = <String>[];
  final requestedFrames = <int>[];
  final cancelledRuns = <bool>[];
  var _cancelled = false;
  Completer<void>? _wake;

  Future<void> _wait(Duration delay, {bool interruptible = true}) async {
    if (!interruptible) return Future<void>.delayed(delay);
    final wake = _wake = Completer<void>();
    final timer = Timer(delay, () {
      if (!wake.isCompleted) wake.complete();
    });
    await wake.future;
    timer.cancel();
  }

  void _cancel() {
    _cancelled = true;
    final wake = _wake;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  @override
  Future<void> unloadModel() async {
    teardowns.add('unload');
    if (teardownCancels) SpeechEngineLease.cancelActiveTask(this);
  }

  @override
  Future<void> dispose() async {
    teardowns.add('dispose');
    if (teardownCancels) SpeechEngineLease.cancelActiveTask(this);
    disposals++;
  }

  Future<BackendTextToSpeechResult> _synthesize(
    BackendTextToSpeechRequest request,
    void Function(BackendTextToSpeechProgress progress)? onProgress,
  ) async {
    _cancelled = false;
    requestedFrames.add(request.maxFrames);
    final frames = math.min(naturalFrames, request.maxFrames);
    var generated = 0;
    while (generated < frames && !_cancelled) {
      await _wait(frameStep);
      if (_cancelled) break;
      generated++;
      onProgress?.call(
        BackendTextToSpeechProgress(
          phase: BackendTextToSpeechPhase.generating,
          promptTokensRemaining: 0,
          framesGenerated: generated,
          truncated: false,
        ),
      );
    }
    if (!_cancelled) {
      final cold = !_decoded && coldDecode > Duration.zero;
      _decoded = true;
      await _wait(
        cold ? decodeStep + coldDecode : decodeStep,
        interruptible: decodeHonoursCancel,
      );
      if (decodeTail > Duration.zero) await Future<void>.delayed(decodeTail);
    } else {
      _decoded = false;
    }
    cancelledRuns.add(_cancelled);
    return BackendTextToSpeechResult(
      samples: Float32List.fromList([.25, -.25]),
      sampleRateHz: 24000,
      channelCount: 1,
      framesGenerated: generated,
      truncated: naturalFrames > request.maxFrames,
    );
  }
}

/// A stopwatch that reads 1% slow, so a timer set from its own readings fires
/// before it reaches its target, as Dart timers occasionally do.
class SlowStopwatch extends FakeTimeStopwatch {
  SlowStopwatch(super.async);

  @override
  int get elapsedMicroseconds => super.elapsedMicroseconds * 99 ~/ 100;
}

/// A [Stopwatch] that reads [FakeAsync.elapsed], so timed checks see the
/// exact delays [SynthesisSpeechEngine] schedules.
class FakeTimeStopwatch implements Stopwatch {
  FakeTimeStopwatch(this._async);
  final FakeAsync _async;
  Duration? _startedAt;
  Duration _stopped = Duration.zero;

  @override
  int get frequency => Duration.microsecondsPerSecond;

  @override
  void start() => _startedAt ??= _async.elapsed;

  @override
  void stop() {
    final startedAt = _startedAt;
    if (startedAt == null) return;
    _stopped += _async.elapsed - startedAt;
    _startedAt = null;
  }

  @override
  void reset() {
    _stopped = Duration.zero;
    if (_startedAt != null) _startedAt = _async.elapsed;
  }

  @override
  Duration get elapsed =>
      _stopped +
      (_startedAt == null ? Duration.zero : _async.elapsed - _startedAt!);

  @override
  int get elapsedTicks => elapsed.inMicroseconds;

  @override
  int get elapsedMicroseconds => elapsed.inMicroseconds;

  @override
  int get elapsedMilliseconds => elapsed.inMilliseconds;

  @override
  bool get isRunning => _startedAt != null;
}

/// Runs [start] on fake time, 1 ms at a time, and returns its result.
///
/// Between steps it yields one real event-loop turn: an `await` on a future
/// the SDK completes in the root zone, such as a finished subscription's
/// `cancel()`, resumes only there.
Future<T> runInFakeTime<T>(Future<T> Function(FakeAsync async) start) async {
  final async = FakeAsync();
  T? value;
  Object? error;
  var done = false;
  async.run(
    (async) => start(async).then(
      (result) {
        value = result;
        done = true;
      },
      onError: (Object caught) {
        error = caught;
        done = true;
      },
    ),
  );
  while (!done) {
    if (async.elapsed > const Duration(minutes: 10)) {
      throw StateError('The run did not finish in 10 minutes of fake time');
    }
    async.elapse(const Duration(milliseconds: 1));
    await Future<void>.delayed(Duration.zero);
  }
  if (error != null) throw error!;
  return value as T;
}

const jfkReference =
    'And so my fellow Americans ask not what your country can do for you ask '
    'what you can do for your country';

List<String> referenceWords(int repeats) =>
    List.filled(repeats, jfkReference).join(' ').split(' ');

class LimitedRecognitionEngine extends FakeSpeechEngine {
  LimitedRecognitionEngine({required this.fixtureBytes, this.typed = true});
  final int fixtureBytes;
  final bool typed;
  final contextSizes = <int>[];
  final maxTokens = <int?>[];
  var _contextSize = 0;

  @override
  Future<void> setModel(
    LlamaModel model, {
    ModelParams params = const ModelParams(),
    ModelLoadOptions download = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    await super.setModel(
      model,
      params: params,
      download: download,
      onProgress: onProgress,
    );
    contextSizes.add(_contextSize = params.contextSize);
  }

  @override
  Future<int> getContextSize() async => _contextSize;

  @override
  Future<List<int>> tokenize(String text, {bool addSpecial = true}) async =>
      List.filled(text.split(' ').length, 1);

  @override
  Stream<LlamaCompletionChunk> create(
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? responseFormat,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) async* {
    generations++;
    final audio = messages
        .expand((message) => message.parts)
        .whereType<LlamaAudioContent>()
        .single;
    audioParts.add(audio);
    maxTokens.add(params!.maxTokens);
    final repeats = (audio.bytes?.length ?? fixtureBytes) > fixtureBytes
        ? 3
        : 1;
    final words = referenceWords(repeats);
    final fits = repeats > 1 && _contextSize < 1024 ? 2 * words.length ~/ 3 : 0;
    final limit = fits > 0 && fits < params.maxTokens ? fits : params.maxTokens;
    for (final word in words.take(limit)) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
      yield completionChunk('$word ');
    }
    if (typed && limit < words.length) {
      throw LlamaSpeechTranscriptTruncatedException(
        'Speech recognition reached a token limit.',
        limit: limit == params.maxTokens
            ? LlamaSpeechTranscriptLimit.maxOutputTokens
            : LlamaSpeechTranscriptLimit.contextSize,
        partialTranscript: words.take(limit).join(' '),
      );
    }
  }
}

int stableFootprintBytes() => 1000;

const mib = 1024 * 1024;

List<int> mibs(Iterable<double> values) => [
  for (final value in values) (value * mib).round(),
];

List<double> parseMib(String values) => [
  for (final value in values.split(' ')) double.parse(value),
];

/// Returns one sample per check in a [FakeSpeech] run's order, then repeats
/// the last: `load` … `after_invalid` (7), `reload`, the cleanup cycles, the
/// two latency bounds, `peak_memory_bound`, `leak_slope_bound`, `dispose`.
int? Function() replay(List<int> bytes) {
  var index = 0;
  return () => bytes[math.min(index++, bytes.length - 1)];
}

/// Seven flat single-shot samples at [base], then `reload` and each cycle
/// growing by [perCycle] bytes.
List<int> linearCycles(int perCycle, {int base = 1000 * mib}) => [
  for (var i = 0; i < 7; i++) base,
  for (var cycle = 0; cycle <= speechCleanupCycles; cycle++)
    base + cycle * perCycle,
];

Map<String, Object?> checkRow(Map<String, Object?> result, String id) =>
    (result['checks'] as List).cast<Map<String, Object?>>().singleWhere(
      (row) => row['id'] == id,
    );

/// Footprint MiB sampled after `malloc_trim(0)`, in the [replay] layout
/// (`load` … `after_invalid`, `reload`, cycles 1-8), from pack runs on GCE
/// g2-standard-8 + NVIDIA L4, Linux CUDA, Ubuntu 24.04, glibc 2.39 (#762).
/// `stt` omits its `bytes_input`, edge-fixture and truncation samples.
const linuxCudaMib = {
  'tts r1':
      '452.6 717.9 718.0 723.2 723.5 723.6 725.7 744.9 733.2 742.5 747.9 754.5 '
      '737.2 735.5 746.0 741.7',
  'tts r2':
      '451.6 715.4 715.6 717.6 723.8 723.9 732.7 738.4 728.9 733.6 743.8 749.0 '
      '749.5 734.0 731.1 731.6',
  'tts r3':
      '462.3 728.1 728.3 730.3 737.8 737.9 743.1 756.7 767.9 769.4 765.4 765.5 '
      '772.6 751.9 752.4 743.4',
  'stt':
      '458.7 611.2 614.9 613.0 614.8 614.9 615.2 653.9 653.1 650.6 631.3 624.6 '
      '629.7 624.0 624.0 625.9',
};

/// [linuxCudaMib] layout, from `tts` pack runs on GCE n2-standard-8 (x64) and
/// t2a-standard-8 (arm64), Linux CPU, Ubuntu 24.04, glibc 2.39 (#762).
const linuxCpuTtsMib = {
  'x64 r1':
      '1819.2 2750.5 2750.6 2755.8 2757.2 2757.4 2757.6 2782.9 2757.1 2766.8 '
      '2771.7 2755.7 2751.1 2751.6 2752.3 2753.7',
  'x64 r2':
      '1841.6 2772.7 2772.9 2772.5 2780.0 2780.1 2780.6 2780.2 2760.1 2748.8 '
      '2751.0 2761.3 2761.7 2750.3 2767.2 2758.0',
  'arm64':
      '1179.0 2110.7 2110.9 2115.8 2115.9 2116.0 2118.6 2120.0 2126.4 2111.6 '
      '2108.5 2112.4 2115.8 2131.9 2114.8 2109.9',
};

/// Resident MiB of the #634 LiteRT ASR run on GCE e2-standard-8, Linux x64
/// CPU, after `load` … `after_invalid`, then after each of the next seven
/// checks (#686): a one-time jump at `cancel`, then +0.7 MiB per cycle.
const linuxLiteRtAsrMib =
    '384.4 485.2 485.5 570.9 574.5 574.5 574.5 577.9 578.7 579.4 580.0 580.7 '
    '581.4 582.1';

/// Footprint MiB sampled after `malloc_trim(0)`, in the [replay] layout
/// (`load` … `after_invalid`, `reload`, cycles 1-8), from GGUF `stt` pack runs
/// on GCE n2-standard-8 (x64) and t2a-standard-8 (arm64), Ubuntu 24.04, glibc
/// 2.39 (#762): r1-r4 at 3d6b83865 with the trim added, r5 with this counter.
/// `stt` omits its `bytes_input`, edge-fixture and truncation samples.
const linuxTrimmedSttMib = {
  'x64 r1':
      '995.2 1169.7 1185.5 1180.4 1176.5 1178.8 1181.3 1181.9 1184.0 1192.5 '
      '1173.9 1171.2 1177.4 1161.8 1167.2 1164.6',
  'x64 r2':
      '980.8 1164.2 1176.4 1165.0 1167.0 1169.6 1166.9 1183.1 1184.1 1198.7 '
      '1169.9 1169.1 1168.3 1174.0 1176.8 1165.8',
  'x64 r3':
      '984.8 1170.8 1185.2 1176.4 1175.5 1176.5 1172.7 1179.1 1189.2 1191.4 '
      '1168.0 1173.8 1165.4 1171.3 1173.6 1171.2',
  'x64 r4':
      '979.0 1159.5 1179.3 1163.4 1163.9 1164.2 1168.0 1188.8 1187.8 1186.2 '
      '1169.4 1177.7 1167.7 1160.3 1169.9 1168.3',
  'arm64 r1':
      '1583.7 1764.1 1781.3 1752.4 1756.1 1759.8 1764.1 1775.3 1780.6 1774.9 '
      '1781.4 1787.0 1776.1 1781.1 1788.9 1784.3',
  'arm64 r2':
      '1569.1 1751.4 1757.9 1745.2 1745.6 1749.3 1756.5 1736.2 1741.9 1749.3 '
      '1747.4 1757.7 1764.1 1758.6 1754.1 1751.3',
  'arm64 r3':
      '1569.0 1753.8 1771.5 1750.8 1752.5 1754.6 1760.9 1753.1 1754.4 1766.0 '
      '1773.3 1766.5 1764.8 1757.1 1762.1 1777.1',
  'arm64 r4':
      '1554.8 1739.6 1756.7 1740.9 1746.8 1748.3 1749.5 1772.4 1771.8 1758.3 '
      '1766.0 1758.6 1761.0 1763.9 1771.9 1779.6',
  'x64 r5':
      '1026.8 1213.3 1216.2 1215.2 1174.5 1174.6 1174.8 1181.6 1192.3 1190.7 '
      '1186.2 1190.1 1190.9 1196.7 1193.8 1178.2',
  'arm64 r5':
      '1570.3 1734.4 1740.3 1738.7 1737.4 1737.6 1738.0 1756.7 1756.0 1763.0 '
      '1746.0 1745.6 1745.8 1747.0 1750.0 1749.3',
};

/// [linuxTrimmedSttMib] runs that `malloc` and write a block of the named size
/// after the `load` in `reload` and in every cycle, and never free it (#762).
const linuxTrimmedSttLeakMib = {
  'x64 16 MiB r1':
      '993.3 1177.0 1196.5 1173.3 1180.2 1180.3 1188.1 1215.6 1211.4 1232.0 '
      '1243.0 1241.7 1259.3 1268.3 1288.9 1315.1',
  'x64 16 MiB r2':
      '991.5 1176.1 1190.4 1184.5 1188.3 1177.8 1178.4 1213.5 1238.0 1238.4 '
      '1237.6 1252.9 1259.0 1276.3 1288.7 1313.3',
  'x64 12 MiB':
      '983.5 1168.1 1182.1 1173.1 1174.6 1172.3 1177.9 1206.6 1219.4 1230.8 '
      '1218.5 1240.7 1240.3 1256.8 1273.7 1281.3',
  'arm64 16 MiB r1':
      '1562.2 1748.9 1769.2 1747.1 1749.8 1750.7 1754.2 1779.6 1805.9 1811.9 '
      '1842.2 1860.2 1863.9 1883.1 1895.7 1908.8',
  'arm64 16 MiB r2':
      '1576.4 1756.6 1776.2 1755.1 1759.9 1757.1 1757.4 1775.1 1785.2 1808.6 '
      '1811.4 1825.9 1842.3 1862.8 1883.4 1891.4',
  'arm64 12 MiB':
      '1563.0 1743.4 1760.2 1746.8 1741.9 1749.7 1754.2 1776.0 1783.0 1796.5 '
      '1801.4 1813.8 1814.8 1828.8 1845.8 1843.3',
};

/// The `leak_slope_bound` window, cycles 1-8, of a series in the [replay]
/// layout, holding its last value as [replay] does.
List<int> leakWindow(List<double> series) => [
  for (var i = 8; i <= 8 + speechLeakWindowCycles; i++)
    (series[math.min(i, series.length - 1)] * mib).round(),
];

/// Resident MiB after `load` … `after_invalid`, `reload` and 14 cleanup
/// cycles, macOS arm64 (Apple M4 Max), load average 3.5-6.1, 2026-09-25 (#686).
/// `stt` omits its `bytes_input` and edge-fixture samples.
const macosMib = {
  'tts/cpu':
      '3129.1 5446.5 5446.5 5446.8 5446.6 5446.6 5447.0 5458.0 5460.2 5462.2 '
      '5462.4 5464.5 5467.7 5469.7 5470.9 5476.9 5477.7 5451.8 5451.8 5452.0 '
      '5452.1 5452.2',
  'tts/metal':
      '2479.2 3925.0 3925.0 3925.1 3925.5 3925.5 3927.4 3935.6 3936.4 3936.9 '
      '3947.5 3951.8 3955.1 3957.0 3957.7 3958.4 3960.7 3961.2 3962.5 3963.1 '
      '3963.8 3965.0',
  'stt/cpu':
      '2339.7 2527.5 2529.3 2529.5 2529.6 2529.6 2529.6 2542.9 2552.8 2554.5 '
      '2556.4 2556.4 2556.4 2556.4 2556.4 2556.4 2556.4 2556.4 2556.4 2556.4 '
      '2556.4 2556.4',
};

/// The #634 LiteRT ASR leak in the same layout and run as [macosMib].
const macosLiteRtAsrMib =
    '364.3 465.5 473.7 479.8 484.6 484.7 489.1 494.3 508.4 556.5 575.7 590.6 '
    '604.7 618.7 632.8 646.9 660.9 674.9 689.0 705.0 719.0 733.0';

/// [series] with `reload` and the cycles taken from [offset] cycles later.
List<double> shifted(List<double> series, int offset) => [
  ...series.take(7),
  ...series.skip(7 + offset).take(speechCleanupCycles + 1),
];

void main() {
  test(
    'speech input rejection accepts contract errors, not inference failures',
    () async {
      for (final error in [
        LlamaAudioFormatException('Encoded audio bytes must not be empty.'),
        LlamaTextToSpeechException('Text to synthesize must not be empty.'),
        LlamaTextToSpeechException('Synthesis failed.'),
        LlamaInferenceException('Generation failed.'),
      ]) {
        final adapter = FakeSpeech()..invalidError = error;
        final result = await runSpeechValidation(
          adapter,
          footprintBytes: stableFootprintBytes,
        );
        final checks = result['checks'] as List;
        final rejection = checks.singleWhere(
          (item) => item['id'] == 'invalid_input',
        );
        final accepted =
            error is LlamaAudioFormatException ||
            error.message == 'Text to synthesize must not be empty.';
        expect(rejection['status'], accepted ? 'PASS' : 'FAIL');
        expect(result['functional_pass'], accepted);
        expect(result['qualified'], false);
        expect(
          checks.singleWhere((item) => item['id'] == 'after_invalid')['status'],
          'PASS',
        );
        expect(adapter.calls.last, 'dispose');
      }
    },
  );

  test(
    'WER counts substitutions, insertions, deletions and rejects empty oracle',
    () {
      expect(speechWordErrorRate('Hello, WORLD!', 'hello world'), 0);
      expect(speechWordErrorRate('one two', 'one three four'), 1);
      expect(speechWordErrorRate('one two', 'one'), .5);
      expect(speechWordErrorRate('one', 'two three four'), 3);
      expect(speechWordErrorRate('Montréal 한글', 'Montréal 한글'), 0);
      expect(() => speechWordErrorRate(' ', 'hello'), throwsArgumentError);
    },
  );
  TextToSpeechResult audio(List<double> values, {bool truncated = false}) =>
      TextToSpeechResult(
        samples: Float32List.fromList(values),
        sampleRateHz: 24000,
        channelCount: 1,
        framesGenerated: 1,
        truncated: truncated,
      );
  test('nonempty bytes alone cannot qualify invalid or truncated TTS', () {
    for (final result in [
      audio([]),
      audio([0, 0]),
      audio([double.nan]),
      audio([double.infinity]),
      audio([.5], truncated: true),
    ]) {
      expect(() => inspectSpeechAudio(result), throwsStateError);
    }
    final result = inspectSpeechAudio(audio([.25, -.25]));
    expect(result['audio_seconds'], closeTo(2 / 24000, .0000001));
    expect(result['listening_check'], 'NOT_RUN');
  });
  test(
    'locked fixture validates PCM duration and rejects malformed headers',
    () {
      final bytes = File('assets/speech/jfk.wav').readAsBytesSync();
      expect(speechFixtureSeconds(bytes), greaterThan(1));
      for (final bad in [
        Uint8List(0),
        Uint8List.fromList(bytes.sublist(0, 50)),
        Uint8List.fromList(bytes)..[0] = 0,
      ]) {
        expect(() => speechFixtureSeconds(bad), throwsFormatException);
      }
      final lock = jsonDecode(
        File('assets/speech/stt.json').readAsStringSync(),
      );
      expect(sha256.convert(bytes).toString(), lock['fixture']['sha256']);
      expect(bytes.length, lock['fixture']['bytes']);
    },
  );
  test('locks parse as immutable model and projector inputs', () {
    for (final pack in ['stt', 'tts']) {
      final lock = jsonDecode(
        File('assets/speech/$pack.json').readAsStringSync(),
      );
      for (final name in ['model', 'projector']) {
        final profile = ValidationProfile.fromJson({
          'schema_version': 1,
          'id': 'speech-$pack-$name',
          'runtime': 'gguf',
          'backend': 'cpu',
          'model': lock[name],
        });
        profile.requireRunnable();
      }
    }
  });
  test(
    'successful lifecycle includes cancellation, rejection and independent reload',
    () async {
      final adapter = FakeSpeech();
      final result = await runSpeechValidation(
        adapter,
        footprintBytes: stableFootprintBytes,
      );
      expect(result['functional_pass'], true);
      expect(result['qualified'], false);
      expect(adapter.calls, [
        'load',
        'execute',
        'cancel_immediate',
        'cancel',
        'execute',
        'invalid',
        'execute',
        'dispose',
        'load',
        'execute',
        for (var cycle = 0; cycle < speechCleanupCycles; cycle++) ...[
          'cancel_immediate',
          'cancel',
          'dispose',
          'load',
          'execute',
        ],
        'dispose',
      ]);
    },
  );
  test('wrong transcript and ignored invalid inputs cannot pass', () async {
    for (final adapter in [
      FakeSpeech()..wrongWords = true,
      FakeSpeech()..ignoreInvalid = true,
    ]) {
      expect(
        (await runSpeechValidation(
          adapter,
          footprintBytes: stableFootprintBytes,
        ))['functional_pass'],
        false,
      );
      expect(adapter.calls.last, 'dispose');
    }
  });
  test('load and cleanup failures remain failures', () async {
    for (final adapter in [
      FakeSpeech()..failLoad = true,
      FakeSpeech()..failCleanup = true,
    ]) {
      expect(
        (await runSpeechValidation(
          adapter,
          footprintBytes: stableFootprintBytes,
        ))['functional_pass'],
        false,
      );
      expect(adapter.calls.last, 'dispose');
    }
  });
  test(
    'unmeasured or over-budget cancellation latency fails the run',
    () async {
      final silent = FakeSpeech()..reportCancelLatency = false;
      final unmeasured = await runSpeechValidation(
        silent,
        footprintBytes: stableFootprintBytes,
      );
      expect(unmeasured['functional_pass'], false);
      final unmeasuredChecks = unmeasured['checks'] as List;
      expect(
        unmeasuredChecks.singleWhere((row) => row['id'] == 'cancel')['status'],
        'FAIL',
      );
      expect(
        unmeasuredChecks.singleWhere(
          (row) => row['id'] == 'cancel_latency_bound',
        )['status'],
        'FAIL',
      );

      final slow = FakeSpeech()
        ..cancelLatencyMs = speechCancelLatencyBudgetMs + 1;
      final overBudget = await runSpeechValidation(
        slow,
        footprintBytes: stableFootprintBytes,
      );
      expect(overBudget['functional_pass'], false);
      final bound = (overBudget['checks'] as List).singleWhere(
        (row) => row['id'] == 'cancel_latency_bound',
      );
      expect(bound['status'], 'FAIL');
      expect(bound['worst_ms'], speechCancelLatencyBudgetMs + 1);
      expect(bound['samples_ms'], hasLength(speechCleanupCycles + 1));
      final reported = overBudget['bounds'] as Map;
      expect(reported['cancel_latency_ms']['within_budget'], false);
      expect(
        reported['cancel_latency_ms']['budget'],
        speechCancelLatencyBudgetMs,
      );

      final fast = FakeSpeech()..cancelLatencyMs = speechCancelLatencyBudgetMs;
      final withinBudget = await runSpeechValidation(
        fast,
        footprintBytes: stableFootprintBytes,
      );
      expect(withinBudget['functional_pass'], true);
      expect(
        (withinBudget['bounds'] as Map)['cancel_latency_ms']['within_budget'],
        true,
      );
    },
  );
  test('a cancellation far past the budget fails the run', () async {
    final stalled = FakeSpeech()..cancelLatencyMs = 4000;
    final result = await runSpeechValidation(
      stalled,
      footprintBytes: stableFootprintBytes,
    );
    expect(result['functional_pass'], false);
    final bound = (result['checks'] as List).singleWhere(
      (row) => row['id'] == 'cancel_latency_bound',
    );
    expect(bound['status'], 'FAIL');
    expect(bound['worst_ms'], 4000);
  });
  test('an immediate cancellation far past its budget fails the run', () async {
    final stalled = FakeSpeech()..immediateCancelLatencyMs = 4000;
    final result = await runSpeechValidation(
      stalled,
      footprintBytes: stableFootprintBytes,
    );
    expect(result['functional_pass'], false);
    final checks = result['checks'] as List;
    final bound = checks.singleWhere(
      (row) => row['id'] == 'immediate_cancel_latency_bound',
    );
    expect(bound['status'], 'FAIL');
    expect(bound['worst_ms'], 4000);
    expect(bound['samples_ms'], hasLength(speechCleanupCycles + 1));
    expect(
      checks.singleWhere(
        (row) => row['id'] == 'cancel_latency_bound',
      )['status'],
      'PASS',
    );
    final reported = (result['bounds'] as Map)['immediate_cancel_latency_ms'];
    expect(reported['within_budget'], false);
    expect(reported['budget'], speechImmediateCancelLatencyBudgetMs);

    final atBudget = await runSpeechValidation(
      FakeSpeech()
        ..immediateCancelLatencyMs = speechImmediateCancelLatencyBudgetMs,
      footprintBytes: stableFootprintBytes,
    );
    expect(atBudget['functional_pass'], true);
    expect(
      (atBudget['bounds']
          as Map)['immediate_cancel_latency_ms']['within_budget'],
      true,
    );
  });
  test('a cancellation not issued on hand-back fails', () async {
    final waited = FakeSpeech()..reportImmediate = false;
    final result = await runSpeechValidation(
      waited,
      footprintBytes: stableFootprintBytes,
    );
    expect(result['functional_pass'], false);
    final checks = result['checks'] as List;
    expect(
      checks.singleWhere((row) => row['id'] == 'cancel_immediate')['status'],
      'FAIL',
    );
    expect(
      checks.singleWhere(
        (row) => row['id'] == 'immediate_cancel_latency_bound',
      )['status'],
      'FAIL',
    );
  });
  test('a cancellation not reported in flight fails', () async {
    final early = FakeSpeech()..reportInFlight = false;
    final result = await runSpeechValidation(
      early,
      footprintBytes: stableFootprintBytes,
    );
    expect(result['functional_pass'], false);
    final checks = result['checks'] as List;
    expect(
      checks.singleWhere((row) => row['id'] == 'cancel')['status'],
      'FAIL',
    );
    expect(
      checks.singleWhere(
        (row) => row['id'] == 'cancel_latency_bound',
      )['status'],
      'FAIL',
    );
  });
  test('an in-flight cancellation issued without a wait fails', () async {
    final result = await runSpeechValidation(
      FakeSpeech()..inFlightLeadMs = 0,
      footprintBytes: stableFootprintBytes,
    );
    expect(result['functional_pass'], false);
    final cancel = (result['checks'] as List).singleWhere(
      (row) => row['id'] == 'cancel',
    );
    expect(cancel['status'], 'FAIL');
    expect(cancel['message'], contains('lead time was not measured'));
  });
  test('a latency bound missing a sample fails', () async {
    final result = await runSpeechValidation(
      FakeSpeech()..unmeasuredInFlightCancel = 2,
      footprintBytes: stableFootprintBytes,
    );
    final checks = result['checks'] as List;
    Map<String, Object?> row(String id) =>
        checks.singleWhere((entry) => entry['id'] == id);
    expect(row('cleanup_cycle_1')['status'], 'FAIL');
    expect(row('cancel_latency_bound')['status'], 'FAIL');
    expect(row('cancel_latency_bound')['message'], contains('incomplete'));
    expect(row('immediate_cancel_latency_bound')['status'], 'PASS');
    final bounds = result['bounds'] as Map;
    expect(
      bounds['cancel_latency_ms']['samples'],
      hasLength(speechCleanupCycles),
    );
    expect(bounds['cancel_latency_ms']['within_budget'], false);
  });
  test('one over-budget cancellation among in-budget ones fails', () async {
    List<double> oneOver(double budget, int at) => List.generate(
      speechCleanupCycles + 1,
      (index) => index == at ? budget + 1 : 1,
    );
    final result = await runSpeechValidation(
      FakeSpeech()
        ..cancelLatenciesMs = oneOver(speechCancelLatencyBudgetMs, 1)
        ..immediateCancelLatenciesMs = oneOver(
          speechImmediateCancelLatencyBudgetMs,
          2,
        ),
      footprintBytes: stableFootprintBytes,
    );
    expect(result['functional_pass'], false);
    final checks = result['checks'] as List;
    for (final (id, budget) in [
      ('cancel_latency_bound', speechCancelLatencyBudgetMs),
      ('immediate_cancel_latency_bound', speechImmediateCancelLatencyBudgetMs),
    ]) {
      final bound = checks.singleWhere((row) => row['id'] == id);
      expect(bound['status'], 'FAIL', reason: id);
      expect(bound['worst_ms'], budget + 1, reason: id);
    }
  });
  test('both cancel bounds pass at 500 ms and fail just past it', () async {
    final adapters = <String, FakeSpeech Function(double)>{
      'cancel_latency': (ms) => FakeSpeech()..cancelLatencyMs = ms,
      'immediate_cancel_latency': (ms) =>
          FakeSpeech()..immediateCancelLatencyMs = ms,
    };
    for (final MapEntry(key: name, value: adapter) in adapters.entries) {
      for (final (latency, within) in [
        (499.999, true),
        (500.0, true),
        (500.001, false),
      ]) {
        final reason = '$name at $latency ms';
        final result = await runSpeechValidation(
          adapter(latency),
          footprintBytes: stableFootprintBytes,
        );
        final bound = (result['checks'] as List).singleWhere(
          (row) => row['id'] == '${name}_bound',
        );
        expect(bound['budget_ms'], 500.0, reason: reason);
        expect(bound['status'], within ? 'PASS' : 'FAIL', reason: reason);
        final reported = (result['bounds'] as Map)['${name}_ms'] as Map;
        expect(reported['budget'], 500.0, reason: reason);
        expect(reported['within_budget'], within, reason: reason);
        expect(result['functional_pass'], within, reason: reason);
      }
    }
  });
  test('the in-flight cancel bound reports a lead fraction of 0.5', () async {
    final result = await runSpeechValidation(
      FakeSpeech(),
      footprintBytes: stableFootprintBytes,
    );
    final bound = (result['checks'] as List).singleWhere(
      (row) => row['id'] == 'cancel_latency_bound',
    );
    expect(bound['lead_fraction'], 0.5);
    final reported = (result['bounds'] as Map)['cancel_latency_ms'] as Map;
    expect(reported['lead_fraction'], 0.5);
  });
  test('a cancellation reporting an invalid measurement fails', () async {
    for (final (report, message) in <(Map<String, Object?>, String)>[
      ({'cancelled': false}, 'Cancellation not confirmed'),
      ({'cancel_latency_ms': double.infinity}, 'latency was not measured'),
      ({'cancel_latency_ms': -1.0}, 'latency was not measured'),
      ({'cancel_after_ms': double.nan}, 'lead time was not measured'),
      ({'cancel_after_ms': -1.0}, 'lead time was not measured'),
    ]) {
      final result = await runSpeechValidation(
        FakeSpeech()..inFlightReport = report,
        footprintBytes: stableFootprintBytes,
      );
      expect(result['functional_pass'], false, reason: '$report');
      final cancel = (result['checks'] as List).singleWhere(
        (row) => row['id'] == 'cancel',
      );
      expect(cancel['status'], 'FAIL', reason: '$report');
      expect(cancel['message'], contains(message), reason: '$report');
    }
  });
  test('only the memory bound may skip and still pass the run', () async {
    final skipping = await runSpeechValidation(
      FakeSpeech()..skipGenerate = true,
      footprintBytes: stableFootprintBytes,
    );
    final generate = (skipping['checks'] as List).singleWhere(
      (row) => row['id'] == 'generate',
    );
    expect(generate['status'], 'SKIP');
    expect(skipping['functional_pass'], false);
  });
  test('a failed predicate outranks skipped in the status ladder', () async {
    final hiding = await runSpeechValidation(
      FakeSpeech()
        ..skipGenerate = true
        ..wrongWords = true,
      footprintBytes: stableFootprintBytes,
    );
    final generate = (hiding['checks'] as List).singleWhere(
      (row) => row['id'] == 'generate',
    );
    expect(generate['skipped'], isTrue);
    expect(generate['predicate_passed'], isFalse);
    expect(generate['status'], 'FAIL');
    expect(hiding['functional_pass'], false);
  });
  test('footprint growth past the budget fails the run', () async {
    var sample = 1000;
    final growing = await runSpeechValidation(
      FakeSpeech(),
      footprintBytes: () => sample += 200,
    );
    expect(growing['functional_pass'], false);
    final bound = (growing['checks'] as List).singleWhere(
      (row) => row['id'] == 'peak_memory_bound',
    );
    expect(bound['status'], 'FAIL');
    expect(
      bound['peak_footprint_growth'],
      greaterThan(speechPeakFootprintGrowthBudget),
    );
    expect(bound['growth_budget'], speechPeakFootprintGrowthBudget);
    expect(
      (growing['bounds'] as Map)['peak_footprint_bytes']['measured'],
      true,
    );

    final flat = await runSpeechValidation(
      FakeSpeech(),
      footprintBytes: stableFootprintBytes,
    );
    expect(flat['functional_pass'], true);
    final measured = (flat['bounds'] as Map)['peak_footprint_bytes'] as Map;
    expect(measured['baseline'], 1000);
    expect(measured['peak'], 1000);
    expect(measured['growth'], 1);
    expect(measured['within_budget'], true);
    expect(measured['measurement'], memoryFootprintSource);
  });
  test('memory growth is measured from the first generation', () async {
    final adapter = FakeSpeech();
    final result = await runSpeechValidation(
      adapter,
      footprintBytes: () => adapter.calls.contains('execute') ? 2000 : 1000,
    );
    expect(result['functional_pass'], true);
    final measured = (result['bounds'] as Map)['peak_footprint_bytes'] as Map;
    expect(measured['baseline'], 2000);
    expect(measured['growth'], 1);
    expect(measured['within_budget'], true);
  });
  test('memory growth before reload counts toward the peak', () async {
    final adapter = FakeSpeech();
    final spike = ((speechPeakFootprintGrowthBudget + 1) * 2000).round();
    final result = await runSpeechValidation(
      adapter,
      footprintBytes: () => adapter.calls.last == 'invalid' ? spike : 2000,
    );
    expect(result['functional_pass'], false);
    final bound = (result['checks'] as List).singleWhere(
      (row) => row['id'] == 'peak_memory_bound',
    );
    expect(bound['status'], 'FAIL');
    expect(bound['baseline_footprint_bytes'], 2000);
    expect(bound['peak_footprint_bytes'], spike);
  });
  test('memory growth equal to the budget passes', () async {
    const baseline = 1 << 52;
    final peak = (baseline * speechPeakFootprintGrowthBudget).toInt();
    final adapter = FakeSpeech();
    final result = await runSpeechValidation(
      adapter,
      footprintBytes: () => adapter.calls.last == 'invalid' ? peak : baseline,
    );
    final bound = (result['checks'] as List).singleWhere(
      (row) => row['id'] == 'peak_memory_bound',
    );
    expect(bound['peak_footprint_growth'], speechPeakFootprintGrowthBudget);
    expect(bound['status'], 'PASS');
    expect(result['functional_pass'], true);
  });
  test('memory growth passes at 1.10x and fails just past it', () async {
    const baseline = 1 << 52;
    final atBudget = (baseline * 1.10).toInt();
    for (final (peak, within) in [
      (atBudget - 1, true),
      (atBudget, true),
      (atBudget + 1, false),
    ]) {
      final reason = 'peak offset ${peak - atBudget}';
      final adapter = FakeSpeech();
      final result = await runSpeechValidation(
        adapter,
        footprintBytes: () => adapter.calls.last == 'invalid' ? peak : baseline,
      );
      final bound = (result['checks'] as List).singleWhere(
        (row) => row['id'] == 'peak_memory_bound',
      );
      expect(bound['growth_budget'], 1.10, reason: reason);
      expect(bound['status'], within ? 'PASS' : 'FAIL', reason: reason);
      final reported = (result['bounds'] as Map)['peak_footprint_bytes'] as Map;
      expect(reported['growth_budget'], 1.10, reason: reason);
      expect(reported['within_budget'], within, reason: reason);
      expect(result['functional_pass'], within, reason: reason);
    }
  });
  test('one unmeasurable footprint sample skips the bound', () async {
    final adapter = FakeSpeech();
    final result = await runSpeechValidation(
      adapter,
      footprintBytes: () => adapter.calls.last == 'invalid' ? null : 1000,
    );
    final bound = (result['checks'] as List).singleWhere(
      (row) => row['id'] == 'peak_memory_bound',
    );
    expect(bound['status'], 'SKIP');
    expect(bound['skip_reason'], 'Memory footprint was not measurable');
    expect(result['functional_pass'], true);
    final reported = (result['bounds'] as Map)['peak_footprint_bytes'] as Map;
    expect(reported['measured'], false);
    expect(reported['peak'], isNull);
  });
  test('an unmeasurable footprint skips the bound with a reason', () async {
    final result = await runSpeechValidation(
      FakeSpeech(),
      footprintBytes: () => null,
    );
    final bound = (result['checks'] as List).singleWhere(
      (row) => row['id'] == 'peak_memory_bound',
    );
    expect(bound['status'], 'SKIP');
    expect(bound['skip_reason'], 'Memory footprint was not measurable');
    expect(bound['measurement'], memoryFootprintSource);
    expect(bound.containsKey('peak_footprint_bytes'), isFalse);
    expect(result['functional_pass'], true);
    final reported = (result['bounds'] as Map)['peak_footprint_bytes'] as Map;
    expect(reported['measured'], false);
    expect(reported['within_budget'], isNull);
    expect(reported['peak'], isNull);
    expect(reported['skip_reason'], 'Memory footprint was not measurable');
  });
  test('the default footprint counter measures this platform', () async {
    final result = await runSpeechValidation(FakeSpeech());
    final reported = (result['bounds'] as Map)['peak_footprint_bytes'] as Map;
    expect(memoryFootprintBytes(), isNotNull);
    expect(reported['measured'], true);
    expect(reported['measurement'], memoryFootprintSource);
    expect(reported['baseline'], isPositive);
    expect(reported['peak'], isPositive);
    expect(reported['within_budget'], true);
  });
  test('a run executes exactly these checks, in order', () async {
    final result = await runSpeechValidation(
      FakeSpeech(),
      footprintBytes: stableFootprintBytes,
    );
    expect(speechLifecycleCheckCount, 21);
    expect(
      [for (final row in result['checks'] as List) row['id']],
      [
        'load',
        'generate',
        'cancel_immediate',
        'cancel',
        'after_cancel',
        'invalid_input',
        'after_invalid',
        'reload',
        for (var cycle = 1; cycle <= 8; cycle++) 'cleanup_cycle_$cycle',
        'cancel_latency_bound',
        'immediate_cancel_latency_bound',
        'peak_memory_bound',
        'leak_slope_bound',
        'dispose',
      ],
    );
    expect(result['expected_checks'], 21);
    final leak = (result['bounds'] as Map)['leak_slope'] as Map;
    expect(leak['warmup_cycles'], 1);
    expect(leak['window_cycles'], 7);
    expect(leak['growth_threshold_bytes'], 7 * mib);
  });
  test('leak slope passes at 7 MiB per cycle and fails just past it', () async {
    for (final (perCycle, within) in [(7 * mib, true), (7 * mib + 1, false)]) {
      final reason = 'growth $perCycle bytes per cycle';
      final result = await runSpeechValidation(
        FakeSpeech(),
        footprintBytes: replay(linearCycles(perCycle)),
      );
      final bound = checkRow(result, 'leak_slope_bound');
      expect(bound['status'], within ? 'PASS' : 'FAIL', reason: reason);
      expect(
        bound['cycle_growth_bytes'],
        List.filled(7, perCycle),
        reason: reason,
      );
      expect(bound['slope_bytes_per_cycle'], perCycle, reason: reason);
      expect(bound['growth_threshold_bytes'], 7 * mib, reason: reason);
      final reported = (result['bounds'] as Map)['leak_slope'] as Map;
      expect(reported['slope_bytes_per_cycle'], perCycle, reason: reason);
      expect(reported['measured'], true, reason: reason);
      expect(reported['within_budget'], within, reason: reason);
      expect(checkRow(result, 'peak_memory_bound')['status'], 'PASS');
      expect(result['functional_pass'], within, reason: reason);
    }
  });
  test(
    'the measured LiteRT ASR leak fails the leak slope everywhere',
    () async {
      final leak = parseMib(macosLiteRtAsrMib);
      for (
        var offset = 0;
        offset + speechCleanupCycles < leak.length - 7;
        offset++
      ) {
        final result = await runSpeechValidation(
          FakeSpeech(),
          footprintBytes: replay(mibs(shifted(leak, offset))),
          operatingSystem: 'linux',
          backend: 'cuda',
        );
        final bound = checkRow(result, 'leak_slope_bound');
        expect(bound['status'], 'FAIL', reason: 'offset $offset');
        expect(result['functional_pass'], false, reason: 'offset $offset');
      }
    },
  );
  test(
    'measured Linux CUDA runs pass the leak slope and skip only the ratio',
    () async {
      for (final MapEntry(key: run, value: text) in linuxCudaMib.entries) {
        final series = parseMib(text);
        final exempt = await runSpeechValidation(
          FakeSpeech(),
          footprintBytes: replay(mibs(series)),
          operatingSystem: 'linux',
          backend: 'cuda',
        );
        expect(
          checkRow(exempt, 'leak_slope_bound')['status'],
          'PASS',
          reason: run,
        );
        final ratio = checkRow(exempt, 'peak_memory_bound');
        expect(ratio['status'], 'SKIP', reason: run);
        expect(
          ratio['skip_reason'],
          speechPeakRatioExemption(operatingSystem: 'linux', backend: 'cuda'),
        );
        expect(ratio['peak_footprint_growth'], isA<double>(), reason: run);
        final reported =
            (exempt['bounds'] as Map)['peak_footprint_bytes'] as Map;
        expect(reported['measured'], true, reason: run);
        expect(reported['applies'], false, reason: run);
        expect(reported['within_budget'], isNull, reason: run);
        expect(exempt['functional_pass'], true, reason: run);
      }
    },
  );
  test('measured macOS runs pass both memory bounds everywhere', () async {
    for (final MapEntry(key: run, value: text) in macosMib.entries) {
      final series = parseMib(text);
      for (
        var offset = 0;
        offset + speechCleanupCycles < series.length - 7;
        offset++
      ) {
        final reason = '$run offset $offset';
        final result = await runSpeechValidation(
          FakeSpeech(),
          footprintBytes: replay(mibs(shifted(series, offset))),
          operatingSystem: 'macos',
          backend: run.split('/').last,
        );
        expect(
          checkRow(result, 'peak_memory_bound')['status'],
          'PASS',
          reason: reason,
        );
        expect(
          checkRow(result, 'leak_slope_bound')['status'],
          'PASS',
          reason: reason,
        );
        expect(result['functional_pass'], true, reason: reason);
      }
    }
  });
  test('a single spike passes the leak slope but not the ratio', () async {
    final series = [
      ...List.filled(10, 1000.0),
      1500.0,
      ...List.filled(5, 1000.0),
    ];
    final result = await runSpeechValidation(
      FakeSpeech(),
      footprintBytes: replay(mibs(series)),
    );
    final leak = checkRow(result, 'leak_slope_bound');
    expect(leak['status'], 'PASS');
    expect(leak['cycle_growth_bytes'], [0, 500 * mib, -500 * mib, 0, 0, 0, 0]);
    expect(checkRow(result, 'peak_memory_bound')['status'], 'FAIL');
    expect(result['functional_pass'], false);
  });
  test('growth before cycle 1 does not count toward the leak slope', () async {
    List<double> jumpAt(int index) => [
      for (var i = 0; i < 16; i++) i < index ? 1000.0 : 1300.0,
    ];
    for (final (index, pass) in [(8, true), (9, false)]) {
      final series = jumpAt(index);
      final result = await runSpeechValidation(
        FakeSpeech(),
        footprintBytes: replay(mibs(series)),
        operatingSystem: 'linux',
        backend: 'cuda',
      );
      final leak = checkRow(result, 'leak_slope_bound');
      expect(leak['window_footprint_bytes'], leakWindow(series));
      expect(leak['status'], pass ? 'PASS' : 'FAIL', reason: '$index');
      expect(result['functional_pass'], pass, reason: '$index');
    }
  });
  test('the leak slope fits the footprint of cycles 1-8', () async {
    // One step, from cycle 7 to 8 or from cycle 4 to 5, at the largest size
    // that passes and just past it.
    for (final (index, step, pass) in [
      (15, 84.0, true),
      (15, 84.1, false),
      (12, 36.75, true),
      (12, 36.8, false),
    ]) {
      final series = [
        for (var i = 0; i < 16; i++) i < index ? 1000.0 : 1000.0 + step,
      ];
      final reason = '$step MiB at sample $index';
      final result = await runSpeechValidation(
        FakeSpeech(),
        footprintBytes: replay(mibs(series)),
        operatingSystem: 'linux',
        backend: 'cuda',
      );
      final leak = checkRow(result, 'leak_slope_bound');
      expect(
        leak['window_footprint_bytes'],
        leakWindow(series),
        reason: reason,
      );
      expect(leak['cycle_growth_bytes'], hasLength(7), reason: reason);
      final after = [
        for (var i = index - 8; i < 8; i++) i - 3.5,
      ].reduce((a, b) => a + b);
      expect(
        leak['slope_bytes_per_cycle'],
        closeTo(step * mib * after / 42, 1),
        reason: reason,
      );
      expect(leak['status'], pass ? 'PASS' : 'FAIL', reason: reason);
    }
  });
  test(
    'measured leaks of 12 and 16 MiB per reload fail the leak slope',
    () async {
      for (final MapEntry(key: run, value: text)
          in linuxTrimmedSttLeakMib.entries) {
        final result = await runSpeechValidation(
          FakeSpeech(),
          footprintBytes: replay(mibs(parseMib(text))),
          operatingSystem: 'linux',
          backend: 'cpu',
        );
        final leak = checkRow(result, 'leak_slope_bound');
        expect(leak['status'], 'FAIL', reason: run);
        expect(
          leak['slope_bytes_per_cycle'],
          greaterThan(8.5 * mib),
          reason: run,
        );
        // A rule that failed only when every step grew passed all of them.
        expect(
          (leak['cycle_growth_bytes']! as List).cast<int>().any(
            (step) => step <= speechLeakCycleGrowthBytes,
          ),
          isTrue,
          reason: run,
        );
        if (run.startsWith('arm64')) {
          expect(checkRow(result, 'peak_memory_bound')['status'], 'PASS');
        }
        expect(result['functional_pass'], false, reason: run);
      }
    },
  );
  test('measured slopes separate runs without a leak from leaks', () {
    Iterable<List<double>> offsets(String text) sync* {
      final series = parseMib(text);
      for (
        var offset = 0;
        offset + speechCleanupCycles < series.length - 7;
        offset++
      ) {
        yield shifted(series, offset);
      }
    }

    double slope(List<double> series) =>
        leastSquaresSlope(leakWindow(series)) / mib;
    final clean = {
      for (final MapEntry(key: run, value: text) in {
        ...linuxTrimmedSttMib,
        for (final MapEntry(key: run, value: text) in linuxCpuTtsMib.entries)
          'tts $run': text,
        for (final MapEntry(key: run, value: text) in linuxCudaMib.entries)
          'cuda $run': text,
        for (final MapEntry(key: run, value: text) in macosMib.entries)
          'macos $run': text,
      }.entries)
        run: [
          for (final series in offsets(text)) slope(series),
        ].reduce(math.max),
    };
    final leaks = {
      for (final MapEntry(key: run, value: text)
          in linuxTrimmedSttLeakMib.entries)
        run: slope(parseMib(text)),
      'macos LiteRT ASR': [
        for (final series in offsets(macosLiteRtAsrMib)) slope(series),
      ].reduce(math.min),
    };
    final threshold = speechLeakCycleGrowthBytes / mib;
    expect(
      clean.values.reduce(math.max),
      lessThan(threshold),
      reason: '$clean',
    );
    expect(
      leaks.values.reduce(math.min),
      greaterThan(threshold),
      reason: '$leaks',
    );
  });
  test('measured Linux CPU runs pass both memory bounds', () async {
    for (final MapEntry(key: run, value: text) in {
      ...linuxTrimmedSttMib,
      ...linuxCpuTtsMib,
    }.entries) {
      final result = await runSpeechValidation(
        FakeSpeech(),
        footprintBytes: replay(mibs(parseMib(text))),
        operatingSystem: 'linux',
        backend: 'cpu',
      );
      expect(
        checkRow(result, 'peak_memory_bound')['status'],
        'PASS',
        reason: run,
      );
      expect(
        checkRow(result, 'leak_slope_bound')['status'],
        'PASS',
        reason: run,
      );
      expect(result['functional_pass'], true, reason: run);
    }
  });
  test(
    'LiteRT ASR growth under 7 MiB per cycle is caught only by the ratio',
    () async {
      final series = mibs(parseMib(linuxLiteRtAsrMib));
      final cpu = await runSpeechValidation(
        FakeSpeech(),
        footprintBytes: replay(series),
        operatingSystem: 'linux',
        backend: 'cpu',
      );
      expect(checkRow(cpu, 'leak_slope_bound')['status'], 'PASS');
      final ratio = checkRow(cpu, 'peak_memory_bound');
      expect(ratio['status'], 'FAIL');
      expect(ratio['peak_footprint_growth'], closeTo(582.1 / 485.2, 1e-3));
      expect(cpu['functional_pass'], false);

      // With the ratio exempt, nothing catches it.
      final cuda = await runSpeechValidation(
        FakeSpeech(),
        footprintBytes: replay(series),
        operatingSystem: 'linux',
        backend: 'cuda',
      );
      expect(checkRow(cuda, 'leak_slope_bound')['status'], 'PASS');
      expect(checkRow(cuda, 'peak_memory_bound')['status'], 'SKIP');
      expect(cuda['functional_pass'], true);
    },
  );
  test('the peak ratio is exempt only on Linux CUDA', () {
    expect(
      speechPeakRatioExemption(operatingSystem: 'linux', backend: 'cuda'),
      isNotNull,
    );
    for (final (os, backend) in [
      ('windows', 'cuda'),
      ('linux', 'cpu'),
      ('linux', 'vulkan'),
      ('linux', 'opencl'),
      ('macos', 'metal'),
      ('macos', 'cpu'),
      ('Linux', 'CUDA'),
      (null, 'cuda'),
      ('linux', null),
      (null, null),
    ]) {
      expect(
        speechPeakRatioExemption(operatingSystem: os, backend: backend),
        isNull,
        reason: '$os/$backend',
      );
    }
  });
  test('the measured low-baseline failure still fails the ratio', () async {
    // #633: macOS CPU `tts` whose `generate` sample was low (GB). The issue
    // gives 5.51-5.52 GB for its three cleanup cycles; cycles 4-8 repeat 5.52.
    final series = mibs([
      for (final gb in [
        3.26, 3.71, 3.71, 5.09, 5.15, 5.15, 5.15, 5.50, //
        5.51, 5.52, 5.52, 5.52, 5.52, 5.52,
      ])
        gb * 1024,
    ]);
    final result = await runSpeechValidation(
      FakeSpeech(),
      footprintBytes: replay(series),
      operatingSystem: 'macos',
      backend: 'cpu',
    );
    expect(checkRow(result, 'leak_slope_bound')['status'], 'PASS');
    final ratio = checkRow(result, 'peak_memory_bound');
    expect(ratio['status'], 'FAIL');
    expect(ratio['peak_footprint_growth'], closeTo(5.52 / 3.71, 1e-3));
    expect(result['functional_pass'], false);
  });
  test('an unmeasurable sample skips both memory bounds', () async {
    for (final (os, backend) in [('linux', 'cuda'), (null, null)]) {
      final adapter = FakeSpeech();
      final result = await runSpeechValidation(
        adapter,
        footprintBytes: () => adapter.calls.last == 'invalid' ? null : 1000,
        operatingSystem: os,
        backend: backend,
      );
      for (final id in ['peak_memory_bound', 'leak_slope_bound']) {
        final row = checkRow(result, id);
        expect(row['status'], 'SKIP', reason: '$id $os');
        expect(row['skip_reason'], 'Memory footprint was not measurable');
      }
      final bounds = result['bounds'] as Map;
      expect(bounds['leak_slope']['measured'], false);
      expect(bounds['leak_slope']['within_budget'], isNull);
      expect(bounds['peak_footprint_bytes']['measured'], false);
      expect(result['functional_pass'], true);
    }
  });
  test('a skipped memory bound does not hide another failure', () async {
    final result = await runSpeechValidation(
      FakeSpeech()..cancelLatencyMs = speechCancelLatencyBudgetMs + 1,
      footprintBytes: () => null,
      operatingSystem: 'linux',
      backend: 'cuda',
    );
    expect(checkRow(result, 'leak_slope_bound')['status'], 'SKIP');
    expect(result['functional_pass'], false);
  });
  test('edge fixtures describe the inputs they encode', () {
    final source = File('assets/speech/jfk.wav').readAsBytesSync();
    final fixtures = buildSpeechEdgeFixtures(Uint8List.fromList(source));
    expect(fixtures.map((fixture) => fixture.id), [
      'edge_silence',
      'edge_truncated_riff',
      'edge_stereo_44100',
      'edge_long_boundary',
    ]);
    for (final fixture in fixtures) {
      expect(fixture.bytes.length, lessThanOrEqualTo(speechFixtureByteCap));
      expect(String.fromCharCodes(fixture.bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(fixture.bytes.sublist(8, 12)), 'WAVE');
      expect(
        fixture.rejectionMessage != null,
        fixture.contract == SpeechEdgeContract.typedRejection,
      );
    }
    final byId = {for (final fixture in fixtures) fixture.id: fixture};
    expect(
      byId['edge_silence']!.rejectionMessage,
      'Speech recognition produced an empty transcript.',
    );
    expect(
      byId['edge_truncated_riff']!.contract,
      SpeechEdgeContract.unrelatedTranscriptOrFormatRejection,
    );
    expect(
      speechFixtureSeconds(byId['edge_silence']!.bytes),
      byId['edge_silence']!.seconds,
    );
    expect(
      speechFixtureSeconds(byId['edge_long_boundary']!.bytes),
      byId['edge_long_boundary']!.seconds,
    );
    expect(byId['edge_long_boundary']!.seconds, greaterThan(30));
    expect(
      byId['edge_long_boundary']!.referenceRepeats,
      greaterThanOrEqualTo(2),
    );
    for (final id in ['edge_stereo_44100', 'edge_truncated_riff']) {
      expect(
        () => speechFixtureSeconds(byId[id]!.bytes),
        throwsFormatException,
      );
    }
    final silence = byId['edge_silence']!.bytes;
    expect(silence.sublist(44).every((byte) => byte == 0), isTrue);
    final truncated = byId['edge_truncated_riff']!.bytes;
    expect(truncated, source.sublist(0, truncated.length));
    expect(
      ByteData.sublistView(truncated).getUint32(4, Endian.little) + 8,
      greaterThan(truncated.length),
    );
    final stereo = ByteData.sublistView(byId['edge_stereo_44100']!.bytes);
    expect(stereo.getUint16(22, Endian.little), 2);
    expect(stereo.getUint32(24, Endian.little), 44100);
    for (var frame = 0; frame < 2000; frame++) {
      expect(
        stereo.getInt16(44 + frame * 4, Endian.little),
        stereo.getInt16(46 + frame * 4, Endian.little),
      );
    }
  });
  test('edge contracts credit exactly the outcome they name', () {
    SpeechEdgeFixture fixtureFor(
      SpeechEdgeContract contract, {
      String? rejectionMessage,
    }) => SpeechEdgeFixture(
      id: contract.name,
      bytes: Uint8List(0),
      sampleRateHz: 16000,
      channelCount: 1,
      seconds: 1,
      contract: contract,
      referenceRepeats: 1,
      rationale: 'table',
      rejectionMessage: rejectionMessage,
    );
    const expectedMessage = 'Speech recognition produced an empty transcript.';
    final rejecting = fixtureFor(
      SpeechEdgeContract.typedRejection,
      rejectionMessage: expectedMessage,
    );
    final unrelated = fixtureFor(SpeechEdgeContract.unrelatedTranscript);
    final tolerant = fixtureFor(
      SpeechEdgeContract.unrelatedTranscriptOrFormatRejection,
    );
    final repeated = fixtureFor(SpeechEdgeContract.repeatedReference);

    expect(speechEdgeTranscriptHolds(rejecting, 0), isFalse);
    expect(speechEdgeTranscriptHolds(rejecting, 1), isFalse);
    expect(speechEdgeTranscriptHolds(unrelated, 0), isFalse);
    expect(speechEdgeTranscriptHolds(unrelated, 0.25), isTrue);
    expect(speechEdgeTranscriptHolds(tolerant, 0), isFalse);
    expect(speechEdgeTranscriptHolds(tolerant, 0.25), isTrue);
    expect(speechEdgeTranscriptHolds(repeated, 0), isTrue);
    expect(speechEdgeTranscriptHolds(repeated, 0.25), isFalse);

    bool rejectionHolds(
      SpeechEdgeFixture fixture, {
      required String message,
      required bool isAudioFormat,
    }) => speechEdgeRejectionHolds(
      fixture,
      message: message,
      isAudioFormat: isAudioFormat,
    );
    expect(
      rejectionHolds(rejecting, message: expectedMessage, isAudioFormat: false),
      isTrue,
    );
    expect(
      rejectionHolds(
        rejecting,
        message: 'Speech recognition failed.',
        isAudioFormat: false,
      ),
      isFalse,
    );
    expect(
      rejectionHolds(
        rejecting,
        message: 'Speech recognition failed.',
        isAudioFormat: true,
      ),
      isFalse,
    );
    expect(
      rejectionHolds(tolerant, message: 'bad header', isAudioFormat: true),
      isTrue,
    );
    expect(
      rejectionHolds(tolerant, message: 'bad header', isAudioFormat: false),
      isFalse,
    );
    for (final fixture in [unrelated, repeated]) {
      for (final isAudioFormat in [true, false]) {
        expect(
          rejectionHolds(
            fixture,
            message: expectedMessage,
            isAudioFormat: isAudioFormat,
          ),
          isFalse,
        );
      }
    }
  });
  test('edge fixtures are opt-in and deliberately counted', () async {
    final fixtures = buildSpeechEdgeFixtures(
      Uint8List.fromList(File('assets/speech/jfk.wav').readAsBytesSync()),
    );
    final lifecycleOnly = await runSpeechValidation(
      FakeEdgeSpeech(),
      footprintBytes: stableFootprintBytes,
    );
    expect(lifecycleOnly['expected_checks'], speechLifecycleCheckCount);
    expect(lifecycleOnly['edge_fixture_ids'], isEmpty);
    expect(lifecycleOnly['functional_pass'], true);
    final adapter = FakeEdgeSpeech();
    final withEdges = await runSpeechValidation(
      adapter,
      checkBytes: true,
      edgeFixtures: fixtures,
      footprintBytes: stableFootprintBytes,
    );
    expect(
      withEdges['expected_checks'],
      speechLifecycleCheckCount + 1 + fixtures.length,
    );
    expect(withEdges['functional_pass'], true);
    expect(
      (withEdges['checks'] as List),
      hasLength(withEdges['expected_checks']),
    );
    expect(adapter.calls, [
      'load',
      'execute',
      'execute',
      'cancel_immediate',
      'cancel',
      'execute',
      'invalid',
      'execute',
      for (final fixture in fixtures) 'edge:${fixture.id}',
      'dispose',
      'load',
      'execute',
      for (var cycle = 0; cycle < speechCleanupCycles; cycle++) ...[
        'cancel_immediate',
        'cancel',
        'dispose',
        'load',
        'execute',
      ],
      'dispose',
    ]);
  });
  test(
    'a failing edge fixture cannot pass, and unsupported adapters throw',
    () {
      final fixtures = buildSpeechEdgeFixtures(
        Uint8List.fromList(File('assets/speech/jfk.wav').readAsBytesSync()),
      );
      expect(
        () => runSpeechValidation(FakeSpeech(), edgeFixtures: fixtures),
        throwsArgumentError,
      );
      for (final fixture in fixtures) {
        expectLater(
          runSpeechValidation(
            FakeEdgeSpeech(failEdge: fixture.id),
            edgeFixtures: fixtures,
            footprintBytes: stableFootprintBytes,
          ).then((result) {
            final checks = result['checks'] as List;
            return [
              result['functional_pass'],
              checks.singleWhere((row) => row['id'] == fixture.id)['status'],
            ];
          }),
          completion([false, 'FAIL']),
        );
      }
    },
  );
  const edgeReference = 'and so my fellow americans';
  Map<String, SpeechEdgeFixture> edgeFixturesById() => {
    for (final fixture in buildSpeechEdgeFixtures(
      Uint8List.fromList(File('assets/speech/jfk.wav').readAsBytesSync()),
    ))
      fixture.id: fixture,
  };
  PublicSpeechValidationAdapter edgeAdapter({
    String pack = 'stt',
    List<String> deltas = const <String>[],
    Object? failure,
    FakeSpeechEngine? engine,
    Duration tokenDelay = Duration.zero,
    Duration? laterTokenDelay,
    Stopwatch Function() newStopwatch = Stopwatch.new,
  }) => PublicSpeechValidationAdapter(
    model: 'model.gguf',
    projector: 'mmproj.gguf',
    backend: GpuBackend.cpu,
    pack: pack,
    audio: Uint8List.fromList(List.filled(44, 7)),
    audioSeconds: 1,
    reference: edgeReference,
    saveAudio: (_) async {},
    createEngine: () =>
        engine ??
        FakeSpeechEngine(
          deltas: deltas,
          failure: failure,
          tokenDelay: tokenDelay,
          laterTokenDelay: laterTokenDelay,
        ),
    newStopwatch: newStopwatch,
  );
  Future<Map<String, Object?>> recognizeEdge(
    SpeechEdgeFixture fixture, {
    List<String> deltas = const <String>[],
    Object? failure,
  }) async {
    final adapter = edgeAdapter(deltas: deltas, failure: failure);
    await adapter.load();
    try {
      return await adapter.executeEdge(fixture);
    } finally {
      await adapter.dispose();
    }
  }

  test('edge recognition scores the repeats the fixture demands', () async {
    final byId = edgeFixturesById();
    final stereo = byId['edge_stereo_44100']!;
    final long = byId['edge_long_boundary']!;
    expect(stereo.referenceRepeats, 1);
    expect(long.referenceRepeats, greaterThanOrEqualTo(2));

    final single = await recognizeEdge(stereo, deltas: [edgeReference]);
    expect(single['predicate_passed'], isTrue);
    expect(single['wer'], 0);
    expect(single['transcript'], edgeReference);
    expect(single['reference_repeats'], 1);

    final wrongWords = await recognizeEdge(stereo, deltas: ['ask not why']);
    expect(wrongWords['predicate_passed'], isFalse);
    expect(wrongWords['wer'], greaterThan(0));

    final repeated = await recognizeEdge(
      long,
      deltas: [List.filled(long.referenceRepeats, edgeReference).join(' ')],
    );
    expect(repeated['predicate_passed'], isTrue);
    expect(repeated['wer'], 0);
    expect(repeated['reference_repeats'], long.referenceRepeats);

    for (final repeats in [1, long.referenceRepeats + 1]) {
      final mismatched = await recognizeEdge(
        long,
        deltas: [List.filled(repeats, edgeReference).join(' ')],
      );
      expect(mismatched['predicate_passed'], isFalse);
      expect(mismatched['wer'], greaterThan(0));
    }
  });

  test('edge rejection credits only the outcome the contract names', () async {
    final byId = edgeFixturesById();
    final silence = byId['edge_silence']!;
    final truncated = byId['edge_truncated_riff']!;

    final empty = await recognizeEdge(silence);
    expect(empty['predicate_passed'], isTrue);
    expect(empty['rejected_with'], 'LlamaSpeechException');
    expect(empty['message'], silence.rejectionMessage);
    expect(empty.containsKey('transcript'), isFalse);
    expect(empty.containsKey('wer'), isFalse);

    final otherFailure = await recognizeEdge(
      silence,
      failure: LlamaSpeechException('Speech recognition failed.'),
    );
    expect(otherFailure['predicate_passed'], isFalse);
    expect(otherFailure['rejected_with'], 'LlamaSpeechException');
    expect(otherFailure['message'], 'Speech recognition failed.');

    final transcribedSilence = await recognizeEdge(
      silence,
      deltas: [edgeReference],
    );
    expect(transcribedSilence['predicate_passed'], isFalse);
    expect(transcribedSilence['transcript'], edgeReference);

    final formatRejection = await recognizeEdge(
      truncated,
      failure: LlamaAudioFormatException('Unsupported RIFF header.'),
    );
    expect(formatRejection['predicate_passed'], isTrue);
    expect(formatRejection['rejected_with'], 'LlamaAudioFormatException');

    final plainRejection = await recognizeEdge(
      truncated,
      failure: LlamaSpeechException('Speech recognition failed.'),
    );
    expect(plainRejection['predicate_passed'], isFalse);

    final unrelated = await recognizeEdge(truncated, deltas: ['Answer.']);
    expect(unrelated['predicate_passed'], isTrue);
    expect(unrelated['wer'], greaterThan(0));

    final reproduced = await recognizeEdge(truncated, deltas: [edgeReference]);
    expect(reproduced['predicate_passed'], isFalse);
    expect(reproduced['wer'], 0);
  });

  test('the public adapter cancels a generation that is running', () async {
    final adapter = edgeAdapter(
      deltas: const ['and ', 'so ', 'my ', 'fellow ', 'americans'],
      tokenDelay: const Duration(milliseconds: 20),
      laterTokenDelay: const Duration(milliseconds: 250),
    );
    await adapter.load();
    final generated = await adapter.execute();
    expect(generated['predicate_passed'], isTrue);
    final reference = generated['elapsed_ms']! as double;
    final cancelled = await adapter.execute(cancel: true);
    await adapter.dispose();
    expect(cancelled['cancelled'], isTrue);
    expect(cancelled['cancel_in_flight'], isTrue);
    expect(cancelled['reference_generation_ms'], reference);
    expect(cancelled['cancel_after_ms'], greaterThanOrEqualTo(reference * 0.5));
    expect(cancelled['cancel_latency_ms'], isA<double>());
    expect(cancelled['cancel_latency_ms'], greaterThanOrEqualTo(0));
  });

  test('the TTS adapter records where a cancel landed', () async {
    Future<Map<String, Object?>> cancelInto(
      SynthesisSpeechEngine engine,
    ) async {
      return runInFakeTime((async) async {
        final adapter = edgeAdapter(
          pack: 'tts',
          engine: engine,
          newStopwatch: () => FakeTimeStopwatch(async),
        );
        await adapter.load();
        final reference = await adapter.execute();
        expect(reference.containsKey('progress_events_before_cancel'), isFalse);
        final cancelled = await adapter.execute(cancel: true);
        await adapter.dispose();
        return cancelled;
      });
    }

    final inFinalStep = await cancelInto(
      SynthesisSpeechEngine(
        frameStep: const Duration(milliseconds: 4),
        decodeStep: const Duration(milliseconds: 600),
      ),
    );
    expect(
      inFinalStep['reference_progress_events'],
      SynthesisSpeechEngine.naturalFrames,
    );
    expect(
      inFinalStep['progress_events_before_cancel'],
      SynthesisSpeechEngine.naturalFrames,
    );
    expect(inFinalStep['cancel_after_reference_last_progress'], isTrue);
    expect(inFinalStep['ms_since_last_progress_at_cancel'], greaterThan(100));

    final inFrameStep = await cancelInto(
      SynthesisSpeechEngine(
        frameStep: const Duration(milliseconds: 40),
        decodeStep: const Duration(milliseconds: 4),
      ),
    );
    expect(
      inFrameStep['progress_events_before_cancel'] as int,
      lessThan(SynthesisSpeechEngine.naturalFrames),
    );
    expect(inFrameStep['cancel_after_reference_last_progress'], isFalse);
    expect(inFrameStep['ms_since_last_progress_at_cancel'], lessThan(40));
  });

  test('the TTS cancel check journals where each cancel landed', () async {
    final adapter = edgeAdapter(
      pack: 'tts',
      engine: SynthesisSpeechEngine(
        frameStep: const Duration(milliseconds: 2),
        decodeStep: const Duration(milliseconds: 30),
      ),
    );
    final journal = await runSpeechValidation(
      adapter,
      footprintBytes: stableFootprintBytes,
    );
    final bound =
        (journal['bounds']! as Map)['cancel_latency_ms']!
            as Map<String, Object?>;
    final samples = (bound['samples'] as List).length;
    expect(bound['progress_events_before_cancel'], hasLength(samples));
    expect(bound['after_reference_last_progress'], hasLength(samples));
    expect(
      (bound['progress_events_before_cancel'] as List).every((n) => n is int),
      isTrue,
    );
    final cycle = (journal['checks'] as List).cast<Map>().firstWhere(
      (check) => check['id'] == 'cleanup_cycle_1',
    );
    expect(cycle['progress_events_before_cancel'], isA<int>());
    expect(cycle['cancel_after_reference_last_progress'], isA<bool>());
  });

  test(
    'the public adapter waits the whole cancel lead on millisecond timers',
    () async {
      final cancelled = await runInFakeTime(
        (async) => runZoned(
          () async {
            final adapter = edgeAdapter(
              deltas: const ['and ', 'so ', 'my ', 'fellow ', 'americans'],
              tokenDelay: const Duration(milliseconds: 21),
              laterTokenDelay: const Duration(milliseconds: 250),
              newStopwatch: () => FakeTimeStopwatch(async),
            );
            await adapter.load();
            expect((await adapter.execute())['elapsed_ms'], 105);
            final result = await adapter.execute(cancel: true);
            await adapter.dispose();
            return result;
          },
          zoneSpecification: ZoneSpecification(
            createTimer: (self, parent, zone, duration, callback) =>
                parent.createTimer(
                  zone,
                  Duration(milliseconds: duration.inMilliseconds),
                  callback,
                ),
          ),
        ),
      );
      expect(cancelled['cancel_in_flight'], isTrue);
      expect(
        cancelled['cancel_after_ms'],
        greaterThanOrEqualTo(105 * speechCancelInFlightLeadFraction),
      );
    },
  );

  test('the public adapter cancels on hand-back without waiting', () async {
    final adapter = edgeAdapter(
      deltas: const ['and ', 'so ', 'my ', 'fellow ', 'americans'],
      tokenDelay: const Duration(milliseconds: 40),
    );
    await adapter.load();
    final unreferenced = await adapter.execute(cancelImmediately: true);
    expect(unreferenced['cancel_immediate'], isTrue);
    final generated = await adapter.execute();
    final reference = generated['elapsed_ms']! as double;
    final cancelled = await adapter.execute(cancelImmediately: true);
    await expectLater(
      adapter.execute(cancel: true, cancelImmediately: true),
      throwsArgumentError,
    );
    await adapter.dispose();
    expect(cancelled['cancelled'], isTrue);
    expect(cancelled['cancel_immediate'], isTrue);
    expect(cancelled.containsKey('cancel_in_flight'), isFalse);
    expect(
      cancelled['cancel_after_ms'],
      lessThan(reference * speechCancelInFlightLeadFraction),
    );
    expect(cancelled['cancel_latency_ms'], greaterThanOrEqualTo(0));
  });

  test('the public adapter cancels into its latest generation', () async {
    const cancelAck = Duration(milliseconds: 100);
    for (final pack in ['stt', 'tts']) {
      final adapter = edgeAdapter(
        pack: pack,
        engine: CancellableSpeechEngine(
          completedTokenDelays: const [
            Duration(milliseconds: 40),
            Duration.zero,
          ],
          cancelAckDelay: cancelAck,
        ),
      );
      await adapter.load();
      await adapter.execute();
      final latestWatch = Stopwatch()..start();
      final latest = await adapter.execute();
      latestWatch.stop();
      final cancelled = await adapter.execute(cancel: true);
      await adapter.dispose();
      final reference = latest['elapsed_ms']! as double;
      expect(
        reference,
        lessThanOrEqualTo(latestWatch.elapsedMicroseconds / 1000),
        reason: pack,
      );
      expect(cancelled['reference_generation_ms'], reference, reason: pack);
      expect(cancelled['cancel_in_flight'], isTrue, reason: pack);
      expect(
        cancelled['cancel_latency_ms'],
        greaterThan(cancelAck.inMilliseconds / 2),
        reason: pack,
      );
    }
  });

  test(
    'the public adapter cancels before an instant generation ends',
    () async {
      for (final pack in ['stt', 'tts']) {
        final adapter = edgeAdapter(
          pack: pack,
          engine: CancellableSpeechEngine(
            completedTokenDelays: [Duration.zero],
          ),
        );
        await adapter.load();
        final cancelled = await adapter.execute(cancelImmediately: true);
        await adapter.dispose();
        expect(cancelled['cancelled'], isTrue, reason: pack);
        expect(cancelled['cancel_immediate'], isTrue, reason: pack);
      }
    },
  );

  test(
    'the public adapter throws the failure a started task reports',
    () async {
      final recognition = edgeAdapter(
        failure: LlamaInferenceException('decode failed'),
      );
      await recognition.load();
      await expectLater(
        recognition.execute(),
        throwsA(isA<LlamaInferenceException>()),
      );
      await recognition.dispose();

      final engine = FakeSpeechEngine();
      engine.speechBackend
        ..textToSpeech = qwen3TtsCapabilities
        ..onSynthesize = (_, _) async =>
            throw LlamaTextToSpeechException('codec failed');
      final synthesis = edgeAdapter(pack: 'tts', engine: engine);
      await synthesis.load();
      await expectLater(
        synthesis.execute(),
        throwsA(isA<LlamaTextToSpeechException>()),
      );
      await synthesis.dispose();
    },
  );

  test('a cancellation with no generation to cancel is refused', () async {
    final adapter = edgeAdapter(deltas: const [edgeReference]);
    await adapter.load();
    await expectLater(adapter.execute(cancel: true), throwsStateError);
    await adapter.dispose();
  });
  test('edge measurement reports the fixture and guards its pack', () async {
    final byId = edgeFixturesById();
    final stereo = byId['edge_stereo_44100']!;
    final engine = FakeSpeechEngine(deltas: [edgeReference]);
    final recorded = edgeAdapter(engine: engine);
    await recorded.load();
    final measured = await recorded.executeEdge(stereo);
    await recorded.dispose();
    expect(engine.audioParts, hasLength(1));
    expect(engine.audioParts.single.bytes, stereo.bytes);
    expect(engine.audioParts.single.path, isNull);
    expect(measured['contract'], stereo.contract.name);
    expect(measured['rationale'], stereo.rationale);
    expect(measured['fixture_bytes'], stereo.bytes.length);
    expect(measured['sample_rate_hz'], 44100);
    expect(measured['channels'], 2);
    expect(measured['audio_seconds'], stereo.seconds);
    expect(measured['elapsed_ms'], isA<double>());

    await expectLater(
      edgeAdapter().executeEdge(stereo),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Speech engine is not loaded',
        ),
      ),
    );

    final tts = edgeAdapter(pack: 'tts');
    await tts.load();
    await expectLater(
      tts.executeEdge(stereo),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Speech edge fixtures require the STT pack',
        ),
      ),
    );
    await tts.dispose();
  });

  test(
    'existing output directory is never modified on CLI rejection',
    () async {
      final directory = Directory.systemTemp.createTempSync('speech-output-');
      try {
        final sentinel = File('${directory.path}/failure.json')
          ..writeAsStringSync('keep');
        final result = await Process.run(Platform.resolvedExecutable, [
          'run',
          'bin/speech.dart',
          '--pack',
          'tts',
          '--out',
          directory.path,
        ]);
        expect(result.exitCode, isNot(0));
        expect(sentinel.readAsStringSync(), 'keep');
        expect(directory.listSync(), hasLength(1));
      } finally {
        directory.deleteSync(recursive: true);
      }
    },
  );

  Map<String, Object?> rowOf(Map<String, Object?> result, String id) =>
      (result['checks'] as List).cast<Map<String, Object?>>().singleWhere(
        (row) => row['id'] == id,
      );
  const interruptIds = [
    'unload_during_synthesis',
    'dispose_during_synthesis',
    'decode_cancel',
  ];
  const limitIds = ['max_output_tokens_truncation', 'context_size_truncation'];

  test(
    'interrupt and limit checks are opt-in and deliberately counted',
    () async {
      final tts = FakeInterruptSpeech();
      final interrupted = await runSpeechValidation(
        tts,
        checkSynthesisInterrupts: true,
        footprintBytes: stableFootprintBytes,
      );
      expect(interrupted['expected_checks'], 25);
      expect(interrupted['checks'], hasLength(25));
      expect(interrupted['functional_pass'], true);
      final ttsIds = [
        for (final row in interrupted['checks'] as List) row['id'] as String,
      ];
      expect(ttsIds.sublist(ttsIds.indexOf('after_invalid') + 1).take(1), [
        'reload',
      ]);
      expect(
        ttsIds.sublist(
          ttsIds.indexOf('peak_memory_bound'),
          ttsIds.indexOf('dispose'),
        ),
        [
          'peak_memory_bound',
          'leak_slope_bound',
          ...interruptIds,
          'interrupt_memory_bound',
        ],
      );
      expect(
        tts.calls.sublist(
          tts.calls.indexOf('unload_synthesis'),
          tts.calls.indexOf('decode_cancel') + 1,
        ),
        ['unload_synthesis', 'dispose_synthesis', 'decode_cancel'],
      );

      final stt = FakeLimitSpeech();
      final limited = await runSpeechValidation(
        stt,
        checkTranscriptLimits: true,
        footprintBytes: stableFootprintBytes,
      );
      expect(limited['expected_checks'], 23);
      expect(limited['functional_pass'], true);
      expect(stt.calls.where((call) => call.startsWith('limit:')), [
        'limit:maxOutputTokens',
        'limit:contextSize',
      ]);
      final sttIds = [
        for (final row in limited['checks'] as List) row['id'] as String,
      ];
      expect(
        sttIds.sublist(
          sttIds.indexOf('after_invalid') + 1,
          sttIds.indexOf('reload'),
        ),
        limitIds,
      );

      final lifecycleOnly = await runSpeechValidation(
        FakeInterruptSpeech(),
        footprintBytes: stableFootprintBytes,
      );
      expect(lifecycleOnly['expected_checks'], speechLifecycleCheckCount);
      expect(
        () => runSpeechValidation(FakeSpeech(), checkSynthesisInterrupts: true),
        throwsArgumentError,
      );
      expect(
        () => runSpeechValidation(FakeSpeech(), checkTranscriptLimits: true),
        throwsArgumentError,
      );
    },
  );

  Future<Map<String, Object?>> interruptMemoryRun(
    int? Function(FakeInterruptSpeech adapter) sample, {
    String? operatingSystem,
    String? backend,
  }) {
    final adapter = FakeInterruptSpeech();
    return runSpeechValidation(
      adapter,
      checkSynthesisInterrupts: true,
      footprintBytes: () => sample(adapter),
      operatingSystem: operatingSystem,
      backend: backend,
    );
  }

  test(
    'footprint growth in the interrupt checks fails only their bound',
    () async {
      for (final persists in [true, false]) {
        var jumped = false;
        final result = await interruptMemoryRun((adapter) {
          final unload = adapter.calls.last == 'unload_synthesis';
          jumped = persists ? jumped || unload : unload;
          return jumped ? 1151 : 1000;
        });
        expect(rowOf(result, 'peak_memory_bound')['status'], 'PASS');
        expect(rowOf(result, 'leak_slope_bound')['status'], 'PASS');
        final bound = rowOf(result, 'interrupt_memory_bound');
        expect(bound['status'], 'FAIL', reason: '$persists');
        expect(bound['baseline_check'], 'leak_slope_bound');
        expect(bound['baseline_footprint_bytes'], 1000);
        expect(bound['peak_footprint_bytes'], 1151);
        expect(bound['growth_budget'], 1.10);
        expect(result['functional_pass'], false, reason: '$persists');
      }
    },
  );

  test(
    'reload growth before the interrupt checks stays in the lifecycle bound',
    () async {
      var reloaded = false;
      final result = await interruptMemoryRun((adapter) {
        reloaded = reloaded || adapter.calls.contains('dispose');
        return reloaded ? 1151 : 1000;
      });
      expect(rowOf(result, 'peak_memory_bound')['status'], 'FAIL');
      final bound = rowOf(result, 'interrupt_memory_bound');
      expect(bound['baseline_footprint_bytes'], 1151);
      expect(bound['peak_footprint_growth'], 1.0);
      expect(bound['status'], 'PASS');
    },
  );

  test(
    'the interrupt memory bound is measured from the leak slope sample',
    () async {
      final ids = [
        for (final row
            in (await interruptMemoryRun((_) => 1000))['checks'] as List)
          row['id'],
      ];
      for (final (lowAfter, status) in [
        ('peak_memory_bound', 'PASS'),
        ('leak_slope_bound', 'FAIL'),
      ]) {
        var sampled = 0;
        final low = ids.indexOf(lowAfter);
        final result = await interruptMemoryRun(
          (_) => sampled++ == low ? 900 : 1000,
        );
        final bound = rowOf(result, 'interrupt_memory_bound');
        expect(bound['status'], status, reason: lowAfter);
        expect(
          bound['baseline_footprint_bytes'],
          lowAfter == 'leak_slope_bound' ? 900 : 1000,
          reason: lowAfter,
        );
      }
    },
  );

  test(
    'the interrupt memory bound skips with the peak ratio on Linux CUDA',
    () async {
      for (final (os, backend) in [
        ('linux', 'cuda'),
        ('windows', 'cuda'),
        ('linux', 'cpu'),
        (null, null),
      ]) {
        final reason = '$os/$backend';
        final exemption = speechPeakRatioExemption(
          operatingSystem: os,
          backend: backend,
        );
        final result = await interruptMemoryRun(
          (adapter) => adapter.calls.last == 'decode_cancel' ? 1151 : 1000,
          operatingSystem: os,
          backend: backend,
        );
        final bound = rowOf(result, 'interrupt_memory_bound');
        expect(
          bound['status'],
          exemption == null ? 'FAIL' : 'SKIP',
          reason: reason,
        );
        expect(bound['skip_reason'], exemption, reason: reason);
        expect(bound['baseline_footprint_bytes'], 1000, reason: reason);
        expect(bound['peak_footprint_bytes'], 1151, reason: reason);
        expect(bound['peak_footprint_growth'], 1.151, reason: reason);
        expect(result['functional_pass'], exemption != null, reason: reason);
      }

      final hidden = await runSpeechValidation(
        FakeInterruptSpeech()..decodeReport = {'uncapped_frames': 1},
        checkSynthesisInterrupts: true,
        footprintBytes: stableFootprintBytes,
        operatingSystem: 'linux',
        backend: 'cuda',
      );
      expect(rowOf(hidden, 'interrupt_memory_bound')['status'], 'SKIP');
      expect(rowOf(hidden, 'decode_cancel')['status'], 'NOT_RUN');
      expect(hidden['functional_pass'], false);
    },
  );

  test(
    'the interrupt memory bound passes at 1.10x and fails past it',
    () async {
      for (final (peak, status) in [(1100, 'PASS'), (1101, 'FAIL')]) {
        final result = await interruptMemoryRun(
          (adapter) => adapter.calls.last == 'decode_cancel' ? peak : 1000,
        );
        expect(
          rowOf(result, 'interrupt_memory_bound')['status'],
          status,
          reason: '$peak',
        );
        expect(result['functional_pass'], status == 'PASS', reason: '$peak');
      }
    },
  );

  test('an unmeasurable interrupt sample skips only that bound', () async {
    final result = await interruptMemoryRun(
      (adapter) => adapter.calls.last == 'dispose_synthesis' ? null : 1000,
    );
    expect(rowOf(result, 'peak_memory_bound')['status'], 'PASS');
    final bound = rowOf(result, 'interrupt_memory_bound');
    expect(bound['status'], 'SKIP');
    expect(bound['skip_reason'], 'Memory footprint was not measurable');
    expect(result['functional_pass'], true);
  });

  test('a teardown that does not cancel a synthesis in flight fails', () async {
    for (final (report, message) in <(Map<String, Object?>, String?)>[
      ({'in_flight': false}, 'not in flight'),
      ({'frames_before_teardown': 0}, 'not in flight'),
      ({'completion_state': 'completed'}, 'did not cancel'),
      ({'final_events': 1}, 'did not cancel'),
      ({'teardown_latency_ms': double.nan}, 'not measured'),
      ({'teardown_latency_ms': null}, 'not measured'),
      (
        {
          'after_teardown': {'predicate_passed': false},
        },
        null,
      ),
      ({'after_teardown': null}, null),
    ]) {
      final result = await runSpeechValidation(
        FakeInterruptSpeech()..teardownReport = report,
        checkSynthesisInterrupts: true,
        footprintBytes: stableFootprintBytes,
      );
      expect(result['functional_pass'], false, reason: '$report');
      for (final id in interruptIds.take(2)) {
        final row = rowOf(result, id);
        expect(row['status'], 'FAIL', reason: '$id $report');
        if (message != null) {
          expect(row['message'], contains(message), reason: '$id $report');
        }
      }
    }
  });

  test('teardown checks pass at 500 ms and fail just past it', () async {
    for (final (latency, within) in [
      (499.999, true),
      (500.0, true),
      (500.001, false),
    ]) {
      final result = await runSpeechValidation(
        FakeInterruptSpeech()
          ..teardownReport = {'teardown_latency_ms': latency},
        checkSynthesisInterrupts: true,
        footprintBytes: stableFootprintBytes,
      );
      for (final id in interruptIds.take(2)) {
        final row = rowOf(result, id);
        expect(row['budget_ms'], 500.0, reason: '$id $latency');
        expect(row['status'], within ? 'PASS' : 'FAIL', reason: '$id $latency');
      }
      expect(result['functional_pass'], within, reason: '$latency');
    }
  });

  Future<Map<String, Object?>> decodeRun(Map<String, Object?> report) =>
      runSpeechValidation(
        FakeInterruptSpeech()..decodeReport = report,
        checkSynthesisInterrupts: true,
        footprintBytes: stableFootprintBytes,
      );
  List<Map<String, Object?>> probes(List<double> latencies) => [
    for (final latency in latencies)
      {
        'completion_state': 'cancelled',
        'final_events': 0,
        'cancel_latency_ms': latency,
      },
  ];
  List<Map<String, Object?>> references(List<Object?> decodes) => [
    for (final decode in decodes)
      {
        'frames': speechDecodeCancelFrameCap,
        'truncated': true,
        'decode_ms': decode,
      },
  ];

  test(
    'a decode cancellation without its preconditions is recorded NOT_RUN',
    () async {
      Map<String, Object?> reference({
        Object? frames = speechDecodeCancelFrameCap,
        Object? truncated = true,
      }) => {'frames': frames, 'truncated': truncated, 'decode_ms': 420.0};
      final passing = FakeInterruptSpeech.passingDecode();
      final probe = (passing['overhead_probes'] as List).first as Map;
      final refs = (passing['references'] as List).cast<Object?>();
      for (final (report, reason) in <(Map<String, Object?>, String)>[
        ({'uncapped_frames': speechDecodeCancelFrameCap}, 'does not truncate'),
        ({'uncapped_frames': null}, 'does not truncate'),
        ({'frame_cap': speechDecodeCancelFrameCap + 1}, 'does not truncate'),
        ({'overhead_probes': null}, 'measure the overhead'),
        (
          {
            'overhead_probes': probes([1.0, 2.0]),
          },
          'measure the overhead',
        ),
        (
          {
            'overhead_probes': [
              ...probes([1.0, 2.0]),
              {...probe, 'completion_state': 'completed'},
            ],
          },
          'measure the overhead',
        ),
        (
          {
            'overhead_probes': [
              ...probes([1.0, 2.0]),
              {...probe, 'final_events': 1},
            ],
          },
          'measure the overhead',
        ),
        (
          {
            'overhead_probes': probes([1.0, 2.0, double.nan]),
          },
          'measure the overhead',
        ),
        ({'warm_up': null}, 'warm-up synthesis did not stop'),
        ({'warm_up': reference(truncated: false)}, 'warm-up synthesis'),
        ({'warm_up': reference(frames: 11)}, 'warm-up synthesis'),
        (
          {
            'warm_up': {...reference(), 'decode_ms': null},
          },
          'warm-up synthesis',
        ),
        (
          {'references': refs.take(7).toList()},
          'did not stop at the frame cap',
        ),
        ({'references_before_cancel': 2}, 'did not stop at the frame cap'),
        (
          {
            'references': [...refs.take(7), reference(truncated: false)],
          },
          'did not stop at the frame cap',
        ),
        (
          {
            'references': [...refs.take(7), reference(frames: 11)],
          },
          'did not stop at the frame cap',
        ),
        (
          {
            'references': [
              ...refs.take(7),
              ...references([0.0]),
            ],
          },
          'did not stop at the frame cap',
        ),
        (
          {
            'references': [
              ...refs.take(7),
              ...references([null]),
            ],
          },
          'did not stop at the frame cap',
        ),
        ({'cancel_after_decode_start_ms': 44.999}, 'not issued at its lead'),
        ({'cancel_after_decode_start_ms': null}, 'not issued at its lead'),
        ({'frames_before_cancel': null}, 'decoding synthesis'),
        ({'cancel_in_flight': false}, 'decoding synthesis'),
        ({'cancel_latency_ms': double.infinity}, 'not measured'),
        ({'cancel_latency_ms': null}, 'not measured'),
      ]) {
        final result = await decodeRun(report);
        final row = rowOf(result, 'decode_cancel');
        expect(row['status'], 'NOT_RUN', reason: '$report');
        expect(row['not_run_reason'], contains(reason), reason: '$report');
        expect(row.containsKey('predicate_passed'), isFalse, reason: '$report');
        expect(row['frame_cap'], isNotNull, reason: '$report');
        expect(result['functional_pass'], false, reason: '$report');
      }
    },
  );

  test('a decode cancellation that emits a final result fails', () async {
    for (final report in <Map<String, Object?>>[
      {'completion_state': 'completed'},
      {'final_events': 1},
      {'completion_state': 'completed', 'cancel_latency_ms': 300.0},
    ]) {
      final result = await decodeRun(report);
      final row = rowOf(result, 'decode_cancel');
      expect(row['status'], 'FAIL', reason: '$report');
      expect(
        row['failure_reason'],
        contains('final result'),
        reason: '$report',
      );
      expect(result['functional_pass'], false, reason: '$report');
    }
  });

  test(
    'decode cancellation passes only when it ends past the margin early',
    () async {
      for (final (latency, status) in [
        (1.0, 'PASS'),
        (264.999, 'PASS'),
        (265.0, 'FAIL'),
        (265.001, 'FAIL'),
        (400.0, 'FAIL'),
      ]) {
        final result = await decodeRun({'cancel_latency_ms': latency});
        final row = rowOf(result, 'decode_cancel');
        expect(row['reference_decode_ms'], 400.0, reason: '$latency');
        expect(row['reference_spread_ms'], 100.0, reason: '$latency');
        expect(row['margin_ms'], 90.0, reason: '$latency');
        expect(row['cancel_overhead_ms'], 3.0, reason: '$latency');
        expect(row['reference_remainder_ms'], 355.0, reason: '$latency');
        expect(row['cancel_end_ms'], 45.0 + latency, reason: '$latency');
        expect(row['lead_fraction'], 0.1, reason: '$latency');
        expect(row['noise_multiple'], 0.9, reason: '$latency');
        expect(row['margin_floor_fraction'], 0.1, reason: '$latency');
        expect(row['status'], status, reason: '$latency');
        expect(result['functional_pass'], status == 'PASS', reason: '$latency');
      }
    },
  );

  test('decode cancellation margin has a floor of 0.1 of the decode', () async {
    for (final (latency, status) in [(259.999, 'PASS'), (260.0, 'FAIL')]) {
      final result = await decodeRun({
        'references': references([
          400.0,
          400.5,
          401.0,
          400.2,
          400.1,
          400.3,
          400.4,
          400.6,
        ]),
        'cancel_after_decode_start_ms': 100.0,
        'cancel_latency_ms': latency,
      });
      final row = rowOf(result, 'decode_cancel');
      expect(row['margin_ms'], 40.0, reason: '$latency');
      expect(row['status'], status, reason: '$latency');
    }
  });

  test('a decode cancel that saved nothing fails', () async {
    final decodes = [500.0, 450.0, 460.0, 470.0, 400.0, 420.0, 430.0, 440.0];
    for (final decode in decodes) {
      final row = rowOf(
        await decodeRun({'cancel_latency_ms': decode - 45.0}),
        'decode_cancel',
      );
      expect(row['status'], 'FAIL', reason: '$decode');
    }
  });

  test('the decode cancel margin keeps the four-reference false-pass rate', () {
    // A cancellation that saves nothing ends like one more reference decode.
    // It passes when it ends more than the margin before the shortest
    // reference; the floor is left out so only the noise term is compared.
    final random = math.Random(759);
    double gauss() =>
        math.sqrt(-2 * math.log(1 - random.nextDouble())) *
        math.cos(2 * math.pi * random.nextDouble());
    double stall() => -math.log(1 - random.nextDouble());
    final models = <String, double Function()>{
      'gauss': gauss,
      'stall': stall,
      'mixed': () => gauss() + (random.nextDouble() < 0.25 ? 5 * stall() : 0),
      'heavy': () => gauss() / math.sqrt(math.max(1e-9, gauss().abs())),
    };
    double falsePasses(double Function() draw, int references, double k) {
      const trials = 200000;
      var passes = 0;
      for (var trial = 0; trial < trials; trial++) {
        var shortest = double.infinity;
        var longest = double.negativeInfinity;
        for (var run = 0; run < references; run++) {
          final decode = draw();
          shortest = math.min(shortest, decode);
          longest = math.max(longest, decode);
        }
        if (shortest - draw() > k * (longest - shortest)) passes++;
      }
      return passes / trials;
    }

    for (final MapEntry(key: model, value: draw) in models.entries) {
      final before = falsePasses(draw, 4, 2.0);
      final now = falsePasses(
        draw,
        speechDecodeCancelReferenceRuns,
        speechDecodeCancelNoiseMultiple,
      );
      expect(now, lessThanOrEqualTo(before), reason: '$model $now > $before');
    }
  });

  test(
    'a decode left too short to tell a cancellation apart is NOT_RUN',
    () async {
      for (final (report, status) in <(Map<String, Object?>, String)>[
        (
          {
            'overhead_probes': probes([1.0, 264.999, 2.0]),
          },
          'PASS',
        ),
        (
          {
            'overhead_probes': probes([1.0, 265.0, 2.0]),
          },
          'NOT_RUN',
        ),
        (
          {
            'overhead_probes': probes([265.0, 1.0, 2.0]),
          },
          'NOT_RUN',
        ),
        (
          {
            'references': references([
              500.0,
              450.0,
              460.0,
              470.0,
              100.0,
              420.0,
              430.0,
              440.0,
            ]),
          },
          'NOT_RUN',
        ),
        (
          {
            'references': references([
              900.0,
              450.0,
              460.0,
              470.0,
              400.0,
              420.0,
              430.0,
              440.0,
            ]),
          },
          'NOT_RUN',
        ),
      ]) {
        final result = await decodeRun(report);
        final row = rowOf(result, 'decode_cancel');
        expect(row['status'], status, reason: '$report');
        expect(result['functional_pass'], status == 'PASS', reason: '$report');
        if (status == 'NOT_RUN') {
          expect(
            row['not_run_reason'],
            contains('within the margin'),
            reason: '$report',
          );
          expect(row['margin_ms'], isA<double>(), reason: '$report');
          expect(row['cancel_overhead_ms'], isA<double>(), reason: '$report');
        }
      }
    },
  );

  test('transcript prefixes credit only a strict cut of the reference', () {
    const reference = 'And so, my fellow Americans';
    expect(speechTranscriptPrefixHolds(reference, 'and so'), isTrue);
    expect(speechTranscriptPrefixHolds(reference, 'And so, my fel'), isTrue);
    expect(
      speechTranscriptPrefixHolds(reference, 'and so my fellow americ'),
      isTrue,
    );
    expect(speechTranscriptPrefixHolds(reference, ''), isFalse);
    expect(speechTranscriptPrefixHolds(reference, reference), isFalse);
    expect(speechTranscriptPrefixHolds(reference, '$reference and'), isFalse);
    expect(speechTranscriptPrefixHolds(reference, 'and to my'), isFalse);
    expect(speechTranscriptPrefixHolds(reference, 'and so mx'), isFalse);
  });

  test('a transcript limit check without its preconditions fails', () async {
    const maxTokens = LlamaSpeechTranscriptLimit.maxOutputTokens;
    const contextSize = LlamaSpeechTranscriptLimit.contextSize;
    for (final (limit, report, message)
        in <(LlamaSpeechTranscriptLimit, Map<String, Object?>, String?)>[
          (maxTokens, {'transcript_tokens': 11}, 'fits in maxOutputTokens'),
          (maxTokens, {'transcript_tokens': null}, 'fits in maxOutputTokens'),
          (maxTokens, {'max_output_tokens': 0}, 'fits in maxOutputTokens'),
          (contextSize, {'context_size': 4096}, 'context size differs'),
          (contextSize, {'max_output_tokens': 511}, 'context size differs'),
          (maxTokens, {'truncated_limit': 'contextSize'}, 'did not fail'),
          (maxTokens, {'truncated_limit': 'runtime'}, 'reported runtime'),
          (contextSize, {'truncated_limit': 'runtime'}, 'reported runtime'),
          (contextSize, {'truncated_limit': null}, 'did not fail'),
          (maxTokens, {'reference': null}, 'no reference'),
          (contextSize, {'reference_repeats': 0}, 'no reference'),
          (maxTokens, {'partial_transcript': ''}, null),
          (
            maxTokens,
            {'partial_transcript': 'and so my fellow americans'},
            null,
          ),
          (contextSize, {'partial_transcript': 'ask not'}, null),
          (
            maxTokens,
            {
              'after_truncation': {'predicate_passed': false},
            },
            null,
          ),
          (contextSize, {'after_truncation': null}, null),
        ]) {
      final reason = '${limit.name} $report';
      final result = await runSpeechValidation(
        FakeLimitSpeech()..reports[limit] = report,
        checkTranscriptLimits: true,
        footprintBytes: stableFootprintBytes,
      );
      final row = rowOf(
        result,
        limit == maxTokens
            ? 'max_output_tokens_truncation'
            : 'context_size_truncation',
      );
      expect(row['status'], 'FAIL', reason: reason);
      if (message != null) {
        expect(row['message'], contains(message), reason: reason);
      }
      expect(result['functional_pass'], false, reason: reason);
    }
  });

  PublicSpeechValidationAdapter synthesisAdapter(
    SynthesisSpeechEngine engine, {
    Stopwatch Function() newStopwatch = Stopwatch.new,
  }) {
    var created = 0;
    return PublicSpeechValidationAdapter(
      model: 'model.gguf',
      projector: 'mmproj.gguf',
      backend: GpuBackend.cpu,
      pack: 'tts',
      saveAudio: (_) async {},
      createEngine: () {
        created++;
        engine.loaded.add('created:$created');
        return engine;
      },
      newStopwatch: newStopwatch,
    );
  }

  test('the decode cancellation lead survives an early timer', () async {
    await runInFakeTime((async) async {
      final adapter = synthesisAdapter(
        SynthesisSpeechEngine(),
        newStopwatch: () => SlowStopwatch(async),
      );
      await adapter.load();
      await adapter.execute();
      final decode = await adapter.executeDecodeCancel();
      final references = decode['references'] as List;
      final shortest = references
          .map((reference) => (reference['decode_ms'] as num).toDouble())
          .reduce(math.min);
      expect(decode['cancel_in_flight'], isTrue);
      expect(
        decode['cancel_after_decode_start_ms'],
        greaterThanOrEqualTo(shortest * speechDecodeCancelLeadFraction),
      );
      await adapter.dispose();
    });
  });

  test('the public adapter interrupts a synthesis in flight', () async {
    await runInFakeTime((async) async {
      final engine = SynthesisSpeechEngine();
      final adapter = synthesisAdapter(
        engine,
        newStopwatch: () => FakeTimeStopwatch(async),
      );
      await adapter.load();
      expect(await adapter.executeDecodeCancel(), {
        'frame_cap': speechDecodeCancelFrameCap,
        'uncapped_frames': null,
      });
      expect(engine.requestedFrames, isEmpty);
      await adapter.execute();
      final unloaded = await adapter.executeTeardown(dispose: false);
      expect(engine.teardowns, ['unload']);
      expect(unloaded['in_flight'], isTrue);
      expect(unloaded['frames_before_teardown'], 1);
      expect(unloaded['completion_state'], 'cancelled');
      expect(unloaded['final_events'], 0);
      expect(
        unloaded['teardown_latency_ms'],
        lessThan(SynthesisSpeechEngine.decodeDelay.inMilliseconds),
      );
      expect(unloaded['teardown_call_ms'], isA<double>());
      expect((unloaded['after_teardown'] as Map)['predicate_passed'], isTrue);
      expect(engine.loaded.where((path) => path.startsWith('created')), [
        'created:1',
      ]);
      expect(engine.loaded.where((path) => path == 'model.gguf'), hasLength(2));

      final disposed = await adapter.executeTeardown(dispose: true);
      expect(engine.teardowns, ['unload', 'dispose']);
      expect(engine.disposals, 1);
      expect(disposed['completion_state'], 'cancelled');
      expect(engine.loaded.where((path) => path.startsWith('created')), [
        'created:1',
        'created:2',
      ]);

      final runsBefore = engine.requestedFrames.length;
      final decode = await adapter.executeDecodeCancel();
      expect(engine.requestedFrames.sublist(runsBefore), List.filled(13, 12));
      expect(engine.cancelledRuns.sublist(runsBefore), [
        ...List.filled(speechDecodeCancelOverheadRuns, true),
        false,
        ...List.filled(speechDecodeCancelReferenceRuns ~/ 2, false),
        true,
        ...List.filled(speechDecodeCancelReferenceRuns ~/ 2, false),
      ]);
      expect(decode['uncapped_frames'], SynthesisSpeechEngine.naturalFrames);
      final probes = decode['overhead_probes'] as List;
      expect(probes, hasLength(speechDecodeCancelOverheadRuns));
      for (final probe in probes) {
        expect(probe['completion_state'], 'cancelled');
        expect(probe['final_events'], 0);
        expect(
          probe['cancel_latency_ms'],
          lessThan(SynthesisSpeechEngine.decodeDelay.inMilliseconds),
        );
      }
      final references = decode['references'] as List;
      expect(references, hasLength(speechDecodeCancelReferenceRuns));
      expect(
        decode['references_before_cancel'],
        speechDecodeCancelReferenceRuns ~/ 2,
      );
      for (final reference in references) {
        expect(reference['frames'], speechDecodeCancelFrameCap);
        expect(reference['truncated'], isTrue);
        expect(
          reference['decode_ms'],
          greaterThanOrEqualTo(
            SynthesisSpeechEngine.decodeDelay.inMilliseconds,
          ),
        );
      }
      final shortestBefore = references
          .take(speechDecodeCancelReferenceRuns ~/ 2)
          .map((reference) => reference['decode_ms'] as double)
          .reduce(math.min);
      expect(
        decode['cancel_after_decode_start_ms'],
        greaterThanOrEqualTo(shortestBefore * speechDecodeCancelLeadFraction),
      );
      expect(decode['frames_before_cancel'], speechDecodeCancelFrameCap);
      expect(decode['cancel_in_flight'], isTrue);
      expect(decode['completion_state'], 'cancelled');
      expect(decode['final_events'], 0);
      await adapter.dispose();
    });
    final stt = edgeAdapter();
    await stt.load();
    await expectLater(
      stt.executeTeardown(dispose: false),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Synthesis interrupts require the TTS pack',
        ),
      ),
    );
    await stt.dispose();
  });

  test('interrupt checks pass only when the runtime ends the work', () async {
    for (final (engine, failing) in [
      (SynthesisSpeechEngine(), <String>[]),
      (
        SynthesisSpeechEngine(teardownCancels: false),
        ['unload_during_synthesis', 'dispose_during_synthesis'],
      ),
      (SynthesisSpeechEngine(decodeHonoursCancel: false), ['decode_cancel']),
    ]) {
      final result = await runInFakeTime(
        (async) => runSpeechValidation(
          DelegatingSpeech(
            synthesisAdapter(
              engine,
              newStopwatch: () => FakeTimeStopwatch(async),
            ),
          ),
          checkSynthesisInterrupts: true,
          footprintBytes: stableFootprintBytes,
        ),
      );
      final decode = rowOf(result, 'decode_cancel');
      expect(
        decode['reference_decode_ms'],
        SynthesisSpeechEngine.decodeDelay.inMilliseconds,
      );
      expect(decode['reference_spread_ms'], 0);
      for (final id in interruptIds) {
        expect(
          rowOf(result, id)['status'],
          failing.contains(id) ? 'FAIL' : 'PASS',
          reason: '$failing ${rowOf(result, id)}',
        );
      }
      expect(result['functional_pass'], failing.isEmpty, reason: '$failing');
    }
  });

  test(
    'the decode cancel warm-up keeps a cold decode out of the spread',
    () async {
      final result = await runInFakeTime(
        (async) => runSpeechValidation(
          DelegatingSpeech(
            synthesisAdapter(
              SynthesisSpeechEngine(
                coldDecode: const Duration(milliseconds: 50),
              ),
              newStopwatch: () => FakeTimeStopwatch(async),
            ),
          ),
          checkSynthesisInterrupts: true,
          footprintBytes: stableFootprintBytes,
        ),
      );
      final row = rowOf(result, 'decode_cancel');
      expect((row['warm_up'] as Map)['decode_ms'], 350);
      expect(row['reference_decode_ms'], 300);
      expect(row['reference_spread_ms'], 0);
      expect(row['status'], 'PASS');
    },
  );

  test(
    'decode cancellation passes only when it stops the decode, not its tail',
    () async {
      // Linux CUDA shape: 145 ms from the cap report, about half of it after
      // the native decode. A cancel that lands after that decode finished
      // saves nothing.
      for (final (decode, tail, status) in [
        (75, 70, 'PASS'),
        (10, 135, 'FAIL'),
      ]) {
        final result = await runInFakeTime(
          (async) => runSpeechValidation(
            DelegatingSpeech(
              synthesisAdapter(
                SynthesisSpeechEngine(
                  decodeStep: Duration(milliseconds: decode),
                  decodeTail: Duration(milliseconds: tail),
                ),
                newStopwatch: () => FakeTimeStopwatch(async),
              ),
            ),
            checkSynthesisInterrupts: true,
            footprintBytes: stableFootprintBytes,
          ),
        );
        final row = rowOf(result, 'decode_cancel');
        expect(row['reference_decode_ms'], 145, reason: '$decode');
        expect(row['margin_ms'], 14.5, reason: '$decode');
        expect(row['cancel_after_decode_start_ms'], 14.5, reason: '$decode');
        expect(row['completion_state'], 'cancelled', reason: '$decode');
        expect(row['final_events'], 0, reason: '$decode');
        expect(row['status'], status, reason: '$row');
        expect(
          row['saved_ms'],
          status == 'PASS' ? 145 - 14.5 - tail : 0,
          reason: '$decode',
        );
      }
    },
  );

  PublicSpeechValidationAdapter limitAdapter(LimitedRecognitionEngine engine) {
    final wav = Uint8List.fromList(
      File('assets/speech/jfk.wav').readAsBytesSync(),
    );
    return PublicSpeechValidationAdapter(
      model: 'model.gguf',
      projector: 'mmproj.gguf',
      backend: GpuBackend.cpu,
      pack: 'stt',
      audio: wav,
      audioSeconds: speechFixtureSeconds(wav),
      reference: jfkReference,
      saveAudio: (_) async {},
      createEngine: () => engine,
    );
  }

  test('the public adapter rejects an unspecified runtime limit '
      'before engine work', () async {
    final engine = LimitedRecognitionEngine(
      fixtureBytes: File('assets/speech/jfk.wav').lengthSync(),
    );
    final adapter = limitAdapter(engine);
    await expectLater(
      adapter.executeTranscriptLimit(LlamaSpeechTranscriptLimit.runtime),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'diagnostic',
          contains('unspecified runtime transcript limit'),
        ),
      ),
    );
    expect(engine.contextSizes, isEmpty);
    expect(engine.generations, 0);
    expect(engine.maxTokens, isEmpty);
    expect(engine.audioParts, isEmpty);
    await adapter.dispose();
  });

  test('the public adapter drives recognition into each limit', () async {
    final wav = File('assets/speech/jfk.wav').readAsBytesSync();
    final engine = LimitedRecognitionEngine(fixtureBytes: wav.length);
    final adapter = limitAdapter(engine);
    await adapter.load();
    await expectLater(
      adapter.executeTranscriptLimit(
        LlamaSpeechTranscriptLimit.maxOutputTokens,
      ),
      throwsStateError,
    );
    await adapter.execute();
    final byTokens = await adapter.executeTranscriptLimit(
      LlamaSpeechTranscriptLimit.maxOutputTokens,
    );
    final referenceTokens = referenceWords(1).length;
    expect(byTokens['reference_tokens'], referenceTokens);
    expect(byTokens['transcript_tokens'], referenceTokens);
    final limit = (referenceTokens * speechTruncationTokenFraction).floor();
    expect(byTokens['max_output_tokens'], limit);
    expect(engine.maxTokens.skip(1), [limit, 512]);
    expect(byTokens['truncated_limit'], 'maxOutputTokens');
    expect(
      byTokens['partial_transcript'],
      referenceWords(1).take(limit).join(' '),
    );
    expect((byTokens['after_truncation'] as Map)['wer'], 0);

    final byContext = await adapter.executeTranscriptLimit(
      LlamaSpeechTranscriptLimit.contextSize,
    );
    final long = edgeFixturesById()['edge_long_boundary']!;
    expect(engine.contextSizes, [4096, speechTruncationContextSize, 4096]);
    expect(byContext['context_size'], speechTruncationContextSize);
    expect(byContext['max_output_tokens'], 512);
    expect(byContext['reference_repeats'], long.referenceRepeats);
    expect(engine.audioParts[engine.audioParts.length - 2].bytes, long.bytes);
    expect(byContext['truncated_limit'], 'contextSize');
    expect((byContext['after_truncation'] as Map)['wer'], 0);
    await adapter.dispose();
    await expectLater(
      edgeAdapter(
        pack: 'tts',
      ).executeTranscriptLimit(LlamaSpeechTranscriptLimit.contextSize),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Transcript limit checks require the STT pack',
        ),
      ),
    );
  });

  test('limit checks pass only for the typed truncation', () async {
    final wav = File('assets/speech/jfk.wav').readAsBytesSync();
    for (final typed in [true, false]) {
      final result = await runSpeechValidation(
        DelegatingSpeech(
          limitAdapter(
            LimitedRecognitionEngine(fixtureBytes: wav.length, typed: typed),
          ),
        ),
        checkTranscriptLimits: true,
        footprintBytes: stableFootprintBytes,
      );
      for (final id in limitIds) {
        expect(
          rowOf(result, id)['status'],
          typed ? 'PASS' : 'FAIL',
          reason: '$id typed=$typed',
        );
      }
      expect(result['functional_pass'], typed, reason: 'typed=$typed');
    }
  });
}
