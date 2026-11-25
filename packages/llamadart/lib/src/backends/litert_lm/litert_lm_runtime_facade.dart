part of 'litert_lm_runtime.dart';

// Activation changes only after artifact and public-path qualification.
const bool _liteRtLmV1ProductionSelection = true;

/// Internal selection seam for ABI and compatibility qualification.
LiteRtLmRuntimeClient createLiteRtLmSelectedRuntimeClient({
  String? libraryPath,
  bool allowV1 = _liteRtLmV1ProductionSelection,
  String? macOsVersion,
  bool eager = false,
}) {
  final client = LiteRtLmRuntimeClient._selected(
    libraryPath,
    allowV1,
    macOsVersion,
  );
  if (eager) client._runtime;
  return client;
}

/// Internal service adapter whose visual hints follow the selected runtime.
LiteRtLmRuntimeClientContract createLiteRtLmSelectedServiceClient({
  String? libraryPath,
  bool allowV1 = _liteRtLmV1ProductionSelection,
  String? macOsVersion,
  bool eager = false,
}) {
  final client = createLiteRtLmSelectedRuntimeClient(
    libraryPath: libraryPath,
    allowV1: allowV1,
    macOsVersion: macOsVersion,
    eager: eager,
  );
  return LiteRtLmLegacyServiceClient(
    client,
    resolveVisualTokenBudget: (preferred) =>
        client._runtime.resolveDefaultVisualTokenBudget(preferred),
  );
}

/// Lazy native client preserving the public LiteRT-LM SPI across C API versions.
class LiteRtLmRuntimeClient {
  /// Creates a client; [libraryPath] overrides packaged runtime discovery.
  LiteRtLmRuntimeClient({String? libraryPath})
    : _facadeLibraryPath = libraryPath,
      _allowV1 = _liteRtLmV1ProductionSelection,
      _macOsVersion = null;
  LiteRtLmRuntimeClient._selected(
    this._facadeLibraryPath,
    this._allowV1,
    this._macOsVersion,
  );
  LiteRtLmRuntimeClient._legacy()
    : _facadeLibraryPath = null,
      _allowV1 = false,
      _macOsVersion = null;
  final String? _macOsVersion;
  final bool _allowV1;

  final String? _facadeLibraryPath;
  LiteRtLmRuntimeClientContract? _selected;
  _LegacyLiteRtLmRuntimeClient? _libraryOwner;

  LiteRtLmRuntimeClientContract get _runtime => _selected ??= _selectRuntime();

  LiteRtLmRuntimeClientContract _selectRuntime() {
    if (_allowV1) {
      liteRtLmEnsureV1PlatformFloor(operatingSystemVersion: _macOsVersion);
      if (_facadeLibraryPath == null) {
        final unsupported = liteRtLmUnsupportedAbiException(liteRtLmGateAbi());
        if (unsupported != null) throw unsupported;
      }
    }
    final owner = _LegacyLiteRtLmRuntimeClient(
      libraryPath: _facadeLibraryPath,
      allowV1Inventory: _allowV1,
    );
    final selected = owner._discoverLibraries();
    _libraryOwner = owner;
    final version = readLiteRtLmCApiVersion(selected.library);
    final LiteRtLmRuntimeClientContract client;
    if (version != null && _allowV1) {
      final unsupported = liteRtLmUnsupportedAbiException(liteRtLmGateAbi());
      if (unsupported != null) throw unsupported;
      client = LiteRtLmV1RuntimeClient(
        selected.library,
        inProcessLiteRtAbiVersion: readLiteRtLmInProcessLiteRtAbiVersion(
          selected.library,
        ),
      );
    } else {
      requireLiteRtLmLegacyCApi(selected.library);
      client = LiteRtLmLegacyServiceClient(owner);
    }

    client.configureResponseThinkingTags(startTag: _startTag, endTag: _endTag);
    return client;
  }

  String _startTag = LiteRtLmChannelAssembler.gemma4ThinkingStartTag;
  String _endTag = LiteRtLmChannelAssembler.gemma4ThinkingEndTag;

