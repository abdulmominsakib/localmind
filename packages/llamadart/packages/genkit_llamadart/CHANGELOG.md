## 3.8.0 - 2026-11-08

- Upgrade to llamadart 0.19.0 and matching 0.19.x Apple companions.

## 3.7.0 - 2026-11-08

- Upgrade to llamadart 0.18.0 and matching 0.18.x Apple companions.

## 3.6.0 - 2026-10-29

- Upgrade to llamadart 0.17.0 and matching 0.17.x Apple companions.
- Structured output parses through `ChatTemplateEngine.parseRendered`, as llamadart's engine parses its final message: after the stock Seed-OSS template, `Plan</seed:think>{...}` is content, as in llama-server, and so is `<think>…</think>{...}` from Qwen3.5 with thinking off, instead of reasoning and the JSON. On a runtime that does not enforce the JSON grammar, such a reply now fails JSON validation with `failedPrecondition` (see the migration guide).

## 3.5.0 - 2026-10-23

- Upgrade to llamadart 0.16.0 and matching 0.16.x Apple companions. Core 0.16 throws `LlamaUnsupportedException` for `ModelParams` fields the selected runtime would ignore, including through `LlamaModelDefinition.modelParams`; see the llamadart migration guide.
- Export `LiteRtLmModelParams` and `LlamaCppModelParams`; examples and docs use them instead of the deprecated `liteRtLm*` arguments of `ModelParams`.
- Round-trip `SpeculativeDecodingConfig.draftMicroBatchSize` through JSON generation controls instead of dropping it.

## 3.4.1 - 2026-10-18

- Move source and guides into the llamadart repository while retaining separate package versions and releases.

## 3.4.0 - 2026-10-18

- Upgrade to llamadart 0.15.0 and matching 0.15.x Apple companions; native overrides must match the v0.7 ABI.
- Add ordered text, image and audio embeddings through Genkit, preserving one vector and metadata per document on compatible GGUF and native LiteRT-LM CPU embedding engines.
- Expose embedding-specific modality probes in inspection and lazy discovery, with optional `LlamaRuntimeEmbeddingProvider` support for custom runtimes; existing custom text embedders retain their interface.
- Add cooperative typed embedding cancellation, snapshot queued inputs to prevent caller-mutation races, and reuse decoded inline media during remote resolution.
- Give runnable examples pinned Hugging Face model defaults and local/HTTPS overrides, simplify telemetry setup, and add a GGUF/LiteRT-LM multimodal embedding example.
- Verify all 22 CLI entry points on macOS arm64 CPU with maintained opt-in tests, compare multimodal embeddings against direct llamadart calls, and correct the LoRA fixture conversion recipe for reproducible checksums.

## 3.3.0 - 2026-10-15

- Add opt-in same-process raw-prompt caches on dedicated native owners, with bounded handles and model-identity checks.
- Add a separate experimental Genkit text-session plugin with isolated runtimes, bounded turns and deterministic cleanup.
- Specify and test intentional reasoning-history omission while preserving streamed/final reasoning output.
- Validate Genkit's standard output schemas locally without a remote draft-07 metadata fetch.
- Preserve richer tool input schemas, including nullable values, enums, composition and length limits, on grammar-capable runtimes.
- Upgrade to llamadart 0.13.0; Flutter Apple apps must use matching 0.13.x runtime companions.

## 3.2.1 - 2026-10-11

- Honor cancelled embedding actions without evaluating queued work or interrupting other requests.
- Complete character and image/audio usage counts while preserving unknown token measurements.
- Add an explicit resource/data normalization example and document reasoning-history policy.

## 3.2.0 - 2026-10-11

