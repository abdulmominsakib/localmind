import 'package:llamadart/src/backends/webgpu/webgpu_load_retry_policy.dart';
import 'package:test/test.dart';

const int _fourMiB = 4 * 1024 * 1024;

WebGpuLoadFailure _failure({
  int attemptIndex = 0,
  int attemptCount = 10,
  String errorText = 'bridge model load failed',
  String? coreVariant,
  String runtimeNotes = '',
  bool forceRemoteFetchRequested = false,
  bool remoteFetchBackendOptedIn = false,
}) {
  return WebGpuLoadFailure(
    attemptIndex: attemptIndex,
    attemptCount: attemptCount,
    errorText: errorText,
    coreVariant: coreVariant,
    runtimeNotes: runtimeNotes,
    forceRemoteFetchRequested: forceRemoteFetchRequested,
    remoteFetchBackendOptedIn: remoteFetchBackendOptedIn,
  );
}

WebGpuLoadEscalation _escalation({int remoteFetchChunkBytes = _fourMiB}) {
  return WebGpuLoadEscalation(remoteFetchChunkBytes: remoteFetchChunkBytes);
}

WebGpuLoadFailure _published(
  (String, String, String) output, {
  int attemptIndex = 0,
  bool forced = false,
  bool optedIn = false,
}) {
  final (coreVariant, runtimeNotes, message) = output;
  return _failure(
    attemptIndex: attemptIndex,
    errorText: message.toLowerCase(),
    coreVariant: coreVariant,
    runtimeNotes: runtimeNotes,
    forceRemoteFetchRequested: forced,
    remoteFetchBackendOptedIn: optedIn,
  );
}

List<WebGpuRetryDecision> _replay(
  List<WebGpuLoadFailure> failures, {
  int remoteFetchChunkBytes = _fourMiB,
}) {
  var state = _escalation(remoteFetchChunkBytes: remoteFetchChunkBytes);
  final decisions = <WebGpuRetryDecision>[];
  for (final failure in failures) {
    final decision = classifyWebGpuLoadFailure(failure, state);
    decisions.add(decision);
    state = decision.escalation;
  }
  return decisions;
}

const _skippedSmallTrapWasm32 = (
  'wasm32',
  'core_wasm32_active;core_pthreads:1;thread_pool_size:4;threads_batch:4;'
      'model_fetch_backend_skipped_small;model_network_stream;'
      'model_response_stream;model_load_ccall_failed',
  'memory access out of bounds',
);

const _skippedSmallTrapWasm64 = (
  'wasm64',
  'core_mem64_attempt;core_mem64_active;core_pthreads:1;thread_pool_size:4;'
      'threads_batch:4;model_fetch_backend_skipped_small;model_network_stream;'
      'model_response_stream;model_load_ccall_failed',
  'memory access out of bounds',
);

const _streamedTrapWasm32 = (
  'wasm32',
  'core_wasm32_active;core_pthreads:1;thread_pool_size:4;threads_batch:4;'
      'model_network_stream;model_response_stream;model_load_ccall_failed',
  'memory access out of bounds',
);

const _streamedStagingOomWasm32 = (
  'wasm32',
  'core_wasm32_active;core_pthreads:1;thread_pool_size:4;threads_batch:4;'
      'model_network_stream;model_response_stream;model_fs_write_loaded:0;'
      'model_fs_write_arraybuffer_oom',
  'Array buffer allocation failed',
);

const _noStreamMem64Unavailable = (
  'wasm32',
  'core_mem64_attempt;core_mem64_unavailable;core_wasm32_active;'
      'core_pthreads:1;thread_pool_size:4;threads_batch:4;'
      'model_network_no_stream;model_response_nostream',
  'Model response did not expose a readable stream (64 bytes).',
);

