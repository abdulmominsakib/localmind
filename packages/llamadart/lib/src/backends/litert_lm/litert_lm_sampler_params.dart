/// Returns the top-k handed to a LiteRT-LM sampler for [temperature].
///
/// Zero temperature returns `1`; any other temperature returns [topK]
/// unchanged. Shared by the native and Web LiteRT-LM paths.
int liteRtLmEffectiveTopK({required double temperature, required int topK}) {
  return temperature == 0 ? 1 : topK;
}
