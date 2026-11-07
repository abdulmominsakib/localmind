// coverage:ignore-file
// GENERATED FILE — DO NOT EDIT BY HAND.
//
// Regenerate with: dart run tool/gen_litert_lm_templates.dart
// Source jinja lives under tool/litert_lm_templates/.

import 'litert_lm_chat_template.dart';

/// Canonical chat template for the gemma4 family.
const String _gemma4ChatTemplate = r'''
{%- macro format_parameters(properties, required) -%}
    {%- set standard_keys = ['description', 'type', 'properties', 'required', 'nullable'] -%}
    {%- set ns = namespace(found_first=false) -%}
    {%- for key, value in properties | dictsort -%}
        {%- set add_comma = false -%}
        {%- if key not in standard_keys -%}
            {%- if ns.found_first %},{% endif -%}
            {%- set ns.found_first = true -%}
            {{ key }}:{
            {%- if value['description'] -%}
                description:<|"|>{{ value['description'] }}<|"|>
                {%- set add_comma = true -%}
            {%- endif -%}
            {%- if value['type'] | upper == 'STRING' -%}
                {%- if value['enum'] -%}
                    {%- if add_comma %},{%- else -%} {%- set add_comma = true -%} {% endif -%}
                    enum:{{ format_argument(value['enum']) }}
                {%- endif -%}
            {%- elif value['type'] | upper == 'ARRAY' -%}
                {%- if value['items'] is mapping and value['items'] -%}
                    {%- if add_comma %},{%- else -%} {%- set add_comma = true -%} {% endif -%}
                    items:{
                    {%- set ns_items = namespace(found_first=false) -%}
                    {%- for item_key, item_value in value['items'] | dictsort -%}
                        {%- if item_value is not none -%}
                            {%- if ns_items.found_first %},{% endif -%}
                            {%- set ns_items.found_first = true -%}
                            {%- if item_key == 'properties' -%}
                                properties:{
                                {%- if item_value is mapping -%}
                                    {{- format_parameters(item_value, value['items']['required'] | default([])) -}}
                                {%- endif -%}
                                }
                            {%- elif item_key == 'required' -%}
                                required:[
                                {%- for req_item in item_value -%}
                                    <|"|>{{- req_item -}}<|"|>
                                    {%- if not loop.last %},{% endif -%}
                                {%- endfor -%}
                                ]
                            {%- elif item_key == 'type' -%}
                                {%- if item_value is string -%}
                                    type:{{ format_argument(item_value | upper) }}
                                {%- else -%}
                                    type:{{ format_argument(item_value | map('upper') | list) }}
                                {%- endif -%}
                            {%- else -%}
                                {{ item_key }}:{{ format_argument(item_value) }}
                            {%- endif -%}
                        {%- endif -%}
                    {%- endfor -%}
                    }
                {%- endif -%}
            {%- endif -%}
            {%- if value['nullable'] %}
                {%- if add_comma %},{%- else -%} {%- set add_comma = true -%} {% endif -%}
                nullable:true
            {%- endif -%}
            {%- if value['type'] | upper == 'OBJECT' -%}
                {%- if value['properties'] is defined and value['properties'] is mapping -%}
                    {%- if add_comma %},{%- else -%} {%- set add_comma = true -%} {% endif -%}
                    properties:{
                    {{- format_parameters(value['properties'], value['required'] | default([])) -}}
                    }
                {%- elif value is mapping -%}
                    {%- if add_comma %},{%- else -%} {%- set add_comma = true -%} {% endif -%}
                    properties:{
                    {{- format_parameters(value, value['required'] | default([])) -}}
                    }
                {%- endif -%}
                {%- if value['required'] -%}
                    {%- if add_comma %},{%- else -%} {%- set add_comma = true -%} {% endif -%}
                    required:[
                    {%- for item in value['required'] | default([]) -%}
                        <|"|>{{- item -}}<|"|>
                        {%- if not loop.last %},{% endif -%}
                    {%- endfor -%}
                    ]
                {%- endif -%}
            {%- endif -%}
            {%- if add_comma %},{%- else -%} {%- set add_comma = true -%} {% endif -%}
            type:<|"|>{{ value['type'] | upper }}<|"|>}
        {%- endif -%}
    {%- endfor -%}
{%- endmacro -%}
{%- macro format_function_declaration(tool_data) -%}
    declaration:{{- tool_data['function']['name'] -}}{description:<|"|>{{- tool_data['function']['description'] -}}<|"|>
    {%- set params = tool_data['function']['parameters'] -%}
    {%- if params -%}
        ,parameters:{
        {%- if params['properties'] -%}
            properties:{ {{- format_parameters(params['properties'], params['required']) -}} },
        {%- endif -%}
        {%- if params['required'] -%}
            required:[
            {%- for item in params['required'] -%}
                <|"|>{{- item -}}<|"|>
                {{- ',' if not loop.last -}}
            {%- endfor -%}
            ],
        {%- endif -%}
        {%- if params['type'] -%}
            type:<|"|>{{- params['type'] | upper -}}<|"|>}
        {%- endif -%}
    {%- endif -%}
    {%- if 'response' in tool_data['function'] -%}
        {%- set response_declaration = tool_data['function']['response'] -%}
        ,response:{
        {%- if response_declaration['description'] -%}
            description:<|"|>{{- response_declaration['description'] -}}<|"|>,
        {%- endif -%}
        {%- if response_declaration['type'] | upper == 'OBJECT' -%}
            type:<|"|>{{- response_declaration['type'] | upper -}}<|"|>}
        {%- endif -%}
    {%- endif -%}
    }
{%- endmacro -%}
{%- macro format_argument(argument, escape_keys=True) -%}
    {%- if argument is string -%}
        {{- '<|"|>' + argument + '<|"|>' -}}
    {%- elif argument is boolean -%}
        {{- 'true' if argument else 'false' -}}
    {%- elif argument is mapping -%}
        {{- '{' -}}
        {%- set ns = namespace(found_first=false) -%}
        {%- for key, value in argument | dictsort -%}
            {%- if ns.found_first %},{% endif -%}
            {%- set ns.found_first = true -%}
            {%- if escape_keys -%}
                {{- '<|"|>' + key + '<|"|>' -}}
            {%- else -%}
                {{- key -}}
            {%- endif -%}
            :{{- format_argument(value, escape_keys=escape_keys) -}}
        {%- endfor -%}
        {{- '}' -}}
    {%- elif argument is sequence -%}
        {{- '[' -}}
        {%- for item in argument -%}
            {{- format_argument(item, escape_keys=escape_keys) -}}
            {%- if not loop.last %},{% endif -%}
        {%- endfor -%}
        {{- ']' -}}
    {%- else -%}
        {{- argument -}}
    {%- endif -%}
{%- endmacro -%}
{%- macro strip_thinking(text) -%}
    {%- set ns = namespace(result='') -%}
    {%- for part in text.split('<channel|>') -%}
        {%- if '<|channel>' in part -%}
            {%- set ns.result = ns.result + part.split('<|channel>')[0] -%}
        {%- else -%}
            {%- set ns.result = ns.result + part -%}
        {%- endif -%}
    {%- endfor -%}
    {{- ns.result | trim -}}
{%- endmacro -%}

{%- macro format_tool_response_block(tool_name, response) -%}
    {{- '<|tool_response>' -}}
    {%- if response is mapping -%}
        {{- 'response:' + tool_name + '{' -}}
        {%- for key, value in response | dictsort -%}
            {{- key -}}:{{- format_argument(value, escape_keys=False) -}}
            {%- if not loop.last %},{% endif -%}
        {%- endfor -%}
        {{- '}' -}}
    {%- else -%}
        {{- 'response:' + tool_name + '{value:' + format_argument(response, escape_keys=False) + '}' -}}
    {%- endif -%}
    {{- '<tool_response|>' -}}
{%- endmacro -%}

{%- set ns = namespace(prev_message_type=None) -%}
{%- set loop_messages = messages -%}
{#- Handle System/Tool Definitions Block -#}
{%- if (enable_thinking is defined and enable_thinking) or tools or messages[0]['role'] in ['system', 'developer'] -%}
    {{- '<|turn>system\n' -}}

    {#- Inject Thinking token at the very top of the FIRST system turn -#}
    {%- if enable_thinking is defined and enable_thinking -%}
        {{- '<|think|>\n' -}}
        {%- set ns.prev_message_type = 'think' -%}
    {%- endif -%}

    {%- if messages[0]['role'] in ['system', 'developer'] -%}
        {{- messages[0]['content'] | trim -}}
        {%- set loop_messages = messages[1:] -%}
    {%- endif -%}

    {%- if tools -%}
        {%- for tool in tools %}
            {{- '<|tool>' -}}
            {{- format_function_declaration(tool) | trim -}}
            {{- '<tool|>' -}}
        {%- endfor %}
        {%- set ns.prev_message_type = 'tool' -%}
    {%- endif -%}

    {{- '<turn|>\n' -}}
{%- endif %}

{#- Pre-scan: find last user message index for reasoning guard -#}
{%- set ns_turn = namespace(last_user_idx=-1) -%}
{%- for i in range(loop_messages | length) -%}
    {%- if loop_messages[i]['role'] == 'user' -%}
        {%- set ns_turn.last_user_idx = i -%}
    {%- endif -%}
{%- endfor -%}

{#- Loop through messages -#}
{%- for message in loop_messages -%}
    {%- if message['role'] != 'tool' -%}
    {%- set ns.prev_message_type = None -%}
    {%- set role = 'model' if message['role'] == 'assistant' else message['role'] -%}
    {#- Detect continuation: suppress duplicate <|turn>model when previous non-tool message was also assistant -#}
    {%- set prev_nt = namespace(role=None, found=false) -%}
    {%- if loop.index0 > 0 -%}
        {%- for j in range(loop.index0 - 1, -1, -1) -%}
            {%- if not prev_nt.found -%}
                {%- if loop_messages[j]['role'] != 'tool' -%}
                    {%- set prev_nt.role = loop_messages[j]['role'] -%}
                    {%- set prev_nt.found = true -%}
                {%- endif -%}
            {%- endif -%}
        {%- endfor -%}
    {%- endif -%}
    {%- set continue_same_model_turn = (role == 'model' and prev_nt.role == 'assistant') -%}
    {%- if not continue_same_model_turn -%}
        {{- '<|turn>' + role + '\n' }}
    {%- endif -%}

    {#- Render reasoning/reasoning_content as thinking channel -#}
    {%- set thinking_text = message.get('reasoning') or message.get('reasoning_content') -%}
    {%- if thinking_text and loop.index0 > ns_turn.last_user_idx and message.get('tool_calls') -%}
        {{- '<|channel>thought\n' + thinking_text + '\n<channel|>' -}}
    {%- endif -%}

            {%- if message['tool_calls'] -%}
                {%- for tool_call in message['tool_calls'] -%}
                    {%- set function = tool_call['function'] -%}
                    {{- '<|tool_call>call:' + function['name'] + '{' -}}
                    {%- if function['arguments'] is mapping -%}
                        {%- set ns_args = namespace(found_first=false) -%}
                        {%- for key, value in function['arguments'] | dictsort -%}
                            {%- if ns_args.found_first %},{% endif -%}
                            {%- set ns_args.found_first = true -%}
                            {{- key -}}:{{- format_argument(value, escape_keys=False) -}}
                        {%- endfor -%}
                    {%- elif function['arguments'] is string -%}
                        {{- function['arguments'] -}}
                    {%- endif -%}
                    {{- '}<tool_call|>' -}}
                {%- endfor -%}
                {%- set ns.prev_message_type = 'tool_call' -%}
            {%- endif -%}

            {%- set ns_tr_out = namespace(flag=false) -%}
            {%- if message.get('tool_responses') -%}
                {#- Legacy: tool_responses embedded on the assistant message (Google/Gemma native) -#}
                {%- for tool_response in message['tool_responses'] -%}
                    {{- format_tool_response_block(tool_response['name'] | default('unknown'), tool_response['response']) -}}
                    {%- set ns_tr_out.flag = true -%}
                    {%- set ns.prev_message_type = 'tool_response' -%}
                {%- endfor -%}
            {%- elif message.get('tool_calls') -%}
                {#- OpenAI Chat Completions: forward-scan consecutive role:tool messages -#}
                {%- set ns_tool_scan = namespace(stopped=false) -%}
                {%- for k in range(loop.index0 + 1, loop_messages | length) -%}
                    {%- if ns_tool_scan.stopped -%}
                    {%- elif loop_messages[k]['role'] != 'tool' -%}
                        {%- set ns_tool_scan.stopped = true -%}
                    {%- else -%}
                        {%- set follow = loop_messages[k] -%}
                        {#- Resolve tool_call_id to function name -#}
                        {%- set ns_tname = namespace(name=follow.get('name') | default('unknown')) -%}
                        {%- for tc in message['tool_calls'] -%}
                            {%- if tc.get('id') == follow.get('tool_call_id') -%}
                                {%- set ns_tname.name = tc['function']['name'] -%}
                            {%- endif -%}
                        {%- endfor -%}
                        {#- Handle content as string or content-parts array -#}
                        {%- set tool_body = follow.get('content') -%}
                        {%- if tool_body is string -%}
                            {{- format_tool_response_block(ns_tname.name, tool_body) -}}
                        {%- elif tool_body is sequence and tool_body is not string -%}
                            {%- set ns_txt = namespace(s='') -%}
                            {%- for part in tool_body -%}
                                {%- if part.get('type') == 'text' -%}
                                    {%- set ns_txt.s = ns_txt.s + (part.get('text') | default('')) -%}
                                {%- endif -%}
                            {%- endfor -%}
                            {{- format_tool_response_block(ns_tname.name, ns_txt.s) -}}
                        {%- else -%}
                            {{- format_tool_response_block(ns_tname.name, tool_body) -}}
                        {%- endif -%}
                        {%- set ns_tr_out.flag = true -%}
                        {%- set ns.prev_message_type = 'tool_response' -%}
                    {%- endif -%}
                {%- endfor -%}
            {%- endif -%}

            {%- if message['content'] is string -%}
                {%- if role == 'model' -%}
                    {{- strip_thinking(message['content']) -}}
                {%- else -%}
                    {{- message['content'] | trim -}}
                {%- endif -%}
            {%- elif message['content'] is sequence -%}
                {%- for item in message['content'] -%}
                    {%- if item['type'] == 'text' -%}
                        {%- if role == 'model' -%}
                            {{- strip_thinking(item['text']) -}}
                        {%- else -%}
                            {{- item['text'] | trim -}}
                        {%- endif -%}
                    {%- elif item['type'] == 'image' -%}
                        {{- '<|image|>' -}}
                        {%- set ns.prev_message_type = 'image' -%}
                    {%- elif item['type'] == 'audio' -%}
                        {{- '<|audio|>' -}}
                        {%- set ns.prev_message_type = 'audio' -%}
                    {%- elif item['type'] == 'video' -%}
                        {{- '<|video|>' -}}
                        {%- set ns.prev_message_type = 'video' -%}
                    {%- endif -%}
                {%- endfor -%}
            {%- endif -%}

        {%- if ns.prev_message_type == 'tool_call' and not ns_tr_out.flag -%}
            {{- '<|tool_response>' -}}
        {%- elif not (ns_tr_out.flag and not message.get('content')) -%}
            {{- '<turn|>\n' -}}
        {%- endif -%}
    {%- endif -%}
{%- endfor -%}

{%- if add_generation_prompt -%}
    {%- if ns.prev_message_type != 'tool_response' and ns.prev_message_type != 'tool_call' -%}
        {{- '<|turn>model\n' -}}
        {%- if not enable_thinking | default(false) -%}
            {{- '<|channel>thought\n<channel|>' -}}
        {%- endif -%}
    {%- endif -%}
{%- endif -%}
''';

