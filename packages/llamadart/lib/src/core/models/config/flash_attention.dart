/// Selects llama.cpp's `flash_attn_type`. Required when [KvCacheType] is
/// not [KvCacheType.f16] — llama.cpp refuses non-F16 KV cache without it.
enum FlashAttention {
  /// Let llama.cpp pick.
  auto,

  /// Force on.
  enabled,

  /// Force off.
  disabled,
}
