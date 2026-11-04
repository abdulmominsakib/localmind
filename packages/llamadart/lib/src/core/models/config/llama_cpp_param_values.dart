import 'flash_attention.dart';
import 'kv_cache_type.dart';

/// Maps llamadart's [KvCacheType] enum to llama.cpp's `ggml_type` value.
int ggmlTypeValueFor(KvCacheType type) {
  return switch (type) {
    KvCacheType.f16 => 1,
    KvCacheType.q4_0 => 2,
    KvCacheType.q8_0 => 8,
  };
}

/// Maps llamadart's [FlashAttention] enum to llama.cpp's flash-attention
/// option value.
int llamaFlashAttentionTypeValueFor(FlashAttention type) {
  return switch (type) {
    FlashAttention.auto => -1,
    FlashAttention.disabled => 0,
    FlashAttention.enabled => 1,
  };
}

/// Resolves the user-requested [FlashAttention] given the requested KV cache
/// types. llama.cpp refuses non-F16 KV without flash attention, so `auto` is
/// auto-promoted to `enabled` when either KV type isn't F16. Explicit `enabled`
/// or `disabled` values pass through unchanged.
FlashAttention resolveFlashAttention({
  required FlashAttention requested,
  required KvCacheType cacheTypeK,
  required KvCacheType cacheTypeV,
}) {
  final wantsKvQuantization =
      cacheTypeK != KvCacheType.f16 || cacheTypeV != KvCacheType.f16;
  if (requested == FlashAttention.auto && wantsKvQuantization) {
    return FlashAttention.enabled;
  }
  return requested;
}
