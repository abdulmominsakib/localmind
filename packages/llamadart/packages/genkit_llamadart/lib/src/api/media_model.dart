import 'package:llamadart/llamadart.dart' as llama;

/// A dedicated batch speech or image model registered by `LlamaDartMediaPlugin`.
///
/// Load a typed llamadart engine first, using its model sources, parameters,
/// download progress and cancellation options. Registration performs no loading
/// or capability probes. These preview integrations currently require native
/// runtimes; browser requests fail explicitly.
sealed class LlamaDartMediaModel {
  /// Creates a named model with explicit engine ownership and transfer limits.
  ///
  /// Limits must be positive. Engines are borrowed unless [ownsEngine] is true.
  LlamaDartMediaModel({
    required this.name,
    this.ownsEngine = false,
    this.maxInputBytes = 20 * 1024 * 1024,
    this.maxOutputBytes = 20 * 1024 * 1024,
  }) {
    if (name.trim().isEmpty || maxInputBytes <= 0 || maxOutputBytes <= 0) {
      throw ArgumentError(
        'A media model needs a name and positive byte limits.',
      );
    }
  }

  /// Unique name within the media plugin, referenced as `llamadart-media/<name>`.
  final String name;

  /// Whether plugin disposal also disposes the typed engine.
  ///
  /// Borrowed engines remain caller-owned. Avoid direct engine operations while
  /// plugin requests are queued or running; they share the same runtime state.
  final bool ownsEngine;

  /// Maximum encoded audio input bytes, checked before starting inference.
  ///
  /// This does not bound decoded duration or runtime memory. Use short, trusted
  /// clips and the runtime's own model/context limits.
  final int maxInputBytes;

  /// Maximum encoded WAV or PNG output bytes returned to Genkit.
  final int maxOutputBytes;
}

/// Whole-file transcription: one audio part in, one final text part out.
///
/// Uses the engine's adapter and live input/cancellation capabilities. This is
/// batch transcription, without microphone streaming, timestamps or diarization.
final class LlamaDartSpeechToTextModel extends LlamaDartMediaModel {
  /// Registers a loaded recognizer with borrowed ownership by default.
  LlamaDartSpeechToTextModel({
    required super.name,
    required this.engine,
    super.ownsEngine,
    super.maxInputBytes,
    super.maxOutputBytes,
  });

  /// Loaded typed recognizer; model loading remains separate from Genkit calls.
  final llama.SpeechToTextEngine engine;
}

/// Batch synthesis: text plus optional reference audio in, a complete WAV out.
///
/// Language and speaker references require the loaded engine's capabilities.
/// Responses contain complete audio, never incrementally playable fragments.
final class LlamaDartTextToSpeechModel extends LlamaDartMediaModel {
  /// Registers a loaded synthesizer with borrowed ownership by default.
  LlamaDartTextToSpeechModel({
    required super.name,
    required this.engine,
    super.ownsEngine,
    super.maxInputBytes,
    super.maxOutputBytes,
  });

  /// Loaded typed synthesizer, configured through llamadart's typed loading API.
  final llama.TextToSpeechEngine engine;
}

/// Native image generation: a text prompt in, complete PNG media parts out.
///
/// Load `ImageGenerationEngine` with the optional `stable_diffusion` runtime
/// enabled in the app's hooks. Model/component resolution stays in llamadart.
final class LlamaDartImageModel extends LlamaDartMediaModel {
  /// Registers a loaded image engine with borrowed ownership by default.
  LlamaDartImageModel({
    required super.name,
    required this.engine,
    super.ownsEngine,
    super.maxOutputBytes,
  });

  /// Loaded native image engine; separate from chat and speech runtimes.
  final llama.ImageGenerationEngine engine;
}
