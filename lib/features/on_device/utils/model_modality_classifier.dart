/// Modality classification for an on-device model.
enum ModelModality { text, vision, audio, embedding, omni, unknown }

/// Classifies a modality from a pipeline tag, tags, and (optionally) the
/// repo/model name. Returns [ModelModality.unknown] when no signal is found.
ModelModality classifyModality({
  String? pipelineTag,
  List<String> tags = const <String>[],
  String? name,
}) {
  final pipeline = (pipelineTag ?? '').toLowerCase().trim();
  final tagSet = tags.map((t) => t.toLowerCase().trim()).toSet();
  final haystack = '$pipeline ${tags.join(' ')} ${name ?? ''}'.toLowerCase();

  // Omni-modal (any-to-any): handles text + image + audio + video.
  // Restricted to pipeline_tag/tags (not name) to avoid false positives.
  if (pipeline.contains('any-to-any') ||
      tagSet.contains('any-to-any') ||
      pipeline.contains('omni') ||
      tagSet.contains('omni')) {
    return ModelModality.omni;
  }

  // Embedding / feature extraction.
  if (pipeline.contains('feature-extraction') ||
      pipeline.contains('sentence-similarity') ||
      pipeline.contains('embedding') ||
      tagSet.contains('embedding') ||
      tagSet.contains('sentence-transformers') ||
      haystack.contains('embedding')) {
    return ModelModality.embedding;
  }

  // Audio / speech.
  if (pipeline.contains('audio') ||
      pipeline.contains('speech') ||
      pipeline.contains('text-to-speech') ||
      pipeline.contains('automatic-speech') ||
      tagSet.contains('audio') ||
      tagSet.contains('speech') ||
      haystack.contains('audio') ||
      haystack.contains('whisper') ||
      haystack.contains('tts')) {
    return ModelModality.audio;
  }

  // Vision / image.
  if (pipeline.contains('image') ||
      pipeline.contains('visual') ||
      pipeline.contains('vision') ||
      pipeline.contains('image-to-text') ||
      pipeline.contains('image-text-to-text') ||
      pipeline.contains('visual-question-answering') ||
      tagSet.contains('vision') ||
      tagSet.contains('image') ||
      tagSet.contains('multimodal') ||
      haystack.contains('vision') ||
      haystack.contains('vlm') ||
      haystack.contains('llava') ||
      haystack.contains('fastvlm')) {
    return ModelModality.vision;
  }

  // Text generation.
  if (pipeline.contains('text-generation') ||
      pipeline.contains('text2text-generation') ||
      pipeline.contains('conversational') ||
      tagSet.contains('text-generation') ||
      tagSet.contains('conversational')) {
    return ModelModality.text;
  }

  return ModelModality.unknown;
}
