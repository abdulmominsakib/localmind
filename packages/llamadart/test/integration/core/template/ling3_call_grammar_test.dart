@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/inference/tool_choice.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/handlers/ling3_handler.dart';
import 'package:test/test.dart';

import '../../../support/gbnf_recognizer.dart';
import '../../../support/ling3_tools.dart';

const String _template =
    'test/fixtures/llama_cpp_templates/inclusionai-ling-3.0-flash.jinja';

/// Replies after the lazy grammar's `<tool_call>` trigger, each with whether
/// llama.cpp's (`cd959bae9`) Ling 3 grammar takes it without and with
/// parallel tool calls, as `test-gbnf-validator` reported.
final List<(String, bool, bool)> _autoReplies = [
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call><|role_end|>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>\n<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Rome</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call><tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Rome</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>\nAll done.',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>\nAll done.<|role_end|>',
    true,
    true,
  ),
  (
    '<tool_call>\n{"name": "get_weather", "arguments": {"location": "Paris"}}\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Par',
    false,
    false,
  ),
  ('<tool_call>get_weather', false, false),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_c',
    false,
    false,
  ),
  (
    '<tool_call>nope\n<arg_key>x</arg_key>\n<arg_value>1</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n<arg_key>zzz</arg_key>\n<arg_value>1</arg_value>\n</tool_call>',
    false,
    false,
  ),
  ('<tool_call>get_weather\n</tool_call>', false, false),
  (
    '<tool_call>get_weather<arg_key>location</arg_key><arg_value>Paris</arg_value></tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key><arg_value>Paris</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n\n\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>42</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>{"a": 1}</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>"Paris"</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris\nFrance</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value></arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>a<arg_key>b</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>  Paris  </arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_time\n<arg_key>tz</arg_key>\n<arg_value>UTC</arg_value>\n<arg_key>days</arg_key>\n<arg_value>3</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_time\n<arg_key>days</arg_key>\n<arg_value>3</arg_value>\n<arg_key>tz</arg_key>\n<arg_value>UTC</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_time\n<arg_key>tz</arg_key>\n<arg_value>UTC</arg_value>\n<arg_key>days</arg_key>\n<arg_value>three</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_time\n<arg_key>tz</arg_key>\n<arg_value>UTC</arg_value>\n<arg_key>days</arg_key>\n<arg_value>"3"</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>set_flags\n<arg_key>verbose</arg_key>\n<arg_value>true</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>set_flags\n<arg_key>verbose</arg_key>\n<arg_value>yes</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>set_flags\n<arg_key>verbose</arg_key>\n<arg_value>false</arg_value>\n<arg_key>tags</arg_key>\n<arg_value>["a", "b"]</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>set_flags\n<arg_key>verbose</arg_key>\n<arg_value>false</arg_value>\n<arg_key>tags</arg_key>\n<arg_value>[1, 2]</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>set_flags\n<arg_key>verbose</arg_key>\n<arg_value>false</arg_value>\n<arg_key>config</arg_key>\n<arg_value>{"k": 1}</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n<arg_key>location</arg_key>\n<arg_value>Rome</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_time\n<arg_key>tz</arg_key>\n<arg_value>UTC</arg_value>\n<arg_key>days</arg_key>\n<arg_value>1</arg_value>\n<arg_key>days</arg_key>\n<arg_value>2</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call><|role_end|>ignored',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call></think>x',
    true,
    true,
  ),
  (
    '<tool_call>book\n<arg_key>from</arg_key>\n<arg_value>A</arg_value>\n<arg_key>to</arg_key>\n<arg_value>B</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>book\n<arg_key>to</arg_key>\n<arg_value>B</arg_value>\n<arg_key>from</arg_key>\n<arg_value>A</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>book\n<arg_key>to</arg_key>\n<arg_value>B</arg_value>\n<arg_key>from</arg_key>\n<arg_value>A</arg_value>\n<arg_key>seats</arg_key>\n<arg_value>2</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>book\n<arg_key>seats</arg_key>\n<arg_value>2</arg_value>\n<arg_key>from</arg_key>\n<arg_value>A</arg_value>\n<arg_key>to</arg_key>\n<arg_value>B</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>book\n<arg_key>from</arg_key>\n<arg_value>A</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>big\n<arg_key>a</arg_key>\n<arg_value>A</arg_value>\n<arg_key>b</arg_key>\n<arg_value>B</arg_value>\n<arg_key>c</arg_key>\n<arg_value>C</arg_value>\n<arg_key>d</arg_key>\n<arg_value>D</arg_value>\n<arg_key>e</arg_key>\n<arg_value>E</arg_value>\n<arg_key>f</arg_key>\n<arg_value>F</arg_value>\n<arg_key>g</arg_key>\n<arg_value>G</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>big\n<arg_key>g</arg_key>\n<arg_value>G</arg_value>\n<arg_key>f</arg_key>\n<arg_value>F</arg_value>\n<arg_key>e</arg_key>\n<arg_value>E</arg_value>\n<arg_key>d</arg_key>\n<arg_value>D</arg_value>\n<arg_key>c</arg_key>\n<arg_value>C</arg_value>\n<arg_key>b</arg_key>\n<arg_value>B</arg_value>\n<arg_key>a</arg_key>\n<arg_value>A</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>big6\n<arg_key>f</arg_key>\n<arg_value>F</arg_value>\n<arg_key>e</arg_key>\n<arg_value>E</arg_value>\n<arg_key>d</arg_key>\n<arg_value>D</arg_value>\n<arg_key>c</arg_key>\n<arg_value>C</arg_value>\n<arg_key>b</arg_key>\n<arg_value>B</arg_value>\n<arg_key>a</arg_key>\n<arg_value>A</arg_value>\n</tool_call>',
    true,
    true,
  ),
  ('<tool_call>ping\n</tool_call>', true, true),
  ('<tool_call>ping</tool_call>', true, true),
  (
    '<tool_call>ping\n<arg_key>x</arg_key>\n<arg_value>1</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>misc\n<arg_key>mode</arg_key>\n<arg_value>fast</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>misc\n<arg_key>mode</arg_key>\n<arg_value>zzz</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_time\n<arg_key>tz</arg_key>\n<arg_value>UTC</arg_value>\n<arg_key>days</arg_key>\n<arg_value> 3 </arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_time\n<arg_key>tz</arg_key>\n<arg_value>UTC</arg_value>\n<arg_key>days</arg_key>\n<arg_value>\n3\n</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_time\n<arg_key>tz</arg_key>\n<arg_value>UTC</arg_value>\n<arg_key>days</arg_key>\n<arg_value>3.5</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_time\n<arg_key>tz</arg_key>\n<arg_value>UTC</arg_value>\n<arg_key>days</arg_key>\n<arg_value>-3</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_time\n<arg_key>tz</arg_key>\n<arg_value>UTC</arg_value>\n<arg_key>days</arg_key>\n<arg_value></arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_time\n<arg_key>tz</arg_key>\n<arg_value>UTC</arg_value>\n<arg_key>days</arg_key>\n<arg_value>3 x</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>set_flags\n<arg_key>verbose</arg_key>\n<arg_value> true</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>set_flags\n<arg_key>verbose</arg_key>\n<arg_value>false</arg_value>\n<arg_key>tags</arg_key>\n<arg_value> ["a"] </arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>set_flags\n<arg_key>verbose</arg_key>\n<arg_value>false</arg_value>\n<arg_key>config</arg_key>\n<arg_value>{"k": 1, "z": {"q": [1,2,{"r": null}]}}</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>set_flags\n<arg_key>verbose</arg_key>\n<arg_value>false</arg_value>\n<arg_key>config</arg_key>\n<arg_value>{"k": 1</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n\n\n\n<arg_key>location</arg_key>\n\n\n\n<arg_value>Paris</arg_value>\n\n\n\n\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather \t <arg_key>location</arg_key> \t <arg_value>Paris</arg_value> \t </tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\r\n<arg_key>location</arg_key>\r\n<arg_value>Paris</arg_value>\r\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key> location </arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call> get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather_extra\n<arg_key>q</arg_key>\n<arg_value>x</arg_value>\n</tool_call>',
    true,
    true,
  ),
  ('<tool_call>get_weatherx\n</tool_call>', false, false),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>\n\n\n  <tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Rome</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>and<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Rome</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>\n<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Rome</arg_value>\n</tool_call>\n<tool_call>get_time\n<arg_key>tz</arg_key>\n<arg_value>UTC</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>\n<tool_call>nope\n<arg_key>x</arg_key>\n<arg_value>1</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>\n<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Ro',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call><|role_end|>a<|role_end|>b',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>a<|role_end|>b</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Zürich 東京 😀</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>a &amp; b &lt;</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>C:\\path\\n "q"</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n< arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg\n_value>\n</tool_call><|role_end|>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call><|role_end|>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_c>all>\n<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Rome</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<ar_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>\n<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Rome</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_vaue>Paris</arg_value>\n</tool_call><tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Rome</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call><tol_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Rome</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</a rg_key>\n<arg_value>Paris</arg_value>\n</tool_call>\nAll done.',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</to\nl_call>\nAll done.',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_ke >\n<arg_value>Paris</arg_value>\n</tool_call>\nAll done.<|role_end|>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location<xarg_key>\n<arg_value>Paris</arg_value>\n</tool_call>\nAll done.<|role_end|>',
    false,
    false,
  ),
  (
    '<tool_call>\n{"name": "get_weather", "arguments": {"location": "Paris"}}\n</tool_ca ll>',
    false,
    false,
  ),
  (
    '<tool_call>\n{"name": "get_weather", "arguments": {"location": "Paris"}}\n< tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_k\ney>\n<arg_value>Paris</arg_value>\n',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris<arg_value>\n',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_vlue>Par',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<<arg_key>location</arg_key>\n<arg_value>Par',
    false,
    false,
  ),
  ('<tool_c ll>get_weather', false, false),
  ('<to>ol_call>get_weather', false, false),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_\nalue>Paris</arg_value>\n</tool_c',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value></tool_c',
    false,
    false,
  ),
  (
    '<tool_call>nope\n<arg_key>x</arg_key>\n<arg_value>1</arg_valu<e>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>nope\n<arg_key>x</arg_key>\n<ar_value>1</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Pa<ris</arg_value>\n<arg_key>zzz</arg_key>\n<arg_value>1</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n<arg_key>zzz/arg_key>\n<arg_value>1</arg_value>\n</tool_call>',
    false,
    false,
  ),
  ('<tool_call>xet_weather\n</tool_call>', false, false),
  ('<tool_cll>get_weather\n</tool_call>', false, false),
  (
    '<tool_ca>ll>get_weather<arg_key>location</arg_key><arg_value>Paris</arg_value></tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather<arg_key>location</arg_key><arg_value>xaris</arg_value></tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key><arg_value>Paris</arg_value>\n/tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key> <arg_value>Paris</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_vale>Paris</arg_value>\n\n\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_val e>Paris</arg_value>\n\n\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_ey>location</arg_key>\n<arg_value>42</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<argkey>location</arg_key>\n<arg_value>42</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key\n<arg_value>{"a": 1}</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>{"a": 1}</arg_value>\n</tool_all>',
    false,
    false,
  ),
  (
    '<tool_call>get\nweather\n<arg_key>location</arg_key>\n<arg_value>"Paris"</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather<arg_key>location</arg_key>\n<arg_value>"Paris"</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris\n\nFrance</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_ke\ny>\n<arg_value>Paris\nFrance</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>< arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<toolcall>get_weather\n<arg_key>location</arg_key>\n<arg_value></arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_wea>ther\n<arg_key>location</arg_key>\n<arg_value>a<arg_key>b</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>a<arg_ey>b</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>  <Paris  </arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<ar>g_value>  Paris  </arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_time\n<arg_key>tz</arg_key>\n<arg_value>UTC</arg_value>\n<arg\n_key>days</arg_key>\n<arg_value>3</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_time\n<arg_key>tz</arg_key>\n<arg_value>UTC</arg_value>\n<arg_key>days</arg_key\n\n<arg_value>3</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_time\n<arg_key>days</arg_key>\n<arg_value>3</arg_value>\n<arg_key>tz</arg_key>\n<arg_value>UTC</arg_valux>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_time\n<ar\n_key>days</arg_key>\n<arg_value>3</arg_value>\n<arg_key>tz</arg_key>\n<arg_value>UTC</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_time\n<<arg_key>tz</arg_key>\n<arg_value>UTC</arg_value>\n<arg_key>days</arg_key>\n<arg_value>three</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>g t_time\n<arg_key>tz</arg_key>\n<arg_value>UTC</arg_value>\n<arg_key>days</arg_key>\n<arg_value>three</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_time\n<arg_key>tz</arg_key>\n<arg_value>UTC</arg_valu >\n<arg_key>days</arg_key>\n<arg_value>"3"</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_time\n<arg_key>tz</arg_key>\n<arg_value>UTC</arg_value>\n<arg_key>days</arg_key>\n<arg_value>" "</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>set_flags\n<arg_key>verbose</arg_key>\n<arg_value>true</arg_value>\n</tool_cal>l>',
    false,
    false,
  ),
  (
    'tool_call>set_flags\n<arg_key>verbose</arg_key>\n<arg_value>true</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>set_flags\n<arg_key>verbose</arg_key>\n<arg_valueyes</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>set_flags\n<arg_key>vebose</arg_key>\n<arg_value>yes</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_ca',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>\nDone.',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call> <|role_end|>x',
    false,
    false,
  ),
  ('<tool_call>', false, false),
];

