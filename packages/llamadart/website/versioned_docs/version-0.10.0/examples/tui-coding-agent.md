---
title: TUI coding agent example
sidebar_label: TUI coding agent
description: "A small terminal coding agent built with nocterm and llamadart: one on-device model, one conversation and four general tools."
---

Path: `example/tui_coding_agent` · Platforms: Dart terminal app on macOS,
Linux and Windows · First-run download: `Qwen3.6-35B-A3B-UD-Q4_K_M.gguf`
(22.1 GB)

A small terminal coding agent built with `nocterm`: one model, one
conversation, one screen and four tools (`read`, `write`, `edit`, `bash`).

## Run

```bash
cd example/tui_coding_agent
dart pub get
dart run bin/tui_coding_agent.dart
```

The default model targets systems with at least 32 GB of RAM.

Variants:

```bash
# Another project, with only the read tool
dart run bin/tui_coding_agent.dart --workspace /path/to/project --read-only

# Qwen thinking with a 32K context (at least 48 GB of memory)
dart run bin/tui_coding_agent.dart --thinking

# A local GGUF, HTTP(S) URL or hf:// source instead of the default
dart run bin/tui_coding_agent.dart --model /path/to/model.gguf
```

:::warning Unsandboxed shell

`bash` runs with your normal permissions and can reach files outside the
workspace, the environment and the network. Only the file tools are confined
to the workspace. Use trusted prompts and repositories, or run the demo in a
sandbox or container.

:::

## What it demonstrates

- A sequential agent loop: each reply is a final answer or exactly one
  `<tool_call>` JSON envelope, which the agent runs before sending the result
  back ([Tool calling](../guides/tool-calling)).
- Streaming Markdown answers, with reasoning streamed separately under
  `[think]` in `--thinking` mode
  ([Generation and streaming](../guides/generation-and-streaming)).
- Qwen3.6 presets built from `ModelParams` and `GenerationParams`, including
  presence penalty and explicit batch sizes
  ([Performance tuning](../guides/performance-tuning)).
- An exact `hf://` source passed to `LlamaEngine.loadModelSource`, with
  resumable downloads into the shared cache
  ([Downloads and cache](../guides/model-downloads)).
- Cancellable downloads, generation and shell process trees, with bounded
  tool output, context use and tool rounds.
- Workspace-confined file tools and a `--read-only` mode that exposes only
  `read`.

## Test

```bash
cd example/tui_coding_agent
dart test
```

Full options: the sampling presets, tool contract, slash commands and trust
boundary are in the
[example README](https://github.com/leehack/llamadart/tree/main/example/tui_coding_agent).
