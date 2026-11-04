/// Supported chat template formats.
enum LlamaChatFormat {
  /// Raw content only.
  contentOnly(0),

  /// Llama 2 format.
  llama2(1),

  /// Llama 3 format.
  llama3(2),

  /// ChatML format.
  chatml(3),

  /// Gemma format.
  gemma(4),

  /// DeepSeek format.
  deepseek(5),

  /// Phi format.
  phi(6),

  /// LFM format.
  lfm(7),

  /// FunctionGemma format.
  functionGemma(8);

  /// The integer value associated with the format.
  final int value;
  const LlamaChatFormat(this.value);
}
