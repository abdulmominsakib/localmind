# LiteRT-LM multimodal embeddings

Tracking: https://github.com/leehack/llamadart/issues/1072.
Contract: [Multimodal embeddings](multimodal_embeddings.md).

## Shipped boundary

`LiteRtLmModelParams(embeddingEngine: true, device: ComputeDevice.cpu)` selects
LiteRT-LM's separate native embedding engine. The default false preserves
conversation loading. Both string and content embedding APIs use this engine;
generation and tokenizer APIs reject embedding mode. GGUF loaders still reject
the LiteRT-LM-only flag. A context cannot change its model's selected engine.

The capability probe checks the actual bundle's text-encoder/embedder and
vision/audio encoder/adapter sections, the complete optional embedding C ABI
for the selected runtime, and successful processor creation. Unknown or unloaded contexts return
all-false without runtime I/O. Native CPU is qualified on macOS arm64 and iOS
arm64 (iPhone 16 Pro and the arm64 simulator). Android arm64 is verified on a
Galaxy S24 (Snapdragon 8 Gen 3, no SVE/SME) and on arm64 emulators with and
without SME, with vectors bit-identical to the iPhone run; other Android devices
are not individually verified. Linux x64 and arm64 and Windows x64 are
qualified on litert-lm-native `v0.19.1-1`, which links LiteRT into
`libLiteRtLm` ([litert-lm-native#112](https://github.com/leehack/litert-lm-native/pull/112)).
Native GPU/NPU, Android x86_64 and all Web embeddings remain unsupported. Synthetic media establishes wiring, not
retrieval quality. Other devices and embedding families were not qualified.

Inputs preserve order and merge adjacent text verbatim. Accepted media are
PNG/JPEG bytes, mono 16 kHz Float32 PCM samples, and mono 16 kHz PCM16/Float32 WAV
bytes. Paths, image URLs, video, multiple sources, malformed media and other
codecs are rejected before inference. All media in the batch is decoded during
Dart preflight in a helper isolate, keeping the caller responsive. The native
worker owns copied inputs and copies complete pooled vectors before freeing
responses. Embedding requests queue on the worker's active-request chain.
Native inference
runs one item at a time, checking cancellation after every item and before
returning any vectors. Unload/dispose requests cancel queued and active embeds
and await the current item before freeing the engine. Timeouts cancel only their
own request and throw `LlamaInferenceException`; other queued callers retain their
own deadlines. A queued request whose deadline expires never enters inference.
No partial output is exposed. Native dispatch uses the single-input C API so
cancellation can settle between items; there is no native batch-API path.

The amended contract still requires whole-batch modalities, part shapes and
media-source/decoding validation before inference. llama.cpp additionally
validates actual expanded capacities before any decode. LiteRT-LM has no
expanded-token count API: it selects `kError` rather than truncation or chunk
averaging, and a runtime overflow fails the whole call with
`LlamaInferenceException` and no vectors. Earlier batch items may waste compute.
The E2E includes a valid input followed by an overflowing input and verifies
that no partial result is returned and the engine remains reusable.

## Embedding load options

`contextSize` selects the encoder signature through the upstream maximum-input-length
setting; it is not a token truncation limit. Available signatures depend on the
bundle, so a small value may select a larger supported signature. Overflow still
fails the whole call. `numberOfThreads`, `liteRtLmCacheDir`, and native CPU device
selection are applied. Explicit LoRA, chat templates, activation type, prefill chunk
size, parallel section loading, dispatch library directory, program cache limits,
MTP/rollback settings and Web memory hints are rejected with
`LlamaUnsupportedException` naming the option and embedding mode before model I/O.

The [upstream input constructor](https://github.com/google-ai-edge/LiteRT-LM/blob/b2f686e2ed4718fb84ec398a61dd59ca0f0aff27/c/engine.cc#L119-L145)
copies encoded image bytes; it does not validate their contents. PNG/JPEG headers
and container structure alone cannot establish that compressed pixel data decodes.
The core `image: ^4.11.1` dependency (4.11.0 calls an `archive` API newer than its declared constraint) retains full decoding in a helper isolate to
honor whole-batch validation before inference, without fetching or executing a
native processor on the caller isolate.

## Exact qualification

Model: [`litert-community/embeddinggemma-2-740m-litert-lm`](https://huggingface.co/litert-community/embeddinggemma-2-740m-litert-lm),
revision `24d962e906c7d332c6428e71c9676855024569e2`, file
`embeddinggemma-2-740m.litertlm` (484,622,336 bytes). SHA-256:
`e7a8a2204b91e0f96e92960e84a09a89212e1633dcb7575a9bf3378b4df77f4c`.

### Historical v0.18 comparison

Native: hook-prepared `v0.18.1-2` (upstream LiteRT-LM `v0.18.1`, with the
XNNPACK PF32 SME2 kernels of `v0.18.0-2` restored and its int4 `pqs8_qc4w` SME2 path
gated off), macOS arm64 (M4 Max, SME2)
CPU, both processors on CPU, max input length 1024. No model download is
involved. All six normalized native CPU vectors have width 768 and match the
standalone upstream C API reference with cosine 1.0 and relative L2 0.0. Ten
embeddings of each of the six inputs on one engine are bit-identical (the
`repeated CPU embeddings` test); `v0.18.1` made audio vectors nondeterministic
([litert-lm-native#82](https://github.com/leehack/litert-lm-native/issues/82),
[#1340](https://github.com/leehack/llamadart/issues/1340)). Tests also cover
raw/normalized direction, media sensitivity, reverse batch order, string/content
and adjacent-text parity, overflow, cancellation/reuse and engine separation.

Image, audio and mixed vectors still differ from those of `v0.18.0-2`; text is
unchanged. The cause of the remaining shift in all `v0.18.1` builds is not
attributed ([litert-lm-native#82](https://github.com/leehack/litert-lm-native/issues/82)).
Versus core `0.16.0` (`v0.18.1`) image and audio vectors shift slightly (cosine
about 0.997-0.999), so re-embed stored media vectors before comparing them.

| Input | v0.18.1-2 vs v0.18.0-2 cosine | Relative L2 |
| --- | ---: | ---: |
| `hello world` | 1.0000000000 | 0% |
| Black PNG | 0.9983847075 | 5.68% |
| Checkerboard PNG | 0.9988759362 | 4.74% |
| One-second 16 kHz silence | 0.9998176891 | 1.91% |
| One-second 440 Hz tone | 0.9996702551 | 2.57% |
| Interleaved text/image/audio | 0.9988463550 | 4.80% |

### Final v0.19 CPU preservation

At historical release head `a47e6ff2`, three maintained tests passed through the
public default-discovery engine with published v0.19.0 on macOS arm64 CPU and
the same model bytes. They produced six finite normalized vectors of width 768,
checked 60 repeat calls for exact numeric equality, and covered media/interleaved
inputs, batch order and limits, whole-call overflow failure, cancellation,
unload/dispose/reuse and chat-engine separation. This was no fresh standalone
C-reference comparison; the historical numbers above remain unchanged. It does
not establish retrieval quality, raw bit-pattern identity, another model family,
GPU support or additional platforms. Generative image/audio chat is a separate
qualification path. Final release integration evidence must be renewed at the
final head; publication remains subject to approval.

### Historical Web comparison

Web: Chrome 155.0.8059.40, headless with `--enable-unsafe-webgpu --use-angle=metal`
and the test runner's GPU-disable flags removed. `navigator.gpu.requestAdapter()`
returned an adapter with vendor `apple`, architecture `metal-3` before engine
creation. Pinned `@litert-lm/core@0.18.0` created the embedding engine, including
CPU vision/audio processors, using **`Backend.GPU=4`**, not conversation's
`GPU_ARTISAN=2`. Raw/normalized direction, media sensitivity, reverse batch and
adjacent-text checks passed in the prototype, but the required native parity
gate failed for every input. That integration was removed; the durable local-only
Web qualification test calls the upstream package directly.

| Input | WebGPU vs `v0.18.0-2` native CPU cosine | Relative L2 |
| --- | ---: | ---: |
| `hello world` | 0.9981586925 | 6.06845% |
| Black PNG | 0.9983765510 | 5.69816% |
| Checkerboard PNG | 0.9984849584 | 5.50462% |
| One-second 16 kHz silence | 0.9980172148 | 6.29728% |
| One-second 440 Hz tone | 0.9980797340 | 6.19720% |
| Interleaved text/image/audio | 0.9977802770 | 6.66291% |

The gate is cosine **>= 0.9998** and relative L2 **< 2% per input**. Web stays
unsupported. These observations do not establish the cause of the numerical gap.

### Web comparison on `@litert-lm/core@0.19.0`

Chrome 157.0.8103.38 on macOS arm64 (M4 Max), same flags and adapter (`apple`,
`metal-3`), the same `Backend.GPU=4` engine with CPU vision/audio processors,
against native CPU vectors regenerated with native `v0.19.0` (identical to the
v0.19 preservation reference). The gate still fails for every input; audio is
further from native than on `0.18.0`:

| Input | WebGPU vs `v0.19.0` native CPU cosine | Relative L2 |
| --- | ---: | ---: |
| `hello world` | 0.9981415258 | 6.09668% |
| Black PNG | 0.9985068591 | 5.46469% |
| Checkerboard PNG | 0.9981208848 | 6.13044% |
| One-second 16 kHz silence | 0.9952921358 | 9.70347% |
| One-second 440 Hz tone | 0.9965292499 | 8.33156% |
| Interleaved text/image/audio | 0.9973914612 | 7.22293% |

`Backend.CPU=3` engine creation still fails with the same `Failed to get
external weight for buffer id 2147483863 (tensor 1451)`.

## Unsupported paths and upstream gaps

- **Android x86_64:** fails at load, before any native call, whichever runtime
  library is loaded; it is unqualified. Requalify a platform before adding it
  to `liteRtLmNativeEmbeddingsQualifiedForAbi`.
- **Linux and Windows runtimes older than `v0.19.1-1`:** their `libLiteRtLm`
  was built with libstdc++ or the MSVC STL but linked the prebuilt libc++
  `libLiteRt`, so LiteRT-LM's external-weight handoff was not ABI-valid.
  EmbeddingGemma 2 engine creation fails with `Failed to open tflite_weights`
  on Linux and crashes the process on Windows x64
  ([#1367](https://github.com/leehack/llamadart/issues/1367),
  [litert-lm-native#111](https://github.com/leehack/litert-lm-native/issues/111)).
  C API 1.0 runtimes `v0.19.0` and `v0.19.1` look the same as `v0.19.1-1`, so
  Linux and Windows embeddings require
  `litert_lm_native_in_process_litert_abi_version` to report 1, first shipped
  in `v0.19.1-2`. Any other runtime, including `v0.18.x` and `v0.19.1-1`, is
  refused with `LlamaUnsupportedException` before any native embedding call.
- **Native GPU:** fail before native engine creation. `v0.18.0-3` has a
  WebGPU accelerator/absl ABI mismatch that crashed the upstream-only reference
  as well as the prototype. The upstream repair is
  [LiteRT dd3db31236](https://github.com/google-ai-edge/LiteRT/commit/dd3db31236).
  `v0.18.1-2` built `libLiteRtLm` with it but shipped the same prebuilt macOS
  WebGPU accelerator, and EmbeddingGemma 2 still crashed on GPU there. No later
  runtime has been requalified on GPU; no unsafe accelerator call or silent CPU
  fallback is made. NPU embeddings are unqualified.
- **Web CPU host weights:** fail before I/O. The pinned source streams text-encoder
  weights only for WebGPU ([upstream lines 794–818](https://github.com/google-ai-edge/LiteRT-LM/blob/b2f686e2ed4718fb84ec398a61dd59ca0f0aff27/runtime/core/embedding_engine_impl.cc#L794-L818)).
  The upstream-only CPU creation error is `Failed to get external weight for
  buffer id 2147483863 (tensor 1451)`.
- **WebGPU:** fail before I/O because the tables above miss the parity gate.
  No modality is advertised, including text, despite successful vector production.
- **Token-count API:** the [C API](https://github.com/google-ai-edge/LiteRT-LM/blob/b2f686e2ed4718fb84ec398a61dd59ca0f0aff27/c/embedding_engine.h)
  and pinned Web API expose compute but no embedding token-count preflight.
  A future API could avoid wasted work in
  [the sequential upstream batch loop](https://github.com/google-ai-edge/LiteRT-LM/blob/b2f686e2ed4718fb84ec398a61dd59ca0f0aff27/runtime/core/embedding_engine_impl.cc#L1639-L1676).

These follow-ups remain under the embedding tracker above. Runtime releases
belong to their [owners](../website/docs/maintainers/runtime-ownership.md);
consumption follows [native/Web sync](../website/docs/maintainers/native-and-web-sync.md).
Task-prefix/Matryoshka policy remains separate under
https://github.com/leehack/llamadart/issues/1126.

## Local-only reproduction

Use `.flutter-version` and a dedicated `TMPDIR` outside the checkout; every
native model-loading suite calls `useSuiteSystemTemp()`. Keep weights read-only.
The matrix row is `litert-lm-multimodal-embedding`.

```bash
dart run tool/testing/run_local_e2e.dart --list
dart run tool/testing/run_local_e2e.dart --scenario litert-lm-multimodal-embedding --model-path /path/model.litertlm --backend cpu --dry-run
dart run tool/testing/run_local_e2e.dart --scenario litert-lm-multimodal-embedding --model-path /path/model.litertlm --backend cpu
```

To retain native vectors and exact synthetic input bytes for a C reference:

```bash
LITERT_LM_EMBEDDING_MODEL=/path/model.litertlm LITERT_LM_EMBEDDING_OUTPUT="$TMPDIR/qualification" dart test -p vm --run-skipped test/e2e/backends/multimodal_embedding_litert_e2e_test.dart
```

The historical v0.18.1-2 C-reference comparison used the command below
(macOS arm64). A new runtime comparison needs its matching runtime directory;
the v0.19 preservation campaign did not rerun this reference:


```bash
python3 test/e2e/backends/multimodal_embedding_litert_reference.py --model-path /path/model.litertlm --runtime-dir .dart_tool/llamadart/litert_lm/0.18.1-2/macos/arm64 --output "$TMPDIR/qualification"
```

Serve the existing weights with Range and CORS on a free port other than 8080:

```bash
python3 test/e2e/backends/multimodal_embedding_litert_server.py --model-path /path/model.litertlm --output "$TMPDIR/qualification" --port 5197
```

In another terminal use a task-local `CHROME_EXECUTABLE` wrapper which removes
`--disable-gpu` and `--disable-software-rasterizer` and adds
`--enable-unsafe-webgpu --use-angle=metal`. Then:

```bash
dart test -p chrome --run-skipped test/e2e/backends/multimodal_embedding_litert_web_e2e_test.dart
```

This diagnostic is expected to fail the parity gate on the pinned package and
must stay local-only. It persists every vector before asserting thresholds.
