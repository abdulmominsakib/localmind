# Closed-thought upstream parses

`closed_thought_upstream.json` records how llama.cpp parses output after a
prompt that ends with an empty thought, for issue #750.

The templates are the vendored DeepSeek V3.1, Qwen3 4B, QwQ 32B and Qwen3.5
0.8B templates. With thinking off, each ends its generation prompt with an
empty thought: `<think></think>`, `<think>\n</think>` or
`<think>\n\n</think>\n\n`.

`upstream` comes from a probe built from unchanged llama.cpp
`620d2225cc436ab0b001e3200e590e3b286ef9ab`, the source of the pinned native
runtime `v0.7.0-2`. With no model loaded, it called `common_chat_templates_init`
on the template, built a `common_chat_session` from one user message, the
`weather` tool, `enable_thinking = false` and `COMMON_REASONING_FORMAT_AUTO`
(format `peg-native`), and called `finish` on the whole output. Feeding the
output one byte at a time before `finish` gave the same result for every case.
No case has reasoning: thinking tags are content.

For issue #1531 the same probe, rebuilt from llama.cpp
`cd959bae99ff4bed22bef2604f45241c09bbb8c8` (native `v0.9.0`), reproduced every
case but the StepFun thoughts, whose trailing whitespace it now trims, and the
Seed-OSS `unfinished-end-tag`: since `a71c00f0b` a finished output keeps the
start of a tag it ends in. Those record the newer result, and the
`partial-tag-at-end` and `partial-call-opening-at-end` cases were added with
it: content that ends in the start of a tag keeps it. The Seed-OSS
`unfinished-*` cases' `upstream_partial` is the same probe's
`common_chat_peg_parse` with `is_partial = true`, which still drops the start
of an end tag.

With the Bielik 11B v3 or Spark 2.5 templates, whose prompts end without an
empty thought when thinking is off, the same probe still parses a leading
`<think>` thought, so llamadart keeps parsing thoughts there.

`open_thought_templates` holds the vendored StepFun3.5-Flash template, whose
generation prompt ends with `<think>\n` whatever the thinking flag. The same
probe parses its reply's leading thought as reasoning. Each case also records
`upstream_without_tools`, the probe run without the tool. llamadart closes
this thought in the prompt when thinking is off, but still parses the reply
as llama.cpp does.

`open_thought_templates` also holds the vendored Cohere2 MoE template. llama.cpp
sets no `reasoning`, so its generation prompt ends with `<|START_THINKING|>`;
llamadart sets `reasoning: false` with thinking off and the template closes the
thought. The same probe, run without the tool too, parses the reply's leading
thought as reasoning. Cases the probe rejects without the tool (`does not match
the expected peg-native format`) have no `upstream_without_tools`. Each entry's
`closed_prompt_suffix` is how llamadart's thinking-off prompt ends.

For issue #1858, `no_thought_templates` also holds the vendored Hermes 2 Pro,
Qwen3-Coder and Qwen3 4B templates, recorded with the same probe at
`cd959bae9`. None opens a thought (Qwen3 4B with `enable_thinking = true`, the
entry's `enable_thinking`; the other two render the same prompt with either
flag, which the probe confirmed). Their cases end a thought the reply did not
open: llama.cpp keeps that end tag and every thinking tag after it as content.
Feeding the output one byte at a time and calling `finish` alone gave the same
result for every case. `upstream_partial` is again `common_chat_peg_parse` with
`is_partial = true`. The Hermes 2 Pro and Qwen3-Coder templates have no
`thought` case: with no reasoning in the template, llama.cpp keeps even a
leading thought as content, which llamadart does not.

For issue #1865, `no_thought_templates` adds one vendored template per format
that takes a thought only at the start of the reply after a prompt that opens
no thought, recorded with the same probe at `cd959bae9`: Gemma 2 and SmolLM3
(generic), Llama 3.2, GLM-4.6, Laguna XS.2, LFM2-8B-A1B, Kimi K2, DeepSeek R1
Distill Qwen 32B, V3.2 and V4, Granite 3.3, MiniCPM5, Mistral Nemo, Apertus and
Hunyuan V3 (`tencent-Hy3`), with thinking flags under which llamadart opens no
thought. It also adds cases to the #1858 entries. Besides a thought that the
reply did not open, the cases put a start tag after text and tags after a
leading thought: llama.cpp takes a thought only where the reply starts with the
start tag and keeps every other thinking tag as content. The `thought`,
`*-after-thought*` cases appear only for templates whose reasoning llama.cpp
parses; with the others it keeps even a leading thought as content, which
llamadart does not. Two differences outside #1865 are left out: Kimi K2 with
the tool takes no thought after leading whitespace, and LFM2's partial parse
drops a trailing partial end tag after content.

For issue #1887, `no_thought_templates` adds the vendored MiniMax M3 template
twice, recorded with the same probe at `cd959bae9`: with thinking off and no
kwargs, as llamadart renders it by default, and with thinking on and
`thinking_mode: adaptive`. Neither prompt opens a thought in llama.cpp
(`]~b]ai\n`) or llamadart, which also ends its thinking-off prompt with
`</mm:think>`; the probe parsed the thinking-off cases the same with
`thinking_mode: disabled`. llama.cpp takes a thought only where `<mm:think>`
starts the reply with no whitespace before it, drops a `</mm:think>` there, and
keeps every other thinking tag as content. With thinking off it drops a leading
thought instead of returning it as reasoning: those cases are in
`dropped_thought_cases`, where the engine streams no reasoning and
`parseRendered` still returns it. Partial parses with a trailing partial
thinking tag after content are left out: MiniMax M3's partial parse drops it.
