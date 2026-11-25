part of 'llama_cpp_service.dart';

const int _asrStreamMaxTransferSamples = 5120;
const int _asrStreamReadTextCapacity = 4096;
const int _asrStreamRequiredSampleRate = 16000;
const int _asrStreamRequiredChannels = 1;
const int _asrStreamPromptedContextFloor = 2048;
const int _asrStreamProjectorMetadataByteCap = 1 << 20;
const int _asrStreamMaxDiagnosticChars = 512;
const int _asrStreamMaxIdleWorkingSteps = 10000;

final class _AsrStreamProbeResult {
  final _AsrStreamApi api;
  final int mode;
  final String projectorType;

  const _AsrStreamProbeResult({
    required this.api,
    required this.mode,
    required this.projectorType,
  });
}

final class _AsrStreamSession {
  final int sessionId;
  final int modelHandle;
  final int contextHandle;
  final int mmContextHandle;
  final Pointer<llama_context> context;
  final Pointer<llama_model> model;
  final Pointer<mtmd_context> projector;
  final _AsrStreamApi api;
  final Pointer<llama_dart_asr_stream> stream;
  final Pointer<Float> pcmBuffer;
  final Pointer<Size> sizeOut;
  final Pointer<llama_dart_asr_stream_progress> progress;
  final Pointer<Char> textBuffer;
  final Pointer<Int8> cancelFlag;
  final void Function(String confirmedText, int acceptedSamples) onText;

  int suppliedSamples = 0;
  int acceptedSamples = 0;
  int lastSamplesConsumed = 0;
  int lastSegmentBreaks = 0;
  bool pendingSegmentBreak = false;
  bool hasVisibleText = false;
  String confirmedText = '';
  bool inFlight = false;
  bool finishing = false;
  bool cancelled = false;
  bool closed = false;

  _AsrStreamSession({
    required this.sessionId,
    required this.modelHandle,
    required this.contextHandle,
    required this.mmContextHandle,
    required this.context,
    required this.model,
    required this.projector,
    required this.api,
    required this.stream,
    required this.pcmBuffer,
    required this.sizeOut,
    required this.progress,
    required this.textBuffer,
    required this.cancelFlag,
    required this.onText,
  });
}

/// Package-internal live ASR stream probe, session lifecycle, and decode loop.
extension LlamaCppServiceAsrStream on LlamaCppService {
  Future<String?> _readAsrProjectorType(int mmContextHandle) async {
    if (_mtmdProjectorTypes.containsKey(mmContextHandle)) {
      return _mtmdProjectorTypes[mmContextHandle];
    }
    final location = _mtmdProjectorPaths[mmContextHandle];
    if (location == null || location.isEmpty) {
      return null;
    }
    RandomAccessFile? file;
    try {
      file = File(location).openSync(mode: FileMode.read);
      final fileLength = file.lengthSync();
      final metadata = await readGgufMetadata(
        (offset, length) async {
          if (offset < 0 || offset >= fileLength || length <= 0) {
            return Uint8List(0);
          }
          final clamped = math.min(length, fileLength - offset);
          file!.setPositionSync(offset);
          return file.readSync(clamped);
        },
        maxBytes: _asrStreamProjectorMetadataByteCap,
        stopAt: 'clip.projector_type',
      );
      final type =
          metadata['clip.projector_type'] ??
          metadata['clip.audio.projector_type'];
      final resolved = type is String ? type : null;
      _mtmdProjectorTypes[mmContextHandle] = resolved;
      return resolved;
    } catch (_) {
      _mtmdProjectorTypes[mmContextHandle] = null;
      return null;
    } finally {
      try {
        file?.closeSync();
      } catch (_) {}
    }
  }

