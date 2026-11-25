part of 'litert_lm_v1_runtime.dart';

/// C API 1.0 client selected by the public ABI-aware facade or injected directly.
/// Runtime selection does not qualify an artifact, model or backend.
final class LiteRtLmV1RuntimeClient implements LiteRtLmRuntimeClientContract {
  /// Admits an explicitly supplied library; never discovers a different runtime.
  ///
  /// [inProcessLiteRtAbiVersion] is the library's
  /// `litert_lm_native_in_process_litert_abi_version`, null when not exported.
  LiteRtLmV1RuntimeClient(
    DynamicLibrary library, {
    LiteRtLmV1CreateRunner? createRunner,
    int? inProcessLiteRtAbiVersion,
  }) : _runtime = LiteRtLmV1Runtime(library, createRunner: createRunner),
       _inProcessLiteRtAbiVersion = inProcessLiteRtAbiVersion;

  final LiteRtLmV1Runtime _runtime;
  final int? _inProcessLiteRtAbiVersion;
  LiteRtLmV1Conversation? _conversation;
  _V1EmbeddingSession? _embedding;
  LiteRtLmNativeSettlement _embeddingCreation =
      LiteRtLmNativeSettlement.settled;
  LiteRtLmV1Turn? _activeTurn;
  int _outputTokens = 256;
  ComputeDevice? _backend;
  bool _disposed = false;
  LiteRtLmFinishReason? _lastFinishReason;
  String _startTag = legacy.LiteRtLmChannelAssembler.gemma4ThinkingStartTag;
  String _endTag = legacy.LiteRtLmChannelAssembler.gemma4ThinkingEndTag;

  void _live() {
    if (_disposed) throw LlamaStateException('C API 1.0 client is disposed.');
  }

  @override
  void configureResponseThinkingTags({
    required String startTag,
    required String endTag,
  }) {
    _live();
    _startTag = startTag;
    _endTag = endTag;
  }

  bool _hasSymbols(List<String> symbols) =>
      !_disposed && symbols.every(_runtime._library.providesSymbol);

  bool get _callbacksAdmitted =>
      _hasSymbols(LiteRtLmV1Conversation._symbols) &&
      _runtime._library.lookupFunction<Int32 Function(), int Function()>(
            'stream_proxy_callback_abi_version',
          )() ==
          2 &&
      _runtime._library.lookupFunction<Int32 Function(), int Function()>(
            'stream_proxy_allocation_failure_abi_version',
          )() ==
          1;

  @override
  bool get supportsAsrBridge =>
      !_disposed && legacy.supportsLiteRtLmAsrLibrary(_runtime._library);

  @override
  bool get supportsSamplingPenalties =>
      _callbacksAdmitted &&
      _hasSymbols(const [
        'litert_lm_conversation_optional_args_create',
        'litert_lm_conversation_optional_args_delete',
        'litert_lm_conversation_optional_args_set_max_output_tokens',
        'litert_lm_repetition_penalty_config_create',
        'litert_lm_repetition_penalty_config_delete',
        'litert_lm_repetition_penalty_config_set_repetition_penalty',
        'litert_lm_repetition_penalty_config_set_presence_penalty',
        'litert_lm_conversation_optional_args_set_repetition_penalty_config',
      ]);

  @override
  bool get supportsThinkingBudget =>
      _callbacksAdmitted && _V1ThinkingBudget(_runtime).supported;

  @override
  bool get supportsFinishReasons =>
      _callbacksAdmitted &&
      _hasSymbols(const [
        'stream_proxy_finish_reason_abi_version',
        'stream_proxy_get_finish_reason',
      ]) &&
      _runtime._library.lookupFunction<Int32 Function(), int Function()>(
            'stream_proxy_finish_reason_abi_version',
          )() ==
          1;

  @override
  bool get supportsJsonSchemaConstraints =>
      _callbacksAdmitted && _hasSymbols(_V1JsonSchema.symbols);

  @override
  bool get supportsJsonSchemaThinking => supportsJsonSchemaConstraints;

  @override
  bool get supportsMessageRendering =>
      _hasSymbols(const ['litert_lm_conversation_render_message_to_string']);

  @override
  int? resolveDefaultVisualTokenBudget(int preferredBudget) =>
      _runtime._inspectMediaSupport().visualBudget ? preferredBudget : null;

  @override
  LiteRtLmFinishReason? get lastFinishReason => _lastFinishReason;

  @override
  LiteRtLmNativeSettlement get nativeSettlement {
    final states = [
      _runtime.nativeSettlement,
      _embeddingCreation,
      _embedding?.settlement,
    ];
    if (states.contains(LiteRtLmNativeSettlement.quarantined)) {
      return LiteRtLmNativeSettlement.quarantined;
    }
    if (states.contains(LiteRtLmNativeSettlement.pending)) {
      return LiteRtLmNativeSettlement.pending;
    }
    return LiteRtLmNativeSettlement.settled;
  }

