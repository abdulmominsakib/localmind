import 'package:genkit/plugin.dart' as genkit;
import 'package:llamadart/llamadart.dart' as llama;

import 'genkit_to_llama.dart';

// Genkit values expose mutable JSON maps. Copy the consumed fields before an
// operation waits in the queue; large media strings remain shared and immutable.
List<genkit.DocumentData> snapshotEmbeddingDocuments(
  List<genkit.DocumentData> documents,
) => [
  for (final document in documents)
    genkit.DocumentData(
      content: [
        for (final part in document.content)
          if (part.isText)
            genkit.TextPart(text: part.text!)
          else if (part.isMedia)
            genkit.MediaPart(
              media: genkit.Media(
                url: part.media!.url,
                contentType: part.media!.contentType,
              ),
            ),
      ],
      metadata: document.metadata == null ? null : Map.of(document.metadata!),
    ),
];

// Validate the entire batch before model loading or remote media resolution.
Set<llama.LlamaEmbeddingModality> embeddingModalities(
  List<genkit.DocumentData> documents,
) {
  final modalities = <llama.LlamaEmbeddingModality>{};
  for (final document in documents) {
    var hasContent = false;
    for (final part in document.content) {
      if (part.isReasoning) continue;
      hasContent = true;
      if (part.isText) {
        modalities.add(llama.LlamaEmbeddingModality.text);
        continue;
      }
      if (part.isMedia) {
        final String? type;
        try {
          type =
              part.media!.contentType ?? inferMediaContentType(part.media!.url);
        } on FormatException {
          throw _invalid('Invalid embedding media data URL.');
        }
        if (type?.startsWith('image/') == true) {
          modalities.add(llama.LlamaEmbeddingModality.image);
          continue;
        }
        if (type?.startsWith('audio/') == true) {
          modalities.add(llama.LlamaEmbeddingModality.audio);
          continue;
        }
      }
      throw _invalid('Embeddings accept only text, image and audio parts.');
    }
    // Retain the existing empty-document text semantics, including reasoning-only.
    if (!hasContent) modalities.add(llama.LlamaEmbeddingModality.text);
  }
  return modalities;
}

List<genkit.Message> embeddingMessages(List<genkit.DocumentData> documents) => [
  for (final document in documents)
    genkit.Message(role: genkit.Role.user, content: document.content),
];

genkit.GenkitException _invalid(String message) =>
    genkit.GenkitException(message, status: genkit.StatusCode.invalidArgument);