  ({
    int modelHandle,
    _LlamaModelWrapper model,
    _LlamaContextWrapper context,
    Pointer<mtmd_context> projector,
  })
  _requireMatchingAsrHandles(int contextHandle, int mmContextHandle) {
    final modelHandle = _contextToModel[contextHandle];
    final context = _contexts[contextHandle];
    final model = modelHandle != null ? _models[modelHandle] : null;
    final projector = _mtmdContexts[mmContextHandle];
    if (modelHandle == null ||
        context == null ||
        model == null ||
        projector == null ||
        _modelToMtmd[modelHandle] != mmContextHandle) {
      throw LlamaStateException(
        'Context $contextHandle and multimodal projector $mmContextHandle do '
        'not match a live loaded pair.',
      );
    }
    _calls.failures.ensureUsable(
      model.pointer,
      'This speech recognition model',
    );
    _calls.failures.ensureUsable(
      context.pointer,
      'This speech recognition context',
    );
    _calls.failures.ensureUsable(projector, 'This multimodal projector');
    return (
      modelHandle: modelHandle,
      model: model,
      context: context,
      projector: projector,
    );
  }

  Future<({String? unsupportedReason, _AsrStreamProbeResult? probe})>
  _probeAsrStream(int contextHandle, int mmContextHandle) async {
    final handles = _requireMatchingAsrHandles(contextHandle, mmContextHandle);
    final _AsrStreamApi api;
    try {
      api = _resolveAsrStreamApi();
    } on LlamaUnsupportedException catch (error) {
      return (unsupportedReason: error.message, probe: null);
    }
    if (api.acceptedModes == 0) {
      return (
        unsupportedReason:
            'Live speech recognition is unsupported by this native runtime '
            '(no supported streaming modes).',
        probe: null,
      );
    }

    final projectorType = await _readAsrProjectorType(mmContextHandle);
    if (projectorType != 'voxtral_rt' && projectorType != 'lfm3a') {
      return (
        unsupportedReason:
            'Live speech recognition is unsupported for projector type '
            '"${projectorType ?? 'unknown'}".',
        probe: null,
      );
    }

    final outInfo = calloc<llama_dart_asr_stream_info>();
    try {
      outInfo.ref.struct_size = sizeOf<llama_dart_asr_stream_info>();
      final status = _calls.asrStreamGetInfo(
        context: handles.context.pointer,
        model: handles.model.pointer,
        projector: handles.projector,
        acceptedModes: api.acceptedModes,
        outInfo: outInfo,
        getInfo: api.getInfo,
      );
      if (status ==
          llama_dart_asr_stream_status
              .LLAMA_DART_ASR_STREAM_STATUS_UPSTREAM_ERROR
              .value) {
        throw LlamaSpeechException(
          'Native live speech recognition probe failed.',
        );
      }
      if (status !=
          llama_dart_asr_stream_status.LLAMA_DART_ASR_STREAM_STATUS_OK.value) {
        return (
          unsupportedReason:
              'Live speech recognition is unsupported by the loaded model, '
              'projector, or runtime.',
          probe: null,
        );
      }

      final info = outInfo.ref;
      if (info.api_version != LLAMA_DART_ASR_STREAM_API_VERSION) {
        return (
          unsupportedReason:
              'Live speech recognition info ABI v${info.api_version} is '
              'unsupported.',
          probe: null,
        );
      }
      final mode = info.mode;
      final tokenDelay = llama_dart_asr_stream_mode
          .LLAMA_DART_ASR_STREAM_MODE_TOKEN_DELAY
          .value;
      final promptedChunks = llama_dart_asr_stream_mode
          .LLAMA_DART_ASR_STREAM_MODE_PROMPTED_CHUNKS
          .value;
      if ((mode != tokenDelay && mode != promptedChunks) ||
          (api.acceptedModes & (1 << mode)) == 0) {
        return (
          unsupportedReason:
              'Live speech recognition mode $mode is unsupported.',
          probe: null,
        );
      }
      if ((projectorType == 'voxtral_rt' && mode != tokenDelay) ||
          (projectorType == 'lfm3a' && mode != promptedChunks)) {
        return (
          unsupportedReason:
              'Live speech recognition mode $mode does not match projector '
              'type "$projectorType".',
          probe: null,
        );
      }
      if (info.sample_rate != _asrStreamRequiredSampleRate ||
          info.channels != _asrStreamRequiredChannels) {
        return (
          unsupportedReason:
              'Live speech recognition requires 16000 Hz mono PCM '
              '(reported ${info.sample_rate} Hz, ${info.channels} channels).',
          probe: null,
        );
      }

      final seqCapacity = _calls.contextSequenceCapacity(
        handles.context.pointer,
      );
      if (mode == promptedChunks &&
          seqCapacity < _asrStreamPromptedContextFloor) {
        return (
          unsupportedReason:
              'Live speech recognition for LFM3-Audio requires at least '
              '$_asrStreamPromptedContextFloor per-sequence context positions '
              '(allocated: $seqCapacity).',
          probe: null,
        );
      }
      if (seqCapacity <= 0) {
        return (
          unsupportedReason:
              'Live speech recognition requires positive per-sequence context '
              'capacity (allocated: $seqCapacity).',
          probe: null,
        );
      }

      return (
        unsupportedReason: null,
        probe: _AsrStreamProbeResult(
          api: api,
          mode: mode,
          projectorType: projectorType!,
        ),
      );
    } finally {
      calloc.free(outInfo);
    }
  }

