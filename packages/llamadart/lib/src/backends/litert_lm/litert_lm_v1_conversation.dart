part of 'litert_lm_v1_runtime.dart';

typedef _OwnedCallbackN =
    Void Function(Pointer<Void>, Pointer<Utf8>, Bool, Pointer<Utf8>);
typedef _ChunkCallbackN = Void Function(Pointer<Void>, Pointer<Void>);
typedef _ProxyCreateN =
    Pointer<Void> Function(
      Pointer<NativeFunction<_OwnedCallbackN>>,
      Pointer<Void>,
      Pointer<Pointer<NativeFunction<_ChunkCallbackN>>>,
    );
typedef _ProxyCreateD =
    Pointer<Void> Function(
      Pointer<NativeFunction<_OwnedCallbackN>>,
      Pointer<Void>,
      Pointer<Pointer<NativeFunction<_ChunkCallbackN>>>,
    );
typedef _SendStreamN =
    Int Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Void>,
      Pointer<NativeFunction<_ChunkCallbackN>>,
      Pointer<Void>,
    );
typedef _SendStreamD =
    int Function(
      Pointer<Void>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Void>,
      Pointer<NativeFunction<_ChunkCallbackN>>,
      Pointer<Void>,
    );
typedef _StatusN = Int Function(Pointer<Void>);
typedef _StatusD = int Function(Pointer<Void>);

/// Internal C API 1.0 conversation used by the selected v1 client.
///
/// Chunks are copied native message JSON, not parsed content or tool calls.
/// Only one turn may run at a time. A cancelled or failed conversation is
/// deleted after its final callback and successful native drain; recreate it
/// through the runtime. This never enables single-threaded native execution.
final class LiteRtLmV1Conversation {
  LiteRtLmV1Conversation._(
    this._runtime,
    LiteRtLmV1ConversationSettings options,
  ) : _thinkingExtraContext =
          options._preface['litert_lm_conversation_config_set_extra_context'] {
    final history =
        options._preface['litert_lm_conversation_config_set_messages'];
    if (history != null) {
      _runtime._validateMediaMessages(jsonDecode(history) as List);
    }
    _schemaEnabled = options.jsonSchemaConstraints;
    _schemaThinking =
        _schemaEnabled &&
        _thinkingExtraContext != null &&
        (jsonDecode(_thinkingExtraContext) as Map)['enable_thinking'] == true;
    if (_schemaEnabled) _V1JsonSchema(_runtime).requireSupport();
    final library = _runtime._library;
    for (final symbol in _symbols) {
      if (!library.providesSymbol(symbol)) {
        throw LlamaUnsupportedException(
          'C API 1.0 conversation preparation requires owner export $symbol.',
        );
      }
    }
    final abi = library.lookupFunction<Int32 Function(), int Function()>(
      'stream_proxy_callback_abi_version',
    )();
    if (abi != 2) {
      throw LlamaUnsupportedException(
        'C API 1.0 conversation requires owner stream proxy callback ABI 2; detected $abi.',
      );
    }
    final allocationAbi = library
        .lookupFunction<Int32 Function(), int Function()>(
          'stream_proxy_allocation_failure_abi_version',
        )();
    if (allocationAbi != 1) {
      throw LlamaUnsupportedException(
        'C API 1.0 conversation requires owner stream proxy allocation-failure ABI 1; detected $allocationAbi.',
      );
    }
    Pointer<Void> sessionConfig = nullptr, sampler = nullptr, config = nullptr;
    final strings = <Pointer<Utf8>>[];
    try {
      sessionConfig = _runtime._create(
        'session_config_create',
        _runtime._configCreate,
      );
      _runtime._check(
        _runtime._setOutputTokens(sessionConfig, options.maxOutputTokens),
        'set_max_output_tokens',
      );
      if (options.sampler case final selected?) {
        sampler = _runtime._create(
          'sampler_params_create',
          (out) => _runtime._samplerCreate(2, out),
        );
        _runtime._check(
          _runtime._samplerTopK(
            sampler,
            liteRtLmEffectiveTopK(
              temperature: selected.temperature,
              topK: selected.topK,
            ),
          ),
          'sampler_set_top_k',
        );
        _runtime._check(
          _runtime._samplerTopP(sampler, selected.topP),
          'sampler_set_top_p',
        );
        _runtime._check(
          _runtime._samplerTemperature(sampler, selected.temperature),
          'sampler_set_temperature',
        );
        _runtime._check(
          _runtime._library.lookupFunction<
            Int Function(Pointer<Void>, Int32),
            int Function(Pointer<Void>, int)
          >('litert_lm_sampler_params_set_seed')(sampler, selected.seed),
          'sampler_set_seed',
        );
        _runtime._check(
          _runtime._setSampler(sessionConfig, sampler),
          'set_sampler_params',
        );
      }
      config = _runtime._create('conversation_config_create', _configCreate);
      _runtime._check(
        _setSessionConfig(config, sessionConfig),
        'conversation_config_set_session_config',
      );
      for (final entry in options._preface.entries) {
        final text = entry.value.toNativeUtf8(allocator: calloc);
        strings.add(text);
        _runtime._check(
          _runtime._library.lookupFunction<_SetStringN, _SetStringD>(entry.key)(
            config,
            text,
          ),
          entry.key,
        );
      }
      _runtime._check(
        _runtime._library.lookupFunction<_SetBoolN, _SetBoolD>(
          'litert_lm_conversation_config_set_enable_constrained_decoding',
        )(config, false),
        'set_enable_constrained_decoding',
      );
      if (_schemaEnabled) {
        _V1JsonSchema(_runtime).configure(config, thinking: _schemaThinking);
      }
      _handle = _runtime._create(
        'conversation_create',
        (out) => _createConversation(_runtime._engine, config, out),
      );
    } finally {
      if (config != nullptr) _configDelete(config);
      if (sampler != nullptr) _runtime._samplerDelete(sampler);
      if (sessionConfig != nullptr) _runtime._configDelete(sessionConfig);
      for (final text in strings) {
        calloc.free(text);
      }
    }
  }