/// Canonical chat template for the gemma3n family.
const String _gemma3nChatTemplate = r'''
{%- if messages[0]['role'] == 'system' -%}
    {%- if messages[0]['content'] is string -%}
        {%- set first_user_prefix = messages[0]['content'] + '

' -%}
    {%- else -%}
        {%- set first_user_prefix = messages[0]['content'][0]['text'] + '

' -%}
    {%- endif -%}
    {%- set loop_messages = messages[1:] -%}
{%- else -%}
    {%- set first_user_prefix = "" -%}
    {%- set loop_messages = messages -%}
{%- endif -%}
{%- for message in loop_messages -%}
    {%- if (message['role'] == 'user') != (loop.index0 % 2 == 0) -%}
        {{ raise_exception("Conversation roles must alternate user/assistant/user/assistant/...") }}
    {%- endif -%}
    {%- if (message['role'] == 'assistant') -%}
        {%- set role = "model" -%}
    {%- else -%}
        {%- set role = message['role'] -%}
    {%- endif -%}
    {{ '<start_of_turn>' + role + '
' + (first_user_prefix if loop.first else "") }}
    {%- if message['content'] is string -%}
        {{ message['content'] | trim }}
    {%- elif message['content'] is iterable -%}
        {%- for item in message['content'] -%}
            {%- if item['type'] == 'audio' -%}
                {{ '<audio_soft_token>' }}
            {%- elif item['type'] == 'image' -%}
                {{ '<image_soft_token>' }}
            {%- elif item['type'] == 'text' -%}
                {{ item['text'] | trim }}
            {%- endif -%}
        {%- endfor -%}
    {%- else -%}
        {{ raise_exception("Invalid content type") }}
    {%- endif -%}
    {{ '<end_of_turn>
' }}
{%- endfor -%}
{%- if add_generation_prompt -%}
    {{'<start_of_turn>model
'}}
{%- endif -%}
''';

