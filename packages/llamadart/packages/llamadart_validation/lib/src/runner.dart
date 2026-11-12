import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';

import 'case_catalog.dart';
import 'embedding_backend.dart';
import 'inflight_evidence.dart';
import 'manifest.dart';
import 'npu_evidence.dart';
import 'runtime_environment.dart';
import 'sampler_evidence.dart';
import 'scoring_evidence.dart';
import 'state_evidence.dart';
import 'structured_output_evidence.dart';
import 'tokenization_evidence.dart';
import 'tool_result_media_evidence.dart';

part 'decision_runner.dart';
part 'embedding_runner.dart';
part 'sampler_runner.dart';
part 'scoring_runner.dart';
part 'state_runner.dart';
part 'structured_runner.dart';
part 'tokenization_runner.dart';
part 'tool_result_media_runner.dart';

/// Sink implemented by file, browser and Firebase host adapters.
typedef ValidationEventSink = Future<void> Function(Map<String, dynamic> event);

/// Injectable public-API boundary for model-free harness regression tests.
abstract interface class ValidationEngine {
  /// Whether the adapter executes in a browser, independent of profile input.
  bool get isWeb;
  Future<void> load(String location, ValidationProfile profile);
  Future<void> unload();
  Future<void> dispose();
  void cancel();
  Future<Map<String, dynamic>> diagnostics();
  Future<List<int>> tokenize(String text);
  Future<String> detokenize(List<int> tokens);
  Future<Map<String, dynamic>> generate(
    String prompt,
    ValidationProfile profile, {
    bool raw = false,
    int? maxTokens,
    int? streamBatchTokens,
    int? streamBatchBytes,
    bool cancelAfterFirst = false,
    bool cancelOnListen = false,
    int? cancelAfterMs,
    List<LlamaChatMessage>? history,
    List<String>? stopSequences,
    bool? enableThinking,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    String? grammar,
  });

  /// Streams [first] and, at its first content or thinking delta, starts
  /// [second] without waiting for [first] to end. With [cancelFirst], that
  /// delta cancels [first] before [second] starts; otherwise [first] is
  /// cancelled at its first delta after [second] ends. [secondAfterMs] instead
  /// schedules the second request from listen time, independent of visible output.
  /// Errors are recorded and the timer is disarmed when the first stream ends.
  Future<Map<String, dynamic>> generateOverlapping(
    String first,
    String second,
    ValidationProfile profile, {
    required bool raw,
    required int firstMaxTokens,
    required bool cancelFirst,
    int? secondAfterMs,
  });
}

