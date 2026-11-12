import '../../backends/litert_lm/litert_lm_asr_types.dart';
import '../models/model_source.dart';
import 'speech_to_text.dart';

/// A speech-recognition model: its files and the adapter that drives it.
///
/// Each file is a `ModelSource` (local path, HTTP(S) URL or Hugging Face
/// file) that `SpeechToTextEngine.load` downloads if needed. The [adapter]
/// decides the runtime and which files the model needs:
///
/// - A [SpeechToTextPromptAdapter], such as [Qwen3AsrAdapter], runs [source]
///   on a `LlamaEngine`. llama.cpp also needs the audio [projector].
/// - A [LiteRtLmAsrAdapter] runs [source] (a `.tflite` model) on the
///   dedicated LiteRT-LM ASR runtime, with its [tokenizer].
///
/// ```dart
/// final model = SpeechToTextModel(
///   ModelSource.parse('hf://owner/repo/asr-model.gguf'),
///   projector: ModelSource.parse('hf://owner/repo/mmproj-asr-model.gguf'),
///   adapter: const Qwen3AsrAdapter(),
/// );
/// ```
///
/// Building a model does no network or file access.
class SpeechToTextModel {
  /// The main model file.
  final ModelSource source;

  /// The multimodal projector that encodes audio for a
  /// [SpeechToTextPromptAdapter] model on llama.cpp, or null.
  final ModelSource? projector;

  /// The tokenizer JSON of a [LiteRtLmAsrAdapter] model, or null.
  final ModelSource? tokenizer;

  /// What drives the model.
  final SpeechToTextAdapter adapter;

  /// Creates a model from its main [source], the files [adapter] needs, and
  /// the [adapter].
  const SpeechToTextModel(
    this.source, {
    this.projector,
    this.tokenizer,
    required this.adapter,
  });
}

/// Model-specific knowledge `SpeechToTextEngine` needs to run a
/// speech-recognition model.
///
/// To support another model family that runs on `LlamaEngine`, extend or
/// implement [SpeechToTextPromptAdapter]. [LiteRtLmAsrAdapter] selects the
/// dedicated LiteRT-LM ASR runtime.
sealed class SpeechToTextAdapter {
  /// Creates an adapter.
  const SpeechToTextAdapter();

  /// Model family name used in messages, such as `Qwen3-ASR`.
  String get name;
}

/// Transcript text and language that a [SpeechToTextPromptAdapter] parsed
/// from a model's output.
class SpeechToTextTranscript {
  /// Transcript text, without model markup.
  final String text;

  /// Language the model reported, or null.
  final String? language;

  /// Creates a parsed transcript.
  const SpeechToTextTranscript(this.text, {this.language});
}

/// Recognizes speech with a multimodal chat model on `LlamaEngine`, by
/// sending the audio with an instruction and parsing the generated text.
///
/// `SpeechToTextEngine` sends one user turn: the text from [promptFor]
/// followed by the audio. Natively the turn goes through the model's chat
/// template with thinking disabled; on the web the bridge takes the text as
/// the raw prompt with the audio bytes. Generation is greedy and stops at
/// `SpeechToTextRequest.maxOutputTokens`.
///
/// Implement it, or extend it to keep the defaults, to add a model family:
///
/// ```dart
/// class MyAsrAdapter extends SpeechToTextPromptAdapter {
///   const MyAsrAdapter();
///
///   @override
///   String get name => 'My-ASR';
///
///   @override
///   String promptFor(SpeechToTextRequest request) => 'Transcribe the audio.';
///
///   @override
///   SpeechToTextTranscript parseTranscript(String output) =>
///       SpeechToTextTranscript(output.trim());
/// }
/// ```
abstract class SpeechToTextPromptAdapter extends SpeechToTextAdapter {
  /// Creates a prompt adapter.
  const SpeechToTextPromptAdapter();

  /// Whether requests may set `SpeechToTextRequest.languageHint`, which
  /// [promptFor] then passes to the model. Defaults to false, and the engine
  /// rejects a hint.
  bool get supportsLanguageHints => false;

  /// Whether requests may set `SpeechToTextRequest.contextPrompt`. Defaults
  /// to true.
  bool get supportsContextPrompt => true;

  /// Whether [parseTranscript] reports the recognized language. Defaults to
  /// false.
  bool get supportsLanguageDetection => false;

  /// The instruction sent before the audio for [request].
  String promptFor(SpeechToTextRequest request);

  /// The transcript in the model's complete [output].
  ///
  /// An empty [SpeechToTextTranscript.text] fails the task.
  SpeechToTextTranscript parseTranscript(String output);
}

/// Qwen3-ASR on llama.cpp, with its audio projector.
///
/// It asks for an accurate transcription, adds
/// `SpeechToTextRequest.contextPrompt` as context, and strips the
/// `language ...<asr_text>` prefix the model emits. It takes no language
/// hints.
class Qwen3AsrAdapter extends SpeechToTextPromptAdapter {
  static final RegExp _languagePrefix = RegExp(
    r'^\s*language\s+([^<\r\n]+?)\s*<asr_text>\s*',
    caseSensitive: false,
  );
  static final RegExp _textMarker = RegExp(
    r'^\s*<asr_text>\s*',
    caseSensitive: false,
  );

  /// Creates the Qwen3-ASR adapter.
  const Qwen3AsrAdapter();

  @override
  String get name => 'Qwen3-ASR';

  @override
  String promptFor(SpeechToTextRequest request) {
    final prompt = StringBuffer('Transcribe this audio accurately.');
    final contextPrompt = request.contextPrompt?.trim();
    if (contextPrompt != null && contextPrompt.isNotEmpty) {
      prompt.write(' Context: $contextPrompt');
    }
    return prompt.toString();
  }

  @override
  SpeechToTextTranscript parseTranscript(String output) {
    final prefix =
        _languagePrefix.firstMatch(output) ?? _textMarker.firstMatch(output);
    return SpeechToTextTranscript(
      prefix == null ? output.trim() : output.substring(prefix.end).trim(),
    );
  }
}

/// Dedicated LiteRT-LM ASR: a `.tflite` speech model and its tokenizer run
/// natively in a worker isolate, with incremental PCM input and partial
/// transcripts.
///
/// The model family comes from [preset], whose metadata the native runtime
/// versions. It accepts mono 16 kHz float PCM, runs on the CPU, and needs a
/// native platform.
class LiteRtLmAsrAdapter extends SpeechToTextAdapter {
  /// The model family's runtime metadata.
  final LiteRtLmAsrModelPreset preset;

  /// Native CPU worker count. Must fit a positive signed 32-bit integer.
  final int numberOfThreads;

  /// Maximum queued audio before native push backpressure is reported. Must
  /// fit a signed 32-bit millisecond value and be at least one inference
  /// window of [preset].
  final Duration maxBufferedAudio;

  /// Fraction of each inference window kept to reconcile the transcript.
  final double overlapRatio;

  /// Path of the LiteRT-LM runtime library, an advanced local-validation
  /// override. Packaged apps leave it null and use the runtime that native
  /// assets resolve.
  final String? libraryPath;

  /// Creates the adapter for a [preset] model family.
  const LiteRtLmAsrAdapter(
    this.preset, {
    this.numberOfThreads = 4,
    this.maxBufferedAudio = const Duration(seconds: 30),
    this.overlapRatio = 0.4,
    this.libraryPath,
  });

  @override
  String get name => 'LiteRT-LM ASR';
}
