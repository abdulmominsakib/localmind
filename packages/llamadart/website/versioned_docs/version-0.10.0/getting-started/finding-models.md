---
title: Find and choose GGUF and LiteRT-LM models
sidebar_label: Finding models
description: Where to download GGUF and .litertlm models, how quantization trades quality for size, and which model sizes fit each platform.
---

`llamadart` supports two model artifact families:

- **GGUF** (GGML Unified Format), the standard format used by `llama.cpp`.
- **`.litertlm`** bundles, used by LiteRT-LM.

You cannot use raw PyTorch (`.bin` or `.safetensors`) models directly; they
must be converted into a runtime-ready artifact first. For most open model
workflows that means a quantized GGUF. For LiteRT-LM deployments, use a
published `.litertlm` bundle that matches the LiteRT-LM runtime.

Fortunately, thousands of pre-converted GGUF models are readily available.
LiteRT-LM bundles are more specialized; use them when your target model is
distributed for LiteRT-LM or when you are intentionally benchmarking that
runtime path.

## Where to find models

The best place to find GGUF models is
**[Hugging Face](https://huggingface.co/models?search=gguf)**.

You can search for any model name followed by `gguf` (e.g., `Llama-3-8B-Instruct-GGUF`).
For a deeper dive into the GGUF ecosystem and how quantization works, check out these insightful resources:
- [The GGUF format specification](https://github.com/ggerganov/ggml/blob/master/docs/gguf.md)
- [Hugging Face's official GGUF documentation](https://huggingface.co/docs/hub/en/gguf)
- [Quantization in llama.cpp](https://github.com/ggerganov/llama.cpp/wiki/Tensor-Encoding-and-Quantization)

For LiteRT-LM, look for model repositories that publish `.litertlm` files and
document LiteRT-LM compatibility. If both GGUF and `.litertlm` variants exist,
see [Choosing llama.cpp or LiteRT-LM](../guides/backend-selection) before
treating them as equivalent artifacts.

## Understanding Quantization

GGUF models usually come in different "quantization" levels, denoted by tags like `Q4_K_M` or `Q8_0`. Quantization reduces the precision of the model's weights to save memory and increase inference speed, at a slight cost to "smartness" (perplexity).

Here is a quick guide to choosing a quantization level:

- **`Q4_K_M`**: The recommended baseline. It offers an excellent balance between small file size, fast generation, and retaining the model's original quality.
- **`Q5_K_M`**: Slightly larger and slower than Q4, but retains more quality. Good if you have the RAM to spare.
- **`Q8_0`**: Almost indistinguishable from the unquantized raw model, but requires double the RAM of Q4.
- **`Q2_K` / `Q3_K`**: Highly compressed. Useful only if you are severely constrained by RAM (e.g., running on older mobile phones), but expect noticeable degradation in reasoning logic.

## Recommended constraints per platform

When downloading a model, check its file size. Your target device needs enough **free RAM** (or VRAM for GPU offloading) to load the model, plus a bit extra for the context window.

| Platform | Recommended Model Parameter Size | Target RAM Usage | 
|----------|----------------------------------|------------------|
| **Mobile (iOS/Android)** | 1B - 3B parameters | 1GB - 2.5GB (e.g., Llama-3.2-1B Q4_K_M) |
| **Old Laptop/Desktop** | 3B - 8B parameters | 2.5GB - 6GB (e.g., Llama-3.1-8B Q4_K_M) |
| **Modern Mac (M1/M2/M3)** | 8B - 32B parameters | 6GB - 20GB+ |

## Starting points

These files are the ones the examples in this repository use. Sizes are for the
file as downloaded. Paste a path into `ModelSource.parse(...)`.

| Task | Model file | Size |
| --- | --- | --- |
| Smoke test only, not for judging quality | `hf://unsloth/SmolLM2-135M-Instruct-GGUF/SmolLM2-135M-Instruct-Q2_K.gguf` | about 88 MB |
| Chat, tool calling, vision | `hf://unsloth/Qwen3.5-0.8B-GGUF/Qwen3.5-0.8B-Q4_K_M.gguf`, projector `mmproj-F16.gguf` in the same repo | about 533 MB plus 205 MB |
| Tool-calling demos | `hf://unsloth/functiongemma-270m-it-GGUF/functiongemma-270m-it-Q4_K_M.gguf` | about 253 MB |
| Image and audio input | `hf://unsloth/gemma-4-E2B-it-GGUF/gemma-4-E2B-it-Q4_K_S.gguf`, projector `mmproj-F16.gguf` in the same repo | about 3.0 GB plus 1.0 GB |
| LiteRT-LM | `hf://litert-community/gemma-4-E2B-it-litert-lm/gemma-4-E2B-it.litertlm` | about 2.6 GB |
| Embeddings | `hf://ggml-org/embeddinggemma-300M-GGUF/embeddinggemma-300M-Q8_0.gguf` | about 334 MB |

## Downloading a model

Once you find a model on Hugging Face:

1. Go to the **Files and versions** tab of the model repository.
2. Look for a file ending in `.gguf` (e.g., `model-q4_k_m.gguf`) or
   `.litertlm`.
3. Pass the exact repository path to
   `ModelSource.parse('hf://owner/repo/path/to/model.gguf')` and load it with
   `engine.loadModelSource(...)`. Keep the real file extension in the path so
   `LlamaBackend()` can route to the correct runtime.

On native, `engine.loadModel()` takes a filesystem path; on web, a URL.
`llamadart` has no asset loader: to ship a model as a Flutter asset on native,
copy the asset to a file first (for example into the app support directory)
and pass that path.

Revisions, private repositories, `mmproj` projector files and sharded GGUFs:
see [Download and cache models](../guides/model-downloads).
