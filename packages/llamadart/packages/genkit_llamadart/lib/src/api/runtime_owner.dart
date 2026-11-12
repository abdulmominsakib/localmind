import 'dart:async';
import 'dart:typed_data';

import 'package:genkit/genkit.dart' as genkit;
import 'package:llamadart/llamadart.dart' as llama;

import '../core/runtime/llama_engine_runtime.dart';
import '../core/runtime/llama_runtime.dart';
import '../core/runtime/prompt_cache_files.dart';
import 'model_definition.dart';

part 'runtime_prompt_cache.dart';

/// Bounds independently owned native llama.cpp contexts for one local GGUF.
///
/// Each [open] creates a fresh runtime outside the plugin's shared model registry.
/// Use handles in application-authorized Genkit flows. The application owns
/// authorization and message history. The pool has no session IDs or checkpoint
/// storage. Live-adapter mutations stay within their owner. Each owner loads its
/// own context and model; shared files do not guarantee shared allocations.
final class LlamaDartRuntimePool {
  /// Creates a native-only pool without loading the model.
  ///
  /// [maxOwners] includes opening and closing owners. [maxQueuedOperations] bounds
  /// waiting work per owner, including work not yet started by the event loop.
  /// [idleTimeout] closes an owner only when it has no active or queued work.
  /// All limits must be positive. Only `.gguf` definitions are accepted by [open];
  /// Web and LiteRT-LM fail before runtime allocation or model access.
  ///
  /// [runtimeFactory] must produce a new, independently owned context every time
  /// and report supported llama.cpp capabilities. Reused runtime objects are
  /// rejected. Custom factories own observer installation and backend isolation;
  /// separate object identities alone cannot prove independent native contexts.
  LlamaDartRuntimePool({
    required LlamaModelDefinition model,
    this.maxOwners = 2,
    this.maxQueuedOperations = 8,
    this.idleTimeout = const Duration(minutes: 5),
    this.enablePromptCache = false,
    this.maxPromptCaches = 2,
    this.maxPromptCacheBytes = 64 * 1024 * 1024,
    LlamaDartRuntimeFactory? runtimeFactory,
    Iterable<llama.LlamaEngineObserver> observers = const [],
  }) {
    _model = enablePromptCache
        ? LlamaModelDefinition(
            name: model.name,
            modelPath: model.modelPath,
            modelParams: model.modelParams.copyWith(
              loras: List.unmodifiable(model.modelParams.loras),
            ),
            mmprojPath: model.mmprojPath,
            supportsEmbeddings: model.supportsEmbeddings,
            supportsTools: model.supportsTools,
            supportsConstrainedOutput: model.supportsConstrainedOutput,
            modelInfo: model.modelInfo,
          )
        : model;
    _usesDefaultRuntime = runtimeFactory == null;
    if (maxOwners < 1 ||
        maxQueuedOperations < 1 ||
        idleTimeout <= Duration.zero ||
        maxPromptCaches < 1 ||
        maxPromptCacheBytes < 1) {
      throw ArgumentError('Runtime pool limits must be positive.');
    }
    final snapshot = List<llama.LlamaEngineObserver>.unmodifiable(observers);
    _factory = runtimeFactory ?? () => LlamaEngineRuntime(observers: snapshot);
  }

  late final LlamaModelDefinition _model;
  late final LlamaDartRuntimeFactory _factory;
  late final bool _usesDefaultRuntime;
  final Set<LlamaDartPromptCache> _promptCaches = {};
  int _pendingPromptCaches = 0;
  int _promptCacheBytes = 0;
  final Set<LlamaDartRuntimeOwner> _owners = {};
  final Expando<bool> _seenRuntimes = Expando<bool>();
  Future<void>? _closing;

  /// Maximum number of unsettled owners, including opening/closing contexts.
  final int maxOwners;

  /// Maximum requests waiting in each owner's queue.
  final int maxQueuedOperations;

  /// Idle duration before an otherwise unused owner closes itself.
  final Duration idleTimeout;

  /// Enables same-process raw-prompt caches on default native runtimes only.
  ///
  /// Opt-in because opening an owner verifies the immutable GGUF's SHA-256.
  /// Caches cannot cross pools, processes, builds, adapters or model identities.
  /// Projectors, load-time/live LoRA and custom runtimes are unsupported.
  final bool enablePromptCache;

  /// Maximum retained/in-progress prompt cache handles in this pool.
  final int maxPromptCaches;

  /// Maximum retained opaque native state bytes across prompt cache handles.
  ///
  /// Does not include native allocations or temporary save/load files. Dispose
  /// unused handles; an in-flight restore retains its bytes until it settles.
  final int maxPromptCacheBytes;

