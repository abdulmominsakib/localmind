# Contributing

Thanks for improving `genkit_llamadart`.

## Local Setup

```bash
dart pub get
```

Make sure the native `llamadart` prerequisites for your platform are installed.
For runtime setup and platform notes, see https://llamadart.leehack.com/.

## Project Layout

See [ARCHITECTURE.md](ARCHITECTURE.md) for package layering and the matching
test layout. End-user guides live under `doc/`; README is the pub.dev entrypoint.

## Code and Documentation

- Keep ordinary code comments for non-obvious constraints, compatibility or
  safety decisions. Avoid narrating assignments, loops or assertions.
- Write Dartdoc for every exported API, including constructors, fields, enum
  values and methods. Explain defaults, ownership, accepted inputs, errors and
  platform differences when they matter; do not repeat the signature.
- Keep README focused on installation, the first successful request, feature
  requirements and navigation. Put detailed guidance under `doc/` and runnable
  examples under `example/`.
- Use absolute HTTPS links in README, CHANGELOG and the example index so
  navigation works when pub.dev renders them. In-page anchors can stay local.
- Update affected package skills with public API changes. Compile documentation
  examples and run `dart doc --dry-run` before claiming docs are ready.

## Testing Conventions

- mirror `lib/src/` under `test/`
- keep each test file focused on one behavior or a tightly related lifecycle
- group related cases when they benefit from shared setup
- place shared helpers in a nearby `test_support/` directory
- prefer unit tests first, then Genkit integration tests, then real-model smoke tests
- Test an observable contract or a plausible failure: conversion, request
  routing, unsupported input, resource ownership, cancellation or telemetry.
  A test should fail if that behavior is removed or miswired.
- Lifecycle changes cover failed initialization, failed disposal and both failing
  together. An uncertain native context retains admission and cannot be reused;
  a later no-op disposal must not erase the original cleanup failure.
- Do not test constructor field assignments or Dart's static type system.
  Remove duplicate tests when the same assertion is covered through a stronger
  production path; preserve that assertion in the retained test.
- Keep tiny real-model tests for native integration, parsing and measurements
  that fakes cannot establish. Share assertions with existing model sessions
  instead of repeatedly loading a model just to assert nonempty output.
- Use coverage to find untested risks, not as a reason to add execution-only
  tests. Test unsupported/version-skew branches when the feature depends on
  runtime capabilities.

## Agent Skills

`skills/` is published to consumers' coding agents. A public API or behavior
change updates the affected `SKILL.md` in the same PR;
`test/tooling/package_documentation_test.dart` validates skill metadata and analyzes Dart
examples from README, guides, example READMEs and skills in one analyzer run.

## Test Commands

Work from `packages/genkit_llamadart` in the llamadart repository. The adapter
resolves dependencies independently: root preparation and analysis exclude it.
CI runs its published-dependency, checkout-core, browser and Dart 3.12 lower-bound
lanes when the adapter, core or shared tooling changes. Ordinary native CI uses
only the pinned tiny SmolLM2 chat and Jina embedding fixtures. Additional model
families, media, LoRA and owner proofs remain opt-in and can use existing local
fixtures.

