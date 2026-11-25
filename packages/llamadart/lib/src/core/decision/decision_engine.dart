import 'dart:async';
import 'dart:typed_data';

import '../../backends/backend.dart';
import '../engine/engine.dart';
import '../engine/engine_capabilities.dart';
import '../engine/llamadart_engine.dart';
import '../engine/engine_observer.dart';
import '../exceptions.dart';
import '../models/config/compute_device.dart';
import '../models/download/model_download_manager.dart';
import '../models/model_file_store.dart';
import '../models/model_format.dart';
import '../models/model_load_options.dart';
import '../models/model_resolver.dart';
import '../models/model_source.dart';
import '../models/model_target_file.dart';
import 'decision_decoder.dart';
import 'decision_key.dart';
import 'decision_model.dart';
import 'decision_model_params.dart';
import 'decision_question.dart';
import 'decision_result.dart';
import 'decision_sequence.dart';

part 'decision_task.dart';

/// Test-only backend factory for the engines `DecisionEngine.load` creates.
LlamaBackend Function()? debugDecisionBackendFactory;

/// Decision-model support of a [LlamaEngine], or of a loaded
/// [DecisionEngine].
class DecisionCapabilities implements EngineCapabilities {
  /// Creates a capability snapshot.
  const DecisionCapabilities({
    required this.isSupported,
    this.unsupportedReason,
    this.backendName,
    this.runtime,
  });

  /// Whether decisions can run: for [DecisionEngine.capabilitiesFor], whether
  /// the engine's backend and loaded model can run decision heads; for
  /// [DecisionEngine.capabilities], whether the engine can answer now.
  @override
  final bool isSupported;

  /// Actionable reason when [isSupported] is false.
  @override
  final String? unsupportedReason;

  /// Active runtime backend label, when the backend reports one.
  @override
  final String? backendName;

  /// The runtime of the loaded encoder, [LlamaRuntime.llamaCpp] for a
  /// supported one, or null when no model is loaded or a custom backend does
  /// not report it.
  final LlamaRuntime? runtime;
}

/// Sequence limits of a loaded decision model and the device its head runs
/// on.
class DecisionModelInfo {
  /// Creates a model description.
  const DecisionModelInfo({
    required this.hiddenSize,
    required this.maxTokens,
    required this.headMaxTokens,
    required this.deviceName,
  });

  /// Hidden size shared by the encoder and the head.
  final int hiddenSize;

  /// Maximum tokens per question sequence, Laya's `max_len`.
  final int maxTokens;

  /// Token budget for the question text and options, Laya's `head_max_len`.
  final int headMaxTokens;

  /// Name of the device the head runs on.
  final String deviceName;
}

