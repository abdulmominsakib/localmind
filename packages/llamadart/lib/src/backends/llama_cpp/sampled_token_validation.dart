/// Validate only sampled vocabulary IDs. Multimodal embedding markers are not
/// token IDs and must never be routed through this guard.
void validateSampledToken(int token, int vocabularySize) {
  if (token < 0 || token >= vocabularySize) {
    throw StateError(
      'Sampler returned token $token outside vocabulary $vocabularySize',
    );
  }
}
