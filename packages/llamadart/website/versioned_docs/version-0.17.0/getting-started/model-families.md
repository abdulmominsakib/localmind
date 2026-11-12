---
title: Supported model families
sidebar_label: Model families
description: Which model families run on llamadart, how their chat templates, tool calls and reasoning are handled, and which ones are validated with a real model.
---

llamadart has no model allowlist. Any GGUF that the pinned llama.cpp runtime
can load will generate text. What varies by family is how chat messages, tool
calls and reasoning are formatted and parsed, and that follows from the
model's chat template.

## How a family is recognized

- **GGUF:** llamadart reads the chat template embedded in the file
  (`tokenizer.chat_template`, or `tokenizer.chat_template.tool_use` when tools
  are passed) and detects its format from marker strings, in llama.cpp's
  priority order. It does not look at the model name or architecture.
- **`.litertlm`:** bundles do not expose their template, so llamadart picks
  one from the file name: `gemma-4`, `gemma-3n`, `gemma-3`/`gemma-2`, `qwen3`
  or `qwen2.5`. Set `ModelParams.chatTemplate` to override it.
- **No match:** the template renders as-is, with no tool-call or reasoning
  parsing. If you pass tools, llamadart adds a generic JSON tool-call
  instruction instead.

To see what a model will receive, render the prompt with
`engine.chatTemplate(...)`; see
[Chat templates and output parsing](../guides/chat-template-and-parsing).

## Evidence levels

- **Validated:** the llamadart validation pack
  (`packages/llamadart_validation`) has a profile that runs the real model.
- **Template-tested:** CI detects and renders the family's published chat
  template, and parses sample output where one is recorded. Templates come
  from llama.cpp's template set (release `b10549`) and from real GGUF files.

## Chat families

| Family | Artifacts | Detected format | Evidence | Example repo |
| --- | --- | --- | --- | --- |
| Qwen3.5 | GGUF, `.litertlm` | Qwen3-Coder XML (GGUF); Qwen3 template (`.litertlm`) | Validated: GGUF on CPU, Metal, CUDA, Vulkan and WebGPU; LiteRT-LM on CPU and GPU | `ggml-org/Qwen3.5-0.8B-GGUF`, `litert-community/Qwen3.5-0.8B` |
| Gemma 4 | GGUF, `.litertlm` | Gemma 4 | Validated: GGUF and LiteRT-LM | `unsloth/gemma-4-E2B-it-GGUF`, `litert-community/gemma-4-E2B-it-litert-lm` |
| Qwen3 | GGUF, `.litertlm` | Hermes | Validated: LiteRT-LM. Template-tested: GGUF | `litert-community/Qwen3-0.6B` |
| Gemma 3, 3n, 2 | GGUF, `.litertlm` | Gemma (generic JSON tool calls) | Validated: LiteRT-LM. Template-tested: GGUF | `litert-community/Gemma3-1B-IT` |
| Qwen2.5, QwQ | GGUF | Hermes | Template-tested | `Qwen/Qwen2.5-0.5B-Instruct-GGUF` |
| Qwen3-Coder | GGUF | Qwen3-Coder XML | Template-tested | — |
| FunctionGemma | GGUF | FunctionGemma | Template-tested | `unsloth/functiongemma-270m-it-GGUF` |
| Llama 3.1, 3.2, 3.3 | GGUF | Llama 3 | Template-tested | — |
| Mistral Nemo | GGUF | Mistral Nemo | Template-tested | — |
| Mistral Small 3.2, Ministral 3, Devstral | GGUF | Ministral | Template-tested | — |
| DeepSeek R1 distills, V3.1, V3.2, V4 | GGUF | DeepSeek R1, V3, V3.2, V4 | Template-tested | — |
| GLM 4.6, 4.7 Flash | GGUF | GLM 4.5 | Template-tested | `unsloth/GLM-4.7-Flash-GGUF` |
| Granite 3.3; Granite 4.0, 4.1 | GGUF | Granite; Hermes | Template-tested | — |
| LFM2 8B-A1B, LFM2.5 8B-A1B, LFM2.5 Instruct | GGUF | LFM2 | Template-tested | — |
| Phi-3.5, SmolLM3 | GGUF | None (generic JSON tool calls) | Template-tested | — |

Other families whose published templates are template-tested with their own
format: GPT-OSS, Seed-OSS, Nemotron Nano v2, Apertus,
Kimi K2 and K3, MiniMax M1, M2 and M3, Command R7B, Cohere2 MoE, MiniCPM5,
Hunyuan Hy3, Solar Open, Poolside Laguna, Muse Glimmer, Functionary v3.1
and v3.2, and FireFunction v2. Nemotron 3 Nano and StepFun 3.5 Flash use the
Qwen3-Coder XML format; Hermes 2 Pro, Hermes 3, Bielik, Reka Edge, MiMo-VL
and Apriel 1.5 use the Hermes format.

"Generic JSON tool calls" means llamadart supplies a fallback protocol when
the selected template has no recognized tool-call format: it asks the model
to answer with a `tool_call` or `response` JSON object and parses that. This
is an intentional extension to the tested llama.cpp behavior, not evidence
of native tool support or reliable tool selection. Templates can omit tool
definitions even when a grammar constrains the output. See
[Generic JSON fallback](../guides/tool-calling#generic-json-fallback) for the
protocol, upstream comparison and prompt limitations.

Where a format defines reasoning markers, such as `<think>`, Gemma 4's
thought channel or Mistral's `[THINK]`, the parser returns reasoning
separately from the reply. See
[Text generation and streaming](../guides/generation-and-streaming).

## Vision and audio

GGUF vision and audio need a matching projector (`mmproj`) file. Gemma 4 E2B
(vision and audio), Qwen3.5 (vision) and LFM2-VL (vision) are the families the
examples use. `.litertlm` bundles process media themselves. See
[Multimodal input](../guides/multimodal).

## Speech, embeddings and decision models

| Task | Model | Evidence | Repo |
| --- | --- | --- | --- |
| Speech to text (whole file) | Qwen3-ASR 0.6B | Validated | `ggml-org/Qwen3-ASR-0.6B-GGUF` |
| Speech to text (live, LiteRT-LM) | Moonshine Tiny | Validated | `litert-community/moonshine-tiny` |
| Text to speech | Qwen3-TTS 1.7B | Validated | `ggml-org/Qwen3-TTS-12Hz-1.7B-Base-GGUF` |
| Embeddings | EmbeddingGemma 300M | Used by the basic example | `ggml-org/embeddinggemma-300M-GGUF` |
| Decision models | Laya (ModernBERT) | Validated | `fr0stbit3/laya-gguf` |

See [Speech to text](../guides/speech-to-text),
[Text to speech](../guides/text-to-speech),
[Embeddings](../guides/embeddings) and
[Decision models](../guides/decision-models).

## If a family behaves oddly

1. Render the prompt with `engine.chatTemplate(...)` and compare it with the
   model card.
2. Check which format was detected: `ChatTemplateEngine.detectFormat(template)`.
3. For tool calls, try a family listed above as validated before debugging
   your own prompts.
4. Report the model repo and file in a
   [GitHub issue](https://github.com/leehack/llamadart/issues).
