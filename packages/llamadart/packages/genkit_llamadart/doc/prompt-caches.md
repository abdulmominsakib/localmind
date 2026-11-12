# Same-process native raw-prompt caches

`LlamaDartRuntimeOwner.cachePrompt` evaluates a raw prompt afresh and returns an
opaque `LlamaDartPromptCache`. `generateFromCache` restores it and generates from
that original prompt in one serialized operation. Enable the feature explicitly
on the [dedicated runtime pool](runtime-owners.md):

```dart
import 'package:genkit_llamadart/genkit_llamadart.dart';

Future<String> cachedCompletion(String modelPath, String prompt) async {
  final pool = LlamaDartRuntimePool(
    model: LlamaModelDefinition(name: 'raw', modelPath: modelPath),
    enablePromptCache: true,
    maxOwners: 1,
    maxPromptCaches: 1,
    maxPromptCacheBytes: 64 * 1024 * 1024,
  );
  try {
    final first = await pool.open();
    final cache = await first.cachePrompt(prompt);
    await first.close();
    final replacement = await pool.open();
    return await replacement.generateFromCache(cache,
      params: const GenerationParams(maxTokens: 32, temp: 0));
  } finally {
    await pool.close();
  }
}
```

## Identity and ownership

Handles belong to one pool and process lifetime. Different pools cannot exchange
them, even with the same file path. They cannot be serialized, exported or
accepted as remote client input. Default native runtimes in the same process use
the same loaded native build; each owner verifies the GGUF SHA-256 before/after
loading and before save/restore. Keep model files immutable for the whole loaded
lifetime. Context parameters are fixed by the pool. No user-supplied compatibility
label substitutes for those checks.

Only default native llama.cpp runtimes with state persistence and scoring are
supported. Web, LiteRT-LM, custom factories, projectors and load-time adapters
reject. Any live adapter mutation permanently disables cache operations on that
owner, including after clearing the adapters. A fresh base-model owner in the
same pool can still use a base cache. Other owners' state is independent.

The cache contains only a freshly evaluated, special-token-aware **raw prompt**.
No sampled generation, context shift, speculative tokens or multimodal inputs
are included. Returned restore tokens must exactly match the evaluated prompt
tokens before generation. `generateFromCache` requires prefix reuse and rejects
speculation. This does not provide general chat checkpoints, a message store or
sampler/RNG continuation; the [broader persistence contract](runtime-isolation-design.md)
remains separate work.

## Storage, budgets and cancellation

Sensitive KV bytes and the raw prompt are retained in memory behind the handle.
Native file APIs use a unique temporary directory, deleted before an operation
returns or publishes a handle. File paths are never public API inputs or outputs.
There is no persistent manifest, cross-process restore or disk-storage promise.
OS-level termination can leave temporary files; the application controls its
process/temp-storage policy and encryption requirements.

`maxPromptCaches` counts retained and in-progress saves. `maxPromptCacheBytes`
bounds retained native state blobs across the pool. It excludes native context
allocations, temporary files and references held by an active operation after a
handle is disposed. The state-file size is checked before reading it into memory;
the pool quota is checked again immediately before publishing a handle. Dispose
unused handles; pool close disposes all of them after owner cleanup settles,
even if cleanup reports a failure. Disposing a handle does not cancel a restore
already in progress.

Queued cancellation skips work. Active cancellation waits for evaluation/file
cleanup to settle, publishes no new handle and closes the uncertain owner.
Native, identity, quota and restore failures also close that owner; valid handles
and other owners are unchanged. Native state errors are sanitized. Keep raw
prompts, cache bytes, model paths and token IDs out of application telemetry.

## Qualified behavior

The native proof uses published llamadart 0.13.0/native `v0.6.0-3`, macOS arm64 CPU,
the checksum-pinned SmolLM2-135M Q2_K fixture, a 512-token context, one CPU thread
and batch/microbatch 1. It verifies actual cached-token reuse after owner close
and replacement, fresh-output parity under that control, independent owners,
cancelled work, quotas, foreign/disposed handles and terminal cleanup.

The same bounded proof passed again on 2026-10-18 with published llamadart
0.15.0/native `v0.7.0-1` on macOS arm64 CPU. This retains the original fixture
and scope; it does not extend qualification to other devices or backends.

Native restore re-evaluates the final token for logits. Automatic batching is a
numerical-tolerance contract and can change greedy output. Batch 1 is a test
control, not a performance recommendation. Cache reuse is demonstrated; no
end-to-end speedup is claimed, especially given model hashing and state-copy
costs. GPU, other platforms and other model families are unqualified.

```bash
LLAMADART_RUN_PROMPT_CACHE_PROOF=1 LLAMADART_AUTO_DOWNLOAD_TEST_MODELS=1 \
dart test test/integration/genkit/runtime/real_model_prompt_cache_test.dart -j 1
dart run example/genkit_llamadart_prompt_cache_example.dart
```