  static const _symbols = <String>[
    'litert_lm_sampler_params_set_seed',
    'litert_lm_conversation_config_set_system_message',
    'litert_lm_conversation_config_set_messages',
    'litert_lm_conversation_config_set_tools',
    'litert_lm_conversation_config_set_extra_context',
    'litert_lm_conversation_config_set_prompt_template',
    'litert_lm_conversation_config_set_enable_constrained_decoding',
    'stream_proxy_callback_abi_version',
    'stream_proxy_allocation_failure_abi_version',
    'stream_proxy_has_allocation_failure',
    'stream_proxy_create',
    'stream_proxy_delete',
    'stream_proxy_free_string',
    'litert_lm_conversation_config_create',
    'litert_lm_conversation_config_delete',
    'litert_lm_conversation_config_set_session_config',
    'litert_lm_conversation_create',
    'litert_lm_conversation_delete',
    'litert_lm_conversation_send_message_stream',
    'litert_lm_conversation_cancel_process',
    'litert_lm_conversation_wait_until_done',
  ];

  final LiteRtLmV1Runtime _runtime;
  final String? _thinkingExtraContext;
  Pointer<Void> _handle = nullptr;
  LiteRtLmV1Turn? _turn;
  bool _quarantined = false;
  legacy.LiteRtLmRuntimeMetrics? _releasedMetrics;
  late final bool _schemaEnabled;
  late final bool _schemaThinking;

  /// Only a final callback followed by successful native drain settles a turn.
  LiteRtLmNativeSettlement get nativeSettlement => _quarantined
      ? LiteRtLmNativeSettlement.quarantined
      : _turn != null
      ? LiteRtLmNativeSettlement.pending
      : LiteRtLmNativeSettlement.settled;

