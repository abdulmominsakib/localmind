@TestOn('vm')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/load_param_helpers.dart';
import 'package:llamadart/src/core/models/config/flash_attention.dart';
import 'package:llamadart/src/core/models/config/kv_cache_type.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:test/test.dart';

void main() {
  group('ggmlTypeFor', () {
    test('f16 → GGML_TYPE_F16', () {
      expect(ggmlTypeFor(KvCacheType.f16), ggml_type.GGML_TYPE_F16);
    });

    test('q8_0 → GGML_TYPE_Q8_0', () {
      expect(ggmlTypeFor(KvCacheType.q8_0), ggml_type.GGML_TYPE_Q8_0);
    });

    test('q4_0 → GGML_TYPE_Q4_0', () {
      expect(ggmlTypeFor(KvCacheType.q4_0), ggml_type.GGML_TYPE_Q4_0);
    });
  });

  group('resolveFlashAttention', () {
    test('auto + F16/F16 → auto (no promotion needed)', () {
      expect(
        resolveFlashAttention(
          requested: FlashAttention.auto,
          cacheTypeK: KvCacheType.f16,
          cacheTypeV: KvCacheType.f16,
        ),
        FlashAttention.auto,
      );
    });

    test('auto + Q8_0 K → enabled (auto-promote)', () {
      expect(
        resolveFlashAttention(
          requested: FlashAttention.auto,
          cacheTypeK: KvCacheType.q8_0,
          cacheTypeV: KvCacheType.f16,
        ),
        FlashAttention.enabled,
      );
    });

    test('auto + Q4_0 V → enabled (auto-promote)', () {
      expect(
        resolveFlashAttention(
          requested: FlashAttention.auto,
          cacheTypeK: KvCacheType.f16,
          cacheTypeV: KvCacheType.q4_0,
        ),
        FlashAttention.enabled,
      );
    });

    test('auto + Q8_0 K/V → enabled (auto-promote)', () {
      expect(
        resolveFlashAttention(
          requested: FlashAttention.auto,
          cacheTypeK: KvCacheType.q8_0,
          cacheTypeV: KvCacheType.q8_0,
        ),
        FlashAttention.enabled,
      );
    });

    test('explicit enabled passes through unchanged regardless of KV', () {
      for (final k in KvCacheType.values) {
        for (final v in KvCacheType.values) {
          expect(
            resolveFlashAttention(
              requested: FlashAttention.enabled,
              cacheTypeK: k,
              cacheTypeV: v,
            ),
            FlashAttention.enabled,
            reason: 'enabled should stay enabled for k=$k v=$v',
          );
        }
      }
    });

    test(
      'explicit disabled passes through unchanged for F16 (no promotion)',
      () {
        // The disabled+non-F16 combination is rejected by ModelParams's
        // constructor; this helper isn't responsible for that validation.
        // For F16/F16, disabled is legal and should pass through.
        expect(
          resolveFlashAttention(
            requested: FlashAttention.disabled,
            cacheTypeK: KvCacheType.f16,
            cacheTypeV: KvCacheType.f16,
          ),
          FlashAttention.disabled,
        );
      },
    );
  });

  group('applyModelParams', () {
    test('maps mmap and mlock combinations to llama.cpp load modes', () {
      final cases = <({bool useMmap, bool useMlock, llama_load_mode expected})>[
        (
          useMmap: false,
          useMlock: false,
          expected: llama_load_mode.LLAMA_LOAD_MODE_NONE,
        ),
        (
          useMmap: true,
          useMlock: false,
          expected: llama_load_mode.LLAMA_LOAD_MODE_MMAP,
        ),
        (
          useMmap: false,
          useMlock: true,
          expected: llama_load_mode.LLAMA_LOAD_MODE_MLOCK,
        ),
        (
          useMmap: true,
          useMlock: true,
          expected: llama_load_mode.LLAMA_LOAD_MODE_MMAP_MLOCK,
        ),
      ];

      for (final testCase in cases) {
        final m = calloc<llama_model_params>();
        try {
          applyModelParams(
            m.ref,
            ModelParams(useMmap: testCase.useMmap, useMlock: testCase.useMlock),
          );
          expect(m.ref.load_mode, testCase.expected);
        } finally {
          calloc.free(m);
        }
      }
    });

    test('default ModelParams selects mmap load mode', () {
      final m = calloc<llama_model_params>();
      try {
        applyModelParams(m.ref, ModelParams());
        expect(m.ref.load_mode, llama_load_mode.LLAMA_LOAD_MODE_MMAP);
        expect(m.ref.load_mtp, isFalse);
      } finally {
        calloc.free(m);
      }
    });

    test('maps the bundled MTP loading opt-in', () {
      final m = calloc<llama_model_params>();
      try {
        applyModelParams(m.ref, const ModelParams(loadMtp: true));
        expect(m.ref.load_mtp, isTrue);
      } finally {
        calloc.free(m);
      }
    });
  });

  group('createSuppressTokensSampler', () {
    test('returns nullptr for an empty token list', () {
      expect(createSuppressTokensSampler(4, const []), nullptr);
    });

    test('sets model-suppressed token logits to negative infinity', () {
      final sampler = createSuppressTokensSampler(4, const [1, 3]);
      expect(sampler, isNot(nullptr));

      final candidates = calloc<llama_token_data>(4);
      final candidateArray = calloc<llama_token_data_array>();
      try {
        for (int i = 0; i < 4; i++) {
          candidates[i]
            ..id = i
            ..logit = i.toDouble()
            ..p = 0;
        }
        candidateArray.ref
          ..data = candidates
          ..size = 4
          ..selected = -1
          ..sorted = false;

        llama_sampler_apply(sampler, candidateArray);

        expect(candidates[0].logit, 0);
        expect(candidates[1].logit, double.negativeInfinity);
        expect(candidates[2].logit, 2);
        expect(candidates[3].logit, double.negativeInfinity);
      } finally {
        calloc.free(candidateArray);
        calloc.free(candidates);
        llama_sampler_free(sampler);
      }
    });
  });

  group('readModelSuppressTokens', () {
    test('copies metadata once into an immutable Dart list', () {
      final nativeTokens = calloc<llama_token>(2);
      addTearDown(() => calloc.free(nativeTokens));
      nativeTokens[0] = 1;
      nativeTokens[1] = 3;
      var calls = 0;

      final tokens = readModelSuppressTokens(
        nullptr,
        getSuppressTokens: (_, countPointer) {
          calls++;
          countPointer.value = 2;
          return nativeTokens;
        },
      );

      nativeTokens[0] = 2;
      expect(calls, 1);
      expect(tokens, const <int>[1, 3]);
      expect(() => tokens.add(4), throwsUnsupportedError);
    });

    test('returns the shared empty list when metadata is absent', () {
      final tokens = readModelSuppressTokens(
        nullptr,
        getSuppressTokens: (_, countPointer) {
          countPointer.value = 0;
          return nullptr;
        },
      );

      expect(tokens, isEmpty);
      expect(() => tokens.add(1), throwsUnsupportedError);
    });
  });

  group('applyContextParams', () {
    test('writes type_k/type_v from cacheTypeK/V', () {
      final c = calloc<llama_context_params>();
      try {
        applyContextParams(
          c.ref,
          ModelParams(
            cacheTypeK: KvCacheType.q8_0,
            cacheTypeV: KvCacheType.q4_0,
            flashAttention: FlashAttention.enabled,
          ),
        );
        expect(c.ref.type_kAsInt, ggml_type.GGML_TYPE_Q8_0.value);
        expect(c.ref.type_vAsInt, ggml_type.GGML_TYPE_Q4_0.value);
      } finally {
        calloc.free(c);
      }
    });

    test('explicit FA enabled writes ENABLED', () {
      final c = calloc<llama_context_params>();
      try {
        applyContextParams(
          c.ref,
          ModelParams(flashAttention: FlashAttention.enabled),
        );
        expect(
          c.ref.flash_attn_typeAsInt,
          llama_flash_attn_type.LLAMA_FLASH_ATTN_TYPE_ENABLED.value,
        );
      } finally {
        calloc.free(c);
      }
    });

    test('explicit FA disabled (with F16 KV) writes DISABLED', () {
      final c = calloc<llama_context_params>();
      try {
        applyContextParams(
          c.ref,
          ModelParams(flashAttention: FlashAttention.disabled),
        );
        expect(
          c.ref.flash_attn_typeAsInt,
          llama_flash_attn_type.LLAMA_FLASH_ATTN_TYPE_DISABLED.value,
        );
      } finally {
        calloc.free(c);
      }
    });

    test('FA auto + Q8 KV auto-promotes to ENABLED in the struct', () {
      final c = calloc<llama_context_params>();
      try {
        final resolved = applyContextParams(
          c.ref,
          ModelParams(
            cacheTypeK: KvCacheType.q8_0,
            cacheTypeV: KvCacheType.q8_0,
          ),
        );
        expect(resolved, FlashAttention.enabled);
        expect(
          c.ref.flash_attn_typeAsInt,
          llama_flash_attn_type.LLAMA_FLASH_ATTN_TYPE_ENABLED.value,
        );
      } finally {
        calloc.free(c);
      }
    });

    test('null kvUnified leaves struct field unchanged', () {
      final c = calloc<llama_context_params>();
      try {
        c.ref.kv_unified = false;
        applyContextParams(c.ref, ModelParams());
        expect(c.ref.kv_unified, isFalse);
      } finally {
        calloc.free(c);
      }
    });

    test('non-null kvUnified writes the value', () {
      final c = calloc<llama_context_params>();
      try {
        applyContextParams(c.ref, ModelParams(kvUnified: true));
        expect(c.ref.kv_unified, isTrue);
      } finally {
        calloc.free(c);
      }
    });

    test('null ropeFrequencyBase / Scale leaves struct fields unchanged', () {
      final c = calloc<llama_context_params>();
      try {
        c.ref.rope_freq_base = 12345.0;
        c.ref.rope_freq_scale = 0.5; // fp32-exact value
        applyContextParams(c.ref, ModelParams());
        expect(c.ref.rope_freq_base, 12345.0);
        expect(c.ref.rope_freq_scale, 0.5);
      } finally {
        calloc.free(c);
      }
    });

    test('non-null rope frequencies write through', () {
      final c = calloc<llama_context_params>();
      try {
        applyContextParams(
          c.ref,
          ModelParams(
            ropeFrequencyBase: 500000.0,
            ropeFrequencyScale: 0.25, // fp32-exact value
          ),
        );
        expect(c.ref.rope_freq_base, 500000.0);
        expect(c.ref.rope_freq_scale, 0.25);
      } finally {
        calloc.free(c);
      }
    });

    test('returns the resolved FlashAttention value', () {
      final c = calloc<llama_context_params>();
      try {
        expect(
          applyContextParams(
            c.ref,
            ModelParams(flashAttention: FlashAttention.enabled),
          ),
          FlashAttention.enabled,
        );
      } finally {
        calloc.free(c);
      }
    });
  });
}
