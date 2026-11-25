import '../../backends/litert_lm/litert_lm_asr_types.dart';
import '../models/model_source.dart';
import 'qwen_windowed_asr.dart';
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
    final prompt = StringBuffer(qwen3AsrDefaultInstruction);
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

/// Opt-in windowed live PCM speech recognition for Qwen3-ASR on native
/// `llama.cpp`.
///
/// Re-transcribes short 2, 4, and 6 second prefixes inside a bounded 8 second
/// (128,000-sample) ring buffer through the Qwen3-ASR prompt path. A full
/// buffer commits at a quiet boundary (latest contiguous >= 100 ms run with
/// RMS <= 0.01 in the final 2 seconds) or hard-cuts at 8 seconds.
/// The first window commits after 8 s of audio plus inference. Subsequent full
/// windows need 6.05–8 s of new audio plus inference. Finishing flushes any
/// remaining audio. Quiet intervals with a nonempty decode may take a second
/// inference pass on amplified audio to suppress false text. An isolated
/// transient has limited influence on quiet classification. Later decodes of
/// a rejected quiet window are checked again before publication. When the
/// entire window transcript matches the default instruction or a known
/// Portuguese variant, changing voiced speech preserves the original wording.
/// Otherwise an audio-only decode of the original audio must corroborate it
/// within one word edit. The extra decode can delay a partial or the final
/// flush. Quiet or misrecognized dictation can be dropped, including whispered
/// (even at normal levels), sung, robotic, or very low-pitched (below about
/// 100 Hz) dictation of the exact instruction. If no final text survives, the
/// session completes with an empty-transcript error. Other echoes can still
/// appear.
///
/// Requires `SpeechToTextEngine.load` on a native platform with a loaded
/// Qwen3-ASR model and verified `qwen3a` audio [SpeechToTextModel.projector].
/// It accepts mono 16 kHz finite normalized float32 PCM (`pcm-f32le`) via
/// `SpeechToTextEngine.startStream` and `SpeechToTextEngine.transcribe` /
/// `transcribeOnce`, and rejects `SpeechToTextEngine.attach`, Web, file or
/// encoded-byte inputs, language hints, and context prompts.
final class Qwen3WindowedAsrAdapter extends Qwen3AsrAdapter {
  /// Creates the opt-in windowed Qwen3-ASR adapter.
  const Qwen3WindowedAsrAdapter();

  @override
  bool get supportsContextPrompt => false;
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

/// Native llama.cpp live PCM speech recognition for streaming ASR models such
/// as Voxtral Realtime and LFM3-Audio.
///
/// Requires a native platform, a GGUF model and its matching multimodal audio
/// [SpeechToTextModel.projector], and `SpeechToTextEngine.load` (with no
/// [SpeechToTextModel.tokenizer]). It accepts mono 16 kHz finite normalized
/// float32 PCM (`pcm-f32le`) via `SpeechToTextEngine.startStream` and
/// `SpeechToTextEngine.transcribe` / `transcribeOnce`, and rejects file or
/// encoded-byte inputs, language hints, and context prompts.
///
/// Prompted-chunk models (such as LFM3-Audio) require an actual per-sequence
/// context capacity of at least 2,048 tokens; token-delay models (such as
/// Voxtral Realtime) run within a finite context window and 4,096 tokens is
/// recommended for roughly five minutes of audio.
final class LlamaCppLiveAsrAdapter extends SpeechToTextAdapter {
  /// Creates a llama.cpp live ASR adapter.
  const LlamaCppLiveAsrAdapter();

  @override
  String get name => 'llama.cpp live ASR';
}