Release prep changes only this package's `pubspec.yaml` and `CHANGELOG.md`, on
`release/genkit_llamadart-vX.Y.Z` or with `release-prep:genkit_llamadart`.
Tags use `genkit_llamadart-vX.Y.Z`; core and Apple companion release numbers do
not follow this package. See the
[maintainer migration procedure](https://github.com/leehack/llamadart/blob/main/website/docs/maintainers/genkit-package.md)
for the owner-controlled publisher handoff and verification checklist.

```bash
python3 .github/check_docs.py
dart test test/tooling/package_documentation_test.dart
```

Fast local checks:

```bash
dart format --output=none --set-exit-if-changed .
dart analyze
dart test -x real-model
```

Real-model smoke tests with auto-download:

```bash
LLAMADART_AUTO_DOWNLOAD_TEST_MODELS=1 \
dart test -t real-model -j 1
```

Real-model smoke tests with local files:

```bash
LLAMADART_INTEGRATION_MODEL_PATH=/models/tiny-chat.gguf \
LLAMADART_INTEGRATION_EMBED_MODEL_PATH=/models/tiny-embed.gguf \
dart test -t real-model -j 1
```

Optional environment variables for smoke tests:

- `LLAMADART_AUTO_DOWNLOAD_TEST_MODELS=1`: download the default tiny models automatically
- `LLAMADART_TEST_MODEL_DIR`: override the local GGUF cache directory
- `HUGGING_FACE_HUB_TOKEN`: optional token for authenticated or rate-limited Hugging Face access

Auto-downloaded smoke-test models are cached under
`.dart_tool/llamadart_test_models` by default.

Optional native LiteRT media qualification uses a locally supplied multimodal
bundle and fixtures; it does not download a large model in default CI:

```bash
LLAMADART_INTEGRATION_LITERT_MODEL_PATH=/models/gemma-4-E2B-it.litertlm \
LLAMADART_INTEGRATION_LITERT_IMAGE_PATH=/fixtures/image.png \
LLAMADART_INTEGRATION_LITERT_AUDIO_PATH=/fixtures/audio.wav \
dart test test/integration/genkit/plugin/real_litert_capabilities_test.dart
```

Use a bundle with confirmed built-in image and audio encoders, a valid PNG and
16 kHz mono PCM WAV. The test exercises CPU text, image and audio generation
without a projector, the same fixtures served through a bounded loopback HTTP
resolver, and unsupported strict JSON and embedding requests. Engine observers
verify the downloaded bytes reach native chat input. The HTTP fixture server
and caller-owned client are closed in teardown. Native
runtime setup follows llamadart's platform instructions. For a standalone Dart
validation override, point `LLAMADART_LITERT_LM_LIB_DIR` to the verified pinned
runtime bundle; llamadart 0.19.0 uses `litert-lm-native` v0.19.1-1.
Without these three fixture paths this targeted test is explicitly skipped.
Browser tests of the adapter guards use deterministic runtimes and can run with
`dart test -p chrome test/integration/genkit/plugin/runtime_capabilities_test.dart`;
they validate Web guards, not real Web inference or deployment.

## Multimodal embedding qualification

This opt-in uses existing local EmbeddingGemma-2 files and downloads nothing:

```bash
GENKIT_MULTIMODAL_EMBED_MODELS=/models/embeddinggemma-2 \
  dart test test/integration/genkit/actions/embedder_action/real_model_multimodal_embedding_test.dart -j 1
```

The directory contains `gguf/embeddinggemma-2-BF16.gguf`,
`gguf/mmproj-embeddinggemma-2-BF16.gguf`, and
`litert/embeddinggemma-2-740m.litertlm`. The test verifies SHA-256 before loading:

| File | SHA-256 |
| --- | --- |
| GGUF model | `68bae29d62fb8c7d23e98d21fd4662753ddd636e6b62b8a70dfe059a9844f216` |
| GGUF projector | `d2033b3cd0223cfb2e7a2b50dc80a664c78c816d375f5b017ec3ef80ee0bc766` |
| LiteRT-LM bundle | `e7a8a2204b91e0f96e92960e84a09a89212e1633dcb7575a9bf3378b4df77f4c` |

The GGUF pair comes from `ggml-org/embeddinggemma-2-GGUF` revision
`bfcd298762cc34d0357ece5ebdd31791a3a374d8`; the LiteRT-LM bundle is from
`litert-community/embeddinggemma-2-740m-litert-lm`, identified here by its exact
checksum. Synthetic PNG and one-second mono 16 kHz PCM WAV inputs exercise
text, image, audio and interleaving. Genkit vectors must match direct core calls
on the same CPU backend, with 768 finite dimensions, unit norm, input order and
metadata preserved. Temporary LiteRT-LM caches are isolated from the model files.
The tests are tagged `multimodal-embedding-model` and skip before filesystem/model
access unless enabled. This does not qualify GPU, mobile or real Web embedding.

## Test Models

The default auto-downloaded models are intentionally tiny and CPU-friendly:

- chat: `SmolLM2-135M-Instruct-Q2_K.gguf` (~88 MB)
- embeddings: `jina-embeddings-v2-small-en-Q2_K.gguf` (~20 MB)

They are meant for smoke testing package behavior, not for judging output
quality. The observer/lifecycle smoke fixture explicitly uses CPU, a 1024-token
context and one generation/batch thread to bound resource use. Run real-model
tests with one test worker, as CI does, to avoid overlapping native inference.
See [ARCHITECTURE.md](ARCHITECTURE.md#real-model-smoke-tests) for their sources
and verification.

### Real tool-model qualification

Run this optional production Genkit tool-loop qualification before releasing
tool-adapter changes:

```bash
LLAMADART_AUTO_DOWNLOAD_TOOL_MODEL=1 \
dart test test/integration/genkit/plugin/real_model_tool_calling_test.dart -j 1
```

This separate opt-in downloads Qwen3-1.7B-Q4_K_M (~1.1 GB), not the default tiny
CI fixtures. Revision `d7f544eead698dbd1f15126ef60b45a1e1933222` and SHA-256
`b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897`
are verified before loading, including local paths supplied through
`LLAMADART_INTEGRATION_TOOL_MODEL_PATH`. The test uses native llama.cpp CPU,
4096-token context, greedy sampling and seed 42. Record OS/architecture,
resolved llamadart version, native artifact and result in PR/release evidence.

The model must request a real tool, receive its result through Genkit, and
return the verification code supplied only by the handler. It covers `auto`,
`required`, `none`, truncation, cancellation and recovery. The required-tool
path qualifies text-only multipart results: the model must return the code
supplied only in text parts, while structured output remains separate in Genkit
history. The tool input requires a null value; its adapter schema is compiled with the
pinned native grammar sampler and checked against valid null, invalid string/
number, missing-field and incomplete-output candidates using the Qwen3
vocabulary. Genkit 1.0 retains
`required` on every turn, so explicit application middleware switches to `none`
after the tool result to permit a final answer. Adapter semantics are unchanged.

Malformed and disallowed calls use deterministic negative fixtures through
`Genkit.generate` in `rejects_invalid_tool_calls_test.dart`; no handler may run.
Streamed deltas may be incomplete, but final calls must have valid object
arguments and must not be token-limited. With `toolChoice.none`, inline
tool-looking text stays inert. This native run does not qualify Web/mobile.

The default real-model suite skips this fixture unless its own opt-in/path is
supplied. Fixture resolution returns no path when disabled; every caller must
return before creating a runtime. `markTestSkipped` alone only annotates the
result and does not stop a test. Fast regression checks verify that disabled
fixtures perform no HTTP requests or cache writes, even when tiny-model downloads
are enabled. It is discoverable through the `tool-model` tag.


## Before Opening A PR

The bounded raw-prompt cache and experimental text-session proofs are native
opt-ins. Both use the checksum-pinned tiny chat fixture; default CI skips them
before file/model access. Run these when changing their contracts:

```bash
LLAMADART_RUN_PROMPT_CACHE_PROOF=1 LLAMADART_RUN_BIDI_PROOF=1 \
LLAMADART_AUTO_DOWNLOAD_TEST_MODELS=1 \
dart test test/integration/genkit/runtime/real_model_prompt_cache_test.dart \
  test/integration/genkit/runtime/real_model_bidi_test.dart -j 1
```

Record SDK, model checksum, native build, device/backend, cached-token evidence
and unsupported combinations. See [cache qualification](doc/prompt-caches.md)
and [experimental transport limits](doc/bidi-sessions.md). Native state reuse
does not prove exact sampler continuation; transport chunks do not prove live audio.

For the opt-in native isolation/checkpoint qualification, see the
[bounded proof and known default-batch limitation](doc/runtime-isolation-design.md#bounded-native-checkpoint-proof).
It uses the checksum-pinned tiny chat fixture and adds no session or live-LoRA API.

Run:

```bash
dart format --output=none --set-exit-if-changed .
dart analyze
dart test -x real-model
LLAMADART_AUTO_DOWNLOAD_TEST_MODELS=1 dart test -t real-model -j 1
# Choose a new staging directory outside the checkout:
python3 ../../tool/release/stage_genkit_package.py /tmp/genkit-publish-check
(cd /tmp/genkit-publish-check && dart pub get && dart pub publish --dry-run)
```

The CI job runs after `flutter pub upgrade`, so it exercises the latest
compatible dependency set. A focused compatibility step first pins the direct
runtime dependencies to their supported lower bounds, then runs analysis and the fast
test suite. This keeps both ends executable without duplicating the latest
dependency checks.

## Releasing

The adapter keeps its own version, changelog and package-specific release prep.
Follow the canonical
[Genkit maintainer procedure](https://github.com/leehack/llamadart/blob/main/website/docs/maintainers/genkit-package.md)
for publisher handoff, exact two-file prep scope, repository metadata, tags,
retries and post-publication checks. Merging a reviewed release-prep PR is the
publication approval boundary; a source migration is not a release.

Prep branches use `release/genkit_llamadart-vX.Y.Z`; the optional package label
is `release-prep:genkit_llamadart`. Tags use `genkit_llamadart-vX.Y.Z`.
Core and Apple companion publication are independent. Do not use the old
repository's generic version tags or release-prep routing here.

Run the executable shell replay and staging regressions from the **repository
root**, not this package directory:

```bash
python3 -B -m unittest discover -s test/ci -p 'test_*.py'
dart test -p vm test/unit/tooling/genkit_release_routing_test.dart test/unit/tooling/genkit_package_staging_test.dart
actionlint .github/workflows/release_genkit_on_prep_merge.yml .github/workflows/publish_genkit_pubdev.yml
shellcheck -s bash tool/release/genkit_release_helpers.sh
```

The shell replay uses fake external commands and publishes nothing. POSIX
release-shell replay stays on POSIX hosts; package staging and selector tests
also run on Windows, with only elevated symlink fixtures skipped there.

The publisher verifies the package-specific tag and dated changelog, latest
compatible and lower-bound dependencies, format, analysis, docs, fast and tiny
native model contracts, Pana and a standalone archive dry-run. It stages a copy
outside ancestor archive exclusions and resolves hosted dependencies before
publishing with GitHub OIDC, then creates the package-specific GitHub Release.
No local override or lockfile ships. The owner checklist requires verification
of the real tag, workflow, pub.dev archive and consumer before retiring the old
repository; that retirement needs separate approval.

## Real inference-control qualification

```bash
LLAMADART_AUTO_DOWNLOAD_TEST_MODELS=1 \
LLAMADART_AUTO_DOWNLOAD_TOOL_MODEL=1 \
LLAMADART_AUTO_DOWNLOAD_QWEN35_MODEL=1 \
dart test test/integration/genkit/plugin/real_model_inference_controls_test.dart -j 1
```

This optional suite compares greedy native output with prefix reuse disabled,
single-piece batching and ngram-simple speculation on SmolLM2; it verifies
zero-budget reasoning in Qwen3 chat and constrained JSON, and the complete
Qwen3.5 nonthinking sampling recipe including presence penalty. Qwen3.5-0.8B
Q4_K_M (~533 MB) is separate from default CI auto-downloads. Revision
`6ab461498e2023f6e3c1baea90a8f0fe38ab64d0`, size 532517120 and SHA-256
`bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517`
are verified even for `LLAMADART_INTEGRATION_QWEN35_MODEL_PATH` overrides.

Record OS/architecture, core/native versions, model hashes, output and timing.
These bounded CPU runs qualify routing and sampler behavior, not throughput
claims or every speculative strategy. Model-specific draft/MTP and real Web
qualification remain targeted checks for the chosen model/backend. Browser
adapter guards are tested in `actions/model_action/inference_controls_test.dart`.

Dedicated media qualification is opt-in (`speech-model` and `image-model` tags)
and stays out of ordinary CI downloads. See `test/integration/genkit/media/`:
`GENKIT_ASR_MODEL`/`GENKIT_ASR_PROJECTOR`, `GENKIT_TTS_MODEL`/`GENKIT_TTS_PROJECTOR`,
and `GENKIT_IMAGE_MODEL` point to checksum-verified fixtures. The speech fixture
uses public-domain `whisper.cpp` JFK audio with its exact hash and reference.
Weights are not shipped. Image tests require a consumer enabling
`hooks.user_defines.llamadart.llamadart_native_runtimes: [llama_cpp, stable_diffusion]`.
Optional `GENKIT_TTS_WAV_OUTPUT`/`GENKIT_IMAGE_PNG_OUTPUT` save inspectable artifacts.
Report model revision/checksum, published runtime, platform/backend and actual
result; scripted engines do not qualify model families.

Decision-flow qualification is also opt-in (`decision-model`) and verifies the
Laya encoder and head checksums before running. See [decision flows](doc/decision-flows.md)
for the exact fixtures and command. Ordinary CI skips it without explicit model
paths; the fast schema tests validate complete output and reject malformed
answer shapes without loading weights.

For public runtime-owner qualification, see
[the opt-in native owner proof](doc/runtime-owners.md#real-model-qualification).

Live source-based LoRA routing has fast owner/runtime tests. Its opt-in real
base/adapter pair proof and conversion provenance are in
[the live LoRA qualification guide](doc/live-lora-qualification.md).

### Runnable example qualification

The [example index](example/README.md) documents native CLI setup. Fast retrieval
tests verify ranking, context limits, metadata exclusion, unsupported input,
Genkit routing, abstention and citation rejection. The optional example proof
executes the actual chat, stream, agent, JSON, inspection and retrieval entry points with the
checksum-pinned Qwen3.5 fixture:

```bash
LLAMADART_RUN_EXAMPLE_PROOF=1 LLAMADART_AUTO_DOWNLOAD_QWEN35_MODEL=1 \
  dart test test/integration/genkit/examples/real_model_examples_test.dart -j 1
```

Or supply `LLAMADART_INTEGRATION_QWEN35_MODEL_PATH` instead of opting into a
download. This proof is skipped before cache access unless explicitly enabled;
default CI downloads no additional weights for these examples.

The source-default CLI proof uses an isolated cache seeded with verified local
fixtures; the CLIs receive no model arguments and exercise their real `hf://`
defaults, cache lookup, preparation and inference:

```bash
LLAMADART_RUN_SOURCE_EXAMPLE_PROOF=1 \
LLAMADART_INTEGRATION_MODEL_PATH=/models/SmolLM2-135M-Instruct-Q2_K.gguf \
LLAMADART_INTEGRATION_EMBED_MODEL_PATH=/models/jina-embeddings-v2-small-en-Q2_K.gguf \
LLAMADART_INTEGRATION_TOOL_MODEL_PATH=/models/Qwen3-1.7B-Q4_K_M.gguf \
LLAMADART_INTEGRATION_QWEN35_MODEL_PATH=/models/Qwen3.5-0.8B-Q4_K_M.gguf \
GENKIT_EXAMPLE_VISION_PROJECTOR=/models/mmproj-F16.gguf \
GENKIT_MULTIMODAL_EMBED_MODELS=/models/embeddinggemma-2 \
  dart test test/integration/genkit/examples/real_model_source_examples_test.dart -j 1
```

Each fixture is independently optional and checksum-verified before cache access.
The vision projector SHA-256 is
`56e4c6cfe73b0c82e3e82bc518d7591997e61d81f723fc41a586f4fa69ea2453`, from
the same pinned Qwen3.5 revision as the chat model. LiteRT EmbeddingGemma-2 is
pinned at `24d962e906c7d332c6428e71c9676855024569e2`; its checksum is above.
This test does not download new models in ordinary CI. A separate fresh-cache
owner CLI run verifies the network path (about 88 MB):

```bash
LLAMADART_EXAMPLE_CACHE=/tmp/genkit-example-fresh-cache \
  dart run example/genkit_llamadart_owner_example.dart
```

The five specialty CLI proofs use the same checksum-pinned fixtures as the
[LoRA qualification](doc/live-lora-qualification.md),
[decision proof](test/integration/genkit/decision/real_model_decision_test.dart)
and [speech](test/integration/genkit/media/real_model_speech_test.dart) /
[image](test/integration/genkit/media/real_model_image_test.dart) proofs. They exercise the
actual entry points with local model overrides, without automatic downloads:

```bash
LLAMADART_RUN_SPECIALTY_EXAMPLE_PROOF=1 \
LLAMADART_TEST_LORA_BASE=/models/Base-F32.gguf \
LLAMADART_TEST_LORA_ADAPTER=/models/Lora-F32.gguf \
GENKIT_DECISION_ENCODER=/models/laya-Q4_K_M.gguf \
GENKIT_DECISION_HEAD=/models/laya-head.safetensors \
GENKIT_ASR_MODEL=/models/Qwen3-ASR-0.6B-Q8_0.gguf \
GENKIT_ASR_PROJECTOR=/models/mmproj-Qwen3-ASR-0.6B-Q8_0.gguf \
GENKIT_TTS_MODEL=/models/Qwen3-TTS-12Hz-1.7B-Base-Q4_K_M.gguf \
GENKIT_TTS_PROJECTOR=/models/mmproj-Qwen3-TTS-12Hz-1.7B-Base-Q8_0.gguf \
GENKIT_IMAGE_MODEL=/models/sdxs-512-tinySDdistilled_Q8_0.gguf \
  dart test test/integration/genkit/examples/real_model_specialty_examples_test.dart -j 1
```

Each test skips explicitly when its fixtures are missing. The image CLI requires
the [stable_diffusion hook configuration](example/README.md#images-and-speech)
in the consumer's `pubspec.yaml`. To keep that optional runtime out of this
package's defaults, run the proof in a temporary repository copy with the hook
enabled and run `dart pub get` there first.

The maintained checks validate changed LoRA output, schema-valid decision JSON,
the exact normalized JFK transcript, complete non-silent mono 24 kHz PCM WAV,
and a decoded, nonuniform 256×256 PNG. The synthetic LoRA pair is a behavior
control, not a language-quality sample. The macOS arm64 CPU qualification also
visually checked the red apple image and transcribed synthesized speech back
through the ASR CLI; those content checks are separate from file validity.

## Rich tool schema qualification

```bash
LLAMADART_AUTO_DOWNLOAD_TOOL_MODEL=1 \
  dart test test/integration/genkit/plugin/real_model_rich_tool_schemas_test.dart -j 1
```

This reuses the Qwen3 revision/checksum described above. It qualifies native
llama.cpp CPU on macOS arm64 against published llamadart 0.13.0 / native
v0.6.0-3. Positive and negative compiled grammar candidates check null/type
alternatives, numeric enums, const, anyOf, length/item bounds and closed
objects through the serialized tool schema and actual model chat template.
Real Genkit handlers must run and supply the final answer in auto/required
loops. The same test executes the rich-schema CLI example. Fast tests cover
interrupt/resume, final validation/stream suppression and unsupported runtime
capabilities. See [the schema matrix](doc/tool-input-schemas.md) for unqualified
families and backend restrictions. Default CI skips this 1.1 GB fixture unless
explicitly enabled; a skip is not model qualification.