/// Canonical chat template for the gemma family.
const String _gemmaChatTemplate = r'''
{%- if messages[0]['role'] == 'system' -%}
    {%- if messages[0]['content'] is string -%}
        {%- set first_user_prefix = messages[0]['content'] + '

' -%}
    {%- else -%}
        {%- set first_user_prefix = messages[0]['content'][0]['text'] + '

' -%}
    {%- endif -%}
    {%- set loop_messages = messages[1:] -%}
{%- else -%}
    {%- set first_user_prefix = "" -%}
    {%- set loop_messages = messages -%}
{%- endif -%}
{%- for message in loop_messages -%}
    {%- if (message['role'] == 'user') != (loop.index0 % 2 == 0) -%}
        {{ raise_exception("Conversation roles must alternate user/assistant/user/assistant/...") }}
    {%- endif -%}
    {%- if (message['role'] == 'assistant') -%}
        {%- set role = "model" -%}
    {%- else -%}
        {%- set role = message['role'] -%}
    {%- endif -%}
    {{ '<start_of_turn>' + role + '
' + (first_user_prefix if loop.first else "") }}
    {%- if message['content'] is string -%}
        {{ message['content'] | trim }}
    {%- elif message['content'] is iterable -%}
        {%- for item in message['content'] -%}
            {%- if item['type'] == 'image' -%}
                {{ '<start_of_image>' }}
            {%- elif item['type'] == 'text' -%}
                {{ item['text'] | trim }}
            {%- endif -%}
        {%- endfor -%}
    {%- else -%}
        {{ raise_exception("Invalid content type") }}
    {%- endif -%}
    {{ '<end_of_turn>
' }}
{%- endfor -%}
{%- if add_generation_prompt -%}
    {{'<start_of_turn>model
'}}
{%- endif -%}
''';