  Future<String?> _asrStreamUnsupportedReason(
    int contextHandle,
    int mmContextHandle,
  ) async {
    final result = await _probeAsrStream(contextHandle, mmContextHandle);
    return result.unsupportedReason;
  }

  Future<void> _startAsrStream(
    int sessionId,
    int contextHandle,
    int mmContextHandle,
    int cancelFlagAddress, {
    required void Function(String confirmedText, int acceptedSamples) onText,
  }) async {
    if (_activeAsrStreamSession != null) {
      throw LlamaStateException(
        'A live speech recognition session is already active.',
      );
    }
    if (_activeTts != nullptr) {
      throw LlamaStateException(
        'Cannot start live speech recognition while text-to-speech is active.',
      );
    }
    if (_generatingContexts.containsKey(contextHandle)) {
      throw LlamaStateException(
        'Cannot start live speech recognition while generation is active.',
      );
    }

    final handles = _requireMatchingAsrHandles(contextHandle, mmContextHandle);
    final probeResult = await _probeAsrStream(contextHandle, mmContextHandle);
    final probe = probeResult.probe;
    if (probe == null) {
      throw LlamaUnsupportedException(
        probeResult.unsupportedReason ??
            'Live speech recognition is unsupported.',
      );
    }

    final cancelFlag = cancelFlagAddress == 0
        ? nullptr
        : Pointer<Int8>.fromAddress(cancelFlagAddress);
    if (cancelFlag != nullptr && cancelFlag.value != 0) {
      throw LlamaSpeechException('Live speech recognition was cancelled.');
    }

    final api = probe.api;
    final params = malloc<llama_dart_asr_stream_params>();
    final outStatus = malloc<Int>();
    Pointer<llama_dart_asr_stream> stream = nullptr;
    try {
      params.ref = api.paramsDefault();
      params.ref.struct_size = sizeOf<llama_dart_asr_stream_params>();
      params.ref.sequence_id = 0;
      outStatus.value = 0;

      // ASR init clears sequence 0 in native KV memory, so any cached prompt
      // tokens or state-load marker on this context are invalidated before
      // calling native init, which can still fail after running seq_rm.
      handles.context.cachedPromptTokens = null;
      handles.context.kvFromStateLoad = false;

      stream = _calls.asrStreamInit(
        context: handles.context.pointer,
        model: handles.model.pointer,
        projector: handles.projector,
        acceptedModes: api.acceptedModes,
        params: params,
        outStatus: outStatus,
        init: api.init,
        freeAddress: api.freeAddress,
      );
      if (stream == nullptr) {
        final status = outStatus.value;
        if (status ==
            llama_dart_asr_stream_status
                .LLAMA_DART_ASR_STREAM_STATUS_UNSUPPORTED
                .value) {
          throw LlamaUnsupportedException(
            'Live speech recognition is unsupported by the loaded model, '
            'projector, or runtime.',
          );
        }
        if (status ==
            llama_dart_asr_stream_status
                .LLAMA_DART_ASR_STREAM_STATUS_CANCELLED
                .value) {
          throw LlamaSpeechException('Live speech recognition was cancelled.');
        }
        if (status ==
            llama_dart_asr_stream_status
                .LLAMA_DART_ASR_STREAM_STATUS_INVALID_STATE
                .value) {
          throw LlamaStateException(
            'Live speech recognition initialization is not valid in this state.',
          );
        }
        throw LlamaSpeechException(
          'Live speech recognition initialization failed.',
        );
      }

      if (cancelFlag != nullptr) {
        final flagStatus = _calls.asrStreamSetCancelFlag(
          stream: stream,
          context: handles.context.pointer,
          model: handles.model.pointer,
          projector: handles.projector,
          flag: cancelFlag,
          setCancelFlag: api.setCancelFlag,
        );
        if (flagStatus !=
            llama_dart_asr_stream_status
                .LLAMA_DART_ASR_STREAM_STATUS_OK
                .value) {
          final error = _readAsrStreamError(api, stream);
          _calls.asrStreamFree(stream, api.free);
          stream = nullptr;
          throw LlamaSpeechException(
            'Live speech recognition cancel registration failed.',
            error,
          );
        }
      }

      final pcmBuffer = malloc<Float>(_asrStreamMaxTransferSamples);
      final sizeOut = malloc<Size>();
      final progress = calloc<llama_dart_asr_stream_progress>();
      final textBuffer = malloc<Char>(_asrStreamReadTextCapacity);

      _activeAsrStreamSession = _AsrStreamSession(
        sessionId: sessionId,
        modelHandle: handles.modelHandle,
        contextHandle: contextHandle,
        mmContextHandle: mmContextHandle,
        context: handles.context.pointer,
        model: handles.model.pointer,
        projector: handles.projector,
        api: api,
        stream: stream,
        pcmBuffer: pcmBuffer,
        sizeOut: sizeOut,
        progress: progress,
        textBuffer: textBuffer,
        cancelFlag: cancelFlag,
        onText: onText,
      );
      stream = nullptr;
    } catch (_) {
      if (stream != nullptr) {
        _calls.asrStreamFree(stream, api.free);
      }
      rethrow;
    } finally {
      malloc.free(params);
      malloc.free(outStatus);
    }
  }

