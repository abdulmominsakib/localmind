part of 'runtime_owner.dart';

/// Opaque same-process cache of one evaluated raw prompt, owned by one pool.
///
/// Created by [LlamaDartRuntimePromptCache.cachePrompt]. It contains sensitive native KV
/// bytes and a prompt in memory; there is no export, file-path or serialization
/// API. It survives owner close, but cannot cross pools or process lifetimes.
/// This is not a chat checkpoint and contains no message history or sampler/RNG.
final class LlamaDartPromptCache {
  LlamaDartPromptCache._(
    this._pool,
    this._prompt,
    this._identity,
    List<int> tokens,
    List<int> bytes,
  ) : tokenCount = tokens.length,
      _tokens = List<int>.unmodifiable(tokens),
      _bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  final LlamaDartRuntimePool _pool;
  String? _prompt;
  final String _identity;
  List<int>? _tokens;
  Uint8List? _bytes;

  /// Number of evaluated prompt tokens, including tokenizer special tokens.
  final int tokenCount;

  /// Whether this handle has released its retained prompt and native state.
  bool get isDisposed => _bytes == null;

  /// Releases retained state and pool admission; terminal and idempotent.
  ///
  /// Already active operations settle with their own immutable byte reference.
  /// Queued or later operations reject a disposed handle. Pool close disposes
  /// every retained handle after its owners settle.
  void dispose() {
    final bytes = _bytes;
    if (bytes == null) return;
    _bytes = null;
    _prompt = null;
    _tokens = null;
    _pool._promptCaches.remove(this);
    _pool._promptCacheBytes -= bytes.length;
  }

  @override
  String toString() =>
      'LlamaDartPromptCache(tokenCount: $tokenCount, disposed: $isDisposed)';
}

/// Same-process raw-prompt cache operations on independently owned contexts.
extension LlamaDartRuntimePromptCache on LlamaDartRuntimeOwner {
  /// Evaluates [prompt] afresh and caches its settled native KV state.
  ///
  /// Requires [LlamaDartRuntimePool.enablePromptCache], the default native
  /// runtime, state/scoring support, immutable GGUF bytes and no projector/LoRA.
  /// Runs in the owner's queue; limits and fresh probes precede temporary file
  /// access. A handle is published only after successful evaluation, native save,
  /// bounded read and cleanup. Cancellation/failure publishes no handle and
  /// closes the uncertain owner. Temporary files are deleted before return.
  Future<LlamaDartPromptCache> cachePrompt(
    String prompt, {
    genkit.CancellationToken? cancellation,
  }) {
    if (prompt.isEmpty) {
      throw ArgumentError('The raw prompt must not be empty.');
    }
    return _run((_) async {
      final runtime = _promptCacheRuntime();
      final pool = _pool;
      if (pool._promptCaches.length + pool._pendingPromptCaches >=
          pool.maxPromptCaches) {
        throw llama.LlamaStateException(
          'The prompt cache handle limit is reached.',
        );
      }
      pool._pendingPromptCaches++;
      try {
        await _verifyPromptModel();
        final saved = await withPromptCacheFile((path) async {
          final tokens = await runtime.savePromptCache(prompt, path);
          final bytes = await readPromptCache(path, pool.maxPromptCacheBytes);
          return (tokens, bytes);
        });
        _checkCancellation(cancellation);
        if (saved.$2.length >
            pool.maxPromptCacheBytes - pool._promptCacheBytes) {
          throw llama.LlamaStateException(
            'The pool prompt cache byte limit is reached.',
          );
        }
        final cache = LlamaDartPromptCache._(
          pool,
          prompt,
          _modelIdentity!,
          saved.$1,
          saved.$2,
        );
        pool._promptCaches.add(cache);
        pool._promptCacheBytes += saved.$2.length;
        return cache;
      } finally {
        pool._pendingPromptCaches--;
      }
    }, cancellation: cancellation);
  }

  /// Restores [cache] and generates from its original raw prompt atomically.
  ///
  /// The handle must be live and from this same pool/model/build/context, with
  /// no adapters applied to this owner. No arbitrary path or client identity is
  /// accepted. Returned tokens are checked before inference. Exact sampler
  /// continuation is unavailable: native restore re-evaluates the final token
  /// for logits; automatic batching can change greedy output. Use cache reuse
  /// for a prompt evaluation optimization, never exact chat recovery.
  ///
  /// [params] must enable prefix reuse and disable speculation. Temporary state
  /// files are removed before generation. Cancellation/failure closes this
  /// owner; other owners and valid handles remain independent.
  Future<String> generateFromCache(
    LlamaDartPromptCache cache, {
    llama.GenerationParams params = const llama.GenerationParams(),
    genkit.CancellationToken? cancellation,
  }) {
    if (!params.reusePromptPrefix ||
        params.speculativeDecoding ||
        params.speculativeDecodingConfig != null) {
      throw ArgumentError(
        'Cached generation requires prefix reuse without speculation.',
      );
    }
    return _run((_) async {
      final runtime = _promptCacheRuntime();
      if (!identical(cache._pool, _pool) ||
          cache.isDisposed ||
          cache._identity != _modelIdentity) {
        throw llama.LlamaStateException(
          'The prompt cache is unavailable or incompatible with this owner.',
        );
      }
      final bytes = cache._bytes!;
      final prompt = cache._prompt!;
      final expectedTokens = cache._tokens!;
      await _verifyPromptModel();
      await withPromptCacheFile((path) async {
        await writePromptCache(path, bytes);
        final tokens = await runtime.loadPromptCache(path, cache.tokenCount);
        if (tokens.length != expectedTokens.length ||
            Iterable<int>.generate(
              tokens.length,
            ).any((i) => tokens[i] != expectedTokens[i])) {
          throw llama.LlamaStateException(
            'Restored prompt tokens do not match the cached evaluation.',
          );
        }
      });
      _checkCancellation(cancellation);
      _generating = true;
      try {
        return await runtime.generate(prompt, params: params).join();
      } finally {
        _generating = false;
      }
    }, cancellation: cancellation);
  }

  LlamaEngineRuntime _promptCacheRuntime() {
    _pool._checkPromptCacheConfiguration();
    if (_adaptersChanged ||
        _runtime is! LlamaEngineRuntime ||
        !(_runtime as LlamaEngineRuntime).supportsPromptCache) {
      throw llama.LlamaUnsupportedException(
        'This owner cannot cache raw prompts after adapter changes or without native state/scoring support.',
      );
    }
    return _runtime as LlamaEngineRuntime;
  }

  Future<void> _verifyPromptModel() async {
    if (_modelIdentity == null ||
        await promptModelIdentity(_pool._model.modelPath) != _modelIdentity) {
      throw llama.LlamaStateException(
        'The immutable prompt-cache model identity changed.',
      );
    }
  }
}
