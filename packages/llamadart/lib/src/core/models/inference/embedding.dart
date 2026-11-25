import '../../exceptions.dart';
import '../chat/content_part.dart';

/// A modality accepted by the embedding input contract.
///
/// Later versions may add modalities, such as video. Switches over modalities
/// need a default case for forward compatibility.
enum LlamaEmbeddingModality {
  /// Plain text, without automatic task prefixes.
  text,

  /// Encoded images.
  image,

  /// Encoded audio or PCM samples, as supported by the runtime.
  audio,
}

/// Embedding modalities available on the loaded model and runtime.
///
/// Media support must be positively probed by the backend, including its
/// projector/processors and runtime ABI. Legacy text-only backends report their
/// existing text support; model-specific restrictions can still reject a call.
/// This does not describe generation capabilities or supported media codecs.
final class LlamaEmbeddingCapabilities {
  /// Whether plain text can be embedded.
  final bool text;

  /// Whether images can be embedded, including alongside text.
  final bool image;

  /// Whether audio can be embedded, including alongside text and images.
  final bool audio;

  /// Actionable runtime requirements when image or audio support is unavailable.
  ///
  /// Used only for a rejected media modality; text support is independent.
  /// Must not contain input payloads, file paths, URLs or credentials.
  final String? mediaUnsupportedReason;

  /// Creates a capability report. Unknown capabilities default to unavailable.
  const LlamaEmbeddingCapabilities({
    this.text = false,
    this.image = false,
    this.audio = false,
    this.mediaUnsupportedReason,
  });

  /// Whether [modality] is available.
  bool supports(LlamaEmbeddingModality modality) => switch (modality) {
    LlamaEmbeddingModality.text => text,
    LlamaEmbeddingModality.image => image,
    LlamaEmbeddingModality.audio => audio,
  };
}

/// One embedding request: ordered, interleaved text, image and audio parts.
///
/// Uses the same media sources as chat content. The list is copied; callers
/// must keep media buffers unchanged until the embedding future settles.
/// Embedding PCM input uses mono 16 kHz Float32 samples.
/// Source/codec availability depends on the selected runtime. No chat template,
/// task prefix, truncation or frame extraction is applied.
///
/// Video and chat-only parts throw [LlamaUnsupportedException]: a portable
/// video sampling/timestamp contract has not been defined. An empty list throws
/// [LlamaArgumentException]; a single empty text part retains raw text semantics.
final class LlamaEmbeddingInput {
  /// An unmodifiable snapshot of the ordered content parts.
  final List<LlamaContentPart> parts;

  /// The ordered part kinds, without text, paths, URLs or media buffers.
  final List<LlamaEmbeddingModality> partKinds;

  /// Creates an embedding input from existing public content parts.
  factory LlamaEmbeddingInput(List<LlamaContentPart> parts) {
    if (parts.isEmpty) {
      throw LlamaArgumentException(
        'Embedding input requires at least one part.',
      );
    }
    final kinds = <LlamaEmbeddingModality>[
      for (final part in parts)
        switch (part) {
          LlamaTextContent() => LlamaEmbeddingModality.text,
          LlamaImageContent() => LlamaEmbeddingModality.image,
          LlamaAudioContent() => LlamaEmbeddingModality.audio,
          _ => throw LlamaUnsupportedException(
            'Embedding input supports only text, image and audio; '
            '${part.runtimeType} is unavailable in the embedding input contract.',
          ),
        },
    ];
    return LlamaEmbeddingInput._(
      List<LlamaContentPart>.unmodifiable(parts),
      List<LlamaEmbeddingModality>.unmodifiable(kinds),
    );
  }

  LlamaEmbeddingInput._(this.parts, this.partKinds);
}
