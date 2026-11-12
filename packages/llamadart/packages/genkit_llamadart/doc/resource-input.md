# Resource and data input

Resolve application resources before local generation. Genkit's resource
registration and generic part types do not automatically dereference URIs for
this adapter. Direct `ResourcePart`, `DataPart` and `CustomPart` input remains
unsupported.

Run the [resource example](../example/genkit_llamadart_resources_example.dart)
from the repository root:

```bash
dart run example/genkit_llamadart_resources_example.dart
```

It uses the shared pinned Qwen3.5 CPU setup, downloading about 533 MB on its
first run. Set `LLAMADART_MODEL_PATH` to a compatible local chat GGUF to reuse
your own model. It resolves the explicitly registered `app://faq/returns`
resource, renders its JSON data as text, and asks about the return window.

Copy [the normalization recipe](../example/resources/normalize_messages.dart)
into your app when you need this policy. The application supplies an exact
URI-to-resource-action allowlist; the recipe calls those actions and checks
their URI matcher. It never fetches arbitrary URIs. Returned JSON data uses
compact `jsonEncode` output in the source's key order. Only JSON values are
accepted; arbitrary objects and custom parts are rejected.

Resource action names are bounded source IDs. Expanded content is bracketed
with `[Source: id]` and `[/Source]`, preserving input message roles and order.
Resource/data expansion is allowed only in user messages so retrieved content
is not promoted into a system instruction. The example also explicitly tells
the model to treat sources as untrusted data. Citations are model output; this
recipe does not validate their accuracy.

The copied policy allows at most 16 messages, 32 visited parts, four resource
or JSON nesting levels, 64 JSON nodes per data part, and 16 KiB of expanded text
plus media URLs. Recursive resources, unsupported parts, oversized input and
resolution failures produce bounded diagnostics without raw transport errors.
These limits do not include the chat template and are not a token budget.
The nesting limit is checked before calling a resource action beyond it.

Image/audio media stays typed. Media transport, payload limits and decoding
remain governed by the compatible model and your application-owned
[remote-media resolver](usage.md#resolving-remote-input-on-native-platforms).
The recipe does not fetch media, extract PDFs or ingest video frames. Send
normalized text/image/audio documents to a compatible
[multimodal embedder](usage.md#multimodal-embeddings) explicitly. Native video support is
tracked in [llamadart #320](https://github.com/leehack/llamadart/issues/320).

Pass a Genkit cancellation token to normalization and subsequent generation.
Resource actions must also cooperate with that token for cancellable external
I/O; an action which ignores it must finish before normalization can settle.
The caller owns resource transports, Genkit and model disposal. Keep resource
URIs free of credentials and configure telemetry content capture explicitly.

Standard `ModelRequest.docs` integration remains blocked by Genkit's public
API/forwarding under [#27](https://github.com/leehack/genkit-llamadart/issues/27).
This recipe normalizes input explicitly and does not add a `docs` parameter.
