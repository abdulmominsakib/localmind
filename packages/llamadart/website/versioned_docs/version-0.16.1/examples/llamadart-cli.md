---
title: llama.cpp-style CLI example
sidebar_label: llama.cpp-style CLI
description: A command-line tool with llama.cpp-style arguments built on llamadart, with parity tooling against upstream llama.cpp.
---

Path: `example/llamadart_cli` · Platforms: Dart CLI on macOS, Linux and
Windows

A terminal chat CLI that accepts llama.cpp-style arguments, with harnesses
that compare its output against upstream llama.cpp.

## Run

```bash
cd example/llamadart_cli
dart pub get
dart run bin/llamadart_cli.dart --model /path/to/model.gguf
```

Variants:

```bash
# Download from Hugging Face into ./models, with Unsloth's GLM settings
dart run bin/llamadart_cli.dart \
  -hf unsloth/GLM-4.7-Flash-GGUF:UD-Q4_K_XL \
  --jinja --ctx-size 16384 \
  --temp 1.0 --top-p 0.95 --min-p 0.01 --fit on

# One prompt from a file, in llama.cpp simple-io style
dart run bin/llamadart_cli.dart --model /path/to/model.gguf \
  --file prompt.txt --simple-io

# List every flag
dart run bin/llamadart_cli.dart --help
```

## What it demonstrates

- llama.cpp flag names and aliases (`-c`, `-ngl`, `-n`, `--top_p`) mapped
  onto `ModelParams` and `GenerationParams`
  ([Runtime parameters](../configuration/runtime-parameters)).
- `-hf repo[:file-hint]` resolution and download into a local model folder
  ([Downloads and cache](../guides/model-downloads)).
- Interactive streaming chat with a thinking stream and slash commands
  ([Generation and streaming](../guides/generation-and-streaming)).
- `--fit on`, which trims old turns and caps the output to the remaining
  context.
- Transcript parity against `llama-cli` and tool-call parity against
  `llama-server`, run through `example/llamadart_server`
  ([Tool calling](../guides/tool-calling)).

## Test

```bash
cd example/llamadart_cli
dart test
```

The real-model parity gates are tagged `local-only` and need local llama.cpp
builds and model files.

Full options: parity harness setup, environment overrides and CLI notes are in
the
[example README](https://github.com/leehack/llamadart/tree/main/example/llamadart_cli).
