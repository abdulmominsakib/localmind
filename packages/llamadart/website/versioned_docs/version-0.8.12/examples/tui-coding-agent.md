---
title: TUI Coding Agent Example
---

Path: `example/tui_coding_agent`

This example builds a local coding-agent workflow in a terminal UI using
`nocterm` + `llamadart`.

## Run

```bash
cd example/tui_coding_agent
dart pub get
dart run bin/tui_coding_agent.dart
```

Default model source:

- `unsloth/GLM-4.7-Flash-GGUF:UD-Q4_K_XL`

Default tool mode is stable text-protocol tool calling. Native template grammar
tool-calling is optional:

```bash
dart run bin/tui_coding_agent.dart --native-tool-calling
```

Override at startup:

```bash
dart run bin/tui_coding_agent.dart --model /path/to/model.gguf
```

## Interactive commands

- `/help`
- `/clear`
- `/model`
- `/model <path|url|owner/repo[:hint]>`
- `/workspace`
- `/cancel`
- `/exit`

## What it demonstrates

- Streaming assistant output in a TUI chat layout.
- Tool-calling loop for coding tasks.
- Workspace-safe file and command operations.
- Runtime model switching without restarting the process.
- Optional native tool-calling mode for template-parity experiments.