  late final _configCreate = _runtime._library
      .lookupFunction<_CreateN, _CreateD>(
        'litert_lm_conversation_config_create',
      );
  late final _configDelete = _runtime._library
      .lookupFunction<_DeleteN, _DeleteD>(
        'litert_lm_conversation_config_delete',
      );
  late final _setSessionConfig = _runtime._library
      .lookupFunction<_SetPointerN, _SetPointerD>(
        'litert_lm_conversation_config_set_session_config',
      );
  late final _createConversation = _runtime._library
      .lookupFunction<_SessionN, _SessionD>('litert_lm_conversation_create');
  late final _delete = _runtime._library.lookupFunction<_DeleteN, _DeleteD>(
    'litert_lm_conversation_delete',
  );
  late final _send = _runtime._library
      .lookupFunction<_SendStreamN, _SendStreamD>(
        'litert_lm_conversation_send_message_stream',
      );
  late final _cancel = _runtime._library.lookupFunction<_StatusN, _StatusD>(
    'litert_lm_conversation_cancel_process',
  );
  late final _wait = _runtime._library.lookupFunction<_StatusN, _StatusD>(
    'litert_lm_conversation_wait_until_done',
  );
  late final _proxyCreate = _runtime._library
      .lookupFunction<_ProxyCreateN, _ProxyCreateD>('stream_proxy_create');
  late final _proxyHasAllocationFailure = _runtime._library
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('stream_proxy_has_allocation_failure');
  late final _proxyDelete = _runtime._library
      .lookupFunction<_DeleteN, _DeleteD>('stream_proxy_delete');
  late final _freeString = _runtime._library
      .lookupFunction<
        Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)
      >('stream_proxy_free_string');

  /// Starts one text-only turn. Inspect [LiteRtLmV1Turn.done] for failures.
  ///
  /// The chunks stream closes after drain; errors are reported only by done,
  /// allowing a caller to await completion without subscribing to chunks.
  /// Null [settings] inherits conversation limits without applying penalties.
  LiteRtLmV1Turn sendText(String text, {LiteRtLmV1TurnSettings? settings}) {
    _requireReadyForSend();
    if (text.contains('\u0000')) {
      throw LlamaArgumentException('Conversation text must not contain NUL.');
    }
    return _sendEncoded(
      jsonEncode({'role': 'user', 'content': text}),
      settings,
    );
  }

  /// Sends the snapshotted text/tool message subset accepted by the preface.
  /// Media and unknown fields remain explicitly refused before native work.
  LiteRtLmV1Turn sendMessage(
    Map<String, Object?> message, {
    LiteRtLmV1TurnSettings? settings,
    Map<String, Object?>? extraContext,
  }) {
    _requireReadyForSend();
    LiteRtLmV1ConversationSettings._jsonValue(
      message,
      HashSet<Object>.identity(),
    );
    final encoded = jsonEncode(message);
    final snapshot = jsonDecode(encoded);
    LiteRtLmV1ConversationSettings._messages([snapshot]);
    _runtime._validateMediaMessages([snapshot]);
    String? context;
    if (extraContext?.isNotEmpty ?? false) {
      LiteRtLmV1ConversationSettings._jsonValue(
        extraContext,
        HashSet<Object>.identity(),
      );
      context = jsonEncode(extraContext);
    }
    return _sendEncoded(encoded, settings, extraContext: context);
  }

  void _requireReadyForSend() {
    if (_quarantined || _handle == nullptr || _turn != null) {
      throw LlamaStateException(
        'C API 1.0 conversation is closed, quarantined or already streaming.',
      );
    }
  }

  LiteRtLmV1Turn _sendEncoded(
    String encoded,
    LiteRtLmV1TurnSettings? settings, {
    String? extraContext,
  }) {
    if (settings?.jsonSchema != null && !_schemaEnabled) {
      throw LlamaUnsupportedException(
        'Create the C API 1.0 conversation with jsonSchemaConstraints before sending a schema.',
      );
    }
    settings?._validate(_runtime, extraContext: extraContext);
    final args = settings?._createArgs(_runtime) ?? nullptr;
    try {
      final turn = LiteRtLmV1Turn._(this);
      _turn = turn;
      try {
        turn._start(encoded, args, extraContext: extraContext);
        return turn;
      } on Object {
        _turn = null;
        _release();
        rethrow;
      }
    } finally {
      // The C entry point copies these values before launching native work.
      // This says nothing about whether the callback family has settled.
      if (args != nullptr) {
        _runtime._library.lookupFunction<_DeleteN, _DeleteD>(
          'litert_lm_conversation_optional_args_delete',
        )(args);
      }
    }
  }

  void _release() {
    if (_handle != nullptr) _delete(_handle);
    _handle = nullptr;
    if (identical(_runtime._conversation, this)) {
      _runtime._conversation = null;
    }
  }

  /// Deletes an idle conversation exactly once.
  ///
  /// Cancel and await the active turn before closing. Failed drain quarantines
  /// the native family: closing/reuse/disposal is refused rather than risking
  /// a callback use-after-free. A missing final callback also retains handles.
  void close() {
    if (_quarantined || _turn != null) {
      throw LlamaStateException(
        'Await a successful C API 1.0 stream drain before closing.',
      );
    }
    _release();
  }
}

