@TestOn('vm')
library;

import 'dart:io';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:test/test.dart';

void main() {
  group('ChatFormat Detection', () {
    test('treats non-strict LFM 2.5 fixture as content-only', () {
      final file = File('test/fixtures/templates/LFM2_5-1_2B-Thinking.jinja');
      final source = file.readAsStringSync();
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.contentOnly));
    });

    test('does not detect LFM2 from keep_past_thinking marker alone', () {
      const source =
          '{%- set keep_past_thinking = true -%}<|im_start|>user\nhi<|im_end|>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.contentOnly));
    });

    test('detects LFM2 from strict tool list markers', () {
      const source =
          'List of tools: <|tool_list_start|>[{"name":"search"}]<|tool_list_end|>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.lfm2));
    });

    test('detects LFM2.5 tool-call templates from plain tool list markers', () {
      const source =
          'List of tools: [{"name":"search"}]'
          '<|tool_call_start|>[search(query="llama")]<|tool_call_end|>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.lfm2));
    });

    test('falls back to content-only for standard ChatML', () {
      const source = '<|im_start|>user\nhi<|im_end|>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.contentOnly));
    });

    test('treats Phi-style chat template as content-only', () {
      const source = '<|user|>hi<|end|><|assistant|>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.contentOnly));
    });

    test(
      'keeps DeepSeek V4 DSML tool_calls template content-only in b9860',
      () {
        const source =
            "{%- set dsml_token = '｜DSML｜' -%}"
            "<' + dsml_token + 'tool_calls>"
            "<' + dsml_token + 'invoke name=\"\$TOOL_NAME\">"
            "</' + dsml_token + 'tool_calls>";
        final format = detectChatFormat(source);
        expect(format, equals(ChatFormat.contentOnly));
      },
    );

    test('detects Cohere2 MoE / North Code before older Command-R', () {
      const source =
          '<|START_THINKING|><|END_THINKING|><|START_TEXT|>{{ content }}<|END_TEXT|><|START_ACTION|>[]<|END_ACTION|>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.cohere2Moe));
    });

    test('detects Granite 4.1 XML tool-call template through Hermes path', () {
      const source =
          '<|start_of_role|>assistant<|end_of_role|>'
          '<tool_call>{"name": "search", "arguments": {}}</tool_call>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.hermes));
    });

    test('detects GPT-OSS format', () {
      const source = '<|start|>assistant<|channel|>final<|message|>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.gptOss));
    });

    test('detects Seed-OSS format', () {
      const source = '<seed:think>thinking</seed:think><seed:tool_call>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.seedOss));
    });

    test('detects Nemotron V2 format', () {
      const source = '<SPECIAL_10>\n<TOOLCALL>[{"name":"weather"}]</TOOLCALL>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.nemotronV2));
    });

    test('detects Hunyuan V3 format', () {
      const source =
          '<｜hy_User{}｜><tool_calls{}><tool_call{}>'
          '<tool_sep{}><arg_key{}><arg_value{}>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.hunyuanV3));
    });

    test('detects Apertus format', () {
      const source =
          '<|system_start|>sys<|system_end|><|tools_prefix|>[]<|tools_suffix|>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.apertus));
    });

    test('detects Xiaomi MiMo format', () {
      const source =
          '<tools># Tools</tools><tool_calls></tool_calls><tool_response>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.xiaomiMimo));
    });

    test('detects Apriel 1.5 format', () {
      const source =
          '<thinking></thinking><available_tools><|assistant|><|tool_result|><tool_calls>[]</tool_calls>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.apriel15));
    });

    test('detects Solar Open format', () {
      const source =
          '<|tool_response:begin|><|tool_response:name|><|tool_response:result|>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.solarOpen));
    });

    test('detects TranslateGemma format', () {
      const source = '[source_lang_code]\n[target_lang_code]\n{{ message }}';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.translateGemma));
    });

    test('detects Kimi K2 format', () {
      const source =
          '<|im_system|>tool_declare<|im_middle|>...<|tool_calls_section_begin|>...## Return of functions.weather:0';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.kimiK2));
    });

    test('does not detect MiniMax from tool_call XML marker alone', () {
      const source = '<minimax:tool_call><invoke name="x"></invoke>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.contentOnly));
    });

    test('detects FireFunction v2 format', () {
      const source = '... functools[...';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.firefunctionV2));
    });

    test('detects Functionary v3.2 format', () {
      const source = '>>>all\nHello';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.functionaryV32));
    });

    test('detects Functionary v3.1 Llama 3.1 format', () {
      const source =
          '<|start_header_id|>assistant<|end_header_id|><function=special_function>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.functionaryV31Llama31));
    });

    test('detects EXAONE MoE format before Hermes', () {
      const source =
          '<tool_call>{}</tool_call><tool_result>x</tool_result><|tool_declare|>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.exaoneMoe));
    });

    test('detects Qwen3 Coder XML before Hermes', () {
      const source =
          '<tool_call><function><function=test><parameters><parameter=a>1</parameter></function></tool_call>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.qwen3CoderXml));
    });

    test('keeps Qwen3 Coder XML detection when think tag is present', () {
      const source =
          '<tool_call><function><function=test><parameters><parameter=a>1</parameter></function></tool_call><think>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.qwen3CoderXml));
    });

    test('detects Qwen3.6 XML tools before Hermes', () {
      const source =
          '<tool_call><function=example_function_name><parameter=example_parameter_1>'
          'Function calls MUST follow the specified format<think>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.qwen3CoderXml));
    });

    test('detects Granite only with thinking marker', () {
      const source = 'elif thinking ... <|tool_call|>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.granite));
    });

    test('detects FunctionGemma format from function-call markers', () {
      const source =
          '<start_of_turn>user\nhi<end_of_turn><start_of_turn>model\n'
          '<start_function_call>call:get_weather{"location":"Seoul"}'
          '<end_function_call>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.functionGemma));
    });

    test('detects Gemma 4 format from turn markers', () {
      const source =
          '<|turn>user\nhi<turn|>\n'
          '<|turn>model\n'
          '<|tool_call>call:get_weather{location:<|"|>Seoul<|"|>}<tool_call|>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.gemma4));
    });

    test('detects Ministral format before Magistral', () {
      const source =
          '[SYSTEM_PROMPT]x[/SYSTEM_PROMPT][TOOL_CALLS]get_weather[ARGS]{}';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.ministral));
    });

    test('detects Magistral format from think tags', () {
      const source = '[THINK]reasoning[/THINK]';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.magistral));
    });

    test('detects unsloth Ministral 3 reasoning template markers', () {
      const source =
          '[SYSTEM_PROMPT]x[/SYSTEM_PROMPT]'
          '[AVAILABLE_TOOLS][][/AVAILABLE_TOOLS]'
          '[THINK]plan[/THINK]'
          '[TOOL_CALLS]get_weather[ARGS]{"city":"Seoul"}';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.ministral));
    });

    test('prefers FunctionGemma detection when both markers are present', () {
      const source =
          '<start_of_turn>user\nhi<end_of_turn>'
          '<start_function_call>call:get_weather{"location":"Paris"}'
          '<end_function_call>';
      final format = detectChatFormat(source);
      expect(format, equals(ChatFormat.functionGemma));
    });
  });
}
