# Web media embedding qualification

Tracking: https://github.com/leehack/llamadart/issues/1072 (lane E).

The Dart WebGPU adapter supports API-version-1 media embeddings from bridge
assets v0.1.64+. The default pinned assets include this API. Older or mismatched
assets disable media with a `LlamaUnsupportedException` naming the required assets. A compatible embedding
model and image/audio projector must also be loaded. Probes run against the
current bridge; missing model/projector encoders or pooling report the unavailable
modality, while cancel/dispose/worker failures retain typed inference errors. Text
capability preserves legacy last-token support on pooling NONE. Probes reflect
projector unload/reload and worker restoration.

Use `embedContent` / `embedContentBatch` with ordered text, encoded image/audio
bytes or mono 16 kHz Float32 PCM. Filesystem paths and image URLs are unsupported
in this adapter. No chat template or task prefix is inserted. Text-only content
uses the existing string route, including the older sequential batch fallback.
Image dimensions are ignored: `LlamaImageContent.bytes` always means encoded
image data, never inferred raw RGB. Reserved `<__media__>` text in a mixed input
throws `LlamaUnsupportedException`, matching native.
All requested modalities are checked before dispatch; the bridge validates the
whole batch's shapes, codecs and expanded-token limits before inference.
Caller buffers remain owned by the caller and must stay unchanged until the
future settles. Cancellation forwards to bridge `cancel`; cancelled content
calls discard a late successful bridge result and throw
`LlamaInferenceException`, including text-only content on older assets. Await
the embedding future before reuse: cancellation does not imply immediate
interruption of synchronous WASM compute. Disposal awaits bridge teardown,
which settles active work and prevents a stale successful content result.

## Current evidence and limits

Chrome fake-bridge tests cover capability protocol/version skew, ordered media
mapping, normalized/raw option forwarding, source rejection, payload-free error
classification and cancellation/disposal. These establish Dart wiring only.
Bridge source contract inspected read-only at
`d1c1b9aac0e88b5748ea436e0bc81a0ef6c54876`, including
`tests/bridge/multimodal_embedding_test.mjs`. It covers direct/worker cancellation,
restore and structured-clone ownership; those are bridge responsibilities.