/// Canonical chat template for the qwen3 family.
const String _qwen3ChatTemplate = r'''
{%- if tools %}
    {{- '<|im_start|>system\n' }}
    {%- if messages[0].role == 'system' %}
        {{- messages[0].content + '\n\n' }}
    {%- endif %}
    {{- "# Tools\n\nYou may call one or more functions to assist with the user query.\n\nYou are provided with function signatures within <tools></tools> XML tags:\n<tools>" }}
    {%- for tool in tools %}
        {{- "\n" }}
        {{- tool | tojson }}
    {%- endfor %}
    {{- "\n</tools>\n\nFor each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:\n<tool_call>\n{\"name\": <function-name>, \"arguments\": <args-json-object>}\n</tool_call><|im_end|>\n" }}
{%- else %}
    {%- if messages[0].role == 'system' %}
        {{- '<|im_start|>system\n' + messages[0].content + '<|im_end|>\n' }}
    {%- endif %}
{%- endif %}
{%- set ns = namespace(multi_step_tool=true, last_query_index=messages|length - 1) %}
{%- for forward_message in messages %}
    {%- set index = (messages|length - 1) - loop.index0 %}
    {%- set message = messages[index] %}
    {%- set current_content = message.content if message.content is defined and message.content is not none else '' %}
    {%- set tool_start = '<tool_response>' %}
    {%- set tool_start_length = tool_start|length %}
    {%- set start_of_message = current_content[:tool_start_length] %}
    {%- set tool_end = '</tool_response>' %}
    {%- set tool_end_length = tool_end|length %}
    {%- set start_pos = (current_content|length) - tool_end_length %}
    {%- if start_pos < 0 %}
        {%- set start_pos = 0 %}
    {%- endif %}
    {%- set end_of_message = current_content[start_pos:] %}
    {%- if ns.multi_step_tool and message.role == "user" and not(start_of_message == tool_start and end_of_message == tool_end) %}
        {%- set ns.multi_step_tool = false %}
        {%- set ns.last_query_index = index %}
    {%- endif %}
{%- endfor %}
{%- for message in messages %}
    {%- if (message.role == "user") or (message.role == "system" and not loop.first) %}
        {{- '<|im_start|>' + message.role + '\n' + message.content + '<|im_end|>' + '\n' }}
    {%- elif message.role == "assistant" %}
        {%- set m_content = message.content if message.content is defined and message.content is not none else '' %}
        {%- set content = m_content %}
        {%- set reasoning_content = '' %}
        {%- if message.reasoning_content is defined and message.reasoning_content is not none %}
            {%- set reasoning_content = message.reasoning_content %}
        {%- else %}
            {%- if '</think>' in m_content %}
                {%- set content = (m_content.split('</think>')|last).lstrip('\n') %}
                {%- set reasoning_content = (m_content.split('</think>')|first).rstrip('\n') %}
                {%- set reasoning_content = (reasoning_content.split('<think>')|last).lstrip('\n') %}
            {%- endif %}
        {%- endif %}
        {%- if loop.index0 > ns.last_query_index %}
            {%- if loop.last or (not loop.last and (not reasoning_content.strip() == '')) %}
                {{- '<|im_start|>' + message.role + '\n<think>\n' + reasoning_content.strip('\n') + '\n</think>\n\n' + content.lstrip('\n') }}
            {%- else %}
                {{- '<|im_start|>' + message.role + '\n' + content }}
            {%- endif %}
        {%- else %}
            {{- '<|im_start|>' + message.role + '\n' + content }}
        {%- endif %}
        {%- if message.tool_calls %}
            {%- for tool_call in message.tool_calls %}
                {%- if (loop.first and content) or (not loop.first) %}
                    {{- '\n' }}
                {%- endif %}
                {%- if tool_call.function %}
                    {%- set tool_call = tool_call.function %}
                {%- endif %}
                {{- '<tool_call>\n{"name": "' }}
                {{- tool_call.name }}
                {{- '", "arguments": ' }}
                {%- if tool_call.arguments is string %}
                    {{- tool_call.arguments }}
                {%- else %}
                    {{- tool_call.arguments | tojson }}
                {%- endif %}
                {{- '}\n</tool_call>' }}
            {%- endfor %}
        {%- endif %}
        {{- '<|im_end|>\n' }}
    {%- elif message.role == "tool" %}
        {%- if loop.first or (messages[loop.index0 - 1].role != "tool") %}
            {{- '<|im_start|>user' }}
        {%- endif %}
        {{- '\n<tool_response>\n' }}
        {{- message.content }}
        {{- '\n</tool_response>' }}
        {%- if loop.last or (messages[loop.index0 + 1].role != "tool") %}
            {{- '<|im_end|>\n' }}
        {%- endif %}
    {%- endif %}
{%- endfor %}
{%- if add_generation_prompt %}
    {{- '<|im_start|>assistant\n' }}
    {%- if enable_thinking is defined and enable_thinking is false %}
        {{- '<think>\n\n</think>\n\n' }}
    {%- endif %}
{%- endif %}''';

