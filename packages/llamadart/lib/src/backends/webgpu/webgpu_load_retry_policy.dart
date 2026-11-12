import 'dart:math' as math;

/// Floor of the restart that warns 'retrying with smaller fetch chunks': it
/// fires only while [WebGpuLoadEscalation.remoteFetchChunkBytes] exceeds this
/// value, and never sets that field below this value.
const int minRemoteFetchChunkBytes = 4 * 1024;

/// Cap on the restart that warns 'retrying with smaller fetch chunks': it
/// fires only while [WebGpuLoadEscalation.remoteFetchChunkRetryCount] is below
/// this value.
const int maxRemoteFetchChunkRestarts = 10;

/// Ceiling of the restart that warns 'retrying with forced fetch-backed
/// loading': it sets [WebGpuLoadEscalation.remoteFetchChunkBytes] to the
/// smaller of that field and this value.
const int fsWriteRetryChunkBytes = 128 * 1024;

/// Whether [loweredErrorText] carries 'array buffer allocation failed',
/// 'out of memory', 'memory access out of bounds', 'bad_alloc', or
/// 'aborted(native code called abort())'.
bool isMemoryPressureErrorText(String loweredErrorText) {
  return loweredErrorText.contains('array buffer allocation failed') ||
      loweredErrorText.contains('out of memory') ||
      loweredErrorText.contains('memory access out of bounds') ||
      loweredErrorText.contains('bad_alloc') ||
      loweredErrorText.contains('aborted(native code called abort())');
}

/// Whether [loweredErrorText] carries both 'cannot convert' and 'bigint'.
bool isBigIntInteropErrorText(String loweredErrorText) {
  return loweredErrorText.contains('cannot convert') &&
      loweredErrorText.contains('bigint');
}

/// Whether [loweredErrorText] carries 'thread constructor failed' or
/// 'error 138' not followed by another digit.
bool isThreadConstructorFailureText(String loweredErrorText) {
  return loweredErrorText.contains('thread constructor failed') ||
      loweredErrorText.contains(_error138);
}

final RegExp _error138 = RegExp(r'error 138(?!\d)');

/// Whether [runtimeNotes] carries 'model_response_nostream',
/// 'model_fs_write_bigint_error', 'model_fs_write_abort',
/// 'model_fs_write_arraybuffer_oom', or 'model_fs_write_failed'.
bool runtimeNotesIndicateModelFsWriteFailure(String runtimeNotes) {
  return runtimeNotes.contains('model_response_nostream') ||
      runtimeNotes.contains('model_fs_write_bigint_error') ||
      runtimeNotes.contains('model_fs_write_abort') ||
      runtimeNotes.contains('model_fs_write_arraybuffer_oom') ||
      runtimeNotes.contains('model_fs_write_failed');
}

/// What the load loop does with the attempt ladder after a failed attempt.
enum WebGpuRetryAction {
  /// Move to the next ladder rung.
  advance,

  /// Restart the ladder from its first rung.
  restart,

  /// Stop retrying and surface the failure.
  giveUp,
}

/// One failed bridge load attempt, reduced to the facts the policy reads.
class WebGpuLoadFailure {
  /// Creates a failure description for [classifyWebGpuLoadFailure].
  const WebGpuLoadFailure({
    required this.attemptIndex,
    required this.attemptCount,
    required this.errorText,
    required this.coreVariant,
    required this.runtimeNotes,
    required this.forceRemoteFetchRequested,
    required this.remoteFetchBackendOptedIn,
  });

  /// Zero-based ladder rung the failed attempt used.
  final int attemptIndex;

  /// Total number of ladder rungs.
  final int attemptCount;

  /// Lower-cased text of the thrown error; the classifier does not lower-case
  /// it.
  final String errorText;

  /// Bridge `llamadart.webgpu.core_variant` hint, or null when absent.
  final String? coreVariant;

  /// Bridge `llamadart.webgpu.runtime_notes` hint, empty when absent.
  final String runtimeNotes;

  /// Whether the failed attempt asked the bridge for the remote fetch backend.
  final bool forceRemoteFetchRequested;

  /// Whether the host page opted into fetch-backed loading.
  final bool remoteFetchBackendOptedIn;
}

