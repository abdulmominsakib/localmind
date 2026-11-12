# Complete image checkpoint container controls

This is qualification of existing loaders for #1218, not a new conversion or
model-ingestion API. The maintained `image-container-formats` scenario extends
the basic example's existing `checkpoint containers preserve CPU pixels` case.
It requires hashed local inputs and independent native reference images.

## Qualified inputs and settings

Requalified on stable-diffusion-native `v0.3.0-1` (2026-10-27): every result below is byte-identical to the `v0.3.0` measurement ([#922](https://github.com/leehack/llamadart/issues/922)).

The source is `Green-Sky/SD-Turbo-GGUF` at immutable revision
`19a31586d02d64a73b4419bc193b3ecfaf38e1f0`, file `sd_turbo-f16.gguf`.
The repository's LFS digest and size match the local file: 2,612,748,512 bytes.
No weights were downloaded for this run. The complete checkpoint contains
1,323 F16/F32 tensors (2,612,612,748 tensor bytes), including its full VAE.
The fixture producers retain every tensor name, shape, dtype and byte, then
verify the written representation. PyTorch inputs use `torch.save` 2.11.0,
protocol 2, as an `OrderedDict` or nested `state_dict`; no arbitrary Python
checkpoint object is executed. Only the producer's own outputs are read back
with `weights_only=True`.

| Input | SHA-256 in this run | Public roles |
| --- | --- | --- |
| Original F16 GGUF | `748f890c075c5d36df93a5ca47e382c7242cd10c2d1084861727f64fb4336540` | Automatic, explicit checkpoint |
| Generated Safetensors | `69f877d397530ba1b20316f136aa6a483233b3b3abbb552821a7b01530d0ff88` | Automatic, explicit checkpoint |
| Generated legacy `.pth` | `54f09072aa0e3bbe201d1f0f65d4cacb30b7d694e8957195742d9f266fd326b0` | Explicit checkpoint |
| Generated ZIP `.pt` | `87d4d377456a29e75074e9d05cdb3a9210e766d6b0e02485a401efc89c7aac8e` | Explicit checkpoint |
| Generated nested ZIP `.ckpt` | `8ed64d0df3a8f21bcdeee7f0e9979eaaa11c2fe0dc6692ec39c138bebdc7d151` | Explicit checkpoint |

Generated PyTorch container metadata can vary between producer runs. Use the
new receipt's digest after verifying its tensors; do not substitute a hash
from this table for different bytes.

All seven public loads, generations and disposals passed on macOS arm64 CPU,
using four threads, 128×128, one Euler/discrete step, CFG 1, seed 42, conditioning
cache disabled, unbatched CFG and explicit flash/direct-convolution modes off.
The prompt is `a red fox in a green forest, watercolor painting`. Every raw RGB
output equals its separately initialized guarded direct-C reference and the
GGUF baseline: SHA-256
`f08a13f24bbe3fee369616e1d2308468dacbcd78af3c09162ddd46405f532ec6`.

The native artifact is `stable-diffusion-native v0.3.0-1`, upstream
`be486498eadc29dc3cd234d944c2180ed42b1415` plus `pickle_line_span.patch`, `fp8_metal_f16_load.patch` and
`lora_immediate_fallback.patch`.
Its macOS arm64 archive SHA-256 is
`79c3517b363e6509df17af4d20056ed6e47bbbd134681fb9321520702534cb40`.
The extracted direct-C dylib is
`3e864a0cc18a963fe3e3f26edc269ce9a0966e631e3fc06982e9051bcb8f7d0b`;
the hook can rewrite install names in its installed copy. Archive provenance
and the actual installed-library bytes remain separate observations.

## Reproduce from trusted local files

Use the pinned Dart/Flutter SDK. The optional fixture producers require a
little-endian host, NumPy and a trusted `gguf-py/gguf` directory; PyTorch variants
also require PyTorch 2.11.0. The recorded reader was from llama.cpp
`e9fa0781f1c25fc4fe8c86be1edc6970661ad6f0`. These are test-input producers,
not shipped runtime dependencies or a public conversion API.

```bash
python3 example/basic_app/test/fixtures/transcode_image_safetensors.py \
  --gguf-package /local/llama.cpp/gguf-py/gguf \
  --source /local/sd_turbo-f16.gguf --output /local/inputs/model.safetensors \
  --receipt /local/inputs/safetensors-receipt.json
python3 example/basic_app/test/fixtures/transcode_image_torch.py \
  --gguf-package /local/llama.cpp/gguf-py/gguf \
  --source /local/sd_turbo-f16.gguf --output-dir /local/inputs
```

Outputs must not already exist. Preserve the verification receipts. Extract
the checksum-verified pinned native bundle into `$bundle`, then compile the
maintained independent reference (it fills C structs directly, without Dart
mapping helpers):

```bash
clang++ -std=c++17 \
  example/basic_app/test/fixtures/image_container_native_reference.cpp \
  -I"$bundle/include" -L"$bundle/lib" -lstable-diffusion \
  -Wl,-rpath,"$bundle/lib" -o /local/native-reference
/local/native-reference /local/sd_turbo-f16.gguf /local/references/gguf-f16.ppm
```

Repeat the last command for each input, with its matching `<id>.ppm` output.
The recorded native controls had an external 45-second deadline per input;
preserve failures/timeouts instead of treating missing references as a pass.
Create a local JSON array (use full verified SHA-256 strings):

```json
[
  {"id":"gguf-f16","path":"/local/sd_turbo-f16.gguf","sha256":"..."},
  {"id":"safetensors-f16","path":"/local/inputs/model.safetensors","sha256":"..."},
  {"id":"torch-legacy","path":"/local/inputs/torch-legacy.pth","sha256":"...","auto":false}
]
```

`auto:false` selects explicit roles only, as PyTorch requires. The other inputs
run both automatic and explicit roles. From the repository root:

```bash
LLAMADART_IMAGE_CONTAINER_REFERENCES=/local/references \
  dart run tool/testing/run_local_e2e.dart --scenario image-container-formats \
  --model-path /local/inputs/models.json --dry-run
```

Remove `--dry-run` after inspecting it. The scenario writes PNGs and the
model/output digests and observed load/generation wall times to
`build/image-container-formats`; those small controls are not benchmarks.

## Limits

The >2-GiB legacy result exercises the published owner reader repair. Current
ZIP inputs completed within the bound, but the historical ZIP timeout's cause
remains unresolved (owner #24); this is later non-reproduction, not a proven
ZIP fix. No broad PyTorch, architecture, dtype, quantization, GPU, Windows,
Linux or mobile full-checkpoint qualification follows. Whole modules,
TorchScript, arbitrary pickle callables and legacy TAR remain unsupported.

The suite checks container/role transport, not artistic quality. Existing
malformed/oversized header, role ambiguity, missing diffusion weights,
decoder-only TAESD and latent-channel mismatch tests remain applicable.
Managed directories, shard-set containment and aggregate identities remain
separate #1219 work; explicit index forwarding is not a managed-set contract.
Weights still load eagerly; no public mmap, load-time weight conversion or
quantization option is added.

## Original SD24 mode — preparation only

The separate maintained `image-original-containers` scenario prepares the six
original Safetensors/flat/nested native/public cases with external full TAESD,
conditioning cache4 and diffusion flash attention. Its fixed settings, strict
177s active +3s cleanup case budget,45s load gate, source/artifact bindings and
stop-on-failure graph are documented in the
[private operator contract](../packages/llamadart_validation/native/sd_original_mode/README.md).
It currently targets the reviewed PR41 diagnostic artifact, not a final
published runtime. No generation result is recorded here; source/artifact/plan
admission and root execution remain separate. Earlier failures and the ordinary
embedded-VAE/cache0/flash-off qualification above retain their original scope.