  /// Allocates and loads one independently owned native context.
  ///
  /// Throws [llama.LlamaStateException] when closed or full,
  /// [genkit.CancelledException] for cancellation, and
  /// [llama.LlamaUnsupportedException] on Web, non-GGUF models or a runtime that
  /// cannot verify supported llama.cpp execution. Loading/probe failures dispose
  /// the failed context before returning a neutral error without model paths.
  /// No waiting list or eviction of another owner's context is performed.
  Future<LlamaDartRuntimeOwner> open({
    genkit.CancellationToken? cancellation,
  }) async {
    if (_closing != null) throw _unavailable();
    _checkCancellation(cancellation);
    if (const bool.fromEnvironment('dart.library.js_interop') ||
        llama.ModelFormat.fromPath(_model.modelPath) !=
            llama.ModelFormat.gguf) {
      throw llama.LlamaUnsupportedException(
        'Isolated runtime owners require native llama.cpp and a local .gguf model. '
        'Web and LiteRT-LM owners are not supported.',
      );
    }
    if (_owners.length >= maxOwners) {
      throw llama.LlamaStateException(
        'The isolated runtime pool is full. Close an owner before opening another.',
      );
    }
    final owner = LlamaDartRuntimeOwner._(this);
    _owners.add(owner);
    try {
      final LlamaDartRuntime runtime;
      try {
        runtime = _factory();
      } catch (_) {
        throw llama.LlamaStateException(
          'Unable to allocate an isolated native runtime. Check runtime installation.',
        );
      }
      if (_seenRuntimes[runtime] == true) {
        throw llama.LlamaStateException(
          'The runtime factory reused an owned runtime. Return a fresh independent context.',
        );
      }
      _seenRuntimes[runtime] = true;
      owner._allocated = runtime;
      if (owner._closed || _closing != null) throw _unavailable();
      await owner._run(
        (_) async {
          if (enablePromptCache) {
            _checkPromptCacheConfiguration();
            owner._modelIdentity = await promptModelIdentity(_model.modelPath);
          }
          await runtime.initialize(_model);
          if (enablePromptCache &&
              owner._modelIdentity !=
                  await promptModelIdentity(_model.modelPath)) {
            throw llama.LlamaStateException(
              'The cache model changed during loading.',
            );
          }
        },
        cancellation: cancellation,
        probe: false,
      );
      await owner._run((_) async {}, cancellation: cancellation);
      if (owner._closed) throw _unavailable();
      return owner;
    } catch (_) {
      await owner.close();
      rethrow;
    }
  }

  /// Rejects new owners, drains accepted work and closes every owned context.
  ///
  /// Terminal and idempotent. Cancel active inference separately when needed.
  /// Cleanup failures remain observable on this future, including owners whose
  /// earlier automatic cleanup failed. Independent contexts close concurrently.
  /// Retained prompt caches are disposed after all owners settle, even on failure.
  Future<void> close() => _closing ??= () async {
    try {
      await _owners.toList().map((owner) => owner.close()).wait;
    } finally {
      for (final cache in _promptCaches.toList()) {
        cache.dispose();
      }
    }
  }();

  void _checkPromptCacheConfiguration() {
    if (!enablePromptCache ||
        !_usesDefaultRuntime ||
        _model.mmprojPath != null ||
        _model.modelParams.loras.isNotEmpty) {
      throw llama.LlamaUnsupportedException(
        'Raw prompt caches require an opted-in default native runtime without projectors or LoRA.',
      );
    }
  }
}

/// An application-owned, serialized native raw-prompt context.
///
/// Obtain it from [LlamaDartRuntimePool.open] and keep the handle within trusted
/// application code. Results can be returned from typed Genkit flows. Prompts
/// and results are sensitive: choose an appropriate Genkit telemetry policy.
/// This owner buffers generation; it exposes no mutable engine or chat history.
final class LlamaDartRuntimeOwner {
  LlamaDartRuntimeOwner._(this._pool);

  final LlamaDartRuntimePool _pool;
  LlamaDartRuntime? _allocated;
  LlamaDartRuntime get _runtime => _allocated!;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closing;
  Timer? _idle;
  int _queued = 0;
  bool _closed = false;
  bool _faulted = false;
  bool _generating = false;
  bool _activeCancelled = false;
  String? _modelIdentity;
  bool _adaptersChanged = false;

  /// Whether this owner has begun closing or faulted and rejects new requests.
  bool get isClosed => _closed || _faulted;

