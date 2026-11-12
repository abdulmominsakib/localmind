---
name: genkit-llamadart-structured-output
description: >-
  Use when getting JSON or typed output from a local model in a genkit_llamadart
  app: Genkit outputSchema with a Schemantic type, outputFormat 'json',
  outputConstrained grammar enforcement, streaming JSON, reading
  response.output, or choosing supportsConstrainedOutput for GGUF versus
  LiteRT-LM models.
---

# Structured JSON output with genkit_llamadart

## Guidelines

- Add `schemantic` (`dart pub add schemantic`) and describe the output as a
  `SchemanticType`: a generated `@Schema()` type, or
  `SchemanticType.from<T>(jsonSchema: ..., parse: ...)` for a hand-written
  JSON Schema.
- Request JSON with `outputSchema: schema`, `outputFormat: 'json'` and
  `outputConstrained: true`. Pass the output type as the first type argument
  (`ai.generate<T, LlamaDartGenerationConfig>(...)`) so `response.output` is
  typed.
- Constrained output compiles the schema into a llama.cpp grammar, so the
  tokens must match the schema. It needs a grammar-capable backend: GGUF
  models on llama.cpp. LiteRT-LM `.litertlm` bundles do not enforce grammars;
  register them with `supportsConstrainedOutput: false` and do not request
  constrained output from them.
- A request with `outputConstrained: true` on a model registered with
  `supportsConstrainedOutput: false` fails with `FAILED_PRECONDITION`.
  An enabled definition still needs verified structured-output and grammar
  capabilities; an unsupported runtime fails before decoding with `UNIMPLEMENTED`.
- Constrained output with tools requires native llama.cpp, one call per turn
  and `enableThinking: false`. WebGPU and LiteRT-LM reject it. For unsupported
  backends, run the tool turn first and ask for JSON separately on a
  grammar-capable model without active tools.
- Keep schemas simple: objects with typed properties, `required` and
  `additionalProperties: false`. Put field meanings in the prompt or in
  `description`s.
- Set `maxTokens` high enough for the full object. A token-limit stop truncates
  the JSON; check `finishReason` (`FinishReason.length`, `failed` or `aborted`)
  before reading `response.output`.
- Use a low temperature and `enableThinking: false` so reasoning text does not
  compete with the JSON.
- When streaming, `chunk.text` is partial JSON; parse only the final
  `response.output` from `await stream.onResult`.

## Examples

Generate a typed JSON object with a constrained grammar:

```dart
import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:schemantic/schemantic.dart';

final SchemanticType<Map<String, dynamic>> reviewSchema =
    SchemanticType.from<Map<String, dynamic>>(
      jsonSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'summary': <String, Object?>{'type': 'string'},
          'sentiment': <String, Object?>{
            'type': 'string',
            'enum': <String>['positive', 'neutral', 'negative'],
          },
          'score': <String, Object?>{'type': 'integer'},
        },
        'required': <String>['summary', 'sentiment', 'score'],
        'additionalProperties': false,
      },
      parse: (json) => (json as Map).cast<String, dynamic>(),
    );

Future<void> main() async {
  final plugin = llamaDart(
    models: const <LlamaModelDefinition>[
      LlamaModelDefinition(
        name: 'local-json',
        modelPath: '/models/chat.gguf',
        supportsEmbeddings: false,
        supportsTools: false,
      ),
    ],
  );
  final ai = Genkit(plugins: <LlamaDartPlugin>[plugin]);

  try {
    final response = await ai
        .generate<Map<String, dynamic>, LlamaDartGenerationConfig>(
          model: llamaDart.model('local-json'),
          prompt:
              'Review: "The battery lasts all day, but the speakers are weak." '
              'Summarize it, classify the sentiment, and score it from 1 to 5.',
          outputSchema: reviewSchema,
          outputFormat: 'json',
          outputConstrained: true,
          config: const LlamaDartGenerationConfig(
            temperature: 0.1,
            maxTokens: 256,
            enableThinking: false,
          ),
        );

    if (response.finishReason != FinishReason.stop) {
      print(
        'No complete JSON: ${response.finishReason} '
        '${response.error?.message ?? ''}',
      );
      return;
    }
    final review = response.output!;
    print('${review['sentiment']} (${review['score']}): ${review['summary']}');
  } finally {
    await plugin.dispose();
    await ai.shutdown();
  }
}
```

Stream the JSON as it is generated and parse the final result:

```dart
import 'dart:io';

import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:schemantic/schemantic.dart';

Future<Map<String, dynamic>?> streamJson(
  Genkit ai,
  SchemanticType<Map<String, dynamic>> schema,
  String prompt,
) async {
  final stream = ai
      .generateStream<Map<String, dynamic>, LlamaDartGenerationConfig>(
        model: llamaDart.model('local-json'),
        prompt: prompt,
        outputSchema: schema,
        outputFormat: 'json',
        outputConstrained: true,
        config: const LlamaDartGenerationConfig(
          temperature: 0.1,
          maxTokens: 256,
          enableThinking: false,
        ),
      );

  await for (final chunk in stream) {
    stdout.write(chunk.text);
  }
  stdout.writeln();

  final response = await stream.onResult;
  return response.finishReason == FinishReason.stop ? response.output : null;
}
```

## More

- Runnable JSON example:
  https://github.com/leehack/llamadart/blob/main/packages/genkit_llamadart/example/genkit_llamadart_json_example.dart
- Schemantic: https://pub.dev/packages/schemantic

Thinking budgets are supported when the runtime reports them; omitted tags are
resolved from the structured request's template. Speculative decoding is rejected
with constrained JSON because core grammar sampling does not support it.

Native combined tool requests use generic JSON envelopes internally. The adapter
returns the schema-directed final JSON and Genkit tool requests. Content is
buffered until complete validation; partial or malformed output is never emitted.
See `doc/usage.md` for the local-pointer reference subset and required-tool final-turn policy.