Qualification target: EmbeddingGemma-2 BF16 with its matching
mmproj and pinned assets `v0.1.83` on Chrome CPU wasm memory64
(`gpuLayers: 0`). The scenario below checks the bridge's production worker
budget against references from the matching native `v0.9.0`.
The table below retains the original `v0.1.66` lineage
([PR 1205](https://github.com/leehack/llamadart/pull/1205)); qualification of the
previous `v0.1.79` pin stayed within its gates (minimum cosine 0.99997,
maximum component difference 8.9e-4).

The independent PR audit qualified the same model and projector with the
then-pinned `v0.1.65` assets on Chrome CPU wasm memory64 (`gpuLayers: 0`).
Direct and worker-configured runs returned identical vectors. Those historical
runs did not assert worker retention after each batch, so they establish
CPU/WASM numerical parity rather than sustained worker execution. WebGPU
hardware was not exercised.

| Input | Cosine versus native CPU |
| --- | --- |
| Text | 0.9999946 |
| Image (PNG) | 0.9999893 |
| Audio (WAV) | 0.9999908 |
| Mixed text/image/audio | 0.9999946 |
| Audio (mono 16 kHz PCM) | 0.9999908 |

Maximum absolute component difference was at most 5.33e-4 versus native CPU.
Versus native Metal, cosine was at least 0.9999844 and maximum absolute
difference at most 6.39e-4. All normalized vectors had norm 1.0 and dimension
768. PCM equalled the WAV path; text content equalled legacy `embed`; reversed
batch order preserved vectors exactly. These are numerical compatibility
measurements, not retrieval-quality or GPU-acceleration qualification. Source:
[independent audit of PR 1185](https://github.com/leehack/llamadart/pull/1185).
This revision records the auditor's measurements; it did not rerun weights.

The wasm32 core aborted on a second media batch until assets `v0.1.76+`,
which free the loaded projector GGUF
([llama-web-bridge#200](https://github.com/leehack/llama-web-bridge/pull/200)),
but repeated wasm32 media batches are not yet qualified here
([#1189](https://github.com/leehack/llamadart/issues/1189)).
**Memory64 remains the qualified setup for repeated media batches.** The scenario below adds
consumer model-backed checks for cancellation of a pending worker RPC,
projector reload, CPU worker restoration and capacity rejection. Hardware
WebGPU, device-loss recovery and mobile browser resource limits require
separate device qualification.

## Local reference scenario

This follows the existing `test/e2e/webgpu/generation_features_e2e_test.dart`
local browser asset pattern. Place immutable local artifacts under the ignored
`build/webgpu_embeddings_e2e/` directory; the Dart test server does not serve
external symlinks. Do not overwrite the pinned chat-app assets.

Create `config.json` there with relative paths:

```json
{
  "bridge": "bridge/llama_webgpu_bridge.js",
  "worker": "bridge/llama_webgpu_bridge_worker.js",
  "core": "bridge/llama_webgpu_core.js",
  "wasm": "bridge/llama_webgpu_core.wasm",
  "coreMem64": "bridge/llama_webgpu_core_mem64.js",
  "wasmMem64": "bridge/llama_webgpu_core_mem64.wasm",
  "model": "model.gguf",
  "projector": "mmproj.gguf",
  "image": "image.png",
  "audio": "audio.wav",
  "text": "The Eiffel Tower is in Paris.",
  "normalizedVectors": [],
  "normalizedMetalVectors": []
}
```

Use EmbeddingGemma-2 with its exact matching projector. Supply four full-width
native reference vectors in `normalizedVectors`: text, image, encoded audio,
then `first ` + image + ` between ` + audio + ` last `. Use identical local
media files and the pinned native runtime; record model/projector/media hashes,
bridge manifest/source/upstream commits, native provenance and browser/backend.
Optionally supply four matching native Metal vectors in
`normalizedMetalVectors`; omit that key when no qualified Metal reference is
available. Empty placeholders intentionally fail; no fabricated reference is
supplied. The audio fixture must be mono IEEE float32 WAV at 16 kHz with a
44-byte header and its `data` chunk starting at byte 36. The scenario checks
this format before comparing its payload with the public PCM input route.

As with the existing browser scenario, configure `CHROME_EXECUTABLE` with a
wrapper allowing SharedArrayBuffer for the test server:
`--enable-features=SharedArrayBuffer,SharedArrayBufferUnrestrictedAccessAllowed`.
The scenario uses CPU/WASM (`gpuLayers: 0`), direct and worker paths. Select the
memory64 files through `coreMem64` and `wasmMem64` in `config.json`. The
scenario maps these to the bridge constructor's `coreModuleUrlMem64` and
`wasmUrlMem64` and sets `preferMemory64: true`; the wasm32 `core`/`wasm` keys
alone do not select memory64. It reports `llamadart.webgpu.core_variant` from
runtime metadata and requires `wasm64`, so a wasm32 fallback fails qualification.
The constructor sets no `workerRequestTimeoutMs`, so the scenario runs on the
bridge's production budget, on the pinned assets 10 minutes per input for a
media request ([llama-web-bridge#165](https://github.com/leehack/llama-web-bridge/issues/165)).
It asserts that budget and checks worker presence after each stage, so a
successful direct-runtime fallback cannot count as a worker pass. Earlier assets
moved a batch that took over two minutes to the direct runtime while still
returning valid vectors.

```bash
dart run tool/testing/run_local_e2e.dart --scenario web-multimodal-embeddings --dry-run
dart run tool/testing/run_local_e2e.dart --scenario web-multimodal-embeddings
```

The cosine gate is 0.999 with unit-norm tolerance 1e-5, below the measured
CPU wasm/native minimum above. Any tolerance change needs exact-artifact
evidence. The scenario checks raw/normalized consistency, batch order,
adjacent-text equivalence, WAV/PCM equality, capacity rejection and reuse, and
projector unload/reload. Its worker lane cancels a pending real media RPC and
then verifies reuse. It also terminates the worker and invokes its installed
error handler, exercising actual CPU worker-to-direct restoration of the model,
projector and batch settings. This fault injection does not prove natural
browser error delivery or WebGPU device-loss recovery. Cancellation is
cooperative; the test does not establish interruption at a particular native
kernel instruction. `EMBEDDING_METRIC` records per-input cosine, maximum
component difference, norm and width; `EMBEDDING_VECTORS` permits an exact
direct/worker comparison. Keep model/projector/media hashes, manifest
provenance and native references with each rerun. No hardware WebGPU support
is implied by CPU/WASM results.
