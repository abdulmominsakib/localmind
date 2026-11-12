import 'dart:convert';

import 'package:genkit/plugin.dart' as genkit;

/// Adds delivered-content counts without replacing backend token measurements.
void recordContentUsage(
  genkit.ModelResponse response, {
  required int inputCharacters,
  int inputImages = 0,
  int inputAudioFiles = 0,
}) {
  if (response.finishReason == genkit.FinishReason.failed ||
      response.finishReason == genkit.FinishReason.aborted) {
    return;
  }

  final usage = response.usage ??= genkit.GenerationUsage();
  usage.inputCharacters = inputCharacters;
  usage.inputImages = inputImages;
  usage.inputAudioFiles = inputAudioFiles;

  final parts = response.message?.content;
  if (parts == null) return;
  var characters = 0;
  var charactersKnown = true;
  var images = 0;
  var audioFiles = 0;
  for (final part in parts) {
    if (part.isText) {
      characters += part.text!.length;
    } else if (part.isReasoning) {
      characters += part.reasoning!.length;
    } else if (part.isToolRequest) {
      try {
        characters += jsonEncode(part.toolRequest!.input).length;
      } on JsonUnsupportedObjectError {
        charactersKnown = false;
      }
    } else if (part.isMedia) {
      final type = part.media!.contentType ?? '';
      if (type.startsWith('image/')) images++;
      if (type.startsWith('audio/')) audioFiles++;
    }
  }
  usage.outputCharacters = charactersKnown ? characters : null;
  usage.outputImages = images;
  usage.outputAudioFiles = audioFiles;
}