  /// Generates a complete raw-text result in this owner's bounded queue.
  ///
  /// [prompt] must be nonempty and already contain any desired chat template.
  /// [params] are llamadart raw generation parameters; no tools or Genkit chat
  /// orchestration is inferred. Prefix reuse applies only to this owner's context.
  /// Cancellation or a native/probe failure closes this owner after work settles;
  /// open a new owner and replay application-owned history to recover.
  Future<String> generate(
    String prompt, {
    llama.GenerationParams params = const llama.GenerationParams(),
    genkit.CancellationToken? cancellation,
  }) {
    if (prompt.isEmpty) {
      throw ArgumentError('The raw prompt must not be empty.');
    }
    return _run((_) async {
      _generating = true;
      try {
        return await _runtime.generate(prompt, params: params).join();
      } finally {
        _generating = false;
      }
    }, cancellation: cancellation);
  }

  /// Scores a raw prompt without sampling or chat-template rendering.
  ///
  /// The loaded runtime must freshly report next-token scoring support and
  /// implement [LlamaRuntimeScoringProvider]. Candidate IDs are snapshotted at
  /// submission; vocabulary limits are checked by the backend. No checkpoint or
  /// exact continuation guarantee is implied. Failures close the uncertain owner.
  Future<llama.LlamaNextTokenScores> scoreNextToken(
    String prompt, {
    List<int> candidates = const [],
    int topK = 0,
    bool reusePromptPrefix = true,
    genkit.CancellationToken? cancellation,
  }) {
    if (prompt.isEmpty ||
        topK < 0 ||
        candidates.any((id) => id < 0) ||
        (topK == 0 && candidates.isEmpty)) {
      throw ArgumentError(
        'Scoring requires a prompt and nonnegative candidates or positive topK.',
      );
    }
    final snapshot = List<int>.unmodifiable(candidates);
    return _run((capabilities) async {
      if (!capabilities!.supportsNextTokenScoring ||
          _runtime is! LlamaRuntimeScoringProvider) {
        throw llama.LlamaUnsupportedException(
          'This isolated runtime does not support next-token scoring.',
        );
      }
      return (_runtime as LlamaRuntimeScoringProvider).scoreNextToken(
        prompt,
        candidates: snapshot,
        topK: topK,
        reusePromptPrefix: reusePromptPrefix,
      );
    }, cancellation: cancellation);
  }

  /// Applies or rescales one compatible adapter between inference operations.
  ///
  /// [scale] must be finite. [download] belongs only to this adapter source;
  /// base-model credentials/checksums are never copied to it. Its cancellation
  /// token stops downloads. [onProgress] is application-owned and can contain
  /// source information; do not export it without a telemetry policy.
  ///
  /// An explicit native live-LoRA probe runs before resolution/download. Success
  /// invalidates native prompt-prefix reuse; replay committed history with the
  /// new configuration. A source/native failure faults and closes this owner;
  /// other owners keep their adapters and context. Genkit cancellation waits for
  /// native work to settle; use [download]'s token to interrupt a download.
  Future<void> setLoraSource(
    llama.ModelSource source, {
    double scale = 1,
    llama.ModelLoadOptions download = llama.ModelLoadOptions.defaults,
    llama.ModelDownloadProgressCallback? onProgress,
    genkit.CancellationToken? cancellation,
  }) {
    if (!scale.isFinite) throw ArgumentError('LoRA scale must be finite.');
    return _withLora(
      (provider) => provider.setLoraSource(
        source,
        scale: scale,
        download: download,
        onProgress: onProgress,
      ),
      cancellation: cancellation,
    );
  }

  /// Removes the adapter previously applied from [source] in the same queue.
  ///
  /// Cached prefixes are invalidated on success. Removal never mutates another
  /// owner's context. Capability or mutation failure closes the uncertain owner.
  Future<void> removeLoraSource(
    llama.ModelSource source, {
    genkit.CancellationToken? cancellation,
  }) => _withLora(
    (provider) => provider.removeLoraSource(source),
    cancellation: cancellation,
  );

  /// Clears all adapters, including load-time adapters, from this owner.
  ///
  /// Invalidates cached prompt-prefix reuse on success.
  ///
  /// Serialized with inference; failure closes this owner before reuse.
  Future<void> clearLoras({genkit.CancellationToken? cancellation}) =>
      _withLora(
        (provider) => provider.clearLoras(),
        cancellation: cancellation,
      );