- Refresh the pub.dev quickstart and runnable feature examples, including local retrieval with bounded passages and source IDs.
- Keep decision-flow capability failures free of raw native diagnostics and model paths.
- Apply, rescale, remove and clear live LoRA adapters on dedicated native owners without reloading the base model.
- Add bounded application-owned native raw-prompt runtimes with isolated queues, cancellation and cleanup.
- Expose typed Genkit actions for raw next-token probabilities with live capability checks and the shared model queue.
- Combine constrained JSON and tool calls on native llama.cpp, with complete-output validation before streaming or tool dispatch; preserve literal tool markup in final JSON.
- Expose dedicated batch transcription, complete WAV synthesis and PNG generation as native Genkit models with explicit engine ownership and cancellation.
- Add an experimental Laya decision-flow recipe with complete choice, score and yes/no results, schemas and native CPU qualification.
- Support text-only multipart tool results while retaining structured output in Genkit history.
- Resolve native HTTP(S) image and audio input with an explicit, bounded application-owned resolver.
- Inspect loaded model capabilities and context capacity, and count or tokenize raw text without inference.
- Keep media validation errors free of signed URLs, credentials and source paths.
- Preserve null tool parameters and reject schema constraints that the runtime cannot retain.
- Stop optional real-model tests before downloads or inference when their fixture is not enabled.

## 3.1.1 - 2026-10-10

- Make the README quick start runnable with a cached Hugging Face Qwen3.5 download and matching sampling settings.
- Add presence penalties, thinking budgets, speculative decoding and native streaming controls with runtime capability checks.
- Expose generation-control schemas and supported strategies in lazy model discovery.
- Export `ModelFormat` and `LiteRtLmActivationDataType` for public model configuration.

## 3.1.0 - 2026-10-10

- Reject malformed, truncated and disallowed final tool calls before tool execution.
- Add an opt-in OpenTelemetry recipe for queue, initialization, action latency and time to first token.
- Simplify getting-started documentation and expand public API guidance.
- Discover model capabilities from the loaded runtime and reject unsupported requests before inference, with optional capability probes for custom runtimes.

## 3.0.0 - 2026-10-09

- Upgrade to Genkit 1.0, Schemantic 1.0, and llamadart 0.11.1 with updated generation, tool choice, and embedding APIs.
- Replace the deprecated `LiteRtLmBackendPreference` export with `ComputeDevice` for device selection.
- Ship agent skills for setup and generation, model preparation, tool calling,
  and structured JSON output; install them with `dart run skills@ get`.

## 2.0.0 - 2026-09-28

### Breaking changes

- Require Dart 3.12, Genkit 0.17, llamadart 0.9, and Schemantic 0.2.3.
  Applications using older Genkit or Dart versions must upgrade before adopting
  this release.
- Follow Genkit 0.17's tool API: callbacks return `ToolResult.response(value)`.
  Multipart tool-result content is rejected with `UNIMPLEMENTED`; return text
  or structured `output` instead.
- Genkit generation can return `failed` or `aborted` responses. Check
  `finishReason` and `error`/`cause` before consuming output.
  `LlamaPreparedModel.warmUp()` continues to throw on failure or cancellation.

### Observability and cancellation

- Report backend token usage, including cached tokens, for chat and constrained
  JSON responses. Unknown measurements remain absent.
- Preserve backend time to first token and generation duration, and report
  queue, initialization, and total model-action timings.
- Accept engine observers on direct and source-prepared plugins for trace
  correlation, model-load and inference diagnostics. Add a runnable
  observability example that exports OpenTelemetry spans and model metrics
  through `genkit_otel`, with content capture off, plus production
  instrumentation guidance; applications configure their own telemetry
  providers.
- Connect Genkit request cancellation to active inference. Skip cancelled queued
  work before initialization without interrupting another active request.
- Preserve backend token-limit finish reasons for constrained JSON output.

### Maintenance

- Reorganize the README around installation, a quickstart, and task guides,
  and refresh the pub.dev description and topics.
- Update action metadata, tool examples, migration documentation, and the
  Dart 3.12 lower-bound dependency compatibility lane.
- Skip runtime and lower-bound CI for known prose-only pull requests while
  retaining package validation; cancel superseded pull-request runs.
