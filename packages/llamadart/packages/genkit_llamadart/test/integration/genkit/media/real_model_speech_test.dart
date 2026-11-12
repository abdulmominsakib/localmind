@Tags(['real-model', 'speech-model'])
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

Future<String?> _fixture(String key, String hash) async {
  final path = Platform.environment[key];
  if (path == null) {
    markTestSkipped('Set $key for pinned speech qualification.');
    return null;
  }
  expect((await sha256.bind(File(path).openRead()).first).toString(), hash);
  return path;
}

void main() {
  test(
    'real Qwen3-ASR transcribes the pinned JFK recording through Genkit',
    () async {
      final path = await _fixture(
        'GENKIT_ASR_MODEL',
        'bca259818b50ca7c4c05e9bdb35a5dc04fa039653a6d6f3f0f331f96f6aa1971',
      );
      if (path == null) return;
      final projector = await _fixture(
        'GENKIT_ASR_PROJECTOR',
        '41a342b5e4c514e968cb756de6cd1b7be39eff43c44c57a2ef5fc6522e36603d',
      );
      if (projector == null) return;
      final engine = await llama.SpeechToTextEngine.load(
        llama.SpeechToTextModel(
          llama.ModelSource.path(path),
          projector: llama.ModelSource.path(projector),
          adapter: const llama.Qwen3AsrAdapter(),
        ),
        params: const llama.ModelParams(
          contextSize: 4096,
          device: llama.ComputeDevice.cpu,
        ),
      );
      final plugin = LlamaDartMediaPlugin(
        models: [
          LlamaDartSpeechToTextModel(
            name: 'asr',
            engine: engine,
            ownsEngine: true,
          ),
        ],
      );
      final ai = Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(() async {
        await plugin.dispose();
        await ai.shutdown();
      });
      final audio = File('test/integration/genkit/media/fixtures/jfk.wav');
      expect(
        (await sha256.bind(audio.openRead()).first).toString(),
        '59dfb9a4acb36fe2a2affc14bacbee2920ff435cb13cc314a08c13f66ba7860e',
      );
      final response = await ai.generate(
        model: LlamaDartMediaPlugin.modelRef('asr'),
        messages: [
          Message(
            role: Role.user,
            content: [
              MediaPart(
                media: Media(
                  url: audio.absolute.path,
                  contentType: 'audio/wav',
                ),
              ),
            ],
          ),
        ],
        config: {'maxOutputTokens': 256},
      );
      expect(
        response.finishReason,
        FinishReason.stop,
        reason: '${response.error}',
      );
      expect(
        response.text
            .toLowerCase()
            .replaceAll(RegExp('[^a-z ]'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim(),
        'and so my fellow americans ask not what your country can do for you ask what you can do for your country',
      );
      expect(response.text, isNot(contains('<asr_text>')));
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    'real Qwen3-TTS produces a complete finite PCM WAV through Genkit',
    () async {
      final path = await _fixture(
        'GENKIT_TTS_MODEL',
        '8d18c94acb2addd042f97da63c98be144eafa76d0d9495177eab65130cf85129',
      );
      if (path == null) return;
      final projector = await _fixture(
        'GENKIT_TTS_PROJECTOR',
        '6fd65188839bcd6ecc91b277ad471e22a0edfada4699a0fe82f1165c18cfcce2',
      );
      if (projector == null) return;
      final engine = await llama.TextToSpeechEngine.load(
        llama.TextToSpeechModel(
          llama.ModelSource.path(path),
          projector: llama.ModelSource.path(projector),
          adapter: const llama.Qwen3TtsAdapter(),
        ),
        params: const llama.ModelParams(
          contextSize: 4096,
          device: llama.ComputeDevice.cpu,
        ),
      );
      final plugin = LlamaDartMediaPlugin(
        models: [
          LlamaDartTextToSpeechModel(
            name: 'tts',
            engine: engine,
            ownsEngine: true,
          ),
        ],
      );
      final ai = Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(() async {
        await plugin.dispose();
        await ai.shutdown();
      });
      final response = await ai.generate(
        model: LlamaDartMediaPlugin.modelRef('tts'),
        prompt: 'Hello from Genkit.',
        config: {'language': 'en', 'maxFrames': 384, 'seed': 1},
      );
      expect(
        response.finishReason,
        FinishReason.stop,
        reason: '${response.error}',
      );
      final media = response.media!;
      expect(media.contentType, 'audio/wav');
      final bytes = UriData.parse(media.url).contentAsBytes();
      expect(bytes.length, greaterThan(44));
      final header = ByteData.sublistView(Uint8List.fromList(bytes));
      expect(header.getUint32(24, Endian.little), 24000);
      expect(header.getUint16(22, Endian.little), 1);
      expect(header.getUint32(40, Endian.little), bytes.length - 44);
      expect(bytes.skip(44).any((byte) => byte != 0), isTrue);
      final output = Platform.environment['GENKIT_TTS_WAV_OUTPUT'];
      if (output != null) {
        await File(output).writeAsBytes(bytes);
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