/// Escalation state carried across attempts of one load.
class WebGpuLoadEscalation {
  /// Creates escalation state; every latch defaults to its unfired value.
  const WebGpuLoadEscalation({
    required this.remoteFetchChunkBytes,
    this.retriedWithWasm32 = false,
    this.retriedWithWasm64 = false,
    this.retriedWithoutRemoteFetchBackend = false,
    this.remoteFetchChunkRetryCount = 0,
    this.retriedAfterFsWriteFailureWithRemote = false,
    this.remoteFetchBackendKnownUnstable = false,
    this.wasm64InteropKnownBroken = false,
  });

  /// Chunk size passed to the bridge for the next attempt.
  final int remoteFetchChunkBytes;

  /// Whether the restart that warns 'wasm64 BigInt interop failure detected'
  /// has fired.
  final bool retriedWithWasm32;

  /// Whether the restart that warns 'wasm32 memory pressure detected' has
  /// fired.
  final bool retriedWithWasm64;

  /// Whether the restart that warns 'fetch-backed model loading aborted' and
  /// sets [WebGpuRetryDecision.forceRemoteFetchBackend] to false has fired.
  final bool retriedWithoutRemoteFetchBackend;

  /// How many restarts that warn 'retrying with smaller fetch chunks' have
  /// fired.
  final int remoteFetchChunkRetryCount;

  /// Whether the restart that warns 'retrying with forced fetch-backed
  /// loading' has fired.
  final bool retriedAfterFsWriteFailureWithRemote;

  /// Latched by [classifyWebGpuLoadFailure] when a failure's runtime notes
  /// carry 'model_fetch_backend_abort', which needs no
  /// 'model_fetch_backend_attempt' marker, or carry
  /// 'model_fetch_backend_attempt' together with either 'core_abort' in the
  /// notes or 'aborted(native code called abort())' in the error text.
  final bool remoteFetchBackendKnownUnstable;

  /// Whether the restart that warns 'wasm64 BigInt interop failure detected'
  /// has fired on a failure whose error text [isBigIntInteropErrorText]
  /// matches.
  final bool wasm64InteropKnownBroken;

  /// Returns a copy with the named fields replaced; null keeps the current one.
  WebGpuLoadEscalation copyWith({
    int? remoteFetchChunkBytes,
    bool? retriedWithWasm32,
    bool? retriedWithWasm64,
    bool? retriedWithoutRemoteFetchBackend,
    int? remoteFetchChunkRetryCount,
    bool? retriedAfterFsWriteFailureWithRemote,
    bool? remoteFetchBackendKnownUnstable,
    bool? wasm64InteropKnownBroken,
  }) {
    return WebGpuLoadEscalation(
      remoteFetchChunkBytes:
          remoteFetchChunkBytes ?? this.remoteFetchChunkBytes,
      retriedWithWasm32: retriedWithWasm32 ?? this.retriedWithWasm32,
      retriedWithWasm64: retriedWithWasm64 ?? this.retriedWithWasm64,
      retriedWithoutRemoteFetchBackend:
          retriedWithoutRemoteFetchBackend ??
          this.retriedWithoutRemoteFetchBackend,
      remoteFetchChunkRetryCount:
          remoteFetchChunkRetryCount ?? this.remoteFetchChunkRetryCount,
      retriedAfterFsWriteFailureWithRemote:
          retriedAfterFsWriteFailureWithRemote ??
          this.retriedAfterFsWriteFailureWithRemote,
      remoteFetchBackendKnownUnstable:
          remoteFetchBackendKnownUnstable ??
          this.remoteFetchBackendKnownUnstable,
      wasm64InteropKnownBroken:
          wasm64InteropKnownBroken ?? this.wasm64InteropKnownBroken,
    );
  }
}

/// What the load loop should do next, and the state it should carry forward.
class WebGpuRetryDecision {
  /// Creates a decision; a null override field leaves that override unchanged.
  const WebGpuRetryDecision({
    required this.action,
    required this.escalation,
    this.preferMemory64,
    this.forceRemoteFetchBackend,
    this.logMessages = const <String>[],
  });

  /// What the loop does with the ladder.
  final WebGpuRetryAction action;

  /// Escalation state for the next attempt.
  final WebGpuLoadEscalation escalation;

