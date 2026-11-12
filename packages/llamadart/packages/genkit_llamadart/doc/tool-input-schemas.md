# Tool input schemas

The plugin requires llamadart `^0.19.0`. Genkit continues to own handlers,
interrupts and message history. Tool input and tool-call argument roots must
be JSON objects; scalar and array roots are unsupported.

## Schema support

Existing simple schemas retain the `ToolParam` route: single primitive types,
string enums, nested objects, required fields and typed arrays. This keeps
best-effort tool calling available on the runtimes that supported it before.

Schemas outside that subset use llamadart's owned
`ToolDefinition.fromJsonSchema` API. Constraints remain in the model-facing
schema and the final arguments are validated before publication or handler
execution. Tool schemas are copied; later caller mutations do not change them.

| Schema feature | Support |
| --- | --- |
| Nullable/type alternatives, such as `['string', 'null']` | Supported on the schema route |
| Scalar `enum` and `const` | Supported, including numeric enums |
| `anyOf` | Supported with complete alternatives; constraint siblings are rejected |
| `minLength` / `maxLength`, `minItems` / `maxItems` | Supported within upstream size/repetition limits |
| `additionalProperties: false`, `true`, or a typed schema | Preserved on the schema route; omitted policies default to open |
| Local named `$defs` / `definitions` references | Resolved before either route; must be acyclic and name the exact root block |
| Numeric bounds, patterns, formats, `oneOf`, `allOf`, tuple arrays | Rejected with `INVALID_ARGUMENT` |
| External/scoped references, semantic constraints beside `$ref`, malformed schemas | Rejected before runtime initialization |

Use `additionalProperties: false` explicitly when a tool's argument names are
fixed. The same property policy applies to nested objects. A simple schema
without richer constraints keeps its established `ToolParam` behavior rather
than gaining strict enforcement on a best-effort runtime.

Dialect URI annotations (`$schema`) are omitted during normalization. The
owner's fixed supported keyword subset defines enforcement; no remote
meta-schema fetch is needed for local final-argument validation. A property
named `$schema` is still an ordinary argument property.

Reference copying and expansion are bounded (128 JSON levels and 16,384 visited
values/subschemas per pass). The owner API additionally limits schema depth,
node/alternative counts and grammar size. Excessive schemas fail explicitly.

## Runtime and streaming behavior

Active rich-schema tools require the loaded runtime to report both tool calling
and grammar support. LiteRT-LM rejects them; existing simple LiteRT-LM tools
retain their behavior. A custom runtime must report capabilities and consume
`ToolDefinition.toJsonSchema()`, rather than rebuild inputs from `parameters`,
which is empty for owned schemas.

The core runtime rejects unsupported template/backend combinations. Its rich
JSON-envelope formats are generic, Hermes and Mistral Nemo. GLM-4.5, Laguna
and Hunyuan V3 accept only their narrower fixed-argument subsets; use explicit
closed objects there. Other template families reject owned schemas. Web
requires an active grammar for the chosen tool format and choice; bridges
without lazy grammar support reject combinations that need it. Browser guard
tests do not qualify real Web inference or a Web deployment.

On the schema route, the full response, including reasoning and tool previews,
is buffered until final parsing and argument validation. Invalid, incomplete
or token-limited calls publish no partial response and execute no handler.
Cancellation discards that buffered result. Simple tool streaming is unchanged.
`toolChoice.none` keeps tools inactive and does not require schema grammar.
`required` persists across Genkit turns: explicitly switch to `none` or `auto`
when your application permits a final answer.

Constrained JSON output with tools retains its native llama.cpp, single-call,
nonthinking restrictions. Tool input schemas and final response schemas remain
separate contracts.

## Example and qualification

Run the [rich tool example](../example/genkit_llamadart_tool_schema_example.dart)
with a local Qwen3-1.7B-Q4_K_M GGUF:

```bash
dart run example/genkit_llamadart_tool_schema_example.dart
```

The example uses nullable input, a numeric enum and a closed object. It runs
one Genkit handler, then permits a final answer containing its demo code.

The opt-in proof uses checksum-pinned Qwen3-1.7B on native llama.cpp CPU. It
checks real `auto`/`required` tool loops, schema-directed argument reconstruction,
and compiled schema/template grammar acceptance and rejection for nullable
values, enums, constants, composition, bounds and object policies. Deterministic
adapter tests cover interruption/resume, invalid final arguments, cancellation
and unsupported capabilities. See [qualification commands](../CONTRIBUTING.md#rich-tool-schema-qualification).

Model qualification covers Qwen3/Hermes on macOS arm64. Mistral Nemo,
GLM-4.5, Laguna and Hunyuan V3 weights were not qualified by this adapter change;
the core's guarded format contract is not evidence of model quality. Real Web,
mobile and LiteRT-LM rich-schema inference are not qualified.
