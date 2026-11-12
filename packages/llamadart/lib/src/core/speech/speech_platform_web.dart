/// Web requires an explicitly validated bridge runtime.
bool get speechToTextRequiresBackendCapability => true;

/// The validated Web bridge contract takes the raw prompt plus audio bytes.
bool get speechToTextUsesChatTemplate => false;

/// Browsers do not expose local filesystem paths to the runtime.
bool get speechToTextSupportsFileInput => false;

/// Browser byte inputs must declare their encoded container.
bool get speechToTextRequiresEncodedAudioFormat => true;

/// Encoded formats the WebGPU bridge decodes, matching native.
Set<String> get speechToTextEncodedAudioFormats => const <String>{
  'wav',
  'mp3',
  'flac',
};
