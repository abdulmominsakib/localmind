import 'package:llamadart/src/core/template/chat_format.dart';

const Map<ChatFormat, String> _sampleOutputsByFormat = <ChatFormat, String>{
  ChatFormat.deepseekR1:
      '</think><｜tool▁calls▁begin｜>'
      '<｜tool▁call▁begin｜>function<｜tool▁sep｜>get_weather\n'
      '```json\n{"location":"Seoul"}\n```<｜tool▁call▁end｜>'
      '<｜tool▁calls▁end｜>',
  ChatFormat.firefunctionV2:
      ' functools[{"name":"get_weather","arguments":{"location":"Seoul"}}]',
  ChatFormat.functionaryV32: '>>>get_weather\n{"location":"Seoul"}',
  ChatFormat.functionaryV31Llama31:
      '<function=get_weather>{"location":"Seoul"}</function>',
  ChatFormat.granite:
      '<|tool_call|>[{"name":"get_weather","arguments":{"location":"Seoul"}}]',
  ChatFormat.lfm2:
      '<|tool_call_start|>[get_weather(location=\'Seoul\')]<|tool_call_end|>',
  ChatFormat.ministral: '[TOOL_CALLS]get_weather[ARGS]{"location":"Seoul"}',
  ChatFormat.kimiK2:
      '<|tool_calls_section_begin|>'
      '<|tool_call_begin|>functions.get_weather:0'
      '<|tool_call_argument_begin|>{"location":"Seoul"}'
      '<|tool_call_end|>'
      '<|tool_calls_section_end|>',
  ChatFormat.apertus:
      '<|tools_prefix|>[{"get_weather":{"location":"Seoul"}}]<|tools_suffix|>',
  ChatFormat.solarOpen:
      '<|tool_calls|>'
      '<|tool_call:begin|>0'
      '<|tool_call:name|>get_weather'
      '<|tool_call:args|>{"location":"Seoul"}'
      '<|tool_call:end|>',
  ChatFormat.hunyuanV3:
      '<think:opensource>check weather</think:opensource>'
      '<tool_calls:opensource>\n'
      '<tool_call:opensource>get_weather<tool_sep:opensource>\n'
      '<arg_key:opensource>location</arg_key:opensource>\n'
      '<arg_value:opensource>Seoul</arg_value:opensource>\n'
      '</tool_call:opensource>\n'
      '</tool_calls:opensource>',
  ChatFormat.kimiK3:
      '<|open|>response<|sep|><|close|>response<|sep|>'
      '<|open|>tools<|sep|>'
      '<|open|>call tool="get_weather" index="1"<|sep|>'
      '<|open|>argument key="location" type="string"<|sep|>'
      'Seoul<|close|>argument<|sep|>'
      '<|close|>call<|sep|><|close|>tools<|sep|>'
      '<|close|>message<|sep|>',
  ChatFormat.minimaxM1:
      '<tool_calls>\n'
      '{"name":"get_weather","arguments":{"location":"Seoul"}}\n'
      '</tool_calls>',
  ChatFormat.minimaxM3:
      '</mm:think>'
      ']<]minimax[>[<tool_call>\n'
      ']<]minimax[>[<invoke name="get_weather">'
      ']<]minimax[>[<location>Seoul]<]minimax[>[</location>'
      ']<]minimax[>[</invoke>\n'
      ']<]minimax[>[</tool_call>',
  ChatFormat.deepseekV4:
      '</think>\n\n'
      '<｜DSML｜tool_calls>\n'
      '<｜DSML｜invoke name="get_weather">\n'
      '<｜DSML｜parameter name="location" string="true">Seoul'
      '</｜DSML｜parameter>\n'
      '</｜DSML｜invoke>\n'
      '</｜DSML｜tool_calls>',
  ChatFormat.deepseekV32:
      '</think>\n\n'
      '<｜DSML｜function_calls>\n'
      '<｜DSML｜invoke name="get_weather">\n'
      '<｜DSML｜parameter name="location" string="true">Seoul'
      '</｜DSML｜parameter>\n'
      '</｜DSML｜invoke>\n'
      '</｜DSML｜function_calls>',
  ChatFormat.museGlimmer:
      ' to=get_weather<|message|><atem:function_calls>\n'
      '<atem:invoke name="get_weather">\n'
      '<atem:parameter name="location">Seoul</atem:parameter>\n'
      '</atem:invoke>\n'
      '</atem:function_calls>',
  ChatFormat.laguna:
      '</think><tool_call>get_weather\n'
      '<arg_key>location</arg_key>\n'
      '<arg_value>Seoul</arg_value>\n'
      '</tool_call>',
  ChatFormat.ling3:
      '</think><tool_call>get_weather\n'
      '<arg_key>location</arg_key>\n'
      '<arg_value>Seoul</arg_value>\n'
      '</tool_call>',
};

String sampleOutputForFormat(ChatFormat format) {
  return _sampleOutputsByFormat[format] ?? 'roundtrip content';
}
