---
title: Finding and Choosing Models
---

`llamadart` runs models formatted as **GGUF** (GGML Unified Format), the
standard format used by `llama.cpp`. You cannot use raw PyTorch (`.bin` or
`.safetensors`) models directly; they must be converted and quantized into GGUF
first.

Fortunately, thousands of pre-converted GGUF models are readily available.

## Where to find models

The best place to find GGUF models is **[Hugging Face](https://huggingface.co/models?search=gguf)**.

You can search for any model name followed by `gguf` (e.g., `Llama-3-8B-Instruct-GGUF`).
For a deeper dive into the GGUF ecosystem and how quantization works, check out these insightful resources:
- [The GGUF format specification](https://github.com/ggerganov/ggml/blob/master/docs/gguf.md)
- [Hugging Face's official GGUF documentation](https://huggingface.co/docs/hub/en/gguf)
- [Quantization in llama.cpp](https://github.com/ggerganov/llama.cpp/wiki/Tensor-Encoding-and-Quantization)

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

## Downloading a model

Once you find a model on Hugging Face:
1. Go to the **Files and versions** tab of the model repository.
2. Look for a file ending in `.gguf` (e.g., `model-q4_k_m.gguf`).
3. Click the download icon next to the file.
4. Place the downloaded `.gguf` file in your application's assets or a reachable file path for `engine.loadModel()`.
