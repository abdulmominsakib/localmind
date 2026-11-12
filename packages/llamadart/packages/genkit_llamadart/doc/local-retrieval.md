# Answer questions from local text

The [runnable retrieval example](../example/genkit_llamadart_retrieval_example.dart)
searches three small local documents and asks Qwen3.5 to answer using the selected
passages. It uses existing Genkit flows and messages, with native constrained
JSON for the answer and source IDs. It needs no vector database or second model.

```bash
dart run example/genkit_llamadart_retrieval_example.dart 'What is the return window?'
```

This downloads the same pinned 533 MB chat model as the quickstart. Set
`LLAMADART_MODEL_PATH` to use a local compatible chat/grammar GGUF. The bundled
shop documents are demo fixtures; edit them to try your own facts. Run from the
repository root so the example can find its files.

## How the recipe works

The [flow helper](../example/retrieval/local_retrieval.dart) ranks documents by
ASCII English-word overlap with the question, with a basic trailing-`s` normalization and
input order preserved for ties. It selects up
to three whole passages within 3,000 JSON-encoded characters. Oversized passages
are skipped, not cut mid-sentence. It supports questions up to 512 characters.
No matching passage returns “I don't know from these documents.” without model
inference. This simple search does not understand synonyms or replace semantic
retrieval; an application can use [embeddings](usage.md#embeddings) for that.

Each `DocumentData` has text parts and a unique `metadata['id']` of 1–64 letters,
digits, underscores or hyphens. Only that ID and the text go into the prompt;
other metadata, including paths or URLs, is excluded. Duplicate/unsafe IDs and
nontext parts fail explicitly. The result contains `answer` and `sources`.
The constrained schema permits only selected IDs, and the flow rejects unknown
citations before returning. An empty source list represents an abstention.

The system message tells the model to treat passages as untrusted data and
ignore instructions inside them. JSON encoding preserves boundaries and escapes
embedded control characters. These measures do not guarantee resistance to
prompt injection or factual accuracy. Treat externally supplied documents as
untrusted, review generated answers, and do not grant this flow tools that can
perform privileged actions.

## Context and support limits

The example uses a 4,096-token native CPU model context and at most 256 output
tokens. The passage character limit reduces input size; it is **not** an exact
token budget. Tokenization varies by language and content, and chat templates,
format instructions and the question also consume context. The runtime's limits
still apply. A larger corpus needs proper chunking, retrieval and application
budgeting. Source IDs prove which passages were selected, not that an answer is
correctly grounded in every cited passage.

Genkit Dart 1.0 does not expose `docs:` on `generate`/`generateStream`, and its
internal generation flow drops `ModelRequest.docs`. This recipe explicitly
places text in ordinary messages. It does not implement Genkit's standard
retriever/document augmentation contract; nonempty `ModelRequest.docs` remains
unsupported by this plugin until [upstream forwarding](https://github.com/genkit-ai/genkit-dart/issues/243)
is available. See [adapter issue #27](https://github.com/leehack/genkit-llamadart/issues/27).

This runnable recipe requires native grammar-constrained JSON. It does not claim
LiteRT-LM grammar support or qualify Web execution. Other examples and their
requirements are listed in the [example index](../example/README.md).
