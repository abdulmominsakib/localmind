import 'chat_format.dart';
import 'chat_parse_result.dart';
import 'chat_template_handler.dart';
import 'handlers/apertus_handler.dart';
import 'handlers/apriel15_handler.dart';
import 'handlers/cohere2_moe_handler.dart';
import 'handlers/command_r7b_handler.dart';
import 'handlers/deepseek_dsml_handler.dart';
import 'handlers/deepseek_r1_handler.dart';
import 'handlers/deepseek_v3_handler.dart';
import 'handlers/exaone_moe_handler.dart';
import 'handlers/firefunction_v2_handler.dart';
import 'handlers/function_gemma_handler.dart';
import 'handlers/functionary_v31_llama31_handler.dart';
import 'handlers/functionary_v32_handler.dart';
import 'handlers/gemma4_handler.dart';
import 'handlers/gemma_handler.dart';
import 'handlers/generic_handler.dart';
import 'handlers/glm45_handler.dart';
import 'handlers/gpt_oss_handler.dart';
import 'handlers/granite_handler.dart';
import 'handlers/hermes_handler.dart';
import 'handlers/hunyuan_v3_handler.dart';
import 'handlers/kimi_k2_handler.dart';
import 'handlers/kimi_k3_handler.dart';
import 'handlers/laguna_handler.dart';
import 'handlers/lfm2_handler.dart';
import 'handlers/ling3_handler.dart';
import 'handlers/llama3_handler.dart';
import 'handlers/magistral_handler.dart';
import 'handlers/minicpm5_handler.dart';
import 'handlers/minimax_m1_m3_handler.dart';
import 'handlers/minimax_m2_handler.dart';
import 'handlers/ministral_handler.dart';
import 'handlers/mistral_handler.dart';
import 'handlers/muse_glimmer_handler.dart';
import 'handlers/nemotron_v2_handler.dart';
import 'handlers/qwen3_coder_xml_handler.dart';
import 'handlers/seed_oss_handler.dart';
import 'handlers/solar_open_handler.dart';
import 'handlers/translate_gemma_handler.dart';
import 'handlers/xiaomi_mimo_handler.dart';
import 'thinking_utils.dart';
import 'xml_tool_call_format.dart';

/// How one [ChatFormat] is detected from a template and which handler
/// renders and parses it.
final class ChatFormatRegistration {
  /// Registers [format], created by [createHandler], matched by [detect] and
  /// routed and streamed by [traits].
  const ChatFormatRegistration(
    this.format,
    this.createHandler, {
    this.detect,
    required this.traits,
  });

  /// The format this registration describes.
  final ChatFormat format;

  /// Creates the handler for [format].
  final ChatTemplateHandler Function() createHandler;

  /// Whether a template source is in [format], or null for a format the
  /// engine selects itself and no template detects.
  final bool Function(String templateSource)? detect;

  /// How the engine routes and the stream parser streams [format].
  final ChatFormatTraits traits;
}

/// Whether a final parse of `output` into `result` left a malformed or
/// incomplete tool call behind.
typedef IncompleteToolCallCheck =
    bool Function(
      ChatParseResult result,
      String output, {
      required bool thinkingForcedOpen,
    });

/// Per-format routing and streaming behavior, kept with the format's
/// registration rather than in tables in the engine or stream parser.
final class ChatFormatTraits {
  /// Traits with explicitly declared schema qualification.
  const ChatFormatTraits({
    required this.qualifiesJsonSchemaTools,
    this.toolCallOpening,
    this.keepsThoughtTagsAsContent = false,
    this.parsesCallsInsideThoughts = false,
    this.keepsForcedThoughtVerbatim = false,
    this.closedThoughtKeepsTagsAsContent = false,
    this.takesThoughtOnlyAtReplyStart = false,
    this.thoughtStartsReplyExactly = false,
    this.reopensThoughtClosedForThinkingOff = false,
    this.forcedThoughtContentOpenings = const [],
    this.budgetThoughtClosePrefix = '',
    this.mayEmbedToolEnvelopeAfterContent = false,
    this.retainsTextAroundToolCalls = false,
    this.endsThoughtAtToolCallOpening = false,
    this.hasRepeatedContentChannels = false,
    this.disabledByResponseSchema = false,
    this.requiredKeepsLazyGrammar = false,
    this.routesThroughGeneric = false,
    this.toolChoiceNoneRendersContentOnly = false,
    this.rendersToolResultContent = false,
    this.leavesIncompleteToolCall,
  });

