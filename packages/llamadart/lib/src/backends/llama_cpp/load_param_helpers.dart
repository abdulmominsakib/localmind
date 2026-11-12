// Focused helpers for native model loading and sampler setup. Kept here (vs
// inlined in the service) so they can be unit-tested without going through
// `LlamaEngine.loadModel`, which is integration-level and needs a real model.

import 'dart:convert';
import 'dart:ffi';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';

import '../../core/models/config/flash_attention.dart';
import '../../core/models/config/kv_cache_type.dart';
import '../../core/models/config/llama_cpp_param_values.dart'
    as llama_cpp_values;
import '../../core/models/inference/model_params.dart';
import 'bindings.dart';

export '../../core/models/config/llama_cpp_param_values.dart'
    show resolveFlashAttention;

/// Maps llamadart's [KvCacheType] enum to llama.cpp's `ggml_type`. Pure
/// switch, no side effects.
ggml_type ggmlTypeFor(KvCacheType type) {
  return ggml_type.fromValue(llama_cpp_values.ggmlTypeValueFor(type));
}

/// Creates a llama.cpp logit-bias sampler that suppresses [tokens].
///
/// The native sampler copies the bias entries before this function releases
/// its temporary allocation. Returns `nullptr` when [tokens] is empty.
Pointer<llama_sampler> createSuppressTokensSampler(
  int vocabSize,
  List<int> tokens,
) {
  if (tokens.isEmpty) {
    return nullptr;
  }

  final biases = calloc<llama_logit_bias>(tokens.length);
  try {
    for (int i = 0; i < tokens.length; i++) {
      biases[i]
        ..token = tokens[i]
        ..bias = double.negativeInfinity;
    }
    return llama_sampler_init_logit_bias(vocabSize, tokens.length, biases);
  } finally {
    calloc.free(biases);
  }
}

/// Signature used to read model-defined suppress-token metadata from llama.cpp.
typedef SuppressTokensGetter =
    Pointer<llama_token> Function(Pointer<llama_vocab>, Pointer<Int32>);

/// Copies model-defined suppress-token metadata into an immutable Dart list.
///
/// Call this once while initializing a loaded model, then reuse the returned
/// list when constructing sampler chains. The native token pointer remains
/// owned by llama.cpp.
List<int> readModelSuppressTokens(
  Pointer<llama_vocab> vocab, {
  SuppressTokensGetter? getSuppressTokens,
}) {
  final countPointer = calloc<Int32>();
  try {
    final tokensPointer =
        (getSuppressTokens ?? llama_vocab_get_suppress_tokens)(
          vocab,
          countPointer,
        );
    final count = countPointer.value;
    if (tokensPointer == nullptr || count <= 0) {
      return const <int>[];
    }
    return List<int>.unmodifiable(tokensPointer.asTypedList(count));
  } finally {
    calloc.free(countPointer);
  }
}

/// Applies the user-controlled fields of [params] to a freshly-defaulted
/// `llama_model_params` struct. Pure function: caller is responsible for
/// initialising and freeing the struct.
void applyModelParams(llama_model_params mparams, ModelParams params) {
  final loadMode = switch ((params.useMmap, params.useMlock)) {
    (false, false) => llama_load_mode.LLAMA_LOAD_MODE_NONE,
    (true, false) => llama_load_mode.LLAMA_LOAD_MODE_MMAP,
    (false, true) => llama_load_mode.LLAMA_LOAD_MODE_MLOCK,
    (true, true) => llama_load_mode.LLAMA_LOAD_MODE_MMAP_MLOCK,
  };
  mparams.load_modeAsInt = loadMode.value;
  mparams.load_mtp = params.loadMtp;
}

/// Applies the user-controlled fields of [params] to a `llama_context_params`
/// struct. Honours the `auto` → `enabled` flash-attention promotion via
/// [resolveFlashAttention]. Returns the resolved [FlashAttention] so the
/// caller can log whether a promotion occurred.
FlashAttention applyContextParams(
  llama_context_params ctxParams,
  ModelParams params,
) {
  final resolvedFlashAttn = llama_cpp_values.resolveFlashAttention(
    requested: params.flashAttention,
    cacheTypeK: params.cacheTypeK,
    cacheTypeV: params.cacheTypeV,
  );
  switch (resolvedFlashAttn) {
    case FlashAttention.auto:
      break;
    case FlashAttention.enabled:
      ctxParams.flash_attn_typeAsInt =
          llama_flash_attn_type.LLAMA_FLASH_ATTN_TYPE_ENABLED.value;
      break;
    case FlashAttention.disabled:
      ctxParams.flash_attn_typeAsInt =
          llama_flash_attn_type.LLAMA_FLASH_ATTN_TYPE_DISABLED.value;
      break;
  }
  ctxParams.type_kAsInt = ggmlTypeFor(params.cacheTypeK).value;
  ctxParams.type_vAsInt = ggmlTypeFor(params.cacheTypeV).value;
  if (params.kvUnified != null) {
    ctxParams.kv_unified = params.kvUnified!;
  }
  if (params.ropeFrequencyBase != null) {
    ctxParams.rope_freq_base = params.ropeFrequencyBase!;
  }
  if (params.ropeFrequencyScale != null) {
    ctxParams.rope_freq_scale = params.ropeFrequencyScale!;
  }
  ctxParams.moe_cache_size = params.moeCacheBytes;
  return resolvedFlashAttn;
}

