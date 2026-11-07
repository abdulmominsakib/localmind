/// KV-cache data type for `llama_context_params.type_k` / `type_v`.
/// q8_0 ≈ 0.5× the KV memory of f16; q4_0 ≈ 0.25×. Both require flash
/// attention to be enabled (see [FlashAttention]).
enum KvCacheType {
  /// fp16 (default).
  f16,

  /// 8-bit quantized.
  q8_0,

  /// 4-bit quantized.
  q4_0,
}