/// Canonical chat template for the qwen25 family.
const String _qwen25ChatTemplate = r'''
{%- if tools %}
    {{- '<|im_start|>system\n' }}
    {%- if messages[0]['role'] == 'system' %}
        {{- messages[0]['content'] }}
    {%- else %}
        {{- 'You are Qwen, created by Alibaba Cloud. You are a helpful assistant.' }}
    {%- endif %}
    {{- "\n\n# Tools\n\nYou may call one or more functions to assist with the user query.\n\nYou are provided with function signatures within <tools></tools> XML tags:\n<tools>" }}
    {%- for tool in tools %}
        {{- "\n" }}
        {{- tool | tojson }}
    {%- endfor %}
    {{- "\n</tools>\n\nFor each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:\n<tool_call>\n{\"name\": <function-name>, \"arguments\": <args-json-object>}\n</tool_call><|im_end|>\n" }}
{%- else %}
    {%- if messages[0]['role'] == 'system' %}
        {{- '<|im_start|>system\n' + messages[0]['content'] + '<|im_end|>\n' }}
    {%- else %}
        {{- '<|im_start|>system\nYou are Qwen, created by Alibaba Cloud. You are a helpful assistant.<|im_end|>\n' }}
    {%- endif %}
{%- endif %}
{%- for message in messages %}
    {%- if (message.role == "user") or (message.role == "system" and not loop.first) or (message.role == "assistant" and not message.tool_calls) %}
        {{- '<|im_start|>' + message.role + '\n' + message.content + '<|im_end|>' + '\n' }}
    {%- elif message.role == "assistant" %}
        {{- '<|im_start|>' + message.role }}
        {%- if message.content %}
            {{- '\n' + message.content }}
        {%- endif %}
        {%- for tool_call in message.tool_calls %}
            {%- if tool_call.function is defined %}
                {%- set tool_call = tool_call.function %}
            {%- endif %}
            {{- '\n<tool_call>\n{"name": "' }}
            {{- tool_call.name }}
            {{- '", "arguments": ' }}
            {{- tool_call.arguments | tojson }}
            {{- '}\n</tool_call>' }}
        {%- endfor %}
        {{- '<|im_end|>\n' }}
    {%- elif message.role == "tool" %}
        {%- if (loop.index0 == 0) or (messages[loop.index0 - 1].role != "tool") %}
            {{- '<|im_start|>user' }}
        {%- endif %}
        {{- '\n<tool_response>\n' }}
        {{- message.content }}
        {{- '\n</tool_response>' }}
        {%- if loop.last or (messages[loop.index0 + 1].role != "tool") %}
            {{- '<|im_end|>\n' }}
        {%- endif %}
    {%- endif %}
{%- endfor %}
{%- if add_generation_prompt %}
    {{- '<|im_start|>assistant\n' }}
{%- endif %}
''';

