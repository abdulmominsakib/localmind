import '../../backends/backend.dart';
import '../exceptions.dart';
import '../models/model_source.dart';

/// A text-to-speech model: its files and the adapter that drives it.
///
/// Each file is a `ModelSource` (local path, HTTP(S) URL or Hugging Face
/// file) that `TextToSpeechEngine.load` downloads if needed. llama.cpp needs
/// the model's audio-generation [projector].
///
/// ```dart
/// final model = TextToSpeechModel(
///   ModelSource.parse('hf://owner/repo/tts-model.gguf'),
///   projector: ModelSource.parse('hf://owner/repo/mmproj-tts-model.gguf'),
///   adapter: const Qwen3TtsAdapter(),
/// );
/// ```
///
/// Building a model does no network or file access.
class TextToSpeechModel {
  /// The main model file.
  final ModelSource source;

  /// The audio-generation multimodal projector, or null.
  final ModelSource? projector;

  /// What drives the model.
  final TextToSpeechAdapter adapter;

  /// Creates a model from its main [source], its [projector] and the
  /// [adapter].
  const TextToSpeechModel(this.source, {this.projector, required this.adapter});
}

/// Model-specific knowledge `TextToSpeechEngine` needs to run a
/// text-to-speech model.
///
/// The runtime generates the audio itself and reports which audio-generation
/// model it loaded as a [BackendTextToSpeechModel]; the adapter accepts the
/// models it drives and maps request languages to the codes they take.
/// Implement it, or extend it to keep the defaults, for another family the
/// runtime supports.
abstract class TextToSpeechAdapter {
  /// Creates an adapter.
  const TextToSpeechAdapter();

  /// Model family name used in messages, such as `Qwen3-TTS`.
  String get name;

  /// Language codes the model takes, reported as
  /// `TextToSpeechCapabilities.supportedLanguages`. Defaults to none.
  Set<String> get supportedLanguages => const <String>{};

  /// Whether this adapter drives [model], the audio-generation model the
  /// runtime loaded, or null when the runtime does not name it.
  bool supportsModel(BackendTextToSpeechModel? model);

  /// The language code the model takes for [language], a trimmed nonempty
  /// `TextToSpeechRequest.language`.
  ///
  /// Defaults to [language] in lower case. Throws
  /// [LlamaTextToSpeechException] for a language the model does not take.
  String normalizeLanguage(String language) => language.toLowerCase();
}

/// Qwen3-TTS on llama.cpp, with its audio-generation projector.
///
/// It takes the two-letter codes in [supportedLanguages] and their English
/// names, such as `English` for `en` and `Korean` for `ko`.
class Qwen3TtsAdapter extends TextToSpeechAdapter {
  static const Map<String, String> _languageAliases = <String, String>{
    'chinese': 'zh',
    'english': 'en',
    'french': 'fr',
    'german': 'de',
    'italian': 'it',
    'japanese': 'ja',
    'korean': 'ko',
    'portuguese': 'pt',
    'russian': 'ru',
    'spanish': 'es',
  };
  static const Set<String> _languageCodes = <String>{
    'zh',
    'en',
    'ja',
    'ko',
    'de',
    'fr',
    'ru',
    'pt',
    'es',
    'it',
  };

  /// Creates the Qwen3-TTS adapter.
  const Qwen3TtsAdapter();

  @override
  String get name => 'Qwen3-TTS';

  @override
  Set<String> get supportedLanguages => _languageCodes;

  @override
  bool supportsModel(BackendTextToSpeechModel? model) =>
      model == BackendTextToSpeechModel.qwen3Tts;

  @override
  String normalizeLanguage(String language) {
    final normalized = language.toLowerCase();
    final code = _languageAliases[normalized] ?? normalized;
    if (!_languageCodes.contains(code)) {
      throw LlamaTextToSpeechException(
        'Unsupported Qwen3-TTS language `$language`. Use one of: '
        '${_languageCodes.join(', ')}.',
      );
    }
    return code;
  }
}