- Automatically tag and publish after an approved release-preparation PR merge,
  with strict lookup failures, tag collision checks, validated polling settings,
  and retry handling that avoids dispatching over an active publisher.

## 1.4.0 - 2026-07-27

- Add compatibility with Genkit `0.15.x` while retaining the `0.13.2` lower
  bound.
- Reject new runtime work once plugin disposal starts and dispose independent
  model runtimes concurrently while preserving every disposal failure.
- Infer media types from URI paths, including signed HTTP(S) image URLs on
  backends that support remote images, and accept Windows drive-letter media
  paths.
- Reject unsupported primitive and list tool-input schemas before advertising a
  mismatched zero-argument tool, while resolving valid reference-wrapped object
  schemas emitted by Genkit.
- Exercise latest-compatible dependencies in the full CI job and lower-bound
  dependencies in a focused compatibility job.
- Run every `real-model`-tagged test in CI and release verification using
  serialized, immutable, SHA-256-verified Hugging Face fixtures without
  stealing stale cache locks.
- Correct source and agent example behavior, and refresh lifecycle, capability,
  architecture, testing, and advanced configuration documentation.

## 1.3.3 - 2026-06-10

- Widen the Genkit and Schemantic dependency constraints to allow `genkit` `0.14.x` while keeping compatibility with `0.13.x`.
- Raise the `llamadart` dependency floor to `0.8.0` so the package depends on the Dart-only top-level `llamadart` package metadata.
- Remove the unnecessary Flutter SDK environment constraint from the package metadata.
- Document `llamadart` Flutter Apple SwiftPM companion packages for iOS and macOS apps.

## 1.3.2 - 2026-06-07

- Add explicit pub.dev platform metadata for Android, iOS, Linux, macOS, web, and Windows so the package listing reflects the cross-platform support inherited from `llamadart`.

## 1.3.1 - 2026-06-06

- Update the `llamadart` dependency constraint to `^0.7.1` so Genkit models can use `.litertlm` LiteRT-LM bundles on supported `llamadart` targets.
- Re-export LiteRT-LM and advanced `ModelParams` option enums from the top-level package API.
- Clarify README and API docs that model paths are not GGUF-only, and that this release resolves through the Flutter SDK required by hosted `llamadart`.

## 1.3.0 - 2026-06-04

- Add plugin and prepared-model APIs for cancelling active `llamadart` generations without holding the underlying `LlamaEngine`.

## 1.2.0 - 2026-05-25

- Add source-backed model preparation with `ModelSource`, package-managed cache/download options, optional mmproj resolution, and typed prepared-model refs.
- Add observable model preparation tasks with progress snapshots, cache-hit states, failure reporting, and cancellation.
- Add prepared-model `createGenkit`, warm-up, and ownership-aware disposal helpers.
- Document direct GenUI and `genkit_shelf` integration paths for prepared local models.

## 1.1.1

- Update the Genkit dependency constraint to `^0.13.2` and verify compatibility with `llamadart` `0.6.14`.

## 1.1.0

- Expand README with installation, lifecycle, embeddings, JSON output, and multimodal guidance
- Add standalone embedding and constrained JSON example programs
- Add explicit `ai.shutdown()` cleanup to example apps
- Add per-model capability flags for embeddings, tools, and constrained output
- Harden streamed tool-call accumulation and raw response metadata
- Add CI and failure-path coverage for plugin, runtime, model, and embedder behavior
- Reorganize source into api, core, and Genkit integration layers
- Mirror the test tree to the source layout with one test per file
- Add optional Hugging Face-backed real-model smoke tests for generation and embeddings
- Add architecture and contributing guides for maintainers and contributors
- Cache downloaded real-model GGUF artifacts in CI

## 1.0.0

- Add an in-process Genkit plugin backed by `llamadart`
- Support local path-based chat generation, streaming, embeddings, and tool loops
- Add example apps for basic generation and a multi-turn agent workflow
- Add tests for converters, runtime queueing, embeddings, and Genkit tool loops
- Add pub.dev-ready package metadata and MIT license