  /// A format with every trait off.
  static const ChatFormatTraits none = ChatFormatTraits(
    qualifiesJsonSchemaTools: false,
  );

  /// For a format whose parse drops tool-call envelopes from trimmed content,
  /// the index of the first possible tool-call opening in `text` at or after
  /// `from`, or `text.length`; the stream holds content back from there.
  final int Function(String text, int from)? toolCallOpening;

  /// Whether the parse extracts no reasoning, so thought tags stream as
  /// content.
  final bool keepsThoughtTagsAsContent;

  /// Whether the parse extracts tool calls before thinking, so a call inside
  /// a thought leaves the reasoning.
  final bool parsesCallsInsideThoughts;

  /// Whether the parse keeps a forced-open thought as generated up to the
  /// first end tag, with escapes and a repeated start tag, and takes the rest
  /// as content in which thinking tags are text.
  final bool keepsForcedThoughtVerbatim;

  /// Whether, after a prompt that ends with a closed thought, the parse
  /// extracts no reasoning, so thinking tags are content.
  final bool closedThoughtKeepsTagsAsContent;

  /// Whether, after a prompt that opens no thought, the parse takes a thought
  /// only at the start of the reply, so other thinking tags are content.
  final bool takesThoughtOnlyAtReplyStart;

  /// Whether, with [takesThoughtOnlyAtReplyStart], the thought must start the
  /// reply with no whitespace before it, and an end tag that starts the reply
  /// is dropped as an empty thought.
  final bool thoughtStartsReplyExactly;

  /// Whether llama.cpp keeps open the thought the handler closed for thinking
  /// off, so a reply that shows a thinking tag or one of
  /// [forcedThoughtContentOpenings] parses as after a forced-open prompt.
  final bool reopensThoughtClosedForThinkingOff;

  /// Markers that, with [keepsForcedThoughtVerbatim], also end a forced-open
  /// thought when they come before its end tag, and start the content.
  final List<String> forcedThoughtContentOpenings;

  /// Text a thinking budget forces before the end tag when it closes a
  /// thought, as llama.cpp forces the first of the format's end sequences.
  final String budgetThoughtClosePrefix;

  /// Whether a tool envelope may follow content, so a stream with tools
  /// parses from its first token instead of deciding from how output starts.
  final bool mayEmbedToolEnvelopeAfterContent;

  /// Whether the parse keeps the text around tool calls as content, so a
  /// reply that starts with a call still streams the content it returns.
  final bool retainsTextAroundToolCalls;

  /// Whether the parse ends a forced-open thought at a tool-call opening even
  /// when tool calls are not parsed, so the stream needs the parse then too.
  final bool endsThoughtAtToolCallOpening;

  /// Whether accepted replies can repeat content channels whose fragments must
  /// be joined and whose framing must be parsed even without tool calling.
  final bool hasRepeatedContentChannels;

  /// Whether a response schema disables the format's handler, as in
  /// llama.cpp: rendering falls back to generic with tool calls and to
  /// content-only without.
  final bool disabledByResponseSchema;

  /// Whether a lazy tool grammar stays lazy for `ToolChoice.required`.
  final bool requiredKeepsLazyGrammar;

  /// Whether llama.cpp has no Jinja handler for the format, so it renders
  /// as generic with tool calls and as content-only without.
  final bool routesThroughGeneric;

