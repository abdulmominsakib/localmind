---
title: llama.cpp-Style CLI Example
---

Path: `example/llamadart_cli`

A compatibility-oriented CLI with llama.cpp-style arguments and parity tooling.

## Run

```bash
cd example/llamadart_cli
dart pub get
dart run bin/llamadart_cli.dart --help
```

## Common usage

Interactive run:

```bash
dart run bin/llamadart_cli.dart --model /path/to/model.gguf
```

Hugging Face shorthand:

```bash
dart run bin/llamadart_cli.dart -hf unsloth/GLM-4.7-Flash-GGUF:UD-Q4_K_XL
```

## What it demonstrates

- CLI-first interaction model.
- Sampling and context controls.
- Prompt-file and simple-io compatibility modes.
- Transcript/tool-call parity harness integration.