/// Runs inference through the exported llamadart API on every platform.
class PublicValidationEngine
    with
        _PublicDecisionValidation,
        _PublicStructuredValidation,
        _PublicSamplerValidation,
        _PublicStateValidation,
        _PublicToolResultMediaValidation
    implements ValidationEngine, TokenCountValidationEngine {
  /// Uses the public engine; a factory allows isolated adapter verification.
  /// [decisionHead] and [decisionConfig] are the prepared decision files or
  /// URLs of a decision profile.
  PublicValidationEngine({
    this.npu,
    LlamaEngine Function()? engineFactory,
    this.decisionHead,
    this.decisionConfig,
    this.projector,
  }) : _engineFactory = engineFactory;
  final NpuExecutionMonitor? npu;
  @override
  final String? projector;
  @override
  final String? decisionHead;
  @override
  final String? decisionConfig;
  final LlamaEngine Function()? _engineFactory;
  @override
  final _stateObserver = _StateObserver();
  bool _recordStateUsage = false;
  LlamaEngine _createEngine() =>
      _engineFactory?.call() ??
      LlamaEngine(
        LlamaBackend(),
        observers: _recordStateUsage ? [_stateObserver] : const [],
      );
  @override
  late LlamaEngine _engine = _createEngine();
  @override
  bool get isWeb => const bool.fromEnvironment('dart.library.js_interop');
  bool _disposed = false;

  @override
  Future<void> load(String location, ValidationProfile profile) async {
    requireValidationRuntimeEnvironment();
    _recordStateUsage = profile.focusFeatures.contains('state_persistence');
    profile.requireRunnable(verifiedAndroidNpuHost: npu != null, web: isWeb);
    if (profile.toolResultProjector != null && projector == null) {
      throw LlamaUnsupportedException(
        'Profile ${profile.id} locks a vision projector that this host did '
        'not prepare; run it with validation.dart local.',
      );
    }
    if (_disposed) {
      _engine = _createEngine();
      _disposed = false;
    }
    await LlamaLogging.configure(level: LlamaLogLevel.info);
    await _engine.setModel(
      LlamaModel(
        ModelSource.parse(location),
        projector: projector == null ? null : ModelSource.parse(projector!),
      ),
      params: switch ((profile.loadParams, npu)) {
        (final LiteRtLmModelParams params, final npu?) => params.copyWith(
          dispatchLibDir: npu.dispatchDirectory,
        ),
        (final params, _) => params,
      },
    );
    if (!_engine.isReady) {
      throw StateError('setModel returned without readiness');
    }
  }

  @override
  Future<void> unload() => _engine.unloadModel();
  @override
  Future<void> dispose() async {
    await _decisions?.dispose();
    _decisions = null;
    await _engine.dispose();
    _disposed = true;
  }

  @override
  void cancel() => _engine.cancelGeneration();
  @override
  Future<List<int>> tokenize(String text) =>
      _engine.tokenize(text, addSpecial: false);
  @override
  Future<String> detokenize(List<int> tokens) => _engine.detokenize(tokens);
  @override
  Future<int> getTokenCount(String text) => _engine.getTokenCount(text);

  @override
  Future<Map<String, dynamic>> diagnostics() async => {
    'backend_name': await _engine.getBackendName(),
    'reported_gpu_layers': await _engine.getResolvedGpuLayers(),
    'context_size': await _engine.getContextSize(),
    'model_metadata': await _engine.getMetadata(),
    if (npu != null) 'npu_identity': npu!.identity,
    // These public values can contain selector hints. They are not placement proof.
    'accelerator_execution_verified': false,
    'accelerator_evidence_reason':
        'requires correlated native driver/offload diagnostics',
  };

  @override
  Future<Map<String, dynamic>> generate(
    String prompt,
    ValidationProfile profile, {
    bool raw = false,
    int? maxTokens,
    int? streamBatchTokens,
    int? streamBatchBytes,
    bool cancelAfterFirst = false,
    bool cancelOnListen = false,
    int? cancelAfterMs,
    List<LlamaChatMessage>? history,
    List<String>? stopSequences,
    bool? enableThinking,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    String? grammar,
  }) => _generate(
    prompt,
    profile,
    raw: raw,
    maxTokens: maxTokens,
    streamBatchTokens: streamBatchTokens,
    streamBatchBytes: streamBatchBytes,
    cancelAfterFirst: cancelAfterFirst,
    cancelOnListen: cancelOnListen,
    cancelAfterMs: cancelAfterMs,
    history: history,
    stopSequences: stopSequences,
    enableThinking: enableThinking,
    tools: tools,
    toolChoice: toolChoice,
    grammar: grammar,
  );

  @override
  Future<Map<String, dynamic>> generateOverlapping(
    String first,
    String second,
    ValidationProfile profile, {
    required bool raw,
    required int firstMaxTokens,
    required bool cancelFirst,
    int? secondAfterMs,
  }) async {
    final clock = Stopwatch()..start();
    double? ms(int? us) => us == null ? null : us / 1000;
    Future<Map<String, dynamic>>? secondRun;
    int? secondIssuedUs;
    int? secondEndedUs;
    int? firstCancelUs;
    int? firstEndedUs;
    Timer? secondTimer;
    bool? firstEndedAtSecondIssue;
    var firstDeltasAfterSecondEnded = 0;
    Future<Map<String, dynamic>> capture(
      Future<Map<String, dynamic>> run,
      void Function() onError,
    ) => run.catchError((Object error) {
      onError();
      return <String, dynamic>{
        'error_type': error.runtimeType.toString(),
        'state_exception': error is LlamaStateException,
        'message': redactDiagnostic('$error'),
        'content': '',
        'chunks': 0,
        'stream_completed': false,
      };
    });
    void issueSecond() {
      if (secondRun != null || firstEndedUs != null) return;
      final now = clock.elapsedMicroseconds;
      if (cancelFirst) {
        firstCancelUs = now;
        cancel();
      }
      firstEndedAtSecondIssue = firstEndedUs != null;
      secondIssuedUs = clock.elapsedMicroseconds;
      secondRun = capture(
        _generate(
          second,
          profile,
          raw: raw,
          clock: clock,
          collectMetrics: false,
          onStreamEnd: () => secondEndedUs ??= clock.elapsedMicroseconds,
        ),
        () => secondEndedUs ??= clock.elapsedMicroseconds,
      );
    }

    void onFirstDelta() {
      if (secondRun == null) {
        if (secondAfterMs == null) issueSecond();
        return;
      }
      final now = clock.elapsedMicroseconds;
      if (secondEndedUs == null) return;
      firstDeltasAfterSecondEnded++;
      if (!cancelFirst && firstCancelUs == null) {
        firstCancelUs = now;
        cancel();
      }
    }

    final firstOutput = await capture(
      _generate(
        first,
        profile,
        raw: raw,
        maxTokens: firstMaxTokens,
        clock: clock,
        collectMetrics: false,
        onDelta: onFirstDelta,
        onListen: secondAfterMs == null
            ? null
            : () => secondTimer = Timer(
                Duration(milliseconds: secondAfterMs),
                issueSecond,
              ),
        onStreamEnd: () {
          secondTimer?.cancel();
          firstEndedUs ??= clock.elapsedMicroseconds;
        },
      ),
      () => firstEndedUs ??= clock.elapsedMicroseconds,
    );
    final secondOutput = await secondRun;
    return {
      'first': firstOutput,
      'second': ?secondOutput,
      'cancel_first': cancelFirst,
      'second_after_ms': secondAfterMs,
      'second_issued': secondOutput != null,
      'first_ended_before_second_issued': firstEndedAtSecondIssue,
      'first_cancelled_before_second_issued':
          firstCancelUs != null &&
          secondIssuedUs != null &&
          firstCancelUs! <= secondIssuedUs!,
      'first_deltas_after_second_ended': firstDeltasAfterSecondEnded,
      'timeline_ms': {
        'first_cancel': ms(firstCancelUs),
        'second_issued': ms(secondIssuedUs),
        'second_ended': ms(secondEndedUs),
        'first_ended': ms(firstEndedUs),
      },
    };
  }

  Future<Map<String, dynamic>> _generate(
    String prompt,
    ValidationProfile profile, {
    bool raw = false,
    int? maxTokens,
    int? streamBatchTokens,
    int? streamBatchBytes,
    bool cancelAfterFirst = false,
    bool cancelOnListen = false,
    int? cancelAfterMs,
    List<LlamaChatMessage>? history,
    List<String>? stopSequences,
    bool? enableThinking,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    String? grammar,
    Stopwatch? clock,
    bool collectMetrics = true,
    void Function()? onDelta,
    void Function()? onListen,
    void Function()? onStreamEnd,
  }) async {
    final text = StringBuffer();
    final thinking = StringBuffer();
    final finish = <String>[];
    final toolDeltas = <Map<String, dynamic>>[];
    var toolBytes = 0;
    var ordered = true;
    var chunks = 0;
    Timer? cancelTimer;
    int? firstUs;
    int? cancelUs;
    int? chunksBeforeCancel;
    int? firstDeltaClockUs;
    int? endClockUs;
    final params = profile.generationParams.copyWith(
      maxTokens: maxTokens,
      streamBatchTokenThreshold: streamBatchTokens,
      streamBatchByteThreshold: streamBatchBytes,
      stopSequences: stopSequences,
      grammar: grammar,
    );
    final npuBefore = npu?.snapshot();
    final watch = Stopwatch()..start();
    void requestCancel() {
      if (cancelUs != null) return;
      cancelUs = watch.elapsedMicroseconds;
      chunksBeforeCancel = chunks;
      cancel();
    }

    Stream<T> listened<T>(Stream<T> source) => Stream<T>.multi((controller) {
      final subscription = source.listen(
        controller.addSync,
        onError: controller.addErrorSync,
        onDone: controller.closeSync,
      );
      controller
        ..onPause = subscription.pause
        ..onResume = subscription.resume
        ..onCancel = subscription.cancel;
      onListen?.call();
      if (cancelOnListen) requestCancel();
      if (cancelAfterMs != null) {
        cancelTimer = Timer(
          Duration(milliseconds: cancelAfterMs),
          requestCancel,
        );
      }
    });

    void delta() {
      firstDeltaClockUs ??= clock?.elapsedMicroseconds;
      onDelta?.call();
    }

    void append(String content) {
      if (content.isEmpty) return;
      firstUs ??= watch.elapsedMicroseconds;
      text.write(content);
      if (text.length > 65536) {
        cancel();
        throw StateError('Output exceeded the 64 KiB core limit');
      }
      if (cancelAfterFirst && cancelUs == null) requestCancel();
      delta();
    }

    String? cancellationAbort;
    try {
      if (raw) {
        await for (final piece in listened(
          _engine.generate(prompt, params: params),
        )) {
          chunks++;
          append(piece);
        }
      } else {
        await for (final chunk in listened(
          _engine.create(
            history ??
                [
                  LlamaChatMessage.fromText(
                    role: LlamaChatRole.user,
                    text: prompt,
                  ),
                ],
            params: params,
            enableThinking: enableThinking ?? profile.enableThinking,
            tools: tools,
            toolChoice: toolChoice,
          ),
        )) {
          chunks++;
          for (final choice in chunk.choices) {
            if (choice.index != 0 || finish.isNotEmpty) ordered = false;
            for (final tool
                in choice.delta.toolCalls ?? <LlamaCompletionChunkToolCall>[]) {
              final data = tool.toJson();
              toolBytes += utf8.encode(jsonEncode(data)).length;
              if (toolBytes > 65536) {
                cancel();
                throw StateError('Tool deltas exceeded the 64 KiB core limit');
              }
              toolDeltas.add(data);
            }
            final content = choice.delta.content ?? '';
            append(content);
            final reasoning = choice.delta.thinking ?? '';
            thinking.write(reasoning);
            if (thinking.length > 65536) {
              cancel();
              throw StateError('Thinking exceeded the 64 KiB core limit');
            }
            if (reasoning.isNotEmpty && content.isEmpty) delta();
            if (choice.finishReason != null) finish.add(choice.finishReason!);
          }
        }
      }
    } on LlamaInferenceException catch (error) {
      // The pinned WASM delegate surfaces cancellation as this explicit abort.
      if (cancelUs != null &&
          error.message == 'Generation failed' &&
          '${error.details}' == 'AbortError: Generation was cancelled.') {
        cancellationAbort = error.toString();
      } else {
        rethrow;
      }
    } finally {
      cancelTimer?.cancel();
      endClockUs = clock?.elapsedMicroseconds;
      onStreamEnd?.call();
    }
    watch.stop();
    final npuAfter = npu?.snapshot();
    // Tokenization and diagnostic reads occur after the timed region.
    int? estimatedTokens;
    BackendPerfContextData? perf;
    if (collectMetrics) {
      try {
        estimatedTokens = (await tokenize(text.toString())).length;
      } catch (_) {}
      try {
        perf = await _engine.getPerformanceContext();
      } catch (_) {}
    }
    final wallMs = watch.elapsedMicroseconds / 1000;
    final nativeMs = perf?.decodeMs ?? perf?.evalMs;
    final nativeTokens = perf?.evalTokens;
    return {
      'prompt': prompt,
      if (history != null) 'messages': history.map((m) => m.toJson()).toList(),
      'max_tokens': params.maxTokens,
      'stop_sequences': params.stopSequences,
      'grammar': ?params.grammar,
      'enable_thinking': enableThinking ?? profile.enableThinking,
      'tools': tools?.map((tool) => tool.toJson()).toList(),
      'tool_choice': toolChoice?.name,
      if (npuBefore != null && npuAfter != null)
        'npu_execution': npuGenerationEvidence(npuBefore, npuAfter),
      'content': text.toString(),
      'thinking': thinking.toString(),
      'chunks': chunks,
      'finish_reasons': finish,
      'tool_call_deltas': toolDeltas,
      'stream_completed': cancellationAbort == null,
      'completion_order_valid':
          ordered && (raw ? finish.isEmpty : finish.length == 1),
      'stream_batch_tokens': params.streamBatchTokenThreshold,
      'stream_batch_bytes': params.streamBatchByteThreshold,
      'cancel_requested': cancelUs != null,
      'cancel_on_listen': cancelOnListen,
      'cancel_after_ms': cancelAfterMs,
      'chunks_before_cancel': chunksBeforeCancel,
      'cancel_abort_observed': cancellationAbort != null,
      'cancel_abort': ?cancellationAbort,
      'cancel_to_done_ms': cancelUs == null
          ? null
          : (watch.elapsedMicroseconds - cancelUs!) / 1000,
      if (clock != null)
        'timeline_ms': {
          'first_delta': firstDeltaClockUs == null
              ? null
              : firstDeltaClockUs! / 1000,
          'ended': endClockUs == null ? null : endClockUs / 1000,
        },
      'metrics': {
        'wall_ms': wallMs,
        'ttfa_ms': firstUs == null ? null : firstUs! / 1000,
        'native_ttft_ms': null,
        'estimated_output_tokens': estimatedTokens,
        'token_count_source': collectMetrics
            ? 'retokenized visible output; not stream chunks'
            : null,
        'estimated_wall_tps': wallMs > 0 && estimatedTokens != null
            ? estimatedTokens * 1000 / wallMs
            : null,
        'native_decode_tokens': nativeTokens,
        'native_decode_ms': nativeMs,
        'native_decode_tps':
            nativeMs != null &&
                nativeMs > 0 &&
                nativeTokens != null &&
                nativeTokens > 0
            ? nativeTokens * 1000 / nativeMs
            : null,
        'native_timing_source': perf == null
            ? null
            : 'getPerformanceContext per-request counters',
        'native_prompt_tokens': perf?.promptEvalTokens,
        'native_prompt_ms': perf?.promptEvalMs,
        'missing_native_metrics_reason': perf == null
            ? collectMetrics
                  ? 'backend did not expose counters'
                  : 'not collected while another request can run'
            : null,
      },
    };
  }
}

