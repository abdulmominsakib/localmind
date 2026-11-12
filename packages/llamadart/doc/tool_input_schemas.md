# Canonical tool input schemas

## Import a JSON Schema

Use `ToolDefinition.fromJsonSchema` when another library already provides the
input schema. The factory owns a deep copy; `toJsonSchema()` returns a fresh
copy. Its `parameters` list is empty, so integrations must read `toJsonSchema()`.

```dart
final ToolDefinition searchTool = ToolDefinition.fromJsonSchema(
  name: 'search',
  description: 'Search selected collections',
  schema: {
    'type': 'object',
    'properties': {
      'query': {'type': 'string', 'minLength': 1, 'maxLength': 2000},
      'collections': {
        'type': 'array',
        'items': {'type': 'string'},
        'minItems': 1,
      },
    },
    'required': ['query', 'collections'],
    'additionalProperties': false,
  },
  handler: (params) async => {
    'query': params.getRequiredString('query'),
    'collections': params.getList('collections'),
  },
);
```

The initial subset supports scalar types, nested objects and arrays, scalar
`enum`/`const`, nullable type lists, `anyOf`, string length and array item
bounds, and boolean or schema-valued `additionalProperties`. The root must be
an object. Missing `additionalProperties` means `true`; the existing
`ToolParam` constructor keeps its closed-property behavior.

References (local and remote), patterns, numeric bounds, `oneOf`/`allOf`, tuple
arrays, container literals and unsupported constraint combinations throw
`LlamaUnsupportedException`. Malformed schemas throw `LlamaArgumentException`.
This API supports a bounded subset of JSON Schema.
Nonempty annotation-only untyped property schemas accept any JSON value;
annotations and unknown `x-*` metadata are preserved. For empty tool-property schemas, use an explicit `type`; response schemas
keep their existing `{}` object grammar. Response schemas share the rejection of unsupported constraints
and bounds above 2000, but support a wider subset (for example local references
and compiled patterns). Decoded model tool arguments are limited to 128 container
levels in final and partial parsing; deeper values throw `LlamaInferenceException`.

`toJsonSchema()` and `toJson()` return the validated schema with object
defaults made explicit: every object schema includes `properties` (empty when
absent) and `additionalProperties` (`true` when absent).

### Limits

Imported schemas may come from untrusted sources, so the factory bounds them
and throws `LlamaUnsupportedException`, naming the keyword or path and the
limit, when a schema exceeds one:

| Limit | Value |
| --- | --- |
| JSON nesting of the schema document, including `default`/`examples` values | 128 levels |
| Subschema nesting | 32 levels |
| Subschemas plus undeclared `required` names per tool | 1024 |
| `anyOf` alternatives | 64 |
| `enum` values | 1024 |
| Property name length | 128 characters |
| `minLength`, `maxLength`, `minItems`, `maxItems` | 2000 (inclusive) |
| Generated grammar per tool | 262,144 characters |

The bound limit is llama.cpp's grammar repetition limit
(`MAX_REPETITION_THRESHOLD`, 2000): the grammar parser of the llama.cpp release
the native runtime ships (upstream `v0.9.0`) rejects a repetition count above
2000 and silently drops a larger upper bound. The schema factory rejects bounds
above 2000 so those constraints cannot be lost.

The grammar for all tools in a request is checked again before generation on
grammar-capable backends. It throws `LlamaUnsupportedException` when llama.cpp
would refuse to load it: a repeated group whose symbols times its repetition
count exceed 2000. Hermes, for example, puts every schema tool inside one
repeated group, so about 2000 schema tools exceed it.

| Selected tool format | Canonical schema support |
| --- | --- |
| Generic JSON fallback, Hermes, Mistral Nemo JSON | The subset above |
| GLM-4.5, Laguna, Hunyuan V3 | Closed root objects with scalar properties; GLM/Laguna also support string enums |
| Other formats | Rejected before generation |

Active schema tools require grammar-constrained decoding. Native llama.cpp
supports it; WebGPU works only when the selected grammar starts at the first
token (usually `ToolChoice.required`). Lazy auto grammars and LiteRT-LM are
rejected. `ToolChoice.none` can retain declarations for replay without enabling
calls. Final parsed calls and direct `invoke` arguments are validated before
handlers run. A schema constrains the input shape; the app still controls
tool permissions and side effects.

Active schema tools cannot be combined with `responseFormat`, which would
replace the tool grammar. Use separate requests. Undeclared calls and malformed
tool envelopes fail the turn before handlers run. In an open object, an extra
property cannot reuse a declared or required property name, so those
properties keep their own schema. Escaped spellings of a declared name (such as `\u0063ity`)
are rejected too: where a declared name continues with a character, an extra
name cannot spell that character as a `\u` escape. Where a declared name needs
a JSON escape (such as `a"b`), the grammar also rejects extra names with a
different escape at that position (such as `a\nb`). Open objects whose
declared names would add more than 65,536 characters of exclusion rules to one
grammar accept any extra name instead; for tools, final validation still checks
declared properties.

In Hermes `auto` mode, a JSON object with a `name` key outside a
`<tool_call>`, `<tool>` or `<function…>` envelope stays answer text unless it
is a complete call to a declared tool, which is then validated like any other
call. A reply cut off by `maxTokens` or the context size finishes with
`length` (tool loops stop with `truncated`) rather than failing as a malformed
call.

When a Hermes template forces reasoning open (such as QwQ), the
`ToolChoice.required` grammar accepts reasoning closed by `</think>` before the
calls, for schema and `ToolParam` tools.

`required` may name a property that `properties` does not declare: the
grammar requires that key, with a value matching `additionalProperties` (any
JSON value when it is `true`). In a closed object (`additionalProperties:
false`) such a name throws `LlamaArgumentException`, because no object can
satisfy it. Response schemas still require `required` to name declared
properties.

On WebGPU, Hermes and Mistral schema-backed automatic tool loops cannot finish:
follow-up rounds use `auto`, which needs a lazy grammar. Use the generic
non-lazy JSON format there, or manage the required-tool request and follow-up
explicitly.

## Qualification

Tests cover schema ownership, typed argument reconstruction, raw and legacy
object defaults, tool choices, thinking prefixes, backend capability rejection,
final parsing and compiled llama.cpp grammar acceptance/rejection. Specialized
family weights are not available for Hermes, Mistral Nemo, GLM-4.5, Laguna or Hunyuan V3; fixtures and
compiled grammars establish protocol behavior, not real-model tool quality.

This SDK work is separate from Flutter Edge AI #628. That connector consumes
published 0.12.2; adopting this factory requires a later SDK release and connector
update. No runtime pin or release change is included here.
