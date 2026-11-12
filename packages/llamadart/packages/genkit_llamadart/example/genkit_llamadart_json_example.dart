import 'dart:convert';
import 'dart:io';

import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:schemantic/schemantic.dart';

import 'support/chat_model.dart';

final SchemanticType<Map<String, dynamic>> _reviewSchema =
    SchemanticType.from<Map<String, dynamic>>(
      jsonSchema: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'summary': <String, Object?>{'type': 'string'},
          'sentiment': <String, Object?>{'type': 'string'},
        },
        'required': <String>['summary', 'sentiment'],
        'additionalProperties': false,
      },
      parse: (json) => (json as Map).cast<String, dynamic>(),
    );

Future<void> main() async {
  final prompt =
      Platform.environment['LLAMADART_PROMPT'] ??
      'Summarize this review as JSON: The battery lasts all day, but the speakers are weak.';
  final prepared = await prepareExampleChat('local-json');
  final ai = prepared.createGenkit();

  try {
    stdout.write('JSON stream: ');
    final stream = ai
        .generateStream<Map<String, dynamic>, LlamaDartGenerationConfig>(
          prompt: prompt,
          outputSchema: _reviewSchema,
          outputFormat: 'json',
          outputConstrained: true,
          config: const LlamaDartGenerationConfig(
            temperature: 0.1,
            maxTokens: 128,
            enableThinking: false,
          ),
        );

    await for (final chunk in stream) {
      if (chunk.text.isNotEmpty) {
        stdout.write(chunk.text);
      }
    }

    stdout.writeln();
    final response = await stream.onResult;

    if (response.finishReason == FinishReason.failed ||
        response.finishReason == FinishReason.aborted) {
      throw response.cause ?? StateError('Generation did not complete.');
    }
    stdout.writeln('Parsed output: ${jsonEncode(response.output)}');
  } finally {
    try {
      await prepared.dispose();
    } finally {
      await ai.shutdown();
    }
  }
}