/// Single model/profile run. Assertion failures do not suppress later cases.
class ValidationRunner {
  ValidationRunner({
    required this.profile,
    required this.engine,
    required this.emit,
    this.caseTimeout = const Duration(seconds: 60),
    this.decisionReference,
    this.embeddingAssets,
    this.stateWorkspaceFactory,
  });

  final ValidationProfile profile;
  final ValidationEngine engine;
  final ValidationEventSink emit;
  final Duration caseTimeout;

  /// Host storage is optional; its absence leaves storage cases incomplete.
  final Future<StateValidationWorkspace> Function()? stateWorkspaceFactory;
  Map<String, dynamic> _structuredEnvironment = const {};
  Map<String, dynamic> _structuredPreparation = const {};

  /// Text of the decision fixture's reference file, for decision profiles.
  final String? decisionReference;

  /// Versioned embedding fixture bytes, verified before every embedding case.
  final Map<String, Uint8List>? embeddingAssets;

  /// Cases that reload the model and generate within one deadline.
  static const engineReloadCaseIds = {
    'C09.reload',
    'C09.reload.second',
    'C12.guards',
    'C12.recovery',
  };

  /// Deadline applied to [id]. The profile override, when declared, applies to
  /// [engineReloadCaseIds] and to the [firstUse] case that follows `C01.load`.
  /// The embedding pack instead locks a deadline for every selected case.
  Duration caseDeadline(String id, {bool firstUse = false}) =>
      profile.embeddingCaseTimeout ??
      (firstUse || engineReloadCaseIds.contains(id)
          ? profile.engineCreateCaseTimeout ?? caseTimeout
          : caseTimeout);
  var _sequence = 0;
  var _cancelled = false;
  bool _closed = false;
  bool _poisoned = false;
  bool _settled = true;
  String? _operationPhase;
  Map<String, dynamic>? _partialCaseEvidence;

  /// Request cancellation from the UI or host without marking success.
  void cancel() {
    _cancelled = true;
    engine.cancel();
  }

  /// Expanded obligations shared with the independent report validator.
  List<String> get caseIds => profile.caseIds;

