# Reasoning in conversation history

The adapter intentionally keeps two representations:

| Representation | Policy |
| --- | --- |
| Streamed and final Genkit responses | Preserve reasoning as `ReasoningPart`, separately from the visible answer. |
| Genkit message history | Preserve the original reasoning, visible answer and tool exchanges. Conversion does not edit the caller's messages. |
| Messages supplied to a local runtime | Omit incoming `ReasoningPart` in every role. Preserve visible text and tool calls/results. A reasoning-only non-tool message becomes an empty message in the same role. |
| Thinking for the new response | Controlled independently by `enableThinking` and `thinkingBudget`, subject to runtime support. |

The same policy applies to ordinary multi-turn calls, automatic tool loops,
interrupt/resume and constrained output. It is independent of the backend's
ability to represent thinking content. There is no reasoning replay option.
Reasoning already embedded by the application in a `TextPart` is ordinary text;
the adapter does not parse or remove thought delimiters from text.

## Why omission is the supported contract

The [official Qwen3-1.7B model guidance](https://huggingface.co/Qwen/Qwen3-1.7B#best-practices)
recommends retaining final answers without historical thinking content. Its
template performs that omission, while integrations using other formatting must
apply the policy themselves. This supports the adapter's default for the Qwen3
family used in native qualification; it is not evidence that every model has the
same requirement.

The existence of llamadart's `LlamaThinkingContent` is a representation capability,
not a portable replay contract. Replaying reasoning could change turn boundaries,
tool continuation or template behavior. An opt-in would need primary guidance and
rendered-prompt qualification for each advertised model/template/backend family,
role validation, tools/resume tests and explicit unsupported/version-skew errors.
No such opt-in is advertised by this release. Applications requiring reasoning
replay must qualify a separate model integration rather than assuming this
adapter forwards it.

## Verification and privacy

Production-path tests cover streamed/final output, ordinary multi-turn history,
all input roles, reasoning-only messages, structured output, tool turns and
interrupt/resume. Deterministic template rendering verifies that the omitted
content cannot enter the prompt while visible answers remain. The existing
native Qwen3 thinking-budget smoke qualifies newly generated thinking controls;
these tests make no model-quality comparison or cross-family replay claim.

Reasoning remains sensitive even though it is omitted from later prompts.
Genkit history, application logs and observer callbacks can retain it; follow the
application's [telemetry policy](observability.md) and do not add raw reasoning to
adapter metrics or error diagnostics.
