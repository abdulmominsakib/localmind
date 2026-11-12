# Dedicated native runtime owners

Use `LlamaDartRuntimePool` when an application-authorized flow needs its own
native llama.cpp context. Each handle owns a fresh loaded runtime. The normal
plugin continues sharing one runtime per model name; a Genkit session ID does
not isolate that context.

The [runnable flow example](../example/genkit_llamadart_owner_example.dart) uses
raw text completion. It accepts a local GGUF path:

```bash
dart run example/genkit_llamadart_owner_example.dart
```

```dart
import 'package:genkit_llamadart/genkit_llamadart.dart';

Future<void> main() async {
  final pool = LlamaDartRuntimePool(
    model: const LlamaModelDefinition(name: 'raw', modelPath: '/models/chat.gguf'),
    maxOwners: 1,
  );
  try {
    final owner = await pool.open();
    print(await owner.generate('Once upon a time',
      params: const GenerationParams(maxTokens: 32, temp: 0)));
  } finally {
    await pool.close();
  }
}
```

## Lifecycle and limits

Opening and closing owners count toward `maxOwners`; a full pool fails rather
than evicting somebody else's state or waiting indefinitely. Each owner has a
bounded queue for buffered raw generation, next-token scoring and live LoRA.
Excess queued work fails before native work. Accepted operations drain on explicit close;
new work is rejected immediately. Repeated close calls return the same future.
A failed native cleanup retains admission and remains observable on pool close.
Idle expiry closes only owners with no active or queued work. Choose limits for
your memory budget: shared immutable files do not guarantee shared allocations.

Use Genkit's `CancellationToken` directly, including `context.cancel` inside a
flow. Cancellation before a queued operation starts performs no native work and
leaves the owner usable. Cancellation after native work starts faults the owner;
active work settles and its context is disposed before the request fails.
Pending requests then fail without starting inference. `cancelActiveGeneration()`
targets only that handle's active generation. It does nothing while idle, loading
or scoring. Close does not cancel active generation automatically.

Native failures and cancellation leave no reusable uncertain context. Open a new
owner and replay application-owned committed history. Allocation, native/probe
and disposal diagnostics are neutral; they do not copy native paths or errors.

## Scope and support

| Target | Support |
| --- | --- |
| Native llama.cpp, local `.gguf` | Dedicated raw-prompt generation and scoring, with fresh runtime probes. |
| Web / LiteRT-LM / non-GGUF | Reject before allocation or model access. |
| Custom runtime factory | Must return fresh independent contexts and a supported llama.cpp capability probe; native isolation is the implementer's responsibility. |

Generation buffers its complete result. Apply any desired chat template in
trusted application code; this helper supplies no tools, message history or
standard `ai.generate()` model registration. Scoring probes its capability on
every call. No raw engine is exposed. Authentication, per-user quotas, message
storage, input limits and trace/content policies remain application-owned.
Native observers may receive prompts/results; Genkit flows may trace their
inputs and outputs. Never expose source paths or mutable owner handles as remote
flow inputs. A handle itself is not authorization.

Opt-in [same-process raw-prompt caches](prompt-caches.md) can reuse evaluated KV
after an owner is replaced within the same pool. General checkpoint persistence
remains separate work: see [the checkpoint/LoRA contract](runtime-isolation-design.md).
General chat recovery still requires an evaluated-token/history contract; raw
prompt caches provide no exported KV files, message restoration or exact sampler
continuation.

## Live LoRA

Load-time adapters still use `ModelParams.loras`. To change a compatible adapter
without reloading the base, use an application-owned handle:

```dart
import 'package:genkit_llamadart/genkit_llamadart.dart';

Future<void> updateAdapter(LlamaDartRuntimeOwner owner) async {
  final adapter = ModelSource.path('/models/adapter.gguf');
  await owner.setLoraSource(adapter, scale: 0.5);
  await owner.removeLoraSource(adapter);
  await owner.clearLoras();
}
```

`clearLoras()` clears all adapters, including any load-time configuration.
These operations share the inference queue; they cannot change adapters during
an active generation. Finite scales include zero. A successful mutation clears
native prompt-prefix reuse, so replay committed application history under the
new adapter configuration. The caller selects a compatible ordinary LoRA and
can pin remote bytes with adapter-specific `ModelLoadOptions`; base-model
credentials and checksums are never inherited. Remove using the same source
identity that was applied. Removing an absent adapter follows llamadart's no-op
behavior.

A live support probe runs before source resolution or download. The built-in
runtime requires a loaded native llama.cpp engine; published llamadart 0.11.1
provides these source APIs. Qualification covers native `v0.5.0-2`; arbitrary
native overrides and other devices are unqualified. Custom factories must
implement `LlamaRuntimeLoraProvider` and explicitly probe actual availability.
Web and LiteRT-LM owners reject before allocation; unsupported custom runtimes
reject before adapter loading. Native compatibility/ABI failures also surface as
errors. There is no shared-plugin live mutation or automatic session lookup.

A source, probe or mutation failure closes the uncertain owner before reuse;
its previous adapter configuration is not restored in place. Open a replacement
and replay trusted history/configuration. Other owners keep their own state.
Queued Genkit cancellation skips the mutation. Active cancellation waits for the
operation to settle, then disposes the owner; it cannot interrupt synchronous
native mutation. For prompt download cancellation use the adapter's
`ModelLoadOptions.cancelToken`. Progress callbacks are application-owned and may
contain source details; keep them out of telemetry unless explicitly permitted.

The [live LoRA qualification guide](live-lora-qualification.md) records the
pinned real pair, conversion recipe and opt-in test. Default CI checks routing,
queue ordering, failure/unsupported paths and cancellation without downloading
these weights.

## Real-model qualification

The public pool/owner route is qualified on macOS arm64 CPU with published
llamadart 0.11.1/native `v0.5.0-2`, the checksum-pinned tiny SmolLM2 Q2_K fixture,
512-token context, one generation/batch thread and batch/microbatch 1. The test
runs a real Genkit flow, interleaves independent owner scoring/generation,
checks B's prefix reuse, cancels A after text emits and opens a replacement after
cleanup. This is bounded lifecycle/routing evidence, not other-family, GPU or
other-device qualification. Batch 1 is a control, not a global recommendation.

```bash
LLAMADART_RUN_OWNER_PROOF=1 LLAMADART_AUTO_DOWNLOAD_TEST_MODELS=1 \
dart test test/integration/genkit/runtime/real_model_owner_test.dart -j 1
```

Default CI skips this proof before fixture/cache access. Native paths must be
explicitly enabled; no additional model download is added to ordinary CI.