  /// Captures a run without pretending selector diagnostics prove GPU placement.
  Future<void> run(
    String location, {
    required String runId,
    required Map<String, dynamic> environment,
    Map<String, dynamic> preparation = const {},
  }) async {
    _structuredEnvironment = Map<String, dynamic>.from(environment);
    _structuredPreparation = Map<String, dynamic>.from(preparation);
    try {
      await emit({
        'type': 'manifest',
        'schema_version': 2,
        'run_id': runId,
        'profile': profile.toJson(),
        'profile_hash': jsonHash(profile.toJson()),
        'effective_config': profile.effectiveConfig,
        'config_hash': jsonHash(profile.effectiveConfig),
        'environment': environment,
        'preparation': preparation,
        'case_ids': caseIds,
        'catalog': profile.catalog,
        'catalog_hash': jsonHash(profile.catalog),
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'accelerator_evidence_required': profile.requiresAcceleratorProof,
      });
      var usable = false;
      var poisoned = false;
      var firstUsePending = false;
      for (final id in caseIds) {
        if (profile.isEmbedding && engine.isWeb) {
          await _record(id, 'NOT_RUN', {
            'reason':
                'Embedding pack Web artifact/reference adapter is unqualified',
          });
          continue;
        }
        if (_cancelled || poisoned || (!usable && id != 'C01.load')) {
          await _record(id, 'NOT_RUN', {
            'reason': _cancelled
                ? 'cancelled'
                : poisoned
                ? 'prior_timeout'
                : 'model_load_failed',
          });
          continue;
        }
        if (!validationCase(id).implemented) {
          await _record(id, 'NOT_RUN', {
            'reason': 'selected case or reference fixture not implemented',
          });
          continue;
        }
        await emit({
          'type': 'case_start',
          'case_id': id,
          'sequence': _sequence++,
        });
        final watch = Stopwatch()..start();
        _operationPhase = id;
        _partialCaseEvidence = null;
        final deadline = caseDeadline(id, firstUse: firstUsePending);
        firstUsePending = id == 'C01.load';
        try {
          _settled = false;
          final pending = _runCase(
            id,
            location,
          ).whenComplete(() => _settled = true);
          final actual = await pending.timeout(deadline);
          if (id == 'C01.load') usable = true;
          final status = actual.remove('status') as String? ?? 'PASS';
          await _record(id, status, {
            ...actual,
            'elapsed_ms': watch.elapsedMicroseconds / 1000,
          });
        } on TimeoutException {
          poisoned = true;
          _poisoned = true;
          engine.cancel();
          await _record(id, 'ERROR', {
            'reason': 'case_timeout',
            ...?_partialCaseEvidence,
            'timeout_ms': deadline.inMilliseconds,
            'operation_phase': _operationPhase,
            'elapsed_ms': watch.elapsedMicroseconds / 1000,
          });
        } catch (error) {
          await _record(id, 'ERROR', {
            'reason': 'runtime_exception',
            ...?_partialCaseEvidence,
            'operation_phase': _operationPhase,
            'error_type': error.runtimeType.toString(),
            'message': redactDiagnostic('$error'),
          });
        }
      }
    } finally {
      _closed = true;
      try {
        await engine.dispose().timeout(const Duration(seconds: 10));
        await emit({
          'type': 'cleanup',
          'status': _settled ? 'PASS' : 'ERROR',
          if (!_settled)
            'message': 'Timed-out backend operation has not settled',
          'sequence': _sequence++,
        });
      } catch (error) {
        await emit({
          'type': 'cleanup',
          'status': 'ERROR',
          'sequence': _sequence++,
          'message': redactDiagnostic('$error'),
        });
      }
      await emit({
        'type': 'run_end',
        'sequence': _sequence++,
        'cancelled': _cancelled,
      });
    }
  }

  Future<void> _record(String id, String status, Map<String, dynamic> values) =>
      emit({
        'type': 'case',
        'case_id': id,
        if (id.startsWith('E')) 'feature_id': 'embeddings',
        'case_version': validationCase(id).version,
        'fixture_hash': jsonHash(profile.caseFixtures(id)),
        'status': status,
        'sequence': _sequence++,
        ...values,
      });

  String get _shortPrompt => profile.isChat
      ? profile.fixtureText('hello', 'prompt')
      : profile.fixtureText('raw', 'prompt');

  Future<T> _checked<T>(Future<T> Function() operation) async {
    void check() {
      if (_closed || _poisoned || _cancelled) {
        throw StateError('Case no longer active');
      }
    }

    check();
    final result = await operation();
    check();
    return result;
  }

  Future<Map<String, dynamic>> _batching() async {
    if (profile.nativeReference ||
        profile.backend == 'npu' ||
        (engine.isWeb && profile.runtime != 'litert')) {
      return {
        'status': 'NOT_RUN',
        'reason': profile.nativeReference
            ? 'Direct native control bypasses public worker batching'
            : profile.backend == 'npu'
            ? 'NPU runtime-default sampling has no qualified deterministic parity control'
            : 'GGUF browser worker batching is not a qualified native-worker control',
      };
    }
    final fixture = profile.fixtures['batching'] as Map;
    final tokens = fixture['token_threshold'] as int;
    final bytes = fixture['byte_threshold'] as int;
    final defaults = profile.generationParams;
    Future<Map<String, dynamic>> generate({
      int? tokenThreshold,
      int? byteThreshold,
    }) => _checked(
      () => engine.generate(
        _shortPrompt,
        profile,
        raw: !profile.isChat,
        streamBatchTokens: tokenThreshold,
        streamBatchBytes: byteThreshold,
      ),
    );
    final control = await generate();
    if (engine.isWeb) {
      final rejected = <Map<String, dynamic>>[];
      for (final option in [
        'streamBatchTokenThreshold',
        'streamBatchByteThreshold',
      ]) {
        try {
          final output = await generate(
            tokenThreshold: option == 'streamBatchTokenThreshold'
                ? tokens
                : null,
            byteThreshold: option == 'streamBatchByteThreshold' ? bytes : null,
          );
          rejected.add({'option': option, 'rejected': false, 'output': output});
        } on LlamaUnsupportedException catch (error) {
          rejected.add({
            'option': option,
            'rejected': error.toString().contains(option),
            'error_type': error.runtimeType.toString(),
            'message': redactDiagnostic(error.toString()),
          });
        }
      }
      final recovery = await generate();
      return {
        'control': control,
        'rejected_options': rejected,
        'recovery': recovery,
        'coverage': 'litert_web_native_option_rejection_and_recovery',
        'status':
            rejected.every((entry) => entry['rejected'] == true) &&
                _validBatchOutput(control) &&
                _validBatchOutput(recovery)
            ? 'PASS'
            : 'FAIL',
        'expected':
            'Each native batching option is rejected with a named typed error; default requests still complete',
      };
    }
    final batched = await generate(
      tokenThreshold: tokens,
      byteThreshold: bytes,
    );
    final recovery = await generate();
    final outputs = [control, batched, recovery];
    final configMatches =
        control['stream_batch_tokens'] == defaults.streamBatchTokenThreshold &&
        control['stream_batch_bytes'] == defaults.streamBatchByteThreshold &&
        batched['stream_batch_tokens'] == tokens &&
        batched['stream_batch_bytes'] == bytes &&
        recovery['stream_batch_tokens'] == defaults.streamBatchTokenThreshold &&
        recovery['stream_batch_bytes'] == defaults.streamBatchByteThreshold;
    final equal = outputs.every(
      (output) =>
          output['content'] == control['content'] &&
          output['thinking'] == control['thinking'] &&
          canonicalJson(output['finish_reasons']) ==
              canonicalJson(control['finish_reasons']),
    );
    final tools = outputs.any(
      (output) =>
          output['tool_call_deltas'] is List &&
          (output['tool_call_deltas'] as List).isNotEmpty,
    );
    return {
      'control': control,
      'batched': batched,
      'recovery': recovery,
      'coverage': 'native_text_and_thinking_reconstruction',
      'configurations_verified': configMatches,
      'reconstruction_equal': equal,
      'status': tools
          ? 'NOT_RUN'
          : configMatches && equal && outputs.every(_validBatchOutput)
          ? 'PASS'
          : 'FAIL',
      'expected':
          'Same nonempty content, thinking and finish reasons with ordered completion; default configuration recovers; chunk count may differ',
      if (tools)
        'reason':
            'Tool emissions require the separately qualified C07 tool fixture',
    };
  }

  bool _validBatchOutput(Map<String, dynamic> output) =>
      output['content'] is String &&
      (output['content'] as String).trim().isNotEmpty &&
      output['thinking'] is String &&
      output['finish_reasons'] is List &&
      output['tool_call_deltas'] is List &&
      output['stream_completed'] == true &&
      output['completion_order_valid'] == true &&
      output['cancel_requested'] == false;

  Future<Map<String, dynamic>> _short() => _checked(
    () => engine.generate(_shortPrompt, profile, raw: !profile.isChat),
  );