  /// Configures how LiteRT-LM thought-channel chunks are exposed to parsers.
  void configureResponseThinkingTags({
    required String startTag,
    required String endTag,
  }) {
    _startTag = startTag;
    _endTag = endTag;
    _selected?.configureResponseThinkingTags(
      startTag: startTag,
      endTag: endTag,
    );
  }

  /// Whether the active native runtime exports the dedicated ASR bridge.
  ///
  /// Runtime load failures are reported as unsupported rather than thrown so
  /// callers can use this as a capability probe.
  bool get supportsAsrBridge {
    try {
      return _runtime.supportsAsrBridge;
    } on Object {
      return false;
    }
  }

  /// Whether the active native runtime exports the per-send repetition
  /// penalty API that [generateMessageJson] uses for `repetitionPenalty` and
  /// `presencePenalty`.
  ///
  /// Runtime load failures are reported as unsupported rather than thrown so
  /// callers can use this as a capability probe.
  bool get supportsSamplingPenalties {
    try {
      return _runtime.supportsSamplingPenalties;
    } on Object {
      return false;
    }
  }

  /// Whether the active native runtime exports the per-send thinking config
  /// API that [generateMessageJson] uses for `thinkingTokenBudget`.
  ///
  /// Runtime load failures are reported as unsupported rather than thrown so
  /// callers can use this as a capability probe.
  bool get supportsThinkingBudget {
    try {
      return _runtime.supportsThinkingBudget;
    } on Object {
      return false;
    }
  }

  /// Whether the active native runtime reports why each streamed turn ended:
  /// its `stream_proxy_finish_reason_abi_version` export returns 1
  /// (litert-lm-native `v0.18.0-3` and later) and it streams through the
  /// embedded StreamProxy.
  ///
  /// Runtime load failures are reported as unsupported rather than thrown so
  /// callers can use this as a capability probe.
  bool get supportsFinishReasons {
    try {
      return _runtime.supportsFinishReasons;
    } on Object {
      return false;
    }
  }

  /// Whether the loaded runtime exports the complete optional schema API.
  bool get supportsJsonSchemaConstraints =>
      _runtime.supportsJsonSchemaConstraints;

  /// Whether a schema constraint can follow an enabled reasoning channel,
  /// rather than the runtime forcing thinking off for constrained chat.
  bool get supportsJsonSchemaThinking => _runtime.supportsJsonSchemaThinking;

  /// Whether a runtime is loaded and provides the entry point of
  /// [renderMessageToString].
  bool get supportsMessageRendering => _runtime.supportsMessageRendering;

  /// Why the latest [generateMessageJson] or [generate] stream ended.
  ///
  /// Set before that stream closes. Null while a stream is running, before
  /// the first one, and on runtimes without [supportsFinishReasons].
  LiteRtLmFinishReason? get lastFinishReason => _selected?.lastFinishReason;

  /// Native lifetime; a Dart stream error alone does not establish settlement.
  LiteRtLmNativeSettlement get nativeSettlement =>
      _selected?.nativeSettlement ?? LiteRtLmNativeSettlement.settled;

  /// What the `.litertlm` bundle at [modelPath] declares in its section
  /// metadata, read without creating an engine: whether it takes image and
  /// audio input, and whether it has a speculative decoding drafter.
  ///
  /// Returns null when the runtime lacks LiteRT-LM's loaded-file capability
  /// API or cannot read the bundle. The reader matches section types
  /// case-sensitively and the runtime does not, so a `false` can be wrong
  /// for a bundle whose section types are not lowercase.
  ({bool vision, bool audio, bool speculativeDecoding})? bundleCapabilities(
    String modelPath,

    /// What the `.litertlm` bundle at [modelPath] declares in its section
    /// metadata, read without creating an engine: whether it takes image and
    /// audio input, and whether it has a speculative decoding drafter.
    ///
    /// Returns null when the runtime lacks LiteRT-LM's loaded-file capability
    /// API or cannot read the bundle. The reader matches section types
    /// case-sensitively and the runtime does not, so a `false` can be wrong
    /// for a bundle whose section types are not lowercase.
  ) => _runtime.bundleCapabilities(modelPath);

