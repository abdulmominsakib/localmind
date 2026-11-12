# Flint template rendering reference

`Flint.jinja` is the exact `tokenizer.chat_template` returned by `/props` for
[ggml-org/Flint-GGUF](https://huggingface.co/ggml-org/Flint-GGUF/tree/468307a1b38259e9e4c9d4fe53d4e3b76386572c),
`Flint-Q4_K_M.gguf`, captured on 2026-10-23. The model template is Apache-2.0 licensed; see `LICENSE` in this directory.
`render_upstream.json` records the model revision, model and template SHA-256,
and each request and prompt returned by `POST /apply-template` from the official
macOS arm64 llama.cpp b11836 build at
`f5027fb21307eb264aed483242603d68c87b0fe3`.

The server loaded this model with Metal, context 8192, one slot, 12 threads,
flash attention enabled, `--no-warmup` and `--cache-ram 0`. No generation was
needed to capture these prompts. The tool-history fixture records OpenAI JSON
argument strings as sent to the server; the test decodes them to objects as
llama.cpp does before rendering.

The cases cover basic and system chat, assistant history, literal backslash
escapes and Unicode, NUL removal and protocol-marker escaping, tool definitions,
and tool-result history. These are template-rendering references, not model,
output-parser or native-runtime qualification. They pin the lexer failure in
[llamadart #1335](https://github.com/leehack/llamadart/issues/1335).