/// A drained internal turn whose proxy could not copy all callback data.
///
/// Native callbacks are settled, but the child conversation is discarded because
/// its output/history cannot be trusted. The finish reason remains the actual
/// native terminal cause; allocation loss never converts cancellation into success.
final class LiteRtLmV1CopyLossException extends LlamaModelException {
  LiteRtLmV1CopyLossException._(this.finishReason, this.streamFailure)
    : super('C API 1.0 stream proxy lost callback data during allocation.');

  /// Independently observed native terminal cause, or unknown without its ABI.
  final LiteRtLmFinishReason finishReason;

  /// Any copied stream failure, already sanitized before native storage is freed.
  final LlamaModelException? streamFailure;
}

/// An owned internal streaming turn. Strings are copied before native return.
final class LiteRtLmV1Turn {
  LiteRtLmV1Turn._(this._conversation) {
    _chunks = StreamController<String>(onCancel: cancel);
  }

  final LiteRtLmV1Conversation _conversation;
  final Completer<LiteRtLmFinishReason> _done = Completer();
  late final StreamController<String> _chunks;
  late final NativeCallable<_OwnedCallbackN> _callback;
  Pointer<Void> _proxy = nullptr;
  Pointer<Utf8> _message = nullptr;
  Pointer<Utf8> _extraContext = nullptr;
  bool _cancelled = false;
  bool _finished = false;
  LlamaModelException? _error;
  bool _errorIsCancellation = false;
  LiteRtLmFinishReason? _finishReason;

  /// Actual cause read after final and successful drain, including on copy loss.
  /// Failed drain leaves this null because the live proxy cannot be inspected.
  LiteRtLmFinishReason? get finishReason => _finishReason;

  /// Copied raw message JSON chunks; no borrowed native pointer escapes.
  Stream<String> get chunks => _chunks.stream;

  /// Completes only after a final callback and successful native drain.
  ///
  /// Failures, including native drain failure, reject this future. A native
  /// cancellation is a terminal reason, never permission to reuse its handle.
  Future<LiteRtLmFinishReason> get done => _done.future;

  void _start(String message, Pointer<Void> args, {String? extraContext}) {
    _message = message.toNativeUtf8(allocator: calloc);
    _callback = NativeCallable<_OwnedCallbackN>.listener(_onChunk);
    final out = calloc<Pointer<NativeFunction<_ChunkCallbackN>>>();
    try {
      _extraContext = extraContext?.toNativeUtf8(allocator: calloc) ?? nullptr;
      _proxy = _conversation._proxyCreate(
        _callback.nativeFunction,
        nullptr,
        out,
      );
      if (_proxy == nullptr || out.value == nullptr) {
        throw LlamaStateException('C API 1.0 stream proxy allocation failed.');
      }
      // Read the thread-local error on this same thread before any other call.
      try {
        _conversation._runtime._check(
          _conversation._send(
            _conversation._handle,
            _message,
            _extraContext,
            args,
            out.value,
            _proxy,
          ),
          'conversation_send_message_stream',
        );
      } on LlamaModelException catch (error, stackTrace) {
        Error.throwWithStackTrace(
          LiteRtLmSendFailureException(error.message, error.details),
          stackTrace,
        );
      }
    } on Object {
      _cleanup();
      rethrow;
    } finally {
      calloc.free(out);
    }
  }