  Map<String, dynamic> _nonempty(Map<String, dynamic> output) => {
    ...output,
    'expected': 'nonempty finite output',
    'status': (output['content'] as String).trim().isNotEmpty ? 'PASS' : 'FAIL',
  };

  Future<Map<String, dynamic>> _withDiagnostics(
    Map<String, dynamic> output,
  ) async {
    final diagnostics = await _checked(() => engine.diagnostics());
    final name = (diagnostics['backend_name'] as String? ?? '').toLowerCase();
    final runtimeResolved =
        name.startsWith('litert-lm') == (profile.runtime == 'litert');
    final metadata = diagnostics['model_metadata'] as Map? ?? {};
    final wasmCpu =
        name == 'wasm (prototype bridge)' &&
        metadata['llamadart.webgpu.n_gpu_layers'] == '0' &&
        metadata['llamadart.webgpu.core_variant'] == 'wasm32';
    final cpuResolved =
        (name.contains('cpu') || wasmCpu) &&
        !RegExp(r'cuda|metal|vulkan|\bgpu\b|\bnpu\b').hasMatch(name);
    return {
      ...output,
      'diagnostics': diagnostics,
      'status': !runtimeResolved || (profile.backend == 'cpu' && !cpuResolved)
          ? 'FAIL'
          : output['status'] as String? ?? 'PASS',
      if (!runtimeResolved)
        'reason': 'Resolved runtime does not match model format',
      if (runtimeResolved && profile.backend == 'cpu' && !cpuResolved)
        'reason': 'Explicit CPU profile did not resolve to CPU diagnostics',
    };
  }

  ToolDefinition _weatherTool() {
    final fixture = profile.fixtures['tools'] as Map;
    final function = (fixture['tool'] as Map)['function'] as Map;
    final tool = ToolDefinition(
      name: function['name'] as String,
      description: function['description'] as String,
      parameters: [ToolParam.string('city', required: true)],
      handler: (_) async => fixture['response'],
    );
    if (canonicalJson(tool.toJson()) != canonicalJson(fixture['tool'])) {
      throw StateError(
        'Tool fixture schema does not match the public tool definition',
      );
    }
    return tool;
  }