  /// Creates a synchronous dedicated-ASR runtime session.
  ///
  /// The current bridge accepts mono 16 kHz float PCM. Inference calls block;
  /// high-level clients should own this session from a worker isolate.
  LiteRtLmAsrRuntimeSession createAsrSession(LiteRtLmAsrRuntimeConfig config) {
    _validateLiteRtLmAsrRuntimeConfig(config);
    return _runtime.createAsrSession(config);
  }

  /// Initializes the native LiteRT-LM engine for a `.litertlm` model bundle.
  ///
  /// [visionBackend] and [audioBackend] enable the native media executors for
  /// multimodal bundles. [maxNumImages] configures legacy image capacity; C API
  /// 1 treats it as a history hint, requires [visionBackend], and accepts actual
  /// images dynamically without enforcing a capacity. [outputTokens]
  /// is the per-request fallback when generation does not provide an explicit
  /// maximum; it is not an upstream benchmark decode-step count.
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
    _validateLiteRtLmInitializeArguments(
      backend: backend,
      visionBackend: visionBackend,
      audioBackend: audioBackend,
      maxTokens: maxTokens,
      outputTokens: outputTokens,
      prefillTokens: prefillTokens,
      maxNumImages: maxNumImages,
      prefillChunkSize: prefillChunkSize,
      dispatchLibDir: dispatchLibDir,
      numberOfThreads: numberOfThreads,
    );
    return _runtime.initialize(
      modelPath: modelPath,
      backend: backend,
      visionBackend: visionBackend,
      audioBackend: audioBackend,
      maxTokens: maxTokens,
      outputTokens: outputTokens,
      prefillTokens: prefillTokens,
      maxNumImages: maxNumImages,
      cacheDir: cacheDir,
      speculativeDecoding: speculativeDecoding,
      minLogLevel: minLogLevel,
      activationDataType: activationDataType,
      prefillChunkSize: prefillChunkSize,
      parallelFileSectionLoading: parallelFileSectionLoading,
      dispatchLibDir: dispatchLibDir,
      numberOfThreads: numberOfThreads,
    );
  }

  /// Creates a new LiteRT-LM conversation for generation and token operations.
  ///
  /// [systemMessage] is plain text, including any literal JSON text. The native
  /// API wraps this content in its own system-role message.
  ///
  /// [promptTemplate] overrides the bundle's native Jinja template. Omit it to
  /// preserve model-specific formatting, especially for media. An explicit
  /// override requires the native conversation-template setter; incompatible
  /// runtime overrides fail with [LlamaUnsupportedException].
  ///
  /// With [temperature] `0`, [topK] is forced to `1`. [npuBackend] sets no
  /// sampler parameters.
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

    /// Creates a new LiteRT-LM conversation for generation and token operations.
    ///
    /// [systemMessage] is plain text, including any literal JSON text. The native
    /// API wraps this content in its own system-role message.
    ///
    /// [promptTemplate] overrides the bundle's native Jinja template. Omit it to
    /// preserve model-specific formatting, especially for media. An explicit
    /// override requires the native conversation-template setter; incompatible
    /// runtime overrides fail with [LlamaUnsupportedException].
    ///
    /// With [temperature] `0`, [topK] is forced to `1`. [npuBackend] sets no
    /// sampler parameters.
  }) => _runtime.createConversation(
    systemMessage: systemMessage,
    promptTemplate: promptTemplate,
    messages: messages,
    tools: tools,
    extraContext: extraContext,
    temperature: temperature,
    topK: topK,
    topP: topP,
    seed: seed,
    npuBackend: npuBackend,
    loraPath: loraPath,
    jsonSchemaConstraints: jsonSchemaConstraints,
  );

  /// Updates the native LiteRT-LM log level.
  void setMinLogLevel(int level) => _runtime.setMinLogLevel(level);

  /// Tokenizes text with the native LiteRT-LM tokenizer.
  List<int> tokenize(String text, {bool addSpecial = true}) =>
      _runtime.tokenize(text, addSpecial: addSpecial);

  /// Converts native LiteRT-LM token ids back to text.
  String detokenize(List<int> tokens) => _runtime.detokenize(tokens);

  /// Renders a message with the active native LiteRT-LM conversation template.
  ///
  /// The returned string is copied into Dart before the native conversation may
  /// invalidate the underlying buffer.
  String renderMessageToString(Map<String, dynamic> message) =>
      _runtime.renderMessageToString(message);

  /// Streams generated text from the active conversation.
  ///
  /// [repetitionPenalty] and [presencePenalty] apply as in
  /// [generateMessageJson].
  Stream<String> generate(
    String prompt, {
    int? maxOutputTokens,
    double? repetitionPenalty,
    double? presencePenalty,

    /// Streams generated text from the active conversation.
    ///
    /// [repetitionPenalty] and [presencePenalty] apply as in
    /// [generateMessageJson].
  }) {
    _validateLiteRtLmSendArguments(
      maxOutputTokens: maxOutputTokens,
      repetitionPenalty: repetitionPenalty,
      presencePenalty: presencePenalty,
    );
    return _runtime.generate(
      prompt,
      maxOutputTokens: maxOutputTokens,
      repetitionPenalty: repetitionPenalty,
      presencePenalty: presencePenalty,
    );
  }

  /// Streams generated text by sending a native LiteRT-LM message JSON object.
  ///
  /// [visualTokenBudget] configures the native image-token budget for
  /// multimodal messages.
  ///
  /// [repetitionPenalty] (at least 1.0) and [presencePenalty] penalize tokens
  /// that this send has already generated; prompt and history tokens are not
  /// counted. [thinkingTokenBudget] (at least 1) caps the tokens generated
  /// inside the thinking channel of the bundle before the runtime forces the
  /// channel closed, and enables thinking for this send. Both throw
  /// [LlamaUnsupportedException] when the runtime does not export their API;
  /// see [supportsSamplingPenalties] and [supportsThinkingBudget].
  Stream<String> generateMessageJson(
    String messageJson, {
    Map<String, dynamic>? extraContext,
    int? visualTokenBudget,
    int? maxOutputTokens,
    double? repetitionPenalty,
    double? presencePenalty,
    int? thinkingTokenBudget,
    String? jsonSchema,

    /// Streams generated text by sending a native LiteRT-LM message JSON object.
    ///
    /// [visualTokenBudget] configures the native image-token budget for
    /// multimodal messages.
    ///
    /// [repetitionPenalty] (at least 1.0) and [presencePenalty] penalize tokens
    /// that this send has already generated; prompt and history tokens are not
    /// counted. [thinkingTokenBudget] (at least 1) caps the tokens generated
    /// inside the thinking channel of the bundle before the runtime forces the
    /// channel closed, and enables thinking for this send. Both throw
    /// [LlamaUnsupportedException] when the runtime does not export their API;
    /// see [supportsSamplingPenalties] and [supportsThinkingBudget].
  }) {
    _validateLiteRtLmSendArguments(
      visualTokenBudget: visualTokenBudget,
      maxOutputTokens: maxOutputTokens,
      repetitionPenalty: repetitionPenalty,
      presencePenalty: presencePenalty,
      thinkingTokenBudget: thinkingTokenBudget,
    );
    return _runtime.generateMessageJson(
      messageJson,
      extraContext: extraContext,
      visualTokenBudget: visualTokenBudget,
      maxOutputTokens: maxOutputTokens,
      repetitionPenalty: repetitionPenalty,
      presencePenalty: presencePenalty,
      thinkingTokenBudget: thinkingTokenBudget,
      jsonSchema: jsonSchema,
    );
  }

  /// Runs a benchmark-style prompt loop and returns runtime metrics.
  Future<LiteRtLmRuntimeResult> run({
    required String prompt,
    int warmupRuns = 1,
    int measuredRuns = 3,

    /// Runs a benchmark-style prompt loop and returns runtime metrics.
  }) async {
    _validateLiteRtLmBenchmarkArguments(warmupRuns, measuredRuns);
    return _runtime.run(
      prompt: prompt,
      warmupRuns: warmupRuns,
      measuredRuns: measuredRuns,
    );
  }

  /// Reads runtime metrics for the active conversation.
  LiteRtLmRuntimeMetrics readMetrics({required int wallMilliseconds}) =>
      _runtime.readMetrics(wallMilliseconds: wallMilliseconds);

  /// Cancels active native generation.
  void cancel() => _selected?.cancel();

  /// Releases native LiteRT-LM resources.
  void dispose() => _selected?.dispose();
}