  Future<int> _pushAsrPcm(
    int sessionId,
    int sampleOffset,
    Float32List samples,
  ) async {
    final session = _requireActiveAsrSession(sessionId);
    if (session.finishing || session.closed) {
      throw LlamaStateException(
        'Cannot push audio to a finishing or closed speech recognition '
        'session.',
      );
    }
    if (session.inFlight) {
      throw LlamaStateException(
        'Another live speech recognition operation is already in progress.',
      );
    }
    if (sampleOffset != session.suppliedSamples) {
      throw LlamaStateException(
        'Unexpected live speech recognition sample offset $sampleOffset '
        '(expected ${session.suppliedSamples}).',
      );
    }
    if (samples.isEmpty || samples.length > _asrStreamMaxTransferSamples) {
      throw LlamaAudioFormatException(
        'Live speech recognition chunk length ${samples.length} is outside '
        '1..$_asrStreamMaxTransferSamples.',
      );
    }

    session.inFlight = true;
    session.suppliedSamples += samples.length;
    try {
      var offset = 0;
      while (offset < samples.length) {
        _checkAsrCancelled(session);
        final remaining = samples.length - offset;
        session.pcmBuffer
            .asTypedList(remaining)
            .setAll(0, samples.sublist(offset));
        session.sizeOut.value = 0;

        final status = _calls.asrStreamPush(
          stream: session.stream,
          context: session.context,
          model: session.model,
          projector: session.projector,
          samples: session.pcmBuffer,
          sampleCount: remaining,
          outAccepted: session.sizeOut,
          push: session.api.push,
        );
        _throwForAsrStatus(session, status, operation: 'audio push');

        final accepted = session.sizeOut.value;
        if (accepted < 0 || accepted > remaining) {
          throw LlamaSpeechException(
            'Native live speech recognition reported invalid accepted sample '
            'count $accepted for $remaining offered samples.',
          );
        }
        offset += accepted;
        session.acceptedSamples += accepted;

        final drainedWithProgress = await _drainAsrSteps(
          session,
          expectingFinish: false,
        );
        if (offset < samples.length && accepted == 0 && !drainedWithProgress) {
          throw LlamaSpeechException(
            'Native live speech recognition made no progress on buffered '
            'audio.',
          );
        }
      }
      return session.acceptedSamples;
    } catch (_) {
      _closeAsrSession(session);
      rethrow;
    } finally {
      session.inFlight = false;
    }
  }