/// The canonical encoding of the [ctxParams] fields that change the layout
/// or the content of a saved llama.cpp state: K and V cache types,
/// flash-attention mode, sequence count, unified KV, full-size SWA cache, and
/// the RoPE frequency base and scale written into the params (0 keeps the
/// model's value).
///
/// The flash-attention mode is the requested one: llama.cpp resolves `auto`
/// per device, and rejects a state whose V cache transposition differs.
/// llama.cpp does not check RoPE settings, and keys saved under other ones
/// restore without error but score wrongly. Changing a field or its spelling
/// needs a new version tag.
String stateContextConfigEncoding(llama_context_params ctxParams) => [
  'llamadart-state-context/2',
  'type_k=${ctxParams.type_k.name}',
  'type_v=${ctxParams.type_v.name}',
  'flash_attn=${ctxParams.flash_attn_type.name}',
  'n_seq_max=${ctxParams.n_seq_max}',
  'kv_unified=${ctxParams.kv_unified}',
  'swa_full=${ctxParams.swa_full}',
  'rope_freq_base=${ctxParams.rope_freq_base}',
  'rope_freq_scale=${ctxParams.rope_freq_scale}',
].join(';');

/// The SHA-256 hex digest of [stateContextConfigEncoding].
String stateContextConfigDigest(llama_context_params ctxParams) => sha256
    .convert(utf8.encode(stateContextConfigEncoding(ctxParams)))
    .toString();

/// The context parameters a speculative session creates its draft context
/// from, for a target context created with [targetParams].
///
/// Returns [targetParams] itself when [draftMicroBatchSize] is null, so the
/// draft context keeps the target's micro-batch size. Otherwise copies
/// [targetParams] into [scratch], which the caller allocates and frees, and
/// sets its `n_ubatch` to [draftMicroBatchSize].
llama_context_params speculativeDraftContextParams(
  llama_context_params targetParams,
  int? draftMicroBatchSize,
  Pointer<llama_context_params> scratch,
) {
  if (draftMicroBatchSize == null) {
    return targetParams;
  }
  scratch.ref = targetParams;
  return scratch.ref..n_ubatch = draftMicroBatchSize;
}

/// The CPU thread count to pass to llama.cpp for a [requested] count.
///
/// A positive [requested] is returned unchanged. Otherwise returns ggml's
/// default of 4 (`GGML_DEFAULT_N_THREADS`), capped at [availableCores]:
/// `ggml_barrier` spin-waits, so more threads than cores stall each other and
/// inference runs tens of times slower.
int resolveCpuThreads(int requested, {required int availableCores}) =>
    requested > 0 ? requested : availableCores.clamp(1, 4);

/// Sets the generation and batch thread counts of [ctxParams] from [params],
/// through [resolveCpuThreads].
void applyContextThreads(
  llama_context_params ctxParams,
  ModelParams params, {
  required int availableCores,
}) {
  ctxParams.n_threads = resolveCpuThreads(
    params.numberOfThreads,
    availableCores: availableCores,
  );
  ctxParams.n_threads_batch = resolveCpuThreads(
    params.numberOfThreadsBatch,
    availableCores: availableCores,
  );
}

/// Configures a decision head's private encoder context.
///
/// One sequence of up to [maxTokens] tokens runs in one ubatch, with
/// per-token embeddings and no pooling. Thread counts come from [params] and
/// [availableCores], through [applyContextThreads].
/// When [runsOnCpu], KQV and op offload and flash attention are disabled so no
/// work reaches a GPU backend.
void applyDecisionContextParams(
  llama_context_params ctxParams,
  ModelParams params, {
  required int maxTokens,
  required bool runsOnCpu,
  required int availableCores,
}) {
  ctxParams.n_ctx = maxTokens;
  ctxParams.n_batch = maxTokens;
  ctxParams.n_ubatch = maxTokens;
  ctxParams.n_seq_max = 1;
  ctxParams.embeddings = true;
  ctxParams.pooling_type = llama_pooling_type.LLAMA_POOLING_TYPE_NONE;
  applyContextThreads(ctxParams, params, availableCores: availableCores);
  if (runsOnCpu) {
    ctxParams.offload_kqv = false;
    ctxParams.op_offload = false;
    ctxParams.flash_attn_typeAsInt =
        llama_flash_attn_type.LLAMA_FLASH_ATTN_TYPE_DISABLED.value;
  }
}