  @override
  ({bool vision, bool audio, bool speculativeDecoding})? bundleCapabilities(
    String modelPath,
  ) {
    _live();
    try {
      final flags = _runtime.bundleCapabilities(modelPath);
      return (
        vision: flags.vision,
        audio: flags.audio,
        speculativeDecoding: flags.speculativeDecoding,
      );
    } on LlamaUnsupportedException {
      return null;
    } on LlamaModelException {
      return null;
    }
  }

  @override
  LiteRtLmAsrRuntimeSession createAsrSession(LiteRtLmAsrRuntimeConfig config) {
    _live();
    return legacy.createLiteRtLmAsrSessionFromLibrary(
      _runtime._library,
      config,
    );
  }

  @override
  Future<LiteRtLmEmbeddingRuntimeSession> createEmbeddingSession({
    required String modelPath,
    required String backend,
    required String cacheDir,
    required int maxInputLength,
    required int numberOfThreads,
  }) async {
    _live();
    if (_embedding != null ||
        nativeSettlement != LiteRtLmNativeSettlement.settled) {
      throw LlamaStateException(
        'Client already owns an embedding or unsettled native work.',
      );
    }
    liteRtLmEnsureNativeEmbeddingsQualified();
    liteRtLmEnsureInProcessLiteRtForNativeEmbeddings(
      _inProcessLiteRtAbiVersion,
    );
    ensureLiteRtLmNativeEmbeddingBackend(backend);
    if (maxInputLength <= 0 ||
        maxInputLength > 0x7fffffff ||
        numberOfThreads < 0 ||
        numberOfThreads > 0x7fffffff) {
      throw LlamaArgumentException(
        'Embedding context must be 1..2147483647 and thread count 0..2147483647.',
      );
    }
    final addresses = _embeddingAddresses(_runtime._library);
    final capabilities = _embeddingBundle(modelPath);
    final paths = [modelPath, cacheDir];
    _embeddingCreation = LiteRtLmNativeSettlement.pending;
    late LiteRtLmBlockingCallResult<int> result;
    try {
      result = await _dispatchEmbeddingCreate((
        addresses: addresses,
        paths: paths,
        model: modelPath,
        cache: cacheDir,
        context: maxInputLength,
        threads: numberOfThreads,
        capabilities: capabilities,
      ));
    } catch (_) {
      _embeddingCreation = LiteRtLmNativeSettlement.quarantined;
      rethrow;
    }
    _embeddingCreation = LiteRtLmNativeSettlement.settled;
    if (result.error case final error?) {
      Error.throwWithStackTrace(error, result.stackTrace!);
    }
    return _embedding = _V1EmbeddingSession(
      _runtime._library,
      addresses,
      paths,
      result.value!,
      capabilities,
    );
  }

  ComputeDevice _device(String value) => switch (value.trim().toLowerCase()) {
    'cpu' => ComputeDevice.cpu,
    'gpu' => ComputeDevice.gpu,
    'npu' => ComputeDevice.npu,
    _ => throw LlamaArgumentException(
      'C API 1.0 backend must be cpu, gpu or npu.',
    ),
  };

  @override
  Future<void> initialize({
    required String modelPath,
    String backend = 'gpu',
    String? visionBackend,
    String? audioBackend,
    int maxTokens = 4096,
    int outputTokens = 256,
    int? prefillTokens,
    int? maxNumImages,
    String? cacheDir,
    bool speculativeDecoding = true,
    int minLogLevel = 3,
    LiteRtLmActivationDataType? activationDataType,
    int? prefillChunkSize,
    bool? parallelFileSectionLoading,
    String? dispatchLibDir,
    int? numberOfThreads,
  }) async {
    _live();
    if (outputTokens <= 0 || outputTokens > 0x7fffffff) {
      throw LlamaArgumentException(
        'C API 1.0 outputTokens must be a positive C int.',
      );
    }
    // The service derives this count from all images in the current history.
    // Advanced engines accept their actual inputs dynamically; no capacity
    // setter is invoked or advertised by accepting this preparation hint.
    if (maxNumImages != null &&
        (maxNumImages <= 0 || maxNumImages > 0x7fffffff)) {
      throw LlamaArgumentException(
        'Image history count must be a positive C int.',
      );
    }
    if (maxNumImages != null && visionBackend == null) {
      throw LlamaUnsupportedException(
        'Image history requires a vision encoder.',
      );
    }
    final options = LiteRtLmV1EngineSettings(
      backend: _device(backend),
      visionBackend: visionBackend == null ? null : _device(visionBackend),
      audioBackend: audioBackend == null ? null : _device(audioBackend),
      contextSize: maxTokens,
      numberOfThreads: numberOfThreads,
      cacheDir: cacheDir,
      speculativeDecoding: speculativeDecoding,

      prefillTokens: prefillTokens,
      activationDataType: activationDataType,
      prefillChunkSize: prefillChunkSize,
      parallelFileSectionLoading: parallelFileSectionLoading,
      dispatchLibDir: dispatchLibDir,
    );
    options._validate(modelPath);
    _closeConversation();
    setMinLogLevel(minLogLevel);
    await _runtime.loadConfiguredAsync(modelPath, options);
    _backend = options.backend;
    _outputTokens = outputTokens;
    _lastFinishReason = null;
  }

