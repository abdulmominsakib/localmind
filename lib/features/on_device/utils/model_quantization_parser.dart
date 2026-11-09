/// Extracts a quantization label (e.g. "Q4_K_M", "Q8_0", "IQ2", "FP16")
/// from a model name, repo id, or filename. Returns `null` when none found.
String? parseQuantization(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  // IQ variants first (more specific).
  final iq = RegExp(r'IQ[1-4](?:_[A-Z]+)?', caseSensitive: false)
      .firstMatch(text);
  if (iq != null) {
    return iq.group(0)!.toUpperCase();
  }

  // Q variants: Q2_K, Q3_K_S/M/L, Q4_0, Q4_K_M, Q5_K_S, Q6_K, Q8_0, etc.
  final q = RegExp(
    r'Q[2-8](?:_[01K](?:_[A-Z]+)?)?',
    caseSensitive: false,
  ).firstMatch(text);
  if (q != null) {
    return q.group(0)!.toUpperCase();
  }

  // Floating point / integer quantization keywords.
  final kw = RegExp(
    r'\b(FP16|BF16|FP32|INT4|INT8|F16|F32)\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (kw != null) {
    return kw.group(0)!.toUpperCase();
  }

  return null;
}
