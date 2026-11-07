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
};

String sampleOutputForFormat(ChatFormat format) {
  return _sampleOutputsByFormat[format] ?? 'roundtrip content';
}