/// Replies after the generation prompt, each with whether llama.cpp's
/// (`cd959bae9`) required-call grammar takes the prompt and the reply, with
/// thinking on and off, as `test-gbnf-validator` reported.
final List<(String, bool, bool)> _requiredReplies = [
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>\n<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Rome</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_time\n<arg_key>tz</arg_key>\n<arg_value>UTC</arg_value>\n<arg_key>days</arg_key>\n<arg_value>3</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>book\n<arg_key>to</arg_key>\n<arg_value>B</arg_value>\n<arg_key>from</arg_key>\n<arg_value>A</arg_value>\n<arg_key>seats</arg_key>\n<arg_value>2</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>\nDone.<|role_end|>',
    true,
    true,
  ),
  (
    '<tool_call>nope\n<arg_key>x</arg_key>\n<arg_value>1</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    '<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_ca',
    false,
    false,
  ),
  ('', false, false),
  (
    'Plan\n</think>\n<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    'Plan\n</think>\n<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>\n<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Rome</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    'Plan\n</think>\n<tool_call>get_time\n<arg_key>tz</arg_key>\n<arg_value>UTC</arg_value>\n<arg_key>days</arg_key>\n<arg_value>3</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    'Plan\n</think>\n<tool_call>book\n<arg_key>to</arg_key>\n<arg_value>B</arg_value>\n<arg_key>from</arg_key>\n<arg_value>A</arg_value>\n<arg_key>seats</arg_key>\n<arg_value>2</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    'Plan\n</think>\n<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>\nDone.<|role_end|>',
    true,
    true,
  ),
  (
    'Plan\n</think>\n<tool_call>nope\n<arg_key>x</arg_key>\n<arg_value>1</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    'Plan\n</think>\n<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_ca',
    false,
    false,
  ),
  ('Plan\n</think>\n', false, false),
  (
    'Plan</think><tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    'Plan</think><tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>\n<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Rome</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    'Plan</think><tool_call>get_time\n<arg_key>tz</arg_key>\n<arg_value>UTC</arg_value>\n<arg_key>days</arg_key>\n<arg_value>3</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    'Plan</think><tool_call>book\n<arg_key>to</arg_key>\n<arg_value>B</arg_value>\n<arg_key>from</arg_key>\n<arg_value>A</arg_value>\n<arg_key>seats</arg_key>\n<arg_value>2</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    'Plan</think><tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>\nDone.<|role_end|>',
    true,
    true,
  ),
  (
    'Plan</think><tool_call>nope\n<arg_key>x</arg_key>\n<arg_value>1</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    'Plan</think><tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_ca',
    false,
    false,
  ),
  ('Plan</think>', false, false),
  (
    'Hello <tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    'Hello <tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>\n<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Rome</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    'Hello <tool_call>get_time\n<arg_key>tz</arg_key>\n<arg_value>UTC</arg_value>\n<arg_key>days</arg_key>\n<arg_value>3</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    'Hello <tool_call>book\n<arg_key>to</arg_key>\n<arg_value>B</arg_value>\n<arg_key>from</arg_key>\n<arg_value>A</arg_value>\n<arg_key>seats</arg_key>\n<arg_value>2</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    'Hello <tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>\nDone.<|role_end|>',
    true,
    true,
  ),
  (
    'Hello <tool_call>nope\n<arg_key>x</arg_key>\n<arg_value>1</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    'Hello <tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_ca',
    false,
    false,
  ),
  ('Hello ', false, false),
  (
    'Plan <think>x</think><tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    'Plan <think>x</think><tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>\n<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Rome</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    'Plan <think>x</think><tool_call>get_time\n<arg_key>tz</arg_key>\n<arg_value>UTC</arg_value>\n<arg_key>days</arg_key>\n<arg_value>3</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    'Plan <think>x</think><tool_call>book\n<arg_key>to</arg_key>\n<arg_value>B</arg_value>\n<arg_key>from</arg_key>\n<arg_value>A</arg_value>\n<arg_key>seats</arg_key>\n<arg_value>2</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    'Plan <think>x</think><tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>\nDone.<|role_end|>',
    true,
    true,
  ),
  (
    'Plan <think>x</think><tool_call>nope\n<arg_key>x</arg_key>\n<arg_value>1</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    'Plan <think>x</think><tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_ca',
    false,
    false,
  ),
  ('Plan <think>x</think>', false, false),
  (
    'a</think>b</think><tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    'a</think>b</think><tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>\n<tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Rome</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    'a</think>b</think><tool_call>get_time\n<arg_key>tz</arg_key>\n<arg_value>UTC</arg_value>\n<arg_key>days</arg_key>\n<arg_value>3</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    'a</think>b</think><tool_call>book\n<arg_key>to</arg_key>\n<arg_value>B</arg_value>\n<arg_key>from</arg_key>\n<arg_value>A</arg_value>\n<arg_key>seats</arg_key>\n<arg_value>2</arg_value>\n</tool_call>',
    true,
    true,
  ),
  (
    'a</think>b</think><tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_call>\nDone.<|role_end|>',
    true,
    true,
  ),
  (
    'a</think>b</think><tool_call>nope\n<arg_key>x</arg_key>\n<arg_value>1</arg_value>\n</tool_call>',
    false,
    false,
  ),
  (
    'a</think>b</think><tool_call>get_weather\n<arg_key>location</arg_key>\n<arg_value>Paris</arg_value>\n</tool_ca',
    false,
    false,
  ),
  ('a</think>b</think>', false, false),
];

