import 'dart:io';

import 'package:genkit/genkit.dart';

import 'support/chat_model.dart';

Future<void> main() async {
  final prepared = await prepareExampleChat('streaming');
  final ai = prepared.createGenkit();
  try {
    final stream = ai.generateStream(
      prompt: 'List three uses for offline AI, one short phrase per line.',
      config: exampleChatConfig,
    );
    await for (final chunk in stream) {
      stdout.write(chunk.text);
    }
    final response = await stream.onResult;
    if (response.finishReason == FinishReason.failed ||
        response.finishReason == FinishReason.aborted) {
      throw response.cause ?? StateError('Generation did not complete.');
    }
    stdout.writeln();
  } finally {
    try {
      await prepared.dispose();
    } finally {
      await ai.shutdown();
    }
  }
}