  Future<({String finalText, int acceptedSamples, int consumedSamples})>
  _finishAsrStream(int sessionId, int expectedTotalSamples) async {
    final session = _requireActiveAsrSession(sessionId);
    if (session.finishing || session.closed) {
      throw LlamaStateException(
        'Live speech recognition finish was already requested.',
      );
    }
    if (session.inFlight) {
      throw LlamaStateException(
        'Another live speech recognition operation is already in progress.',
      );
    }
    if (expectedTotalSamples != session.suppliedSamples) {
      throw LlamaStateException(
        'Live speech recognition finish sample total $expectedTotalSamples '
        'does not match supplied samples ${session.suppliedSamples}.',
      );
    }

    session.inFlight = true;
    session.finishing = true;
    try {
      _checkAsrCancelled(session);
      final status = _calls.asrStreamFinish(
        stream: session.stream,
        context: session.context,
        model: session.model,
        projector: session.projector,
        finish: session.api.finish,
      );
      _throwForAsrStatus(session, status, operation: 'stream finish');

      await _drainAsrSteps(session, expectingFinish: true);
      final consumed = session.progress.ref.samples_consumed;
      if (consumed < 0 || consumed > session.acceptedSamples) {
        throw LlamaSpeechException(
          'Native live speech recognition reported invalid consumed sample '
          'count $consumed (accepted ${session.acceptedSamples}).',
        );
      }
      if (consumed < session.acceptedSamples) {
        throw LlamaSpeechTranscriptTruncatedException(
          'Live speech recognition ended before consuming all accepted audio.',
          limit: LlamaSpeechTranscriptLimit.runtime,
          partialTranscript: session.confirmedText,
        );
      }
      return (
        finalText: session.confirmedText,
        acceptedSamples: session.acceptedSamples,
        consumedSamples: consumed,
      );
    } finally {
      session.inFlight = false;
      _closeAsrSession(session);
    }
  }

  void _cancelAsrStream([int? sessionId]) {
    final session = _activeAsrStreamSession;
    if (session == null) {
      return;
    }
    if (sessionId != null && session.sessionId != sessionId) {
      return;
    }
    session.cancelled = true;
    if (!session.closed && session.stream != nullptr) {
      session.api.cancel(session.stream);
    }
  }

  void _closeAsrStreamIfIdle([int? sessionId]) {
    final session = _activeAsrStreamSession;
    if (session == null) {
      return;
    }
    if (sessionId != null && session.sessionId != sessionId) {
      return;
    }
    if (!session.inFlight) {
      _closeAsrSession(session);
    }
  }

  _AsrStreamSession _requireActiveAsrSession(int sessionId) {
    final session = _activeAsrStreamSession;
    if (session == null || session.sessionId != sessionId) {
      throw LlamaStateException(
        'Live speech recognition session $sessionId is not active.',
      );
    }
    return session;
  }

  void _checkAsrCancelled(_AsrStreamSession session) {
    if (session.cancelled ||
        (session.cancelFlag != nullptr && session.cancelFlag.value != 0)) {
      throw LlamaSpeechException('Live speech recognition was cancelled.');
    }
  }

