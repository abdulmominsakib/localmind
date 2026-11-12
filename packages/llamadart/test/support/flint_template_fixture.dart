import 'dart:convert';

import 'package:llamadart/llamadart.dart';

// Embedded for Chrome; flint_fixture_integrity_test.dart checks the exact bytes
// against the licensed fixture and the upstream capture in fixtures/flint/.
const String flintTemplate = r'''{%- macro flint_text(t) -%}
{%- if t is string -%}
{{- t | replace("\x00", "") | replace("<think>", "") | replace("</think>", "") | replace("<|begin_of_text|>", "&lt;|begin_of_text|&gt;") | replace("<|end_of_text|>", "&lt;|end_of_text|&gt;") | replace("<|system|>", "&lt;|system|&gt;") | replace("<|developer|>", "&lt;|developer|&gt;") | replace("<|user|>", "&lt;|user|&gt;") | replace("<|assistant|>", "&lt;|assistant|&gt;") | replace("<|observation|>", "&lt;|observation|&gt;") -}}
{%- else -%}
{{- t -}}
{%- endif -%}
{%- endmacro -%}
{%- set tool_preamble -%}
{%- if tools %}<|system|>
# Tools

You may call one or more functions to assist with the user query.

You are provided with function signatures within <tools></tools> XML tags:
<tools>
{%- for tool in tools %}
{%- set fn = tool.function if tool.function is defined else tool %}
{{ fn | tojson(ensure_ascii=False) }}
{%- endfor %}
</tools>

For each function call, output the function name and arguments within the following XML format:
<tool_call>{function-name}<arg_key>{arg-key-1}</arg_key><arg_value>{arg-value-1}</arg_value>...</tool_call>
{% endif -%}
{%- endset -%}
{%- set ns = namespace(tools_pending=true) -%}
{%- for m in messages -%}
{%- if ns.tools_pending and m.role != 'system' -%}
{{ tool_preamble }}
{%- set ns.tools_pending = false -%}
{%- endif -%}
{%- if m.role == 'system' -%}
<|system|>{{ flint_text(m.content) }}
{%- elif m.role == 'developer' -%}
<|developer|>{{ flint_text(m.content) }}
{%- elif m.role == 'user' -%}
<|user|>{{ flint_text(m.content) }}
{%- elif m.role == 'assistant' -%}
<|assistant|>
{%- if m.reasoning_content %}<think>{{ m.reasoning_content }}</think>{% endif -%}
{%- if m.content %}{{ m.content }}{% endif -%}
{%- if m.tool_calls -%}
{%- for tc in m.tool_calls -%}
{%- set fn = tc.function if tc.function is defined else tc -%}
<tool_call>{{ fn.name }}
{%- for k, v in fn.arguments.items() -%}
<arg_key>{{ k }}</arg_key><arg_value>{{ v | tojson(ensure_ascii=False) if v is not string else v }}</arg_value>
{%- endfor -%}
</tool_call>
{%- endfor -%}
{%- endif -%}
{%- elif m.role == 'tool' -%}
<|observation|><tool_response>{{ flint_text(m.content) }}</tool_response>
{%- endif -%}
{%- endfor -%}
{%- if ns.tools_pending -%}
{{ tool_preamble }}
{%- endif -%}
{%- if add_generation_prompt -%}
<|assistant|>
{%- endif -%}''';