  Future<Map<String, dynamic>> _tools() async {
    final fixture = profile.fixtures['tools'] as Map;
    final tool = _weatherTool();
    final trials = <Map<String, dynamic>>[];
    _partialCaseEvidence = {'trials': trials};
    var passed = true;
    var webRequiredRejected = false;
    for (final mode in [
      ToolChoice.auto,
      ToolChoice.required,
      ToolChoice.none,
    ]) {
      _operationPhase = 'tools.${mode.name}.generate';
      final Map<String, dynamic> output;
      try {
        output = await _checked(
          () => engine.generate(
            fixture['prompt'] as String,
            profile,
            tools: [tool],
            toolChoice: mode,
            enableThinking: false,
            maxTokens: 128,
          ),
        );
      } on LlamaUnsupportedException catch (error) {
        if (!engine.isWeb ||
            mode != ToolChoice.required ||
            !error.message.contains('ToolChoice.required') ||
            !error.message.contains('needs a lazy tool-call grammar')) {
          rethrow;
        }
        webRequiredRejected = true;
        trials.add({
          'tool_choice': mode.name,
          'mode_passed': true,
          'documented_web_rejection': true,
          'message': redactDiagnostic(error.message),
        });
        continue;
      }
      final deltas = output['tool_call_deltas'] as List;
      final name = StringBuffer();
      final arguments = StringBuffer();
      String? callId;
      var valid = true;
      for (final delta in deltas.cast<Map>()) {
        if (delta['index'] != 0) valid = false;
        if (delta['id'] != null) {
          if (callId != null && callId != delta['id']) valid = false;
          callId = delta['id'] as String;
        }
        final fn = delta['function'] as Map?;
        name.write(fn?['name'] ?? '');
        arguments.write(fn?['arguments'] ?? '');
      }
      Object? decoded;
      if (deltas.isNotEmpty) {
        try {
          decoded = jsonDecode(arguments.toString());
        } on FormatException {
          valid = false;
        }
      }
      final modePassed =
          (mode == ToolChoice.none
              ? _isTextFinish(output['finish_reasons'])
              : canonicalJson(output['finish_reasons']) ==
                    canonicalJson(['tool_calls'])) &&
          output['tool_choice'] == mode.name &&
          output['enable_thinking'] == false &&
          canonicalJson(output['tools']) == canonicalJson([tool.toJson()]) &&
          output['stream_completed'] == true &&
          output['completion_order_valid'] == true &&
          (mode == ToolChoice.none
              ? deltas.isEmpty &&
                    (output['content'] as String).trim().isNotEmpty
              : valid &&
                    deltas.isNotEmpty &&
                    name.toString() == tool.name &&
                    canonicalJson(decoded) ==
                        canonicalJson(fixture['expected_arguments']));
      passed = passed && modePassed;
      final trial = <String, dynamic>{
        ...output,
        'mode_passed': modePassed,
        'reconstructed_name': name.toString(),
        'reconstructed_arguments': decoded,
      };
      trials.add(trial);
      Map<String, dynamic>? followup;
      if (mode != ToolChoice.none && modePassed) {
        final response = await tool.invoke(
          Map<String, dynamic>.from(decoded as Map),
        );
        final prompt =
            'What is the temperature_celsius from the tool result? Reply with only the number.';
        _operationPhase = 'tools.${mode.name}.tool_result_followup';
        final answer = await _checked(
          () => engine.generate(
            prompt,
            profile,
            enableThinking: false,
            tools: [tool],
            toolChoice: ToolChoice.none,
            history: [
              LlamaChatMessage.fromText(
                role: LlamaChatRole.user,
                text: fixture['prompt'] as String,
              ),
              LlamaChatMessage.withContent(
                role: LlamaChatRole.assistant,
                content: [
                  LlamaToolCallContent(
                    id: callId,
                    name: tool.name,
                    arguments: Map<String, dynamic>.from(decoded as Map),
                    rawJson: arguments.toString(),
                  ),
                ],
              ),
              LlamaChatMessage.withContent(
                role: LlamaChatRole.tool,
                content: [
                  LlamaToolResultContent(
                    id: callId,
                    name: tool.name,
                    result: response,
                  ),
                ],
              ),
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt),
            ],
          ),
        );
        passed =
            passed &&
            (answer['content'] as String).trim() ==
                '${(fixture['response'] as Map)['temperature_celsius']}' &&
            (answer['tool_call_deltas'] as List).isEmpty &&
            answer['tool_choice'] == 'none' &&
            canonicalJson(answer['finish_reasons']) ==
                canonicalJson(['stop']) &&
            answer['stream_completed'] == true &&
            answer['completion_order_valid'] == true;
        followup = answer;
      }
      if (followup != null) trial['tool_result_followup'] = followup;
    }
    _operationPhase = 'tools.recovery';
    final recovery = await _short();
    return {
      'trials': trials,
      'recovery': recovery,
      'required_documented_web_rejection': webRequiredRejected,
      'status':
          passed &&
              RegExp(
                profile.fixtureText('hello', 'regex'),
                caseSensitive: false,
              ).hasMatch(recovery['content'] as String) &&
              recovery['stream_completed'] == true &&
              recovery['completion_order_valid'] == true &&
              recovery['tools'] == null &&
              recovery['tool_choice'] == null &&
              (recovery['tool_call_deltas'] as List).isEmpty &&
              (profile.enableThinking || recovery['thinking'] == '') &&
              recovery['enable_thinking'] == profile.enableThinking &&
              _isTextFinish(recovery['finish_reasons'])
          ? 'PASS'
          : 'FAIL',
    };
  }

  /// Whether [finishReasons] is one text finish: `stop`, or `length` when the
  /// answer reached its token budget.
  bool _isTextFinish(Object? finishReasons) =>
      canonicalJson(finishReasons) == canonicalJson(['stop']) ||
      canonicalJson(finishReasons) == canonicalJson(['length']);

  bool _completedText(Map<String, dynamic>? output) =>
      output != null &&
      output['error_type'] == null &&
      output['stream_completed'] == true &&
      output['completion_order_valid'] == true &&
      (output['content'] as String).trim().isNotEmpty;

  Future<Map<String, dynamic>> _earlyCancel() async {
    final cancel = profile.fixtures['cancel'] as Map;
    final deadline = cancel['deadline_ms'] as num;
    _operationPhase = 'cancel_on_listen';
    final cancelled = await _checked(
      () => engine.generate(
        _shortPrompt,
        profile,
        raw: !profile.isChat,
        cancelOnListen: true,
      ),
    );
    _partialCaseEvidence = {'cancelled': cancelled};
    _operationPhase = 'uncancelled_control';
    final control = await _short();
    final duration = cancelled['cancel_to_done_ms'] as num?;
    final issuedEarly =
        cancelled['cancel_requested'] == true &&
        cancelled['cancel_on_listen'] == true &&
        cancelled['chunks_before_cancel'] == 0;
    return {
      'cancelled': cancelled,
      'uncancelled_control': control,
      'cancel_before_first_delta': issuedEarly,
      'deadline_ms': deadline,
      'expected':
          'A request cancelled right after listening ends without output '
          'within the deadline; the same request then completes with output',
      'status': !issuedEarly
          ? 'NOT_RUN'
          : cancelled['stream_completed'] == true &&
                cancelled['completion_order_valid'] == true &&
                cancelled['content'] == '' &&
                cancelled['thinking'] == '' &&
                (cancelled['tool_call_deltas'] as List).isEmpty &&
                duration != null &&
                duration <= deadline &&
                control['cancel_requested'] == false &&
                _completedText(control)
          ? 'PASS'
          : 'FAIL',
      if (!issuedEarly) 'reason': 'Cancel was not issued before any delta',
    };
  }

  Future<Map<String, dynamic>> _overlapping({required bool restart}) async {
    if (engine.isWeb && profile.runtime == 'gguf') {
      return {
        'status': 'NOT_RUN',
        'reason':
            'Only native llama.cpp defines GGUF generation restart and '
            'overlap; the Web bridge does not',
      };
    }
    final cancel = profile.fixtures['cancel'] as Map;
    final prompt = profile.isChat
        ? profile.fixtureText('cancel', 'chat_prompt')
        : profile.fixtureText('raw', 'prompt');
    Map<String, dynamic>? control;
    if (!restart) {
      _operationPhase = 'overlap_control';
      control = await _checked(
        () => engine.generate(
          prompt,
          profile,
          raw: !profile.isChat,
          maxTokens: cancel['max_tokens'] as int,
        ),
      );
    }
    _operationPhase = restart ? 'cancel_then_restart' : 'overlap';
    final pair = await _checked(
      () => engine.generateOverlapping(
        prompt,
        _shortPrompt,
        profile,
        raw: !profile.isChat,
        firstMaxTokens: cancel['max_tokens'] as int,
        cancelFirst: restart,
        secondAfterMs: restart ? null : _inflightDelay(control!),
      ),
    );
    final first = pair['first'] as Map<String, dynamic>;
    final second = pair['second'] as Map<String, dynamic>?;
    final timeline = pair['timeline_ms'] as Map;
    final firstEnded = timeline['first_ended'] as num?;
    final issuedWhileRunning =
        pair['second_issued'] == true &&
        pair['first_ended_before_second_issued'] == false;
    if (restart) {
      final secondFirstDelta =
          (second?['timeline_ms'] as Map?)?['first_delta'] as num?;
      final precondition =
          issuedWhileRunning &&
          pair['first_cancelled_before_second_issued'] == true;
      return {
        ...pair,
        'expected':
            'A request issued right after cancelling a running generation '
            'starts once the cancelled run stops and completes with output',
        'status': !precondition
            ? 'NOT_RUN'
            : first['error_type'] == null &&
                  first['stream_completed'] == true &&
                  first['completion_order_valid'] == true &&
                  _completedText(second) &&
                  firstEnded != null &&
                  secondFirstDelta != null &&
                  secondFirstDelta >= firstEnded
            ? 'PASS'
            : 'FAIL',
        if (!precondition)
          'reason':
              'The second request was not issued after the cancel and before '
              'the cancelled stream ended',
      };
    }
    _partialCaseEvidence = pair;
    _operationPhase = 'overlap_recovery';
    final recovery = await _short();
    final evidence = <String, dynamic>{
      ...pair,
      'uncancelled_control': control,
      'recovery': recovery,
      'expected':
          'A timed request while native generation runs uncancelled fails with '
          'LlamaStateException, the first stream continues and a later request completes',
    };
    final precondition = overlapWindowObserved(evidence);
    return {
      ...evidence,
      'status': !precondition
          ? 'NOT_RUN'
          : validInflightEvidence(
              'C08.overlap',
              evidence,
              deadlineMs: cancel['deadline_ms'] as num,
            )
          ? 'PASS'
          : 'FAIL',
      if (!precondition)
        'reason':
            'The timed request did not settle before the first stream ended',
    };
  }

  int _inflightDelay(Map<String, dynamic> control) {
    final wall = (control['metrics'] as Map?)?['wall_ms'] as num?;
    if (wall == null || !wall.isFinite || wall <= 0) {
      throw StateError(
        'In-flight validation requires a measured control duration',
      );
    }
    final fraction =
        (profile.fixtures['inflight'] as Map)['control_fraction'] as num;
    return math.max(1, (wall * fraction).floor());
  }

  Future<Map<String, dynamic>> _invalidGrammar() async {
    final fixture = profile.fixtures['invalid_grammar'] as Map;
    final watch = Stopwatch()..start();
    Map<String, dynamic>? accepted;
    Map<String, dynamic>? rejection;
    _operationPhase = 'invalid_grammar';
    try {
      accepted = await _checked(
        () => engine.generate(
          profile.fixtureText('raw', 'prompt'),
          profile,
          raw: true,
          grammar: fixture['grammar'] as String,
        ),
      );
    } on LlamaException catch (error) {
      rejection = {
        'error_type': error.runtimeType.toString(),
        'inference_exception': error is LlamaInferenceException,
        'message': redactDiagnostic(error.message),
        'details': error.details == null
            ? null
            : redactDiagnostic('${error.details}'),
        'rejected_after_ms': watch.elapsedMicroseconds / 1000,
      };
    }
    _partialCaseEvidence = {'accepted': accepted, 'rejection': rejection};
    _operationPhase = 'invalid_grammar_recovery';
    final recovery = await _short();
    final contract = engine.isWeb
        ? 'LlamaInferenceException whose details contain '
              '${fixture['web_details_marker']}'
        : 'LlamaInferenceException "${fixture['native_message']}"';
    final rejected =
        rejection != null &&
        rejection['inference_exception'] == true &&
        (engine.isWeb
            ? '${rejection['details']}'.contains(
                fixture['web_details_marker'] as String,
              )
            : rejection['message'] == fixture['native_message']);
    return {
      'accepted': accepted,
      'rejection': rejection,
      'recovery': recovery,
      'expected': '$contract, then a normal request completes',
      'status':
          accepted == null &&
              rejected &&
              recovery['cancel_requested'] == false &&
              _completedText(recovery)
          ? 'PASS'
          : 'FAIL',
    };
  }

  Future<Map<String, dynamic>> _toolsAutoText() async {
    final tool = _weatherTool();
    final output = await _checked(
      () => engine.generate(
        profile.fixtureText('hello', 'prompt'),
        profile,
        tools: [tool],
        toolChoice: ToolChoice.auto,
        enableThinking: false,
        maxTokens: 128,
      ),
    );
    return {
      ...output,
      'expected_regex': profile.fixtureText('hello', 'regex'),
      'expected':
          'ToolChoice.auto with a tool available answers a prompt that needs '
          'no tool in text, without a tool call',
      'status':
          (output['tool_call_deltas'] as List).isEmpty &&
              _isTextFinish(output['finish_reasons']) &&
              RegExp(
                profile.fixtureText('hello', 'regex'),
                caseSensitive: false,
              ).hasMatch(output['content'] as String) &&
              output['tool_choice'] == ToolChoice.auto.name &&
              canonicalJson(output['tools']) ==
                  canonicalJson([tool.toJson()]) &&
              output['enable_thinking'] == false &&
              output['stream_completed'] == true &&
              output['completion_order_valid'] == true
          ? 'PASS'
          : 'FAIL',
    };
  }

  Future<Map<String, dynamic>> _runCase(String id, String location) async {
    if (id.startsWith('E')) return _embeddingCase(id);
    if (id.startsWith('D')) return _decisionCase(id, location);
    if (id.startsWith('S')) return _structuredCase(id);
    if (id.startsWith('P')) return _stateCase(id, location);
    if (id.startsWith('N')) return _scoringCase(id);
    if (id.startsWith('G')) return _samplerCase(id);
    if (id.startsWith('T')) return _tokenizationCase(id);
    if (id.startsWith('M')) return _toolResultMediaCase(id);
    if (profile.nativeReference &&
        [
          'C02.generate',
          'C05.thinking',
          'C07.tools',
          'C07.tools.auto_text',
        ].contains(id)) {
      return {
        'status': 'NOT_RUN',
        'reason': 'Requires public chat feature controls',
      };
    }
    switch (id) {
      case 'C07.tools.auto_text':
        return _toolsAutoText();
      case 'C08.cancel.early':
        return _earlyCancel();
      case 'C08.cancel.restart':
        return _overlapping(restart: true);
      case 'C08.overlap':
        return _overlapping(restart: false);
      case 'C12.grammar':
        return _invalidGrammar();
      case 'C02.generate':
        final output = await _checked(
          () => engine.generate(
            profile.fixtureText('unicode_generation', 'prompt'),
            profile,
            enableThinking: false,
          ),
        );
        final expected = profile.fixtureText('unicode_generation', 'expected');
        return {
          ...output,
          'expected': expected,
          'status':
              output['content'] == expected &&
                  output['thinking'] == '' &&
                  output['enable_thinking'] == false &&
                  output['stream_completed'] == true &&
                  output['completion_order_valid'] == true
              ? 'PASS'
              : 'FAIL',
        };
      case 'C05.thinking':
        final prompt = profile.fixtureText('arithmetic', 'prompt');
        final trials = <Map<String, dynamic>>[];
        for (final enabled in [true, false]) {
          trials.add(
            await _checked(
              () => engine.generate(
                prompt,
                profile,
                enableThinking: enabled,
                maxTokens: 512,
              ),
            ),
          );
        }
        final expected = RegExp(profile.fixtureText('arithmetic', 'regex'));
        return {
          'trials': trials,
          'status':
              trials.every(
                    (trial) =>
                        expected.hasMatch(
                          (trial['content'] as String).trim(),
                        ) &&
                        trial['stream_completed'] == true &&
                        trial['completion_order_valid'] == true,
                  ) &&
                  trials[0]['enable_thinking'] == true &&
                  (trials[0]['thinking'] as String).trim().isNotEmpty &&
                  trials[1]['enable_thinking'] == false &&
                  trials[1]['thinking'] == ''
              ? 'PASS'
              : 'FAIL',
        };
      case 'C07.tools':
        return _tools();
      case 'C01.load':
        _operationPhase = 'public_load';
        await _checked(() => engine.load(location, profile));
        return _withDiagnostics({
          'load_scope': 'public_load_and_readiness',
          'native_initialization_proven': false,
          'initialization_note':
              'Public readiness does not prove eager native initialization; first use may include deferred initialization.',
        });
      case 'C02.unicode':
        final text = profile.fixtureText('unicode', 'input');
        _operationPhase = profile.runtime == 'litert'
            ? 'tokenize_including_possible_deferred_initialization'
            : 'tokenize';
        final tokenizeWatch = Stopwatch()..start();
        final tokens = await _checked(() => engine.tokenize(text));
        tokenizeWatch.stop();
        _operationPhase = 'detokenize';
        final detokenizeWatch = Stopwatch()..start();
        final decoded = await _checked(() => engine.detokenize(tokens));
        detokenizeWatch.stop();
        final prefix = profile.fixtureText('unicode', 'expected_prefix');
        final expected = '$prefix$text';
        return {
          'input': text,
          'tokens': tokens,
          'decoded': decoded,
          'expected': expected,
          'tokenizer_prefix': prefix,
          'tokenize_call_ms': tokenizeWatch.elapsedMicroseconds / 1000,
          'detokenize_call_ms': detokenizeWatch.elapsedMicroseconds / 1000,
          'tokenize_timing_scope': profile.runtime == 'litert'
              ? 'public_call_including_possible_deferred_initialization'
              : 'public_call',
          'status': decoded == expected ? 'PASS' : 'FAIL',
        };
      case 'C03.raw':
        return _nonempty(
          await _checked(
            () => engine.generate(
              profile.fixtureText('raw', 'prompt'),
              profile,
              raw: true,
            ),
          ),
        );
      case 'C04.hello':
      case 'C04.arithmetic':
        final arithmetic = id.endsWith('arithmetic');
        final fixture = arithmetic ? 'arithmetic' : 'hello';
        final prompt = profile.fixtureText(fixture, 'prompt');
        final expected = profile.fixtureText(fixture, 'regex');
        final output = await _checked(() => engine.generate(prompt, profile));
        final text = (output['content'] as String).trim();
        return {
          ...output,
          'expected_regex': expected,
          'status':
              RegExp(expected, caseSensitive: false).hasMatch(text) &&
                  (output['thinking'] as String).isEmpty
              ? 'PASS'
              : 'FAIL',
        };
      case 'C06.history':
      case 'C06.history.public_system_wire':
      case 'C06.history.no_system':
      case 'C06.history.combined':
        final prompt = profile.fixtureText('history', 'prompt');
        final system = profile.fixtureText('history', 'system');
        final literalSystem = id == 'C06.history.public_system_wire';
        final combined = id == 'C06.history.combined';
        final messages = [
          if (id != 'C06.history.no_system')
            LlamaChatMessage.fromText(
              role: LlamaChatRole.system,
              text: literalSystem
                  ? jsonEncode({
                      'role': 'system',
                      'content': [
                        {'type': 'text', 'text': system},
                      ],
                    })
                  : system,
            ),
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: profile.fixtureText('history', 'user'),
          ),
          LlamaChatMessage.fromText(
            role: LlamaChatRole.assistant,
            text: profile.fixtureText('history', 'assistant'),
          ),
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt),
        ];
        final selectedPrompt = combined
            ? messages.map((message) => message.content).join('\n')
            : prompt;
        final output = await _checked(
          () => engine.generate(
            selectedPrompt,
            profile,
            history: combined ? null : messages,
          ),
        );
        return {
          ...output,
          if (profile.historyControls) 'history_control': id,
          'expected': profile.fixtureText('history', 'expected'),
          'status':
              (output['content'] as String).trim() ==
                  profile.fixtureText('history', 'expected')
              ? 'PASS'
              : 'FAIL',
        };
      case 'C08.cancel':
        final prompt = profile.isChat
            ? profile.fixtureText('cancel', 'chat_prompt')
            : profile.fixtureText('raw', 'prompt');
        final control = await _checked(
          () => engine.generate(
            prompt,
            profile,
            raw: !profile.isChat,
            maxTokens: (profile.fixtures['cancel'] as Map)['max_tokens'] as int,
          ),
        );
        final output = await _checked(
          () => engine.generate(
            prompt,
            profile,
            raw: !profile.isChat,
            maxTokens: (profile.fixtures['cancel'] as Map)['max_tokens'] as int,
            cancelAfterFirst: profile.runtime != 'gguf' || engine.isWeb,
            cancelAfterMs: profile.runtime == 'gguf' && !engine.isWeb
                ? _inflightDelay(control)
                : null,
          ),
        );
        final recovery = await _short();
        final evidence = <String, dynamic>{
          ...output,
          'recovery': recovery,
          'uncancelled_control': control,
        };
        final interrupted = cancellationObserved(
          evidence,
          allowAbort: engine.isWeb,
        );
        return {
          ...evidence,
          'interruption_observed': interrupted,
          'status': output['cancel_requested'] != true || !interrupted
              ? 'NOT_RUN'
              : validInflightEvidence(
                  'C08.cancel',
                  evidence,
                  allowAbort: engine.isWeb,
                  deadlineMs:
                      (profile.fixtures['cancel'] as Map)['deadline_ms'] as num,
                )
              ? 'PASS'
              : 'FAIL',
          'reason':
              'requires fewer native decoded tokens or an explicit cancellation abort, '
              'matching control prefix, ordered completion, recovery and bounded cancellation latency',
        };
      case 'C09.reload':
      case 'C09.reload.second':
        await _checked(() => engine.dispose());
        await _checked(() => engine.load(location, profile));
        return _withDiagnostics(_nonempty(await _short()));
      case 'C10.limit':
        final output = await _checked(
          () => engine.generate(
            _shortPrompt,
            profile,
            raw: !profile.isChat,
            maxTokens: (profile.fixtures['limit'] as Map)['max_tokens'] as int,
          ),
        );
        final count =
            (output['metrics'] as Map)['native_decode_tokens'] as num?;
        return {
          ...output,
          'expected': 'at most one native decoded token',
          'status': count == null
              ? 'NOT_RUN'
              : count ==
                    (profile.fixtures['limit']
                        as Map)['expected_native_decode_tokens']
              ? 'PASS'
              : 'FAIL',
          if (count == null)
            'reason': 'native token counter unavailable; chunks are not tokens',
        };
      case 'C11.batching':
        return _batching();
      case 'C10.stop':
        if (profile.nativeReference || !profile.isChat) {
          return {
            'status': 'NOT_RUN',
            'reason': 'Requires public chat generation',
          };
        }
        final prompt = profile.fixtureText('stop', 'prompt');
        final marker = profile.fixtureText('stop', 'marker');
        final control = await _checked(() => engine.generate(prompt, profile));
        final text = control['content'] as String;
        final index = text.indexOf(marker);
        final stopped = await _checked(
          () => engine.generate(prompt, profile, stopSequences: [marker]),
        );
        final recovery = await _short();
        return {
          'control': control,
          'stopped': stopped,
          'recovery': recovery,
          'stop_marker': marker,
          'expected_prefix': index < 0 ? null : text.substring(0, index),
          'status':
              index > 0 &&
                  marker.isNotEmpty &&
                  stopped['content'] == text.substring(0, index) &&
                  stopped['stream_completed'] == true &&
                  stopped['completion_order_valid'] == true &&
                  canonicalJson(stopped['stop_sequences']) ==
                      canonicalJson([marker]) &&
                  (recovery['content'] as String).trim().isNotEmpty
              ? 'PASS'
              : 'FAIL',
        };
      case 'C12.guards':
        if (profile.nativeReference) {
          return {
            'status': 'NOT_RUN',
            'reason': 'Native control bypasses public readiness guards',
          };
        }
        await _checked(() => engine.unload());
        String? rejected;
        try {
          await _short();
        } on LlamaContextException catch (error) {
          rejected = error.runtimeType.toString();
        }
        await _checked(() => engine.load(location, profile));
        final recovery = await _short();
        return _withDiagnostics({
          'rejected_error_type': rejected,
          'recovery': recovery,
          'expected':
              'typed unloaded-engine rejection followed by valid generation',
          'status':
              rejected != null &&
                  (recovery['content'] as String).trim().isNotEmpty
              ? 'PASS'
              : 'FAIL',
        });
      case 'C12.recovery':
        await _checked(() => engine.unload());
        String? errorType;
        try {
          await _checked(() => engine.load('$location.missing', profile));
        } on LlamaException catch (error) {
          errorType = error.runtimeType.toString();
        }
        await _checked(() => engine.unload());
        await _checked(() => engine.load(location, profile));
        final output = await _short();
        return _withDiagnostics({
          ...output,
          'rejected_error_type': errorType,
          'status':
              errorType != null &&
                  (output['content'] as String).trim().isNotEmpty
              ? 'PASS'
              : 'FAIL',
          'expected': 'typed missing-model error and valid recovery',
        });
      case 'B01.warmup':
      case 'B01.1':
      case 'B01.2':
      case 'B01.3':
        final prompt = profile.isChat
            ? profile.fixtureText('benchmark', 'chat_prompt')
            : profile.fixtureText('raw', 'prompt');
        return {
          ..._nonempty(
            await _checked(
              () => engine.generate(prompt, profile, raw: !profile.isChat),
            ),
          ),
          'benchmark': true,
          'warmup': id == 'B01.warmup',
          'cohort': profile.isChat
              ? 'short-generation'
              : 'tiny-packaging-diagnostic',
        };
      default:
        throw StateError('No implementation for catalog case $id');
    }
  }
}

/// Bounds and removes common credential/path material from diagnostic exports.
String redactDiagnostic(String value) {
  final redacted = value
      .replaceAll(
        RegExp(r'bearer\s+[^\s]+', caseSensitive: false),
        'Bearer [redacted]',
      )
      .replaceAll(RegExp(r'https?://[^\s]+\?[^\s]+'), '[signed URL redacted]')
      .replaceAll(RegExp(r'/(?:Users|home)/[^\s/]+'), '/[user]');
  return redacted.length <= 8192
      ? redacted
      : '${redacted.substring(0, 8192)}[truncated]';
}