/// LFM3-Audio and LFM3-Omni speech output on llama.cpp, with the model's
/// audio projector.
///
/// The model speaks through its `tts` chat template, so load the LFM3 model
/// that matches the projector; one without that template is unsupported.
/// Output is 24 kHz mono PCM.
///
/// - [TextToSpeechRequest.voice] selects `female` (the default) or `male`.
/// - [TextToSpeechRequest.language] is rendered into the template as given,
///   as a code such as `en` or a language name; nothing validates it, so
///   check it against the model card. Without one the template's default,
///   English, applies.
/// - Speaker references are unsupported.
/// - Audio codes are sampled with the model's own GGUF settings:
///   [TextToSpeechRequest.topK], `topP`, `minP` and `temperature` are
///   validated but unused. [TextToSpeechRequest.seed] seeds the generation.
///
/// Needs llamadart-native v0.8.0 or later; earlier runtimes report the
/// projector as unsupported.
class Lfm3AudioTtsAdapter extends TextToSpeechAdapter {
  /// Creates the LFM3-Audio adapter.
  const Lfm3AudioTtsAdapter();

  @override
  String get name => 'LFM3-Audio';

  @override
  bool supportsModel(BackendTextToSpeechModel? model) =>
      model == BackendTextToSpeechModel.lfm3Audio;

  @override
  String normalizeLanguage(String language) => language;
}

/// Soprano on llama.cpp, with its Vocos-decoder projector.
///
/// Soprano takes no language, voice or speaker reference; requests with any
/// of them are unsupported. It samples with the request's settings, whose
/// default temperature is 0.8; upstream's example decodes greedily, so pass
/// `temperature: 0` to match it. Output is 32 kHz mono PCM, decoded on the
/// last generation step. Fewer than two generated frames fail the synthesis.
///
/// No llama.cpp-format Soprano GGUF is published; see the text-to-speech
/// guide for converting one. Needs llamadart-native v0.8.0 or later.
class SopranoTtsAdapter extends TextToSpeechAdapter {
  /// Creates the Soprano adapter.
  const SopranoTtsAdapter();

  @override
  String get name => 'Soprano';

  @override
  bool supportsModel(BackendTextToSpeechModel? model) =>
      model == BackendTextToSpeechModel.soprano;
}

/// Chatterbox Turbo and Chatterbox Multilingual on llama.cpp, with the
/// model's audio projector.
///
/// Both speak with a predefined voice of the projector (the ggml-org
/// conversions list one, `default`) or clone a speaker reference; a voice and
/// a reference together are refused. A speaker clip of about 10 seconds works
/// best: a short one can make the model run on to `maxFrames`. Requests
/// sample with their own settings; the GGUFs store upstream's defaults
/// (Turbo `topK` 1000, `topP` 0.95, `minP` 0; Multilingual `topP` 1, `minP`
/// 0.05; both `temperature` 0.8), which callers may pass to match upstream
/// `llama-tts`.
///
/// - Turbo takes no language; a request with one is unsupported.
/// - Multilingual reports `supportsLanguage`: [TextToSpeechRequest.language]
///   is a code such as `fr`, lower-cased and not validated, so check it
///   against the model card. It decodes a second sequence for
///   classifier-free guidance, so load it with
///   `ModelParams(maxParallelSequences: 2)`; with fewer the projector is
///   reported unsupported.
///
/// Output is 24 kHz mono PCM, decoded on the last generation step. Needs
/// llamadart-native v0.9.0 or later.
class ChatterboxTtsAdapter extends TextToSpeechAdapter {
  /// Creates the Chatterbox adapter.
  const ChatterboxTtsAdapter();

  @override
  String get name => 'Chatterbox';

  @override
  bool supportsModel(BackendTextToSpeechModel? model) =>
      model == BackendTextToSpeechModel.chatterbox;
}

/// Pocket TTS on llama.cpp, with the model's audio projector.
///
/// It speaks with a predefined voice of the projector, the first one when a
/// request names none (the Kyutai English pack lists 25, starting with
/// `alba`), or unconditioned when the projector has none. A speaker
/// reference needs a projector with a voice encoder, which the Kyutai packs
/// lack; `capabilities` reports it. The language is that of the weights, so a
/// request language is unsupported. It samples with the weights' own
/// settings: [TextToSpeechRequest.topK], `topP`, `minP` and `temperature` are
/// validated but unused, and `seed` seeds the flow decoder. Long text is
/// split into chunks that all count towards `maxFrames`. Output is 24 kHz
/// mono PCM. Needs llamadart-native v0.9.0 or later.
class PocketTtsAdapter extends TextToSpeechAdapter {
  /// Creates the Pocket TTS adapter.
  const PocketTtsAdapter();

  @override
  String get name => 'Pocket TTS';

  @override
  bool supportsModel(BackendTextToSpeechModel? model) =>
      model == BackendTextToSpeechModel.pocketTts;
}
