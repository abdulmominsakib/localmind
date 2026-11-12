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

  group('llama_load_mode binding', () {
    test('keeps upstream automatic load mode signed and available', () {
      expect(
        llama_load_mode.fromValue(-1),
        llama_load_mode.LLAMA_LOAD_MODE_AUTO,
      );
      expect(llama_load_mode.LLAMA_LOAD_MODE_AUTO.value, -1);
    });
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

  group('speculativeDraftContextParams', () {
    late Pointer<llama_context_params> target;
    late Pointer<llama_context_params> scratch;

    setUp(() {
      target = calloc<llama_context_params>();
      target.ref
        ..n_ctx = 2048
        ..n_batch = 512
        ..n_ubatch = 256
        ..n_seq_max = 1;
      scratch = calloc<llama_context_params>();
    });

    tearDown(() {
      calloc.free(target);
      calloc.free(scratch);
    });

    test('returns the target params unchanged when unset', () {
      final draft = speculativeDraftContextParams(target.ref, null, scratch);

      expect(draft.n_ubatch, 256);
      expect(draft.n_batch, 512);
      expect(scratch.ref.n_ubatch, 0, reason: 'nothing is copied');
    });

    test('copies the target params with the draft micro-batch size', () {
      final draft = speculativeDraftContextParams(target.ref, 32, scratch);

      expect(draft.n_ubatch, 32);
      expect(draft.n_batch, 512);
      expect(draft.n_ctx, 2048);
      expect(draft.n_seq_max, 1);
      expect(target.ref.n_ubatch, 256, reason: 'the target keeps its own');
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
    test('matches the native per-sequence output context ABI', () {
      final defaults = llama_context_default_params();

      expect(defaults.n_outputs_max, 0);
      expect(defaults.n_outputs_max_per_seq, 1);
    });

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

  group('applyDecisionContextParams', () {
    Pointer<llama_context_params> gpuDefaults() {
      final c = calloc<llama_context_params>();
      c.ref.offload_kqv = true;
      c.ref.op_offload = true;
      c.ref.flash_attn_typeAsInt =
          llama_flash_attn_type.LLAMA_FLASH_ATTN_TYPE_AUTO.value;
      c.ref.pooling_typeAsInt =
          llama_pooling_type.LLAMA_POOLING_TYPE_MEAN.value;
      c.ref.n_threads = 3;
      c.ref.n_threads_batch = 3;
      return c;
    }

    test('sizes one sequence per ubatch with unpooled embeddings', () {
      final c = gpuDefaults();
      try {
        applyDecisionContextParams(
          c.ref,
          const ModelParams(numberOfThreads: 2, numberOfThreadsBatch: 6),
          maxTokens: 512,
          runsOnCpu: false,
          availableCores: 16,
        );
        expect(
          [c.ref.n_ctx, c.ref.n_batch, c.ref.n_ubatch, c.ref.n_seq_max],
          [512, 512, 512, 1],
        );
        expect(c.ref.embeddings, isTrue);
        expect(
          c.ref.pooling_typeAsInt,
          llama_pooling_type.LLAMA_POOLING_TYPE_NONE.value,
        );
        expect([c.ref.n_threads, c.ref.n_threads_batch], [2, 6]);
      } finally {
        calloc.free(c);
      }
    });

    test('caps automatic threads at the available cores', () {
      final c = gpuDefaults();
      try {
        applyDecisionContextParams(
          c.ref,
          const ModelParams(numberOfThreads: 0, numberOfThreadsBatch: 0),
          maxTokens: 64,
          runsOnCpu: false,
          availableCores: 2,
        );
        expect([c.ref.n_threads, c.ref.n_threads_batch], [2, 2]);
      } finally {
        calloc.free(c);
      }
    });

    test('keeps offload on a GPU model', () {
      final c = gpuDefaults();
      try {
        applyDecisionContextParams(
          c.ref,
          const ModelParams(),
          maxTokens: 512,
          runsOnCpu: false,
          availableCores: 16,
        );
        expect(c.ref.offload_kqv, isTrue);
        expect(c.ref.op_offload, isTrue);
        expect(
          c.ref.flash_attn_typeAsInt,
          llama_flash_attn_type.LLAMA_FLASH_ATTN_TYPE_AUTO.value,
        );
      } finally {
        calloc.free(c);
      }
    });

    test('disables offload and flash attention on the CPU', () {
      final c = gpuDefaults();
      try {
        applyDecisionContextParams(
          c.ref,
          const ModelParams(),
          maxTokens: 512,
          runsOnCpu: true,
          availableCores: 16,
        );
        expect(c.ref.offload_kqv, isFalse);
        expect(c.ref.op_offload, isFalse);
        expect(
          c.ref.flash_attn_typeAsInt,
          llama_flash_attn_type.LLAMA_FLASH_ATTN_TYPE_DISABLED.value,
        );
      } finally {
        calloc.free(c);
      }
    });
  });

  group('stateContextConfigDigest', () {
    String digestWith(void Function(llama_context_params params) change) {
      final c = calloc<llama_context_params>();
      try {
        c.ref = llama_context_default_params();
        change(c.ref);
        return stateContextConfigDigest(c.ref);
      } finally {
        calloc.free(c);
      }
    }

    final base = digestWith((_) {});

    test('is a stable SHA-256 hex digest', () {
      expect(base, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(digestWith((_) {}), base);
    });

    test('changes with every state-layout setting', () {
      final changes = <String, void Function(llama_context_params)>{
        'type_k': (p) => p.type_k = ggml_type.GGML_TYPE_Q8_0,
        'type_v': (p) => p.type_v = ggml_type.GGML_TYPE_Q4_0,
        'flash_attn': (p) => p.flash_attn_type =
            p.flash_attn_type ==
                llama_flash_attn_type.LLAMA_FLASH_ATTN_TYPE_DISABLED
            ? llama_flash_attn_type.LLAMA_FLASH_ATTN_TYPE_ENABLED
            : llama_flash_attn_type.LLAMA_FLASH_ATTN_TYPE_DISABLED,
        'n_seq_max': (p) => p.n_seq_max = p.n_seq_max + 1,
        'kv_unified': (p) => p.kv_unified = !p.kv_unified,
        'swa_full': (p) => p.swa_full = !p.swa_full,
        'rope_freq_base': (p) => p.rope_freq_base = 1000,
        'rope_freq_scale': (p) => p.rope_freq_scale = 0.5,
      };
      final digests = <String>{base};
      for (final MapEntry(:key, :value) in changes.entries) {
        final digest = digestWith(value);
        expect(digest, isNot(base), reason: key);
        digests.add(digest);
      }
      expect(digests, hasLength(changes.length + 1));
    });

    test('pins the version 2 encoding and its digest', () {
      final c = calloc<llama_context_params>();
      try {
        c.ref = llama_context_default_params();
        c.ref
          ..type_k = ggml_type.GGML_TYPE_F16
          ..type_v = ggml_type.GGML_TYPE_Q8_0
          ..flash_attn_type =
              llama_flash_attn_type.LLAMA_FLASH_ATTN_TYPE_ENABLED
          ..n_seq_max = 2
          ..kv_unified = true
          ..swa_full = false
          ..rope_freq_base = 10000
          ..rope_freq_scale = 0.25;
        const encoding =
            'llamadart-state-context/2;type_k=GGML_TYPE_F16;'
            'type_v=GGML_TYPE_Q8_0;flash_attn=LLAMA_FLASH_ATTN_TYPE_ENABLED;'
            'n_seq_max=2;kv_unified=true;swa_full=false;'
            'rope_freq_base=10000.0;rope_freq_scale=0.25';
        expect(stateContextConfigEncoding(c.ref), encoding);
        expect(
          stateContextConfigDigest(c.ref),
          '0a3035d07e11d509527c587268e60af51b99d35c026d8a7392ab558dd5435a9a',
        );
      } finally {
        calloc.free(c);
      }
    });

    test('ignores context size, batch, threads and offload', () {
      expect(
        digestWith(
          (p) => p
            ..n_ctx = 4096
            ..n_batch = 7
            ..n_ubatch = 3
            ..n_threads = 5
            ..n_threads_batch = 6
            ..offload_kqv = !p.offload_kqv
            ..op_offload = !p.op_offload,
        ),
        base,
      );
    });
  });

  group('resolveCpuThreads', () {
    test('caps an automatic count at the available cores', () {
      for (final (cores, threads) in const [
        (1, 1),
        (2, 2),
        (3, 3),
        (4, 4),
        (5, 4),
        (128, 4),
      ]) {
        expect(
          resolveCpuThreads(0, availableCores: cores),
          threads,
          reason: '$cores cores',
        );
      }
    });

    test('treats a negative count as automatic, as ggml does', () {
      expect(resolveCpuThreads(-1, availableCores: 2), 2);
      expect(resolveCpuThreads(-1, availableCores: 16), 4);
    });

    test('never changes an explicit count', () {
      for (final cores in const [1, 2, 3, 4, 128]) {
        for (final threads in const [1, 2, 4, 5, 64]) {
          expect(resolveCpuThreads(threads, availableCores: cores), threads);
        }
      }
    });

    test('uses one thread when the core count is unavailable', () {
      expect(resolveCpuThreads(0, availableCores: -1), 1);
      expect(resolveCpuThreads(0, availableCores: 0), 1);
    });
  });

  group('applyContextThreads', () {
    test('resolves the generation and batch counts independently', () {
      final c = calloc<llama_context_params>();
      try {
        applyContextThreads(
          c.ref,
          const ModelParams(numberOfThreads: 6),
          availableCores: 2,
        );
        expect([c.ref.n_threads, c.ref.n_threads_batch], [6, 2]);

        applyContextThreads(
          c.ref,
          const ModelParams(numberOfThreadsBatch: 6),
          availableCores: 3,
        );
        expect([c.ref.n_threads, c.ref.n_threads_batch], [3, 6]);
      } finally {
        calloc.free(c);
      }
    });
  });
}
