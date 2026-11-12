# Architecture

`genkit_llamadart` is organized as a layered adapter around `llamadart`.

## Layers

### `lib/src/api/`

Public package surface and stable user-facing types.

- `plugin_handle.dart`: `llamaDart`, typed model refs, typed embedder refs
- `model_definition.dart`: static model registration config
- `generation_config.dart`: request-time model options
- `embed_config.dart`: request-time embed options
- `model_preparation.dart`: observable source preparation state and tasks
- `prepared_model.dart`: prepared model ownership and lifecycle helpers
- `runtime_owner.dart`: bounded dedicated native contexts and live LoRA controls

Rules:

- safe to export from `lib/genkit_llamadart.dart`
- configuration and value types should not depend on Genkit action internals
- facade and ownership helpers may construct the Genkit integration plugin
- should stay small, stable, and easy to document

### `lib/src/core/`

Runtime and transport-neutral `llamadart` logic.

- `runtime/`: engine lifecycle and queued runtime access
- `streaming/`: chunk accumulation and stream assembly helpers
- `metadata/`: model capability shaping shared by integrations

Rules:

- should not depend on package public exports
- should avoid Genkit-specific request/response types where possible
- should contain reusable logic if another integration layer is added later

### `lib/src/integration/genkit/`

The Genkit adapter layer.

- plugin registration
- model and embedder actions
- Genkit <-> `llamadart` conversion
- action metadata and raw response shaping

Rules:

- this is the only layer that should know about Genkit action wiring
- request validation that is specific to Genkit belongs here
- it can depend on both `api` and `core`

## Dependency Relationships

Configuration and model-definition types in `api` are the shared dependency
surface for `core` and `integration`. The public facade helpers then construct
the integration plugin so package users do not need to import internal paths.

More concretely:

- `core` must not import `integration`
- `integration` may import API value types and `core`
- API configuration and model-definition files must not import `integration`
- API facade and ownership files may import stable integration entrypoints, but
  must not reach into actions or converters

`lib/genkit_llamadart.dart` re-exports the supported public API without exposing
the internal layout to package consumers.

## Dedicated Runtime Ownership

The runtime registry owns one queued runtime per model name, not per Genkit
session. The [dedicated native owner API](doc/runtime-owners.md) instead allocates
a fresh context outside that registry, with bounded admission and one queue for
generation, scoring and live LoRA changes. Genkit flows may use owner handles
inside trusted application code; session lookup and authorization remain
application-owned. KV checkpoints remain deferred under the
[isolation implementation contract](doc/runtime-isolation-design.md).

## Test Layout

The `test/api/`, `test/core/` and `test/integration/genkit/` trees mirror the
source layers. Test doubles stay in nearby `test_support/` directories, outside
production code. See [CONTRIBUTING.md](CONTRIBUTING.md#testing-conventions) for
test selection and quality expectations.

## Real-Model Smoke Tests

The real-model tests intentionally use tiny GGUF files so they can run in CPU
mode in CI and on low-end developer machines.
Auto-downloaded fixtures use immutable Hugging Face revisions and are verified
by size and SHA-256 before loading, so warm and cold caches exercise identical
model bytes. Downloads are serialized per fixture across test isolates to
protect a shared cold cache. A stale lock fails with a diagnostic instead of
being evicted while its original owner might still be active.

Current defaults:

- chat: `unsloth/SmolLM2-135M-Instruct-GGUF` / `SmolLM2-135M-Instruct-Q2_K.gguf`
- embeddings: `second-state/jina-embeddings-v2-small-en-GGUF` / `jina-embeddings-v2-small-en-Q2_K.gguf`

These are smoke-test models, not quality baselines. They are chosen to validate
loading, generation, and embedding paths cheaply.
