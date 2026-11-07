// Focused helpers for native model loading and sampler setup. Kept here (vs
// inlined in the service) so they can be unit-tested without going through
// `LlamaEngine.loadModel`, which is integration-level and needs a real model.

import 'dart:ffi';

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
  return resolvedFlashAttn;
}
