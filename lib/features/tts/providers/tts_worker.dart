import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '../../../core/logger/app_logger.dart';
import '../../../core/models/enums.dart';

sealed class TtsWorkerMessage {}

class TtsInitRequest extends TtsWorkerMessage {
  final EngineId engineId;
  final String modelPath;
  final String voicesPath;
  final String tokensPath;
  final String dataDir;
  final String lexicon;

  TtsInitRequest({
    required this.engineId,
    required this.modelPath,
    required this.voicesPath,
    required this.tokensPath,
    required this.dataDir,
    required this.lexicon,
  });
}

class TtsSynthesizeRequest extends TtsWorkerMessage {
  final String text;
  final String voiceId;
  final double speed;
  final int chunkIndex;
  final int sessionId;

  TtsSynthesizeRequest({
    required this.text,
    required this.voiceId,
    required this.speed,
    required this.chunkIndex,
    required this.sessionId,
  });
}

class TtsStopRequest extends TtsWorkerMessage {}

class TtsWorkerResponse {
  final int? chunkIndex;
  final int? sessionId;
  final Uint8List? wavBytes;
  final String? error;
  final bool isInitResponse;

  TtsWorkerResponse({
    this.chunkIndex,
    this.sessionId,
    this.wavBytes,
    this.error,
    this.isInitResponse = false,
  });
}

void ttsWorkerEntry(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  sherpa_onnx.initBindings();

  sherpa_onnx.OfflineTts? tts;
  EngineId? activeEngineId;
  TtsInitRequest? activeInit;

  receivePort.listen((message) async {
    try {
      if (message is TtsInitRequest) {
        tts?.free();
        tts = null;

        activeEngineId = message.engineId;
        activeInit = message;

        tts = _createTts(message);
        Log.info('Worker initialized engine: ${message.engineId}');
        mainSendPort.send(TtsWorkerResponse(isInitResponse: true));
      } else if (message is TtsSynthesizeRequest) {
        if (activeEngineId == null || tts == null || activeInit == null) {
          mainSendPort.send(
            TtsWorkerResponse(
              chunkIndex: message.chunkIndex,
              sessionId: message.sessionId,
              error: 'No engine initialized in worker',
            ),
          );
          return;
        }

        final speakerId = _resolveSpeakerId(activeEngineId!, message.voiceId);
        final genConfig = sherpa_onnx.OfflineTtsGenerationConfig(
          sid: speakerId,
          speed: message.speed,
          silenceScale: 0.2,
        );

        final audio = tts!.generateWithConfig(
          text: message.text,
          config: genConfig,
        );
        if (audio.samples.isEmpty) {
          mainSendPort.send(
            TtsWorkerResponse(
              chunkIndex: message.chunkIndex,
              sessionId: message.sessionId,
              error: 'Empty PCM generated',
            ),
          );
          return;
        }

        final wavBytes = _createWav(audio.samples, audio.sampleRate);
        mainSendPort.send(
          TtsWorkerResponse(
            chunkIndex: message.chunkIndex,
            sessionId: message.sessionId,
            wavBytes: wavBytes,
          ),
        );
      } else if (message is TtsStopRequest) {
        // No-op: the main isolate handles queue cancellation.
      }
    } catch (e) {
      mainSendPort.send(TtsWorkerResponse(error: e.toString()));
    }
  });
}

sherpa_onnx.OfflineTts _createTts(TtsInitRequest message) {
  final vits = message.engineId == EngineId.piper
      ? sherpa_onnx.OfflineTtsVitsModelConfig(
          model: message.modelPath,
          tokens: message.tokensPath,
          dataDir: message.dataDir,
          lexicon: message.lexicon,
        )
      : sherpa_onnx.OfflineTtsVitsModelConfig();

  final kitten = message.engineId == EngineId.kitten
      ? sherpa_onnx.OfflineTtsKittenModelConfig(
          model: message.modelPath,
          voices: message.voicesPath,
          tokens: message.tokensPath,
          dataDir: message.dataDir,
        )
      : sherpa_onnx.OfflineTtsKittenModelConfig();

  final modelConfig = sherpa_onnx.OfflineTtsModelConfig(
    vits: vits,
    kitten: kitten,
    numThreads: 2,
    debug: true,
    provider: 'cpu',
  );

  final config = sherpa_onnx.OfflineTtsConfig(
    model: modelConfig,
    maxNumSenetences: 1,
  );

  return sherpa_onnx.OfflineTts(config);
}

int _resolveSpeakerId(EngineId engine, String voiceId) {
  if (engine == EngineId.piper) {
    return 0;
  }
  final voices = voicesForEngine(engine);
  final index = voices.indexWhere((voice) => voice.id == voiceId);
  return index < 0 ? 0 : index;
}

Uint8List _createWav(Float32List samples, int sampleRate) {
  final int byteCount = samples.length * 2;
  final int totalSize = 36 + byteCount;
  final Uint8List wav = Uint8List(44 + byteCount);
  final ByteData data = ByteData.view(wav.buffer);

  data.setUint8(0, 0x52);
  data.setUint8(1, 0x49);
  data.setUint8(2, 0x46);
  data.setUint8(3, 0x46);
  data.setUint32(4, totalSize, Endian.little);
  data.setUint8(8, 0x57);
  data.setUint8(9, 0x41);
  data.setUint8(10, 0x56);
  data.setUint8(11, 0x45);
  data.setUint8(12, 0x66);
  data.setUint8(13, 0x6d);
  data.setUint8(14, 0x74);
  data.setUint8(15, 0x20);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  data.setUint8(36, 0x64);
  data.setUint8(37, 0x61);
  data.setUint8(38, 0x74);
  data.setUint8(39, 0x61);
  data.setUint32(40, byteCount, Endian.little);

  for (var i = 0; i < samples.length; i++) {
    final int sample = (samples[i] * 32767).clamp(-32768, 32767).toInt();
    data.setInt16(44 + (i * 2), sample, Endian.little);
  }

  return wav;
}
