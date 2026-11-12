# Isolated state and LoRA: implementation contract

This contract guides [#36](https://github.com/leehack/genkit-llamadart/issues/36)
and [#46](https://github.com/leehack/genkit-llamadart/issues/46).
[Dedicated native owners](runtime-owners.md) now provide bounded raw generation,
scoring, cancellation and cleanup. Live ordinary LoRA updates also use these owners, with
[a pinned native pair qualification](live-lora-qualification.md). The bounded
first slice for #36 is now an opt-in [same-process raw-prompt cache](prompt-caches.md),
with same-pool identity, bounded in-memory handles and no exported state files.
The persistent/general-chat checkpoint requirements below remain deferred.
Applications can already configure load-time adapters through
`ModelParams.loras`; shared plugin runtimes expose no live adapter mutation.

## Why a separate owner is required

The [registry](../lib/src/core/runtime/engine_registry.dart) creates one runtime
per registered model name and serializes all its operations. A queue prevents
simultaneous use; it does not prevent persistent mutations from affecting the
next user's request. A Genkit session stores application state and messages,
not ownership of a native context. A different session ID therefore cannot
isolate either KV state or LoRA on the existing model action.

Use a dedicated runtime per application-authorized session. It must never be
an entry in the shared model registry, appear as an ordinary reusable model
name, or be returned to a pool with its context still loaded. Different owners
may use the same immutable weight files, but must have distinct engines and
backend contexts. Do not expose the mutable engine to callers. Start with native
llama.cpp; memory costs and admission limits must be explicit. Do not promise
shared loaded weights or inexpensive sessions.

Genkit can host a typed provider action/flow for this owner without changing
standard `generate` parameters. The application authenticates and authorizes
session access; a caller-supplied session ID is never authorization. Names and
public owner handles remain within trusted application code.

## Ordering and lifecycle

Each owner has one queue for initialization, inference, scoring, checkpointing,
restore and adapter changes. Capability checks happen inside it before file
access or adapter downloads. Cancellation of an active generation bypasses the
queue, targets only that owner's engine, and unregisters when the operation
settles. Queued cancellation must skip initialization and side effects.

| State | Contract |
| --- | --- |
| Opening | Allocate a fresh engine, verify identity and capabilities; dispose failed initialization. |
| Ready / running | Execute one accepted operation at a time. Only settled, validated operations may become checkpoints. |
| Faulted | Reject queued inference and mutations; dispose the uncertain engine. Recovery constructs a new engine and restores only a verified checkpoint, or re-evaluates committed history. |
| Closing / closed | Reject new operations, drain accepted work, then dispose exactly once. Closing is terminal and idempotent. |

Explicit close drains work; applications cancel active inference separately
before close when needed. Bound active sessions, queued work and idle lifetime;
expiration follows the same close contract. Do not kill a worker and report
successful cleanup while native work may still be running.

Cancellation is not rollback. If generation aborts, preserve the last committed
conversation, mark its live KV state unusable for checkpoints and re-evaluate
that conversation before reuse. A save cancelled after writing its temporary
file must not publish a manifest. Restore or adapter failure after a native call
may have changed the context: fault and rebuild instead of returning it to use.
Report cancellation or the sanitized operation error only after resources settle.

## Checkpoints and conversation consistency

A checkpoint binds one opaque state blob to an application-owned manifest:

- a format version and immutable checkpoint ID;
- SHA-256 identities for weights and any projector/adapters, adapter order and
  scales, and the template/tokenizer identity;
- exact llamadart version, native artifact/build identity, backend/platform and
  effective context configuration, including measured capacity;
- committed message-history revision, exact rendered prompt/token sequence and
  token count, plus the state blob's size and checksum.

Unknown build identity disables restore; a backend display name or a local
filename is insufficient. Reject incompatible manifests before loading state.
Loading restores KV only: restore messages separately, validate their revision
and template-derived tokens, then compare the returned token sequence with the
manifest. Never infer messages from token IDs. Save with tokens that actually
produced the KV state, not a guessed re-tokenization of displayed text. The
same adapter identity is required before restore; changing its scale creates
a different checkpoint identity.

The adapter currently exposes text/completion chunks and usage counts, not an
authoritative ledger of evaluated tokens, hidden template tokens, truncation,
context shifts and the final sampled token's decode status. Consequently,
**post-generation chat checkpoints cannot be implemented by concatenating
history and tokenizing it**. Multimodal, speculative and shifted contexts need
separate proof. A message store remains the recovery source of truth.

The first executable proof should be a text-only raw-prompt checkpoint immediately
after successful prompt evaluation (for example, next-token scoring), with no
sampling or context shift. Match the backend's special-token/BOS policy exactly;
the public raw token helper defaults alone do not establish that match. Compare
restored scoring and deterministic continuation against a fresh evaluation.
Only then choose either a narrowly documented prompt-checkpoint API or an
upstream evaluated-token snapshot contract for chat checkpoints. This proof does
not establish exact continuation of a sampler/RNG from a saved conversation.

Storage remains application-owned: pass an opaque storage handle to the action,
resolve native paths in trusted application code, and never accept arbitrary
client paths. Write a unique temporary blob, verify success/size/checksum, then
publish the manifest last using the storage provider's atomic commit contract.
Keep the prior checkpoint valid on failure and clean incomplete files. Use a
single writer or explicit revision checks; concurrent processes must not overwrite
the same checkpoint. Applications control retention, deletion, access and
encryption. Treat both messages and opaque KV bytes as sensitive data.

## Live adapter changes

Use `setLoraSource`, `removeLoraSource` and `clearLoras`, preserving source-specific
download/checksum/progress/cancellation behavior. Do not use deprecated path
setters or forward the base model's credentials/checksum to another source.
Validate finite scales, compatible base identities and immutable adapter bytes.

Adapters are session-scoped for this first slice. A model-wide update to the
shared plugin would change every user's behavior and is outside scope. Apply,
scale change, removal and clear all run between inference operations. Keep a
committed adapter configuration; advance it only after the native mutation and
cache invalidation succeed. No best-effort reset in a `finally` block can prove
that a shared runtime has been restored.

Published native code clears its prompt-prefix token cache on successful LoRA
changes. Still invalidate the owner's checkpoints and re-evaluate committed
history with the new adapter configuration. Never restore an old-adapter KV
blob into a new-adapter context. On uncertain failure, rebuild with the previous
committed adapters and replay history; if recovery fails, remain faulted.

## Backend and privacy boundaries

| Target | First implementation contract |
| --- | --- |
| Native llama.cpp | Require ready runtime and state support; qualify the exact model/build and compatible ordinary LoRA pair. Unsupported aLoRA/ABI paths remain explicit errors. |
| WebGPU | Deferred. State methods require a live bridge probe (`v0.1.15+`); LoRA requires all methods and a supported API-version-1 probe (`v0.1.54+`). Tags alone do not prove availability, independent contexts or durable browser storage. |
| LiteRT-LM | Reject state and live LoRA before file access/download. The published APIs do not provide these operations. |
| Custom/unknown runtime | Reject without an explicit isolation and capability contract; implementing method names alone is insufficient. |

Future Web support must qualify direct/worker calls, independent bridge instances,
version skew, cache invalidation and application-owned durable export/import.
Virtual filesystem paths do not establish survival across reloads.

Telemetry may report operation, outcome, queue duration and neutral backend
labels. Keep paths, source URLs, authentication, token IDs, state bytes, messages
and adapter manifests out of spans, discovery, raw responses and errors. Genkit
telemetry can capture action inputs: keep those inputs to opaque handles and
follow the application's [telemetry policy](observability.md).

## Acceptance before implementation is called ready

1. Real native sessions A/B use distinct engines/contexts. Interleave scoring,
   inference, save/restore and cancellation; A's state and cancellation never
   affect B. Include close/reopen and failed initialization/restore.
2. Save/load/resume on an exact model/build matches fresh evaluation with the
   same prompt/settings. Demonstrate cache reuse as well as output parity;
   output equality alone could hide full re-evaluation.
3. Deterministic negative tests cover identity/adapter/history mismatches,
   corrupt/truncated files, capacity limits, unknown build, expired ownership,
   queued cancellation, partial native mutation, save commit failure and cleanup.
4. A compatible real base/LoRA pair qualifies apply, scale change, remove and
   clear, restored baseline and interleaved B. Verify prefix caches cannot reuse
   tokens evaluated with the old adapters. Record exact model/adapter checksums,
   artifact/build, device/backend and sanitized logs. A fake is not this proof.
5. Negative runtime tests cover LiteRT, old/custom Web bridges and capability
   probe/version failures before downloads. Verify redaction through Genkit.
6. Independent QA checks the exact implementation head, production queue wiring,
   positive/negative isolation tests and model evidence. Update public Dartdoc,
   support docs and changelog only for behavior actually delivered.

## Current upstream restore contract

[llamadart #1003](https://github.com/leehack/llamadart/issues/1003) is closed with
an explicit numerical-tolerance contract, reflected in the published
[llamadart 0.13 state API](https://github.com/leehack/llamadart/blob/v0.13.0/lib/src/core/engine/engine.dart).
Restore is KV-only; logits are recovered by re-evaluating the final token, and
automatic batching can change greedy continuation. This allows a scoped
raw-prompt cache design for #36 to proceed with that limitation. It does not
supply the evaluated-token/history ledger required for general chat checkpoints,
or preserve sampler/RNG state. The fixed-batch proof below remains a historical
qualification control, not a reason to change default batching.

## Bounded native checkpoint proof

The opt-in [native proof](../test/integration/genkit/runtime/real_model_isolation_test.dart)
uses application-owned `LlamaEngine` instances, outside the shared plugin registry.
It qualifies the prerequisite on macOS arm64 CPU with published llamadart 0.11.1
and native artifact `v0.5.0-2` (llama.cpp `7fe450e19305b828c199d602c23a8337aaa1f03b`).
It verifies the pinned tiny SmolLM2 model's size and SHA-256 before loading.

Run the narrow configuration:

```bash
LLAMADART_RUN_ISOLATION_PROOF=1 LLAMADART_AUTO_DOWNLOAD_TEST_MODELS=1 \
dart test -t isolation-model -j 1
```

| Check | Qualified result |
| --- | --- |
| Separate A/B contexts | Interleaved A scoring/save/restore leaves B's counters and cached-prefix continuation intact. |
| Raw-prompt state | A saves immediately after scoring; restore returns the same special-token-aware 12-token prompt sequence. |
| Reuse and parity | Restore reuses 11 tokens, re-evaluates the final token for logits, and matches fresh scoring and eight-token greedy continuation. |
| Lifecycle and cancellation | Close/reopen preserves restore/reuse; cancelling A after both streams emit leaves B's output and cancellation outcome unchanged. |
| Failed restore | Insufficient token capacity and corrupt files reject; uncertain engines are disposed rather than reused. |

**This result requires `batchSize: 1` and `microBatchSize: 1`**, a 512-token
context and one CPU thread for generation and batching. It is a qualification
control, not a performance recommendation or a general session implementation.
Default CI skips the proof before fixture/cache access unless explicitly enabled.

Automatic batching fails the score/continuation parity assertions on this exact
model/runtime. To reproduce that qualification failure, use the same command
with `LLAMADART_ISOLATION_BATCH_SIZE=0`. Direct llama.cpp C calls on the published
library reproduce the score changes exactly; see
[llamadart #1003](https://github.com/leehack/llamadart/issues/1003) for the native
control and provenance. Single-token batches eliminate the observed difference.
This does not identify a specific kernel or prove a corrupt state file.

The new public raw-prompt cache proof is documented in [the cache guide](prompt-caches.md);
it qualifies the current 0.13 native owner path separately from this historical proof.
Broader chat checkpoints, sampler/RNG continuation, message-history recovery,
model/build/adapter identity enforcement and transactional checkpoint storage
remain unimplemented. Bounded native owners expose
no public state files or chat recovery. GPU, Web, other native
platforms and model families are unqualified. Live-LoRA qualification is recorded separately in
[the native pair guide](live-lora-qualification.md); it makes no checkpoint
continuation claim. Cross-process persistence remains beyond the same-process cache slice.

## Source evidence

Inspected adapter main `270be2071e307bc67c76c95c5bccd927947345c3` and the published
llamadart 0.11.1 sources:

- [Registry queue and lifetime](../lib/src/core/runtime/engine_registry.dart),
  [runtime contract](../lib/src/core/runtime/llama_runtime.dart) and
  [engine wrapper](../lib/src/core/runtime/llama_engine_runtime.dart).
- [State and source-based LoRA engine APIs](https://github.com/leehack/llamadart/blob/v0.11.1/lib/src/core/engine/engine.dart): state files are model/build-tied; LiteRT LoRA rejects before download.
- [Native save/load and LoRA implementation](https://github.com/leehack/llamadart/blob/v0.11.1/lib/src/backends/llama_cpp/llama_cpp_service.dart): load rebuilds cached prompt tokens; LoRA clears them on success. Active adapter maps change before native application succeeds, so failures are not transactional.
- [Web LoRA probes](https://github.com/leehack/llamadart/blob/v0.11.1/lib/src/backends/webgpu/webgpu_lora.dart) and [Web state probes](https://github.com/leehack/llamadart/blob/v0.11.1/lib/src/backends/webgpu/webgpu_backend.dart).
