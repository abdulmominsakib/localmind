# enable_thinking render reference

`enable_thinking_render_upstream.json` holds the prompts that an unmodified
`llama-server` built from llama.cpp `620d2225c` (the pinned runtime) returned
from `POST /apply-template` for the templates whose text prompt depends on
`enable_thinking` but whose handler did not set it
([#1465](https://github.com/leehack/llamadart/issues/1465)). llama.cpp gives
every template `enable_thinking` (`common/chat.cpp`), so `enableThinking`
alone must reach them.

Each request sent `messages` and, for `tools: true` cases, `tools`, with
`chat_template_kwargs: {"enable_thinking": <enable_thinking>}`. The server ran
with `--jinja --chat-template-file <template> -c 1024 -ngl 0 --no-warmup` on
`model` (sha256 `model_sha256`), which only supplies `bos_token` and
`eos_token`.

`test/unit/core/template/enable_thinking_render_parity_test.dart` renders each
case through `ChatTemplateEngine.render` with `enableThinking` and no kwargs
and expects the exact prompt, and a forced-open thought exactly when thinking
is on and the prompt ends with `<think>`.

SmolLM3 and RWKV World with tools are left out: they route through the generic
tool format, whose system instruction differs from llama-server's independently
of `enable_thinking`.
