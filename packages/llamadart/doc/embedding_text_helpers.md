# Text embedding profiles and qualification

Tracking: https://github.com/leehack/llamadart/issues/1126.
Ownership: [Dart integration](../website/docs/maintainers/runtime-ownership.md).

`LlamaTextEmbedder` wraps an existing engine without changing `LlamaEngine` or
backend signatures. It does not own the engine. The default `raw` profile
accepts prepared text only, delegates normalization unchanged and forbids
model-specific dimension reduction. Existing content and string calls remain
unchanged.

The explicit `embeddingGemma2` profile is a caller assertion, not model
authentication. A 768-wide arbitrary model is not thereby MRL-compatible.
There is no filename guessing, registry, media policy or runtime pin change.
Query tasks follow the [official prompt configuration](https://huggingface.co/google/embeddinggemma-2/blob/914f7f89142e33e77833254d9c9b90c3cef7303b/config_sentence_transformers.json).
Documents use `title: {title or none} | text: {content}`. Prepared text is
always verbatim; choose it for instructions already supplied by the caller.
The helper has no media input and inserts no instructions into media calls.

EG2 requests raw 768-wide vectors from the engine, validates every component
including discarded ones, keeps 768/512/256/128 leading components, then L2
normalizes if requested. Scaling before summing squares avoids overflow and
underflow. A zero retained vector throws `LlamaInferenceException` when
normalizing; with normalization off it returns finite zeros. Invalid dimensions,
raw/profile combinations or source width throw `LlamaUnsupportedException`.
Batch preflight validates every formatting request before inference; malformed
output returns no partial vectors. Underlying cancellation/errors propagate.

## Reproduce official CPU retrieval comparison

The local-only `text-embedding-retrieval` scenario compares production single
and batch helper calls with independent SentenceTransformers inference over
the checked-in four-query/four-document corpus. It checks normalized vector
cosine above 0.999, score error below 0.01 and matching relevant top-1 at all
four dimensions. These are explicit numerical budgets, not a benchmark claim.
Unprefixed query output must differ, while prepared and explicit task output
must agree. Queries and corpus use the same profile and dimension.

Use an isolated Python environment, then download exact public artifacts:

```sh
uv venv /tmp/eg2-reference-venv
uv pip install --python /tmp/eg2-reference-venv/bin/python \
  torch==2.14.1 transformers==5.20.2 sentence-transformers==6.2.0 \
  pillow torchvision torchaudio
hf download google/embeddinggemma-2 \
  --revision 914f7f89142e33e77833254d9c9b90c3cef7303b \
  --local-dir /tmp/eg2-official
hf download ggml-org/embeddinggemma-2-GGUF embeddinggemma-2-BF16.gguf \
  --revision bfcd298762cc34d0357ece5ebdd31791a3a374d8 \
  --local-dir /tmp/eg2-gguf
/tmp/eg2-reference-venv/bin/python \
  test/e2e/backends/embeddinggemma2_retrieval_reference.py \
  --model-dir /tmp/eg2-official --output /tmp/eg2-reference.json
export LLAMADART_EMBEDDINGGEMMA2_MODEL_PATH=/tmp/eg2-gguf/embeddinggemma-2-BF16.gguf
export LLAMADART_EG2_RETRIEVAL_REFERENCE=/tmp/eg2-reference.json
dart run tool/testing/run_local_e2e.dart --scenario text-embedding-retrieval --dry-run
TMPDIR="$(mktemp -d)" dart run tool/testing/run_local_e2e.dart --scenario text-embedding-retrieval
```

Reference Safetensors SHA-256:
`197a32965d4b1105faf060417baa899e193fb73cd401f42ec9295234d5553d79`.
BF16 GGUF SHA-256:
`68bae29d62fb8c7d23e98d21fd4662753ddd636e6b62b8a70dfe059a9844f216`.
Reference execution is CPU float32 with optional media encoders omitted,
following Google's precision advice. JSON records reference model/revision,
weights and corpus hashes, dtype and library versions. The Dart test verifies
the corpus hash and reports cosine, score error and ranking at each dimension.
Runtime identity comes from the hook-prepared native pin; record its manifest
and library hash with the PR evidence.

The macOS arm64 CPU run on native `v0.7.0-2` (llama.cpp
`620d2225cc436ab0b001e3200e590e3b286ef9ab`) produced:

| Dimensions | Minimum vector cosine | Maximum retrieval score error | Relevant top-1 |
| --- | --- | --- | --- |
| 768 | 0.999994335 | 0.000656542 | 4/4 |
| 512 | 0.999994595 | 0.000652083 | 4/4 |
| 256 | 0.999994534 | 0.000625224 | 4/4 |
| 128 | 0.999995505 | 0.000581787 | 4/4 |

Consumed `libllamadart.dylib` SHA-256:
`8228fd6066d70d3d0a4c22798aac669d2acd520b841d091ed480ac721b1292b4`.
The test checks both checkpoint/GGUF hashes, records the reference corpus hash,
and allows 1e-6 component variation between single/batch CPU accumulation.

This corpus qualifies the text helper on the tested BF16 CPU path only.
It makes no inference about quantized artifacts, LiteRT bundles, GPU, Web,
media retrieval or other models. Those need independent artifact/model evidence.
128 dimensions particularly reduces multimodal quality according to the
[official model card](https://huggingface.co/google/embeddinggemma-2#best-practices).
