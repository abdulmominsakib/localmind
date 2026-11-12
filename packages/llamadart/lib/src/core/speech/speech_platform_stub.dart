/// Whether this platform requires a backend runtime opt-in for prompt ASR.
bool get speechToTextRequiresBackendCapability => false;

/// Whether prompt-adapted audio is rendered through the model chat template.
///
/// Native Qwen3-ASR only emits a transcript when the audio turn is wrapped by
/// the model's own chat template, so raw prompt generation returns nothing.
bool get speechToTextUsesChatTemplate => true;

/// Whether local filesystem speech input is available on this platform.
bool get speechToTextSupportsFileInput => true;

/// Whether byte inputs require explicit encoding metadata on this platform.
bool get speechToTextRequiresEncodedAudioFormat => false;

/// Encoded formats accepted for prompt-adapted speech input.
Set<String> get speechToTextEncodedAudioFormats => const <String>{
  'wav',
  'mp3',
  'flac',
};
