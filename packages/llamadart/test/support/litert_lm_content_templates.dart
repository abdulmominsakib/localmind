import 'package:dinja/dinja.dart';
import 'package:llamadart/src/core/exceptions.dart';

/// Bundle templates that read message content as a string, as bundles built
/// for LiteRT-LM runtimes before v0.18 do, keyed by how they read it.
const Map<String, String> liteRtLmStringContentTemplates = {
  'interpolating':
      '{%- for message in messages -%}\n'
      '<|im_start|>\n'
      '{{ message.content }}<|im_end|>\n'
      '{% endfor -%}',
  'concatenating':
      '{%- for message in messages -%}\n'
      "{{ '<|im_start|>\\n' + message.content + '<|im_end|>\\n' }}"
      '{%- endfor -%}',
  'string-only':
      '{%- for message in messages -%}\n'
      '{%- if message.content is string -%}\n'
      '{%- set text = message.content -%}\n'
      '{%- else -%}\n'
      "{%- set text = '' -%}\n"
      '{%- endif -%}\n'
      '<|im_start|>\n'
      '{{ text }}<|im_end|>\n'
      '{% endfor -%}',
};

/// A bundle template that reads content parts and strings.
const String liteRtLmPartsContentTemplate =
    '{%- for message in messages -%}\n'
    '<|im_start|>\n'
    '{%- if message.content is string -%}\n'
    '{{ message.content }}\n'
    '{%- else -%}\n'
    '{%- for part in message.content -%}\n'
    "{%- if part.type == 'text' -%}{{ part.text }}{%- endif -%}\n"
    '{%- endfor -%}\n'
    '{%- endif -%}\n'
    '<|im_end|>\n'
    '{% endfor -%}';

/// Renders [template] for one message with [content], as a LiteRT-LM runtime
/// renders the single message of a conversation. Throws a
/// [LlamaModelException] when the template fails, as the C API 1.0 runtime
/// client does.
String renderLiteRtLmContent(String template, Object? content) {
  try {
    return Template(template).render({
      'messages': [
        {'role': 'user', 'content': content},
      ],
    });
  } on Exception catch (error) {
    throw LlamaModelException('template failed: $error');
  }
}