  void _closeConversation() {
    if (nativeSettlement != LiteRtLmNativeSettlement.settled) {
      throw LlamaStateException(
        'Settle C API 1.0 native work before replacing or releasing its conversation.',
      );
    }
    _conversation?.close();
    _conversation = null;
  }

  @override
  void createConversation({
    String? systemMessage,
    String? promptTemplate,
    List<Map<String, dynamic>>? messages,
    List<Map<String, dynamic>>? tools,
    Map<String, dynamic>? extraContext,
    double temperature = 0.8,
    int topK = 40,
    double topP = 0.95,
    int seed = 1,
    bool npuBackend = false,
    String? loraPath,
    bool jsonSchemaConstraints = false,
  }) {
    _live();
    if (loraPath != null) {
      throw LlamaUnsupportedException(
        'The pinned native LiteRT-LM runtime does not execute initial text LoRA '
        'adapters in its advanced engine. The session path setter alone '
        'does not provide adapter support. Use a supported llama.cpp '
        'model/adapter pair; tracked in litert-lm-native#99.',
      );
    }
    if (jsonSchemaConstraints) _V1JsonSchema(_runtime).requireSupport();
    if (npuBackend && _backend != ComputeDevice.npu) {
      throw LlamaArgumentException('npuBackend requires a loaded NPU engine.');
    }
    final settings = LiteRtLmV1ConversationSettings(
      maxOutputTokens: _outputTokens,
      jsonSchemaConstraints: jsonSchemaConstraints,
      sampler: _backend == ComputeDevice.npu
          ? null
          : LiteRtLmV1SamplerSettings(
              temperature: temperature,
              topK: topK,
              topP: topP,
              seed: seed,
            ),
      systemMessage: systemMessage,
      promptTemplate: promptTemplate,
      messages: messages,
      tools: tools,
      extraContext: extraContext,
    );
    _closeConversation();
    _conversation = _runtime.openConfiguredConversation(settings);
    _lastFinishReason = null;
  }

  @override
  void setMinLogLevel(int level) {
    _live();
    if (!const {0, 1, 2, 3, 4, 5, 1000}.contains(level)) {
      throw LlamaArgumentException(
        'C API 1.0 logging requires a declared severity.',
      );
    }
    const symbol = 'litert_lm_set_min_log_level';
    _requireV1Symbols(_runtime._library, const [symbol]);
    final set = _runtime._library
        .lookupFunction<Int Function(Int), int Function(int)>(symbol);
    _runtime._check(set(level), symbol);
  }

  @override
  List<int> tokenize(String text, {bool addSpecial = true}) =>
      _runtime.tokenize(text, addSpecial: addSpecial);

  @override
  String detokenize(List<int> tokens) => _runtime.detokenize(tokens);

  LiteRtLmV1Conversation get _current {
    _live();
    return _conversation ??
        (throw LlamaStateException('Create a C API 1.0 conversation first.'));
  }

  @override
  String renderMessageToString(Map<String, dynamic> message) =>
      _current.renderMessageToString(message);

  @override
  Stream<String> generate(
    String prompt, {
    int? maxOutputTokens,
    double? repetitionPenalty,
    double? presencePenalty,
  }) => generateMessageJson(
    jsonEncode({
      'role': 'user',
      'content': [
        {'type': 'text', 'text': prompt},
      ],
    }),
    maxOutputTokens: maxOutputTokens,
    repetitionPenalty: repetitionPenalty,
    presencePenalty: presencePenalty,
  );

  String _canonicalResponse(String raw) {
    Object? value;
    try {
      value = jsonDecode(raw);
    } on FormatException {
      return raw;
    }
    if (value is! Map<String, dynamic> ||
        !value.containsKey('reasoning_content')) {
      return raw;
    }
    final reasoning = value['reasoning_content'];
    final channels = value['channels'];
    // v1 SendMessageToChannel emits one named channel plus the same text in
    // reasoning_content. The explicit field identifies reasoning independently
    // of model-specific channel names; never emit its duplicate as answer text.
    if (reasoning is! String ||
        (channels != null &&
            (channels is! Map<String, dynamic> ||
                channels.length != 1 ||
                channels.values.single != reasoning))) {
      throw LlamaModelException(
        'C API 1.0 returned contradictory reasoning-channel data.',
      );
    }
    final canonical = Map<String, dynamic>.from(value)
      ..remove('reasoning_content')
      ..['channels'] = {'thought': reasoning};
    return jsonEncode(canonical);
  }

