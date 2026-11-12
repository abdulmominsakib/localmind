@TestOn('vm')
@Tags(<String>['local-only', 'e2e'])
@Timeout(Duration(minutes: 60))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

const _asrModelKey = 'LLAMADART_STT_MODEL_PATH';
const _asrMmprojKey = 'LLAMADART_STT_MMPROJ_PATH';
const _speakerKey = 'LLAMADART_TTS_SPEAKER_REFERENCE_PATH';
const _outputDirectoryKey = 'LLAMADART_TTS_OUTPUT_DIR';
const _gpuKey = 'LLAMADART_TTS_GPU';
const _text = 'Good morning. The weather is sunny and warm today.';

ModelParams _params({int sequences = 1}) => ModelParams(
  contextSize: 4096,
  numberOfThreads: 2,
  numberOfThreadsBatch: 2,
  maxParallelSequences: sequences,
  preferredBackend: Platform.environment[_gpuKey] == '1'
      ? GpuBackend.auto
      : GpuBackend.cpu,
  gpuLayers: Platform.environment[_gpuKey] == '1'
      ? ModelParams.maxGpuLayers
      : 0,
);

class _Spec {
  final String name;
  final String key;
  final TextToSpeechAdapter adapter;
  final int sampleRateHz;

  /// The leading listed voices, and how many there are when more.
  final List<String> voices;
  final int? listedVoices;

  /// Whether a request without a voice speaks the first listed voice.
  final bool defaultIsFirstVoice;
  final bool supportsLanguage;
  final bool supportsSpeakerReference;
  final int sequences;

  /// Text in another language and its code, spoken and transcribed back.
  final (String, String)? otherLanguage;
  final double temperature;

  const _Spec({
    required this.name,
    required this.key,
    required this.adapter,
    required this.sampleRateHz,
    this.voices = const <String>[],
    this.listedVoices,
    this.defaultIsFirstVoice = false,
    this.supportsLanguage = false,
    this.supportsSpeakerReference = false,
    this.sequences = 1,
    this.otherLanguage,
    this.temperature = 0.8,
  });

  int get voiceCount => listedVoices ?? voices.length;

  String get modelKey => 'LLAMADART_TTS_${key}_MODEL_PATH';
  String get mmprojKey => 'LLAMADART_TTS_${key}_MMPROJ_PATH';
}

const _specs = <_Spec>[
  _Spec(
    name: 'LFM3-Audio',
    key: 'LFM3',
    adapter: Lfm3AudioTtsAdapter(),
    sampleRateHz: 24000,
    voices: ['female', 'male'],
    supportsLanguage: true,
  ),
  _Spec(
    name: 'Soprano',
    key: 'SOPRANO',
    adapter: SopranoTtsAdapter(),
    sampleRateHz: 32000,
    temperature: 0,
  ),
  _Spec(
    name: 'Chatterbox Turbo',
    key: 'CHATTERBOX_TURBO',
    adapter: ChatterboxTtsAdapter(),
    sampleRateHz: 24000,
    voices: ['default'],
    defaultIsFirstVoice: true,
    supportsSpeakerReference: true,
  ),
  _Spec(
    name: 'Chatterbox Multilingual',
    key: 'CHATTERBOX_MULTILINGUAL',
    adapter: ChatterboxTtsAdapter(),
    sampleRateHz: 24000,
    voices: ['default'],
    defaultIsFirstVoice: true,
    supportsLanguage: true,
    supportsSpeakerReference: true,
    sequences: 2,
    otherLanguage: ('Bonjour, comment allez-vous aujourd\'hui?', 'fr'),
  ),
  _Spec(
    name: 'Pocket TTS',
    key: 'POCKET',
    adapter: PocketTtsAdapter(),
    sampleRateHz: 24000,
    voices: ['alba', 'anna', 'azelma'],
    listedVoices: 25,
    defaultIsFirstVoice: true,
  ),
];