String _call(String arguments) => '<tool_call>mixed\n$arguments</tool_call>';

String _argument(String name, String value) =>
    '<arg_key>$name</arg_key>\n<arg_value>$value</arg_value>\n';

void main() {
  for (final parallel in [false, true]) {
    test('the lazy call grammar takes what llama.cpp takes, parallel '
        '$parallel', () {
      final rendered = ChatTemplateEngine.render(
        templateSource: File(_template).readAsStringSync(),
        messages: const [
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'Weather in Paris?',
          ),
        ],
        metadata: const {},
        tools: ling3Tools,
        parallelToolCalls: parallel,
      );
      expect(rendered.grammarLazy, isTrue);
      final grammar = GbnfRecognizer(rendered.grammar!);
      for (final (reply, single, parallelCalls) in _autoReplies) {
        expect(
          grammar.accepts(reply),
          parallel ? parallelCalls : single,
          reason: reply,
        );
      }
    });
  }

  for (final enableThinking in [true, false]) {
    test('the required call grammar takes what llama.cpp takes, thinking '
        '$enableThinking', () {
      final rendered = ChatTemplateEngine.render(
        templateSource: File(_template).readAsStringSync(),
        messages: const [
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'Weather in Paris?',
          ),
        ],
        metadata: const {},
        tools: ling3Tools,
        toolChoice: ToolChoice.required,
        enableThinking: enableThinking,
      );
      expect(rendered.grammarLazy, isFalse);
      final grammar = GbnfRecognizer(rendered.grammar!);
      for (final (reply, thinking, notThinking) in _requiredReplies) {
        expect(
          grammar.accepts(reply),
          enableThinking ? thinking : notThinking,
          reason: reply,
        );
      }
    });
  }

  test('the handler builds the parallel auto grammar for its tools', () {
    final grammar = GbnfRecognizer(Ling3Handler().buildGrammar(ling3Tools)!);
    for (final (reply, _, parallelCalls) in _autoReplies) {
      expect(grammar.accepts(reply), parallelCalls, reason: reply);
    }
  });

  test('a value that may be a string or JSON is any text', () {
    final grammar = GbnfRecognizer(
      Ling3Handler().buildGrammar(ling3SchemaTools)!,
    );
    expect(grammar.accepts(_call(_argument('level', '5'))), isTrue);
    expect(grammar.accepts(_call(_argument('level', 'high'))), isTrue);
    expect(grammar.accepts(_call(_argument('maybe', 'x'))), isFalse);
    expect(
      grammar.accepts(
        _call(_argument('level', '1') + _argument('maybe', 'null')),
      ),
      isTrue,
    );
  });
}
