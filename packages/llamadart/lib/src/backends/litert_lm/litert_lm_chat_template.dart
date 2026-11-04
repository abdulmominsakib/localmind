/// A built-in chat template for a LiteRT-LM model family.
///
/// LiteRT-LM `.litertlm` bundles do not expose their chat template through the
/// native FFI, so the backend must supply `tokenizer.chat_template` itself,
/// keyed by detecting the model family from the bundle filename. See
/// `doc/litert_lm_templates.md` for the full rationale and the recipe for
/// adding a new family.
class LiteRtLmChatTemplate {
  /// Creates a built-in chat template descriptor.
  const LiteRtLmChatTemplate({
    required this.id,
    required this.template,
    required this.familyMatches,
    this.bosToken = '<bos>',
    this.eosToken = '<turn|>',
    this.thinkingStartTag = '<|channel>thought\n',
    this.thinkingEndTag = '<channel|>',
  });

  /// Stable identifier for diagnostics (e.g. `gemma4`).
  final String id;

  /// The jinja chat template, rendered by the matching format handler.
  ///
  /// Copied verbatim from the canonical jinja that llama.cpp ships, minus any
  /// leading `bos_token` emission: the native LiteRT-LM runtime adds the start
  /// token itself, so emitting one here would double it.
  final String template;

  /// Filename substrings that identify this family.
  ///
  /// Matched against the lower-cased bundle filename with `_` normalized to
  /// `-`. Order matters in the registry: the first matching entry wins, so
  /// more specific families must be registered before broader ones.
  final List<String> familyMatches;

  /// The BOS token exposed via `tokenizer.ggml.bos_token` metadata.
  final String bosToken;

  /// The EOS token exposed via `tokenizer.ggml.eos_token` metadata.
  final String eosToken;

  /// The marker used to expose LiteRT-LM thought-channel chunks as reasoning.
  final String thinkingStartTag;

  /// The marker used to close LiteRT-LM thought-channel chunks.
  final String thinkingEndTag;

  /// Whether [normalizedName] (lower-cased, `_`→`-`) belongs to this family.
  bool matches(String normalizedName) =>
      familyMatches.any(normalizedName.contains);
}