  /// Requests cancellation without freeing callbacks or waiting for native work.
  /// Later chunks are freed and suppressed; the conversation is deleted only
  /// after final+drain. Repeated or completed cancellation is harmless.
  void cancel() {
    if (_finished || _cancelled) return;
    _cancelled = true;
    _conversation._runtime._check(
      _conversation._cancel(_conversation._handle),
      'conversation_cancel_process',
    );
  }

  void _onChunk(
    Pointer<Void> data,
    Pointer<Utf8> chunk,
    bool isFinal,
    Pointer<Utf8> error,
  ) {
    try {
      if (!_finished) {
        if (error != nullptr && _error == null) {
          final nativeError = error.toDartString();
          _errorIsCancellation = RegExp(
            r'^CANCELLED(?::|$)',
          ).hasMatch(nativeError);
          _error = LlamaModelException(
            'C API 1.0 stream failed: ${liteRtLmNativeErrorDetail(code: -1, message: nativeError, paths: _conversation._runtime._diagnosticPaths)}',
          );
        }
        if (chunk != nullptr && !_cancelled && _error == null) {
          _chunks.add(chunk.toDartString());
        }
      }
    } on Object {
      _error ??= LlamaModelException(
        'C API 1.0 stream returned invalid callback data.',
      );
    } finally {
      if (chunk != nullptr) _conversation._freeString(chunk);
      if (error != nullptr) _conversation._freeString(error);
    }
    if (isFinal && !_finished) _finish();
  }

  void _finish() {
    _finished = true;
    final runtime = _conversation._runtime;
    var reason = LiteRtLmFinishReason.unknown;
    try {
      runtime._check(
        _conversation._wait(_conversation._handle),
        'conversation_wait_until_done',
      );
    } on Object catch (failure) {
      // Failed drain supplies no proof that callbacks have stopped. Retain the
      // callback, proxy, message, child and parent instead of unsafe cleanup.
      _conversation._quarantined = true;
      _done.completeError(failure);
      unawaited(_chunks.close());
      return;
    }
    final library = runtime._library;
    if (library.providesSymbol('stream_proxy_finish_reason_abi_version') &&
        library.providesSymbol('stream_proxy_get_finish_reason') &&
        library.lookupFunction<Int32 Function(), int Function()>(
              'stream_proxy_finish_reason_abi_version',
            )() ==
            1) {
      reason = LiteRtLmFinishReason.fromWire(
        library.lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('stream_proxy_get_finish_reason')(_proxy),
      );
    }
    _finishReason = reason;
    // The sticky allocation-free status is readable only while the proxy is
    // alive, after final+drain. A clean final must not hide an earlier lost copy.
    if (_conversation._proxyHasAllocationFailure(_proxy) != 0) {
      _error = LiteRtLmV1CopyLossException._(reason, _error);
    } else if (_errorIsCancellation &&
        reason == LiteRtLmFinishReason.cancelled) {
      // Canonical cancellation is normal only with an independent native cause.
      _error = null;
    }
    if (reason == LiteRtLmFinishReason.error && _error == null) {
      _error = LlamaModelException(
        'C API 1.0 stream ended with a native error.',
      );
    }
    _cleanup();
    _conversation._turn = null;
    if (_cancelled && _error == null) {
      _conversation._captureMetricsBeforeRelease();
    }
    if (_cancelled ||
        _error != null ||
        reason == LiteRtLmFinishReason.cancelled ||
        reason == LiteRtLmFinishReason.error) {
      _conversation._release();
    }
    unawaited(_chunks.close());
    if (_error case final failure?) {
      _done.completeError(failure);
    } else {
      _done.complete(reason);
    }
  }

  void _cleanup() {
    if (_proxy != nullptr) _conversation._proxyDelete(_proxy);
    _proxy = nullptr;
    _callback.close();
    if (_message != nullptr) calloc.free(_message);
    _message = nullptr;
    if (_extraContext != nullptr) calloc.free(_extraContext);
    _extraContext = nullptr;
  }
}
