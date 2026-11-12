# LFM2 quoted tool delimiter fixtures

The upstream fixture captures unchanged llama.cpp `8642541b255bfb5dc39cd351a178be09013a55d6`
(`v0.8.0`, consumed by native `v0.8.0-1` and bridge `v0.1.79`).
`common_chat_templates_apply`, `common_chat_peg_parse` and
`common_chat_session` receive the recorded request and identical raw outputs.
The LFM2 Tool and LFM2.5 Thinking template byte hashes are included. The parser
source files were checked byte-for-byte against that upstream Git object and
compiled directly for the capture. These are parser emissions, not model
samples or browser-runtime qualification.

Upstream preserves a quoted `<|tool_call_end|>` in Python-call arguments,
including a parallel second call; whole and bytewise sessions agree. Under
these templates it rejects the recorded JSON-form envelope and surrounding
prose. Dart already accepts both, and the repair retains that deliberate
acceptance rather than adopting the upstream rejection.

The compatibility fixture records malformed/unclosed-quote behavior on core
`4432c7538ad04e15727e048d49003c10ab7e7c01`. Existing loose parsing can accept
unclosed argument quotes and strip malformed envelopes. Those policies remain
unchanged here; #1610 owns a schema-directed parser redesign.

The maintained local-only test also generates the quoted marker through the
existing required-tool JSON grammar, using a single enum value to make the
literal deterministic. It separately checks public `LlamaEngine.create`.
Existing cached macOS CPU weights passed:

| Model | SHA-256 |
| --- | --- |
| LFM2-1.2B-Tool-Q4_K_M | `3a942f51f9f3088c0b502b61ee49480a3d8c54de369f9c53ee5668419caf67a7` |
| LFM2.5-1.2B-Instruct-Q4_K_M | `b1b3de114215d9507409a662a501a631095a479a419584e8a2ded6304b19b4f5` |

Both emitted a JSON tool envelope containing `"city": "a<|tool_call_end|>b"`
followed by the real closing delimiter. This does not establish upstream
JSON-form acceptance, unconstrained model instruction-following, GPU or device
coverage. No grammar, escape, schema or tool-choice policy changes are made.

To repeat with existing weights and the pinned SDK:

```bash
LLAMADART_LFM2_MARKER_MODEL=/path/to/LFM2-1.2B-Tool-Q4_K_M.gguf \
LLAMADART_LFM25_MARKER_MODEL=/path/to/LFM2.5-1.2B-Instruct-Q4_K_M.gguf \
TMPDIR="$(mktemp -d)" dart test -p vm -j 1 --run-skipped -t local-only \
  test/e2e/template/lfm2_quoted_tool_delimiter_e2e_test.dart
```

The test never downloads weights and reports a missing model as skipped.