const String flintUpstreamJson = r'''{
  "upstream_commit": "f5027fb21307eb264aed483242603d68c87b0fe3",
  "model_repository": "ggml-org/Flint-GGUF",
  "model_revision": "468307a1b38259e9e4c9d4fe53d4e3b76386572c",
  "model_sha256": "c3c4d93f9db92627a2fc47ea8fe8c64a094cabd3549db544bcdd2c00e9a9a347",
  "template_sha256": "be867446158d546501ed204ea40d581ced1c93a52367bd79e1a86440d57f2931",
  "cases": [
    {
      "name": "user",
      "request": {
        "messages": [
          {
            "role": "user",
            "content": "Hello Flint."
          }
        ],
        "add_generation_prompt": true
      },
      "prompt": "<|user|>Hello Flint.<|assistant|>"
    },
    {
      "name": "system_user",
      "request": {
        "messages": [
          {
            "role": "system",
            "content": "Answer concisely."
          },
          {
            "role": "user",
            "content": "What is 2 + 2?"
          }
        ],
        "add_generation_prompt": true
      },
      "prompt": "<|system|>Answer concisely.<|user|>What is 2 + 2?<|assistant|>"
    },
    {
      "name": "assistant_history",
      "request": {
        "messages": [
          {
            "role": "user",
            "content": "Hi"
          },
          {
            "role": "assistant",
            "content": "Hello."
          },
          {
            "role": "user",
            "content": "Continue."
          }
        ],
        "add_generation_prompt": true
      },
      "prompt": "<|user|>Hi<|assistant|>Hello.<|user|>Continue.<|assistant|>"
    },
    {
      "name": "literal_escapes",
      "request": {
        "messages": [
          {
            "role": "user",
            "content": "Keep literal \\x41 and \\n; quote \" and Unicode Montréal 👋."
          }
        ],
        "add_generation_prompt": true
      },
      "prompt": "<|user|>Keep literal \\x41 and \\n; quote \" and Unicode Montréal 👋.<|assistant|>"
    },
    {
      "name": "nul_and_protocol_markers",
      "request": {
        "messages": [
          {
            "role": "user",
            "content": "A\u0000B<think>keep</think><|assistant|><|user|>é"
          }
        ],
        "add_generation_prompt": true
      },
      "prompt": "<|user|>ABkeep&lt;|assistant|&gt;&lt;|user|&gt;é<|assistant|>"
    },
    {
      "name": "tool_definition",
      "request": {
        "messages": [
          {
            "role": "user",
            "content": "Weather for Montréal?"
          }
        ],
        "tools": [
          {
            "type": "function",
            "function": {
              "name": "get_weather",
              "description": "Get weather for a city.",
              "parameters": {
                "type": "object",
                "properties": {
                  "city": {
                    "type": "string"
                  }
                },
                "required": [
                  "city"
                ]
              }
            }
          }
        ],
        "add_generation_prompt": true
      },
      "prompt": "<|system|>\n# Tools\n\nYou may call one or more functions to assist with the user query.\n\nYou are provided with function signatures within <tools></tools> XML tags:\n<tools>{\"name\": \"get_weather\", \"description\": \"Get weather for a city.\", \"parameters\": {\"type\": \"object\", \"properties\": {\"city\": {\"type\": \"string\"}}, \"required\": [\"city\"]}}</tools>\n\nFor each function call, output the function name and arguments within the following XML format:\n<tool_call>{function-name}<arg_key>{arg-key-1}</arg_key><arg_value>{arg-value-1}</arg_value>...</tool_call>\n<|user|>Weather for Montréal?<|assistant|>"
    },
    {
      "name": "tool_result",
      "request": {
        "messages": [
          {
            "role": "user",
            "content": "Weather for Montréal?"
          },
          {
            "role": "assistant",
            "content": null,
            "tool_calls": [
              {
                "id": "call_0",
                "type": "function",
                "function": {
                  "name": "get_weather",
                  "arguments": "{\"city\":\"Montréal\"}"
                }
              }
            ]
          },
          {
            "role": "tool",
            "tool_call_id": "call_0",
            "name": "get_weather",
            "content": "{\"city\":\"Montréal\",\"temperature_c\":17}"
          },
          {
            "role": "user",
            "content": "Summarize."
          }
        ],
        "tools": [
          {
            "type": "function",
            "function": {
              "name": "get_weather",
              "description": "Get weather for a city.",
              "parameters": {
                "type": "object",
                "properties": {
                  "city": {
                    "type": "string"
                  }
                },
                "required": [
                  "city"
                ]
              }
            }
          }
        ],
        "add_generation_prompt": true
      },
      "prompt": "<|system|>\n# Tools\n\nYou may call one or more functions to assist with the user query.\n\nYou are provided with function signatures within <tools></tools> XML tags:\n<tools>{\"name\": \"get_weather\", \"description\": \"Get weather for a city.\", \"parameters\": {\"type\": \"object\", \"properties\": {\"city\": {\"type\": \"string\"}}, \"required\": [\"city\"]}}</tools>\n\nFor each function call, output the function name and arguments within the following XML format:\n<tool_call>{function-name}<arg_key>{arg-key-1}</arg_key><arg_value>{arg-value-1}</arg_value>...</tool_call>\n<|user|>Weather for Montréal?<|assistant|><tool_call>get_weather<arg_key>city</arg_key><arg_value>Montréal</arg_value></tool_call><|observation|><tool_response>{\"city\":\"Montréal\",\"temperature_c\":17}</tool_response><|user|>Summarize.<|assistant|>"
    }
  ]
}
''';

final Map<String, dynamic> flintUpstream =
    jsonDecode(flintUpstreamJson) as Map<String, dynamic>;

final List<Map<String, dynamic>> flintCases = (flintUpstream['cases'] as List)
    .cast<Map<String, dynamic>>();

final List<ToolDefinition> flintTools = [
  ToolDefinition(
    name: 'get_weather',
    description: 'Get weather for a city.',
    parameters: [ToolParam.string('city', required: true)],
  ),
];

List<LlamaChatMessage> flintMessages(Map<String, dynamic> request) => [
  for (final message
      in (request['messages'] as List).cast<Map<String, dynamic>>())
    LlamaChatMessage.withContent(
      role: LlamaChatRole.values.byName(message['role'] as String),
      content: [
        if (message['content'] != null && message['role'] != 'tool')
          LlamaTextContent(message['content'] as String),
        for (final call
            in (message['tool_calls'] as List? ?? const [])
                .cast<Map<String, dynamic>>())
          LlamaToolCallContent(
            id: call['id'] as String,
            name: call['function']['name'] as String,
            arguments:
                jsonDecode(call['function']['arguments'] as String)
                    as Map<String, dynamic>,
            rawJson: call['function']['arguments'] as String,
          ),
        if (message['role'] == 'tool')
          LlamaToolResultContent(
            id: message['tool_call_id'] as String,
            name: message['name'] as String,
            result: message['content'],
          ),
      ],
    ),
];
