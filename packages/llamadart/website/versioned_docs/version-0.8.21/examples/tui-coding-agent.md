---
title: TUI Coding Agent Example
---

Path: `example/tui_coding_agent`

This example is a deliberately small, Pi-style local coding agent built with
`nocterm` and `llamadart`. It uses one model, one in-memory conversation, one
screen, and four general tools.

## Run

```bash
cd example/tui_coding_agent
dart pub get
dart run bin/tui_coding_agent.dart
```

Select a different workspace, model, or cache only at startup:

```bash
dart run bin/tui_coding_agent.dart --workspace /path/to/project
dart run bin/tui_coding_agent.dart --read-only
dart run bin/tui_coding_agent.dart --thinking
dart run bin/tui_coding_agent.dart --model /path/to/model.gguf
dart run bin/tui_coding_agent.dart \
  --model hf://owner/repo/path/to/model.gguf
dart run bin/tui_coding_agent.dart --cache-dir /path/to/model-cache
```

The default model is the native-desktop Qwen3.6 35B-A3B Unsloth
`UD-Q4_K_M` GGUF at
`hf://unsloth/Qwen3.6-35B-A3B-GGUF/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf`, intended
for systems with at least 32 GB of RAM. Its
non-thinking preset uses a 16,384-token context, up to 4,096 output tokens,
an explicit logical batch size of `2,048` and physical micro-batch size of
`512`, temperature `0.7`, top-K `20`, top-P `0.8`, min-P `0`, repeat penalty
`1.0`, presence penalty `1.5`, and at most 24 tool rounds.

`--thinking` is an explicit quality-over-latency profile for coding tasks. It
enables Qwen reasoning with a 32,768-token context, up to 8,192 output tokens,
the same explicit `2,048` logical batch and `512` physical micro-batch,
temperature `0.6`, top-K `20`, top-P `0.95`, min-P `0`, and zero presence
penalty. It is intended for systems with at least 48 GB of available unified
memory or RAM; the 32K context preserves practical headroom on a 64 GB Apple
Silicon system, where 48K and 64K contexts can exhaust Metal allocations.
Non-thinking remains the default because it reaches actionable
tool calls faster, uses substantially less context, and is less likely to spend
the output budget before producing the strict final tool-call envelope.
The sampling values follow the published
[Qwen3.6 model guidance](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF#best-practices)
for non-thinking general use and thinking-mode precise coding.

Qwen3.6 has a real thinking on/off switch but no model-trained
low/medium/high reasoning-effort levels. This example exposes only the real
control: `--thinking` enables reasoning and its coding sampler; omitting the
flag disables it. Thinking mode also passes Qwen's `preserve_thinking` template
option so reasoning can be reused across agent tool rounds. Upstream llama.cpp
has a separate hard reasoning-token budget, but llamadart's embedded API does
not currently expose it, and the example does not mislabel total output tokens
as reasoning effort.

The session passes its exact `hf://` source to
`LlamaEngine.loadModelSource`, which owns resolution, resumable downloads, and
the shared per-user cache. `--cache-dir` is an optional override. An earlier
flat `UD-Q4_K_S` TUI file remains usable by passing its local path explicitly;
it is not substituted for the new K_M default.

## One sequential loop

Each model response is either a normal final answer or exactly one standalone
JSON tool call:

```text
<tool_call>{"name":"tool_name","arguments":{...}}</tool_call>
```

The agent executes that call, sends its JSON result back to the model, and
repeats. It never executes sibling calls or calls mixed with prose. Malformed,
incomplete, shorthand, XML, alias, and unknown-tool forms are rejected.

The model normally receives exactly four tools:

- `read` reads bounded UTF-8 text from a workspace file.
- `write` creates or overwrites a workspace file.
- `edit` replaces exactly one literal match.
- `bash` runs a command with Bash on Unix or `cmd.exe` on Windows.

With `--read-only`, only `read` is exposed; `write`, `edit`, and `bash` are not
included in the model prompt or parser allowlist.

Applicable `AGENTS.md` files are loaded once at startup as prompt context.

## UI and limits

The TUI is one TurboVision-inspired blue framed window, transcript, input, and
gray status line for a single session. It deliberately restores the visual
identity without restoring the earlier multi-window desktop. Model selection
happens only at startup. `/clear` resets conversation history, `/model` reports
the active model, `/workspace` reports the root, and `/cancel` or `Esc` cancels
active work. `Ctrl+C` cancels while busy and exits cleanly while idle.

Normal answers stream incrementally through a compact GitHub-flavored Markdown
renderer with headings, lists, links, inline code, and syntax-highlighted fenced
code. Fences use their language label when available, recognize a small set of
common unlabelled formats, and safely fall back to plain code. Their background
fills empty lines as well as text rows, and Markdown blocks plus transcript
messages do not insert automatic blank spacer rows. With `--thinking`, reasoning
streams independently under `[think]`; the final Markdown answer stays under
`[agent]`. Potential split `<tool_call>` prefixes are withheld until the strict
envelope parser has classified them, so executable JSON is not rendered as
assistant prose. High-frequency deltas are coalesced to terminal frame cadence
and accumulated in buffers. Off-screen transcript rows are built lazily, while
the active Markdown row is reparsed only at presentation cadence rather than for
every burst of backend deltas. Highlighting is bounded for unusually large
generated blocks so streaming stays responsive.

Model resolution and downloads, generation, and the active shell process tree
are cancellable. Native model allocation itself cannot be interrupted; a
cancellation requested during that phase is acknowledged by unloading as soon
as allocation returns. File and tool output, command duration, context use, and
tool rounds are bounded. The `read`, `write`, and `edit` tools resolve paths
canonically and reject paths or symlink targets outside the workspace.

Cancellation does not roll back effects that already occurred. The transcript
shows each command or file path, a bounded result summary, and a durable warning
when an interrupted tool may have changed state.

:::warning Unsandboxed shell

`bash` runs with the current user's normal permissions. It can access or
modify files outside the workspace, use the environment and network, and start
arbitrary child processes. File-tool path confinement does not sandbox shell
commands. Use trusted prompts and repositories, or run the entire demo inside
an external sandbox or container.

:::