  /// Whether tools with `ToolChoice.none` render content-only, as llama.cpp's
  /// Jinja dispatcher does unless a response schema forces generic routing.
  final bool toolChoiceNoneRendersContentOnly;

  /// Whether the format is qualified to render `LlamaToolResultContent`
  /// `content` in the tool turn, with a media marker at each media part.
  final bool rendersToolResultContent;

  /// Detects a tool call that a final parse left malformed or incomplete.
  final IncompleteToolCallCheck? leavesIncompleteToolCall;

  /// Whether canonical JSON Schema tools are qualified for the format.
  /// Changing incomplete-call detection must not change schema admission.
  final bool qualifiesJsonSchemaTools;
}

/// Every [ChatFormat], each exactly once, in detection priority order: the
/// first registration whose [ChatFormatRegistration.detect] matches a
/// template wins, following llama.cpp's order. A detector placed earlier
/// shadows every later one whose markers it shares.
final List<ChatFormatRegistration>
chatFormatRegistrations = List.unmodifiable(<ChatFormatRegistration>[
  // Keep Kimi K3 separate from Kimi K2: K3 uses XTML tags and typed
  // arguments rather than K2's tool-call-section tokens.
  ChatFormatRegistration(
    ChatFormat.kimiK3,
    KimiK3Handler.new,
    detect: (s) =>
        _hasAll(s, const ['<|open|>', '<|close|>', '<|end_of_msg|>']),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      mayEmbedToolEnvelopeAfterContent: true,
    ),
  ),
  // Recipient channels and ATEM calls.
  ChatFormatRegistration(
    ChatFormat.museGlimmer,
    MuseGlimmerHandler.new,
    detect: (s) => _hasAll(s, const ['<atem:function_calls>', '<|eom|>']),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      mayEmbedToolEnvelopeAfterContent: true,
    ),
  ),
  // Before Hermes: the namespaced envelope contains a literal <tool_call>.
  ChatFormatRegistration(
    ChatFormat.minimaxM3,
    MinimaxM3Handler.new,
    detect: (s) =>
        _hasAll(s, const [']<]minimax[>[', '<tool_call>', '<invoke name=']),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      keepsForcedThoughtVerbatim: true,
      takesThoughtOnlyAtReplyStart: true,
      thoughtStartsReplyExactly: true,
      mayEmbedToolEnvelopeAfterContent: true,
    ),
  ),
  // DeepSeek V3.2/V4 DSML family. The marker is assembled from a Jinja
  // variable, so detecting only literal rendered tags misses every variant.
  ChatFormatRegistration(
    ChatFormat.deepseekV32,
    DeepseekV32Handler.new,
    detect: (s) => _hasAll(s, const ['dsml_token', 'DSML', 'function_calls']),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      takesThoughtOnlyAtReplyStart: true,
      mayEmbedToolEnvelopeAfterContent: true,
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.deepseekV4,
    DeepseekV4Handler.new,
    detect: (s) => _hasAll(s, const ['dsml_token', 'DSML', 'tool_calls']),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      takesThoughtOnlyAtReplyStart: true,
      mayEmbedToolEnvelopeAfterContent: true,
    ),
  ),
  // Newline-delimited JSON tool-call envelope.
  ChatFormatRegistration(
    ChatFormat.minimaxM1,
    MinimaxM1Handler.new,
    detect: (s) => _hasAll(s, const [
      '<begin_of_document>',
      '<beginning_of_sentence>',
      '<tool_calls>',
    ]),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      mayEmbedToolEnvelopeAfterContent: true,
    ),
  ),
  // Shares GLM-style argument tags but uses explicit assistant and
  // tool-response turns and </assistant> as a stop.
  ChatFormatRegistration(
    ChatFormat.laguna,
    LagunaHandler.new,
    detect: (s) => _hasAll(s, const [
      '<assistant>',
      '</assistant>',
      '<tool_response>',
      '<arg_key>',
      '<arg_value>',
    ]),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: true,
      takesThoughtOnlyAtReplyStart: true,
      mayEmbedToolEnvelopeAfterContent: true,
      leavesIncompleteToolCall: _contentContainsAny(const ['<tool_call>']),
    ),
  ),
  // Right after Laguna, which shares the GLM-style argument tags: the <role>
  // turns tell them apart. Above Hermes because the call envelope is a
  // literal <tool_call>.
  ChatFormatRegistration(
    ChatFormat.ling3,
    Ling3Handler.new,
    detect: (s) => _hasAll(s, const ['<role>ASSISTANT</role>', '<arg_key>']),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      mayEmbedToolEnvelopeAfterContent: true,
      retainsTextAroundToolCalls: true,
      endsThoughtAtToolCallOpening: true,
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.deepseekV3,
    DeepseekV3Handler.new,
    detect: (s) => s.contains(
      "message['prefix'] is defined and message['prefix'] and thinking",
    ),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      toolCallOpening: DeepseekV3Handler.toolCallOpening,
      keepsForcedThoughtVerbatim: true,
      disabledByResponseSchema: true,
      closedThoughtKeepsTagsAsContent: true,
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.deepseekR1,
    DeepseekR1Handler.new,
    detect: (s) => s.contains('<｜tool▁calls▁begin｜>'),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      takesThoughtOnlyAtReplyStart: true,
      toolCallOpening: DeepseekR1Handler.toolCallOpening,
      disabledByResponseSchema: true,
    ),
  ),
  // Cohere2 MoE / North Code, before Command R7B: both use
  // <|START_ACTION|>, but START_TEXT is unique to the newer template.
  ChatFormatRegistration(
    ChatFormat.cohere2Moe,
    Cohere2MoeHandler.new,
    detect: (s) => _hasAll(s, const ['<|START_TEXT|>', '<|START_ACTION|>']),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      toolCallOpening: CommandR7BHandler.toolCallOpening,
      keepsForcedThoughtVerbatim: true,
      reopensThoughtClosedForThinkingOff: true,
      forcedThoughtContentOpenings:
          Cohere2MoeHandler.forcedThoughtContentOpenings,
      disabledByResponseSchema: true,
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.minicpm5,
    MiniCpm5Handler.new,
    detect: (s) => _hasAll(s, const [
      'Tool usage guidelines:',
      '<function name="',
      '<param name="',
    ]),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      takesThoughtOnlyAtReplyStart: true,
      toolCallOpening: XmlToolCallFormat.minicpm5.toolCallOpening,
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.commandR7B,
    CommandR7BHandler.new,
    detect: (s) => s.contains('<|END_THINKING|><|START_ACTION|>'),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      toolCallOpening: CommandR7BHandler.toolCallOpening,
      disabledByResponseSchema: true,
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.granite,
    GraniteHandler.new,
    detect: (s) => _hasAll(s, const ['elif thinking', '<|tool_call|>']),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      takesThoughtOnlyAtReplyStart: true,
      toolCallOpening: GraniteHandler.toolCallOpening,
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.glm45,
    Glm45Handler.new,
    detect: (s) =>
        _hasAll(s, const ['[gMASK]<sop>', '<arg_key>', '<arg_value>']),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: true,
      takesThoughtOnlyAtReplyStart: true,
      mayEmbedToolEnvelopeAfterContent: true,
      disabledByResponseSchema: true,
      leavesIncompleteToolCall: _contentContainsAny(const ['<tool_call>']),
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.hunyuanV3,
    HunyuanV3Handler.new,
    detect: (s) =>
        _hasAll(s, const ['<｜hy_User{}｜>', '<tool_sep{}>', '<arg_key{}>']),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: true,
      takesThoughtOnlyAtReplyStart: true,
      toolCallOpening: HunyuanV3Handler.toolCallOpening,
      leavesIncompleteToolCall: _contentContainsAny(const [
        '<tool_call:opensource>',
        '<tool_calls:opensource>',
      ]),
    ),
  ),
  // Qwen3.6 uses the same generated `<function=...><parameter=...>`
  // envelope, but its template describes the shape through its XML
  // tool-call instruction instead of `<function>` and `<parameters>`
  // declaration tags.
  ChatFormatRegistration(
    ChatFormat.qwen3CoderXml,
    Qwen3CoderXmlHandler.new,
    detect: (s) =>
        _hasAll(s, const ['<tool_call>', '<function=', '<parameter=']) &&
        (_hasAll(s, const ['<function>', '<parameters>']) ||
            s.contains('Function calls MUST follow the specified format')),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      takesThoughtOnlyAtReplyStart: true,
      toolCallOpening: XmlToolCallFormat.qwen3Coder.toolCallOpening,
      closedThoughtKeepsTagsAsContent: true,
      keepsForcedThoughtVerbatim: true,
      reopensThoughtClosedForThinkingOff: true,
      forcedThoughtContentOpenings: [XmlToolCallFormat.qwen3CoderScopeStart],
      budgetThoughtClosePrefix: '\n',
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.xiaomiMimo,
    XiaomiMimoHandler.new,
    detect: (s) => _hasAll(s, const [
      '<tools>',
      '# Tools',
      '</tools>',
      '<tool_calls>',
      '</tool_calls>',
      '<tool_response>',
    ]),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      toolCallOpening: XmlToolCallFormat.xiaomiMimo.toolCallOpening,
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.exaoneMoe,
    ExaoneMoeHandler.new,
    detect: (s) =>
        _hasAll(s, const ['<tool_call>', '<tool_result>', '<|tool_declare|>']),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      toolCallOpening: ExaoneMoeHandler.toolCallOpening,
    ),
  ),
  // Hermes 2 Pro / Qwen 2.5/3. Every <tool_call> family above must stay
  // above it.
  ChatFormatRegistration(
    ChatFormat.hermes,
    HermesHandler.new,
    detect: (s) => s.contains('<tool_call>'),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: true,
      takesThoughtOnlyAtReplyStart: true,
      toolCallOpening: HermesHandler.toolCallOpening,
      keepsForcedThoughtVerbatim: true,
      disabledByResponseSchema: true,
      closedThoughtKeepsTagsAsContent: true,
      // Qualified on Qwen3-VL against llama-server's rendering (#1008).
      rendersToolResultContent: true,
      leavesIncompleteToolCall: _hermesLeavesIncompleteToolCall,
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.gptOss,
    GptOssHandler.new,
    detect: (s) => s.contains('<|channel|>'),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      toolCallOpening: GptOssHandler.toolCallOpening,
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.seedOss,
    SeedOssHandler.new,
    detect: (s) => s.contains('<seed:think>'),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      toolCallOpening: XmlToolCallFormat.seedOss.toolCallOpening,
      keepsForcedThoughtVerbatim: true,
      reopensThoughtClosedForThinkingOff: true,
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.nemotronV2,
    NemotronV2Handler.new,
    detect: (s) => s.contains('<SPECIAL_10>'),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      toolCallOpening: NemotronV2Handler.toolCallOpening,
      requiredKeepsLazyGrammar: true,
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.apertus,
    ApertusHandler.new,
    detect: (s) => _hasAll(s, const ['<|system_start|>', '<|tools_prefix|>']),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      takesThoughtOnlyAtReplyStart: true,
      toolCallOpening: ApertusHandler.toolCallOpening,
      requiredKeepsLazyGrammar: true,
    ),
  ),
  // LFM2 wraps its tool list in <|tool_list_start|>/<|tool_list_end|>;
  // LFM2.5 writes a plain "List of tools: [...]". llama.cpp routes both.
  ChatFormatRegistration(
    ChatFormat.lfm2,
    Lfm2Handler.new,
    detect: (s) =>
        _hasAll(s, const ['<|tool_list_start|>', '<|tool_list_end|>']) ||
        (s.contains('List of tools: [') && !s.contains('<|tool_list_start|>')),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      takesThoughtOnlyAtReplyStart: true,
      toolCallOpening: Lfm2Handler.toolCallOpening,
      requiredKeepsLazyGrammar: true,
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.minimaxM2,
    MinimaxM2Handler.new,
    detect: (s) => _hasAll(s, const [']~!b[', ']~b]']),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      toolCallOpening: XmlToolCallFormat.minimaxM2.toolCallOpening,
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.kimiK2,
    KimiK2Handler.new,
    detect: (s) => _hasAll(s, const [
      '<|im_system|>tool_declare<|im_middle|>',
      '<|tool_calls_section_begin|>',
      '## Return of',
    ]),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      takesThoughtOnlyAtReplyStart: true,
      toolCallOpening: KimiK2Handler.toolCallOpening,
      parsesCallsInsideThoughts: true,
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.apriel15,
    Apriel15Handler.new,
    detect: (s) => _hasAll(s, const [
      '<thinking>',
      '</thinking>',
      '<available_tools>',
      '<|assistant|>',
      '<|tool_result|>',
      '<tool_calls>[',
      ']</tool_calls>',
    ]),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      toolCallOpening: XmlToolCallFormat.apriel15.toolCallOpening,
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.solarOpen,
    SolarOpenHandler.new,
    detect: (s) => _hasAll(s, const [
      '<|tool_response:begin|>',
      '<|tool_response:name|>',
      '<|tool_response:result|>',
    ]),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      hasRepeatedContentChannels: true,
    ),
  ),
  // Before Gemma 3, whose turn markers FunctionGemma templates also use.
  ChatFormatRegistration(
    ChatFormat.functionGemma,
    FunctionGemmaHandler.new,
    detect: (s) =>
        s.contains('<start_function_declaration>') ||
        s.contains('<start_function_call>') ||
        s.contains('<start_function_response>'),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      toolCallOpening: FunctionGemmaHandler.toolCallOpening,
      keepsThoughtTagsAsContent: true,
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.translateGemma,
    TranslateGemmaHandler.new,
    detect: (s) =>
        _hasAll(s, const ['[source_lang_code]', '[target_lang_code]']),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      keepsThoughtTagsAsContent: true,
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.functionaryV32,
    FunctionaryV32Handler.new,
    detect: (s) => s.contains('>>>all'),
    traits: ChatFormatTraits(qualifiesJsonSchemaTools: false),
  ),
  ChatFormatRegistration(
    ChatFormat.firefunctionV2,
    FirefunctionV2Handler.new,
    detect: (s) => s.contains(' functools['),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      toolCallOpening: FirefunctionV2Handler.toolCallOpening,
      keepsThoughtTagsAsContent: true,
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.functionaryV31Llama31,
    FunctionaryV31Llama31Handler.new,
    detect: (s) => _hasAll(s, const ['<|start_header_id|>', '<function=']),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      toolCallOpening: FunctionaryV31Llama31Handler.toolCallOpening,
      keepsThoughtTagsAsContent: true,
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.llama3,
    Llama3Handler.new,
    detect: (s) => s.contains('<|start_header_id|>ipython<|end_header_id|>'),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      takesThoughtOnlyAtReplyStart: true,
    ),
  ),
  // Ministral templates also carry [THINK] and [TOOL_CALLS], so Ministral
  // precedes Magistral and Mistral Nemo.
  ChatFormatRegistration(
    ChatFormat.ministral,
    MinistralHandler.new,
    detect: (s) =>
        _hasAll(s, const ['[SYSTEM_PROMPT]', '[TOOL_CALLS]', '[ARGS]']),
    traits: ChatFormatTraits(qualifiesJsonSchemaTools: false),
  ),
  ChatFormatRegistration(
    ChatFormat.magistral,
    MagistralHandler.new,
    detect: (s) => _hasAll(s, const ['[THINK]', '[/THINK]']),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      toolCallOpening: MagistralHandler.toolCallOpening,
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.mistralNemo,
    MistralHandler.new,
    detect: (s) => s.contains('[TOOL_CALLS]'),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: true,
      takesThoughtOnlyAtReplyStart: true,
      toolCallOpening: MistralHandler.toolCallOpening,
      toolChoiceNoneRendersContentOnly: true,
      leavesIncompleteToolCall: _contentContainsAny(const ['[TOOL_CALLS]']),
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.gemma,
    GemmaHandler.new,
    detect: (s) => s.contains('<start_of_turn>') && !s.contains('<|im_start|>'),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      toolCallOpening: GemmaHandler.toolCallOpening,
      keepsThoughtTagsAsContent: true,
      routesThroughGeneric: true,
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.gemma4,
    Gemma4Handler.new,
    detect: (s) => _hasAll(s, const ['<|turn>', '<turn|>']),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      mayEmbedToolEnvelopeAfterContent: true,
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.llama3BuiltinTools,
    Llama3Handler.new,
    traits: ChatFormatTraits(qualifiesJsonSchemaTools: false),
  ),
  ChatFormatRegistration(
    ChatFormat.pegSimple,
    () => _withoutTemplateToolCalls(ChatFormat.pegSimple),
    traits: ChatFormatTraits(qualifiesJsonSchemaTools: false),
  ),
  ChatFormatRegistration(
    ChatFormat.pegNative,
    () => _withoutTemplateToolCalls(ChatFormat.pegNative),
    traits: ChatFormatTraits(qualifiesJsonSchemaTools: false),
  ),
  ChatFormatRegistration(
    ChatFormat.pegConstructed,
    () => _withoutTemplateToolCalls(ChatFormat.pegConstructed),
    traits: ChatFormatTraits(qualifiesJsonSchemaTools: false),
  ),
  ChatFormatRegistration(
    ChatFormat.generic,
    GenericHandler.new,
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: true,
      takesThoughtOnlyAtReplyStart: true,
      toolChoiceNoneRendersContentOnly: true,
      leavesIncompleteToolCall: _genericLeavesIncompleteToolCall,
    ),
  ),
  ChatFormatRegistration(
    ChatFormat.contentOnly,
    () => _withoutTemplateToolCalls(ChatFormat.contentOnly),
    traits: ChatFormatTraits(
      qualifiesJsonSchemaTools: false,
      takesThoughtOnlyAtReplyStart: true,
      toolChoiceNoneRendersContentOnly: true,
    ),
  ),
]);

