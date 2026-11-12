import 'chat_format_registry.dart';

/// Identifies the chat format detected from a model's template source.
///
/// Each format corresponds to a specific model family's tool calling
/// convention, with dedicated rendering and parsing logic.
///
/// See llama.cpp's `common_chat_format` enum for the reference implementation.
enum ChatFormat {
  /// No tool call support — plain text-only models.
  contentOnly,

  /// ChatML-based generic handler (JSON tool call wrapping).
  /// Fallback for models using `<|im_start|>/<|im_end|>` without
  /// a more specific tool call format.
  generic,

  /// Mistral Nemo — `[TOOL_CALLS]` prefix with JSON array.
  mistralNemo,

  /// Magistral — `[THINK]`/`[/THINK]` thinking + `[TOOL_CALLS]` prefix.
  magistral,

  /// Llama 3.x — ipython role with `<|python_tag|>` optional builtin tools.
  llama3,

  /// Llama 3.x builtin-tools variant.
  llama3BuiltinTools,

  /// DeepSeek R1 — fullwidth unicode delimiters.
  deepseekR1,

  /// FireFunction v2 — `functools[...]` JSON tool-call arrays.
  firefunctionV2,

  /// Functionary v3.2 — `>>>name` / `>>>all` tool-call blocks.
  functionaryV32,

  /// Functionary v3.1 Llama 3.1 — `<function=name>{...}</function>`.
  functionaryV31Llama31,

  /// DeepSeek V3.1 — prefix-based thinking with `<tool_call>` tags.
  deepseekV3,

  /// Hermes 2 Pro / Qwen 2.5 / Qwen 3 — `<tool_call>` XML tags.
  hermes,

  /// Command R7B — `<|START_ACTION|>/<|END_ACTION|>` with thinking.
  commandR7B,

  /// Granite — `<|tool_call|>` + JSON array with `<think>` support.
  granite,

  /// GPT-OSS assistant channel/message format.
  gptOss,

  /// Seed OSS format with `<seed:think>` and XML tool blocks.
  seedOss,

  /// Nemotron V2 format with `<TOOLCALL>` JSON blocks.
  nemotronV2,

  /// Apertus format with `<|tools_prefix|>` and `<|tools_suffix|>`.
  apertus,

  /// LFM2 / LFM2.5 — `<|tool_call_start|>/<|tool_call_end|>` special tokens.
  lfm2,

  /// GLM 4.5 — `<|observation|>` with XML-style arg_key/arg_value.
  glm45,

  /// MiniMax M2 — `<minimax:tool_call>` with `<invoke>` tags.
  minimaxM2,

  /// Kimi K2 — `<|tool_call_begin|>` with special tokens.
  kimiK2,

  /// Qwen3 Coder XML — `<function=name><parameter=key>` format.
  qwen3CoderXml,

  /// Apriel 1.5 format with `<thinking>` and `<tool_calls>`.
  apriel15,

  /// Xiaomi MiMo format with `<tool_call>` JSON blocks.
  xiaomiMimo,

  /// Solar Open format with `<|think|>` and tool response markers.
  solarOpen,

  /// EXAONE MoE format with `<tool_call>` blocks and thinking tags.
  exaoneMoe,

  /// PEG simple parser-backed format.
  pegSimple,

  /// PEG native parser-backed format.
  pegNative,

  /// PEG constructed parser-backed format.
  ///
  /// Retains llama.cpp's historical `peg-constructed` name and XML mapper;
  /// upstream removed this format before b10549. Used by Qwen3 Coder XML.
  pegConstructed,

  /// FunctionGemma — `<start_function_call>call:name{args}<end_function_call>`.
  functionGemma,

  /// Gemma 3 / Gemma 3n — `<start_of_turn>/<end_of_turn>` with
  /// prompt-engineered tool calling and multimodal support.
  gemma,

  /// Gemma 4 — `<|turn>/<turn|>` with optional `<|channel>` reasoning blocks
  /// and `<|tool_call>call:name{args}<tool_call|>` tool calling.
  gemma4,

  /// TranslateGemma format with language-code message content fields.
  translateGemma,

  /// Ministral 3 reasoning format with `[TOOL_CALLS]name[ARGS]{...}`.
  ministral,

  /// Cohere2 MoE / North Code — `<|START_TEXT|>` content or
  /// `<|START_ACTION|>` JSON tool arrays after thinking.
  cohere2Moe,

  /// MiniCPM5 — ChatML turns with `<function name="...">` XML tool calls.
  minicpm5,

  /// Hunyuan V3 — namespaced thinking and XML-like argument tool calls.
  hunyuanV3,

  /// Kimi K3 — XTML response, reasoning, and typed tool-call sections.
  kimiK3,

  /// MiniMax M1 — newline-delimited JSON calls inside `<tool_calls>`.
  minimaxM1,

  /// MiniMax M3 — namespaced XML invokes with `<mm:think>` reasoning.
  minimaxM3,

  /// DeepSeek V4 — DSML `tool_calls` with typed parameter values.
  deepseekV4,

  /// Muse Glimmer — recipient channels with ATEM function-call markup.
  museGlimmer,

  /// Poolside Laguna — tagged reasoning and arg-key/value tool calls.
  laguna,

  /// DeepSeek V3.2 — DSML `function_calls` with typed parameter values.
  ///
  /// Appended to preserve the serialized indices of existing formats.
  deepseekV32,

  /// Ling 3.0 (Bailing V3) — `<role>` turns with `<tool_call>name` and
  /// `<arg_key>`/`<arg_value>` tool calls.
  ling3,
}

/// Detects the [ChatFormat] by scanning a Jinja template source string
/// for signature tokens, in the priority order of [chatFormatRegistrations].
///
/// Returns [ChatFormat.contentOnly] if `templateSource` is null or empty.
/// Falls back to [ChatFormat.contentOnly] if no specific pattern is matched.
ChatFormat detectChatFormat(String? templateSource) {
  if (templateSource == null || templateSource.isEmpty) {
    return ChatFormat.contentOnly;
  }
  for (final registration in chatFormatRegistrations) {
    if (registration.detect?.call(templateSource) ?? false) {
      return registration.format;
    }
  }
  return ChatFormat.contentOnly;
}
