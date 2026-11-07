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
}

/// Detects the [ChatFormat] by scanning a Jinja template source string
/// for signature tokens, following llama.cpp's priority order.
///
/// Returns [ChatFormat.contentOnly] if `templateSource` is null or empty.
/// Falls back to [ChatFormat.contentOnly] if no specific pattern is matched.
ChatFormat detectChatFormat(String? templateSource) {
  if (templateSource == null || templateSource.isEmpty) {
    return ChatFormat.contentOnly;
  }

  // DeepSeek V3.1
  if (templateSource.contains(
    "message['prefix'] is defined and message['prefix'] and thinking",
  )) {
    return ChatFormat.deepseekV3;
  }

  // DeepSeek R1
  if (templateSource.contains('<｜tool▁calls▁begin｜>')) {
    return ChatFormat.deepseekR1;
  }

  // Cohere2 MoE / North Code. Check before Command R7B because both use
  // <|START_ACTION|>, but START_TEXT is unique to the newer North template.
  if (templateSource.contains('<|START_TEXT|>') &&
      templateSource.contains('<|START_ACTION|>')) {
    return ChatFormat.cohere2Moe;
  }

  // MiniCPM5
  if (templateSource.contains('Tool usage guidelines:') &&
      templateSource.contains('<function name="') &&
      templateSource.contains('<param name="')) {
    return ChatFormat.minicpm5;
  }

  // Command R7B
  if (templateSource.contains('<|END_THINKING|><|START_ACTION|>')) {
    return ChatFormat.commandR7B;
  }

  // Granite
  if (templateSource.contains('elif thinking') &&
      templateSource.contains('<|tool_call|>')) {
    return ChatFormat.granite;
  }

  // GLM 4.5
  if (templateSource.contains('[gMASK]<sop>') &&
      templateSource.contains('<arg_key>') &&
      templateSource.contains('<arg_value>')) {
    return ChatFormat.glm45;
  }

  // Tencent Hunyuan V3
  if (templateSource.contains('<｜hy_User{}｜>') &&
      templateSource.contains('<tool_sep{}>') &&
      templateSource.contains('<arg_key{}>')) {
    return ChatFormat.hunyuanV3;
  }

  // Qwen3 Coder XML. Qwen3.6 uses the same generated
  // `<function=...><parameter=...>` envelope, but its template describes the
  // shape through its XML tool-call instruction instead of `<function>` and
  // `<parameters>` declaration tags.
  final hasQwenXmlToolEnvelope =
      templateSource.contains('<tool_call>') &&
      templateSource.contains('<function=') &&
      templateSource.contains('<parameter=');
  final hasQwen3CoderDeclarations =
      templateSource.contains('<function>') &&
      templateSource.contains('<parameters>');
  final hasQwen36ToolInstructions = templateSource.contains(
    'Function calls MUST follow the specified format',
  );
  if (hasQwenXmlToolEnvelope &&
      (hasQwen3CoderDeclarations || hasQwen36ToolInstructions)) {
    return ChatFormat.qwen3CoderXml;
  }

  // Xiaomi MiMo
  if (templateSource.contains('<tools>') &&
      templateSource.contains('# Tools') &&
      templateSource.contains('</tools>') &&
      templateSource.contains('<tool_calls>') &&
      templateSource.contains('</tool_calls>') &&
      templateSource.contains('<tool_response>')) {
    return ChatFormat.xiaomiMimo;
  }

  // EXAONE MoE
  if (templateSource.contains('<tool_call>') &&
      templateSource.contains('<tool_result>') &&
      templateSource.contains('<|tool_declare|>')) {
    return ChatFormat.exaoneMoe;
  }

  // Hermes 2 Pro / Qwen 2.5/3
  if (templateSource.contains('<tool_call>')) {
    return ChatFormat.hermes;
  }

  // GPT-OSS
  if (templateSource.contains('<|channel|>')) {
    return ChatFormat.gptOss;
  }

  // Seed-OSS
  if (templateSource.contains('<seed:think>')) {
    return ChatFormat.seedOss;
  }

  // Nemotron V2
  if (templateSource.contains('<SPECIAL_10>')) {
    return ChatFormat.nemotronV2;
  }

  // Apertus
  if (templateSource.contains('<|system_start|>') &&
      templateSource.contains('<|tools_prefix|>')) {
    return ChatFormat.apertus;
  }

  // LFM2 / LFM2.5. Upstream llama.cpp routes both the strict marker variant
  // and the plain "List of tools: [...]" variant when the template also emits
  // LFM tool-call delimiters.
  if ((templateSource.contains('List of tools: <|tool_list_start|>[') &&
          templateSource.contains(']<|tool_list_end|>')) ||
      (templateSource.contains('List of tools: [') &&
          templateSource.contains('<|tool_call_start|>') &&
          templateSource.contains('<|tool_call_end|>') &&
          !templateSource.contains('<|tool_list_start|>'))) {
    return ChatFormat.lfm2;
  }

  // MiniMax M2
  if (templateSource.contains(']~!b[') && templateSource.contains(']~b]')) {
    return ChatFormat.minimaxM2;
  }

  // Kimi K2
  if (templateSource.contains('<|im_system|>tool_declare<|im_middle|>') &&
      templateSource.contains('<|tool_calls_section_begin|>') &&
      templateSource.contains('## Return of')) {
    return ChatFormat.kimiK2;
  }

  // Apriel 1.5
  if (templateSource.contains('<thinking>') &&
      templateSource.contains('</thinking>') &&
      templateSource.contains('<available_tools>') &&
      templateSource.contains('<|assistant|>') &&
      templateSource.contains('<|tool_result|>') &&
      templateSource.contains('<tool_calls>[') &&
      templateSource.contains(']</tool_calls>')) {
    return ChatFormat.apriel15;
  }

  // Solar Open
  if (templateSource.contains('<|tool_response:begin|>') &&
      templateSource.contains('<|tool_response:name|>') &&
      templateSource.contains('<|tool_response:result|>')) {
    return ChatFormat.solarOpen;
  }

  // FunctionGemma
  if (templateSource.contains('<start_function_declaration>') ||
      templateSource.contains('<start_function_call>') ||
      templateSource.contains('<start_function_response>')) {
    return ChatFormat.functionGemma;
  }

  // TranslateGemma
  if (templateSource.contains('[source_lang_code]') &&
      templateSource.contains('[target_lang_code]')) {
    return ChatFormat.translateGemma;
  }

  // Functionary v3.2
  if (templateSource.contains('>>>all')) {
    return ChatFormat.functionaryV32;
  }

  // FireFunction v2
  if (templateSource.contains(' functools[')) {
    return ChatFormat.firefunctionV2;
  }

  // Functionary v3.1 (Llama 3.1)
  if (templateSource.contains('<|start_header_id|>') &&
      templateSource.contains('<function=')) {
    return ChatFormat.functionaryV31Llama31;
  }

  // Llama 3.x
  if (templateSource.contains('<|start_header_id|>ipython<|end_header_id|>')) {
    return ChatFormat.llama3;
  }

  // Magistral / Ministral
  if (templateSource.contains('[SYSTEM_PROMPT]') &&
      templateSource.contains('[TOOL_CALLS]') &&
      templateSource.contains('[ARGS]')) {
    return ChatFormat.ministral;
  }
  if (templateSource.contains('[THINK]') &&
      templateSource.contains('[/THINK]')) {
    return ChatFormat.magistral;
  }

  // Mistral Nemo
  if (templateSource.contains('[TOOL_CALLS]')) {
    return ChatFormat.mistralNemo;
  }

  // Gemma 3/3n
  if (templateSource.contains('<start_of_turn>') &&
      !templateSource.contains('<|im_start|>')) {
    return ChatFormat.gemma;
  }

  // Gemma 4
  if (templateSource.contains('<|turn>') &&
      templateSource.contains('<turn|>')) {
    return ChatFormat.gemma4;
  }

  // No recognized pattern
  return ChatFormat.contentOnly;
}