/// Answers typed questions about a state with a Laya-style decision model.
///
/// A decision model is a bidirectional encoder GGUF, run by a [LlamaEngine],
/// plus a decision head; see [DecisionModel]. Each question is answered in
/// one encoder pass without generating text.
///
/// [load] creates the [LlamaEngine], loads the whole model and owns it:
/// [dispose] frees everything. [attach] loads a head on an engine that
/// already holds the encoder, for example to share one encoder between
/// several heads, and borrows it: [dispose] frees only the head.
///
/// The API keeps the names of TypeSafe's Jev API
/// (<https://docs.typesafe.ai/>) and Laya's `system_one` format
/// (<https://huggingface.co/convaiinnovations/laya>):
///
/// - *System One* ([systemOne]): answer typed questions about an input in one
///   fast encoder pass per question, without generating text.
/// - *state*: the text or JSON being judged ([DecisionRequest.state]).
/// - *instructions*: the question text ([DecisionQuestion.instructions]).
/// - *criteria*: a question's options: labels with descriptions, ordered
///   levels, or descriptions of yes and no.
/// - *choice*: pick one option ([ChoiceQuestion], [ChoiceAnswer]).
/// - *score*: rate on ordered levels; the answer is the expected level, so it
///   can fall between levels ([ScoreQuestion], [ScoreAnswer]).
/// - *noul*: yes/no; the answer is the probability that the statement is
///   true ([NoulQuestion], [NoulAnswer.noul]).
/// - *confidence*: how sure the model is of an answer, from 0 to 1
///   ([DecisionAnswer.confidence]).
/// - *act probability*: Laya's action signal, which Laya documents as
///   carrying no usable signal yet ([DecisionAnswer.actProbability]).
///
/// Supported on native llama.cpp backends, and on Web with llama-web-bridge
/// assets that include the decision API (apiVersion 1). With bridge assets
/// without decision API version 1, and with the LiteRT-LM backends, [load]
/// and [attach] throw [LlamaUnsupportedException].
///
/// ```dart
/// final decisions = await DecisionEngine.load(
///   DecisionModel(
///     encoder: ModelSource.parse('hf://fr0stbit3/laya-gguf/laya-Q8_0.gguf'),
///     head: ModelSource.parse(
///       'hf://fr0stbit3/laya-gguf/laya-head.safetensors',
///     ),
///   ),
/// );
/// final result = await decisions.systemOne(
///   state: 'Billed twice for March.',
///   questions: {
///     'refund': DecisionQuestion.noul('Does the user request a refund?'),
///   },
/// );
/// print(result.nouls['refund']!.noul);
/// await decisions.dispose();
/// ```
class DecisionEngine implements LlamadartEngine<DecisionCapabilities> {
  DecisionEngine._(
    this._engine,
    this._head,
    this._config,
    this._modelEpoch, {
    required bool ownsEngine,
  }) : _ownsEngine = ownsEngine,
       info = DecisionModelInfo(
         hiddenSize: _head.hiddenSize,
         maxTokens: _config.maxTokens,
         headMaxTokens: _config.headMaxTokens,
         deviceName: _head.deviceName,
       ),
       _spec = DecisionSequenceSpec(
         clsToken: _head.clsToken,
         sepToken: _head.sepToken,
         maskToken: _head.maskToken,
         maskText: _head.maskText,
         maxTokens: _config.maxTokens,
         headMaxTokens: _config.headMaxTokens,
       );

  final LlamaEngine _engine;
  final bool _ownsEngine;
  final BackendDecisionHeadInfo _head;
  final DecisionHeadConfig _config;
  final int? _modelEpoch;
  final DecisionSequenceSpec _spec;
  final Set<DecisionTask<Object>> _tasks = {};
  int _activeCalls = 0;
  Completer<void>? _idle;
  Future<void>? _disposal;

  /// Reports whether [attach] can load a decision head on [engine] now.
  ///
  /// A failed probe is reported as unsupported with its error.
  static Future<DecisionCapabilities> capabilitiesFor(
    LlamaEngine engine,
  ) async {
    final backendName = await _backendNameOf(engine);
    final BackendDecisionCapabilities capabilities;
    try {
      capabilities = await engine.backendDecisionCapabilities;
    } catch (error) {
      return DecisionCapabilities(
        isSupported: false,
        unsupportedReason: 'The decision capability probe failed: $error',
        backendName: backendName,
        runtime: engine.runtime,
      );
    }
    return DecisionCapabilities(
      isSupported: capabilities.isSupported,
      unsupportedReason: capabilities.isSupported
          ? null
          : _unsupportedReason(capabilities),
      backendName: backendName,
      runtime: engine.runtime,
    );
  }