  Future<bool> _drainAsrSteps(
    _AsrStreamSession session, {
    required bool expectingFinish,
  }) async {
    var anyProgress = false;
    var idleWorkingSteps = 0;
    var lastBuffered = -1;
    var lastConsumed = session.lastSamplesConsumed;
    var lastTokens = -1;
    var lastTextAvailable = -1;
    var lastBreaks = session.lastSegmentBreaks;

    while (true) {
      _checkAsrCancelled(session);
      session.progress.ref.struct_size =
          sizeOf<llama_dart_asr_stream_progress>();
      final status = _calls.asrStreamStep(
        stream: session.stream,
        context: session.context,
        model: session.model,
        projector: session.projector,
        outProgress: session.progress,
        step: session.api.step,
      );

      final progress = session.progress.ref;
      if (status ==
          llama_dart_asr_stream_status
              .LLAMA_DART_ASR_STREAM_STATUS_CONTEXT_FULL
              .value) {
        _drainAsrText(session, progress.segment_breaks);
        throw LlamaSpeechTranscriptTruncatedException(
          'Live speech recognition filled the model context.',
          limit: LlamaSpeechTranscriptLimit.contextSize,
          partialTranscript: session.confirmedText,
        );
      }
      _throwForAsrStatus(session, status, operation: 'stream step');

      final state = progress.state;
      if (progress.segment_breaks < session.lastSegmentBreaks) {
        throw LlamaSpeechException(
          'Native live speech recognition reported a decreasing segment count.',
        );
      }
      final textGrew = _drainAsrText(session, progress.segment_breaks);
      if (textGrew || progress.samples_consumed > session.lastSamplesConsumed) {
        if (progress.samples_consumed > session.lastSamplesConsumed) {
          session.lastSamplesConsumed = progress.samples_consumed;
        }
        anyProgress = true;
      }

      if (state ==
          llama_dart_asr_stream_state
              .LLAMA_DART_ASR_STREAM_STATE_NEEDS_AUDIO
              .value) {
        if (expectingFinish) {
          throw LlamaSpeechException(
            'Native live speech recognition requested audio after finish.',
          );
        }
        return anyProgress || progress.samples_consumed > lastConsumed;
      }

      if (state ==
          llama_dart_asr_stream_state
              .LLAMA_DART_ASR_STREAM_STATE_FINISHED
              .value) {
        if (!expectingFinish) {
          throw LlamaSpeechTranscriptTruncatedException(
            'Live speech recognition ended before input closed.',
            limit: LlamaSpeechTranscriptLimit.runtime,
            partialTranscript: session.confirmedText,
          );
        }
        return true;
      }

      if (state ==
          llama_dart_asr_stream_state
              .LLAMA_DART_ASR_STREAM_STATE_CANCELLED
              .value) {
        throw LlamaSpeechException('Live speech recognition was cancelled.');
      }

      if (state ==
          llama_dart_asr_stream_state
              .LLAMA_DART_ASR_STREAM_STATE_FAILED
              .value) {
        throw LlamaSpeechException(
          'Live speech recognition failed.',
          _readAsrStreamError(session.api, session.stream),
        );
      }

      if (state !=
          llama_dart_asr_stream_state
              .LLAMA_DART_ASR_STREAM_STATE_WORKING
              .value) {
        throw LlamaSpeechException(
          'Native live speech recognition reported unknown state $state.',
        );
      }

      final changed =
          progress.samples_buffered != lastBuffered ||
          progress.samples_consumed != lastConsumed ||
          progress.tokens_sampled != lastTokens ||
          progress.text_available != lastTextAvailable ||
          progress.segment_breaks != lastBreaks ||
          textGrew;
      if (changed) {
        anyProgress = true;
        idleWorkingSteps = 0;
        lastBuffered = progress.samples_buffered;
        lastConsumed = progress.samples_consumed;
        lastTokens = progress.tokens_sampled;
        lastTextAvailable = progress.text_available;
        lastBreaks = progress.segment_breaks;
      } else if (++idleWorkingSteps >= _asrStreamMaxIdleWorkingSteps) {
        throw LlamaSpeechException(
          'Native live speech recognition stopped making progress.',
        );
      }

      await Future<void>.delayed(Duration.zero);
    }
  }