/// Built-in LiteRT-LM chat templates, matched in order.
///
/// The first entry whose [LiteRtLmChatTemplate.matches] returns
/// true for the bundle filename wins, so more specific families
/// must precede broader ones.
const List<LiteRtLmChatTemplate> kLiteRtLmChatTemplates = [
  LiteRtLmChatTemplate(
    id: 'gemma4',
    template: _gemma4ChatTemplate,
    familyMatches: ['gemma-4', 'gemma4'],
    bosToken: '<bos>',
    eosToken: '<turn|>',
    thinkingStartTag: '<|channel>thought\n',
    thinkingEndTag: '<channel|>',
  ),
  LiteRtLmChatTemplate(
    id: 'gemma3n',
    template: _gemma3nChatTemplate,
    familyMatches: ['gemma-3n', 'gemma3n'],
    bosToken: '<bos>',
    eosToken: '<end_of_turn>',
    thinkingStartTag: '<|channel>thought\n',
    thinkingEndTag: '<channel|>',
  ),
  LiteRtLmChatTemplate(
    id: 'gemma',
    template: _gemmaChatTemplate,
    familyMatches: ['gemma-3', 'gemma3', 'gemma-2', 'gemma2'],
    bosToken: '<bos>',
    eosToken: '<end_of_turn>',
    thinkingStartTag: '<|channel>thought\n',
    thinkingEndTag: '<channel|>',
  ),
  LiteRtLmChatTemplate(
    id: 'qwen3',
    template: _qwen3ChatTemplate,
    familyMatches: ['qwen3', 'qwen-3'],
    bosToken: '',
    eosToken: '<|im_end|>',
    thinkingStartTag: '<think>',
    thinkingEndTag: '</think>',
  ),
  LiteRtLmChatTemplate(
    id: 'qwen25',
    template: _qwen25ChatTemplate,
    familyMatches: ['qwen2.5', 'qwen-2.5', 'qwen2'],
    bosToken: '',
    eosToken: '<|im_end|>',
    thinkingStartTag: '<think>',
    thinkingEndTag: '</think>',
  ),
];