  /// Loads [model] into a new [LlamaEngine] that the returned engine owns.
  ///
  /// Every file of [model] comes from its `ModelSource`, resolved like
  /// `LlamaEngine.load`: [store]'s resolver (by default
  /// [DefaultModelResolver]) resolves it, and its download manager (by
  /// default [DefaultModelDownloadManager]) checks a local file, or downloads
  /// a remote one into the model cache, resuming an interrupted download and
  /// reusing a cached file. Files resolve one at a time, encoder first, and
  /// all before anything loads. [download] applies to every remote file:
  /// cache policy and directory, authentication, resume, retries and the
  /// cancel token. Local files take only the cancel token. Its bearer token
  /// and headers are never sent across hosts: when they are set and the
  /// remote files, or the URLs the resolver returns for them, span more than
  /// one origin (scheme, host and port), the load throws before contacting
  /// another host. [onProgress] reports the files together: `receivedBytes`
  /// counts every file resolved so far plus the bytes of the current
  /// download; `totalBytes` is the combined size once every size is known,
  /// and `null` before.
  ///
  /// On Web the backend fetches each file itself: a local path is a URL
  /// relative to the document base URL, [download] must leave every option
  /// at its default, and [onProgress] reports only the encoder fetch, as a
  /// fraction.
  ///
  /// The encoder loads with [DecisionModelParams.encoderModelParams] of
  /// [params], then the head. [download]'s cancel token is checked again
  /// after each file resolves, after the encoder loads and after the head
  /// loads.
  ///
  /// The load is atomic: when it throws, the engine it created is disposed
  /// and nothing stays loaded. Downloaded files stay in the model cache.
  ///
  /// Throws:
  /// - [LlamaUnsupportedException] for [ComputeDevice.npu]; for
  ///   [ComputeDevice.gpu] when the encoder cannot load on a GPU; when
  ///   [download] sets [ModelLoadOptions.sha256], which cannot apply to
  ///   several files; when the encoder's [ModelSource.format] is
  ///   [ModelFormat.liteRtLm]; on Web for a [download] option the backend
  ///   fetch cannot apply; and when the backend or encoder cannot run
  ///   decision heads.
  /// - [LlamaArgumentException] for a negative [DecisionModelParams.threads],
  ///   and when [download] sets a bearer token or headers for remote files on
  ///   more than one origin; the message names the origins, never the
  ///   credentials.
  /// - [LlamaModelException] when a file is missing or cannot be downloaded,
  ///   when the encoder cannot load, and when the head or its config cannot
  ///   be read, is malformed, or does not fit the encoder.
  /// - [LlamaContextException] when the head's encoder context cannot be
  ///   created.
  /// - [LlamaStateException] when [download]'s cancel token cancels the
  ///   load.
  /// - [LlamaDecisionException] when the head's config or mask text fails
  ///   validation.
  static Future<DecisionEngine> load(
    DecisionModel model, {
    DecisionModelParams params = const DecisionModelParams(),
    ModelLoadOptions download = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
    ModelFileStore? store,
  }) async {
    if (params.device == ComputeDevice.npu) {
      throw LlamaUnsupportedException(
        'DecisionEngine runs on the CPU or a GPU; ComputeDevice.npu is not '
        'supported. Use ComputeDevice.auto.',
      );
    }
    if (params.threads < 0) {
      throw LlamaArgumentException(
        'DecisionModelParams.threads must be 0 or greater.',
        name: 'threads',
        invalidValue: params.threads,
      );
    }
    if (download.sha256 != null) {
      throw LlamaUnsupportedException(
        'DecisionEngine.load loads several files, so ModelLoadOptions.sha256 '
        'cannot apply to them. Leave it unset.',
      );
    }
    if (model.encoder.format == ModelFormat.liteRtLm) {
      throw LlamaUnsupportedException(
        'A decision encoder is a GGUF run by llama.cpp, so it cannot be '
        'ModelFormat.liteRtLm.',
      );
    }
    final (engine, targets) = await loadLlamaEngine(
      LlamaModel(model.encoder),
      params: params.encoderModelParams,
      download: download,
      onProgress: onProgress,
      store: store,
      backend: (debugDecisionBackendFactory ?? LlamaBackend.new)(),
      operation: _loadingOperation,
      assetType: 'decision model',
      companions: [model.head, ?model.config],
    );
    try {
      final modelEpoch = modelUnloadEpoch(engine);
      await _probe(engine, modelEpoch);
      final decisions = await _loadHead(
        engine,
        targets[0],
        targets.length > 1 ? targets[1] : null,
        modelEpoch,
        ownsEngine: true,
      );
      _throwIfCancelled(download);
      return decisions;
    } catch (_) {
      try {
        await engine.dispose();
      } catch (_) {}
      rethrow;
    }
  }