  @override
  Stream<String> generateMessageJson(
    String messageJson, {
    Map<String, dynamic>? extraContext,
    int? visualTokenBudget,
    int? maxOutputTokens,
    double? repetitionPenalty,
    double? presencePenalty,
    int? thinkingTokenBudget,
    String? jsonSchema,
  }) {
    final conversation = _current;
    Object? message;
    try {
      message = jsonDecode(messageJson);
    } on FormatException {
      throw LlamaArgumentException('C API 1.0 message must be a JSON object.');
    }
    if (message is! Map<String, dynamic>) {
      throw LlamaArgumentException('C API 1.0 message must be a JSON object.');
    }
    _lastFinishReason = null;
    final turn = conversation.sendMessage(
      message,
      extraContext: extraContext,
      settings: LiteRtLmV1TurnSettings(
        maxOutputTokens: maxOutputTokens ?? _outputTokens,
        visualTokenBudget: visualTokenBudget,
        repetitionPenalty: repetitionPenalty,
        presencePenalty: presencePenalty,
        thinkingTokenBudget: thinkingTokenBudget,
        jsonSchema: jsonSchema,
      ),
    );
    _activeTurn = turn;
    Object? failure;
    StackTrace? failureStack;
    final completion = turn.done.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        failure ??= error;
        failureStack ??= stack;
      },
    );
    final assembler = legacy.LiteRtLmChannelAssembler(
      thinkingStartTag: _startTag,
      thinkingEndTag: _endTag,
    );
    late final StreamController<String> controller;
    final settled = Completer<void>();
    controller = StreamController<String>(
      onCancel: () async {
        turn.cancel();
        await settled.future;
      },
    );
    unawaited(() async {
      try {
        await for (final raw in turn.chunks) {
          final text = assembler.add(_canonicalResponse(raw));
          if (text.isNotEmpty) controller.add(text);
        }
      } on Object catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
        try {
          turn.cancel();
        } on Object catch (cancelError, cancelStack) {
          failure ??= cancelError;
          failureStack ??= cancelStack;
        }
      }
      await completion;
      // Final-data listeners may already have started a different turn.
      if (identical(_activeTurn, turn)) {
        _lastFinishReason = supportsFinishReasons ? turn.finishReason : null;
        _activeTurn = null;
      }
      if (failure case final error?) {
        controller.addError(error, failureStack);
      } else {
        final tail = assembler.flush();
        if (tail.isNotEmpty) controller.add(tail);
      }
      // Subscription cancellation must also wait for this adapter's terminal
      // state update, so a new turn cannot be overwritten by an older task.
      settled.complete();
      await controller.close();
    }());
    return controller.stream;
  }

  @override
  Future<legacy.LiteRtLmRuntimeResult> run({
    required String prompt,
    int warmupRuns = 1,
    int measuredRuns = 3,
  }) async {
    if (warmupRuns < 0 || measuredRuns <= 0) {
      throw LlamaArgumentException(
        'Benchmark requires nonnegative warmups and positive measured runs.',
      );
    }
    for (var i = 0; i < warmupRuns; i++) {
      createConversation();
      await generate(prompt).drain<void>();
    }
    var text = '';
    late legacy.LiteRtLmRuntimeMetrics measured;
    for (var i = 0; i < measuredRuns; i++) {
      createConversation();
      final buffer = StringBuffer();
      final clock = Stopwatch()..start();
      await for (final chunk in generate(prompt)) {
        buffer.write(chunk);
      }
      clock.stop();
      text = buffer.toString();
      measured = readMetrics(wallMilliseconds: clock.elapsedMilliseconds);
    }
    return legacy.LiteRtLmRuntimeResult(text: text, metrics: measured);
  }

  @override
  legacy.LiteRtLmRuntimeMetrics readMetrics({required int wallMilliseconds}) =>
      _current.readMetrics(wallMilliseconds: wallMilliseconds);

  @override
  void cancel() {
    _live();
    _activeTurn?.cancel();
  }

  @override
  void dispose() {
    if (_disposed) return;
    if (nativeSettlement != LiteRtLmNativeSettlement.settled) {
      throw LlamaStateException(
        'Cannot dispose a client with unsettled native work.',
      );
    }
    _embedding?.dispose();
    _closeConversation();
    _runtime.dispose();
    _disposed = true;
  }
}