  Future<void> _withLora(
    Future<void> Function(LlamaRuntimeLoraProvider provider) operation, {
    genkit.CancellationToken? cancellation,
  }) => _run((_) async {
    if (_runtime is! LlamaRuntimeLoraProvider ||
        !await (_runtime as LlamaRuntimeLoraProvider).supportsLiveLora) {
      throw llama.LlamaUnsupportedException(
        'Live LoRA requires a supported native adapter API and explicit runtime probe.',
      );
    }
    _checkCancellation(cancellation);
    _adaptersChanged = true;
    await operation(_runtime as LlamaRuntimeLoraProvider);
  }, cancellation: cancellation);

  /// Requests cancellation only of this owner's active generation.
  ///
  /// Bypasses the queue. Once generation is active, the owner faults and drains
  /// pending requests without starting their native work, then disposes itself.
  /// No-op while loading, scoring, idle or closed. Queued-request cancellation
  /// instead uses [genkit.CancellationToken]. It never targets another owner.
  void cancelActiveGeneration() {
    if (!_generating || _faulted) return;
    _requestCancellation();
  }

  /// Rejects new requests, drains accepted work and disposes this context once.
  ///
  /// Does not cancel active inference. Terminal and idempotent; disposal errors
  /// remain observable on repeated calls. Admission is released only after
  /// successful cleanup, so failed cleanup cannot silently exceed the pool limit.
  Future<void> close() {
    _closed = true;
    _idle?.cancel();
    return _closing ??= _tail.then((_) async {
      try {
        await _allocated?.dispose();
        _pool._owners.remove(this);
      } catch (_) {
        throw llama.LlamaStateException(
          'Failed to close the isolated runtime. Native cleanup must be checked before reusing its resources.',
        );
      }
    });
  }

  Future<T> _run<T>(
    Future<T> Function(llama.LlamaEngineCapabilities? capabilities) operation, {
    genkit.CancellationToken? cancellation,
    bool probe = true,
  }) {
    if (isClosed) return Future<T>.error(_unavailable());
    if (_queued >= _pool.maxQueuedOperations) {
      return Future<T>.error(
        llama.LlamaStateException(
          'The isolated runtime request queue is full. Await existing work before submitting more.',
        ),
      );
    }
    _idle?.cancel();
    _queued++;
    final result = _tail.then((_) async {
      _queued--;
      if (_faulted) throw _unavailable();
      _checkCancellation(cancellation);
      final unregister = cancellation?.onCancel(_requestCancellation);
      _activeCancelled = false;
      try {
        llama.LlamaEngineCapabilities? capabilities;
        if (probe) {
          if (_runtime is! LlamaRuntimeCapabilityProvider) {
            throw llama.LlamaUnsupportedException(
              'Isolated owners require a fresh native runtime capability probe.',
            );
          }
          capabilities =
              await (_runtime as LlamaRuntimeCapabilityProvider).capabilities;
          if (!capabilities.isSupported ||
              capabilities.runtime != llama.LlamaRuntime.llamaCpp) {
            throw llama.LlamaUnsupportedException(
              'Isolated owners require a supported native llama.cpp context.',
            );
          }
        }
        _checkCancellation(cancellation);
        final value = await operation(capabilities);
        if (_activeCancelled) throw _cancelled();
        return value;
      } catch (error) {
        _faulted = true;
        if (_activeCancelled) throw _cancelled();
        if (error is llama.LlamaUnsupportedException) {
          throw llama.LlamaUnsupportedException(
            'This isolated runtime operation is unavailable. Check native llama.cpp capabilities and the supplied operation options.',
          );
        }
        throw llama.LlamaStateException(
          'The isolated runtime operation failed. Open a new owner and replay committed application history.',
        );
      } finally {
        unregister?.call();
        _scheduleIdle();
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result.then<T>(
      (value) => value,
      onError: (Object error, StackTrace stack) async {
        if (_faulted) {
          await close();
        } else {
          _scheduleIdle();
        }
        Error.throwWithStackTrace(error, stack);
      },
    );
  }

  void _requestCancellation() {
    _activeCancelled = true;
    _faulted = true;
    if (_generating) {
      try {
        _runtime.cancelGeneration();
      } catch (_) {}
    }
  }

  void _scheduleIdle() {
    if (_closed || _faulted || _queued != 0) return;
    _idle?.cancel();
    _idle = Timer(_pool.idleTimeout, () {
      close().then<void>((_) {}, onError: (Object _, StackTrace _) {});
    });
  }
}

llama.LlamaStateException _unavailable() =>
    llama.LlamaStateException('The isolated runtime owner or pool is closed.');
genkit.CancelledException _cancelled() => genkit.CancelledException();
void _checkCancellation(genkit.CancellationToken? cancellation) {
  if (cancellation?.isCancelled ?? false) throw _cancelled();
}