  /// Loads [head] on [engine], which already holds the encoder, and borrows
  /// [engine]: [dispose] frees only the head.
  ///
  /// Load the encoder with [DecisionModelParams.encoderModelParams], or at
  /// least a small context such as `ModelParams(contextSize: 512)`, since
  /// decisions run in the head's own encoder context. Several heads can be
  /// attached to one engine.
  ///
  /// [config] is Laya's `rl_agent_config.json`, for a head file without
  /// `laya.config` metadata. [head] and [config] resolve through [engine]'s
  /// `modelResolver` and `modelDownloadManager`, with [download] and
  /// [onProgress] as in [load]: credentials go to one origin only. When
  /// [config] is null, [ModelLoadOptions.sha256] verifies [head], whether it
  /// is a local file or a download. The decision capability probe runs
  /// before anything downloads. On Web the backend fetches both files, as in
  /// [load], and [onProgress] is not called.
  ///
  /// When it throws, any head it loaded is freed and [engine] keeps its
  /// model. Throws [LlamaUnsupportedException] when the backend or the
  /// loaded model cannot run decision heads, including when no model is
  /// loaded, when [download] sets [ModelLoadOptions.sha256] with a [config],
  /// and on Web for a [download] option the backend fetch cannot apply;
  /// [LlamaArgumentException] when [download] sets a bearer token or headers
  /// for remote files on more than one origin; [LlamaModelException] when a
  /// file is missing, cannot be downloaded or fails its checksum, or the head
  /// or its config cannot be read, is malformed, or does not fit the
  /// encoder; [LlamaContextException] when the head's encoder context
  /// cannot be created; [LlamaStateException] when [engine] is disposed,
  /// when [download]'s cancel token cancels it, when the model is unloaded
  /// during it, or on Web when the bridge rejects the load as disposed, busy
  /// or cancelled; and [LlamaDecisionException] when the head's config or
  /// mask text fails validation.
  static Future<DecisionEngine> attach(
    LlamaEngine engine, {
    required ModelSource head,
    ModelSource? config,
    ModelLoadOptions download = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    if (engine.isDisposed) {
      throw LlamaStateException(
        'DecisionEngine.attach needs a LlamaEngine that is not disposed.',
      );
    }
    if (config != null && download.sha256 != null) {
      throw LlamaUnsupportedException(
        'DecisionEngine.attach loads a head and a config, so '
        'ModelLoadOptions.sha256 cannot apply to both. Leave it unset.',
      );
    }
    final modelEpoch = engine.isReady ? modelUnloadEpoch(engine) : null;
    await _probe(engine, modelEpoch);
    final targets = await _fileTargets(
      engine,
      [head, ?config],
      download,
      onProgress,
    );
    _throwIfCancelled(download);
    if (modelEpoch != null && !_hasModel(engine, modelEpoch)) {
      throw LlamaStateException(_loadInterruptedMessage);
    }
    return _loadHead(
      engine,
      targets[0],
      targets.length > 1 ? targets[1] : null,
      modelEpoch,
      ownsEngine: false,
    );
  }

  /// Throws unless [engine] can load a decision head on the model it held at
  /// [modelEpoch].
  static Future<void> _probe(LlamaEngine engine, int? modelEpoch) async {
    try {
      final capabilities = await engine.backendDecisionCapabilities;
      if (modelEpoch != null && !_hasModel(engine, modelEpoch)) {
        throw LlamaStateException(_loadInterruptedMessage);
      }
      if (!capabilities.isSupported) {
        throw LlamaUnsupportedException(_unsupportedReason(capabilities));
      }
    } on LlamaStateException {
      rethrow;
    } catch (error, stackTrace) {
      _throwIfInterrupted(engine, modelEpoch, error, stackTrace);
      rethrow;
    }
  }

  static Future<DecisionEngine> _loadHead(
    LlamaEngine engine,
    String headPath,
    String? configPath,
    int? modelEpoch, {
    required bool ownsEngine,
  }) async {
    final BackendDecisionHeadInfo head;
    try {
      head = await engine.loadDecisionHeadBackend(
        headPath,
        configPath: configPath,
      );
    } on LlamaStateException {
      rethrow;
    } catch (error, stackTrace) {
      _throwIfInterrupted(engine, modelEpoch, error, stackTrace);
      rethrow;
    }
    try {
      if (head.maskText.isEmpty) {
        throw LlamaDecisionException(
          'The decision head reports an empty mask token text; decision '
          'sequences need it to strip the mask token from user text.',
        );
      }
      return DecisionEngine._(
        engine,
        head,
        decodeDecisionHeadConfig(head.configJson),
        modelEpoch,
        ownsEngine: ownsEngine,
      );
    } catch (error, stackTrace) {
      await engine
          .freeDecisionHeadBackend(head.handle)
          .catchError((Object _) {});
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Local paths of [sources] on file-backed backends; on URL-loading
  /// backends, the URLs or document-relative paths the backend fetches.
  static Future<List<String>> _fileTargets(
    LlamaEngine engine,
    List<ModelSource> sources,
    ModelLoadOptions download,
    ModelDownloadProgressCallback? onProgress,
  ) async {
    if (!engine.backend.supportsUrlLoading) {
      return resolveModelSourceFiles(
        sources,
        store: ModelFileStore(
          resolver: engine.modelResolver,
          downloadManager: engine.modelDownloadManager,
        ),
        download: download,
        operation: _loadingOperation,
        onProgress: onProgress,
        assetType: 'decision model',
      );
    }
    return resolveModelSourceUrls(
      sources,
      resolver: engine.modelResolver,
      download: download,
      assetType: 'decision model',
    );
  }

  static void _throwIfCancelled(ModelLoadOptions download) {
    if (download.cancelToken?.isCancelled ?? false) {
      throw LlamaStateException('$_loadingOperation was cancelled.');
    }
  }

  static void _throwIfInterrupted(
    LlamaEngine engine,
    int? modelEpoch,
    Object error,
    StackTrace stackTrace,
  ) {
    if (modelEpoch != null && !_hasModel(engine, modelEpoch)) {
      Error.throwWithStackTrace(
        LlamaStateException(_loadInterruptedMessage, error),
        stackTrace,
      );
    }
  }

  /// Whether this engine can answer now, and on which backend and runtime.
  ///
  /// Unsupported once [dispose] has been called, and once the model it was
  /// loaded for is unloaded. On Web a bridge runtime restart, which frees the
  /// head, shows only when a call throws [LlamaStateException].
  @override
  Future<DecisionCapabilities> get capabilities async {
    DecisionCapabilities? unavailable() => isDisposed
        ? const DecisionCapabilities(
            isSupported: false,
            unsupportedReason: 'The DecisionEngine is disposed.',
          )
        : !_hasModel(_engine, _modelEpoch)
        ? const DecisionCapabilities(
            isSupported: false,
            unsupportedReason: _modelUnloadedMessage,
          )
        : null;
    if (unavailable() case final reason?) return reason;
    final runtime = _engine.runtime;
    final backendName = await _backendNameOf(_engine);
    return unavailable() ??
        DecisionCapabilities(
          isSupported: true,
          backendName: backendName,
          runtime: runtime,
        );
  }

  /// Limits and device of the loaded model.
  final DecisionModelInfo info;

  /// Whether [dispose] has been called.
  @override
  bool get isDisposed => _disposal != null;

  /// Answers each question about [state] in one fast encoder pass per
  /// question, without generating text (Laya's `system_one`).
  ///
  /// [state] is text, or a JSON-like value encoded as JSON text. Throws
  /// [LlamaDecisionException] for invalid questions and for text that
  /// contains U+0000, which the Web bridge tokenizer cuts off there; it is
  /// rejected on every backend. JSON encoding escapes it in non-string
  /// states. Throws [LlamaStateException] after [dispose] or once the
  /// engine's model is unloaded. A call running during an unload throws it
  /// too, unless its sequences already reached the backend; that call returns
  /// answers from the unloaded model. On Web it is also thrown once the bridge
  /// restarts its runtime, which frees the head; load or attach the
  /// DecisionEngine again.
  ///
  /// To read answers as typed values, build [questions] with
  /// [DecisionKey.questionsOf] and read them with
  /// [DecisionResultKeys.answerOf].
  Future<DecisionResult> systemOne({
    required Object? state,
    required Map<String, DecisionQuestion> questions,
  }) => _track(() async {
    final results = await _answer([
      DecisionRequest(state: state, questions: questions),
    ]);
    return results.single;
  });

  /// Answers the questions of several states at once, in one backend call,
  /// in order.
  ///
  /// All questions are validated and tokenized before the model runs, and
  /// all sequences run in one backend call. The call answers [requests] as
  /// they are when it starts; later changes to the list do not affect it. An
  /// empty [requests] gives an empty list. Throws like [systemOne].
  Future<List<DecisionResult>> systemOneBatch(List<DecisionRequest> requests) {
    final snapshot = List<DecisionRequest>.unmodifiable(requests);
    return _track(() => _answer(snapshot));
  }

  /// Starts a cooperative task answering [questions] about [state].
  ///
  /// Snapshots the state and questions at creation, and starts without an
  /// events listener. Validation failures are reported through the task.
  /// Cancellation stops preflight at tokenization/dispatch checkpoints; after
  /// dispatch it waits for the backend and discards the answer. Backend errors
  /// still fail the task. Disposing this engine or unloading its model cancels
  /// active tasks at the same checkpoints. Legacy [systemOne] is unchanged.
  DecisionTask<DecisionResult> systemOneTask({
    required Object? state,
    required Map<String, DecisionQuestion> questions,
  }) => _startTask(
    () => [DecisionRequest(state: state, questions: questions)],
    (List<DecisionResult> results) => results.single,
  );

  /// Starts one cooperative task for [requests], preserving request order.
  ///
  /// Snapshots the list at creation; [DecisionRequest] already freezes its
  /// state and questions. Emits one final list, including an empty list for
  /// an empty batch. Cancellation and failure emit no partial results. See
  /// [systemOneTask] for cancellation and lifecycle semantics.
  DecisionTask<List<DecisionResult>> systemOneBatchTask(
    List<DecisionRequest> requests,
  ) => _startTask(
    () => List<DecisionRequest>.unmodifiable(requests),
    (List<DecisionResult> results) => results,
  );

  DecisionTask<R> _startTask<R extends Object>(
    List<DecisionRequest> Function() snapshot,
    R Function(List<DecisionResult>) select,
  ) {
    final task = DecisionTask<R>._();
    _tasks.add(task);
    void checkpoint() {
      if (isDisposed || !_hasModel(_engine, _modelEpoch)) task.cancel();
      task._checkpoint();
    }

    unawaited(
      task
          ._execute(
            () => _track(() async {
              final requests = snapshot();
              if (requests.isNotEmpty && !_hasModel(_engine, _modelEpoch)) {
                throw LlamaStateException(_modelUnloadedMessage);
              }
              // Reserve the active lifetime now, but let an immediate cancel stop
              // even the first tokenizer call.
              await Future<void>.value();
              checkpoint();
              final results = await _answer(requests, checkpoint: checkpoint);
              checkpoint();
              return select(results);
            }),
          )
          .whenComplete(() => _tasks.remove(task)),
    );
    return task;
  }

  /// Frees the decision head after in-flight calls finish, then the
  /// [LlamaEngine] when [load] created it.
  ///
  /// Idempotent. Calls made after it throw [LlamaStateException]. An engine
  /// passed to [attach] stays loaded.
  @override
  Future<void> dispose() {
    final existing = _disposal;
    if (existing != null) return existing;

    // Cleanup hooks can reenter before an async body's first suspension.
    final disposal = Completer<void>();
    _disposal = disposal.future;
    for (final task in _tasks) {
      task.cancel();
    }
    disposal.complete(_dispose());
    return disposal.future;
  }

  Future<void> _dispose() async {
    if (_activeCalls > 0) {
      await (_idle = Completer<void>()).future;
    }
    try {
      await _engine.freeDecisionHeadBackend(_head.handle);
    } finally {
      if (_ownsEngine) await _engine.dispose();
    }
  }

  Future<T> _track<T>(Future<T> Function() call) async {
    if (isDisposed) {
      throw LlamaStateException(
        'This DecisionEngine was disposed. Load a new one with '
        'DecisionEngine.load.',
      );
    }
    _activeCalls++;
    try {
      return await call();
    } finally {
      if (--_activeCalls == 0) {
        _idle?.complete();
        _idle = null;
      }
    }
  }

  Future<List<DecisionResult>> _answer(
    List<DecisionRequest> requests, {
    void Function()? checkpoint,
  }) async {
    if (requests.isEmpty) return const <DecisionResult>[];
    if (!_hasModel(_engine, _modelEpoch)) {
      throw LlamaStateException(_modelUnloadedMessage);
    }
    try {
      return await _run(requests, checkpoint: checkpoint);
    } on _DecisionTaskCancelled {
      rethrow;
    } on LlamaDecisionException {
      rethrow;
    } on LlamaStateException {
      rethrow;
    } catch (error, stackTrace) {
      if (!_hasModel(_engine, _modelEpoch)) {
        Error.throwWithStackTrace(
          LlamaStateException(_modelUnloadedMessage, error),
          stackTrace,
        );
      }
      rethrow;
    }
  }

  Future<List<DecisionResult>> _run(
    List<DecisionRequest> requests, {
    void Function()? checkpoint,
  }) async {
    final tokenCache = <String, Future<List<int>>>{};
    Future<List<int>> tokenize(String text) async {
      checkpoint?.call();
      if (text.contains('\u0000')) {
        throw LlamaDecisionException(
          'Decision text contains U+0000, where Web bridge tokenization cuts '
          'it off, so every backend rejects it. Remove it from the state, '
          'instructions and options, or pass the state as a JSON value.',
        );
      }
      final tokens = await tokenCache.putIfAbsent(
        text,
        () => _engine.tokenize(text, addSpecial: false),
      );
      checkpoint?.call();
      return tokens;
    }

    final sequences = <List<DecisionSequence>>[
      for (final request in requests)
        await buildDecisionSequences(request, _spec, tokenize),
    ];

    final inputs = <BackendDecisionSequence>[
      for (var r = 0; r < requests.length; r++)
        for (final (q, question) in requests[r].questions.values.indexed)
          BackendDecisionSequence(
            tokens: Int32List.fromList(sequences[r][q].tokens),
            markers: Int32List.fromList(sequences[r][q].markers),
            questionType: question.type,
          ),
    ];
    checkpoint?.call();
    final outputs = await _engine.runDecisionBackend(_head.handle, inputs);
    if (outputs.length != inputs.length) {
      throw LlamaDecisionException(
        'The decision backend returned ${outputs.length} outputs for '
        '${inputs.length} sequences.',
      );
    }

    final results = <DecisionResult>[];
    var next = 0;
    for (var r = 0; r < requests.length; r++) {
      final answers = <String, DecisionAnswer>{};
      for (final MapEntry(key: id, value: question)
          in requests[r].questions.entries) {
        final output = outputs[next++];
        answers[id] = decodeDecisionAnswer(
          question,
          output.logits,
          output.actLogits,
          _config,
        );
      }
      results.add(
        DecisionResult(
          model: decisionResponseModel,
          answers: answers,
          questions: requests[r].questions,
          usage: DecisionUsage(
            inputTokens: sequences[r].fold(
              0,
              (total, sequence) => total + sequence.tokens.length,
            ),
            outputTokens: 0,
          ),
        ),
      );
    }
    return results;
  }

  static const String _loadingOperation = 'Decision model loading';

  static const String _loadInterruptedMessage =
      'The model was unloaded while the DecisionEngine was loading. Load the '
      'model and the DecisionEngine again.';

  static const String _modelUnloadedMessage =
      'The model this DecisionEngine was loaded for was unloaded. Load the '
      'DecisionEngine again.';

  static bool _hasModel(LlamaEngine engine, int? modelEpoch) =>
      engine.isReady && modelUnloadEpoch(engine) == modelEpoch;

  static Future<String?> _backendNameOf(LlamaEngine engine) async {
    try {
      return await engine.getBackendName();
    } catch (_) {
      return null;
    }
  }

  static String _unsupportedReason(BackendDecisionCapabilities capabilities) =>
      capabilities.unsupportedReason ??
      'The active backend cannot run decision models.';
}