/// The registration of [format].
ChatFormatRegistration chatFormatRegistration(ChatFormat format) =>
    _registrationsByFormat[format]!;

final Map<ChatFormat, ChatFormatRegistration> _registrationsByFormat = {
  for (final registration in chatFormatRegistrations)
    registration.format: registration,
};

bool _hasAll(String source, List<String> markers) =>
    markers.every(source.contains);

/// A generic handler for [format] that serializes no tool calls into the
/// template.
GenericHandler _withoutTemplateToolCalls(ChatFormat format) => GenericHandler(
  format: format,
  toolCallSerialization: TemplateToolCallSerialization.none,
);

final RegExp _genericToolCallJson = RegExp(r'^\{\s*"tool_calls?"\s*:');

bool _genericLeavesIncompleteToolCall(
  ChatParseResult result,
  String output, {
  required bool thinkingForcedOpen,
}) =>
    result.toolCalls.isEmpty &&
    _genericToolCallJson.hasMatch(
      extractThinking(
        output,
        thinkingForcedOpen: thinkingForcedOpen,
      ).content.trimLeft(),
    );

bool _hermesLeavesIncompleteToolCall(
  ChatParseResult result,
  String output, {
  required bool thinkingForcedOpen,
}) => HermesHandler.hasCompleteToolCallOpening(result.content);

IncompleteToolCallCheck _contentContainsAny(List<String> markers) =>
    (result, output, {required thinkingForcedOpen}) =>
        markers.any(result.content.contains);
