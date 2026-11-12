import 'package:llamadart/src/core/template/chat_format.dart';

typedef ChatFormatTrigger = ({ChatFormat format, String source});

/// The smallest source matching each detector, keyed by a stable name.
/// `chatml` is the ChatML marker that suppresses Gemma 3 detection.
const Map<String, ChatFormatTrigger> chatFormatTriggers = {
  'kimiK3': (
    format: ChatFormat.kimiK3,
    source: '<|open|><|close|><|end_of_msg|>',
  ),
  'museGlimmer': (
    format: ChatFormat.museGlimmer,
    source: '<atem:function_calls><|eom|>',
  ),
  'minimaxM3': (
    format: ChatFormat.minimaxM3,
    source: ']<]minimax[>[<tool_call><invoke name=',
  ),
  'deepseekV32': (
    format: ChatFormat.deepseekV32,
    source: 'dsml_token DSML function_calls',
  ),
  'deepseekV4': (
    format: ChatFormat.deepseekV4,
    source: 'dsml_token DSML tool_calls',
  ),
  'minimaxM1': (
    format: ChatFormat.minimaxM1,
    source: '<begin_of_document><beginning_of_sentence><tool_calls>',
  ),
  'laguna': (
    format: ChatFormat.laguna,
    source: '<assistant></assistant><tool_response><arg_key><arg_value>',
  ),
  'ling3': (
    format: ChatFormat.ling3,
    source: '<role>ASSISTANT</role><arg_key>',
  ),
  'deepseekV3': (
    format: ChatFormat.deepseekV3,
    source: "message['prefix'] is defined and message['prefix'] and thinking",
  ),
  'deepseekR1': (format: ChatFormat.deepseekR1, source: '<｜tool▁calls▁begin｜>'),
  'cohere2Moe': (
    format: ChatFormat.cohere2Moe,
    source: '<|START_TEXT|><|START_ACTION|>',
  ),
  'minicpm5': (
    format: ChatFormat.minicpm5,
    source: 'Tool usage guidelines: <function name=" <param name="',
  ),
  'commandR7B': (
    format: ChatFormat.commandR7B,
    source: '<|END_THINKING|><|START_ACTION|>',
  ),
  'granite': (
    format: ChatFormat.granite,
    source: 'elif thinking <|tool_call|>',
  ),
  'glm45': (
    format: ChatFormat.glm45,
    source: '[gMASK]<sop><arg_key><arg_value>',
  ),
  'hunyuanV3': (
    format: ChatFormat.hunyuanV3,
    source: '<｜hy_User{}｜><tool_sep{}><arg_key{}>',
  ),
  'qwen3CoderXml': (
    format: ChatFormat.qwen3CoderXml,
    source: '<tool_call><function=<parameter=<function><parameters>',
  ),
  'qwen36Xml': (
    format: ChatFormat.qwen3CoderXml,
    source:
        '<tool_call><function=<parameter='
        'Function calls MUST follow the specified format',
  ),
  'xiaomiMimo': (
    format: ChatFormat.xiaomiMimo,
    source: '<tools># Tools</tools><tool_calls></tool_calls><tool_response>',
  ),
  'exaoneMoe': (
    format: ChatFormat.exaoneMoe,
    source: '<tool_call><tool_result><|tool_declare|>',
  ),
  'hermes': (format: ChatFormat.hermes, source: '<tool_call>'),
  'gptOss': (format: ChatFormat.gptOss, source: '<|channel|>'),
  'seedOss': (format: ChatFormat.seedOss, source: '<seed:think>'),
  'nemotronV2': (format: ChatFormat.nemotronV2, source: '<SPECIAL_10>'),
  'apertus': (
    format: ChatFormat.apertus,
    source: '<|system_start|><|tools_prefix|>',
  ),
  'lfm2': (
    format: ChatFormat.lfm2,
    source: '<|tool_list_start|><|tool_list_end|>',
  ),
  'lfm25': (format: ChatFormat.lfm2, source: 'List of tools: ['),
  'minimaxM2': (format: ChatFormat.minimaxM2, source: ']~!b[]~b]'),
  'kimiK2': (
    format: ChatFormat.kimiK2,
    source:
        '<|im_system|>tool_declare<|im_middle|>'
        '<|tool_calls_section_begin|>## Return of',
  ),
  'apriel15': (
    format: ChatFormat.apriel15,
    source:
        '<thinking></thinking><available_tools><|assistant|>'
        '<|tool_result|><tool_calls>[]</tool_calls>',
  ),
  'solarOpen': (
    format: ChatFormat.solarOpen,
    source:
        '<|tool_response:begin|><|tool_response:name|>'
        '<|tool_response:result|>',
  ),
  'functionGemmaDeclaration': (
    format: ChatFormat.functionGemma,
    source: '<start_function_declaration>',
  ),
  'functionGemmaCall': (
    format: ChatFormat.functionGemma,
    source: '<start_function_call>',
  ),
  'functionGemmaResponse': (
    format: ChatFormat.functionGemma,
    source: '<start_function_response>',
  ),
  'translateGemma': (
    format: ChatFormat.translateGemma,
    source: '[source_lang_code][target_lang_code]',
  ),
  'functionaryV32': (format: ChatFormat.functionaryV32, source: '>>>all'),
  'firefunctionV2': (format: ChatFormat.firefunctionV2, source: ' functools['),
  'functionaryV31Llama31': (
    format: ChatFormat.functionaryV31Llama31,
    source: '<|start_header_id|><function=',
  ),
  'llama3': (
    format: ChatFormat.llama3,
    source: '<|start_header_id|>ipython<|end_header_id|>',
  ),
  'ministral': (
    format: ChatFormat.ministral,
    source: '[SYSTEM_PROMPT][TOOL_CALLS][ARGS]',
  ),
  'magistral': (format: ChatFormat.magistral, source: '[THINK][/THINK]'),
  'mistralNemo': (format: ChatFormat.mistralNemo, source: '[TOOL_CALLS]'),
  'gemma': (format: ChatFormat.gemma, source: '<start_of_turn>'),
  'gemma4': (format: ChatFormat.gemma4, source: '<|turn><turn|>'),
  'chatml': (format: ChatFormat.contentOnly, source: '<|im_start|>'),
};