void main() {
  group('failure text predicates', () {
    test('memory pressure covers every recognised phrase', () {
      for (final phrase in <String>[
        'array buffer allocation failed',
        'out of memory',
        'memory access out of bounds',
        'bad_alloc',
        'aborted(native code called abort())',
      ]) {
        expect(
          isMemoryPressureErrorText('prefix $phrase suffix'),
          isTrue,
          reason: phrase,
        );
      }
      expect(isMemoryPressureErrorText('bridge model load failed'), isFalse);
    });

    test('bigint interop needs both halves of the phrase', () {
      expect(
        isBigIntInteropErrorText('cannot convert a bigint value to a number'),
        isTrue,
      );
      expect(isBigIntInteropErrorText('cannot convert a value'), isFalse);
      expect(isBigIntInteropErrorText('bigint overflow'), isFalse);
    });

    test('thread constructor failure covers both markers', () {
      expect(isThreadConstructorFailureText('thread constructor failed'), true);
      expect(isThreadConstructorFailureText('pthread error 138 raised'), true);
      expect(isThreadConstructorFailureText('error 139'), isFalse);
      expect(isThreadConstructorFailureText('error 138.'), isTrue);
      expect(isThreadConstructorFailureText('error 1380'), isFalse);
    });

    test('fs write notes cover every recognised marker', () {
      for (final note in <String>[
        'model_response_nostream',
        'model_fs_write_bigint_error',
        'model_fs_write_abort',
        'model_fs_write_arraybuffer_oom',
        'model_fs_write_failed',
      ]) {
        expect(
          runtimeNotesIndicateModelFsWriteFailure('a;$note;b'),
          isTrue,
          reason: note,
        );
      }
      expect(
        runtimeNotesIndicateModelFsWriteFailure('model_fetch_backend_attempt'),
        isFalse,
      );
    });
  });

  group('smaller remote fetch chunk restart', () {
    WebGpuLoadFailure abortedForcedFetch({int attemptIndex = 0}) {
      return _failure(
        attemptIndex: attemptIndex,
        runtimeNotes: 'model_fetch_backend_attempt;model_fetch_backend_abort',
        coreVariant: 'wasm32',
        forceRemoteFetchRequested: true,
        remoteFetchBackendOptedIn: true,
      );
    }

    test('halves the chunk size and reports the new size', () {
      final decision = classifyWebGpuLoadFailure(
        abortedForcedFetch(),
        _escalation(remoteFetchChunkBytes: 16 * 1024 * 1024),
      );

      expect(decision.action, WebGpuRetryAction.restart);
      expect(decision.escalation.remoteFetchChunkBytes, 8 * 1024 * 1024);
      expect(decision.escalation.remoteFetchChunkRetryCount, 1);
      expect(decision.forceRemoteFetchBackend, isTrue);
      expect(decision.preferMemory64, isNull);
      expect(decision.logMessages, <String>[
        'WebGpuLlamaBackend: fetch-backed model loading aborted; '
            'retrying with smaller fetch chunks '
            '(8192 KiB, attempt #1).',
      ]);
    });

    test('halves ten times from 16 MiB and then gives up', () {
      var state = _escalation(remoteFetchChunkBytes: 16 * 1024 * 1024);
      final sizes = <int>[state.remoteFetchChunkBytes];
      final actions = <WebGpuRetryAction>[];

      for (var i = 0; i < 12; i += 1) {
        final decision = classifyWebGpuLoadFailure(abortedForcedFetch(), state);
        actions.add(decision.action);
        state = decision.escalation;
        if (decision.action != WebGpuRetryAction.restart) {
          break;
        }
        sizes.add(state.remoteFetchChunkBytes);
      }

      expect(sizes, <int>[
        16 * 1024 * 1024,
        8 * 1024 * 1024,
        4 * 1024 * 1024,
        2 * 1024 * 1024,
        1024 * 1024,
        512 * 1024,
        256 * 1024,
        128 * 1024,
        64 * 1024,
        32 * 1024,
        16 * 1024,
      ]);
      expect(
        actions.where((a) => a == WebGpuRetryAction.restart),
        hasLength(10),
      );
      expect(actions.last, WebGpuRetryAction.giveUp);
      expect(state.remoteFetchChunkRetryCount, maxRemoteFetchChunkRestarts);
    });

    test('stops halving at the four KiB floor', () {
      var state = _escalation(remoteFetchChunkBytes: 20 * 1024);
      final sizes = <int>[state.remoteFetchChunkBytes];
      WebGpuRetryDecision decision;

      do {
        decision = classifyWebGpuLoadFailure(abortedForcedFetch(), state);
        state = decision.escalation;
        if (decision.action == WebGpuRetryAction.restart) {
          sizes.add(state.remoteFetchChunkBytes);
        }
      } while (decision.action == WebGpuRetryAction.restart);

      expect(sizes, <int>[
        20 * 1024,
        10 * 1024,
        5 * 1024,
        minRemoteFetchChunkBytes,
      ]);
      expect(decision.action, WebGpuRetryAction.giveUp);
      expect(state.remoteFetchChunkRetryCount, 3);
    });

    test('does not fire when thread creation is the failure', () {
      final decision = classifyWebGpuLoadFailure(
        _failure(
          errorText: 'thread constructor failed',
          runtimeNotes: 'model_fetch_backend_attempt;model_fetch_backend_abort',
          coreVariant: 'wasm32',
          forceRemoteFetchRequested: true,
          remoteFetchBackendOptedIn: true,
        ),
        _escalation(),
      );

      expect(decision.action, WebGpuRetryAction.giveUp);
      expect(decision.escalation.remoteFetchChunkBytes, _fourMiB);
    });

    test('does not fire without the remote fetch opt-in', () {
      final decision = classifyWebGpuLoadFailure(
        _failure(
          runtimeNotes: 'model_fetch_backend_attempt;model_fetch_backend_abort',
          coreVariant: 'wasm32',
          forceRemoteFetchRequested: true,
        ),
        _escalation(),
      );

      expect(decision.escalation.remoteFetchChunkRetryCount, 0);
    });

    test('halves a chunk one byte above the floor down to the floor', () {
      final decision = classifyWebGpuLoadFailure(
        abortedForcedFetch(),
        _escalation(remoteFetchChunkBytes: minRemoteFetchChunkBytes + 1),
      );

      expect(decision.action, WebGpuRetryAction.restart);
      expect(
        decision.escalation.remoteFetchChunkBytes,
        minRemoteFetchChunkBytes,
      );
    });

    test('does not fire when the notes report a thread failure', () {
      for (final note in <String>[
        'thread_constructor_failed',
        'threads_capped_no_coi',
      ]) {
        final decision = classifyWebGpuLoadFailure(
          _failure(
            errorText: 'aborted(). build with -sassertions for more info.',
            runtimeNotes:
                'core_wasm32_active;core_pthreads:1;thread_pool_size:4;'
                '$note;threads_batch:1;model_fetch_backend_attempt;'
                'model_fetch_chunk:4194304;core_abort',
            coreVariant: 'wasm32',
            forceRemoteFetchRequested: true,
            remoteFetchBackendOptedIn: true,
          ),
          _escalation(),
        );

        expect(decision.action, WebGpuRetryAction.giveUp, reason: note);
      }
    });

    test('needs both the attempt and the abort note', () {
      for (final notes in <String>[
        'model_fetch_backend_attempt',
        'model_fetch_backend_abort',
      ]) {
        final decision = classifyWebGpuLoadFailure(
          _failure(
            runtimeNotes: notes,
            coreVariant: 'wasm32',
            forceRemoteFetchRequested: true,
            remoteFetchBackendOptedIn: true,
          ),
          _escalation(),
        );

        expect(decision.action, WebGpuRetryAction.giveUp, reason: notes);
      }
    });
  });

  group('streamed loading restart', () {
    test('drops the fetch backend and prefers wasm64 on a wasm32 abort', () {
      final decision = classifyWebGpuLoadFailure(
        _failure(
          coreVariant: 'wasm32',
          runtimeNotes: 'model_fetch_backend_attempt;model_fetch_backend_abort',
        ),
        _escalation(),
      );

      expect(decision.action, WebGpuRetryAction.restart);
      expect(decision.forceRemoteFetchBackend, isFalse);
      expect(decision.preferMemory64, isTrue);
      expect(decision.escalation.retriedWithoutRemoteFetchBackend, isTrue);
      expect(decision.escalation.remoteFetchBackendKnownUnstable, isTrue);
      expect(decision.logMessages, <String>[
        'WebGpuLlamaBackend: fetch-backed model loading aborted on '
            'wasm32; retrying with wasm64 core and streamed '
            'network loading.',
      ]);
    });

    test('leaves the memory64 override alone on a non-wasm32 core', () {
      final decision = classifyWebGpuLoadFailure(
        _failure(
          coreVariant: 'wasm64',
          runtimeNotes: 'model_fetch_backend_attempt;model_fetch_backend_abort',
        ),
        _escalation(),
      );

      expect(decision.action, WebGpuRetryAction.restart);
      expect(decision.preferMemory64, isNull);
      expect(decision.logMessages, <String>[
        'WebGpuLlamaBackend: fetch-backed model loading aborted; '
            'retrying with streamed network loading.',
      ]);
    });

    test('fires at most once', () {
      final failure = _failure(
        coreVariant: 'wasm32',
        runtimeNotes: 'model_fetch_backend_attempt;model_fetch_backend_abort',
      );
      final first = classifyWebGpuLoadFailure(failure, _escalation());
      final second = classifyWebGpuLoadFailure(failure, first.escalation);

      expect(first.action, WebGpuRetryAction.restart);
      expect(second.action, WebGpuRetryAction.giveUp);
    });
  });

  group('remote fetch abort detection', () {
    test('a core abort note during a fetch attempt counts as an abort', () {
      final decision = classifyWebGpuLoadFailure(
        _failure(
          coreVariant: 'wasm32',
          errorText: 'out of memory',
          runtimeNotes: 'model_fetch_backend_attempt;core_abort',
          remoteFetchBackendOptedIn: true,
        ),
        _escalation(),
      );

      expect(decision.action, WebGpuRetryAction.restart);
      expect(decision.escalation.remoteFetchBackendKnownUnstable, isTrue);
      expect(decision.escalation.retriedWithoutRemoteFetchBackend, isTrue);
      expect(decision.forceRemoteFetchBackend, isFalse);
      expect(decision.logMessages, <String>[
        'WebGpuLlamaBackend: fetch-backed model loading aborted on '
            'wasm32; retrying with wasm64 core and streamed '
            'network loading.',
      ]);
    });

    test('a native abort error during a fetch attempt counts as an abort', () {
      final decision = classifyWebGpuLoadFailure(
        _failure(
          coreVariant: 'wasm32',
          errorText:
              'error: aborted(native code called abort()) | '
              'aborted(native code called abort())',
          runtimeNotes: 'model_fetch_backend_attempt',
          remoteFetchBackendOptedIn: true,
        ),
        _escalation(),
      );

      expect(decision.action, WebGpuRetryAction.restart);
      expect(decision.escalation.remoteFetchBackendKnownUnstable, isTrue);
      expect(decision.escalation.retriedWithoutRemoteFetchBackend, isTrue);
      expect(decision.forceRemoteFetchBackend, isFalse);
      expect(decision.logMessages, <String>[
        'WebGpuLlamaBackend: fetch-backed model loading aborted on '
            'wasm32; retrying with wasm64 core and streamed '
            'network loading.',
      ]);
    });

    test('neither abort marker counts without a fetch attempt', () {
      for (final failure in <WebGpuLoadFailure>[
        _failure(
          coreVariant: 'wasm32',
          errorText: 'out of memory',
          runtimeNotes: 'core_abort',
          remoteFetchBackendOptedIn: true,
        ),
        _failure(
          coreVariant: 'wasm32',
          errorText: 'aborted(native code called abort())',
          remoteFetchBackendOptedIn: true,
        ),
      ]) {
        final decision = classifyWebGpuLoadFailure(failure, _escalation());

        expect(decision.escalation.remoteFetchBackendKnownUnstable, isFalse);
        expect(decision.forceRemoteFetchBackend, isTrue);
      }
    });
  });

  group('wasm32 restart after a wasm64 interop failure', () {
    test('latches the broken interop and clears both overrides', () {
      final decision = classifyWebGpuLoadFailure(
        _failure(
          coreVariant: 'wasm64',
          errorText: 'cannot convert a bigint value to a number',
        ),
        _escalation(),
      );

      expect(decision.action, WebGpuRetryAction.restart);
      expect(decision.preferMemory64, isFalse);
      expect(decision.forceRemoteFetchBackend, isFalse);
      expect(decision.escalation.retriedWithWasm32, isTrue);
      expect(decision.escalation.wasm64InteropKnownBroken, isTrue);
      expect(decision.logMessages, <String>[
        'WebGpuLlamaBackend: wasm64 BigInt interop failure detected; '
            'retrying with wasm32 core.',
      ]);
    });

    test('also fires on a skipped small fetch without latching interop', () {
      final decision = classifyWebGpuLoadFailure(
        _failure(
          coreVariant: 'wasm64',
          runtimeNotes: 'model_fetch_backend_skipped_small',
        ),
        _escalation(),
      );

      expect(decision.action, WebGpuRetryAction.restart);
      expect(decision.escalation.retriedWithWasm32, isTrue);
      expect(decision.escalation.wasm64InteropKnownBroken, isFalse);
    });

    test('fires at most once', () {
      final failure = _failure(
        coreVariant: 'wasm64',
        errorText: 'cannot convert a bigint value to a number',
      );
      final first = classifyWebGpuLoadFailure(failure, _escalation());
      final second = classifyWebGpuLoadFailure(failure, first.escalation);

      expect(first.action, WebGpuRetryAction.restart);
      expect(second.action, WebGpuRetryAction.giveUp);
    });

    test('a latched broken interop blocks the later wasm64 restart', () {
      final broken = classifyWebGpuLoadFailure(
        _failure(
          coreVariant: 'wasm64',
          errorText: 'cannot convert a bigint value to a number',
        ),
        _escalation(),
      ).escalation;

      final decision = classifyWebGpuLoadFailure(
        _failure(
          coreVariant: 'wasm32',
          errorText: 'out of memory',
          attemptIndex: 9,
        ),
        broken,
      );

      expect(decision.action, WebGpuRetryAction.giveUp);
      expect(decision.preferMemory64, isNull);
    });
  });

  group('wasm64 restart under wasm32 memory pressure', () {
    test('enables the fetch backend when it is opted in and untried', () {
      final decision = classifyWebGpuLoadFailure(
        _failure(
          coreVariant: 'wasm32',
          errorText: 'array buffer allocation failed',
          remoteFetchBackendOptedIn: true,
        ),
        _escalation(),
      );

      expect(decision.action, WebGpuRetryAction.restart);
      expect(decision.preferMemory64, isTrue);
      expect(decision.forceRemoteFetchBackend, isTrue);
      expect(decision.escalation.retriedWithWasm64, isTrue);
      expect(decision.logMessages, <String>[
        'WebGpuLlamaBackend: wasm32 memory pressure detected; '
            'retrying with wasm64 core and explicitly enabled '
            'fetch-backed loading.',
      ]);
    });

    test('reports the streamed retry after a fetch-backed attempt', () {
      final decision = classifyWebGpuLoadFailure(
        _failure(
          coreVariant: 'wasm32',
          errorText: 'out of memory',
          runtimeNotes: 'model_fetch_backend_attempt',
          remoteFetchBackendOptedIn: true,
        ),
        _escalation(),
      );

      expect(decision.forceRemoteFetchBackend, isFalse);
      expect(decision.logMessages, <String>[
        'WebGpuLlamaBackend: wasm32 memory pressure detected after '
            'fetch-backed loading; retrying with wasm64 core and '
            'streamed network loading.',
      ]);
    });

    test('reports the plain streamed retry without the opt-in', () {
      final decision = classifyWebGpuLoadFailure(
        _failure(coreVariant: 'wasm32', errorText: 'out of memory'),
        _escalation(),
      );

      expect(decision.forceRemoteFetchBackend, isFalse);
      expect(decision.logMessages, <String>[
        'WebGpuLlamaBackend: wasm32 memory pressure detected; '
            'retrying with wasm64 core and streamed network loading.',
      ]);
    });

    test(
      'a bare abort note in the same failure blocks re-enabling the backend',
      () {
        final decision = classifyWebGpuLoadFailure(
          _failure(
            coreVariant: 'wasm32',
            errorText: 'out of memory',
            runtimeNotes: 'model_fetch_backend_abort',
            remoteFetchBackendOptedIn: true,
          ),
          _escalation(),
        );

        expect(decision.action, WebGpuRetryAction.restart);
        expect(decision.escalation.remoteFetchBackendKnownUnstable, isTrue);
        expect(decision.forceRemoteFetchBackend, isFalse);
        expect(decision.logMessages, <String>[
          'WebGpuLlamaBackend: wasm32 memory pressure detected; '
              'retrying with wasm64 core and streamed network loading.',
        ]);
      },
    );

    test('an earlier abort also blocks re-enabling the backend', () {
      final decision = classifyWebGpuLoadFailure(
        _failure(
          coreVariant: 'wasm32',
          errorText: 'out of memory',
          remoteFetchBackendOptedIn: true,
        ),
        _escalation().copyWith(remoteFetchBackendKnownUnstable: true),
      );

      expect(decision.forceRemoteFetchBackend, isFalse);
    });

    test('wasm32 staging failure counts as memory pressure', () {
      final decision = classifyWebGpuLoadFailure(
        _failure(
          coreVariant: 'wasm32',
          runtimeNotes: 'model_fs_write_failed',
          remoteFetchBackendOptedIn: true,
        ),
        _escalation(),
      );

      expect(decision.action, WebGpuRetryAction.restart);
      expect(decision.preferMemory64, isTrue);
    });

    test('a wasm32 staging failure advances once the restart is spent', () {
      final decision = classifyWebGpuLoadFailure(
        _failure(
          coreVariant: 'wasm32',
          runtimeNotes: 'model_fs_write_failed',
          remoteFetchBackendOptedIn: true,
        ),
        _escalation().copyWith(retriedWithWasm64: true),
      );

      expect(decision.action, WebGpuRetryAction.advance);
      expect(decision.forceRemoteFetchBackend, isNull);
      expect(decision.logMessages, isEmpty);
    });

    test(
      'a staging failure without the wasm32 core is not memory pressure',
      () {
        final decision = classifyWebGpuLoadFailure(
          _failure(runtimeNotes: 'model_fs_write_failed'),
          _escalation(),
        );

        expect(decision.action, WebGpuRetryAction.giveUp);
      },
    );

    test('a skipped small fetch suppresses the restart', () {
      final decision = classifyWebGpuLoadFailure(
        _published(_skippedSmallTrapWasm32, optedIn: true),
        _escalation(),
      );

      expect(decision.action, WebGpuRetryAction.advance);
      expect(decision.escalation.retriedWithWasm64, isFalse);
    });

    test('fires at most once', () {
      final failure = _failure(
        coreVariant: 'wasm32',
        errorText: 'out of memory',
        remoteFetchBackendOptedIn: true,
      );
      final first = classifyWebGpuLoadFailure(failure, _escalation());
      final second = classifyWebGpuLoadFailure(failure, first.escalation);

      expect(first.action, WebGpuRetryAction.restart);
      expect(second.action, WebGpuRetryAction.advance);
    });
  });

  group('wasm64 staging failure', () {
    WebGpuLoadFailure stagingFailure({bool optedIn = true}) {
      return _failure(
        coreVariant: 'wasm64',
        runtimeNotes: 'model_fs_write_failed',
        remoteFetchBackendOptedIn: optedIn,
      );
    }

    test('clamps the chunk size to 128 KiB on the forced retry', () {
      final decision = classifyWebGpuLoadFailure(
        stagingFailure(),
        _escalation(),
      );

      expect(decision.action, WebGpuRetryAction.restart);
      expect(decision.escalation.remoteFetchChunkBytes, fsWriteRetryChunkBytes);
      expect(decision.forceRemoteFetchBackend, isTrue);
      expect(decision.escalation.retriedAfterFsWriteFailureWithRemote, isTrue);
      expect(decision.logMessages, <String>[
        'WebGpuLlamaBackend: wasm64 model staging failed; retrying '
            'with forced fetch-backed loading and '
            '128 KiB chunks.',
      ]);
    });

    test('keeps an already smaller chunk size', () {
      final decision = classifyWebGpuLoadFailure(
        stagingFailure(),
        _escalation(remoteFetchChunkBytes: 64 * 1024),
      );

      expect(decision.escalation.remoteFetchChunkBytes, 64 * 1024);
      expect(decision.logMessages.single, contains('64 KiB chunks'));
    });

    test('rounds a chunk size that is not whole KiB down in the warning', () {
      final decision = classifyWebGpuLoadFailure(
        _failure(
          coreVariant: 'wasm64',
          errorText: 'array buffer allocation failed',
          runtimeNotes:
              'core_mem64_attempt;core_mem64_active;core_pthreads:1;'
              'threads_capped_pool:4;thread_pool_size:4;threads_batch:4;'
              'model_fetch_backend_attempt;model_fetch_chunk:16384;'
              'model_fetch_backend_failed;model_network_stream;'
              'model_response_stream;model_fs_write_loaded:0;'
              'model_fs_write_arraybuffer_oom',
          remoteFetchBackendOptedIn: true,
        ),
        _escalation(remoteFetchChunkBytes: 5 * 1024 - 1),
      );

      expect(decision.escalation.remoteFetchChunkBytes, 5 * 1024 - 1);
      expect(decision.logMessages.single, contains(' 4 KiB chunks'));
    });

    test('gives up with the skip warning once the retry is spent', () {
      final first = classifyWebGpuLoadFailure(stagingFailure(), _escalation());
      final second = classifyWebGpuLoadFailure(
        stagingFailure(),
        first.escalation,
      );

      expect(second.action, WebGpuRetryAction.giveUp);
      expect(second.logMessages, <String>[
        'WebGpuLlamaBackend: wasm64 model staging failed; skipping '
            'fallback ladder because additional nCtx/GPU/thread '
            'reductions are unlikely to recover FS write failures.',
      ]);
    });

    test('gives up immediately without the remote fetch opt-in', () {
      final decision = classifyWebGpuLoadFailure(
        stagingFailure(optedIn: false),
        _escalation(),
      );

      expect(decision.action, WebGpuRetryAction.giveUp);
      expect(decision.logMessages, <String>[
        'WebGpuLlamaBackend: wasm64 model staging failed; '
            'fetch-backed recovery requires explicit opt-in, so no '
            'unsafe remote-fetch retry will be attempted.',
      ]);
    });

    test('never advances the ladder even under memory pressure', () {
      final decision = classifyWebGpuLoadFailure(
        _failure(
          coreVariant: 'wasm64',
          errorText: 'out of memory',
          runtimeNotes: 'model_fs_write_failed',
        ),
        _escalation(),
      );

      expect(decision.action, WebGpuRetryAction.giveUp);
    });
  });

  group('ladder advance and give up', () {
    test('advances while memory pressure and rungs remain', () {
      final decision = classifyWebGpuLoadFailure(
        _failure(
          attemptIndex: 0,
          attemptCount: 10,
          coreVariant: 'wasm64',
          errorText: 'out of memory',
        ),
        _escalation(),
      );

      expect(decision.action, WebGpuRetryAction.advance);
      expect(decision.logMessages, isEmpty);
      expect(decision.preferMemory64, isNull);
      expect(decision.forceRemoteFetchBackend, isNull);
    });

    test('gives up on the last rung', () {
      final decision = classifyWebGpuLoadFailure(
        _failure(
          attemptIndex: 9,
          attemptCount: 10,
          coreVariant: 'wasm64',
          errorText: 'out of memory',
        ),
        _escalation(),
      );

      expect(decision.action, WebGpuRetryAction.giveUp);
    });

    test('gives up when the failure is not memory pressure', () {
      final decision = classifyWebGpuLoadFailure(
        _failure(attemptIndex: 0, attemptCount: 10, coreVariant: 'wasm64'),
        _escalation(),
      );

      expect(decision.action, WebGpuRetryAction.giveUp);
    });

    test('carries the abort override through an advance', () {
      final decision = classifyWebGpuLoadFailure(
        _failure(
          attemptIndex: 0,
          attemptCount: 10,
          coreVariant: 'wasm64',
          errorText: 'out of memory',
          runtimeNotes: 'model_fetch_backend_attempt;model_fetch_backend_abort',
        ),
        _escalation().copyWith(retriedWithoutRemoteFetchBackend: true),
      );

      expect(decision.action, WebGpuRetryAction.advance);
      expect(decision.forceRemoteFetchBackend, isFalse);
      expect(decision.escalation.remoteFetchBackendKnownUnstable, isTrue);
    });

    test('leaves the override alone when the abort was self-inflicted', () {
      final decision = classifyWebGpuLoadFailure(
        _failure(
          attemptIndex: 9,
          attemptCount: 10,
          coreVariant: 'wasm32',
          runtimeNotes: 'model_fetch_backend_attempt;model_fetch_backend_abort',
          forceRemoteFetchRequested: true,
          remoteFetchBackendOptedIn: true,
        ),
        _escalation(remoteFetchChunkBytes: minRemoteFetchChunkBytes),
      );

      expect(decision.action, WebGpuRetryAction.giveUp);
      expect(decision.forceRemoteFetchBackend, isNull);
      expect(decision.escalation.remoteFetchBackendKnownUnstable, isTrue);
    });
  });

  group('restart precedence on published bridge failures', () {
    test('a forced fetch that traps after a core abort halves the chunk', () {
      final decision = classifyWebGpuLoadFailure(
        _failure(
          coreVariant: 'wasm32',
          errorText: 'memory access out of bounds',
          runtimeNotes:
              'core_wasm32_active;core_pthreads:1;threads_capped_pool:4;'
              'thread_pool_size:4;threads_batch:4;model_fetch_backend_attempt;'
              'model_fetch_chunk:4194304;core_abort',
          forceRemoteFetchRequested: true,
          remoteFetchBackendOptedIn: true,
        ),
        _escalation(),
      );

      expect(decision.action, WebGpuRetryAction.restart);
      expect(decision.escalation.remoteFetchChunkBytes, 2 * 1024 * 1024);
      expect(decision.escalation.retriedWithWasm64, isFalse);
      expect(decision.escalation.remoteFetchBackendKnownUnstable, isTrue);
      expect(decision.forceRemoteFetchBackend, isTrue);
      expect(decision.preferMemory64, isNull);
      expect(decision.logMessages, <String>[
        'WebGpuLlamaBackend: fetch-backed model loading aborted; '
            'retrying with smaller fetch chunks '
            '(2048 KiB, attempt #1).',
      ]);
    });

    test(
      'a forced fetch that aborts before a BigInt failure halves the chunk',
      () {
        final decision = classifyWebGpuLoadFailure(
          _failure(
            coreVariant: 'wasm64',
            errorText: 'cannot convert a bigint value to a number',
            runtimeNotes:
                'core_mem64_attempt;core_mem64_active;core_pthreads:1;'
                'threads_capped_pool:4;thread_pool_size:4;threads_batch:4;'
                'model_fetch_backend_attempt;model_fetch_chunk:4194304;'
                'core_abort;model_fetch_backend_failed;model_network_stream;'
                'model_response_stream;model_fs_write_loaded:0;'
                'model_fs_write_bigint_error',
            forceRemoteFetchRequested: true,
            remoteFetchBackendOptedIn: true,
          ),
          _escalation(),
        );

        expect(decision.action, WebGpuRetryAction.restart);
        expect(decision.escalation.remoteFetchChunkBytes, 2 * 1024 * 1024);
        expect(decision.escalation.retriedWithWasm32, isFalse);
        expect(decision.escalation.wasm64InteropKnownBroken, isFalse);
        expect(decision.forceRemoteFetchBackend, isTrue);
        expect(decision.preferMemory64, isNull);
      },
    );

    test('an aborted automatic fetch prefers streamed loading to wasm32', () {
      final decision = classifyWebGpuLoadFailure(
        _failure(
          coreVariant: 'wasm64',
          errorText: 'cannot convert a bigint value to a number',
          runtimeNotes:
              'core_mem64_attempt;core_mem64_active;core_pthreads:1;'
              'threads_capped_pool:4;thread_pool_size:4;threads_batch:4;'
              'model_fetch_backend_attempt;model_fetch_chunk:4194304;'
              'core_abort;model_fetch_backend_failed;model_network_stream;'
              'model_response_stream;model_fs_write_loaded:0;'
              'model_fs_write_bigint_error',
          remoteFetchBackendOptedIn: true,
        ),
        _escalation(),
      );

      expect(decision.action, WebGpuRetryAction.restart);
      expect(decision.escalation.retriedWithoutRemoteFetchBackend, isTrue);
      expect(decision.escalation.retriedWithWasm32, isFalse);
      expect(decision.forceRemoteFetchBackend, isFalse);
      expect(decision.preferMemory64, isNull);
      expect(decision.logMessages, <String>[
        'WebGpuLlamaBackend: fetch-backed model loading aborted; '
            'retrying with streamed network loading.',
      ]);
    });

    test('a skipped small fetch prefers wasm32 to the forced fetch retry', () {
      final decision = classifyWebGpuLoadFailure(
        _failure(
          coreVariant: 'wasm64',
          errorText: 'array buffer allocation failed',
          runtimeNotes:
              'core_mem64_attempt;core_mem64_active;core_pthreads:1;'
              'threads_capped_pool:4;thread_pool_size:4;threads_batch:4;'
              'model_fetch_backend_skipped_small;model_network_stream;'
              'model_response_stream;model_fs_write_loaded:0;'
              'model_fs_write_arraybuffer_oom',
          remoteFetchBackendOptedIn: true,
        ),
        _escalation(),
      );

      expect(decision.action, WebGpuRetryAction.restart);
      expect(decision.escalation.retriedWithWasm32, isTrue);
      expect(decision.escalation.retriedAfterFsWriteFailureWithRemote, isFalse);
      expect(decision.escalation.remoteFetchChunkBytes, _fourMiB);
      expect(decision.preferMemory64, isFalse);
      expect(decision.forceRemoteFetchBackend, isFalse);
      expect(decision.logMessages, <String>[
        'WebGpuLlamaBackend: wasm64 BigInt interop failure detected; '
            'retrying with wasm32 core.',
      ]);
    });
  });

  group('escalation state', () {
    List<Object> fieldsOf(WebGpuLoadEscalation state) => <Object>[
      state.remoteFetchChunkBytes,
      state.retriedWithWasm32,
      state.retriedWithWasm64,
      state.retriedWithoutRemoteFetchBackend,
      state.remoteFetchChunkRetryCount,
      state.retriedAfterFsWriteFailureWithRemote,
      state.remoteFetchBackendKnownUnstable,
      state.wasm64InteropKnownBroken,
    ];

    test('copyWith keeps every field it is not given', () {
      const fired = WebGpuLoadEscalation(
        remoteFetchChunkBytes: 5120,
        retriedWithWasm32: true,
        retriedWithWasm64: true,
        retriedWithoutRemoteFetchBackend: true,
        remoteFetchChunkRetryCount: 3,
        retriedAfterFsWriteFailureWithRemote: true,
        remoteFetchBackendKnownUnstable: true,
        wasm64InteropKnownBroken: true,
      );

      expect(fieldsOf(fired.copyWith()), fieldsOf(fired));
    });
  });

  group('published bridge failures', () {
    const nativeAbort = 'Aborted(). Build with -sASSERTIONS for more info.';

    test('a release-build native abort is not memory pressure', () {
      final decision = classifyWebGpuLoadFailure(
        _published((
          'wasm32',
          'core_wasm32_active;core_pthreads:1;thread_pool_size:4;'
              'threads_batch:4;model_network_stream;model_response_stream;'
              'core_abort;model_load_ccall_abort',
          nativeAbort,
        )),
        _escalation(),
      );

      expect(isMemoryPressureErrorText(nativeAbort.toLowerCase()), isFalse);
      expect(decision.action, WebGpuRetryAction.giveUp);
      expect(decision.logMessages, isEmpty);
    });

    test('a core that cannot allocate its memory is not memory pressure', () {
      const message = 'WebAssembly.Memory(): could not allocate memory';
      final decision = classifyWebGpuLoadFailure(
        _published(('uninitialized', '', message)),
        _escalation(),
      );

      expect(isMemoryPressureErrorText(message.toLowerCase()), isFalse);
      expect(decision.action, WebGpuRetryAction.giveUp);
    });

    test('a table index trap is not memory pressure', () {
      const message = 'table index is out of bounds';
      final decision = classifyWebGpuLoadFailure(
        _published((
          'wasm32',
          'core_wasm32_active;core_pthreads:1;thread_pool_size:4;'
              'threads_batch:4;model_network_stream;model_response_stream;'
              'model_load_ccall_failed',
          message,
        )),
        _escalation(),
      );

      expect(isMemoryPressureErrorText(message), isFalse);
      expect(decision.action, WebGpuRetryAction.giveUp);
      expect(decision.escalation.retriedWithWasm64, isFalse);
    });

    test('recognises only the V8 wording of a BigInt failure', () {
      const message = "can't convert BigInt to number";
      final decision = classifyWebGpuLoadFailure(
        _published((
          'wasm64',
          'core_mem64_attempt;core_mem64_active;core_pthreads:1;'
              'thread_pool_size:4;threads_batch:4;model_network_stream;'
              'model_response_stream;model_fs_write_loaded:0;'
              'model_fs_write_bigint_error',
          message,
        )),
        _escalation(),
      );

      expect(isBigIntInteropErrorText(message.toLowerCase()), isFalse);
      expect(decision.action, WebGpuRetryAction.giveUp);
      expect(decision.escalation.retriedWithWasm32, isFalse);
    });

    test('a model size in the error text is not a thread failure', () {
      const message =
          'Model response did not expose a readable stream (1138294784 bytes).';
      final decision = classifyWebGpuLoadFailure(
        _published(
          (
            'wasm64',
            'core_mem64_attempt;core_mem64_active;core_pthreads:1;'
                'thread_pool_size:4;threads_batch:4;'
                'model_fetch_backend_attempt;model_fetch_chunk:4194304;'
                'core_abort;model_fetch_backend_failed;model_network_no_stream;'
                'model_response_nostream',
            message,
          ),
          forced: true,
          optedIn: true,
        ),
        _escalation(),
      );

      expect(isThreadConstructorFailureText(message.toLowerCase()), isFalse);
      expect(decision.action, WebGpuRetryAction.restart);
      expect(decision.escalation.remoteFetchChunkRetryCount, 1);
      expect(decision.escalation.remoteFetchChunkBytes, 2 * 1024 * 1024);
    });

    test('a bridge URL in the error stack is not a thread failure', () {
      const errorText =
          'error: aborted(). build with -sassertions for more info. | '
          'aborted(). build with -sassertions for more info. | '
          'error: aborted(). build with -sassertions for more info.\n'
          '    at bridgeworkerproxy._worker.onmessage '
          '(https://example.com/threads/webgpu_bridge/'
          'llama_webgpu_bridge.js:1037:11)';
      final decision = classifyWebGpuLoadFailure(
        _failure(
          errorText: errorText,
          coreVariant: 'wasm64',
          runtimeNotes:
              'core_mem64_attempt;core_mem64_active;core_pthreads:1;'
              'thread_pool_size:4;threads_batch:4;model_fetch_backend_attempt;'
              'model_fetch_chunk:4194304;core_abort',
          forceRemoteFetchRequested: true,
          remoteFetchBackendOptedIn: true,
        ),
        _escalation(),
      );

      expect(isThreadConstructorFailureText(errorText), isFalse);
      expect(decision.action, WebGpuRetryAction.restart);
      expect(decision.escalation.remoteFetchChunkRetryCount, 1);
    });

    test('a resumed stream is not a staging failure', () {
      const notes =
          'core_mem64_attempt;core_mem64_active;core_pthreads:1;'
          'thread_pool_size:4;threads_batch:4;model_network_stream;'
          'model_response_stream;model_fs_write_loaded:32;'
          'model_stream_resume_retry:1;model_stream_resume_offset:32;'
          'model_network_stream;model_response_stream;model_load_ccall_failed';
      final decision = classifyWebGpuLoadFailure(
        _published(('wasm64', notes, 'memory access out of bounds')),
        _escalation(),
      );

      expect(runtimeNotesIndicateModelFsWriteFailure(notes), isFalse);
      expect(decision.action, WebGpuRetryAction.advance);
      expect(decision.logMessages, isEmpty);
    });

    test('a cancelled transfer is not a fetch backend abort', () {
      final decision = classifyWebGpuLoadFailure(
        _published((
          'wasm64',
          'core_mem64_attempt;core_mem64_active;core_pthreads:1;'
              'thread_pool_size:4;threads_batch:4;model_fetch_backend_attempt;'
              'model_fetch_chunk:4194304;model_fetch_backend_failed;'
              'model_network_stream;model_response_stream;'
              'model_fs_write_loaded:64;model_fs_write_abort',
          'Model load was cancelled.',
        ), optedIn: true),
        _escalation(),
      );

      expect(decision.escalation.remoteFetchBackendKnownUnstable, isFalse);
      expect(decision.escalation.retriedWithoutRemoteFetchBackend, isFalse);
    });

    test('a split model is not a skipped small fetch', () {
      const splitNotes =
          'core_pthreads:1;thread_pool_size:4;threads_batch:4;'
          'model_split_detected:2;model_fetch_backend_skipped_split;'
          'model_network_stream;model_response_stream;model_network_stream;'
          'model_response_stream;model_load_ccall_failed';
      final wasm64 = classifyWebGpuLoadFailure(
        _published((
          'wasm64',
          'core_mem64_attempt;core_mem64_active;$splitNotes',
          'memory access out of bounds',
        ), optedIn: true),
        _escalation(),
      );
      final wasm32 = classifyWebGpuLoadFailure(
        _published((
          'wasm32',
          'core_wasm32_active;$splitNotes',
          'memory access out of bounds',
        ), optedIn: true),
        _escalation(),
      );

      expect(wasm64.action, WebGpuRetryAction.advance);
      expect(wasm64.escalation.retriedWithWasm32, isFalse);
      expect(wasm32.action, WebGpuRetryAction.restart);
      expect(wasm32.escalation.retriedWithWasm64, isTrue);
    });

    test(
      'leaves the override alone after a forced abort without the opt-in',
      () {
        final decision = classifyWebGpuLoadFailure(
          _published((
            'wasm32',
            'core_wasm32_active;core_pthreads:1;thread_pool_size:4;'
                'threads_batch:4;model_fetch_backend_attempt;'
                'model_fetch_chunk:4194304;core_abort',
            nativeAbort,
          ), forced: true),
          _escalation(),
        );

        expect(decision.action, WebGpuRetryAction.giveUp);
        expect(decision.escalation.remoteFetchBackendKnownUnstable, isTrue);
        expect(decision.forceRemoteFetchBackend, isNull);
      },
    );

    test('the wasm32 restart keeps an abort from the same failure', () {
      final decision = classifyWebGpuLoadFailure(
        _published(
          (
            'wasm64',
            'core_mem64_attempt;core_mem64_active;core_pthreads:1;'
                'thread_pool_size:4;threads_capped_no_coi;threads_batch:1;'
                'model_fetch_backend_attempt;model_fetch_chunk:4194304;'
                'core_abort;model_fetch_backend_failed;model_network_stream;'
                'model_response_stream;model_fs_write_loaded:0;'
                'model_fs_write_bigint_error',
            'Cannot convert a BigInt value to a number',
          ),
          forced: true,
          optedIn: true,
        ),
        _escalation(),
      );

      expect(decision.action, WebGpuRetryAction.restart);
      expect(decision.escalation.retriedWithWasm32, isTrue);
      expect(decision.escalation.remoteFetchBackendKnownUnstable, isTrue);
    });

    test('matches a core variant built at run time', () {
      (String, String, String) atRunTime((String, String, String) output) {
        final (coreVariant, runtimeNotes, message) = output;
        return (
          String.fromCharCodes(coreVariant.codeUnits),
          runtimeNotes,
          message,
        );
      }

      final staging = classifyWebGpuLoadFailure(
        _published(atRunTime(_noStreamMem64Unavailable)),
        _escalation(),
      );
      final wasm32 = classifyWebGpuLoadFailure(
        _published(atRunTime(_skippedSmallTrapWasm64), optedIn: true),
        _escalation(),
      );
      final wasm64 = classifyWebGpuLoadFailure(
        _published(atRunTime(_streamedStagingOomWasm32)),
        _escalation(),
      );

      expect(staging.escalation.retriedWithWasm64, isTrue);
      expect(wasm32.escalation.retriedWithWasm32, isTrue);
      expect(wasm64.escalation.retriedWithWasm64, isTrue);
    });
  });

  group('published bridge failure sequences', () {
    const nativeAbort = 'Aborted(). Build with -sASSERTIONS for more info.';
    const mem64Prefix =
        'core_mem64_attempt;core_mem64_active;core_pthreads:1;'
        'thread_pool_size:4;threads_batch:4;';

    List<WebGpuRetryAction> actionsOf(List<WebGpuRetryDecision> decisions) =>
        decisions.map((decision) => decision.action).toList();

    test('a staging restart keeps the abort latch for the wasm64 restart', () {
      final decisions = _replay([
        _published(
          (
            'wasm64',
            'core_mem64_attempt;core_mem64_active;core_pthreads:1;'
                'thread_pool_size:4;threads_capped_no_coi;threads_batch:1;'
                'model_fetch_backend_attempt;model_fetch_chunk:4194304;'
                'core_abort;model_fetch_backend_failed;model_network_stream;'
                'model_response_stream;model_fs_write_loaded:0;'
                'model_fs_write_arraybuffer_oom',
            'Array buffer allocation failed',
          ),
          forced: true,
          optedIn: true,
        ),
        _published(
          (
            'wasm32',
            'core_mem64_attempt;core_mem64_unavailable;core_wasm32_active;'
                'core_pthreads:1;thread_pool_size:4;threads_capped_no_coi;'
                'threads_batch:1;model_network_stream;model_response_stream;'
                'model_fs_write_loaded:0;model_fs_write_arraybuffer_oom',
            'Array buffer allocation failed',
          ),
          forced: true,
          optedIn: true,
        ),
      ]);

      expect(actionsOf(decisions), <WebGpuRetryAction>[
        WebGpuRetryAction.restart,
        WebGpuRetryAction.restart,
      ]);
      expect(decisions[0].escalation.remoteFetchBackendKnownUnstable, isTrue);
      expect(decisions[1].forceRemoteFetchBackend, isFalse);
      expect(decisions[1].logMessages, <String>[
        'WebGpuLlamaBackend: wasm32 memory pressure detected; '
            'retrying with wasm64 core and streamed network loading.',
      ]);
    });

    test('the wasm64 restart stays spent after the ladder advances', () {
      final decisions = _replay([
        _published(_streamedStagingOomWasm32),
        _published(_noStreamMem64Unavailable),
        _published((
          'wasm32',
          'core_mem64_attempt;core_mem64_unavailable;core_wasm32_active;'
              'core_pthreads:1;thread_pool_size:4;threads_batch:4;'
              'model_network_stream;model_response_stream;'
              'model_fs_write_loaded:0;model_fs_write_arraybuffer_oom',
          'Array buffer allocation failed',
        ), attemptIndex: 1),
      ]);

      expect(actionsOf(decisions), <WebGpuRetryAction>[
        WebGpuRetryAction.restart,
        WebGpuRetryAction.advance,
        WebGpuRetryAction.advance,
      ]);
    });

    test('the wasm32 restart stays spent after the wasm64 restart', () {
      final decisions = _replay([
        _published(_skippedSmallTrapWasm64, optedIn: true),
        _published(_streamedTrapWasm32, optedIn: true),
        _published(
          (
            'wasm64',
            '${mem64Prefix}model_fetch_backend_attempt;'
                'model_fetch_chunk:4194304;model_fetch_backend_failed;'
                'model_network_stream;model_response_stream;'
                'model_fs_write_loaded:0;model_fs_write_arraybuffer_oom',
            'Array buffer allocation failed',
          ),
          forced: true,
          optedIn: true,
        ),
        _published(
          (
            'wasm64',
            '${mem64Prefix}model_fetch_backend_attempt;'
                'model_fetch_chunk:131072;model_fetch_backend_failed;'
                'model_network_stream;model_response_stream;'
                'model_fs_write_loaded:0;model_fs_write_bigint_error',
            'Cannot convert a BigInt value to a number',
          ),
          forced: true,
          optedIn: true,
        ),
      ]);

      expect(actionsOf(decisions), <WebGpuRetryAction>[
        WebGpuRetryAction.restart,
        WebGpuRetryAction.restart,
        WebGpuRetryAction.restart,
        WebGpuRetryAction.giveUp,
      ]);
      expect(decisions[1].forceRemoteFetchBackend, isTrue);
      expect(decisions[3].logMessages, <String>[
        'WebGpuLlamaBackend: wasm64 model staging failed; skipping '
            'fallback ladder because additional nCtx/GPU/thread '
            'reductions are unlikely to recover FS write failures.',
      ]);
    });

    test('a native load BigInt error is not a staging failure', () {
      const notes =
          '${mem64Prefix}model_fetch_backend_attempt;model_fetch_chunk:4194304;'
          'model_fetch_backend_failed;model_network_stream;'
          'model_response_stream;model_load_ccall_bigint_error';
      final decisions = _replay([
        _published(_skippedSmallTrapWasm64, optedIn: true),
        _published(_streamedTrapWasm32, optedIn: true),
        _published(
          ('wasm64', notes, 'Cannot convert a BigInt value to a number'),
          forced: true,
          optedIn: true,
        ),
      ]);

      expect(runtimeNotesIndicateModelFsWriteFailure(notes), isFalse);
      expect(decisions.last.action, WebGpuRetryAction.giveUp);
      expect(decisions.last.logMessages, isEmpty);
    });

    test('the chunk restart count survives a ladder advance', () {
      final decisions = _replay([
        _published(
          (
            'wasm64',
            '${mem64Prefix}model_fetch_backend_attempt;'
                'model_fetch_chunk:20480;core_abort',
            nativeAbort,
          ),
          forced: true,
          optedIn: true,
        ),
        _published(
          (
            'wasm64',
            '${mem64Prefix}model_fetch_backend_attempt;'
                'model_fetch_chunk:16384',
            'memory access out of bounds',
          ),
          forced: true,
          optedIn: true,
        ),
        _published(
          (
            'wasm64',
            '${mem64Prefix}model_fetch_backend_attempt;'
                'model_fetch_chunk:16384;core_abort',
            nativeAbort,
          ),
          attemptIndex: 1,
          forced: true,
          optedIn: true,
        ),
      ], remoteFetchChunkBytes: 20 * 1024);

      expect(actionsOf(decisions), <WebGpuRetryAction>[
        WebGpuRetryAction.restart,
        WebGpuRetryAction.advance,
        WebGpuRetryAction.restart,
      ]);
      expect(decisions[2].logMessages, <String>[
        'WebGpuLlamaBackend: fetch-backed model loading aborted; '
            'retrying with smaller fetch chunks (5 KiB, attempt #2).',
      ]);
    });

    test('a chunk restart keeps the streamed restart spent', () {
      final decisions = _replay([
        _published((
          'wasm64',
          '${mem64Prefix}model_fetch_backend_attempt;'
              'model_fetch_chunk:4194304;core_abort',
          nativeAbort,
        ), optedIn: true),
        _published((
          'wasm64',
          '${mem64Prefix}model_network_stream;model_response_stream;'
              'model_fs_write_loaded:0;model_fs_write_arraybuffer_oom',
          'Array buffer allocation failed',
        ), optedIn: true),
        _published(
          (
            'wasm64',
            '${mem64Prefix}model_fetch_backend_attempt;'
                'model_fetch_chunk:131072;core_abort',
            nativeAbort,
          ),
          forced: true,
          optedIn: true,
        ),
      ]);

      expect(actionsOf(decisions), <WebGpuRetryAction>[
        WebGpuRetryAction.restart,
        WebGpuRetryAction.restart,
        WebGpuRetryAction.restart,
      ]);
      expect(decisions[2].escalation.remoteFetchChunkBytes, 64 * 1024);
      expect(decisions[2].escalation.retriedWithoutRemoteFetchBackend, isTrue);
    });
  });
}
