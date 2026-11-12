# Native live LoRA qualification

The [dedicated owner API](runtime-owners.md#live-lora) uses published llamadart
0.11.1 source-based adapter controls. The maintained proof covers both direct
engines and public owner routing on macOS arm64 CPU, native `v0.5.0-2`, upstream
llama.cpp `7fe450e19305b828c199d602c23a8337aaa1f03b`.

## Pinned pair

The fixture is the small trained synthetic Llama pair used by
[llama.cpp's official LoRA test](https://github.com/ggml-org/llama.cpp/blob/7fe450e19305b828c199d602c23a8337aaa1f03b/tests/test-lora-conversion-inference.sh).
It is a behavior control, not a production model or a Gemma/Qwen qualification.
Source: [ggml-org/lora-tests at c26d5fb](https://huggingface.co/ggml-org/lora-tests/tree/c26d5fb85b4070a9e9c4e65d132c783b98086890/LlamaForCausalLM/hidden_size%3D64),
`LlamaForCausalLM/hidden_size=64/base` and `/lora`. Conversion uses the
unmodified upstream scripts at the exact native source commit.

| Converted file | Bytes | SHA-256 |
| --- | ---: | --- |
| Base-F32.gguf | 76403584 | `cd144ca9826a7b009f8b841c247de6cf6c982735a1d13e9830cdd27447cfac16` |
| Lora-F32.gguf | 19203744 | `ecb2cbbbc49ad140b1be6c073a6221c785c4101aedc88e92e8029b67b7cbb50a` |

Source safetensors SHA-256: base
`8f88983f4a197958c8e1e88802495b9ddd090421bfd43b4cb13276d4471d4d83`,
adapter `6cf1e0f1254d5b391eebf7168ff4313a44794b10a82e276d72bd9a0499a5fd62`.
The test verifies converted sizes and checksums before creating engines.

## Reproduce

In a temporary workspace, download the pinned source pair and upstream scripts.
Conversion was qualified with Python 3.12.14, torch 2.11.0, transformers 4.57.6,
numpy 2.2.6, gguf 0.19.0, safetensors 0.8.0, sentencepiece 0.2.2 and
tokenizers 0.22.2. Use an isolated environment for upstream requirements:

```bash
git clone https://github.com/ggml-org/llama.cpp.git upstream
git -C upstream checkout 7fe450e19305b828c199d602c23a8337aaa1f03b
python3.12 -m venv venv
venv/bin/pip install -r upstream/requirements.txt
venv/bin/pip install torch==2.11.0 transformers==4.57.6 numpy==2.2.6 \
  gguf==0.19.0 safetensors==0.8.0 sentencepiece==0.2.2 tokenizers==0.22.2
venv/bin/hf download ggml-org/lora-tests \
  --revision c26d5fb85b4070a9e9c4e65d132c783b98086890 \
  --include 'LlamaForCausalLM/hidden_size=64/base/*' \
  'LlamaForCausalLM/hidden_size=64/lora/*' --exclude '**/README.md' \
  --local-dir source
venv/bin/python upstream/convert_hf_to_gguf.py \
  source/LlamaForCausalLM/hidden_size=64/base --outfile Base-F32.gguf --outtype f32
venv/bin/python upstream/convert_lora_to_gguf.py \
  source/LlamaForCausalLM/hidden_size=64/lora \
  --base source/LlamaForCausalLM/hidden_size=64/base \
  --outfile Lora-F32.gguf --outtype f32
```

Exclude the model cards to reproduce the hashes above. The adapter's README
adds base-model provenance fields during conversion; including it produces
different GGUF metadata and a different checksum even with identical tensors.
Use a fresh source directory so a previously downloaded README is not retained.

Then from this repository:

```bash
LLAMADART_TEST_LORA_BASE=/absolute/path/Base-F32.gguf \
LLAMADART_TEST_LORA_ADAPTER=/absolute/path/Lora-F32.gguf \
dart test test/integration/genkit/runtime/real_model_lora_isolation_test.dart -j 1
```

## Evidence and limits

Both paths apply a live adapter, change its scale to half and zero, remove it,
clear it and restore baseline scores/output. Interleaved owner B remains
unchanged. Native load observers prove the base loads only once per context;
mutation does not reload it. Generation after mutations reports no cached prompt
tokens. A missing adapter fails; public owner A is disposed and B stays usable.
Fast tests separately prove mutation/inference ordering in both directions,
explicit unsupported probes before source loading, source/download/progress
forwarding, finite-scale validation and queued/active cancellation.

The raw prompt is `Is this`, with 256-token contexts, one generation/batch thread,
batch/microbatch 1 and greedy eight-token decoding. Batch 1 is a bounded control,
not a global tuning recommendation. The fixture does not claim production output
quality, arbitrary adapter compatibility, aLoRA, GPU, Web, LiteRT-LM, other native
devices or exact KV-checkpoint continuation. Applications must choose a matching
base/adapter pair and pin trusted bytes themselves.

If either environment variable is absent, both tests skip before model/cache
access. Ordinary CI does not download this pair. No weights or native source
patches are shipped in the package.