  /// New memory64 preference, or null to leave the current override unchanged.
  final bool? preferMemory64;

  /// New remote-fetch preference, or null to leave the override unchanged.
  final bool? forceRemoteFetchBackend;

  /// Warnings the loop emits, in order, before acting on [action].
  final List<String> logMessages;
}

/// Decides how the web model load ladder reacts to [failure].
///
/// [escalation] is the state carried from earlier attempts of the same load;
/// the returned decision carries the state for the next attempt.
WebGpuRetryDecision classifyWebGpuLoadFailure(
  WebGpuLoadFailure failure,
  WebGpuLoadEscalation escalation,
) {
  final errorText = failure.errorText;
  final coreVariant = failure.coreVariant;
  final runtimeNotes = failure.runtimeNotes;
  final remoteFetchBackendOptedIn = failure.remoteFetchBackendOptedIn;
  final forceRemoteFetchRequested = failure.forceRemoteFetchRequested;

  final fsWriteFailed = runtimeNotesIndicateModelFsWriteFailure(runtimeNotes);
  final bigIntInteropError = isBigIntInteropErrorText(errorText);
  final remoteFetchAttempted = runtimeNotes.contains(
    'model_fetch_backend_attempt',
  );
  final remoteFetchAborted =
      runtimeNotes.contains('model_fetch_backend_abort') ||
      (remoteFetchAttempted && runtimeNotes.contains('core_abort')) ||
      (remoteFetchAttempted &&
          errorText.contains('aborted(native code called abort())'));
  final threadConstructorFailure =
      isThreadConstructorFailureText(errorText) ||
      runtimeNotes.contains('thread_constructor_failed') ||
      runtimeNotes.contains('threads_capped_no_coi');
  final wasm32ModelStagingFailed = coreVariant == 'wasm32' && fsWriteFailed;
  final memoryPressureFailure =
      isMemoryPressureErrorText(errorText) || wasm32ModelStagingFailed;

  var state = escalation;
  bool? baseForceRemoteFetchBackend;
  if (remoteFetchAborted) {
    state = state.copyWith(remoteFetchBackendKnownUnstable: true);
    if (!forceRemoteFetchRequested) {
      baseForceRemoteFetchBackend = false;
    }
  }

  final shouldRetryWithoutRemoteFetchBackend =
      !state.retriedWithoutRemoteFetchBackend &&
      !forceRemoteFetchRequested &&
      remoteFetchAttempted &&
      remoteFetchAborted;
  final shouldRetryWithSmallerRemoteFetchChunks =
      state.remoteFetchChunkRetryCount < maxRemoteFetchChunkRestarts &&
      remoteFetchBackendOptedIn &&
      remoteFetchAttempted &&
      remoteFetchAborted &&
      forceRemoteFetchRequested &&
      !threadConstructorFailure &&
      state.remoteFetchChunkBytes > minRemoteFetchChunkBytes;
  final shouldRetryWithWasm32 =
      !state.retriedWithWasm32 &&
      coreVariant == 'wasm64' &&
      (bigIntInteropError ||
          runtimeNotes.contains('model_fetch_backend_skipped_small'));
  final shouldRetryWithWasm64 =
      !state.retriedWithWasm64 &&
      !state.wasm64InteropKnownBroken &&
      coreVariant == 'wasm32' &&
      memoryPressureFailure &&
      !runtimeNotes.contains('model_fetch_backend_skipped_small');
  final canRetry =
      failure.attemptIndex < failure.attemptCount - 1 &&
      memoryPressureFailure &&
      !(fsWriteFailed && coreVariant == 'wasm64');

  if (shouldRetryWithSmallerRemoteFetchChunks) {
    final retryCount = state.remoteFetchChunkRetryCount + 1;
    final chunkBytes = math.max(
      minRemoteFetchChunkBytes,
      state.remoteFetchChunkBytes ~/ 2,
    );
    return WebGpuRetryDecision(
      action: WebGpuRetryAction.restart,
      escalation: state.copyWith(
        remoteFetchChunkRetryCount: retryCount,
        remoteFetchChunkBytes: chunkBytes,
      ),
      forceRemoteFetchBackend: true,
      logMessages: <String>[
        'WebGpuLlamaBackend: fetch-backed model loading aborted; '
            'retrying with smaller fetch chunks '
            '(${chunkBytes ~/ 1024} KiB, '
            'attempt #$retryCount).',
      ],
    );
  }

  if (shouldRetryWithoutRemoteFetchBackend) {
    return WebGpuRetryDecision(
      action: WebGpuRetryAction.restart,
      escalation: state.copyWith(retriedWithoutRemoteFetchBackend: true),
      preferMemory64: coreVariant == 'wasm32' ? true : null,
      forceRemoteFetchBackend: false,
      logMessages: <String>[
        coreVariant == 'wasm32'
            ? 'WebGpuLlamaBackend: fetch-backed model loading aborted on '
                  'wasm32; retrying with wasm64 core and streamed '
                  'network loading.'
            : 'WebGpuLlamaBackend: fetch-backed model loading aborted; '
                  'retrying with streamed network loading.',
      ],
    );
  }

  if (shouldRetryWithWasm32) {
    return WebGpuRetryDecision(
      action: WebGpuRetryAction.restart,
      escalation: state.copyWith(
        retriedWithWasm32: true,
        wasm64InteropKnownBroken: bigIntInteropError ? true : null,
      ),
      preferMemory64: false,
      forceRemoteFetchBackend: false,
      logMessages: const <String>[
        'WebGpuLlamaBackend: wasm64 BigInt interop failure detected; '
            'retrying with wasm32 core.',
      ],
    );
  }

  if (shouldRetryWithWasm64) {
    final retryWithRemoteFetchBackend =
        remoteFetchBackendOptedIn &&
        !remoteFetchAttempted &&
        !state.remoteFetchBackendKnownUnstable;
    return WebGpuRetryDecision(
      action: WebGpuRetryAction.restart,
      escalation: state.copyWith(retriedWithWasm64: true),
      preferMemory64: true,
      forceRemoteFetchBackend: retryWithRemoteFetchBackend,
      logMessages: <String>[
        retryWithRemoteFetchBackend
            ? 'WebGpuLlamaBackend: wasm32 memory pressure detected; '
                  'retrying with wasm64 core and explicitly enabled '
                  'fetch-backed loading.'
            : remoteFetchAttempted
            ? 'WebGpuLlamaBackend: wasm32 memory pressure detected after '
                  'fetch-backed loading; retrying with wasm64 core and '
                  'streamed network loading.'
            : 'WebGpuLlamaBackend: wasm32 memory pressure detected; '
                  'retrying with wasm64 core and streamed network loading.',
      ],
    );
  }

  final logMessages = <String>[];
  if (fsWriteFailed && coreVariant == 'wasm64') {
    if (remoteFetchBackendOptedIn &&
        !state.retriedAfterFsWriteFailureWithRemote) {
      final chunkBytes = math.min(
        state.remoteFetchChunkBytes,
        fsWriteRetryChunkBytes,
      );
      return WebGpuRetryDecision(
        action: WebGpuRetryAction.restart,
        escalation: state.copyWith(
          retriedAfterFsWriteFailureWithRemote: true,
          remoteFetchChunkBytes: chunkBytes,
        ),
        forceRemoteFetchBackend: true,
        logMessages: <String>[
          'WebGpuLlamaBackend: wasm64 model staging failed; retrying '
              'with forced fetch-backed loading and '
              '${chunkBytes ~/ 1024} KiB chunks.',
        ],
      );
    }

    logMessages.add(
      remoteFetchBackendOptedIn
          ? 'WebGpuLlamaBackend: wasm64 model staging failed; skipping '
                'fallback ladder because additional nCtx/GPU/thread '
                'reductions are unlikely to recover FS write failures.'
          : 'WebGpuLlamaBackend: wasm64 model staging failed; '
                'fetch-backed recovery requires explicit opt-in, so no '
                'unsafe remote-fetch retry will be attempted.',
    );
  }

  return WebGpuRetryDecision(
    action: canRetry ? WebGpuRetryAction.advance : WebGpuRetryAction.giveUp,
    escalation: state,
    forceRemoteFetchBackend: baseForceRemoteFetchBackend,
    logMessages: logMessages,
  );
}