void main() {
  SpeechToTextEngine? recognizer;

  setUpAll(() async {
    final model = _file(_asrModelKey);
    final projector = _file(_asrMmprojKey);
    if (model == null || projector == null) return;
    recognizer = await SpeechToTextEngine.load(
      SpeechToTextModel(
        ModelSource.path(model),
        projector: ModelSource.path(projector),
        adapter: const Qwen3AsrAdapter(),
      ),
      params: _params(),
    );
  });

  tearDownAll(() async => recognizer?.dispose());

  for (final spec in _specs) {
    group(spec.name, () {
      TextToSpeechEngine? synthesizer;

      TextToSpeechModel? model() {
        final model = _file(spec.modelKey);
        final projector = _file(spec.mmprojKey);
        if (model == null || projector == null) return null;
        return TextToSpeechModel(
          ModelSource.path(model),
          projector: ModelSource.path(projector),
          adapter: spec.adapter,
        );
      }

      setUpAll(() async {
        final files = model();
        if (files == null) return;
        synthesizer = await TextToSpeechEngine.load(
          files,
          params: _params(sequences: spec.sequences),
        );
      });

      tearDownAll(() async => synthesizer?.dispose());

      TextToSpeechEngine? engine() {
        final value = synthesizer;
        if (value == null) {
          markTestSkipped(
            'Set ${spec.modelKey} and ${spec.mmprojKey} to run the '
            '${spec.name} E2E.',
          );
        }
        return value;
      }

      TextToSpeechRequest request({
        String text = _text,
        String? voice,
        String? language,
        SpeechAudioInput? speakerReference,
        int seed = 1,
      }) => TextToSpeechRequest(
        text: text,
        voice: voice,
        language: language,
        speakerReference: speakerReference,
        maxFrames: 1024,
        temperature: spec.temperature,
        seed: seed,
      );

      test('reports the model capabilities', () async {
        final tts = engine();
        if (tts == null) return;
        final capabilities = await tts.capabilities;
        expect(
          capabilities.isSupported,
          isTrue,
          reason: capabilities.unsupportedReason,
        );
        expect(capabilities.sampleRateHz, spec.sampleRateHz);
        expect(capabilities.channelCount, 1);
        expect(capabilities.supportsVoice, spec.voices.isNotEmpty);
        expect(capabilities.voices, hasLength(spec.voiceCount));
        expect(capabilities.voices.take(spec.voices.length), spec.voices);
        expect(capabilities.supportsLanguage, spec.supportsLanguage);
        expect(
          capabilities.supportsSpeakerReference,
          spec.supportsSpeakerReference,
        );
      });

      test('speech transcribes back to the text', () async {
        final tts = engine();
        if (tts == null) return;
        final result = await tts.synthesizeOnce(request());
        expect(result.sampleRateHz, spec.sampleRateHz);
        expect(result.truncated, isFalse);
        await _expectTranscript(
          recognizer,
          result,
          _text,
          '${spec.key}-default',
        );
      });

      test('a request without a voice speaks the first listed voice', () async {
        final tts = engine();
        if (tts == null) return;
        if (!spec.defaultIsFirstVoice) {
          markTestSkipped('${spec.name} has no default voice to compare.');
          return;
        }
        final unnamed = await tts.synthesizeOnce(request());
        final named = await tts.synthesizeOnce(
          request(voice: spec.voices.first.toUpperCase()),
        );
        expect(named.samples, orderedEquals(unnamed.samples));
      });

      test(
        'another listed voice speaks the text and changes the audio',
        () async {
          final tts = engine();
          if (tts == null) return;
          final voices = (await tts.capabilities).voices;
          if (voices.length < 2) {
            markTestSkipped('${spec.name} lists fewer than two voices.');
            return;
          }
          final first = await tts.synthesizeOnce(request(voice: voices.first));
          final last = await tts.synthesizeOnce(
            request(voice: voices.last.toUpperCase()),
          );
          expect(last.samples, isNot(orderedEquals(first.samples)));
          await _expectTranscript(
            recognizer,
            last,
            _text,
            '${spec.key}-${voices.last}',
          );
        },
      );

      test('a speaker reference changes the voice', () async {
        final tts = engine();
        if (tts == null) return;
        final reference = _file(_speakerKey);
        if (!spec.supportsSpeakerReference || reference == null) {
          markTestSkipped(
            spec.supportsSpeakerReference
                ? 'Set $_speakerKey to a speech clip of about 10 seconds.'
                : '${spec.name} takes no speaker reference.',
          );
          return;
        }
        final plain = await tts.synthesizeOnce(request());
        final cloned = await tts.synthesizeOnce(
          request(speakerReference: SpeechAudioFileInput(reference)),
        );
        expect(cloned.samples, isNot(orderedEquals(plain.samples)));
        await _expectTranscript(
          recognizer,
          cloned,
          _text,
          '${spec.key}-cloned',
        );
      });

      test('speaks another language', () async {
        final tts = engine();
        if (tts == null) return;
        final other = spec.otherLanguage;
        if (other == null) {
          markTestSkipped('${spec.name} has no other-language check.');
          return;
        }
        final (text, code) = other;
        final result = await tts.synthesizeOnce(
          request(text: text, language: code),
        );
        await _expectTranscript(recognizer, result, text, '${spec.key}-$code');
      });

      test('rejects what the model does not take before synthesis', () async {
        final tts = engine();
        if (tts == null) return;
        if (spec.voices.isEmpty) {
          await expectLater(
            tts.synthesize(request(voice: 'female')),
            throwsA(isA<LlamaUnsupportedException>()),
          );
        } else {
          await expectLater(
            tts.synthesize(request(voice: 'no-such-voice')),
            throwsA(isA<LlamaTextToSpeechException>()),
          );
        }
        if (!spec.supportsLanguage) {
          await expectLater(
            tts.synthesize(request(language: 'en')),
            throwsA(isA<LlamaUnsupportedException>()),
          );
        }
        final reference = SpeechAudioBytesInput(
          Uint8List.fromList(const [1, 2, 3]),
        );
        if (!spec.supportsSpeakerReference) {
          await expectLater(
            tts.synthesize(request(speakerReference: reference)),
            throwsA(isA<LlamaUnsupportedException>()),
          );
        }
        if (spec.voices.isNotEmpty) {
          await expectLater(
            tts.synthesize(
              request(voice: spec.voices.first, speakerReference: reference),
            ),
            throwsA(isA<LlamaTextToSpeechException>()),
          );
        }
      });

      test('a fixed seed repeats after a cancelled task', () async {
        final tts = engine();
        if (tts == null) return;
        final first = await tts.synthesizeOnce(request());
        final cancelled = await tts.synthesize(request());
        await cancelled.events.firstWhere(
          (event) => event is TextToSpeechProgressEvent,
        );
        cancelled.cancel();
        expect(
          (await cancelled.done).state,
          TextToSpeechCompletionState.cancelled,
        );
        final repeated = await tts.synthesizeOnce(request());
        expect(repeated.framesGenerated, first.framesGenerated);
        expect(repeated.samples, orderedEquals(first.samples));
      });

      test('refuses a context without its guidance sequence', () async {
        if (spec.sequences < 2) {
          markTestSkipped('${spec.name} needs one sequence.');
          return;
        }
        final files = model();
        if (files == null || engine() == null) return;
        await expectLater(
          TextToSpeechEngine.load(files, params: _params()),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              contains('maxParallelSequences of at least 2'),
            ),
          ),
        );
      });
    });
  }
}

