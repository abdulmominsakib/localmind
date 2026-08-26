/// Known and recommended Apple MLX model checkpoints.
class AppleMlxModelIds {
  const AppleMlxModelIds._();

  // LLM / Text Generation Models (Hugging Face mlx-community)
  static const String gemma22b = 'mlx-community/gemma-2-2b-it-4bit';
  static const String llama321b = 'mlx-community/Llama-3.2-1B-Instruct-4bit';
  static const String llama323b = 'mlx-community/Llama-3.2-3B-Instruct-4bit';
  static const String smolLm2135m = 'mlx-community/SmolLM2-135M-Instruct';
  static const String qwen2505b = 'mlx-community/Qwen2.5-0.5B-Instruct-4bit';
  static const String qwen2515b = 'mlx-community/Qwen2.5-1.5B-Instruct-4bit';
  static const String qwen253b = 'mlx-community/Qwen2.5-3B-Instruct-4bit';

  // Speech-To-Text (STT) Models
  static const String parakeetTdt06b = 'mlx-community/parakeet-tdt-0.6b-v2';
  static const String whisperTiny = 'mlx-community/whisper-tiny-mlx';
  static const String whisperBase = 'mlx-community/whisper-base-mlx';
  static const String whisperSmall = 'mlx-community/whisper-small-mlx';

  // Text-To-Speech (TTS) Models
  static const String pocketTts = 'mlx-community/pocket-tts';

  // Default PocketTTS voice IDs
  static const List<String> defaultVoices = [
    'alba',
    'marius',
    'javert',
    'jean',
  ];
}

/// Configuration options for MLX speech operations.
class AppleMlxConfig {
  /// Path or Hugging Face repo ID for STT model.
  final String? sttModelId;

  /// Path or Hugging Face repo ID for TTS model.
  final String? ttsModelId;

  /// Default voice ID to use for TTS.
  final String defaultVoice;

  /// Maximum samples allowed in audio buffer for STT.
  final int? maximumInputSamples;

  const AppleMlxConfig({
    this.sttModelId = AppleMlxModelIds.parakeetTdt06b,
    this.ttsModelId = AppleMlxModelIds.pocketTts,
    this.defaultVoice = 'alba',
    this.maximumInputSamples,
  });
}
