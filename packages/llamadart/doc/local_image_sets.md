# Bounded local checkpoint sets

The first #1219 slice accepts a complete SD-Turbo F16/F32 checkpoint split
across 1..16 adjacent Safetensors shards, declared by
`model.safetensors.index.json`. Either the standard index or its directory is
an input. This is not a Diffusers pipeline/component reader. Markers such as
`model_index.json` or `unet/`, extra model/index files and component overrides
are deliberately unavailable. Individual-file GGUF/Safetensors and explicit
PyTorch roles retain their existing route; no remote set/repository fetch,
native owner/ABI/pin change, GPU/device or new validation catalog is involved.

## Recipe and provenance

Requalified on stable-diffusion-native `v0.3.0-1` (2026-10-27): every result below is byte-identical to the `v0.3.0` measurement ([#922](https://github.com/leehack/llamadart/issues/922)).

- Pinned stable-diffusion-native v0.3.0-1, upstream
  `be486498eadc29dc3cd234d944c2180ed42b1415`, macOS CPU, explicit flash attention
  and direct VAE convolution off. Four CPU threads were measured.
- Trusted macOS arm64 archive SHA-256
  `79c3517b363e6509df17af4d20056ed6e47bbbd134681fb9321520702534cb40`;
  extracted library SHA-256
  `3e864a0cc18a963fe3e3f26edc269ce9a0966e631e3fc06982e9051bcb8f7d0b`.
- Full original SD-Turbo F16 GGUF: SHA-256
  `748f890c075c5d36df93a5ca47e382c7242cd10c2d1084861727f64fb4336540`,
  immutable `Green-Sky/SD-Turbo-GGUF@19a31586d02d64a73b4419bc193b3ecfaf38e1f0`.
  The existing container-only derived complete Safetensors checkpoint is
  SHA-256 `69f877d397530ba1b20316f136aa6a483233b3b3abbb552821a7b01530d0ff88`.
  All 1,323 tensor payloads were verified against that conversion receipt.
  This work adds no public conversion API.
- The accepted tensor-layout fingerprint is
  `e5ae320534104044d4816a818df7129b9fd2d33d1262d18081adac95dee012fd`:
  SHA-256 of compact UTF-8 JSON `[[name,dtype,shape], ...]`, sorted by tensor
  name. It describes the measured 1,323-tensor recipe, including each dtype
  and dimension. It is not a general model-completeness detector, a weight
  allowlist, or model authenticity proof. Other matching weights are unmeasured;
  other layouts/inventories/dtypes are refused before native load.

The measured two-shard fixture preserves every tensor's bytes, names, shapes
and dtype. It has 2,612,612,748 tensor bytes and 2,612,941,197 total bytes
including shard headers and index. Native guarded-C directory, explicit index
and complete single-file reference all yield raw RGB SHA-256
`f08a13f24bbe3fee369616e1d2308468dacbcd78af3c09162ddd46405f532ec6`.
The public existing explicit-role index diagnostic matches, but reports only
the 144,881-byte index; it does not establish managed safety/accounting.
The new managed path accounts for the entire set.

## Resolution/cache contract

`ImageGenerationModel.localSafetensorsSet(path, sha256: ..., cacheDirectory: ...)`
returns an internal subtype, so old `ImageGenerationModel` implementers gain
no required getter and no new public SPI is introduced. The expected map is
copied and must identify the index and every shard by safe basename/digest.
It should come from trusted immutable app configuration, not a checksum taken
from whatever mutable files happen to be present at load time.

The loader resolves every required local file through `ModelFileStore` before
calling any manager. Remote and outside-root resolver targets are refused,
then the existing manager checks each local file. Only cancellation from
`ModelLoadOptions` applies: this factory supplies per-file hashes and an
explicit owned cache location. Local file/credential options on existing
individual-file paths are unchanged.

Managed entries allow safe ASCII basenames only: no absolute/parent paths,
subdirectories, Windows backslashes/drive prefixes or encoded separators.
Canonical adjacency and regular-file checks reject symlinks, including the
index. Source directory topology must stay stable throughout resolution and
copying; concurrent malicious file-entry replacement is outside this
app-owned-source contract. Contents are hash-verified while copying, so a
manager's earlier checksum is not treated as an immutable lease.

A unique partial snapshot lives in the app-private cache namespace. Streams
are bounded and cancellation-aware; every header's F16/F32 tensor sizes,
nonoverlapping contiguous ranges, index mapping and complete identity map are
checked. JSON keys must be unique, including escaped aliases. Headers are
bounded to 1 MiB, index to 4 MiB, nesting to 32 levels, aggregate files to
3 GiB. Shard metadata accepts only the optional `format: pt` marker; index
metadata accepts only an optional exact integer `total_size`.

Publication renames the verified directory atomically under the hash of the
sorted filename/expected-hash pairs. Concurrent publishers converge on the
same verified immutable identity. Cache reuse rehashes all files, so corrupt
content fails rather than being silently repaired under a live engine. Cache
content verification and model-family admission are separate; an unsupported
content set may be retained but can never reach native load.

The caller reserves this cache for owned snapshots and must never alter or
remove published files while any engine uses them. There is no automatic
pruning of published snapshots; clear the cache manually after all engines
are disposed. The original files can change or disappear after copying.
Cancellation/failure removes only this load's partial directory; a complete
published snapshot remains cached. Cleanup failures surface as errors.
Progress and memory estimates include every shard/header and the index in
sorted basename order, rather than using the tiny index's size.

Loaded capability `supportsLocalSafetensorsSets` confirms this admitted
recipe; it is false before load/after disposal. Managed assignment deliberately
withholds the decoder proof used for VAE tiling, seamless and image-editing
opt-ins. The first slice is ordinary text-to-image only, including when later
combined with the separate image-editing branch.

## Reproduce

Use the pinned Flutter 3.47.1 / Dart 3.13.1, prepare the clean workspace and
supply the existing complete Safetensors checkpoint above. No weights are
downloaded by this scenario. The maintainer fixture builder streams the
unchanged tensors into two shards; it refuses another input identity or an
unrecognized existing output directory.

```bash
python3 example/basic_app/test/fixtures/split_local_checkpoint.py \
  "$complete_safe" build/local-image-set-fixture
clang++ -std=c++17 \
  example/basic_app/test/fixtures/local_image_set_native_reference.cpp \
  -I"$bundle/include" -L"$bundle/lib" -lstable-diffusion \
  -Wl,-rpath,"$bundle/lib" -o build/local-image-set-reference
build/local-image-set-reference \
  build/local-image-set-fixture/model.safetensors.index.json \
  build/local-image-set-reference.ppm
dart run tool/testing/run_local_e2e.dart --list
dart run tool/testing/run_local_e2e.dart --scenario image-local-checkpoint-sets \
  --model-path "$complete_safe" --dry-run
LLAMADART_LOCAL_SET_REFERENCE="$PWD/build/local-image-set-reference.ppm" \
  TMPDIR="$(mktemp -d)" dart run tool/testing/run_local_e2e.dart \
  --scenario image-local-checkpoint-sets --model-path "$complete_safe"
```

The C fixture directly fills upstream structs and uses the existing guarded
wrapper; it shares no Dart parameter helper. CPU settings are 128 square,
Euler/discrete, one step, CFG 1, seed 42, conditioning cache zero and explicit
flash/direct off. Native/public output must match exactly. The maintained
suite also removes only its script-created source directory while an engine
is alive, verifies generation/cache reload, checks cancellation removes its
partial stage, recovers, and refuses tiling/seamless requests. A reference
path is optional for diagnostics; qualification requires the independent C
comparison. Inspect the saved PNGs; exact parity is not arbitrary prompt or
image-quality certification.

`example/basic_app/bin/local_image_set.dart` is a runnable public consumer
accepting a local directory or index, trusted hash-map JSON, dedicated private
cache and output PNG. True Diffusers components and other image families are
unavailable until independently qualified. A versioned validation pack remains
tracked in [#1219](https://github.com/leehack/llamadart/issues/1219).


The first slice requires complete contiguous numbered shard basenames,
`model-00001-of-000NN.safetensors` through `model-000NN-of-000NN.safetensors`,
for N in 1..16. Arbitrary names, gaps and count aliases fail before manager or
native work. This keeps caller-chosen basenames out of the existing native
log path; no shared worker/redactor expansion is needed. The strict index
mapping and tensor-layout fingerprint bind all native-visible tensor names;
unsupported metadata/extra aliases use fixed error categories without
quoting caller text.

Managed integrity, confinement and aggregate accounting apply only to
`localSafetensorsSet`. Legacy ordinary explicit-role JSON forwarding remains
unchanged and unqualified; it does not acquire these guarantees. Unexpected
process termination may leave uncommitted partial directories; these are never
reused, and may be removed only after all processes using this private cache
have stopped.


The fixed 128-square, one-step diagnostic output is an abstract green/white
pattern rather than a recognizable fox. Native single-file, index, directory
and public paths are byte-identical, so this qualifies container/cache-path
equivalence only. It is not evidence of prompt fidelity or a recommended
image-generation preset; no cause for that baseline output is asserted here.