Future<void> _expectTranscript(
  SpeechToTextEngine? recognizer,
  TextToSpeechResult result,
  String text,
  String name,
) async {
  final wav = result.toWavBytes();
  final directory = Platform.environment[_outputDirectoryKey];
  if (directory != null && directory.isNotEmpty) {
    File('$directory/$name.wav')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(wav, flush: true);
  }
  if (recognizer == null) {
    markTestSkipped(
      'Set $_asrModelKey and $_asrMmprojKey to check the speech content.',
    );
    return;
  }
  final transcript = (await recognizer.transcribeOnce(
    SpeechToTextRequest(
      audio: SpeechAudioBytesInput(
        wav,
        format: const SpeechAudioFormat(encoding: 'wav'),
      ),
    ),
  )).text;
  print('TRANSCRIPT $name: $transcript');
  expect(
    _wordErrorRate(text, transcript),
    lessThanOrEqualTo(0.25),
    reason: 'transcript: $transcript',
  );
}

double _wordErrorRate(String reference, String hypothesis) {
  List<String> words(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9' ]"), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  final expected = words(reference);
  final actual = words(hypothesis);
  var previous = List<int>.generate(actual.length + 1, (index) => index);
  for (var i = 1; i <= expected.length; i++) {
    final current = List<int>.filled(actual.length + 1, 0)..[0] = i;
    for (var j = 1; j <= actual.length; j++) {
      final substitution =
          previous[j - 1] + (expected[i - 1] == actual[j - 1] ? 0 : 1);
      current[j] = [
        previous[j] + 1,
        current[j - 1] + 1,
        substitution,
      ].reduce((a, b) => a < b ? a : b);
    }
    previous = current;
  }
  return previous[actual.length] / expected.length;
}

String? _file(String key) {
  final value = Platform.environment[key];
  if (value == null || value.isEmpty) return null;
  if (!File(value).existsSync()) {
    throw StateError('$key does not exist.');
  }
  return value;
}