  bool _drainAsrText(_AsrStreamSession session, int segmentBreaks) {
    if (segmentBreaks > session.lastSegmentBreaks) {
      session.lastSegmentBreaks = segmentBreaks;
      if (session.hasVisibleText) {
        session.pendingSegmentBreak = true;
      }
    }

    final bytesBuilder = BytesBuilder(copy: false);
    while (true) {
      session.sizeOut.value = 0;
      final status = _calls.asrStreamReadText(
        stream: session.stream,
        context: session.context,
        model: session.model,
        projector: session.projector,
        out: session.textBuffer,
        capacity: _asrStreamReadTextCapacity,
        outLen: session.sizeOut,
        readText: session.api.readText,
      );
      _throwForAsrStatus(session, status, operation: 'text read');
      final count = session.sizeOut.value;
      if (count < 0 || count > _asrStreamReadTextCapacity) {
        throw LlamaSpeechException(
          'Native live speech recognition reported invalid text byte count '
          '$count.',
        );
      }
      if (count == 0) {
        break;
      }
      bytesBuilder.add(
        Uint8List.fromList(session.textBuffer.cast<Uint8>().asTypedList(count)),
      );
    }

    if (bytesBuilder.isEmpty) {
      return false;
    }
    final piece = utf8.decode(bytesBuilder.takeBytes(), allowMalformed: true);
    if (piece.isEmpty) {
      return false;
    }

    final buffer = StringBuffer(session.confirmedText);
    if (session.pendingSegmentBreak) {
      if (piece.trim().isNotEmpty) {
        if (session.confirmedText.isNotEmpty &&
            !session.confirmedText.endsWith(' ') &&
            !piece.startsWith(' ')) {
          buffer.write(' ');
        }
        session.pendingSegmentBreak = false;
      } else if (session.confirmedText.endsWith(' ')) {
        session.pendingSegmentBreak = false;
      }
    }
    buffer.write(piece);
    session.confirmedText = buffer.toString();
    if (piece.trim().isNotEmpty) {
      session.hasVisibleText = true;
    }
    session.onText(session.confirmedText, session.acceptedSamples);
    return true;
  }

  void _throwForAsrStatus(
    _AsrStreamSession session,
    int status, {
    required String operation,
  }) {
    if (status ==
        llama_dart_asr_stream_status.LLAMA_DART_ASR_STREAM_STATUS_OK.value) {
      return;
    }
    if (status ==
        llama_dart_asr_stream_status
            .LLAMA_DART_ASR_STREAM_STATUS_CANCELLED
            .value) {
      throw LlamaSpeechException('Live speech recognition was cancelled.');
    }
    if (status ==
        llama_dart_asr_stream_status
            .LLAMA_DART_ASR_STREAM_STATUS_CONTEXT_FULL
            .value) {
      throw LlamaSpeechTranscriptTruncatedException(
        'Live speech recognition filled the model context.',
        limit: LlamaSpeechTranscriptLimit.contextSize,
        partialTranscript: session.confirmedText,
      );
    }
    final details = _readAsrStreamError(session.api, session.stream);
    if (status ==
        llama_dart_asr_stream_status
            .LLAMA_DART_ASR_STREAM_STATUS_UNSUPPORTED
            .value) {
      throw LlamaUnsupportedException(
        'Live speech recognition $operation is unsupported.',
      );
    }
    if (status ==
        llama_dart_asr_stream_status
            .LLAMA_DART_ASR_STREAM_STATUS_INVALID_STATE
            .value) {
      throw LlamaStateException(
        'Live speech recognition $operation is not valid in this state.',
        details,
      );
    }
    throw LlamaSpeechException(
      'Live speech recognition $operation failed.',
      details,
    );
  }

  String? _readAsrStreamError(
    _AsrStreamApi api,
    Pointer<llama_dart_asr_stream> stream,
  ) {
    if (stream == nullptr) {
      return null;
    }
    final ptr = api.lastError(stream);
    if (ptr == nullptr) {
      return null;
    }
    final raw = ptr.cast<Utf8>().toDartString();
    final sanitized = raw.replaceAll(RegExp(r'[\x00-\x1F\x7F]+'), ' ').trim();
    if (sanitized.isEmpty) {
      return null;
    }
    if (sanitized.length <= _asrStreamMaxDiagnosticChars) {
      return sanitized;
    }
    return '${sanitized.substring(0, _asrStreamMaxDiagnosticChars)}...';
  }

  void _closeAsrSession(_AsrStreamSession session) {
    if (session.closed) {
      return;
    }
    session.closed = true;
    if (identical(_activeAsrStreamSession, session)) {
      _activeAsrStreamSession = null;
    }
    try {
      if (session.stream != nullptr) {
        _calls.asrStreamFree(session.stream, session.api.free);
      }
    } finally {
      malloc.free(session.pcmBuffer);
      malloc.free(session.sizeOut);
      calloc.free(session.progress);
      malloc.free(session.textBuffer);
    }
  }
}
