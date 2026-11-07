import 'package:llamadart/src/core/models/config/flash_attention.dart';
import 'package:llamadart/src/core/models/config/kv_cache_type.dart';
import 'package:llamadart/src/core/models/config/llama_cpp_param_values.dart';
import 'package:test/test.dart';

void main() {
  group('ggmlTypeValueFor', () {
    test('maps supported KV cache types to ggml_type values', () {
      expect(ggmlTypeValueFor(KvCacheType.f16), 1);
      expect(ggmlTypeValueFor(KvCacheType.q4_0), 2);
      expect(ggmlTypeValueFor(KvCacheType.q8_0), 8);
    });
  });

  group('llamaFlashAttentionTypeValueFor', () {
    test('maps flash-attention options to llama.cpp values', () {
      expect(llamaFlashAttentionTypeValueFor(FlashAttention.auto), -1);
      expect(llamaFlashAttentionTypeValueFor(FlashAttention.disabled), 0);
      expect(llamaFlashAttentionTypeValueFor(FlashAttention.enabled), 1);
    });
  });

  group('resolveFlashAttention', () {
    test('keeps auto when both KV caches are F16', () {
      expect(
        resolveFlashAttention(
          requested: FlashAttention.auto,
          cacheTypeK: KvCacheType.f16,
          cacheTypeV: KvCacheType.f16,
        ),
        FlashAttention.auto,
      );
    });

    test('promotes auto when either KV cache is quantized', () {
      expect(
        resolveFlashAttention(
          requested: FlashAttention.auto,
          cacheTypeK: KvCacheType.q8_0,
          cacheTypeV: KvCacheType.f16,
        ),
        FlashAttention.enabled,
      );
      expect(
        resolveFlashAttention(
          requested: FlashAttention.auto,
          cacheTypeK: KvCacheType.f16,
          cacheTypeV: KvCacheType.q4_0,
        ),
        FlashAttention.enabled,
      );
    });

    test('passes explicit options through unchanged', () {
      for (final k in KvCacheType.values) {
        for (final v in KvCacheType.values) {
          expect(
            resolveFlashAttention(
              requested: FlashAttention.enabled,
              cacheTypeK: k,
              cacheTypeV: v,
            ),
            FlashAttention.enabled,
          );
          expect(
            resolveFlashAttention(
              requested: FlashAttention.disabled,
              cacheTypeK: k,
              cacheTypeV: v,
            ),
            FlashAttention.disabled,
          );
        }
      }
    });
  });
}
